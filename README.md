# Debian SID/Unstable Image Generator for the MyBook Live Series

## Introduction

This project's build.sh generates an adapted Debian Sid/Unstable (As it still has the powerpc target today) image for the Western Digital MyBook Live Series devices.  This repository is forked from https://github.com/chunkeey/mbl-debian to fix a few defects and to integrate my custom kernels for MyBookLive.  All credits for the Debian image go to Christian Lamparter aka chunkeey.

Big parts of this generator code habe been adapted from the [npn2-debian](https://github.com/riptidewave93/npn2-debian) project.

## Requirements
A working and up-to-date Debian build (virtual) machine with 20GiB+ of free space and root access (preferred).
Alternatively, any recent Debian or Ubuntu system will work (e.g. Linux Mint) too, but might not be as clean (the scripts currently remove all loop devices so that may impact your system). 

Then you have to make sure your package index is up to date `# apt update` before installing the following packages on your Debian build host:

`# apt install bc binfmt-support build-essential debootstrap device-tree-compiler dosfstools fakeroot git kpartx lvm2 parted python-dev python3-dev qemu qemu-user-static swig wget u-boot-tools gdisk fdisk uuid-runtime rsync zerofree gcc-10-powerpc-linux-gnu gcc-compiler-powerpc-linux-gnu binutils-powerpc-linux-gnu`

## Preparation and personalization
In "./build.env"
- Provide your GitHub email address: GIT_EMAIL_ADDRESS (mandatory)
- Change the desired kernel release: LINUX_KERNEL_VERSION (optional)
- Add/delete packages to DEBOOTSTRAP_INCLUDE_PACKAGES and APT_INSTALL_PACKAGES (optional)
- Change root password : ROOT_PASSWORD (optional)
- Change data format: DATE (optional)

## Build
- Just run `sudo ./build.sh`. 
- Completed builds output to the project root directory as `Debian-powerpc-unstable-YYYYMMDD-HHMM-GPT.img.gz`

## Advanced customization
- The kernel config file is located in `overlay/kernel`, kernel patches are located in `patches/kernel`
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

Once you have the HDD extracted, connect it to a PC and make a backup of it. After the backup was successfully completed and verified, you should zap out the existing GPT+MBR structures `gfdisk /dev/sdX` on that disk (look there in the expert option menu) and then you can uncompress the image onto the HDD. For example: `# gunzip -d -c Debian-powerpc-*-GPT.img.gz > /dev/sdX`... followed up by a `sync` to make sure everything is written to the HDD.

### Over the SSH-Console
For this method, you have to gain root access to the MyBook Live via SSH by any means necessary.
This is by no means ideal, since this can lead to a soft-bricked device, in case something went wrong.
So be prepared to disassemble the device.

To write the image onto the MyBook Live's drive, you can do it over the same network by executing:

`# cat Debian-powerpc-*-GPT.img.gz | ssh root@$MYBOOKLIVEADDRESS 'gunzip -d -c > /dev/sda'`

`zcat > /dev/sda` could be used in place of `gunzip -d -c > /dev/sda`

It's also possible (but it's discouraged because you can end up even more so with a bricked
device) to simply copy the image onto the HDD (via the provided standard access in the vendor
NAS firmware) and execute `# gunzip -c /path/to/Debian*.img.gz > /dev/sda` on the ssh shell of
the MyBook Live in order to write it directly onto /dev/sda.

After the image has been written, remove and reinsert the powerplug to do a instant reset.
The MyBook Live should then boot into a vanilla Debian Sid/Unstable.

## Usage

For access and administration, the image comes preinstalled with the [cockpit](https://cockpit-project.org/) web interface at [https://mbl-debian](https://mbl-debian).
SSH access is also available. Though, caution should be exercised. Because to make the first login possible when no serial cable has been attached, SSH will allow
password login for root, when no authorized_keys file is placed in `/root/.ssh/`.

## Notes
- The default root password is "debian" (see ROOT_PASSWORD variable in the build.sh script).
- The default hostname is "mbl-debian".
- This image will initialize the swap on the first boot and resize the GPT to fit the HDD.
- All Debian packages are directly pulled from the debian server. This is great since, the programs are up-to-date, but they can also be problems because of this. Be prepared to handle/fix or work-around your own problems.

## KNOWN ISSUES
- There are two SSH packages installed: DROPBEAR and OpenSSH, rendering DROPBEAR inoperable. Ideally DROPBEAR should be used but OpenSSH is pulled in via a package dependency.   You can use COCKPIT to fix this manually.

## RECENT CHANGES
- The BOOT partition is now 256MB in size and can fit multiple kernels.
- Add zerofree and rsync as packages
- The NOR flash is now working (fw_printenv, fw_setenv)

