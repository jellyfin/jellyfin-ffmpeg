#!/bin/bash

# Builds the DEB inside the Docker container

set -o errexit
set -o xtrace

ARCHIVE_ADDR=http://archive.ubuntu.com/ubuntu/
PORTS_ADDR=http://ports.ubuntu.com/

# Prepare HWA headers, libs and drivers for x86_64-linux-gnu
prepare_hwa_amd64() {
    # Download and install the nvidia headers
    pushd ${SOURCE_DIR}
    git clone --depth=1 https://git.videolan.org/git/ffmpeg/nv-codec-headers.git
    pushd nv-codec-headers
    make
    make install
    popd
    popd

    # Download and setup AMD AMF headers
    # https://www.ffmpeg.org/general.html#AMD-AMF_002fVCE
    svn checkout https://github.com/GPUOpen-LibrariesAndSDKs/AMF/trunk/amf/public/include
    pushd include
    mkdir -p /usr/include/AMF
    mv * /usr/include/AMF
    popd

    # Download and install libva
    pushd ${SOURCE_DIR}
    git clone -b v2.6-branch --depth=1 https://github.com/intel/libva
    pushd libva
    sed -i 's|getenv("LIBVA_DRIVERS_PATH")|"/usr/lib/jellyfin-ffmpeg/lib/dri:/usr/lib/x86_64-linux-gnu/dri:/usr/lib/dri:/usr/local/lib/dri"|g' va/va.c
    sed -i 's|getenv("LIBVA_DRIVER_NAME")|NULL|g' va/va.c
    ./autogen.sh
    ./configure --prefix=${TARGET_DIR}
    make -j$(nproc) && make install && make install DESTDIR=${SOURCE_DIR}/intel
    echo "intel${TARGET_DIR}/lib/libva.so* usr/lib/jellyfin-ffmpeg/lib" >> ${SOURCE_DIR}/debian/jellyfin-ffmpeg.install
    echo "intel${TARGET_DIR}/lib/libva-drm.so* usr/lib/jellyfin-ffmpeg/lib" >> ${SOURCE_DIR}/debian/jellyfin-ffmpeg.install
    popd
    popd

    # Download and install intel-vaapi-driver
    pushd ${SOURCE_DIR}
    git clone -b v2.4-branch --depth=1 https://github.com/intel/intel-vaapi-driver
    pushd intel-vaapi-driver
    ./autogen.sh
    ./configure LIBVA_DRIVERS_PATH=${TARGET_DIR}/lib/dri
    make -j$(nproc) && make install
    mkdir -p ${SOURCE_DIR}/intel/dri
    cp ${TARGET_DIR}/lib/dri/i965*.so ${SOURCE_DIR}/intel/dri
    echo "intel/dri/i965*.so usr/lib/jellyfin-ffmpeg/lib/dri" >> ${SOURCE_DIR}/debian/jellyfin-ffmpeg.install
    popd
    popd

    # Uncomment for non-free QSV
    # Download and install gmmlib
    #pushd ${SOURCE_DIR}
    #git clone -b intel-gmmlib-19.3.4.x --depth=1 https://github.com/intel/gmmlib
    #pushd gmmlib
    #mkdir build && pushd build
    #cmake -DCMAKE_INSTALL_PREFIX=${TARGET_DIR} ..
    #make -j$(nproc) && make install && make install DESTDIR=${SOURCE_DIR}/intel
    #make install
    #echo "intel${TARGET_DIR}/lib/libigdgmm.so* usr/lib/jellyfin-ffmpeg/lib" >> ${SOURCE_DIR}/debian/jellyfin-ffmpeg.install
    #popd
    #popd
    #popd

    # Uncomment for non-free QSV
    # Download and install media-driver
    # Full Feature Build: ENABLE_KERNELS=ON(Default) ENABLE_NONFREE_KERNELS=ON(Default)
    # Free Kernel Build: ENABLE_KERNELS=ON ENABLE_NONFREE_KERNELS=OFF
    #pushd ${SOURCE_DIR}
    #git clone -b intel-media-19.4 --depth=1 https://github.com/intel/media-driver
    #pushd media-driver
    #mkdir build && pushd build
    #cmake -DCMAKE_INSTALL_PREFIX=${TARGET_DIR} \
    #      -DENABLE_KERNELS=ON \
    #      -DENABLE_NONFREE_KERNELS=ON \
    #      LIBVA_DRIVERS_PATH=${TARGET_DIR}/lib/dri \
    #      ..
    #make -j$(nproc) && make install && make install DESTDIR=${SOURCE_DIR}/intel
    #echo "intel${TARGET_DIR}/lib/libigfxcmrt.so* usr/lib/jellyfin-ffmpeg/lib" >> ${SOURCE_DIR}/debian/jellyfin-ffmpeg.install
    #mkdir -p ${SOURCE_DIR}/intel/dri
    #cp ${TARGET_DIR}/lib/dri/iHD*.so ${SOURCE_DIR}/intel/dri
    #echo "intel/dri/iHD*.so usr/lib/jellyfin-ffmpeg/lib/dri" >> ${SOURCE_DIR}/debian/jellyfin-ffmpeg.install
    #popd
    #popd
    #popd

    # Uncomment for non-free QSV
    # Download and install MediaSDK
    #pushd ${SOURCE_DIR}
    #git clone -b intel-mediasdk-19.4 --depth=1 https://github.com/Intel-Media-SDK/MediaSDK
    #pushd MediaSDK
    #sed -i 's|MFX_PLUGINS_CONF_DIR "/plugins.cfg"|"/usr/lib/jellyfin-ffmpeg/lib/mfx/plugins.cfg"|g' api/mfx_dispatch/linux/mfxloader.cpp
    #mkdir build && pushd build
    #cmake -DCMAKE_INSTALL_PREFIX=${TARGET_DIR} ..
    #make -j$(nproc) && make install && make install DESTDIR=${SOURCE_DIR}/intel
    #echo "intel${TARGET_DIR}/lib/libmfx* usr/lib/jellyfin-ffmpeg/lib" >> ${SOURCE_DIR}/debian/jellyfin-ffmpeg.install
    #echo "intel${TARGET_DIR}/lib/mfx/*.so usr/lib/jellyfin-ffmpeg/lib/mfx" >> ${SOURCE_DIR}/debian/jellyfin-ffmpeg.install
    #echo "intel${TARGET_DIR}/share/mfx/plugins.cfg usr/lib/jellyfin-ffmpeg/lib/mfx" >> ${SOURCE_DIR}/debian/jellyfin-ffmpeg.install
    #popd
    #popd
    #popd
}
# Prepare the cross-toolchain
prepare_crossbuild_env_armhf() {
    # Prepare the Ubuntu-specific cross-build requirements
    if [[ $( lsb_release -i -s ) == "Ubuntu" ]]; then
        CODENAME="$( lsb_release -c -s )"
        # Remove the default sources.list
        rm /etc/apt/sources.list
        # Add arch-specific list files
        cat <<EOF > /etc/apt/sources.list.d/amd64.list
deb [arch=amd64] ${ARCHIVE_ADDR} ${CODENAME} main restricted universe multiverse
deb [arch=amd64] ${ARCHIVE_ADDR} ${CODENAME}-updates main restricted universe multiverse
deb [arch=amd64] ${ARCHIVE_ADDR} ${CODENAME}-backports main restricted universe multiverse
deb [arch=amd64] ${ARCHIVE_ADDR} ${CODENAME}-security main restricted universe multiverse
EOF
        cat <<EOF > /etc/apt/sources.list.d/armhf.list
deb [arch=armhf] ${PORTS_ADDR} ${CODENAME} main restricted universe multiverse
deb [arch=armhf] ${PORTS_ADDR} ${CODENAME}-updates main restricted universe multiverse
deb [arch=armhf] ${PORTS_ADDR} ${CODENAME}-backports main restricted universe multiverse
deb [arch=armhf] ${PORTS_ADDR} ${CODENAME}-security main restricted universe multiverse
EOF
    fi
    # Add armhf architecture
    dpkg --add-architecture armhf
    # Update and install cross-gcc-dev
    apt-get update
    yes | apt-get install -y cross-gcc-dev
    # Generate gcc cross source
    TARGET_LIST="armhf" cross-gcc-gensource ${GCC_VER}
    # Install dependencies
    pushd cross-gcc-packages-amd64/cross-gcc-${GCC_VER}-armhf
    ln -fs /usr/share/zoneinfo/America/Toronto /etc/localtime
    yes | apt-get install -y -o APT::Immediate-Configure=0 gcc-${GCC_VER}-source libstdc++6-armhf-cross binutils-arm-linux-gnueabihf bison flex libtool gdb sharutils netbase libmpc-dev libmpfr-dev libgmp-dev systemtap-sdt-dev autogen expect chrpath zlib1g-dev zip libc6-dev:armhf linux-libc-dev:armhf libgcc1:armhf libcurl4-openssl-dev:armhf libfontconfig1-dev:armhf libfreetype6-dev:armhf liblttng-ust0:armhf libstdc++6:armhf
    popd

    # Fetch RasPi headers to build MMAL support
    pushd ${SOURCE_DIR}
    git clone --depth=1 https://github.com/raspberrypi/firmware mmalheaders
    git clone --depth=1 https://github.com/raspberrypi/userland piuserland
    cp -a mmalheaders/opt/vc/include/* /usr/include/
    cp -a mmalheaders/opt/vc/lib/* /usr/lib/
    cp -a piuserland/interface/* /usr/include/
    popd
}
prepare_crossbuild_env_arm64() {
    # Prepare the Ubuntu-specific cross-build requirements
    if [[ $( lsb_release -i -s ) == "Ubuntu" ]]; then
        CODENAME="$( lsb_release -c -s )"
        # Remove the default sources.list
        rm /etc/apt/sources.list
        # Add arch-specific list files
        cat <<EOF > /etc/apt/sources.list.d/amd64.list
deb [arch=amd64] ${ARCHIVE_ADDR} ${CODENAME} main restricted universe multiverse
deb [arch=amd64] ${ARCHIVE_ADDR} ${CODENAME}-updates main restricted universe multiverse
deb [arch=amd64] ${ARCHIVE_ADDR} ${CODENAME}-backports main restricted universe multiverse
deb [arch=amd64] ${ARCHIVE_ADDR} ${CODENAME}-security main restricted universe multiverse
EOF
        cat <<EOF > /etc/apt/sources.list.d/arm64.list
deb [arch=arm64] ${PORTS_ADDR} ${CODENAME} main restricted universe multiverse
deb [arch=arm64] ${PORTS_ADDR} ${CODENAME}-updates main restricted universe multiverse
deb [arch=arm64] ${PORTS_ADDR} ${CODENAME}-backports main restricted universe multiverse
deb [arch=arm64] ${PORTS_ADDR} ${CODENAME}-security main restricted universe multiverse
EOF
    fi
    # Add armhf architecture
    dpkg --add-architecture arm64
    # Update and install cross-gcc-dev
    apt-get update
    yes | apt-get install -y cross-gcc-dev
    # Generate gcc cross source
    TARGET_LIST="arm64" cross-gcc-gensource ${GCC_VER}
    # Install dependencies
    pushd cross-gcc-packages-amd64/cross-gcc-${GCC_VER}-arm64
    ln -fs /usr/share/zoneinfo/America/Toronto /etc/localtime
    yes | apt-get install -y -o APT::Immediate-Configure=0 gcc-${GCC_VER}-source libstdc++6-arm64-cross binutils-aarch64-linux-gnu bison flex libtool gdb sharutils netbase libmpc-dev libmpfr-dev libgmp-dev systemtap-sdt-dev autogen expect chrpath zlib1g-dev zip libc6-dev:arm64 linux-libc-dev:arm64 libgcc1:arm64 libcurl4-openssl-dev:arm64 libfontconfig1-dev:arm64 libfreetype6-dev:arm64 liblttng-ust0:arm64 libstdc++6:arm64
    popd
}

# Set the architecture-specific options
case ${ARCH} in
    'amd64')
        prepare_hwa_amd64
        CONFIG_SITE=""
        DEP_ARCH_OPT=""
        BUILD_ARCH_OPT=""
    ;;
    'armhf')
        prepare_crossbuild_env_armhf
        ln -s /usr/bin/arm-linux-gnueabihf-gcc-6 /usr/bin/arm-linux-gnueabihf-gcc
        CONFIG_SITE="/etc/dpkg-cross/cross-config.${ARCH}"
        DEP_ARCH_OPT="--host-arch armhf"
        BUILD_ARCH_OPT="-aarmhf"
    ;;
    'arm64')
        prepare_crossbuild_env_arm64
        #ln -s /usr/bin/arm-linux-gnueabihf-gcc-6 /usr/bin/arm-linux-gnueabihf-gcc
        CONFIG_SITE="/etc/dpkg-cross/cross-config.${ARCH}"
        DEP_ARCH_OPT="--host-arch arm64"
        BUILD_ARCH_OPT="-aarm64"
    ;;
esac

# Move to source directory
pushd ${SOURCE_DIR}

# Install dependencies and build the deb
yes | mk-build-deps -i ${DEP_ARCH_OPT}
dpkg-buildpackage -b -rfakeroot -us -uc ${BUILD_ARCH_OPT}

popd

# Move the artifacts out
mkdir -p ${ARTIFACT_DIR}/deb
mv /jellyfin-ffmpeg_* ${ARTIFACT_DIR}/deb/
chown -Rc $(stat -c %u:%g ${ARTIFACT_DIR}) ${ARTIFACT_DIR}
