trap 'catch' ERR

catch() {
    echo "Build failed"
    exit
}
echo "Compiling NimD"
nim -d:release -d:danger --passC:"-O3 -flto" --opt:size --hints:off --gc:orc --passL:"-static" -o:rootfs/sbin/nimd c src/main
echo "Compiling NimD subprograms"
nim -d:release -d:danger --passC:"-O3 -flto" --opt:size --hints:off --gc:orc --passL:"-static" -o:rootfs/sbin/poweroff c src/programs/poweroff
nim -d:release -d:danger --passC:"-O3 -flto" --opt:size --hints:off --gc:orc --passL:"-static" -o:rootfs/sbin/halt c src/programs/halt
nim -d:release -d:danger --passC:"-O3 -flto" --opt:size --hints:off --gc:orc --passL:"-static" -o:rootfs/sbin/reboot c src/programs/reboot
nim -d:release -d:danger --passC:"-O3 -flto" --opt:size --hints:off --gc:orc --passL:"-static" -o:rootfs/sbin/nimd-reload c src/programs/reload
echo "Setting up directory structure"
mkdir -p rootfs/etc/nimd
cp nimd.conf rootfs/etc/nimd
echo "Building and starting VM"
./boot.sh --memory 1G --kernel vmlinuz-linux --initrd initramfs-linux.img --build