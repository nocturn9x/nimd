# Build the environment
mkdir -p rootfs/etc/nimd
cp nimd.conf rootfs/etc/nimd/nimd.conf
nim -o:rootfs/bin/nimd      -d:release --gc:orc --opt:size --passL:"-static" compile src/main.nim
nim -o:rootfs/bin/halt      -d:release --gc:orc --opt:size --passL:"-static" compile src/programs/halt.nim
nim -o:rootfs/bin/reboot    -d:release --gc:orc --opt:size --passL:"-static" compile src/programs/reboot.nim
nim -o:rootfs/bin/poweroff  -d:release --gc:orc --opt:size --passL:"-static" compile src/programs/poweroff.nim

# Start the VM
./scripts/boot.sh --kernel vmlinuz-linux --initrd initrd-linux.img --memory 1G --build
