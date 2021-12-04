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
import cpuinfo
import tables
import osproc
import posix
import shlex


import ../util/logging
import ../util/misc


type
    RunLevel* = enum
        ## Enum of possible runlevels
        Boot, Default, Shutdown
    ServiceKind* = enum
        ## Enumerates all service
        ## types
        Oneshot, Simple
    Service* = ref object of RootObj
        ## A service object
        name: string
        description: string
        kind: ServiceKind
        workDir: string
        runlevel: RunLevel
        exec: string
        supervised: bool
        restartOnFailure: bool
        restartDelay: int


proc newService*(name, description: string, kind: ServiceKind, workDir: string, runlevel: RunLevel, exec: string, supervised, restartOnFailure: bool, restartDelay: int): Service =
    ## Creates a new service object
    result = Service(name: name, description: description, kind: kind, workDir: workDir, runLevel: runLevel,
                     exec: exec, supervised: supervised, restartOnFailure: restartOnFailure, restartDelay: restartDelay)


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
    var pid = pid
    var status: cint
    var returnCode: int
    var sig: int
    while true:
        returnCode = posix.waitPid(Pid(pid), status, WUNTRACED)
        if WIFEXITED(status):
            sig = 0
        elif WIFSIGNALED(status):
            sig = WTERMSIG(status)
        else:
            sig = -1
        if service.restartOnFailure and sig > 0:
            logger.info(&"Service {service.name} has exited with return code {returnCode} (terminated by signal {sig}: {strsignal(cint(sig))}), sleeping {service.restartDelay} seconds before restarting it")
            removeManagedProcess(pid)
            sleepSeconds(service.restartDelay)
            var split = shlex(service.exec)
            if split.error:
                logger.error(&"Error while starting service {service.name}: invalid exec syntax")
                return
            var arguments = split.words
            let progName = arguments[0]
            arguments = arguments[1..^1]
            pid = startProcess(progName, workingDir=service.workDir, args=arguments, options={poParentStreams}).processID()
        else:
            logger.info(&"Service {service.name} has exited with return code {returnCode}), shutting down controlling process")
            break
    
    

proc startService(logger: Logger, service: Service) =
    ## Starts a single service (this is called by
    ## startServices below until all services have
    ## been started)
    
    var split = shlex(service.exec)
    if split.error:
        logger.error(&"Error while starting service {service.name}: invalid exec syntax")
        return
    var arguments = split.words
    let progName = arguments[0]
    arguments = arguments[1..^1]
    try:
        var process = startProcess(progName, workingDir=service.workDir, args=arguments, options={poParentStreams, })
        if service.supervised:
            supervisorWorker(logger, service, process.processID)
    except OSError:
        logger.error(&"Error while starting service {service.name}: {getCurrentExceptionMsg()}")
    quit(0)


proc startServices*(logger: Logger, workers: int = 1, level: RunLevel) =
    ## Starts the services in the given
    ## runlevel. The workers parameter
    ## configures parallelism and allows
    ## for faster boot times by starting
    ## services concurrently rather than 
    ## sequentially (1 to disable parallelism).
    ## Note this function immediately returns to
    ## the caller and forks in the background
    echo posix.getpid()
    discard readLine(stdin)
    var pid: int = posix.fork()
    if pid == -1:
        logger.fatal(&"Could not fork(): {posix.strerror(posix.errno)}")
        return
    elif pid == 0:
        quit(0)
    var servicesCopy: seq[Service] = @[]
    echo servicesCopy.len(), " ", posix.getpid()
    for service in services:
        if service.runlevel == level:
            servicesCopy.add(service)
    echo servicesCopy.len(), " ", posix.getpid()
    if workers > cpuinfo.countProcessors() * 2 - 1:
        logger.warning(&"The configured workers count is beyond the recommended threshold ({workers} > {cpuinfo.countProcessors() * 2 - 1}), performance may degrade")
    while servicesCopy.len() > 0:
        echo servicesCopy.len(), " ", posix.getpid()
        sleepSeconds(5)
        for i in 1..workers:
            pid = posix.fork()
            if pid == -1:
                logger.error(&"An error occurred while forking to spawn services, trying again: {posix.strerror(posix.errno)}")
            elif pid == 0:
                logger.info(&"Starting service {servicesCopy[0].name}")
                startService(logger, servicesCopy[0])
            else:
                if servicesCopy.len() > 0 and servicesCopy[0].supervised:
                    addManagedProcess(pid, servicesCopy[0])
            
