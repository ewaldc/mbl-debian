#!/bin/bash

process_options(){
	for OPT in "$@"; do
		case "$OPT" in
			--type=*)		KERNEL_BUILD="${OPT#*=}"; shift;;
			--version=*)	LINUX_KERNEL_VERSION="${OPT#*=}"; shift;;
			*) 				echo "Option $OPT not supported"; exit 1;;
		esac
	done
}

cleanup(){
	echo "Cleanup loop devices and mappings"
	# Just in case it was not unmounted	
	/bin/umount -f -A -R -l "$TARGET"

	$KPARTX -f -d "$IMAGE"	# Force deletion
	dmsetup info ${LO_DEVICE}p1 2>/dev/null && dmsetup remove -f ${LO_DEVICE}p1
	dmsetup info ${LO_DEVICE}p2 2>/dev/null && dmsetup remove -f ${LO_DEVICE}p2
	/sbin/losetup -D

	# Clean up all left over loop back devices related to target
	LOOP_DEVICES=$(losetup -a | grep "$TARGET"| grep '.img' | awk '{print $1}')
	for DEVICE in $LOOP_DEVICES; do
		$KPARTX -d -f $DEVICE
		/usr/sbin/losetup -d $DEVICE 2>/dev/null
	done

	if [ -n "$SOURCE_ISO" ]; then # we have an ISO source
		echo "Unmounting ISO source"
		MOUNT_SRC=$(findmnt -n -o SOURCE /mnt/iso)
		if [ -n "$MOUNT_SRC" ]; then
		    umount -f $MOUNT_SRC
		fi
	fi
	umount -f ${TARGET}/proc 2>/dev/null
	umount -f ${TARGET}/sys 2>/dev/null
	umount -f ${TARGET}/dev 2>/dev/null
	umount -f ${TARGET}/mnt/iso 2>/dev/null
}

# set -xe
source config/build.env
process_options

IMAGESIZE=$(("$BOOTSIZE" + "$ROOTSIZE" + (4 * 1024 * 1024 )))

IMAGE="$DISTRIBUTION-$ARCH-$RELEASE-$DATE.img"

# Problem here is that the kernel md-autodetect code needs
# a 0.90 SuperBlock for the rootfs to boot off. The 0.90
# superblock unfortunatley uses the ARCH's (powerpc =
# big endian) encoding....
# But we are building on x86/ARM with little endian so we,
# can't use the established mdadm to make the RAID.
MAKE_RAID=


die() {
	(>&2 echo "$@")
	exit 1
}

to_k()
{
	echo $(($1 / 1024))"k"
}

echo "Building Image '$IMAGE'"

# Add powerpc architecture
dpkg --add-architecture $ARCH

# Test if all the required tool are installed
declare -a NEEDED=("/usr/bin/uuidgen uuid-runtime" "$QEMU_STATIC qemu-user-static" "$MKIMAGE u-boot-tools"
	"$DTC device-tree-compiler" "$KPARTX kpartx" "$PARTPROBE parted"
	"$DEBOOTSTRAP debootstrap" "/usr/bin/git git" "/bin/mount mount" "/usr/bin/rsync rsync"
	"/sbin/gdisk gdisk" "/sbin/fdisk fdisk" "/usr/sbin/chroot coreutils"
	"/sbin/mkswap util-linux" "/usr/sbin/zerofree zerofree"
	"/usr/bin/powerpc-linux-gnu-gcc gcc-powerpc-linux-gnu"
	"/usr/bin/powerpc-linux-gnu-ld binutils-powerpc-linux-gnu xorriso")

for PACKAGE in "${NEEDED[@]}"; do
	set -- $PACKAGE

	[ -r "$1" ] || {
		die "Can't find '$1'. Please install '$2'"
	}
done

# Cleanup

[ -d "$TARGET" ] && {
	/bin/umount -f -l "$TARGET" || echo "Image was already mounted - unmounting"
}
[ -r "$IMAGE" ] && {
	$KPARTX -d "$IMAGE" || echo "Image was already loaded - cleaning"
}
/sbin/losetup -D
rm -rf "$TARGET" "$IMAGE"

fallocate -l "$IMAGESIZE" "$IMAGE"

trap "/bin/umount -A -R -l $TARGET || cleanup || echo ''; rm -rf $TARGET linux-*.deb" EXIT
#trap "/bin/umount -A -R -l $TARGET || cleanup || echo ''; rm -rf $TARGET" EXIT

/sbin/gdisk "$IMAGE" <<-GPTEOF
	o
	y
	n
	p
	1

	+$(to_k $BOOTSIZE)

	n
	p
	2

	+$(to_k $ROOTSIZE)

	x
	c
	2
	$ROOTPARTUUID
	m
	w
	y
GPTEOF

DEVICE=$(/sbin/losetup -f --show "$IMAGE")

$PARTPROBE

LO_DEVICE=$($KPARTX -vas "$IMAGE" | sed -E 's/.*(loop[0-9])p.*/\1/g' | head -1)
sleep 1

DEVICE="/dev/mapper/${LO_DEVICE}"
BOOTP=${DEVICE}p1
ROOTP=${DEVICE}p2

echo "BOOTP: $BOOTP ROOTP:$ROOTP"
echo "CONFIG_DIR $CONFIG_DIR WORKDIR $WORKDIR"

#read -p "Press any key to resume ..."

# Build Kernel from scratch/clean
bash -x ./build-kernelE.sh --type=${KERNEL_BUILD_TYPE} --target=${KERNEL_BUILD_TARGET} --version=${LINUX_KERNEL_VERSION}

# Make filesystems

# Boot ext2 Filesystem - revision 1 is needed because of u-boot ext2load
/sbin/mkfs.ext2 "$BOOTP" -O filetype -L BOOT -m 0 -U $BOOTUUID -b 1024
# Reserve space at the end for an mdadm RAID 0.9 or 1.0 superblock
/sbin/resize2fs "$BOOTP" $(( $BOOTSIZE / 1024 - 128 ))

# Root Filesystem - ext4 is specified in rootfstype= kernel cmdline
/sbin/mkfs.ext4 "$ROOTP" -L root -U $ROOTUUID -b 4096
# Reserve space at the end for an mdadm RAID 0.9 or 1.0 superblock
/sbin/resize2fs "$ROOTP" $(( $ROOTSIZE / 4096 - 32 ))

mkdir -p "$TARGET"

mount "$ROOTP" "$TARGET" -t ext4

# create swapfile - it's still up to debate whenever fallocate or dd is better
dd if=/dev/zero of="$TARGET/.swapfile" bs=1M count="$SWAPFILESIZE"
chmod 0600 "$TARGET/.swapfile"

#prepare boot
mkdir -p "$TARGET/tmp"
mkdir -p "$TARGET/boot"
mount "$BOOTP" "$TARGET/boot" -t ext2
mkdir -p "$TARGET/boot/boot"
cp $CONFIG_DIR/dts/wd-mybooklive.dtb "$TARGET/boot/apollo3g.dtb"
cp $CONFIG_DIR/dts/wd-mybooklive.dtb.tmp "$TARGET/boot/apollo3g.dts"
if [ "$SSH_SERVER" == "openssh" ]; then APT_INSTALL_PACKAGES+=" openssh-server"; fi

ROOTBOOT="UUID=$ROOTUUID"

echo "$ROOTBOOT" > "$TARGET/boot/boot/root-device"

# debootstap
if [ -n "$SOURCE_ISO" ]; then # we have an ISO source
    echo "ISO Source defined, mounting as loop device"
    mkdir -p /mnt/iso
    MOUNT_SRC=$(findmnt -n -o SOURCE /mnt/iso)
    if [ -n "$MOUNT_SRC" ]; then
        umount -f $MOUNT_SRC
    fi
    mount -o loop,ro $SOURCE_ISO /mnt/iso
    #$MULTISTRAP -f "$MULTISTRAP_CONFIG" -a "$ARCH" -d "$TARGET"
    $DEBOOTSTRAP --no-check-gpg --foreign --include="$DEBOOTSTRAP_INCLUDE_PACKAGES" --exclude="powerpc-utils" --arch "$ARCH" "$RELEASE" "$TARGET" "file:///mnt/iso"
	mkdir -p "$TARGET/usr/share/dpkg"
	cp $SOURCE_ISO $TARGET/usr/share/dpkg
elif [ -n "$SOURCE_DIR" ]; then
    #$MULTISTRAP -f "$MULTISTRAP_CONFIG" -a "$ARCH" -d "$TARGET"
    $DEBOOTSTRAP --no-check-gpg --foreign --include="$DEBOOTSTRAP_INCLUDE_PACKAGES" --exclude="powerpc-utils" --arch "$ARCH" "$RELEASE" "$TARGET" "file://$SOURCE_DIR"
else
    $DEBOOTSTRAP --no-check-gpg --foreign --include="$DEBOOTSTRAP_INCLUDE_PACKAGES" --exclude="powerpc-utils" --arch "$ARCH" "$RELEASE" "$TARGET" "$SOURCE_HTTP"
fi

mkdir -p "$TARGET/usr/bin"
cp "$QEMU_STATIC" "$TARGET"/usr/bin/

#if [ -z "$SOURCE_ISO" ]; then # we have a HTTP source
LANG=C.UTF-8 /usr/sbin/chroot "$TARGET" /debootstrap/debootstrap --second-stage
#fi

if [ -d $CONFIG_DIR/overlay/fs ]; then
	echo "Applying fs overlay"
	cp -vR $CONFIG_DIR/overlay/fs/* "$TARGET"
fi

mv linux-*.deb "$TARGET/tmp"
if [ -f fix-missing-ports/*.deb ]; then
	mkdir -p "$TARGET/tmp/fix"
	cp fix-missing-ports/*.deb "$TARGET/tmp/fix"
fi
rm -f linux-upstream*

mkdir -p "$TARGET/dev/mapper"

cat <<-INSTALLEOF > "$TARGET/tmp/install-script.sh"
	#!/bin/bash -e

	export DEBIAN_FRONTEND=noninteractive DEBCONF_NONINTERACTIVE_SEEN=true
	export LC_ALL=C LANGUAGE=C LANG=C

    # fstab
    cat <<-FSTABEOF > /etc/fstab
        # <file system>	<mount point>	<type>	<options>			<dump>	<pass>
        #UUID=$ROOTUUID	/		ext4	defaults			0	1
		#UUID=$BOOTUUID	/boot		ext2	defaults,sync,nosuid,noexec	0	2
        /dev/sda2	/		ext4	defaults			0	1
        /dev/sda1	/boot	ext2    defaults,sync,nosuid,noexec     0       2
    	proc		/proc		proc	defaults			0	0
    	none		/var/log	tmpfs	size=30M,mode=755,gid=0,uid=0	0	0
	FSTABEOF

    mount -t proc /proc
    mount -t sysfs sys /sys
    mount udev -t devtmpfs /dev

    mkdir -p /usr/local

	# apt sources
    >/etc/apt/sources.list
	# Test if local iso present
	DEBIAN_ISO=\$(ls /usr/share/dpkg/debian-*.iso 2>&1)
	if [ -n "\$DEBIAN_ISO" ]; then
		mkdir -p /mnt/iso    	
		mount -o loop,ro \$DEBIAN_ISO /mnt/iso
		cat <<-SOURCESEOF >> /etc/apt/sources.list
			deb [trusted=yes] file:/mnt/iso $RELEASE main
		SOURCESEOF
	fi
	# Enable standard HTTP sources
	cat <<-SOURCESEOF >> /etc/apt/sources.list
		deb $SOURCE_HTTP $RELEASE main contrib non-free non-free-firmware
		deb-src $SOURCE_SRC $RELEASE main contrib non-free non-free-firmware
	SOURCESEOF

	echo "$TARGET" > etc/hostname
	echo "127.0.1.1	$TARGET" >> /etc/hosts

	export LANGUAGE="en_US.UTF-8"
	export LANG="en_US.UTF-8"
	export LC_ALL="en_US.UTF-8"
	echo 'en_US.UTF-8 UTF-8' > /etc/locale.gen
    /usr/sbin/locale-gen
	export LC_ALL="en_US.UTF-8"
    dpkg-reconfigure locales
    update-locale LC_ALL=en_US.UTF-8

	. /etc/profile

	# Networking
	mkdir -p /etc/network
	cat <<-NETOF > /etc/network/interfaces
		auto lo
        # This file describes the network interfaces available on your system
		# and how to activate them. For more information, see interfaces(5).
		source /etc/network/interfaces.d/*
		# The loopback network interface
		auto lo
		iface lo inet loopback
	NETOF
	mkdir -p /etc/network/interfaces.d
	cat <<-NETOF > /etc/network/interfaces.d/eth0
		allow-hotplug eth0
		iface eth0 inet dhcp
		iface eth0 inet6 auto
	NETOF
	cat <<-NETOF > /etc/network/interfaces.d/end0
		allow-hotplug end0
		iface end0 inet dhcp
		iface end0 inet6 auto
	NETOF

	# Debian unattented settings
	cat <<-CONSET > /tmp/debconf.set
		console-common	console-data/keymap/policy	select	Select keymap from full list
		console-common	console-data/keymap/full	select	us
		iperf		iperf3/start_daemon		string	false
	CONSET

	( export DEBIAN_FRONTEND=noninteractive; debconf-set-selections /tmp/debconf.set )

	#echo 'en_US.UTF-8 UTF-8' > /etc/locale.gen
	#/usr/sbin/locale-gen

	# Set root password...
	echo "root:$ROOT_PASSWORD" | /usr/sbin/chpasswd
	echo 'RAMTMP=yes' >> /etc/default/tmpfs
	rm -f /etc/udev/rules.d/70-persistent-net.rules

	mkdir -p /etc/systemd/system/cockpit.socket.d/
	cat <<-CPLISTEN > /etc/systemd/system/cockpit.socket.d/listen.conf
	[Socket]
	ListenStream=
	ListenStream=80
	ListenStream=443
	ListenStream=9090
	CPLISTEN

	cat <<-FWCONF > /etc/fw_env.config
	# MTD device name	Device offset	Env. size	Flash sector size	Number of sectors
	/dev/mtd1		    0x0000		    0x1000		0x1000			    1
	/dev/mtd1		    0x1000		    0x1000		0x1000			    1
	FWCONF

	# Delete "existing" MD arrays... These have been copied from the Host system
	# They don't belong into this image

	if [ -f "/etc/mdadm/mdadm.conf" ]; then
		sed -i '/#\ definitions\ of\ existing\ MD\ arrays/,/^$/d' /etc/mdadm/mdadm.conf
	fi

	echo "overlay" >> /etc/initramfs-tools/modules
	touch /disable-root-ro

	rm -f /etc/dropbear/dropbear_*_host_key
	rm -f /etc/dropbear-initramfs/dropbear_*_host_key	# Debian 11 (?)
	rm -f /etc/dropbear/initramfs/dropbear_*_host_key	# Debian 12	

	# install kernel image (mostly for the modules)
	dpkg -i /tmp/linux-*deb

	if [ -d /tmp/fix ]; then
		dpkg -i /tmp/fix/*.deb
	fi

	# First, try to fix bad packages dependencies
	apt install -f -y
	apt update

	apt install -y $APT_INSTALL_PACKAGES

	# If a root-keyfile is already in place. Don't change the SSH Default password setting for root
	[[ -f /root/.ssh/authorized_keys ]] || sed -i 's|#PermitRootLogin prohibit-password|PermitRootLogin yes|g' /etc/ssh/sshd_config

	# Make it possible to login to cockpit as root... by deleting the "root" user by overwriting that file
	echo "# List of users which are not allowed to login to Cockpit" > /etc/cockpit/disallowed-users

	# Configure first_boot
	#update-rc.d first_boot defaults
	#update-rc.d first_boot enable
	chmod 744 /etc/init.d/first_boot
	chmod 664 /etc/systemd/system/first_boot.service
	systemctl enable first_boot

	# Configure the proper ssh server	
	if [ "$SSH_SERVER" == "openssh" ]; then 
		systemctl disable dropbear
	fi

	# ... but make it so, that root has to change it on the first login
	# (This hopefully unbreaks dnsmasq install)
	/usr/bin/passwd -e root

	# git doesn't track permission on folders, so we have to step and lock
	# the /boot and /root (since we likely created these folders with the
	# overlay.
	chmod 0770 /boot /root

	# cleanup
	apt clean
	apt-get --purge -y autoremove
	rm -rf /var/lib/apt/lists/* /var/tmp/*
	rm -f /tmp/linux*deb /tmp/debconf.set
	apt-mark minimize-manual -y

	# Delete the generated ssh key - It has to go since otherwise
	# the key is shipped with the image and will not be unique
	rm -f /etc/ssh/ssh_host_*

	# Enable tmpfs on /tmp
    systemctl enable /usr/share/systemd/tmp.mount

	# Delete ISO image
	if [ -n "\$DEBIAN_ISO" ]; then
		echo "Unmounting local repository"
		umount /mnt/iso
		rm -f \$DEBIAN_ISO
		rm -f /usr/shar/dpkg/debian*.iso
		# Comment out local repository
		sed -i '1s/^/#/' /etc/apt/sources.list
	fi

	echo "Install script terminated"
	# Allow for better compression by NULLING all the free space on the drive
	rm /tmp/install-script.sh

INSTALLEOF

#read -p "Press any key to resume ..."

chmod a+x "$TARGET/tmp/install-script.sh"
LANG=C.UTF-8 /usr/sbin/chroot "$TARGET" /tmp/install-script.sh
#DEBIAN_FRONTEND=noninteractive DEBCONF_NONINTERACTIVE_SEEN=true LC_ALL=C LANGUAGE=C LANG=C /usr/sbin/chroot "$TARGET" /tmp/install-script.sh

sleep 2
read -p "Press any key to resume ..."

/bin/umount -A -R -l "$TARGET"

/usr/sbin/zerofree -v "$BOOTP"
/usr/sbin/zerofree -v "$ROOTP"

[[ $MAKE_RAID ]] && {
	# super 1.0 is between 8k and 12k
	dd if=boot-md0-raid1 of="$BOOTP" bs=1K seek=$(( $BOOTSIZE / 1024 - 8 )) status=noxfer

	# super 0.9 is at 64K
	dd if=root-md1-raid1 of="$ROOTP" bs=1k seek=$(( $ROOTSIZE / 1024 - 64)) status=noxfer
}

# Clean up loop devices and device mappings
cleanup

[[ $MAKE_RAID ]] && {
	# Do this at the end. This is because if we start with the
	# FD00 partition type when we are creating the partitions above,
	# the kernel will try to automount it when partprobe and kpartx
	# gets invoced... which we don't want.

	/sbin/gdisk "$IMAGE" <<-RAIDEOF
		t
		1
		fd00
		t
		2
		fd00
		w
		y
	RAIDEOF
}

if [[ "$DO_COMPRESS" ]]; then
	echo "Compressing Image. This can take a while."
	if [[ "$(command -v pigz)" ]]; then
		pigz "$IMAGE"
	else
		gzip "$IMAGE"
	fi
fi

# Remove powerpc architecture
#dpkg --remove -architecture ${ARCH}

# Write image
#zcat "$IMAGE" 
