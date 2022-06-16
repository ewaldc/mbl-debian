#!/bin/bash

set -e

ARCH=powerpc
RELEASE=unstable
TARGET=mbl-debian
DISTRIBUTION=Debian
PARALLEL=$(getconf _NPROCESSORS_ONLN)
REV=1.00

DTS_DIR=dts
DTS_MBL=dts/wd-mybooklive.dts
DTB_MBL=dts/wd-mybooklive.dtb
LINUX_DIR=linux
LINUX_VER=5.17.14
#LINUX_VER=5.17-rc8
#LINUX_VER=5.4.196
#LINUX_VER=5.17
MAJOR=$(echo $LINUX_VER | cut -d. -f1)
MINOR=$(echo $LINUX_VER | cut -d. -f2)
SUBVERSION=$(echo $LINUX_VER | cut -d. -f3)

GIT_EMAIL_ADDRESS="ewald_comhaire@hotmail.com"

# This "cached-linux" serves as a local cache for a unmodified linux.git
LINUX_LOCAL="cached-linux"
#LINUX_GIT=https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git
LINUX_GIT="https://git.kernel.org/pub/scm/linux/kernel/git/stable/linux.git"

OURPATH="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

echo "Building Kernel $LINUX_VER"

if [[ $# -eq 1 ]] && [[ "$1" == "--clean" ]]; then
	echo "Clean up previous installs"
	rm -rf "$LINUX_DIR"

	if [[ -d "$LINUX_LOCAL" ]]; then
		git clone --local "$LINUX_LOCAL" "$LINUX_DIR"
	elif [[ "$LINUX_VER" ]]; then
		#git clone "$LINUX_GIT" "$LINUX_DIR"
		#(cd "$LINUX_DIR"; git checkout dev "$LINUX_VER")
		git clone --single-branch --depth 1 --branch "v${LINUX_VER}" "$LINUX_GIT" "$LINUX_DIR"
		(cd "$LINUX_DIR"; git checkout -B dev "v${LINUX_VER}")
	else
		git clone "$LINUX_GIT" "$LINUX_DIR"
	fi
	#if [[ "$LINUX_VER" ]]; then
	#	(cd "$LINUX_DIR"; git checkout -B dev "$LINUX_VER")
	#	(cd "$LINUX_DIR"; git checkout dev "$LINUX_VER")
	#fi
	git config --global user.email ${GIT_EMAIL_ADDRESS}
	if [[ -d "$OURPATH/patches/kernel/" ]]; then
		PATCHPATH="$OURPATH/patches/kernel/${LINUX_VER}"
		echo "Testing kernel patches from ${PATCHPATH}"
		if [[ ! -d "$PATCHPATH" ]]; then PATCHPATH="$OURPATH/patches/kernel/${MAJOR}.${MINOR}"; fi
		if [[ ! -d "$CONFIGPATH" ]]; then CONFIGPATH="$OURPATH/patches/kernel"; fi
		echo "Applying kernel patches from ${PATCHPATH}"
		for file in ${PATCHPATH}/*.patch; do
			echo "Applying kernel patch $file"
			( cd $LINUX_DIR; git am $file )
			#( cd $LINUX_DIR; git apply $file )
		done
	fi
else # cleanup Debian package directory
	rm -rf "$LINUX_DIR/debian"
	(cd $LINUX_DIR; git clean -f)
fi
# Remove Debian packages for the current request version
rm -f linux-*_${LINUX_VER}*

if [[ -d "$OURPATH/overlay/kernel/" ]]; then
	CONFIGPATH="$OURPATH/overlay/kernel/${LINUX_VER}"
	if [[ ! -d "$CONFIGPATH" ]]; then CONFIGPATH="$OURPATH/overlay/kernel/${MAJOR}.${MINOR}"; fi
	if [[ ! -d "$CONFIGPATH" ]]; then CONFIGPATH="$OURPATH/overlay/kernel"; fi
	echo "Applying kernel overlay (includes config file) from ${CONFIGPATH}"
	cp -vr "${CONFIGPATH}/.config" "$OURPATH/overlay/kernel/"* "$LINUX_DIR" || echo bad
fi


cpp -nostdinc -x assembler-with-cpp \
		-I "$DTS_DIR" \
		-I "$LINUX_DIR/include/" \
		-undef -D__DTS__ "$DTS_MBL" -o "$DTB_MBL.tmp"

# The DTB needs to be enlarged as u-boot needs the extra size for adding ranges and frequency properties
dtc -O dtb -i "$DTS_DIR" -S 32768 -o "$DTB_MBL" "$DTB_MBL.tmp"

#(cd $LINUX_DIR; make ARCH="$ARCH" syncconfig;
#make-kpkg kernel-source kernel-headers kernel-image kernel-debug --revision 1.00 --arch=powerpc --cross-compile powerpc-linux-gnu- )
#make-kpkg kernel-image --revision 1.00 --arch=powerpc --cross-compile powerpc-linux-gnu- )
#make deb-pkg ARCH=powerpc CROSS_COMPILE=powerpc-linux-gnu- -j8
#
(cd $LINUX_DIR; make deb-pkg ARCH="$ARCH" CROSS_COMPILE=powerpc-linux-gnu- -j${PARALLEL} )

