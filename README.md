# Nim Daemon - An init system written in Nim
A minimal, self-contained, dependency-based Linux init system written in Nim.

## Note

The code in here is pretty bad: in fact, it's horrible (and it _barely_ works). I'm just messing around to get the basics done, sorry for that, 
but I need to get a proof of concept done before starting to do some actually sensible programming.

I mainly made this thing for fun and as an excuse to learn more about the mysterious PID 1 and the Linux kernel in general. If you are like me
and love getting your hands dirty, I truly recommend trying an endeavor like this as I haven't had this fun cobbling something together in a very
long time. Sometimes programming only large scale software is boring, go figure.

## Disclaimers & Functionality

This software is developed on a _"It works on my (virtual) machine"_ basis. I don't perform any extensive testing: if this thing unmounts your
root partition while you're saving your precious family photos, I can't do much (although it probably won't). I currently test NimD inside a
minimal Alpine VM that runs the 5.10.0-9-amd64 version of the Linux kernel.

NimD is developed **for Linux only**, as that's the kernel my OS uses: other kernels are not supported at all and NimD **will** explode with fancy
fireworks if you try to run it unmodified on other kernels (although probably things like BSD and Solaris are not that hard to add support for).

NimD is not particularly secure (although basic checks like making sure regular users can't reboot the machine are in place), but it doesn't need to be: the only thing it does is run the services you provide to it, that's it*. No `nimd-modulenamed` madness, no `libnimd.so` libraries to link against, NimD only runs your services: if it blows up, it's your fault (or it's a bug).

NimD expects the 3 [standard streams](https://en.wikipedia.org/wiki/Standard_streams) to be properly connected to `/dev/console` (which is something all modern versions of the Linux kernel do). I tried connecting them manually, but I was out of luck: if you happen to  know how to check for (or open) them and connect them manually, please make a PR, I'd love to hear how to do that.

_*_: Well, almost. If you don't wanna write oneshot services for simple things like creating symlinks/directories (especially if you plan running BSD ports of
some program on Linux) and mounting your drives then NimD can do it for you, but just because it _can_ doesn't mean it _has to_: you choose! NimD has a builtin
fstab parser and can operate entirely independently of the `mount` command, since it directly hooks up to `mount`, `umount` and `umount2` inside `sys/mount.h`

## Setup

NimD expects to be installed like so:
- `/etc/nimd` -> Contains configuration files and utilities like `reboot` and `poweroff`
    - `/etc/nimd/runlevels` -> Contains the runlevels (`boot`, `default`, `shutdown`)
    - `/etc/nimd/nimd.conf` -> NimD's own configuration file
- `/var/run/nimd.sock` -> Unix domain socket for IPC
- `/etc/runlevels` -> Symlink to `/etc/nimd/runlevels`
- `/sbin/nimd` -> Actual NimD executable
- `/sbin/init` -> Symlink to `/sbin/nimd`
- `/bin/{poweroff,shutdown,reboot,halt}`  -> Minimal utilities that communicate with NimD to poweroff/shutdown/reboot/halt the machine
- `/bin/nimdctl` -> Utility to interact with NimD (add/remove/start/stop services, read logs, inspect services' status, etc)


__Note__: The runlevels directory contains `*.conf` files (or they can also be symlinks, NimD doesn't care): those are NimD's own unit files.


## Unit files

Services in NimD are called _unit files_ or just _units_ (I know, __very__ original). They are configuration files that tell NimD what to do once
it has booted your system

### Dependency management

Unlike some other init systems (most notably, runit) NimD is _dependency based_: to understand this relatively simple concept disguised as a fancy term,
you have to understand NimD (like many others) relies on the concepts of _dependents_ (units that _depend_ on some others to work) and _providers_ (units 
that _provide_ services to their dependents and that may in turn have dependencies themselves). For example, if you wanna start an SSH server, you probably
want to make sure your disks are mounted and that your network has been set up. To do that, you can write something like this:

```
[Service]

name         = ssh                    # The name of the service
description  = Secure Shell Server    # A short description
type         = simple                 # Other option: oneshot (i.e. runs only once, implies supervised=false)
exec         = /usr/bin/sshd <args>   # Note: this is not passed trough the shell, it's executed directly
depends      = net,fs                 # This service will be started only when these dependencies are satisfied
provides     = ssh                    # Dependents can also be providers
restart      = always                 # Other options are: never, onFailure
restartDelay = 10                     # NimD will wait this many seconds before trying to start it again
supervised   = true                   # This is the default. Disable it if you don't need NimD to watch for it

[Logging]

stderr = /var/log/sshd     # Path of the stderr log for the service
stdout = /var/log/sshd     # Path of the stdout log for the service
stdin  = /dev/null         # Path of the stdin fd for the service
```

__Note__: Unsupervised services cannot be restarted, as NimD has no control over them once they're spawned.


A dependency name can either be the name of a unit file (case sensitive, but without the `.conf` extension), or one of the following placeholders:
- `net` -> Stands for network connection. Services like NetworkManager and dhcpcd should be set as providers for this
- `fs`  -> If you mount your disks using a oneshot service (recommended for the best experience), your service should provide this
- `ssh` -> The service provides some sort of SSH functionality
- `ftp` -> The service provides an FTP server
- `http` -> The service is an HTTP webserver

Note that NimD resolves placeholders before service names: this means that if you have a service named `ssh.conf`, using `ssh` as 
a dependency will __not__ set that service as a dependency and will __not__ override the default behavior unless said unit file also has
`provides=ssh` in it. Also note that multiple providers for the same service raise a warning by default and cause NimD to let the alphabet decide 
which dependency is started (i.e. they are sorted lexicographically by their filename, without the extension, and the first is picked), but this
behavior can be changed (e.g. raising an error instead)

## Configuring NimD

NimD's own configuration file is located at `/etc/nimd/nimd.conf` and its syntax is similar to those of unit files (i.e. uses an
INI-like structure), but the options are obviously different. An example config would look something like this:

```
[Logging]

level   = info            # Levels are: trace, debug, info, warning, error, critical, fatal
logFile = /var/log/nimd   # Path to log file

[Filesystem]

autoMount      = true                                    # Automatically parses /etc/fstab and mounts disks
autoUnmount    = true                                    # Automatically parses /proc/mounts and unmounts everything on shutdown
fstabPath      = /etc/fstab                              # Path to your system's fstab (defaults to /etc/fstab)
createDirs     = /path/to/dir1, /path/to/dir2            # Creates these directories on boot. Empty to disable
createSymlinks = /path/to/symlink:/path/to/dest, ...     # Creates these symlinks on boot. Empty to disable

[Misc]

controlSocket        = /var/run/nimd.sock    # Path to the Unix domain socket to create for IPC
onDependencyConflict = skip                  # Other option: warn, error                   
```