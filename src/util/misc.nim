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

import logging



proc nimDExit*(logger: Logger, code: int) =
    logger.warning("The system is being shut down, beginning child process termination")
    # TODO
    logger.info("Processing shutdown runlevel")
    # TODO
    logger.warning("Process termination complete, sending final shutdown signal")
    # TODO
    quit(code)


proc sleepSeconds*(amount: SomeInteger) = sleep(amount * 1000)


proc handleControlC* {.noconv.} =
    getDefaultLogger().warning("Main process received SIGINT: exiting")  # TODO: Call exit point
    nimDExit(getDefaultLogger(), 130)  # Exit code 130 indicates a SIGINT