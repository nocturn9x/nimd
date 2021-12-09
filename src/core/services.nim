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
        Boot = 0,
        Default,
        Shutdown
    ServiceKind* = enum
        ## Enumerates all service
        ## types
        Oneshot, Simple
    RestartKind* = enum
        ## Enum of possible restart modes
        Always, OnFailure, Never
    DependencyKind* = enum
        ## Enum of possible dependencies
        Network, Filesystem,
        Ssh, Ftp, Http, Other
    Dependency* = ref object
        ## A dependency
        kind*: DependencyKind
        provider*: Service
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
        depends: seq[Dependency]
        provides: seq[Dependency]
        ## These two fields are
        ## used by the dependency
        ## resolver
        isMarked: bool
        isResolved: bool



proc newDependency*(kind: DependencyKind, provider: Service): Dependency =
    ## Creates a new dependency object
    result = Dependency(kind: kind, provider: provider)


proc newService*(name, description: string, kind: ServiceKind, workDir: string, runlevel: RunLevel, exec: string, supervised: bool, restart: RestartKind,
                 restartDelay: int, depends, provides: seq[Dependency]): Service =
    ## Creates a new service object
    result = Service(name: name, description: description, kind: kind, workDir: workDir, runLevel: runLevel,
                     exec: exec, supervised: supervised, restart: restart, restartDelay: restartDelay, 
                     depends: depends, provides: provides, isMarked: false, isResolved: false)
    result.provides.add(newDependency(Other, result))


proc extend[T](self: var seq[T], other: seq[T]) =
    ## Extends self with the elements of other
    for el in other:
        self.add(el)


var services: seq[Service] = @[]
var processIDs: TableRef[int, Service] = newTable[int, Service]()


proc resolve(logger: Logger, node: Service): seq[Service] =
    ## Returns a sorted list of services according
    ## to their dependency and provider requirements.
    ## This function recursively iterates over the
    ## list of services, treating it as a DAG
    ## (Directed Acyclic Graph) and builds a topologically
    ## sorted list such that a service appears in it only
    ## after all of its dependencies and only
    ## before all of its dependents.
    ## This function also automatically handles
    ## detached subgraphs, which can occurr if
    ## one or more dependencies have common
    ## dependencies/dependents between each other,
    ## but not with the rest of the graph. Nodes
    ## that have no dependencies nor provide any
    ## service may be located anywhere in the list,
    ## as that does not invalidate the invariants
    ## described above. The algorithm comes from
    ## https://www.electricmonk.nl/log/2008/08/07/dependency-resolving-algorithm/
    ## and has been extended to support the dependent-provider paradigm.
    ## Note that it is not an error for a service in a given runlevel to depend
    ## on services in other runlevels: when that occurs a warning is raised and
    ## the service in the lower runlevel is promoted to the higher one (runlevels start from 0),
    ## which means adding a module in a given runlevel implicitly adds all of its dependencies
    ## to said runlevel as well, regardless of what was specified in their unit file
    if node.isResolved:
        logger.debug(&"Dependency '{node.name}' has already been satisfied, skipping it")
        return @[]
    var ok: bool = true
    result = @[]
    node.isMarked = true
    for service in node.provides:
        if service.provider == node:
            continue   # Services implicitly provide themselves
        if node.runlevel < service.provider.runlevel:
            logger.warning(&"Service '{node.name}' in runlevel {node.runlevel} depends on '{service.provider.name}' in runlevel {service.provider.runlevel}, loading dependency regardless")
        if not service.provider.isResolved:
            if service.provider.isMarked:
                logger.warning(&"Cyclic dependency from '{node.name}' to '{service.provider.name}' detected while building dependency graph: skipping both")
                ok = false
                break
            service.provider.isMarked = true
            result.extend(resolve(logger, service.provider))
    for service in node.depends:
        if service.provider == node:
            logger.warning(&"Cyclic dependency from '{node.name}' to itself detected while building dependency graph: skipping it")
            ok = false
            break
        if node.runlevel > service.provider.runlevel:
            logger.warning(&"Service '{node.name}' in runlevel {node.runlevel} depends on '{service.provider.name}' in runlevel {service.provider.runlevel}, loading both")
        if not service.provider.isResolved:
            if service.provider.isMarked:
                logger.warning(&"Cyclic dependency from '{node.name}' to '{service.provider.name}' detected while building dependency graph: skipping both")
                ok = false
                break
            service.provider.isMarked = true
            result.extend(resolve(logger, service.provider))
    if ok:
        result.add(node)
        node.isResolved = true
        node.isMarked = false


proc resolveDependencies(logger: Logger, services: seq[Service], level: RunLevel): seq[Service] =
    ## Iteratively calls resolve() until all services
    ## have been processed
    result = @[]
    var node: Service
    var i = 1
    var s: seq[Service] = @[]
    for service in services:
        if service.runlevel == level:
            s.add(service)
    while i <= len(s):
        node = s[^i]
        result.extend(resolve(logger, node))
        inc(i)


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
        if service.supervised and service.kind != Oneshot:
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
    if len(services) == 0:
        return
    var dependencies = resolveDependencies(logger, services, level)
    if workers > cpuinfo.countProcessors():
        logger.warning(&"The configured number of workers ({workers}) is greater than the number of CPU cores ({cpuinfo.countProcessors()}), performance may degrade")
    var status: cint
    var pid: int = posix.fork()
    var pids: seq[int] = @[]
    if pid == -1:
        logger.error(&"Error, cannot fork: {posix.strerror(posix.errno)}")
    elif pid == 0:
        var service: Service
        logger.debug("Started service spawner process")
        while dependencies.len() > 0:
            for _ in 0..<workers:
                if len(dependencies) == 0:
                    break
                service = dependencies[0]
                dependencies.del(0)
                pid = posix.fork()
                if pid == -1:
                    logger.error(&"An error occurred while forking to spawn services, trying again: {posix.strerror(posix.errno)}")
                elif pid == 0:
                    logger.trace(&"New child has been spawned")
                    if not service.supervised or service.kind == Oneshot:
                        logger.info(&"""Starting {(if service.kind != Oneshot: "unsupervised" else: "oneshot")} service '{service.name}'""")
                    else:
                        logger.info(&"Starting supervised service '{service.name}'")
                    startService(logger, service)
                else:
                    pids.add(pid)
                    if service.supervised:
                        addManagedProcess(pid, service)
            if len(pids) == workers:
                logger.debug(&"""Worker queue full, waiting for some worker{(if workers > 1: "s" else: "")} to exit...""")
                for i, pid in pids:
                    logger.trace(&"Calling waitpid() on {pid}")
                    var returnCode = waitPid(cint(pid), status, WUNTRACED)
                    logger.trace(&"Call to waitpid() on {pid} set status to {status} and returned {returnCode}")
                pids = @[]
        quit(0)
    else:
        logger.debug(&"Waiting for completion of service spawning in runlevel {($level).toLowerAscii()}")
        logger.trace(&"Calling waitpid() on {pid}")
        var returnCode = waitPid(cint(pid), status, WUNTRACED)
        logger.trace(&"Call to waitpid() on {pid} set status to {status} and returned {returnCode}")