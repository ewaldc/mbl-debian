#!/bin/bash

# simple function to check http response code before downloading a remote file
# example usage:
# if `validate_url $url >/dev/null`; then dosomething; else echo "does not exist"; fi


POSITIONAL_ARGS=()
ARGS=""
PACKAGES_NOT_FOUND=""
ACTION=""

function setAction(){
	if [ -z "$ACTION" ]; then ACTION="$1"
	else
		echo "ERROR $0: only one action (-a | -s | -g | -i | -l ) allowed"
		exit 1
	fi 
}

function getOptions(){
	while [[ $# -gt 0 ]]; do
	  	case $1 in
			-a|--add)
				setAction "add"
				shift # past argument
			;;
			-f|--findPackageFile)
				setAction "findPackageFile"
				shift # past argument
				;;
			-l|--listPackage)
				setAction "listPackage"
				shift # past argument
				;;
			-g|--genIso)
				setAction "genIso"
				shift # past argument
				;;
			-i|--init)
				setAction "init"
				shift # past argument
				;;			
			-u|--update)
				setAction "update"
				shift # past argument
				;;		
			-c|--cleanp)
				setAction "cleanup"
				shift # past argument
				;;		
			-*|--*)
				echo "Unknown option $1"
				exit 1
				;;
			*)
				POSITIONAL_ARGS+=("$1") # save positional arg
				ARGS+=" $1"
				shift # past argument
				;;
	  	esac
	done
}

function cleanup(){
	echo "Cleanup loop devices and mappings"
	# Just in case it was not unmounted	
	/bin/umount -f -A -R -l "$TARGET" 2>/dev/null

	# Clean up all left over loop back devices related to target
	LOOP_DEVICES=$(losetup | sed -n '/.*'"$TARGET"'.*\.img/p'| awk '{print $1}')
	for DEVICE in $LOOP_DEVICES; do
		$KPARTX -d -f $DEVICE
		/usr/sbin/losetup -d $DEVICE 2>/dev/null
	done
}

function validate_url(){
	wget -S --spider $1  2>&1 | grep -q 'HTTP/1.1 200 OK'
}

function listPackage(){
	sed -n '/^Package: '"$1"'$/,/^ *$/p' ${WORKDIR}/config/${ARCH}-packages
}

function listPackageProvider(){
	sed -n '/^Provides: .*'"$1"'.*$/,/^ *$/p' ${WORKDIR}/config/${ARCH}-packages
}

function findPackageFile(){
	local PACKAGE_PATH=$(listPackage "$1"|sed -n 's/^Filename: //p')
	if [ -z "$PACKAGE_PATH" ]; then
		# There is no package with that name, but maybe it's provided by another package
		PACKAGE_PATH=$(listPackageProvider "$1"|sed -n 's/^Filename: //p')
	fi
	if [ -z "$PACKAGE_PATH" ]; then
		PACKAGES_NOT_FOUND+=" $1"
	else /bin/dirname $PACKAGE_PATH
	fi
	#/bin/basename $(/bin/dirname $PATH)
}

# Update packages file from online repo
function update(){
	> ${WORKDIR}/config/${ARCH}-packages
	for REPO in main contrib non-free non-free-firmware
	do
		wget -qO- --show-progress ${SOURCE_HTTP}/dists/unstable/${REPO}/binary-${ARCH}/Packages.gz|zcat >> ${WORKDIR}/config/${ARCH}-packages
	done
}

# Initializes package functionality - gets combined, uncompressed packages file
function init(){
	if [ -d "$REPOSITORY" ]; then
		echo "ERROR: remove existing repository ($REPOSITORY) first)"; exit 1
	fi
	update
}

function checkRepository(){
	if [ ! -d "$REPOSITORY/dists" ]; then
		mkdir -p $REPOSITORY
		echo "WARNING: $0 missing (writable) local repository, creating from ISO ($SOURCE_ISO)" 
		xorriso -osirrox on -indev $SOURCE_ISO -extract / $REPOSITORY
	fi
}

function checkMount(){
    MOUNT_SRC=$(findmnt -n -o SOURCE /mnt/iso)
    if [ -z "$MOUNT_SRC" ]; then mountIso; return 0; fi
    if [ -n "$MOUNT_SRC" ]; then
		MOUNTED_ISO=$(mount|grep '/mnt/iso'|awk '{print $1}')
		if [ "$MOUNTED_ISO" != "$SOURCE_ISO" ]; then
			echo "Wrong device mounted (${MOUNTED_ISO}, unmounting"
			umount -f $MOUNT_SRC
			mountIso
		fi
	fi
}

function mountIso(){
    mkdir -p /mnt/iso
	echo "Mounting ISO source: $SOURCE_ISO"
    MOUNT_SRC=$(findmnt -n -o SOURCE /mnt/iso)
    if [ -n "$MOUNT_SRC" ]; then umount -f $MOUNT_SRC; fi
    mount -o loop,ro $SOURCE_ISO /mnt/iso
}


function findPackageFiles(){
	for PACKAGE in $ARGS
	do
		findPackageFile $PACKAGE|uniq
	done
}

function listPackages(){
	for PACKAGE in $ARGS
	do
		listPackage $PACKAGE
	done
}


function addPackages(){
	for PACKAGE in $ARGS
	do
		PACKAGE_FILE=$(findPackageFile $PACKAGE|uniq)
		echo $PACKAGE_FILE
		#findPackageFile $PACKAGE |read -r PACKAGE_FILE
		if [ -z "$PACKAGE_FILE" ]; then continue; fi
		echo "Downloading package ${PACKAGE_FILE}"
	    wget -q --show-progress -A deb -A udeb -e robots=off -r -l 1 -nH --cut-dirs=1 "${SOURCE_HTTP}/${PACKAGE_FILE}"
		# Libraries are special (e.g. 'libu' in stead of 'l'
		#if [ "${PACKAGE:0:3}" == "lib" ]; then
		#    PACKAGE_INITIAL=${PACKAGE:0:4}
		#else PACKAGE_INITIAL=${PACKAGE:0:1}
		#fi

		#mkdir -p "pool-powerpc/main/${PACKAGE_INITIAL}/${PACKAGE}"
		#URL="${SOURCE_HTTP}/${PACKAGE_FILE}/${PACKAGE}"
		#if validate_url $URL; then
		#    echo "Fetching from pool-powerpc/main"
		    #wget -R "*.buildinfo" -R "index.html*" -R "*.gif" -e robots=off -r -l 1 -nH --cut-dirs=1 "${SOURCE_HTTP}/pool-powerpc/main/${PACKAGE_INITIAL}/${PACKAGE}/"
		#    wget -q --show-progress --progress=bar:noscroll -A deb -A udeb -e robots=off -r -l 1 -nH --cut-dirs=1 "$URL"
		    #wget -q -A deb -A udeb -e robots=off -r -l 1 -nH --cut-dirs=1 "$URL"

		#fi
		#URL="${SOURCE_HTTP}/pool/main/${PACKAGE_INITIAL}/${PACKAGE}"
		#if validate_url $URL; then
		#    echo "Fetch from pool/main (all architectures)"
		#    wget -q --show-progress -A deb -A udeb -e robots=off -r -l 1 -nH --cut-dirs=1 "$URL"
		#fi
	done
}

function genIso(){
	# Regenerate Packages file
	#apt-ftparchive -o APT::FTPArchive::AlwaysStat=true: -c=../aptftp.conf generate ../config-deb.conf
	echo "Regenerate Packages"
	#dpkg-scanpackages --multiversion pool-powerpc > dists/unstable/main/binary-${ARCH}/Packages 2>/dev/null
	#dpkg-scanpackages --multiversion pool >> dists/unstable/main/binary-${ARCH}/Packages 2>/dev/null
	dpkg-scanpackages pool-powerpc > dists/unstable/main/binary-${ARCH}/Packages 2>/dev/null
	dpkg-scanpackages pool >> dists/unstable/main/binary-${ARCH}/Packages 2>/dev/null
	cp dists/unstable/main/binary-${ARCH}/Packages ${WORKDIR}/config
	echo "Compress Packages"
	gzip -f dists/unstable/main/binary-${ARCH}/Packages

	# Regenerate MD5 sums
	echo "Regenerate MD5 sums"
	md5sum $(find ! -name "md5sum.txt" ! -path "./isolinux/*" -follow -type f 2>/dev/null) > md5sum.txt 

	# Regenerate Release file
	echo "Regenerate Release file"
	#sed -i '/MD5Sum:/,$d' dists/unstable/Release
	apt-ftparchive -o APT::FTPArchive::AlwaysStat=true: -c=${WORKDIR}/config/aptftp.conf release dists/unstable >dists/unstable/Release
	echo "Regenerate ISO"

	SOURCE_ISO_FILE=$(basename $SOURCE_ISO)

	rm -f /tmp/$SOURCE_ISO_FILE
	xorriso -as mkisofs -r -checksum_algorithm_iso md5,sha256,sha512 -V 'Debian 12.0.0 ppc n' -o /tmp/${SOURCE_ISO_FILE} -J -joliet-long -cache-inodes -hfsplus -apm-block-size 2048 -hfsplus-file-creator-type chrp tbxi /System/Library/CoreServices/BootX -hfs-bless-by p /System/Library/CoreServices -sysid PPC -graft-points /System/Library/CoreServices/BootX=boot/grub/powerpc-ieee1275/grub.chrp /System/Library/CoreServices/grub.elf=boot/grub/powerpc.elf -chrp-boot-part $PWD
	#sh .disk/mkisofs
	cp /tmp/${SOURCE_ISO_FILE} ${WORKDIR}/source
 }


source config/build.env

getOptions "$@"

if [ -z "$ACTION" ]; then
	echo "ERROR $0: missing action (-a | -s | -g | -i | -l )"
	exit 1
fi


# Unsure ISO i mounted
REPOSITORY="${WORKDIR}/config/${ARCH}-repository"
checkRepository
cd $REPOSITORY

if [ "$ACTION" != "init" ] && [ ! -f $WORKDIR/config/${ARCH}-packages ]; then
	echo "WARNING: packages not initialized, initializing..."
	init
fi

case $ACTION in
	add)				addPackages;;
	init)				init;;
	update)				update;;
	findPackageFile)	findPackageFiles;;
	listPackage)		listPackages;;
	genIso)				genIso;;
	cleanup)			cleanup;;
esac


#POOL=$1
#shift
#if [ "${POOL::4}" != "pool" ]; then
#    echo "usage: $0 pool <list of packages>"
#    echo "  where pool is pool/main or pool-powerpc/main"
#    exit 1
#fi





