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
    (source: cstring("proc"), target: cstring("/proc"), filesystemtype: cstring("procfs"), mountflags: culong(0), data: cstring("nosuid,noexec,nodev")),
    (source: cstring("sys"), target: cstring("/sys"), filesystemtype: cstring("sysfs"), mountflags: culong(0), data: cstring("nosuid,noexec,nodev")),
    (source: cstring("run"), target: cstring("/run"), filesystemtype: cstring("tmpfs"), mountflags: culong(0), data: cstring("mode=0755,nosuid,nodev")),
    (source: cstring("dev"), target: cstring("/dev"), filesystemtype: cstring("devtmpfs"), mountflags: culong(0), data: cstring("mode=0755,nosuid")),
    (source: cstring("devpts"), target: cstring("/dev/pts"), filesystemtype: cstring("devpts"), mountflags: culong(0), data: cstring("mode=0620,gid=5,nosuid,noexec")),
    (source: cstring("shm"), target: cstring("/dev/shm"), filesystemtype: cstring("tmpfs"), mountflags: culong(0), data: cstring("mode=1777,nosuid,nodev")),

]

proc parseFileSystemTable*(fstab: string): seq[tuple[source: cstring, target: cstring, filesystemtype: cstring, mountflags: culong, data: cstring]] =
    ## Parses the contents of the given file (the contents of /etc/fstab or /etc/mtab
    ## most of the time, but this is not enforced in any way) and returns a sequence 
    ## of tuples with elements source, target, filesystemtype, mountflags and data
    ## as required by mount/umount/umount2 in sys/mount.h which is wrapped below. 
    ## An improperly formatted fstab will cause this function to error out with an 
    ## IndexDefect exception (when an entry is incomplete) that should be caught by 
    ## the caller. No other checks other than very basic syntax are performed, as 
    ## that job is delegated to the operating system.
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
        echo result[^1]

# Nim wrappers around C functionality in sys/mount.h on Linux
proc mount*(source: cstring, target: cstring, filesystemtype: cstring,
            mountflags: culong, data: pointer): cint {.header: "sys/mount.h", importc.}
proc umount*(target: cstring): cint {.header: "sys/mount.h", importc.}
proc umount2*(target: cstring, flags: cint): cint {.header: "sys/mount.h", importc.}


proc mountRealDisks*(logger: Logger, fstab: string = "/etc/fstab") =
    ## Mounts real disks from /etc/fstab
    try:
        logger.info(&"Reading disk entries from {fstab}")
        for entry in parseFileSystemTable(readFile(fstab)):
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
        logger.fatal("Improperly formatted fstab, exiting")
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


proc unmountAllDisks*(logger: Logger, code: int) =
    ## Unmounts all currently mounted disks, including the ones that
    ## were not mounted trough fstab and virtual filesystems
    
    try:
        logger.info(&"Reading disk entries from /proc/mounts")
        for entry in parseFileSystemTable(readFile("/proc/mounts")):
            echo entry
            logger.debug(&"Unmounting filesystem {entry.source} ({entry.filesystemtype}) from {entry.target}")
            logger.trace(&"Calling umount({entry.source})")
            var retcode = umount(entry.source)
            logger.trace(&"umount({entry.source}) returned {retcode}")
            if retcode == -1:
                logger.error(&"Unmounting disk {entry.source} has failed with error {posix.errno}: {posix.strerror(posix.errno)}")
                # Resets the error code
                posix.errno = cint(0)
            else:
                logger.debug(&"Unmounted {entry.source} from {entry.target}")
    except IndexDefect:  # Check parseFileSystemTable for more info on this catch block
        logger.fatal("Improperly formatted /etc/mtab, exiting")
        nimDExit(logger, 131)