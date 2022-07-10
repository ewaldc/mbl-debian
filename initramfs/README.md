# Generic initramfs

## Introduction

This initramfs is independent of kernel versions.  It is based on (static) busybox and does not use udev.
Consequently it is just a fraction in size and steps up the boot process.
While it supports dynamically loadable modules it is recommended to statically include all drivers required for booting since they will need to be loaded anyway and it won't make the kernel smaller.

## Using generic initramfs

First, build a kernel with all hardware dependend drivers as static modules. Use 'lsmod' after boot to find out which modules are loaded.
Install this kernel as /boot/uImage. 

Copy [uInitrd-generic](../initramfs/uInitrd-generic) to /boot on the MBL, create a symlink to uInitrd and then reboot
`
cd /boot
ln -sf uInitrd-generic uInitrd
systemctl reboot
`

## Customizing generic initramfs

First download [initrd.img-generic](https://github.com/ewaldc/mbl-debian/blob/master/initramfs/uInitrd-generic) to e.g. /root
Use unmkinitramfs to unpack the cpio archive e.g. to /root
`
cd /root
mkdir initramfs
unmkinitramfs custom-ramfs.cpio /tmp/r

`

## KNOWN ISSUES
- Support for UUID based root devices in the kernel commandline is pre-enabled but not yet working

## RECENT CHANGES

