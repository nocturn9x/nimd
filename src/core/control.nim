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
import net
import strformat
import shutdown


import ../util/logging
import ../util/misc


proc initControlSocket*(logger: Logger, path: string = "/var/run/nimd.sock"): Socket =
    ## Initializes NimD's control socket (an unbuffered
    ## TCP Unix Domain Socket) binding it to the given
    ## path (defaults to /var/run/nimd.sock)
    try:
        logger.info(&"Initializing control socket at '{path}'")
        if exists(path):
            removeFile(path)
        result = newSocket(AF_UNIX, SOCK_STREAM, IPPROTO_IP, buffered=false)
        bindUnix(result, path)
    except OSError:
        logger.error(&"Error when binding unix socket at '{path}': {getCurrentExceptionMsg()}")
        nimDExit(logger, code=int(osLastError()))