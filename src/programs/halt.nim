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


when isMainModule:
    var sock = newSocket(AF_UNIX, SOCK_STREAM, IPPROTO_IP)
    try:
        sock.connectUnix("/var/run/nimd.sock")
    except OSError:
        echo &"Communication with NimD control socket failed: {osErrorMsg(osLastError())}"
        quit(int(osLastError()))
    if sock.trySend("h"):
        echo "Halting"
    else:
        echo &"Communication with NimD control socket failed: {osErrorMsg(osLastError())}"
    sock.close()
