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

proc strsignal*(sig: cint): cstring {.header: "string.h", importc.}
proc dup3*(a1, a2, a3: cint): cint {.importc.}
# Nim wrappers around C functionality in sys/mount.h on Linux
proc mount*(source: cstring, target: cstring, fstype: cstring,
            mountflags: culong, data: pointer): cint {.header: "sys/mount.h", importc.}
# Since cstrings are weak references, we need to convert nim strings to cstrings only
# when we're ready to use them and only when we're sure the underlying nim string is
# in scope, otherwise garbage collection madness happens
proc mount*(source, target, fstype: string, mountflags: uint64, data: string): int = int(mount(cstring(source), cstring(target), cstring(fstype), culong(mountflags), cstring(data)))

proc umount*(target: cstring): cint {.header: "sys/mount.h", importc.}
proc umount2*(target: cstring, flags: cint): cint {.header: "sys/mount.h", importc.}
# These 2 wrappers silent the CStringConv warning 
# (implicit conversion to 'cstring' from a non-const location)
proc umount*(target: string): int = int(umount(cstring(target)))
proc umount2*(target: string, flags: int): int = int(umount2(cstring(target), cint(flags)))
