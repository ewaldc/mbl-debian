#!/bin/bash

set -e
source ./build.env

process_options(){
	for OPT in "$@"; do
		case "$OPT" in
			--type=*)		KERNEL_BUILD_TYPE="${OPT#*=}"; shift;;
			--version=*)	LINUX_KERNEL_VERSION="${OPT#*=}"; KERNEL_BUILD_TYPE="clean"; shift;;
			--target=*)		KERNEL_BUILD_TARGET="${OPT#*=}"; shift;;
			*) 				echo "Option $opt not supported"; exit 1;;
		esac
	done
}

process_options "$@"
LINUX_VER=${LINUX_KERNEL_VERSION:-5.15.126}
# Obtain MAJOR and MINOR
LINUX_SV="$(echo -n $LINUX_VER | cut -d. -f-2)"
LINUX_SV="${LINUX_SV%%-rc*}"  # strip release candidate
LINUX_DIR="linux-${LINUX_SV}"

LINUX_GIT="https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git"
LINUX_GIT_STABLE="https://git.kernel.org/pub/scm/linux/kernel/git/stable/linux.git"
PARALLEL=$(getconf _NPROCESSORS_ONLN)


echo "Building Kernel $LINUX_VER (${LINUX_SV})"

if [ "${KERNEL_BUILD_TYPE:-}" == "clean" ]; then
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

	# Apply patches in sequence: more specific to more general
	if [[ -d "$OURPATH/patches/kernel-${LINUX_SV}/" ]]; then
		for file in $OURPATH/patches/kernel-${LINUX_SV}/*.patch; do
			echo "Applying kernel patch $file"
			( cd "$LINUX_DIR"; git am "$file" )
		done
	fi
	if [[ -d "$OURPATH/patches/kernel/" ]]; then
		for file in $OURPATH/patches/kernel/*.patch; do
			echo "Applying kernel patch $file"
			( cd "$LINUX_DIR"; git am "$file" )
		done
	fi
else # cleanup Debian package directory
	rm -rf "$LINUX_DIR/debian"
	(cd $LINUX_DIR; git clean -f)
fi
# Remove Debian packages for the current request version
rm -f linux-*_${LINUX_VER}*

if [[ -d "$OURPATH/overlay/kernel/" ]]; then
	echo "Applying generic kernel overlay"
	cp -vr "$OURPATH/overlay/kernel/.config" "$OURPATH/overlay/kernel/"* "$LINUX_DIR" || echo bad
fi
if [[ -d "$OURPATH/overlay/kernel-${LINUX_SV}/" ]]; then
	echo "Applying kernel overlay for version ${LINUX_SV}"
	cp -vr "$OURPATH/overlay/kernel-${LINUX_SV}/.config" "$OURPATH/overlay/kernel-${LINUX_SV}/"* "$LINUX_DIR" || echo bad
fi

cpp -nostdinc -x assembler-with-cpp -I "$DTS_DIR" -I "$LINUX_DIR/include/" \
		-undef -D__DTS__ "$DTS_MBL" -o "$DTB_MBL.tmp"

# The DTB needs to be enlarged as u-boot needs the extra size for adding ranges and frequency properties
dtc -O dtb -i "$DTS_DIR" -S 32768 -o "$DTB_MBL" "$DTB_MBL.tmp"

#(cd $LINUX_DIR; make ARCH="$ARCH" syncconfig;
#make-kpkg kernel-source kernel-headers kernel-image kernel-debug --revision 1.00 --arch=powerpc --cross-compile powerpc-linux-gnu- )
#make-kpkg kernel-image --revision 1.00 --arch=powerpc --cross-compile powerpc-linux-gnu- )
#make deb-pkg ARCH=powerpc CROSS_COMPILE=powerpc-linux-gnu- -j8
#
(cd $LINUX_DIR; make ${KERNEL_BUILD_TARGET} ARCH="$ARCH" CROSS_COMPILE="$ARCH-linux-gnu-" -j${PARALLEL} )
