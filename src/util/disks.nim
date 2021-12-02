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
import os

import logging
import misc


const virtualFileSystems: array[6, tuple[source: string, target: string, filesystemtype: string, mountflags: uint64, data: string, dump, pass: uint8]] = [
    # ALl the standard POSIX filesystems needed by the OS to work properly are listed here
    (source: "proc", target: "/proc", filesystemtype: "proc", mountflags: 0u64, data: "nosuid,noexec,nodev", dump: 0u8, pass: 0u8),
    (source: "sys", target: "/sys", filesystemtype: "sysfs", mountflags: 0u64, data: "nosuid,noexec,nodev", dump: 0u8, pass: 0u8),
    (source: "run", target: "/run", filesystemtype: "tmpfs", mountflags: 0u64, data: "mode=0755,nosuid,nodev", dump: 0u8, pass: 0u8),
    (source: "dev", target: "/dev", filesystemtype: "devtmpfs", mountflags: 0u64, data: "mode=0755,nosuid", dump: 0u8, pass: 0u8),
    (source: "devpts", target: "/dev/pts", filesystemtype: "devpts", mountflags: 0u64, data: "mode=0620,gid=5,nosuid,noexec", dump: 0u8, pass: 0u8),
    (source: "shm", target: "/dev/shm", filesystemtype: "tmpfs", mountflags: 0u64, data: "mode=1777,nosuid,nodev", dump: 0u8, pass: 0u8),
]


proc parseFileSystemTable*(fstab: string): seq[tuple[source, target, filesystemtype: string, mountflags: uint64, data: string, dump, pass: uint8]] =
    ## Parses the contents of the given file (the contents of /etc/fstab or /etc/mtab
    ## most of the time, but this is not enforced in any way) and returns a sequence 
    ## of tuples with elements source, target, filesystemtype, mountflags, data, dump
    ## and pass as required by mount/umount/umount2 in sys/mount.h which are wrapped below. 
    ## The types of these arguments are Nim types to make the garbage collector happy
    ## and avoid freeing the underlying string object.
    ## An improperly formatted fstab will cause this function to error out with a 
    ## ValueError exception (when an entry is incomplete) that should be caught by 
    ## the caller. No other checks other than very basic syntax are performed, as 
    ## that job is delegated to the operating system. Missing dump/pass entries are
    ## interpreted as if they were set to 0, following the way Linux does it.
    ## Note that this function automatically converts UUID/LABEL/PARTUUID/ID directives
    ## to their corresponding /dev/disk symlink just like the mount command would do 
    ## on a Linux system.
    var temp: seq[string] = @[]
    var dump: int
    var pass: int
    var line: string = ""
    for l in fstab.splitlines():
        line = l.strip().replace("\t", " ")
        if line.startswith("#") or line.isEmptyOrWhitespace():
            continue
        # This madness will make sure we only get (hopefully) 6 entries
        # in our temporary list
        temp = line.split().filterIt(it != "").join(" ").split(maxsplit=6)
        if len(temp) < 6:
            if len(temp) < 4:
                # Not enough columns!
                raise newException(ValueError, "improperly formatted filesystem table")
            elif len(temp) == 4:
                dump = 0
                pass = 0
            elif len(temp) == 5:
                dump = 0
        else:
            try:
                dump = parseInt(temp[4])
            except ValueError:
                raise newException(ValueError, &"improperly formatted filesystem table -> invalid value ({dump}) for dump")
            try:
                pass = parseInt(temp[5])
            except ValueError:
                raise newException(ValueError, &"improperly formatted filesystem table -> invalid value ({pass}) for pass")
        if dump notin 0..1:
            raise newException(ValueError, &"invalid value in filesystem table -> invalid value ({dump}) for dump")
        if pass notin 0..2:
            raise newException(ValueError, &"invalid value in filesystem table -> invalid value ({pass}) for pass")
        if temp[0].toLowerAscii().startswith("id="):
            if (let s = temp[0].split("=", maxsplit=2); len(s) < 2):
                raise newException(ValueError, "improperly formatted filesystem table")
            temp[0] = &"""/dev/disk/by-id/{temp[0].split("=", maxsplit=2)[1]}"""
        if temp[0].toLowerAscii().startswith("label="):
            if (let s = temp[0].split("=", maxsplit=2); len(s) < 2):
                raise newException(ValueError, "improperly formatted filesystem table")
            temp[0] = &"""/dev/disk/by-label/{temp[0].split("=", maxsplit=2)[1]}"""
        if temp[0].toLowerAscii().startswith("uuid="):
            if (let s = temp[0].split("=", maxsplit=2); len(s) < 2):
                raise newException(ValueError, "improperly formatted filesystem table")
            temp[0] = &"""/dev/disk/by-uuid/{temp[0].split("=", maxsplit=2)[1]}"""
        if temp[0].toLowerAscii().startswith("partuuid="):
            if (let s = temp[0].split("=", maxsplit=2); len(s) < 2):
                raise newException(ValueError, "improperly formatted filesystem table")
            temp[0] = &"""/dev/disk/by-partuuid/{temp[0].split("=", maxsplit=2)[1]}"""
        result.add((source: temp[0], target: temp[1], filesystemtype: temp[2], mountflags: 0u64, data: temp[3], dump: uint8(dump), pass: uint8(pass)))


# Nim wrappers around C functionality in sys/mount.h on Linux
proc mount*(source: cstring, target: cstring, filesystemtype: cstring,
            mountflags: culong, data: pointer): cint {.header: "sys/mount.h", importc.}
# Since cstrings are weak references, we need to convert nim strings to cstrings only
# when we're ready to use them and only when we're sure the underlying nim string is
# in scope, otherwise garbage collection madness happens
proc mount*(source, target, filesystemtype: string, mountflags: uint64, data: string): int = int(mount(cstring(source), cstring(target), cstring(filesystemtype), culong(mountflags), cstring(data)))

proc umount*(target: cstring): cint {.header: "sys/mount.h", importc.}
proc umount2*(target: cstring, flags: cint): cint {.header: "sys/mount.h", importc.}
# These 2 wrappers silent the CStringConv warning 
# (implicit conversion to 'cstring' from a non-const location)
proc umount*(target: string): int = int(umount(cstring(target)))
proc umount2*(target: string, flags: int): int = int(umount2(cstring(target), cint(flags)))


proc exists(p: string): bool =
    # Checks if a path exists. Thanks
    # araq :)
    try:
        discard getFileInfo(p)
        result = true
    except OSError:
        result = false


proc checkDisksIsMounted(search: tuple[source, target, filesystemtype: string, mountflags: uint64, data: string, dump, pass: uint8], expand: bool = false): bool =
    ## Returns true if a disk is already mounted. If expand is true,
    ## symlinks are expanded and checked instead of doing a simple
    ## string comparison of the source entry point. This should be
    ## true when mounting real filesystems. This returns false if
    ## /proc/mounts does not exist (usually happens when /proc has
    ## not been mounted yet)
    if not fileExists("/proc/mounts"):
        return false
    for entry in parseFileSystemTable(readFile("/proc/mounts")):
        if expand:
                if exists(entry.source) and exists(search.source) and sameFile(entry.source, search.source):
                    return true
        elif entry.source == search.source:
            return true
    return false


proc mountRealDisks*(logger: Logger, fstab: string = "/etc/fstab") =
    ## Mounts real disks from /etc/fstab
    var retcode = 0
    try:
        logger.debug(&"Reading disk entries from {fstab}")
        for entry in parseFileSystemTable(readFile(fstab)):
            if checkDisksIsMounted(entry, expand=true):
                logger.debug(&"Skipping mounting filesystem {entry.source} ({entry.filesystemtype}) at {entry.target}: already mounted")
                continue
            logger.debug(&"Mounting filesystem {entry.source} ({entry.filesystemtype}) at {entry.target} with mount option(s) {entry.data}")
            logger.trace(&"Calling mount('{entry.source}', '{entry.target}', '{entry.filesystemtype}', {entry.mountflags}, '{entry.data}')")
            retcode = mount(entry.source, entry.target, entry.filesystemtype, entry.mountflags, entry.data)
            logger.trace(&"mount('{entry.source}', '{entry.target}', '{entry.filesystemtype}', {entry.mountflags}, '{entry.data}') returned {retcode}")
            if retcode == -1:
                logger.error(&"Mounting {entry.source} at {entry.target} has failed with error {posix.errno}: {posix.strerror(posix.errno)}")
                # Resets the error code
                posix.errno = cint(0)
            else:
                logger.debug(&"Mounted {entry.source} at {entry.target}")
    except ValueError:  # Check parseFileSystemTable for more info on this catch block
        logger.fatal("Improperly formatted fstab, exiting")
        nimDExit(logger, 131)


proc mountVirtualDisks*(logger: Logger) =
    ## Mounts POSIX virtual filesystems/partitions,
    ## such as /proc and /sys
    
    var retcode = 0
    for entry in virtualFileSystems:
        if checkDisksIsMounted(entry):
            logger.debug(&"Skipping mounting filesystem {entry.source} ({entry.filesystemtype}) at {entry.target}: already mounted")
            continue
        logger.debug(&"Mounting filesystem {entry.source} ({entry.filesystemtype}) at {entry.target} with mount option(s) {entry.data}")
        logger.trace(&"Calling mount('{entry.source}', '{entry.target}', '{entry.filesystemtype}', {entry.mountflags}, '{entry.data}')")
        retcode = mount(entry.source, entry.target, entry.filesystemtype, entry.mountflags, entry.data)
        logger.trace(&"mount('{entry.source}', '{entry.target}', '{entry.filesystemtype}', {entry.mountflags}, '{entry.data}') returned {retcode}")
        if retcode == -1:
            logger.error(&"Mounting disk {entry.source} at {entry.target} has failed with error {posix.errno}: {posix.strerror(posix.errno)}")
            # Resets the error code
            posix.errno = cint(0)
            logger.fatal("Failed mounting vital system disk partition, system is likely corrupted, booting cannot continue")
            nimDExit(logger, 131) # ENOTRECOVERABLE - State not recoverable
        else:
            logger.debug(&"Mounted {entry.source} at {entry.target}")


proc unmountAllDisks*(logger: Logger, code: int) =
    ## Unmounts all currently mounted disks, including the ones that
    ## were not mounted trough fstab but excluding virtual filesystems
    var flag: bool = false
    var retcode = 0
    try:
        logger.info("Detaching real filesystems")
        logger.debug(&"Reading disk entries from /proc/mounts")
        for entry in parseFileSystemTable(readFile("/proc/mounts")):
            if entry.source in ["proc", "sys", "run", "dev", "devpts", "shm"]:
                flag = true   # We don't detach the vfs
            for path in ["/proc", "/sys", "/run", "/dev", "/dev/pts", "/dev/shm"]:
                if entry.target.startswith(path):
                    flag = true
            if flag:
                flag = false
                logger.debug(&"Skipping unmounting filesystem {entry.source} ({entry.filesystemtype}) from {entry.target} as it is a virtual filesystem")
                continue
            if not checkDisksIsMounted(entry):
                logger.debug(&"Skipping unmounting filesystem {entry.source} ({entry.filesystemtype}) from {entry.target}: not mounted")
                continue
            logger.debug(&"Unmounting filesystem {entry.source} ({entry.filesystemtype}) from {entry.target}")
            logger.trace(&"Calling umount2('{entry.target}', MNT_DETACH)")
            var retcode = umount2(entry.target, 2)   # 2 = MNT_DETACH - Since we're shutting down, we need the disks to be *gone*!
            logger.trace(&"umount2('{entry.target}', MNT_DETACH) returned {retcode}")
            if retcode == -1:
                logger.error(&"Unmounting disk {entry.source} from {entry.target} has failed with error {posix.errno}: {posix.strerror(posix.errno)}")
                # Resets the error code
                posix.errno = cint(0)
            else:
                logger.debug(&"Unmounted {entry.source} from {entry.target}")
    except ValueError:  # Check parseFileSystemTable for more info on this catch block
        logger.fatal(&"A fatal error occurred while unmounting disks: {getCurrentExceptionMsg()}")
        nimDExit(logger, 131)
