nim -o:rootfs/bin/nimd -d:release --gc:orc --opt:size --passL:"-static" compile src/main.nim
nim -o:rootfs/bin/nimdown -d:release --gc:orc --opt:size --passL:"-static" compile src/programs/poweroff.nim
nim -o:rootfs/bin/nimhalt -d:release --gc:orc --opt:size --passL:"-static" compile src/programs/halt.nim
nim -o:rootfs/bin/nimreboot -d:release --gc:orc --opt:size --passL:"-static" compile src/programs/reboot.nim
mkdir -p rootfs/etc/nimd
cp nimd.conf rootfs/etc/nimd/nimd.conf
./boot.sh --kernel vmlinuz-linux --initrd initrd-linux.img --memory 1G --build
