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
import segfaults   # Makes us catch segfaults as NilAccessDefect exceptions!
import strformat
import os


import ../util/[logging, disks, misc]


proc mainLoop*(logger: Logger, mountDisks: bool = true, fstab: string = "/etc/fstab") =
    ## NimD's main execution loop
    try:
        addShutdownHandler(unmountAllDisks, logger)
        if mountDisks:
            logger.info("Mounting filesystem")
            logger.info("Mounting virtual disks")
            mountVirtualDisks(logger)
            logger.info("Mounting real disks")
            mountRealDisks(logger, fstab)
        else:
            logger.info("Skipping disk mounting, did we restart after a critical error?")
    except:
        logger.fatal(&"A fatal error has occurred while preparing filesystem, booting cannot continue. Error -> {getCurrentExceptionMsg()}")
        nimDExit(logger, 131)
    logger.info("Disks mounted")
    logger.info("Processing boot runlevel")
    # TODO
    logger.info("Processing default runlevel")
    # TODO
    logger.info("System initialization complete, going idle")
    while true:
        try:
            # TODO
            sleepSeconds(5)
        except CtrlCException:
            logger.warning("Main process received SIGINT: exiting")
            nimDExit(logger, 130)  # 130 - Interrupted by SIGINT
        except:
            logger.critical(&"A critical error has occurred while running, restarting the mainloop! Error -> {getCurrentExceptionMsg()}")
            # We *absolutely* cannot die
            mainLoop(logger, mountDisks=false)
