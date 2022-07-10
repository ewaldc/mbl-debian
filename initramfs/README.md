# Generic initramfs

## Introduction

This initramfs is independent of kernel versions.  It is based on (static) busybox and does not use udev.
Consequently it is just a fraction in size and steps up the boot process.
While it supports dynamically loadable modules it is recommended to statically include all drivers required for booting since they will need to be loaded anyway and it won't make the kernel smaller.

## Using generic initramfs

Copy [uInitrd-generic]() to /boot on the MBL and create a symlink to uInitrd
´´´
ln -sf uInitrd-generic uInitrd
systemctl reboot
´´´

## Customizing generic initramfs

Use unmkinitramfs to unpack the cpio archive


## KNOWN ISSUES
- Support for UUID based root devices in the kernel commandline is pre-enabled but not yet working

## RECENT CHANGES

