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


import ../util/[logging, misc]
import services
import control
import shutdown



proc mainLoop*(logger: Logger) =
    ## NimD's main execution loop
    logger.info("Processing default runlevel")
    startServices(logger, workers=1, level=Default)
    logger.debug(&"Unblocking signals")
    unblockSignals(logger)
    logger.info("System initialization complete, going idle")
    var opType: string
    try:
        logger.trace("Calling initControlSocket()")
        var serverSocket = initControlSocket(logger)
        serverSocket.listen(5)
        var clientSocket = newSocket(AF_INET, SOCK_STREAM, IPPROTO_TCP)
        # logger.switchToFile()
        while true:
            serverSocket.accept(clientSocket)
            if clientSocket.recv(opType, size=1) == 0:
                logger.debug(&"Client has disconnected, waiting for new connection")
                continue
            logger.debug(&"Received operation type '{opType}' via control socket")
            # The operation type is a single byte:
            # - 'p' -> poweroff
            # - 'r' -> reboot
            # - 'h' -> halt
            # - 's' -> Services-related operations (start, stop, get status, etc.)
            case opType:
                of "":
                    logger.debug(&"Empty read from control socket: did the client disconnect?")
                    continue
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
                    discard  # TODO
                else:
                    logger.warning(&"Received unknown operation type '{opType}' via control socket, ignoring it")
                    discard
            clientSocket.close()
    except:
        logger.critical(&"A critical error has occurred while running, restarting the mainloop in 30 seconds! Error -> {getCurrentExceptionMsg()}")
        sleepSeconds(30)
        # We *absolutely* cannot die
        mainLoop(logger)
