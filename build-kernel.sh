#!/bin/bash

set -e
source config/build.env

process_options(){
	for OPT in "$@"; do
		case "$OPT" in
			--type=*)	    KERNEL_BUILD_TYPE="${OPT#*=}"; shift;;
			--version=*)	LINUX_KERNEL_VERSION="${OPT#*=}"; shift;;
			--target=*)	    KERNEL_BUILD_TARGET="${OPT#*=}"; shift;;
			*) 		        echo "Option $opt not supported"; exit 1;;
		esac
	done
}

process_options "$@"
LINUX_VER=${LINUX_KERNEL_VERSION:-5.15.126}
# Obtain MAJOR and MINOR
LINUX_SV="$(echo $LINUX_VER | cut -d. -f-2)"
LINUX_SV="${LINUX_SV%%-rc*}"  # strip release candidate
LINUX_DIR="linux-${LINUX_SV}"


# If KERNEL_BUILD_TYPE is unset, then try to rebuild an existing kernel first
KERNEL_BUILD_TYPE=${KERNEL_BUILD_TYPE:-rebuild}

# We can only rebuild a kernel when its directory exists
if [ ! -d "$LINUX_DIR" ]; then
    KERNEL_BUILD_TYPE="clean"
fi

if [ "${LINUX_SV#*-rc}" == "${LINUX_SV}" ]; then # stable release
	STABLE_RELEASE=1
	LINUX_GIT="https://git.kernel.org/pub/scm/linux/kernel/git/stable/linux.git"
else # release candidate
	STABLE_RELEASE=0
	LINUX_GIT="https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git"
fi

PARALLEL=$(getconf _NPROCESSORS_ONLN)

echo "Building Kernel $LINUX_VER (${LINUX_SV})"

if [ "${KERNEL_BUILD_TYPE:-}" == "clean" ]; then
	echo "Clean up previous Linux kernel build directory and Debian Kernel packages"
	rm -rf "$LINUX_DIR"
    rm -f ../linux-*.deb

	if [ -d "$LINUX_LOCAL" ]; then
		git clone --local "$LINUX_LOCAL" "$LINUX_DIR"
	elif [ "$STABLE_RELEASE" -eq 1 ]; then
		git clone --single-branch --depth 1 --branch "v${LINUX_VER}" "$LINUX_GIT" "$LINUX_DIR"
		(cd "$LINUX_DIR"; git checkout -B dev "v${LINUX_VER}")
	else
		git clone "$LINUX_GIT" "$LINUX_DIR"
		(cd "$LINUX_DIR"; git checkout -B dev "v${LINUX_VER}")
	fi
	git config --global user.email ${GIT_EMAIL_ADDRESS}

	# Apply patches in sequence: more specific to more general
	if [[ -d "$CONFIG_DIR/patches/kernel-${LINUX_SV}/" ]]; then
		for file in $CONFIG_DIR/patches/kernel-${LINUX_SV}/*.patch; do
			echo "Applying kernel patch $file"
			( cd "$LINUX_DIR"; git am "$file" )
		done
	fi
	if [[ -d "$CONFIG_DIR/patches/kernel/" ]]; then
		for file in $CONFIG_DIR/patches/kernel/*.patch; do
			echo "Applying kernel patch $file"
			( cd "$LINUX_DIR"; git am "$file" )
		done
	fi
else # cleanup Debian package directory
	rm -rf "$LINUX_DIR/debian"
	(cd $LINUX_DIR; git clean -f)
fi
# Remove Debian packages for the current request version
#rm -f linux-*_${LINUX_VER}*

if [[ -d "$CONFIG_DIR/overlay/kernel/${LINUX_SV}/" ]]; then
	echo "Applying kernel overlay for version ${LINUX_SV}"
	cp -vr -- "$CONFIG_DIR/overlay/kernel/${LINUX_SV}/" "$LINUX_DIR" || echo bad
fi
#elif [[ -d "$CONFIG_DIR/overlay/kernel/" ]]; then
#	echo "Applying generic kernel overlay"
#	cp -vr "$CONFIG_DIR/overlay/kernel/.config" "$CONFIG_DIR/overlay/kernel/"* "$LINUX_DIR" || echo bad
#fi


cpp -nostdinc -x assembler-with-cpp -I "$DTS_DIR" -I "$LINUX_DIR/include/" \
		-undef -D__DTS__ "$DTS_MBL" -o "$DTB_MBL.tmp"

# The DTB needs to be enlarged as u-boot needs the extra size for adding ranges and frequency properties
dtc -O dtb -i "$DTS_DIR" -S 32768 -o "$DTB_MBL" "$DTB_MBL.tmp"

#(cd $LINUX_DIR; make ARCH="$ARCH" syncconfig;
#make-kpkg kernel-source kernel-headers kernel-image kernel-debug --revision 1.00 --arch=powerpc --cross-compile powerpc-linux-gnu- )
#make-kpkg kernel-image --revision 1.00 --arch=powerpc --cross-compile powerpc-linux-gnu- )
#make deb-pkg ARCH=powerpc CROSS_COMPILE=powerpc-linux-gnu- -j8
#

#if [ "${KERNEL_BUILD_TYPE:-}" == "clean" ] ; then  #|| [ ]
    (cd $LINUX_DIR; make ${KERNEL_BUILD_TARGET} ARCH="$ARCH" CROSS_COMPILE="$ARCH-linux-gnu-" -j${PARALLEL} )
#fi
