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
import core/mainloop


proc main(logger: Logger) = 
    ## NimD's entry point
    logger.debug("Starting NimD: A minimal, self-contained dependency-based Linux init system written in Nim")
    logger.info(&"NimD version {NimdVersion.major}.{NimdVersion.minor}.{NimdVersion.patch} is starting up...")
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
        quit(EPERM)   # EPERM - Operation not permitted
    logger.debug("Setting up dummy signal handlers")
    onSignal(SIGABRT, SIGALRM, SIGHUP, SIGILL, SIGKILL, SIGQUIT, SIGSTOP, SIGSEGV,
            SIGTRAP, SIGTERM, SIGPIPE, SIGUSR1, SIGUSR2, 6, SIGFPE, SIGBUS, SIGURG, SIGINT):  # 6 is SIGIOT
        # Can't capture local variables because this implicitly generates
        # a noconv procedure
        getDefaultLogger().warning(&"Ignoring signal {sig} ({strsignal(sig)})")  # Nim injects the variable "sig" into the scope. Gotta love those macros
    logger.debug("Starting uninterruptible mainloop")
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
                        logger.error(&"Unkown command-line long option '{key}'")
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
        logger.fatal(&"A fatal unrecoverable error has occurred during startup and NimD cannot continue: {getCurrentExceptionMsg()}")
        nimDExit(logger, 131)  # ENOTRECOVERABLE - State not recoverable
        # This will almost certainly cause the kernel to crash with an error the likes of "Kernel not syncing, attempted to kill init!",
        # but, after all, there isn't much we can do if we can't even initialize *ourselves* is there?