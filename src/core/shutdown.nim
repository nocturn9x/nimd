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
import os
import osproc
import posix
import glob
import strutils
import strformat
import times


import ../util/logging
import services


type ShutdownHandler* = ref object
    ## A shutdown handler (internal to NimD)
    body*: proc (logger: Logger, code: int)


proc newShutdownHandler*(body: proc (logger: Logger, code: int)): ShutdownHandler =
    result = ShutdownHandler(body: body)


var shutdownHandlers: seq[ShutdownHandler] = @[]
var sigTermDelay: float = 10.0


proc addShutdownHandler*(handler: ShutdownHandler) =
    ## Registers a shutdown handler to be executed
    ## upon a call of NimDExit
    shutdownHandlers.add(handler)


proc removeShutdownHandler*(handler: ShutdownHandler) =
    ## Unregisters a shutdown handler
    for i, hndlr in shutdownHandlers:
        if hndlr == handler:
            shutdownHandlers.del(i)
            break


proc anyUserlandProcessLeft: bool =
    ## Returns true if there's any
    ## userland processes running.
    ## A userland process is one
    ## whose pid is higher than 2
    ## or whose /proc/<pid>/cmdline
    ## file is empty. This function
    ## assumes /proc is mounted and
    ## readable and returns false in
    ## the event of any I/O exceptions
    try:
        for dir in walkGlob("/proc/[0-9]"):
            if dir.lastPathPart.parseInt() > 2 or readFile(dir.joinPath("/cmdline")).len() == 0:
                # PID > 2 or empty cmdline file means it's a kernel process so we ignore
                # it (not that we'd have the right to send those processes a signal anyway)
                continue
            else:
                return true   # There is at least one userland process running 
    except OSError:
        return false
    except IOError:
        return false
    return false


proc nimDExit*(logger: Logger, code: int, emerg: bool = true) =
    ## NimD's exit point. This function tries to shut down
    ## as cleanly as possible. When emerg equals true, it will
    ## try to spawn a root shell and exit
    if emerg:
        # We're in emergency mode: do not crash the kernel, spawn a shell and exit
        logger.fatal("NimD has entered emergency mode and cannot continue. You will be now (hopefully) dropped in a root shell: you're on your own. May the force be with you")
        logger.info("Terminating child processes with SIGKILL")
        discard execCmd("/bin/sh")  # TODO: Is this fine? maybe use execProcess
        discard posix.kill(-1, SIGKILL)
        quit(-1)
    logger.warning("The system is shutting down")
    logger.info("Processing shutdown runlevel")
    startServices(logger, Shutdown)
    logger.info("Running shutdown handlers")
    try:
        for handler in shutdownHandlers:
            handler.body(logger, code)
    except:
        logger.error(&"An error has occurred while calling shutdown handlers. Error -> {getCurrentExceptionMsg()}")
        # Note: continues calling handlers!
    logger.info("Terminating child processes with SIGTERM")
    logger.debug(&"Waiting up to {sigTermDelay} seconds for the kernel to deliver signals")
    discard posix.kill(-1, SIGTERM)  # The kernel handles this for us asynchronously
    var t = cpuTime()
    # We wait some time for the signals to propagate
    while anyUserlandProcessLeft() or cpuTime() - t >= sigTermDelay:
        sleep(int(0.25 * 1000))
    if anyUserlandProcessLeft():
        logger.info("Terminating child processes with SIGKILL")
        discard posix.kill(-1, SIGKILL)
    logger.warning("Shutdown procedure complete, sending final termination signal")
    quit(code)
