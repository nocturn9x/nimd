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
import strformat
import strutils
import syscall


import logging

# Note: This will work reliably only with absolute paths. Use with care
const symlinks: array[7, tuple[dest, source: string]] = [
    (dest: "/dev/fd", source: "/proc/self/fd"),
    (dest: "/dev/fd/0", source: "/proc/self/fd/0"),
    (dest: "/dev/fd/1", source: "/proc/self/fd/1"),
    (dest: "/dev/fd/2", source: "/proc/self/fd/2"),
    (dest: "/dev/std/in", source: "/proc/self/fd/0"),
    (dest: "/dev/std/out", source: "/proc/self/fd/1"),
    (dest: "/dev/std/err", source: "/proc/self/fd/2"),
]


var shutdownHandlers: seq[proc (logger: Logger, code: int)] = @[]


proc doSync*(logger: Logger) =
    logger.debug(&"Calling sync() syscall has returned {syscall(SYNC)}")    


proc reapProcess*(logger: Logger) =
    logger.debug("Handling SIGCHLD")
    # TODO


proc exists*(p: string): bool =
    # Checks if a path exists. Thanks
    # araq :)
    try:
        discard getFileInfo(p)
        result = true
    except OSError:
        result = false


proc addShutdownHandler*(handler: proc (logger: Logger, code: int), logger: Logger) =
    shutdownHandlers.add(handler)


proc removeShutdownHandler*(handler: proc (logger: Logger, code: int)) =
    for i, h in shutdownHandlers:
        if h == handler:
            shutdownHandlers.delete(i)


proc nimDExit*(logger: Logger, code: int, emerg: bool = true) =
    logger.warning("The system is shutting down")
    # TODO
    logger.info("Processing shutdown runlevel")
    # TODO
    logger.info("Running shutdown handlers")
    try:
        for handler in shutdownHandlers:
            handler(logger, code)
    except:
        logger.error(&"An error has occurred while calling shutdown handlers. Error -> {getCurrentExceptionMsg()}")
        # Note: continues calling handlers!
    if emerg:
        # We're in emergency mode: do not crash the kernel, spawn a shell and exit
        logger.fatal("NimD has entered emergency mode and cannot continue. You will be now (hopefully) dropped in a root shell: you're on your own. May the force be with you")
        discard execShellCmd("/bin/sh")  # TODO: Is this fine? maybe use execProcess
    else:
        logger.info("Terminating child processes with SIGINT")
        # TODO
        logger.info("Terminating child processes with SIGKILL")
        # TODO
        logger.warning("Shutdown procedure complete, sending final termination signal")
        # TODO
    quit(code)


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


proc createSymlinks*(logger: Logger) =
    ## Creates a set of symlinks needed
    ## by stuff like Linux ports of BSD
    ## software
    for sym in symlinks:
        try:
            if not exists(sym.source):
                logger.warning(&"Skipping creation of symbolic link from {sym.dest} to {sym.source}: destination does not exist")
                continue
            elif exists(sym.dest):
                if symlinkExists(sym.dest) and sameFile(expandSymlink(sym.dest), sym.source):
                    logger.debug(&"Skipping creation of symbolic link from {sym.dest} to {sym.source}: link already exists")
                elif symlinkExists(sym.dest) and not sameFile(expandSymlink(sym.dest), sym.source):
                    logger.warning(&"Attempted to create symbolic link from {sym.dest} to {sym.source}, but link already exists and points to {expandSymlink(sym.dest)}")
                continue
            logger.debug(&"Creating symbolic link from {sym.source} to {sym.dest}")
            createSymlink(sym.dest, sym.source)
        except:
            logger.error(&"Failed to create symbolic link from {sym.dest} to {sym.source}: {getCurrentExceptionMsg()}")


proc createDirectories*(logger: Logger) =
    ## Creates 

proc sleepSeconds*(amount: SomeInteger) = sleep(amount * 1000)


proc strsignal*(sig: cint): cstring {.header: "string.h", importc.}
