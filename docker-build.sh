#!/bin/bash

NVCH_VERSION="8.2.15.8-dmo1"

# Builds the DEB inside the Docker container

set -o errexit
set -o xtrace

# Prepare the cross-toolchain
prepare_crossbuild_env() {
    # Add armhf architecture
    dpkg --add-architecture armhf
    # Update and install cross-gcc-dev
    apt-get update
    apt-get install -y cross-gcc-dev
    # Generate gcc cross source
    TARGET_LIST="armhf" cross-gcc-gensource ${GCC_VER}
    # Install dependencies
    pushd cross-gcc-packages-amd64/cross-gcc-${GCC_VER}-armhf
    apt-get install -y gcc-${GCC_VER}-source libstdc++6-armhf-cross binutils-arm-linux-gnueabihf bison flex libtool gdb sharutils netbase libcloog-isl-dev libmpc-dev libmpfr-dev libgmp-dev systemtap-sdt-dev autogen expect chrpath zlib1g-dev zip libc6-dev:armhf linux-libc-dev:armhf libgcc1:armhf libcurl4-openssl-dev:armhf libfontconfig1-dev:armhf libfreetype6-dev:armhf liblttng-ust0:armhf libstdc++6:armhf
    popd
}

# Set the architecture-specific options
case ${ARCH} in
    'amd64')
        CONFIG_SITE=""
        DEP_ARCH_OPT=""
        BUILD_ARCH_OPT=""
    ;;
    'armhf')
        prepare_crossbuild_env
        ln -s /usr/bin/arm-linux-gnueabihf-gcc-6 /usr/bin/arm-linux-gnueabihf-gcc
        CONFIG_SITE="/etc/dpkg-cross/cross-config.${ARCH}"
        DEP_ARCH_OPT="--host-arch armhf"
        BUILD_ARCH_OPT="-aarmhf"
    ;;
esac

# Download and install the nvidia headers from deb-multimedia
wget -O nv-codec-headers.deb https://www.deb-multimedia.org/pool/main/n/nv-codec-headers-dmo/nv-codec-headers_${NVCH_VERSION}_all.deb
dpkg -i nv-codec-headers.deb
apt -f install

# Move to source directory
pushd ${SOURCE_DIR}

# Install dependencies and build the deb
yes | mk-build-deps -i ${DEP_ARCH_OPT}
dpkg-buildpackage -b -rfakeroot -us -uc ${BUILD_ARCH_OPT}

popd

# Move the artifacts out
mkdir -p ${ARTIFACT_DIR}/deb
mv /jellyfin-ffmpeg_* ${ARTIFACT_DIR}/deb/
