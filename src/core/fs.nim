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

import ../util/[logging, misc, cffi]
import shutdown



## Our Nim API
type
    Directory* = ref object
        path: string
        permissions: uint64
    Symlink* = ref object
        ## A symbolic link
        source: string
        dest: string
    Filesystem* = ref object
        ## A filesystem
        ## (real or virtual)
        source: string
        target: string
        fstype: string
        mountflags: uint64
        data: string
        dump: uint8
        pass: uint8
        virtual: bool   # Is this a virtual filesystem?


proc newFilesystem*(source, target, fstype: string, mountflags: uint64 = 0, data: string = "", dump: uint8 = 0, pass: uint8 = 0, virtual: bool = false): Filesystem =
    ## Initializes a new filesystem object
    result = Filesystem(source: source, target: target, fstype: fstype, mountflags: mountflags, data: data, dump: dump, pass: pass, virtual: virtual)


proc newSymlink*(source, dest: string): Symlink =
    ## Initializes a new symlink object
    result = Symlink(source: source, dest: dest)


proc newDirectory*(path: string, permissions: uint64): Directory =
    ## Initializes a new directory object
    result = Directory(path: path, permissions: permissions)


# Stores filesystem entries to be mounted upon boot. You could do this with a oneshot
# service, but it's a simple enough feature to have it built-in into the init itself, 
# especially since it makes error handling a heck of a lot easier.
# Note this has to be used only for stuff that's not already in /etc/fstab, like virtual
# filesystems (/proc, /sys, etc) if your kernel doesn't already mount them upon startup
# (which it most likely does)
var fileSystems: seq[Filesystem] = @[]
# Since creating symlinks is a pretty typical operation for an init, NimD
# provides a straightforward way to create them on boot without creating
# full fledged oneshot services 
var symlinks: seq[Symlink ] = @[]
# Stores directories to be created on boot. Again, this is achievable trough oneshots,
# but having a builtin API is a nice option IMHO
var directories: seq[Directory] = @[]


proc addFS*(filesystem: FileSystem) =
    ## Adds a filesystem to be mounted upon boot
    filesystems.add(filesystem)


proc removeFS*(filesystem: Filesystem) =
    ## Unregisters a filesystem. Note
    ## this has no effect if executed after
    ## the filesystems have been mounted (i.e. after
    ## a call to mountDisks)
    for i, f in filesystems:
        if f == filesystem:
            filesystems.del(i)


iterator getAllFSPaths: string =
    ## Yields all of the mount points of
    ## the currently registered
    ## filesystems
    for fs in filesystems:
        yield fs.target


iterator getAllFSNames: string =
    ## This is similar to what
    ## getAllVFSPaths does, except
    ## it yields the VFS' source
    ## instead of the mount point 
    ## (which in this case is just
    ## an alias, hence the "names" part)
    for fs in filesystems:
        yield fs.source


proc addSymlink*(symlink: Symlink) =
    ## Adds a symlink to be created
    ## upon boot (check createSymlinks)
    symlinks.add(symlink)


proc removeSymlink*(symlink: Symlink) =
    ## Removes a symlink. This has no
    ## effect after createSymlinks has
    ## been executed
    for i, sym in symlinks:
        if sym == symlink:
            symlinks.del(i)


proc addDirectory*(directory: Directory) =
    ## Adds a directory to be created upon
    ## boot (check createDirectories)
    directories.add(directory)


proc removeDirectory*(directory: Directory) =
    ## Removes a directory. This has no
    ## effect after createDirectories has
    ## been executed
    for i, dir in directories:
        if dir == directory:
            directories.del(i)


proc parseFileSystemTable*(fstab: string): seq[Filesystem] =
    ## Parses the contents of the given filesystem table and returns a list of Filesystem objects.
    ## An improperly formatted or semantically invalid fstab will cause this function to 
    ## error out with a ValueError exception that should be caught by the caller.
    ## No other checks other than very basic syntax are performed, as that job
    ## is delegated to the operating system. Missing dump/pass entries are interpreted
    ## as if they were set to 0, following the way Linux does it. Note that this function
    ## automatically converts UUID/LABEL/PARTUUID/ID directives to their corresponding
    ## /dev/disk/by-XXX/YYY symlink just like the mount command would do on a Linux system.
    var temp: seq[string] = @[]
    var dump: int
    var pass: int
    var line: string = ""
    var s: seq[string] = @[]
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
        if pass < 0:
            raise newException(ValueError, &"invalid value in filesystem table -> invalid value ({pass}) for pass")
        s = temp[0].split("=", maxsplit=2)
        if temp[0].toLowerAscii().startswith("id="):
            if len(s) < 2:
                raise newException(ValueError, "improperly formatted filesystem table")
            temp[0] = &"""/dev/disk/by-id/{s[1]}"""
        if temp[0].toLowerAscii().startswith("label="):
            if len(s) < 2:
                raise newException(ValueError, "improperly formatted filesystem table")
            temp[0] = &"""/dev/disk/by-label/{s[1]}"""
        if temp[0].toLowerAscii().startswith("uuid="):
            if len(s) < 2:
                raise newException(ValueError, "improperly formatted filesystem table")
            temp[0] = &"""/dev/disk/by-uuid/{s[1]}"""
        if temp[0].toLowerAscii().startswith("partuuid="):
            if len(s) < 2:
                raise newException(ValueError, "improperly formatted filesystem table")
            temp[0] = &"""/dev/disk/by-partuuid/{s[1]}"""
        result.add(newFilesystem(source=temp[0], target=temp[1], fstype=temp[2], mountflags=0u64, data=temp[3], dump=uint8(dump), pass=uint8(pass)))


proc checkDiskIsMounted(search: Filesystem, expand: bool = false): bool =
    ## Returns true if a disk is already mounted. If expand is true,
    ## symlinks are expanded and checked instead of doing a simple
    ## string comparison of the source entry point. This should be
    ## true when mounting real filesystems. Returns false if
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


proc mountDisks*(logger: Logger, fstab: string = "/etc/fstab") =
    ## Mounts disks from /etc/fstab as well as the ones registered
    ## via addFS (these are mounted first)
    var retcode = 0
    try:
        logger.debug(&"Reading disk entries from {fstab} (mounting custom filesystems first!)")
        for entry in filesystems & parseFileSystemTable(readFile(fstab)):
            if checkDiskIsMounted(entry, expand=true):
                logger.debug(&"Skipping mounting filesystem {entry.source} ({entry.fstype}) at {entry.target}: already mounted")
                continue
            logger.debug(&"Mounting filesystem {entry.source} ({entry.fstype}) at {entry.target} with mount option(s) {entry.data}")
            logger.trace(&"Calling mount('{entry.source}', '{entry.target}', '{entry.fstype}', {entry.mountflags}, '{entry.data}')")
            retcode = mount(entry.source, entry.target, entry.fstype, entry.mountflags, entry.data)
            logger.trace(&"mount('{entry.source}', '{entry.target}', '{entry.fstype}', {entry.mountflags}, '{entry.data}') returned {retcode}")
            if retcode == -1:
                logger.error(&"Mounting {entry.source} at {entry.target} has failed with error {posix.errno}: {posix.strerror(posix.errno)}")
                # Resets the error code
                posix.errno = cint(0)
            else:
                logger.debug(&"Mounted {entry.source} at {entry.target}")
    except ValueError:  # Check parseFileSystemTable for more info on this catch block
        logger.fatal("Improperly formatted fstab, exiting")
        nimDExit(logger, 131)


proc unmountAllDisks*(logger: Logger, code: int) =
    ## Unmounts all currently mounted disks, including the ones that
    ## were not mounted trough fstab but excluding virtual filesystems
    var isVFS: bool = false
    var retcode = 0
    try:
        logger.info("Detaching real filesystems")
        logger.debug(&"Reading disk entries from /proc/mounts")
        for entry in parseFileSystemTable(readFile("/proc/mounts")):
            # We don't detach the virtual filesystems because they are a software-level abstraction
            # that exists purely in memory, and unmounting them while keeping the system stable during 
            # shutdown is a headache I don't wanna deal with.
            # All of these checks seem excessive, but they make absolutely sure we don't unmount them,
            # as they are critical system components (especially /proc): maybe we should use stat()
            # instead and make a generic check, but adding a system call into the mix seems overkill given
            # we alredy have all the info we need
            if entry.virtual:
                # Detects VFS manually
                continue
            for source in getAllFSNames():
                # Detects VFS by name
                if entry.source == source:
                    isVFS = true
                    break
            for path in getAllFSPaths():
                # Detects VFS by mount point
                if entry.target.startswith(path):
                    isVFS = true
                    break
            if isVFS:
                isVFS = false
                logger.trace(&"Skipping unmounting filesystem {entry.source} ({entry.fstype}) from {entry.target} as it is a virtual filesystem")
                continue
            if not checkDiskIsMounted(entry):
                logger.trace(&"Skipping unmounting filesystem {entry.source} ({entry.fstype}) from {entry.target}: not mounted")
                continue
            logger.debug(&"Unmounting filesystem {entry.source} ({entry.fstype}) from {entry.target}")
            logger.trace(&"Calling umount2('{entry.source}', MNT_DETACH)")
            retcode = umount2(entry.source, 2)   # 2 = MNT_DETACH - Since we're shutting down, we need the disks to be *gone*!
            logger.trace(&"umount2('{entry.source}', MNT_DETACH) returned {retcode}")
            if retcode == -1:
                logger.error(&"Unmounting disk {entry.source} from {entry.target} has failed with error {posix.errno}: {posix.strerror(posix.errno)}")
                # Resets the error code
                posix.errno = cint(0)
            else:
                logger.debug(&"Unmounted {entry.source} from {entry.target}")
    except ValueError:  # Check parseFileSystemTable for more info on this catch block
        logger.fatal(&"A fatal error occurred while unmounting disks: {getCurrentExceptionMsg()}")
        nimDExit(logger, 131)


proc createSymlinks*(logger: Logger) =
    ## Creates a set of symlinks needed
    ## by stuff like Linux ports of BSD
    ## software. Non-existing directories
    ## are created until the path to the
    ## symlink is valid. Already existing
    ## sources and non-existent destinations
    ## cause the symlink creation to be skipped
    for sym in symlinks:
        try:
            if not exists(sym.source):
                logger.warning(&"Skipping creation of symbolic link from {sym.dest} to {sym.source}: destination does not exist")
                continue
            elif exists(sym.dest):
                if symlinkExists(sym.dest) and sameFile(expandSymlink(sym.dest), sym.source):
                    logger.debug(&"Skipping creation of symbolic link from {sym.dest} to {sym.source}: link already exists")
                elif symlinkExists(sym.dest) and not sameFile(expandSymlink(sym.dest), sym.source):
                    logger.warning(&"Attempted to create symbolic link from {sym.dest} to {sym.source}, but link already exists and points to {expandSymlink(sym.dest)}")
                else:
                    logger.warning(&"Attempted to create symbolic link from {sym.dest} to {sym.source}, but destination already exists and is not a symlink")
                continue
            logger.debug(&"Creating symbolic link from {sym.dest} to {sym.source}")
            createDir(sym.dest.splitPath().head)
            createSymlink(sym.source, sym.dest)
        except:
            logger.error(&"Failed to create symbolic link from {sym.dest} to {sym.source}: {getCurrentExceptionMsg()}")


proc createDirectories*(logger: Logger) =
    ## Creates standard directories that
    ## Linux software expects to be present.
    ## Note that this has to run after the
    ## filesystem has been initialized.
    ## If a chmod binary is found, it is used
    ## to set directory permissions as specified
    ## in their config. Note that the entire path
    ## of the directory is created if it does not 
    ## exist yet
    var hasChmod = true
    try:
        if findExe("chmod").isEmptyOrWhitespace():
            logger.warning("Could not find chmod binary, directory permissions will default to OS configuration")
            hasChmod = false
    except:
      logger.error(&"Failed to search for chmod binary, directory permissions will default to OS configuration: {getCurrentExceptionMsg()}")
      hasChmod = false
    for dir in directories:
        try:
            if exists(dir.path):
                if dirExists(dir.path):
                    logger.warning(&"Creation of directory {dir.path} skipped: directory already exists")
                elif fileExists(dir.path):
                    logger.warning(&"Creation of directory {dir.path} skipped: path is a file")
                elif symlinkExists(dir.path):
                    logger.warning(&"Creation of directory {dir.path} skipped: path is a symlink to {expandSymlink(dir.path)}")
                else:
                    # Catch-all
                    logger.warning(&"Creation of directory {dir.path} skipped: destination already exists")
            else:
                createDir(dir.path)
                logger.debug(&"Created new directory at {dir.path}")
                if hasChmod:
                    logger.debug(&"Setting permissions to {dir.permissions} for {dir.path}")
                    if (let code = execShellCmd(&"chmod -R {dir.permissions} {dir.path}"); code) != 0:
                        logger.warning(&"Command 'chmod -R {dir.permissions} {dir.path}' exited non-zero status code {code}")
        except:
            logger.error(&"Failed to create directory at {dir.path}: {getCurrentExceptionMsg()}")
