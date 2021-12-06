# Nim Daemon - An init system written in Nim
A minimal, self-contained, dependency-based Linux init system written in Nim.

## Note

The code in here is pretty bad: in fact, it's horrible (and it _barely_ works). I'm just messing around to get the basics done, sorry for that, 
but I need to get a proof of concept done before starting to do some actually sensible programming.

I mainly made this thing for fun and as an excuse to learn more about the mysterious PID 1 and the Linux kernel in general. If you are like me
and love getting your hands dirty, I truly recommend trying an endeavor like this as I haven't had this fun cobbling something together in a very
long time. Sometimes programming only large scale software is boring, go figure.

## Disclaimers & Functionality

This software is developed on a _"It works on my machine"_ basis. I don't perform any extensive testing: if this thing unmounts your
root partition while you're saving your precious family photos, I can't do much. I run an installation of Artix Linux (x86_64)
using the 5.15.5-artix1-1 linux kernel.

Also, NimD is developed **for Linux only**, as that's the kernel my OS uses: other kernels are not supported at all and NimD
**will** explode with fancy fireworks if you try to run it unmodified on other kernels (although probably things like BSD and Solaris
are not that hard to add support for using some `when defined()` clauses and changing what virtual filesystems NimD expects to mount).

NimD is not particularly secure. Actually it's probably very insecure by modern standards, but basic checks like making sure regular users
can't reboot the machine are (_actually_, will be) at least in place, so there's that I guess.

NimD assumes that the standard file descriptors 0, 1 and 2 (stdin, stdout and stderr respectively) are properly connected to /dev/console 
(which is something all modern versions of the Linux kernel do). I tried connecting them manually, but I was out of luck: if you happen to 
know how to check for a proper set of file descriptors and connect them manually, please make a PR, I'd love to hear how to do that.

When mounting the filesystem, NimD is at least somewhat smart:
- First, it'll try to mount the standard POSIX virtual filesystems (/proc, /sys, etc) if they're not mounted already (you specify which)
- Then, it'll parse /etc/fstab and mount all the disks from there as well (unless they are already mounted, of course).
    Drive IDs/UUIDs, LABELs and PARTUUIDs are also supported and are automatically resolved to their respective /dev/disk/by-XXX symlink

__Note__: To check if a disk is mounted, NimD reads /proc/mounts. If said virtual file is absent (say because we just booted and haven't mounted
/proc yet), the disk is assumed to be unmounted and is then mounted. This seems fairly reasonable to me, but in the off chance that said disk is
indeed mounted and NimD doesn't know it, it'll just log the error about the disk being already mounted and happily continue its merry way into
booting your system (_hopefully_), but failing to mount any of the POSIX virtual filesystems will cause NimD to abort with error code 131 (which
in turn will most likely cause your kernel to panic) because it's almost sure that the system would be in a broken state anyway.

The way I envision NimD being installed on a system is the following:
- /etc/nimd -> Contains configuration files
    - /etc/nimd/runlevels -> Contains the runlevels (think openrc)
- /var/run/nimd.sock -> Unix domain socket for IPC
- /etc/runlevels -> Symlink to /etc/nimd/runlevels
- /sbin/nimd -> Actual NimD executable
- /sbin/init -> Symlink to /sbin/nimd



