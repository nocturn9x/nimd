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
import posix
import os


import util/logger as log


const NimdVersion*: tuple[major, minor, patch: int] = (major: 0, minor: 0, patch: 1)


proc main(logger: Logger) = 
    ## NimD entry point
    logger.info(&"NimD version {NimdVersion.major}.{NimdVersion.minor}.{NimdVersion.patch} is starting up...")
    if posix.getuid() != 0:
        logger.error("NimD must run as root")
        quit(1)   # EPERM - Operation not permitted
    if (let pid = getCurrentProcessId(); pid) != 1:
        logger.warning(&"Expecting to run as PID 1, but current process ID is {pid}")
    

when isMainModule:
    var logger = getDefaultLogger()
    try:
        main(logger)
    except:
        logger.fatal(&"A fatal exception has occurred during startup and NimD cannot continue: {getCurrentExceptionMsg()}")
        quit(131)  # ENOTRECOVERABLE - State not recoverable
        # This will almost certainly cause the kernel to crash with an error the likes of "Kernel not syncing, attempted to kill init!",
        # but there isn't much we can do if we can't even initialize *ourselves*, after all, is there?