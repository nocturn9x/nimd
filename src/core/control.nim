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
import posix
import strformat
import shutdown


import ../util/logging


proc initControlSocket*(logger: Logger, path: string = "/var/run/nimd.sock"): Socket =
    ## Initializes NimD's control socket (an unbuffered
    ## TCP Unix Domain Socket) binding it to the given
    ## path (defaults to /var/run/nimd.sock). The socket's
    ## permissions are set to 700 so that only root can read
    ## from it
    try:
        logger.info(&"Initializing control socket at '{path}'")
        if fileExists(path):
            removeFile(path)
        elif dirExists(path):
            removeDir(path)
        result = newSocket(net.AF_UNIX, net.SOCK_STREAM, net.IPPROTO_IP, buffered=false)
        bindUnix(result, path)
        if posix.chmod(cstring(splitPath(path).head), 700) == -1:
            logger.error(&"Could not restrict access to unix socket at '{path}: {posix.strerror(posix.errno)}'")
            nimDExit(logger, code=int(posix.errno))
    except OSError:
        logger.error(&"Error when binding unix socket at '{path}': {getCurrentExceptionMsg()}")
        nimDExit(logger, code=int(osLastError()))