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
import net


import ../util/[logging, misc, config]
import services
import control
import shutdown



proc mainLoop*(logger: Logger, config: NimDConfig, startServices: bool = true) =
    ## NimD's main execution loop
    if startServices:
        logger.info("Processing default runlevel")
        startServices(logger, workers=config.workers, level=Default)
    logger.debug(&"Unblocking signals")
    unblockSignals(logger)
    logger.info("System initialization complete, idling on control socket")
    var opType: string
    try:
        logger.trace("Calling initControlSocket()")
        var serverSocket = initControlSocket(logger, config.sock)
        serverSocket.listen(5)
        var clientSocket = newSocket(AF_INET, SOCK_STREAM, IPPROTO_TCP)
        logger.switchToFile()
        logger.debug("Entering accept() loop")
        while true:
            serverSocket.accept(clientSocket)
            logger.debug(&"Received connection on control socket")
            if clientSocket.recv(opType, size=1) == 0:
                logger.debug(&"Client has disconnected, waiting for new connections")
                continue
            logger.debug(&"Received operation type '{opType}' via control socket")
            # The operation type is a single byte:
            # - 'p' -> poweroff
            # - 'r' -> reboot
            # - 'h' -> halt
            # - 's' -> Services-related operations (start, stop, get status, etc.)
            # - 'l' -> Reload in-memory configuration
            # - 'c' -> Check NimD status (returns "1" if up)
            case opType:
                of "p":
                    logger.info("Received shutdown request")
                    shutdown(logger)
                of "r":
                    logger.info("Received reboot request")
                    reboot(logger)
                of "h":
                    logger.info("Received halt request")
                    halt(logger)
                of "s":
                    logger.info("Received service-related request")
                    # TODO: Operate on services
                of "l":
                    logger.info("Received reload request")
                    mainLoop(logger, parseConfig(logger, "/etc/nimd/nimd.conf"), startServices=false)
                of "c":
                    logger.info("Received check request, responding")
                    clientSocket.send("1")
                else:
                    logger.warning(&"Received unknown operation type '{opType}' via control socket, ignoring it")
                    discard
            clientSocket.close()
    except:
        logger.critical(&"A critical error has occurred while running, restarting the mainloop in {config.restartDelay} seconds! Error -> {getCurrentExceptionMsg()}")
        sleepSeconds(config.restartDelay)
        # We *absolutely* cannot die
        mainLoop(logger, config, startServices=false)
