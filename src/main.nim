# Copyright 2021 Mattia Giambirbone & All Contributors
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
import parseopt
import strformat
import posix
import os

# NimD's own stuff
import util/[logging, constants, misc]
import core/[mainloop, fs, shutdown, services]



proc main(logger: Logger, mountDisks: bool = true, fstab: string = "/etc/fstab") = 
    ## NimD's entry point and setup
    ## function
    logger.debug("Starting NimD: A minimal, self-contained dependency-based Linux init system written in Nim")
    logger.info(fmt"NimD version {NimdVersion.major}.{NimdVersion.minor}.{NimdVersion.patch} is starting up!")
    logger.trace("Calling getCurrentProcessId()")
    let pid = getCurrentProcessId()
    logger.trace(fmt"getCurrentProcessId() returned {pid}")
    if pid != 1:
        logger.warning(fmt"Expecting to run as PID 1, but current process ID is {pid}")
    logger.trace("Calling getuid()")
    let uid = posix.getuid()
    logger.trace(fmt"getuid() returned {uid}")
    if uid != 0:
        logger.fatal(fmt"NimD must run as root, but current user id is {uid}")
        nimDExit(logger, EPERM)   # EPERM - Operation not permitted
    logger.trace("Setting up signal handlers")
    onSignal(SIGABRT, SIGALRM, SIGHUP, SIGILL, SIGKILL, SIGQUIT, SIGSTOP, SIGSEGV, SIGTSTP,
            SIGTRAP, SIGPIPE, SIGUSR1, SIGUSR2, 6, SIGFPE, SIGBUS, SIGURG, SIGTERM, SIGINT):  # 6 is SIGIOT
        # Can't capture local variables because this implicitly generates
        # a noconv procedure, so we use getDefaultLogger() instead. Must find
        # a better solution long-term because we need the configuration from
        # our own logger object (otherwise we'd always create a new one and
        # never switch our logs to file once booting is completed)
        getDefaultLogger().warning(fmt"Ignoring signal {sig} ({strsignal(sig)})")  # Nim injects the variable "sig" into the scope. Gotta love those macros
    onSignal(SIGCHLD):
        # One of the key features of an init system is reaping child
        # processes!
        reapProcess(getDefaultLogger())
    onSignal(SIGINT):
        # Temporary
        nimDExit(getDefaultLogger(), 131, emerg=true)
    addSymlink(newSymlink(dest="/dev/fd", source="/proc/self/fd"))
    addSymlink(newSymlink(dest="/dev/fd/0", source="/proc/self/fd/0"))
    addSymlink(newSymlink(dest="/dev/fd/1", source="/proc/self/fd/1"))
    addSymlink(newSymlink(dest="/dev/fd/2", source="/proc/self/fd/2"))
    addSymlink(newSymlink(dest="/dev/std/in", source="/proc/self/fd/0"))
    addSymlink(newSymlink(dest="/dev/std/out", source="/proc/self/fd/1"))
    addSymlink(newSymlink(dest="/dev/std/err", source="/proc/self/fd/2"))
    # Tests here. Check logging output (debug) to see if
    # they work as intended
    addSymlink(newSymlink(dest="/dev/std/err", source="/"))  # Should say link already exists and points to /proc/self/fd/2
    addSymlink(newSymlink(dest="/dev/std/in", source="/does/not/exist"))   # Shuld say destination does not exist
    addSymlink(newSymlink(dest="/dev/std/in", source="/proc/self/fd/0"))   # Should say link already exists
    # Adds virtual filesystems
    addVFS(newFilesystem(source="proc", target="/proc", fstype="proc", mountflags=0u64, data="nosuid,noexec,nodev", dump=0u8, pass=0u8))
    addVFS(newFilesystem(source="sys", target="/sys", fstype="sysfs", mountflags=0u64, data="nosuid,noexec,nodev", dump=0u8, pass=0u8))
    addVFS(newFilesystem(source="run", target="/run", fstype="tmpfs", mountflags=0u64, data="mode=0755,nosuid,nodev", dump=0u8, pass=0u8))
    addVFS(newFilesystem(source="dev", target="/dev", fstype="devtmpfs", mountflags=0u64, data="mode=0755,nosuid", dump=0u8, pass=0u8))
    addVFS(newFilesystem(source="devpts", target="/dev/pts", fstype="devpts", mountflags=0u64, data="mode=0620,gid=5,nosuid,noexec", dump=0u8, pass=0u8))
    addVFS(newFilesystem(source="shm", target="/dev/shm", fstype="tmpfs", mountflags=0u64, data="mode=1777,nosuid,nodev", dump=0u8, pass=0u8))
    addShutdownHandler(newShutdownHandler(unmountAllDisks))
    try:
        if mountDisks:
            logger.info("Mounting filesystem")
            logger.info("Mounting virtual disks")
            mountVirtualDisks(logger)
            logger.info("Mounting real disks")
            mountRealDisks(logger, fstab)
        else:
            logger.info("Skipping disk mounting, assuming this has already been done")
    except:
        logger.fatal(fmt"A fatal error has occurred while preparing filesystem, booting cannot continue. Error -> {getCurrentExceptionMsg()}")
        nimDExit(logger, 131, emerg=false)
    logger.info("Disks mounted")
    logger.debug("Calling sync() just in case")
    doSync(logger)
    logger.info("Setting hostname")
    logger.debug(fmt"Hostname was set to '{setHostname(logger)}'")
    logger.info("Creating symlinks")
    createSymlinks(logger)
    logger.info("Creating directories")
    createDirectories(logger)
    logger.debug("Entering critical fork() section: blocking signals")
    var sigset: Sigset
    # TODO
    logger.info("Processing boot runlevel")
    addService(newService(name="echoer", description="prints owo", exec="/bin/echo owo",
                          runlevel=Boot, kind=Oneshot, workDir=getCurrentDir(),
                          supervised=false, restartOnFailure=false, restartDelay=0))
    addService(newService(name="sleeper", description="la mamma di licenziato", 
                         exec="/usr/bin/sleep 10", supervised=true, restartOnFailure=true,
                         restartDelay=5, runlevel=Boot, workDir="/home", kind=Simple))
    addService(newService(name="errorer", description="la mamma di gavd", 
                         exec="/bin/false", supervised=true, restartOnFailure=true,
                         restartDelay=5, runlevel=Boot, workDir="/", kind=Simple))
    startServices(logger, workers=2, level=Boot)
    logger.debug("Setting up real signal handlers")
    onSignal(SIGABRT, SIGALRM, SIGHUP, SIGILL, SIGKILL, SIGQUIT, SIGSTOP, SIGSEGV, SIGTSTP,
            SIGTRAP, SIGPIPE, SIGUSR1, SIGUSR2, 6, SIGFPE, SIGBUS, SIGURG, SIGTERM):  # 6 is SIGIOT
        # Can't capture local variables because this implicitly generates
        # a noconv procedure, so we use getDefaultLogger() instead. Must find
        # a better solution long-term because we need the configuration from
        # our own logger object (otherwise we'd always create a new one and
        # never switch our logs to file once booting is completed)
        getDefaultLogger().warning(fmt"Ignoring signal {sig} ({strsignal(sig)})")  # Nim injects the variable "sig" into the scope. Gotta love those macros
    onSignal(SIGCHLD):
        # One of the key features of an init system is reaping child
        # processes!
        reapProcess(getDefaultLogger())
    onSignal(SIGINT):
        # Temporary
        nimDExit(getDefaultLogger(), 131, emerg=true)
    logger.debug("Starting main loop")
    mainLoop(logger)


when isMainModule:
    var logger = getDefaultLogger()
    var optParser = initOptParser(commandLineParams())
    for kind, key, value in optParser.getopt():
        case kind:
            of cmdArgument:
                discard
            of cmdLongOption:
                case key:
                    of "help":
                        echo helpMessage
                        quit(0)
                    of "version":
                        echo NimDVersionString
                        quit(0)
                    of "verbose":
                        logger.setLevel(LogLevel.Debug)
                    of "extra":
                        logger.setLevel(LogLevel.Trace)
                    else:
                        logger.error(fmt"Unkown command-line long option '{key}'")
                        quit(EINVAL)  # EINVAL - Invalid argument
            of cmdShortOption:
                case key:
                    of "h":
                        echo helpMessage
                        quit(0)
                    of "v":
                        echo NimDVersionString
                        quit(0)
                    of "V":
                        logger.setLevel(LogLevel.Debug)
                    of "X":
                        logger.setLevel(LogLevel.Trace)
                    else:
                        logger.error(&"Unkown command-line short option '{key}'")
                        quit(EINVAL) # EINVAL - Invalid argument
            else:
                echo "Usage: nimd [options]"
                quit(EINVAL) # EINVAL - Invalid argument
    logger.debug("Calling NimD entry point")
    try:
        main(logger)
    except:
        logger.fatal(fmt"A fatal unrecoverable error has occurred during startup and NimD cannot continue: {getCurrentExceptionMsg()}")
        nimDExit(logger, 131)  # ENOTRECOVERABLE - State not recoverable
        # This will almost certainly cause the kernel to crash with an error the likes of "Kernel not syncing, attempted to kill init!",
        # but, after all, there isn't much we can do if we can't even initialize *ourselves* is there?
