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

## Default signal handlers, exit procedures and helpers
## to allow a clean shutdown of NimD
import os
import strutils
import syscall
import strformat
import posix


import logging
import ../core/shutdown


proc sleepSeconds*(amount: SomeNumber) = sleep(int(amount * 1000))
proc dummySigHandler(x: cint) {.noconv.} = discard



proc doSync*(logger: Logger) =
    ## Performs a sync() system call
    logger.debug(&"Calling sync() syscall has returned {syscall(SYNC)}")    


proc blockSignals*(logger: Logger) =
    ## Temporarily blocks all signals
    ## for critical sections of code
    var tmp: Sigset
    var sigaction: Sigaction
    sigaction.sa_handler = dummySigHandler
    sigaction.sa_flags = SA_RESTART
    if posix.sigfillset(sigaction.sa_mask) == -1:
        logger.fatal(&"Could not initialize signal lock (code {posix.errno}, {posix.strerror(posix.errno)}): environment is not safe, exiting now!")
        nimDExit(logger, 131)
    if posix.sigprocmask(SIG_SETMASK, sigaction.sa_mask, tmp) == -1:
        logger.fatal(&"Could not apply signal mask to process (code {posix.errno}, {posix.strerror(posix.errno)}): environment is not safe, exiting now!")
        nimDExit(logger, 131)


proc unblockSignals*(logger: Logger) =
    ## Unblocks all signals
    var tmp: Sigset
    var sigaction: Sigaction
    sigaction.sa_flags = SA_RESTART
    if posix.sigemptyset(sigaction.sa_mask) == -1:
        logger.fatal(&"Could not initialize signal unlock (code {posix.errno}, {posix.strerror(posix.errno)}): environment is not safe, exiting now!")
        nimDExit(logger, 131)
    if posix.sigprocmask(SIG_SETMASK, sigaction.sa_mask, tmp) == -1:
        logger.fatal(&"Could not apply signal mask to process (code {posix.errno}, {posix.strerror(posix.errno)}): environment is not safe, exiting now!")
        nimDExit(logger, 131)
    

proc reapProcess*(logger: Logger) =
    ## Reaps zombie processes. Note: This does not
    ## handle restarting crashed service processes,
    ## it simply makes sure that there's no dead
    ## process entries in the kernel's ptable.
    ## When (supervised) services are started,
    ## they are spawned by a controlling subprocess
    ## of PID 1 which listens for changes in them
    ## and restarts them as needed
    logger.debug("Handling SIGCHLD")
    var status: cint
    logger.trace("Calling waitpid() on -1")
    var returnCode = posix.waitPid(-1, status, WNOHANG)   # This doesn't hang, which is what we want
    logger.trace(&"Call to waitpid() set status to {status} and returned {returnCode}")



proc setHostname*(logger: Logger): string =
    ## Sets the machine's hostname. Returns 
    ## the hostname that has been set or an
    ## empty string if an error occurs. If
    ## /etc/hostname doesn't exist, the hostname
    ## defaults to localhost
    var hostname: string
    try:
        if not fileExists("/etc/hostname"):
            logger.warning("/etc/hostname doesn't exist, defaulting to 'localhost'")
            hostname = "localhost"
        else:
            hostname = readFile("/etc/hostname").strip(chars={'\n'})
        writeFile("/proc/sys/kernel/hostname", hostname)
    except:
        logger.error(&"An error occurred while setting hostname -> {getCurrentExceptionMsg()}")
        return ""
    return hostname


proc exists*(p: string): bool =
    ## Returns true if a path exists,
    ## false otherwise
    try:
        discard getFileInfo(p)
        result = true
    except OSError:
        result = false