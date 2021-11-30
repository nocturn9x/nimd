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
import strutils
import sequtils


proc parseFileSystemTable*(fstab: string): seq[tuple[source: cstring, target: cstring, filesystemtype: cstring, mountflags: culong, data: cstring]] =
    ## Parses the contents of the given file (the contents of /etc/fstab) 
    ## and returns a sequence of tuples with elements source, target, 
    ## filesystemtype, mountflags and data as required by mount in sys/mount.h
    ## which is wrapped below. An improperly formatted fstab will cause this
    ## function to error out with an IndexDefect exception (when an fstab entry is
    ## incomplete) that should be caught by the caller. No other checks other than
    ## very basic syntax are performed, as that job is delegated to the operating
    ## system.
    var temp: seq[string] = @[]
    var line: string
    for l in fstab.splitlines():
        if l.strip().startswith("#"):
            continue
        if l.strip().len() == 0:
            continue
        line = l.filterIt(it != ' ').join("")
        temp = line.split(maxsplit=6)
        result.add((source: cstring(temp[0]), target: cstring(temp[1]), filesystemtype: cstring(temp[2]), mountflags: culong(0), data: cstring(temp[3])))


proc mount*(source: cstring, target: cstring, filesystemtype: cstring,
           mountflags: culong, data: pointer): cint {.header: "sys/mount.h", importc.}
