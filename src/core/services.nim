# Copyright 2021 Mattia Giambirtone & All Contributors
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
import strformat
import strutils
import cpuinfo
import tables
import osproc
import posix
import shlex
import os


proc strsignal(sig: cint): cstring {.header: "string.h", importc.}


import ../util/logging


type
    RunLevel* = enum
        ## Enum of possible runlevels
        Boot, Default, Shutdown
    ServiceKind* = enum
        ## Enumerates all service
        ## types
        Oneshot, Simple
    RestartKind* = enum
        ## Enum of possible restart modes
        Always, OnFailure, Never
    Service* = ref object of RootObj
        ## A service object
        name: string
        description: string
        kind: ServiceKind
        workDir: string
        runlevel: RunLevel
        exec: string
        supervised: bool
        restart: RestartKind
        restartDelay: int


proc newService*(name, description: string, kind: ServiceKind, workDir: string, runlevel: RunLevel, exec: string, supervised: bool, restart: RestartKind, restartDelay: int): Service =
    ## Creates a new service object
    result = Service(name: name, description: description, kind: kind, workDir: workDir, runLevel: runLevel,
                     exec: exec, supervised: supervised, restart: restart, restartDelay: restartDelay)


var services: seq[Service] = @[]
var processIDs: TableRef[int, Service] = newTable[int, Service]()


proc isManagedProcess*(pid: int): bool = 
    ## Returns true if the given process 
    ## id is associated to a supervised
    ## NimD service
    result = pid in processIDs


proc getManagedProcess*(pid: int): Service =
    ## Returns a managed process by its PID.
    ## Returns nil if the given pid doesn't
    ## belong to a managed process
    
    result = if pid.isManagedProcess(): processIDs[pid] else: nil


proc removeManagedProcess*(pid: int) =
    ## Removes a managed process entry
    ## from the table
    if pid.isManagedProcess():
        processIDs.del(pid)


proc addManagedProcess*(pid: int, service: Service) =
    ## Adds a managed process to the
    ## table
    processIDs[pid] = service


proc addService*(service: Service) =
    ## Adds a service to be started when
    ## its runlevel is processed
    services.add(service)


proc removeService*(service: Service) =
    ## Unregisters a service from being
    ## started (has no effect after services
    ## have already been started)
    for i, serv in services:
        if serv == service:
            services.del(i)
            break


proc supervisorWorker(logger: Logger, service: Service, pid: int) =
    ## This is the actual worker that supervises the service process
    logger.trace(&"New supervisor for service '{service.name}' has been spawned")
    var pid = pid
    var status: cint
    var returnCode: int
    var sig: int
    var process: Process
    logger.debug("Switching logs to file")
    logger.switchToFile()
    while true:
        logger.trace(&"Calling waitpid() on {pid}")
        returnCode = posix.waitPid(cint(pid), status, WUNTRACED)
        if WIFEXITED(status):
            sig = 0
        elif WIFSIGNALED(status):
            sig = WTERMSIG(status)
        else:
            sig = -1
        logger.trace(&"Call to waitpid() set status to {status} and returned {returnCode}, setting sig to {sig}")
        case service.restart:
            of Never:
                logger.info(&"Service '{service.name}' ({returnCode}) has exited, shutting down controlling process")
                break
            of Always:
                if sig > 0:
                    logger.info(&"Service '{service.name}' ({returnCode}) has crashed (terminated by signal {sig}: {strsignal(cint(sig))}), sleeping {service.restartDelay} seconds before restarting it")
                elif sig == 0:
                    logger.info(&"Service '{service.name}' has exited gracefully, sleeping {service.restartDelay} seconds before restarting it")
                else:
                    logger.info(&"Service '{service.name}' has exited, sleeping {service.restartDelay} seconds before restarting it")
                removeManagedProcess(pid)
                sleep(service.restartDelay * 1000)
                var split = shlex(service.exec)
                if split.error:
                    logger.error(&"Error while restarting service '{service.name}': invalid exec syntax")
                    break
                var arguments = split.words
                let progName = arguments[0]
                arguments = arguments[1..^1]
                process = startProcess(progName, workingDir=service.workDir, args=arguments)
                pid = process.processID()
            of OnFailure:
                if sig > 0:
                    logger.info(&"Service '{service.name}' ({returnCode}) has crashed (terminated by signal {sig}: {strsignal(cint(sig))}), sleeping {service.restartDelay} seconds before restarting it")
                removeManagedProcess(pid)
                sleep(service.restartDelay * 1000)
                var split = shlex(service.exec)
                if split.error:
                    logger.error(&"Error while restarting service '{service.name}': invalid exec syntax")
                    break
                var arguments = split.words
                let progName = arguments[0]
                arguments = arguments[1..^1]
                process = startProcess(progName, workingDir=service.workDir, args=arguments)
                pid = process.processID()
    if process != nil:
        process.close()


proc startService(logger: Logger, service: Service) =
    ## Starts a single service (this is called by
    ## startServices below until all services have
    ## been started). This function is supposed to 
    ## be called from a forked process and it itself
    ## forks to call supervisorWorker if the service
    ## is a supervised one
    var process: Process
    try:
        var split = shlex(service.exec)
        if split.error:
            logger.error(&"Error while starting service '{service.name}': invalid exec syntax")
            quit(0)
        var arguments = split.words
        let progName = arguments[0]
        arguments = arguments[1..^1]
        process = startProcess(progName, workingDir=service.workDir, args=arguments)
        if service.supervised:
            var pid = posix.fork()
            if pid == 0:
                logger.trace(&"New child has been spawned")
                supervisorWorker(logger, service, process.processID)
        # If the service is unsupervised we just exit
    except:
        logger.error(&"Error while starting service {service.name}: {getCurrentExceptionMsg()}")
    if process != nil:
        process.close()
    quit(0)


proc startServices*(logger: Logger, level: RunLevel, workers: int = 1) =
    ## Starts the registered services in the 
    ## given runlevel
    if workers > cpuinfo.countProcessors():
        logger.warning(&"The configured number of workers ({workers}) is greater than the number of CPU cores ({cpuinfo.countProcessors()}), performance may degrade")
    var workerCount: int = 0
    var status: cint
    var pid: int = posix.fork()
    if pid == -1:
        logger.error(&"Error, cannot fork: {posix.strerror(posix.errno)}")
    elif pid == 0:
        logger.debug("Started service spawner process")
        var servicesCopy: seq[Service] = @[]
        for service in services:
            if service.runlevel == level:
                servicesCopy.add(service)
        while servicesCopy.len() > 0:
            if workerCount == workers:
                logger.debug(&"Worker queue full, waiting for some worker to exit...")
                logger.trace(&"Calling waitpid() on {pid}")
                var returnCode = waitPid(cint(pid), status, WUNTRACED)
                logger.trace(&"Call to waitpid() set status to {status} and returned {returnCode}")
                dec(workerCount)
            pid = posix.fork()
            if pid == -1:
                logger.error(&"An error occurred while forking to spawn services, trying again: {posix.strerror(posix.errno)}")
            elif pid == 0:
                logger.trace(&"New child has been spawned")
                if not servicesCopy[0].supervised:
                    logger.info(&"Starting unsupervised service '{servicesCopy[0].name}'")
                else:
                    logger.info(&"Starting supervised service '{servicesCopy[0].name}'")
                startService(logger, servicesCopy[0])
            elif servicesCopy.len() > 0:
                workerCount += 1
                if servicesCopy[0].supervised:
                    addManagedProcess(pid, servicesCopy[0])
                servicesCopy.del(0)
        quit(0)
    else:
        logger.debug(&"Waiting for completion of service spawning in runlevel {($level).toLowerAscii()}")
        logger.trace(&"Calling waitpid() on {pid}")
        var returnCode = waitPid(cint(pid), status, WUNTRACED)
        logger.trace(&"Call to waitpid() set status to {status} and returned {returnCode}")