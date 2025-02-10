# Debian SID/Unstable Image Generator for the MyBook Live Series

## Introduction

This project's build.sh generates an adapted Debian Sid/Unstable (as it still has the powerpc target today) image for the Western Digital MyBook Live Series devices.  This repository is forked from https://github.com/chunkeey/mbl-debian with following differences:
- Integration of custom MBL drivers for increased performance
- Move from unstable (daily) snapshots to a more controlled snapshot taking during Debian 12 release freeze (Debian 12 NETINST ISO)
- Introduction of a configuration directory for all configuration files/directories
- Additional tools to build or extend the provide Debian 12 custom ISO or build your own using `bin/package` command
- A very small number of changes/fixes (e.g. Dropbear, first boot).

All credits for the installation process for the Debian image go to Christian Lamparter aka chunkeey.

Big parts of this generator code have been adapted from the [npn2-debian](https://github.com/riptidewave93/npn2-debian) project, which is better maintained and has support for the very latest kernels such as 6.12.

## Expectations/Warnings

The new build process moves away from exclusive use of the Debian Sid/Unstable repository, which is not only a possibly unstable build but also a daily/frequently changing release that may or may not work.

To mitigate this issue, the base OS installation is now being performed from a Debian 12 PowerPC ISO image that is the result of a snapshot taken during the Debian 12 release freeze week. The original Debian 12 ISO image can be obtained from [here](https://cdimage.debian.org/cdimage/ports/stable/powerpc/).  More recent snapshots can be found [here](https://cdimage.debian.org/cdimage/ports/snapshots/)

This approach should provide following advantages:
- A more coherent and stable release (versus dialy snapshots)
- Repeatable installation quality/behavior
- Ability to provide updated ISO's e.g. based on newer snapshots that have been tested as reliable

That said, Debian 12 for PowerPC remains an unsupported and largely untested release.  All add-on packages (e.g. Samba) are still installed from the online, unstable repository.
At the same time, users retain the full flexibility to update the whole system to the very latest versions, update selected packages (e.g. for security reasons) or install specific versions of certain packages.

## Limitations

At this time the customized MBL performance patches are only available for the Linux Kernel 5.4 LTS series.
Work is being done to make these available on 5.15 LTS and 6.5 in anticipation of a late 2023 Kernel 6.x LTS release.

## Requirements
A working and up-to-date, Linux development/build virtual system with 20GiB+ of free space, 8GB of memory and root access (preferred).   With less than 4GB of memory there will most likely be errors during the Git clone of the Linux Kernel (might be resolved with setting GIT parameters).  Also needed is QEMU for the PowerPC platform.

Any recent Debian or Ubuntu physical system will also work (e.g. Linux Mint 20+), but might not be without risk:
- the scripts currently remove all loop devices so that may impact your system
- occasionally a reboot might be required when running out of loop devices (on some systems)
- a defect in a script could lead to accidental removal of data!

When using a physical server, make sure you have a **FULL BACKUP ALL YOUR DATA!**
To ensure your VM or system has all the needed build packages, make sure your package index is up to date `# apt update` before installing the following packages on your Debian build host:

`# apt install bc binfmt-support build-essential debootstrap device-tree-compiler dosfstools fakeroot git kpartx lvm2 parted python-dev python3-dev qemu qemu-user-static swig wget u-boot-tools gdisk fdisk uuid-runtime rsync zerofree bison flex libssl-dev gcc-10-powerpc-linux-gnu gcc-compiler-powerpc-linux-gnu binutils-powerpc-linux-gnu`

## Preparation and personalization
Modify "./config/build.env".  At minimum, it is required to review/change following settings (in the form of build variables)

- Provide your GitHub email address: `GIT_EMAIL_ADDRESS` (**mandatory**)
- Change the desired kernel release: `LINUX_KERNEL_VERSION` (optional, default is 6.4.14)
- Add/delete packages to `DEBOOTSTRAP_INCLUDE_PACKAGES` and `APT_INSTALL_PACKAGES` (optional)
- Change initial root password : `ROOT_PASSWORD` (optional)
- Change date format: DATE (optional)

In the `source` directory, download the Debian 12 NETINST ISO image of choice or use a provide one (e.g. `debian-12.0.0-powerpc-MBL-NETINST-1.iso`):

## Build
- Just run `sudo ./build.sh`.
- Completed builds output to the project root directory as `Debian-powerpc-unstable-YYYYMMDD-HHMM-GPT.img.gz`

## Advanced customization and problem resolution
- The Debian 12 ISO is mounted under `/mnt/iso`
- The kernel config file is located in `overlay/kernel`, kernel patches are located in `config/patches/kernel`
- Within these locations the kernel build script will look in sequence to:
    - `${LINUX_VER}` folder (e.g. `5.17.14`)
    - `${MAJOR}.${MINOR}`  (e.g. `5.17`)
    - the location directory itself
    to find the kernel config file and/or patches.  This means you can override the generic config/patchset with more version dependent ones if required.
    It also means you can have different config files for different kernel versions
- Run `sudo ./build-kernel.sh --type=rebuild` to only rebuild the kernel that is already checked out (versus whole image rebuild).  An updated Debian Kernel package will then be created (compared to a new compressed image).
- Run `sudo ./build-kernel.sh --type=clean` to erase the "linux" directory, do a fresh git checkout and perform a new kernel build of the same version as the image build.  By default, each kernel build results in a set of Debian packages: linux-headers, linux-image and linux-libc-dev (e.g. `linux-image-5.17.14+_5.17.14+-1_powerpc.deb`).  These can be copied to your MBL and intalled like any Debian package
- Run `sudo ./build-kernel.sh --target=uImage` to build a uImage rather than to the Debian Packages mentioned above (the default)
- Run `sudo ./build-kernel.sh --version=<version>` to just build a specific kernel version without rebuilding the whole image (will do a "clean" type build)

## Installing
There are multiple ways to get the image onto the device.

### Write the image onto the HDD by disassembling
This is the prefered method for the MyBook Live Duo. As it's as easy as opening the drive lid and pulling the HDD out of the enclosure. On the MyBook Live Single, this requires to fully disassemble the device in order to extract the HDD.

Once you have the HDD extracted, connect it to a PC and make a backup of it. After the backup was successfully completed and verified, you should zap out the existing GPT+MBR structures `gfdisk /dev/sdX` on that disk (look there in the expert option menu) and then you can uncompress the image onto the HDD (as root). For example:
```
zcat Debian-powerpc-*.img.gz > /dev/sdX`
sync
```

Use `sync` to make sure everything is effectively written to the HDD.

### Over the SSH-Console
For this method, you have to gain root access to the MyBook Live via SSH by any means necessary.
This is by no means ideal, since this can lead to a soft-bricked device, in case something went wrong.
So be prepared to disassemble the device.

To write the image onto the MyBook Live's drive, you can do it over the same network by executing:

```
cat Debian-powerpc-*-GPT.img.gz | ssh root@$MYBOOKLIVEADDRESS 'zcat > /dev/sdX'
```

Alternatively, `gunzip -d -c` could be used in place of `zcat`.

It's also possible (but it's discouraged because you can end up even more so with a bricked
device) to simply copy the image onto the HDD (via the provided standard access in the vendor
NAS firmware) and execute `# gunzip -c /path/to/Debian*.img.gz > /dev/sda` on the ssh shell of
the MyBook Live in order to write it directly onto /dev/sdX.

After the image has been written, remove and reinsert the powerplug to do a instant reset.
The MyBook Live should then boot into a vanilla Debian Sid/Unstable.

## Usage

For access and administration, the image comes preinstalled with the [cockpit](https://cockpit-project.org/) web interface at [https://mbl-debian](https://mbl-debian).
SSH access is also available. Though, caution should be exercised. Because to make the first login possible when no serial cable has been attached, SSH will allow
password login for root, when no authorized_keys file is placed in `/root/.ssh/`.
In the case SSH is non-functional, you can obtain a terminal windows via the `cockpit` interface.

## Notes
- The default root password is `debian` (see ROOT_PASSWORD variable in the `build.env` script).
- The default hostname is determined by the `TARGET` variable and defaults to `mbl-debian`.
- This image will initialize the swap on the first boot and resize the GPT to fit the size of the HDD.
- All Debian packages are directly pulled from the debian server. This is great since, the programs are up-to-date, but they can also be problems because of this. Be prepared to handle/fix or work-around your own problems.
- Dropbear is be the default SSH server, but can be changed to openssh via the `SSH-SERVER` variable. Dropbear is more targetted to embedded systems and has a smaller footprint, but lacks `SFTP` support. It does however support `SCP` which makes it easy to copy files from or to Windows using WinSCP.

## RECENT CHANGES
- The BOOT partition is now 256MB in size and can fit multiple kernels.
- Add zerofree and rsync as packages
- The NOR flash is now working (fw_printenv, fw_setenv)
- Support for custom/small initramfs
- Support for Debian 12
- Support for local repositories (Debian 12 Netinst ISO)
- Tool for adding packages to the ISO/local repository (`package.sh`)
