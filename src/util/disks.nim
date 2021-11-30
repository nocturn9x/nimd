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
import strformat
import posix

import logging
import misc

const virtualFileSystems: seq[tuple[source: cstring, target: cstring, filesystemtype: cstring, mountflags: culong, data: cstring]] = @[
    (source: cstring("proc"), target: cstring("/proc"), filesystemtype: cstring("proc"), mountflags: culong(0), data: cstring("nosuid,noexec,nodev")),
    (source: cstring("sys"), target: cstring("/sys"), filesystemtype: cstring("sysfs"), mountflags: culong(0), data: cstring("nosuid,noexec,nodev")),
    (source: cstring("run"), target: cstring("/run"), filesystemtype: cstring("tmpfs"), mountflags: culong(0), data: cstring("mode=0755,nosuid,nodev")),
    (source: cstring("dev"), target: cstring("/dev"), filesystemtype: cstring("devtmpfs"), mountflags: culong(0), data: cstring("mode=0755,nosuid")),
    (source: cstring("devpts"), target: cstring("/dev/pts"), filesystemtype: cstring("devpts"), mountflags: culong(0), data: cstring("mode=0620,gid=5,nosuid,noexec")),
    (source: cstring("shm"), target: cstring("/dev/shm"), filesystemtype: cstring("tmpfs"), mountflags: culong(0), data: cstring("mode=1777,nosuid,nodev")),

]

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
    var line: string = ""
    for l in fstab.splitlines():
        line = l.strip().replace("\t", " ")
        if line.startswith("#"):
            continue
        if line.isEmptyOrWhitespace():
            continue
        # This madness will make sure we only get (hopefully) 6 entries
        # in our temporary list
        temp = line.split().filterIt(it != "").join(" ").split(maxsplit=6)
        result.add((source: cstring(temp[0]), target: cstring(temp[1]), filesystemtype: cstring(temp[2]), mountflags: culong(0), data: cstring(temp[3])))


proc mount*(source: cstring, target: cstring, filesystemtype: cstring,
           mountflags: culong, data: pointer): cint {.header: "sys/mount.h", importc.}


proc mountRealDisks*(logger: Logger) =
    ## Mounts real disks from /etc/fstab
    try:
        logger.info("Reading disk entries from /etc/fstab")
        for entry in parseFileSystemTable(readFile("/etc/fstab")):
            logger.debug(&"Mounting filesystem {entry.source} ({entry.filesystemtype}) at {entry.target} with mount option(s) {entry.data}")
            logger.trace(&"Calling mount({entry.source}, {entry.target}, {entry.filesystemtype}, {entry.mountflags}, {entry.data})")
            var retcode = mount(entry.source, entry.target, entry.filesystemtype, entry.mountflags, entry.data)
            logger.trace(&"mount({entry.source}, {entry.target}, {entry.filesystemtype}, {entry.mountflags}, {entry.data}) returned {retcode}")
            if retcode == -1:
                logger.error(&"Mounting disk {entry.source} has failed with error {posix.errno}: {posix.strerror(posix.errno)}")
                # Resets the error code
                posix.errno = cint(0)
            else:
                logger.debug(&"Mounted {entry.source} at {entry.target}")
    except IndexDefect:  # Check parseFileSystemTable for more info on this catch block
        logger.fatal("Improperly formatted /etc/fstab, exiting")
        nimDExit(logger, 131)


proc mountVirtualDisks*(logger: Logger) =
    ## Mounts POSIX virtual filesystems/partitions,
    ## such as /proc and /sys
    for entry in virtualFileSystems:
        logger.debug(&"Mounting filesystem {entry.source} ({entry.filesystemtype}) at {entry.target} with mount option(s) {entry.data}")
        logger.trace(&"Calling mount({entry.source}, {entry.target}, {entry.filesystemtype}, {entry.mountflags}, {entry.data})")
        var retcode = mount(entry.source, entry.target, entry.filesystemtype, entry.mountflags, entry.data)
        logger.trace(&"mount({entry.source}, {entry.target}, {entry.filesystemtype}, {entry.mountflags}, {entry.data}) returned {retcode}")
        if retcode == -1:
            logger.error(&"Mounting disk {entry.source} has failed with error {posix.errno}: {posix.strerror(posix.errno)}")
            # Resets the error code
            posix.errno = cint(0)
            logger.fatal("Failed mounting vital system disk partition, system is likely corrupted, booting cannot continue")
            nimDExit(logger, 131) # ENOTRECOVERABLE - State not recoverable
        else:
            logger.debug(&"Mounted {entry.source} at {entry.target}")