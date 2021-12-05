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
import os


import ../util/[logging, misc]
import services



proc mainLoop*(logger: Logger) =
    ## NimD's main execution loop
    logger.info("Processing default runlevel")
    startServices(logger, workers=1, level=Default)
    logger.debug(&"Unblocking signals")
    unblockSignals(logger)
    logger.info("System initialization complete, going idle")
    logger.switchToFile()
    try:
        discard execShellCmd("/bin/login -f root")  # TODO: Use a service
        while true:
            sleepSeconds(30)
    except:
        logger.critical(&"A critical error has occurred while running, restarting the mainloop in 30 seconds! Error -> {getCurrentExceptionMsg()}")
        sleepSeconds(30)
        # We *absolutely* cannot die
        mainLoop(logger)
