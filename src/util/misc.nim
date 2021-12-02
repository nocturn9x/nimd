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


import logging

type CtrlCException* = object of CatchableError


var shutdownHandlers: seq[proc (logger: Logger, code: int)] = @[]


proc addShutdownHandler*(handler: proc (logger: Logger, code: int), logger: Logger) =
    shutdownHandlers.add(handler)


proc removeShutdownHandler*(handler: proc (logger: Logger, code: int)) =
    for i, h in shutdownHandlers:
        if h == handler:
            shutdownHandlers.delete(i)


proc nimDExit*(logger: Logger, code: int) =
    logger.warning("The system is being shut down!")
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
    logger.info("Terminating child processes with SIGINT")
    # TODO
    logger.info("Terminating child processes with SIGKILL")
    # TODO
    logger.warning("Shutdown procedure complete, sending final termination signal")
    # TODO
    quit(code)  # Replace with syscall(REBOOT, ...)


proc sleepSeconds*(amount: SomeInteger) = sleep(amount * 1000)


proc handleControlC* {.noconv.} =
    raise newException(CtrlCException, "Interrupted by Ctrl+C")
