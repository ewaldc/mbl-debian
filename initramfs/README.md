# Generic initramfs

## Introduction

This initramfs is independent of kernel versions.  It is based on (static) busybox and does not use udev.
Consequently it is just a fraction in size and steps up the boot process.
While it supports dynamically loadable modules it is recommended to statically include all drivers required for booting since they will need to be loaded anyway and it won't make the kernel smaller.

## Installing pre-build generic initramfs

First, build a kernel with all hardware dependend drivers as static modules. Use 'lsmod' after boot to find out which modules are loaded.
Install this kernel as /boot/uImage. 

Copy [uInitrd-generic](../../../raw/master/initramfs/uInitrd-generic) to /boot on the MBL, create a symlink to uInitrd and then reboot
```
cd /boot
ln -sf uInitrd-generic uInitrd
systemctl reboot
```

## Customizing generic initramfs

First download [initrd.img-generic](../../../raw/master/initramfs/uInitrd-generic) to e.g. /root
Use unmkinitramfs to unpack the cpio archive, the modify the files.
Afterward, repack with cpio, compress with either gzip or z-standard and create an uInitrd image. 
```
cd /root
mkdir initramfs
unmkinitramfs uInitrd-generic initramfs
cd initramfs
# Modify files
find . -print0 | cpio --null --create --verbose --format=newc | zstd > ../uInitrd-generic-zst
cd ..
/usr/bin/mkimage -A powerpc -T ramdisk -C none -n "MyBook Live Ramdisk - Generic" -d uInitrd-generic-zst /boot/uInitrd-generic-zst
cd /boot
ln -sf uInitrd-generic-zst uInitrd
```

## KNOWN ISSUES
- Support for UUID based root devices in the kernel commandline is pre-enabled but still requires a few modifications

## RECENT CHANGES

