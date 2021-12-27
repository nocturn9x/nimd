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
import parseopt
import strformat
import posix
import os

# NimD's own stuff
import util/[logging, constants, misc]
import core/[mainloop, fs, shutdown, services]


proc addStuff = 
    ## Adds stuff to test NimD. This is
    ## a temporary procedure
    
    # Adds symlinks
    addSymlink(newSymlink(dest="/dev/fd", source="/proc/self/fd"))
    addSymlink(newSymlink(dest="/dev/fd/0", source="/proc/self/fd/0"))
    addSymlink(newSymlink(dest="/dev/fd/1", source="/proc/self/fd/1"))
    addSymlink(newSymlink(dest="/dev/fd/2", source="/proc/self/fd/2"))
    addSymlink(newSymlink(dest="/dev/std/in", source="/proc/self/fd/0"))
    addSymlink(newSymlink(dest="/dev/std/out", source="/proc/self/fd/1"))
    addSymlink(newSymlink(dest="/dev/std/err", source="/proc/self/fd/2"))
    # Tests here. Check logging output (debug) to see if
    # they work as intended
    addSymlink(newSymlink(dest="/dev/std/err", source="/"))                # Should say link already exists and points to /proc/self/fd/2
    addSymlink(newSymlink(dest="/dev/std/in", source="/does/not/exist"))   # Should say destination does not exist
    addSymlink(newSymlink(dest="/dev/std/in", source="/proc/self/fd/0"))   # Should say link already exists
    addDirectory(newDirectory("test", 764))           # Should create a directory
    addDirectory(newDirectory("/dev/disk", 123))      # Should say directory already exists
    # Shutdown handler to unmount disks
    addShutdownHandler(newShutdownHandler(unmountAllDisks))
    # Adds test services
    var echoer = newService(name="echoer", description="prints owo", exec="/bin/echo owoooooooooo",
                            runlevel=Boot, kind=Simple, workDir=getCurrentDir(),
                            supervised=false, restart=Always, restartDelay=5,
                            depends=(@[]), provides=(@[]))
    var errorer = newService(name="errorer", description="la mamma di gavd", 
                             exec="/bin/false", supervised=true, restart=OnFailure,
                             restartDelay=5, runlevel=Boot, workDir="/", kind=Simple,
                             depends=(@[]), provides=(@[]))
    var exiter = newService(name="exiter", description="la mamma di licenziat", 
                            exec="/bin/true", supervised=true, restart=Always,
                            restartDelay=5, runlevel=Boot, workDir="/", kind=Simple,
                            depends=(@[newDependency(Other, errorer)]), provides=(@[]))
    var shell = newService(name="login", description="A simple login shell", kind=Simple,
                           getCurrentDir(), runlevel=Default, exec="/bin/login -f root",
                           supervised=true, restart=Always, restartDelay=5, depends=(@[]), provides=(@[]),
                           useParentStreams=true
                           )
    addService(errorer)
    addService(echoer)
    addService(exiter)
    addService(shell)



proc main(logger: Logger, mountDisks: bool = true, fstab: string = "/etc/fstab", setHostname: bool = true, workerCount: int = 1) =
    ## NimD's entry point and setup
    ## function
    setStdIoUnbuffered()   # Colors and output synchronization don't work otherwise
    logger.debug("Starting NimD: A minimal, self-contained, dependency-based Linux init system written in Nim")
    logger.info(&"NimD version {NimdVersion.major}.{NimdVersion.minor}.{NimdVersion.patch} is starting up!")
    logger.trace("Calling getCurrentProcessId()")
    let pid = getCurrentProcessId()
    logger.trace(&"getCurrentProcessId() returned {pid}")
    if pid != 1:
        logger.warning(&"Expecting to run as PID 1, but current process ID is {pid}")
    logger.trace("Calling getuid()")
    let uid = posix.getuid()
    logger.trace(&"getuid() returned {uid}")
    if uid != 0:
        logger.fatal(&"NimD must run as root, but current user id is {uid}")
        nimDExit(logger, EPERM, emerg=false)   # EPERM - Operation not permitted
    logger.trace("Setting up signal handlers")
    onSignal(SIGABRT, SIGALRM, SIGHUP, SIGILL, SIGKILL, SIGQUIT, SIGSTOP, SIGSEGV, SIGTSTP,
            SIGTRAP, SIGPIPE, SIGUSR1, SIGUSR2, 6, SIGFPE, SIGBUS, SIGURG, SIGTERM, SIGINT):  # 6 is SIGIOT
        # Can't capture local variables because this implicitly generates
        # a noconv procedure, so we use getDefaultLogger() instead
        getDefaultLogger().warning(&"Ignoring signal {sig} ({strsignal(sig)})")  # Nim injects the variable "sig" into the scope. Gotta love those macros
    onSignal(SIGCHLD):
        # One of the key features of an init system is reaping child
        # processes!
        reapProcess(getDefaultLogger())
    addStuff()
    try:
        if mountDisks:
            logger.info("Mounting filesystem")
            mountDisks(logger, fstab)
        else:
            logger.info("Skipping disk mounting, assuming this has already been done")
        logger.info("Creating symlinks")
        createSymlinks(logger)
        logger.info("Creating directories")
        createDirectories(logger)
        logger.info("Filesystem preparation complete")
        logger.debug("Calling sync() just in case")
        doSync(logger)
    except:
        logger.fatal(&"A fatal error has occurred while preparing filesystem, booting cannot continue. Error -> {getCurrentExceptionMsg()}")
        nimDExit(logger, 131, emerg=false)
    if setHostname:
        logger.info("Setting hostname")
        logger.debug(&"Hostname was set to '{misc.setHostname(logger)}'")
    else:
        logger.info("Skipping setting hostname")
    logger.debug("Entering critical fork() section: blocking signals")
    blockSignals(logger)   # They are later unblocked in mainLoop
    logger.info("Processing boot runlevel")
    startServices(logger, workers=workerCount, level=Boot)
    logger.debug("Starting main loop")
    mainLoop(logger, workers=workerCount)


when isMainModule:
    var logger = getDefaultLogger()
    var optParser = initOptParser(commandLineParams())
    for kind, key, value in optParser.getopt():
        case kind:
            of cmdArgument:
                echo "Error: unexpected argument"
                quit(EINVAL)
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
                        echo &"Unkown command-line long option '{key}'"
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
                        echo &"Unkown command-line short option '{key}'"
                        echo "Usage: nimd [options]"
                        echo "Try nimd --help for more info"
                        quit(EINVAL) # EINVAL - Invalid argument
            else:
                echo "Usage: nimd [options]"
                quit(EINVAL) # EINVAL - Invalid argument
    logger.debug("Calling NimD entry point")
    try:
        main(logger)
    except:
        logger.fatal(&"A fatal unrecoverable error has occurred during startup and NimD cannot continue: {getCurrentExceptionMsg()}")
        nimDExit(logger, 131)  # ENOTRECOVERABLE - State not recoverable
        # This will almost certainly cause the kernel to crash with an error the likes of "Kernel not syncing, attempted to kill init!",
        # but, after all, there isn't much we can do if we can't even initialize *ourselves* is there?
