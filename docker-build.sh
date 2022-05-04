#!/bin/bash

# Builds the DEB inside the Docker container

set -o errexit
set -o xtrace

ARCHIVE_ADDR=http://archive.ubuntu.com/ubuntu/
PORTS_ADDR=http://ports.ubuntu.com/

# Prepare common extra libs for amd64, armhf and arm64
prepare_extra_common() {
    # Download and install zimg for zscale filter
    pushd ${SOURCE_DIR}
    git clone --depth=1 https://github.com/sekrit-twc/zimg
    pushd zimg
    case ${ARCH} in
        'amd64')
            CROSS_OPT=""
        ;;
        'armhf')
            CROSS_OPT="--host=armv7-linux-gnueabihf CC=arm-linux-gnueabihf-gcc CXX=arm-linux-gnueabihf-g++"
        ;;
        'arm64')
            CROSS_OPT="--host=aarch64-linux-gnu CC=aarch64-linux-gnu-gcc CXX=aarch64-linux-gnu-g++"
        ;;
    esac
    ./autogen.sh
    ./configure --prefix=${TARGET_DIR} ${CROSS_OPT}
    make -j $(nproc) && make install && make install DESTDIR=${SOURCE_DIR}/zimg
    echo "zimg${TARGET_DIR}/lib/libzimg.so* usr/lib/jellyfin-ffmpeg/lib" >> ${SOURCE_DIR}/debian/jellyfin-ffmpeg.install
    popd
    popd

    # Download and install dav1d
    pushd ${SOURCE_DIR}
    git clone -b 1.0.0 --depth=1 https://code.videolan.org/videolan/dav1d.git
    pushd dav1d
    mkdir build
    pushd build
    nasmver="$(nasm -v | cut -d ' ' -f3)"
    nasmminver="2.14.0"
    if [ "$(printf '%s\n' "$nasmminver" "$nasmver" | sort -V | head -n1)" = "$nasmminver" ]; then
        x86asm=true
    else
        x86asm=false
    fi
    if [ "${ARCH}" = "amd64" ]; then
        meson -Denable_asm=$x86asm \
              -Denable_{tools,tests,examples}=false \
              -Ddefault_library=shared \
              --prefix=${TARGET_DIR} ..
        ninja
        meson install
        cp ${TARGET_DIR}/lib/x86_64-linux-gnu/pkgconfig/dav1d.pc  /usr/lib/pkgconfig
        cp ${TARGET_DIR}/lib/x86_64-linux-gnu/*dav1d* ${SOURCE_DIR}/dav1d
        echo "dav1d/*dav1d* /usr/lib/jellyfin-ffmpeg/lib" >> ${SOURCE_DIR}/debian/jellyfin-ffmpeg.install
    fi
    if [ "${ARCH}" = "armhf" ] || [ "${ARCH}" = "arm64" ]; then
        meson -Denable_asm=true \
              -Denable_{tools,tests,examples}=false \
              -Ddefault_library=shared \
              --cross-file=${SOURCE_DIR}/cross-${ARCH}.meson \
              --prefix=${TARGET_DIR} ..
        ninja
        meson install
        cp ${TARGET_DIR}/lib/pkgconfig/dav1d.pc  /usr/lib/pkgconfig
        cp ${TARGET_DIR}/lib/*dav1d* ${SOURCE_DIR}/dav1d
        echo "dav1d/*dav1d* /usr/lib/jellyfin-ffmpeg/lib" >> ${SOURCE_DIR}/debian/jellyfin-ffmpeg.install
    fi
    popd
    popd
    popd

    # Download and install fdk-aac-stripped
    pushd ${SOURCE_DIR}
    git clone -b stripped4 --depth=1 https://gitlab.freedesktop.org/wtaymans/fdk-aac-stripped.git
    pushd fdk-aac-stripped
    ./autogen.sh
    ./configure \
        --disable-{static,silent-rules} \
        --prefix=${TARGET_DIR} CFLAGS="-O3 -DNDEBUG" CXXFLAGS="-O3 -DNDEBUG" ${CROSS_OPT}
    make -j$(nproc) && make install && make install DESTDIR=${SOURCE_DIR}/fdk-aac-stripped
    echo "fdk-aac-stripped${TARGET_DIR}/lib/libfdk-aac.so* usr/lib/jellyfin-ffmpeg/lib" >> ${SOURCE_DIR}/debian/jellyfin-ffmpeg.install
    popd
    popd
}

# Prepare extra headers, libs and drivers for x86_64-linux-gnu
prepare_extra_amd64() {
    # Download and install the nvidia headers
    pushd ${SOURCE_DIR}
    git clone -b n11.0.10.1 --depth=1 https://github.com/FFmpeg/nv-codec-headers
    pushd nv-codec-headers
    make
    make install
    popd
    popd

    # Download and setup AMD AMF headers
    # https://www.ffmpeg.org/general.html#AMD-AMF_002fVCE
    git clone --depth=1 https://github.com/GPUOpen-LibrariesAndSDKs/AMF
    pushd AMF/amf/public/include
    mkdir -p /usr/include/AMF
    mv * /usr/include/AMF
    popd

    # Download and install libva
    pushd ${SOURCE_DIR}
    git clone --depth=1 https://github.com/intel/libva
    pushd libva
    sed -i 's|getenv("LIBVA_DRIVERS_PATH")|"/usr/lib/jellyfin-ffmpeg/lib/dri:/usr/lib/x86_64-linux-gnu/dri:/usr/lib/dri:/usr/local/lib/dri"|g' va/va.c
    sed -i 's|getenv("LIBVA_DRIVER_NAME")|getenv("LIBVA_DRIVER_NAME_JELLYFIN")|g' va/va.c
    ./autogen.sh
    ./configure --prefix=${TARGET_DIR}
    make -j$(nproc) && make install && make install DESTDIR=${SOURCE_DIR}/intel
    echo "intel${TARGET_DIR}/lib/libva.so* usr/lib/jellyfin-ffmpeg/lib" >> ${SOURCE_DIR}/debian/jellyfin-ffmpeg.install
    echo "intel${TARGET_DIR}/lib/libva-drm.so* usr/lib/jellyfin-ffmpeg/lib" >> ${SOURCE_DIR}/debian/jellyfin-ffmpeg.install
    popd
    popd

    # Download and install libva-utils
    pushd ${SOURCE_DIR}
    git clone --depth=1 https://github.com/intel/libva-utils
    pushd libva-utils
    ./autogen.sh
    ./configure --prefix=${TARGET_DIR}
    make -j$(nproc) && make install && make install DESTDIR=${SOURCE_DIR}/intel
    echo "intel${TARGET_DIR}/bin/vainfo usr/lib/jellyfin-ffmpeg" >> ${SOURCE_DIR}/debian/jellyfin-ffmpeg.install
    popd
    popd

    # Download and install intel-vaapi-driver
    pushd ${SOURCE_DIR}
    git clone --depth=1 https://github.com/intel/intel-vaapi-driver
    pushd intel-vaapi-driver
    ./autogen.sh
    ./configure LIBVA_DRIVERS_PATH=${TARGET_DIR}/lib/dri
    make -j$(nproc) && make install
    mkdir -p ${SOURCE_DIR}/intel/dri
    cp ${TARGET_DIR}/lib/dri/i965*.so ${SOURCE_DIR}/intel/dri
    echo "intel/dri/i965*.so usr/lib/jellyfin-ffmpeg/lib/dri" >> ${SOURCE_DIR}/debian/jellyfin-ffmpeg.install
    popd
    popd

    # Download and install gmmlib
    pushd ${SOURCE_DIR}
    git clone -b intel-gmmlib-22.1.2 --depth=1 https://github.com/intel/gmmlib
    pushd gmmlib
    mkdir build && pushd build
    cmake -DCMAKE_INSTALL_PREFIX=${TARGET_DIR} ..
    make -j$(nproc) && make install && make install DESTDIR=${SOURCE_DIR}/intel
    make install
    echo "intel${TARGET_DIR}/lib/libigdgmm.so* usr/lib/jellyfin-ffmpeg/lib" >> ${SOURCE_DIR}/debian/jellyfin-ffmpeg.install
    popd
    popd
    popd

    # Download and install MediaSDK
    # Provides MSDK runtime (libmfxhw64.so.1) for 11th Gen Rocket Lake and older
    # Provides MFX dispatcher (libmfx.so.1) for FFmpeg
    pushd ${SOURCE_DIR}
    git clone -b intel-mediasdk-22.4.0 --depth=1 https://github.com/Intel-Media-SDK/MediaSDK
    pushd MediaSDK
    sed -i 's|MFX_PLUGINS_CONF_DIR "/plugins.cfg"|"/usr/lib/jellyfin-ffmpeg/lib/mfx/plugins.cfg"|g' api/mfx_dispatch/linux/mfxloader.cpp
    mkdir build && pushd build
    cmake -DCMAKE_INSTALL_PREFIX=${TARGET_DIR} \
          -DBUILD_SAMPLES=OFF \
          -DBUILD_TUTORIALS=OFF \
          ..
    make -j$(nproc) && make install && make install DESTDIR=${SOURCE_DIR}/intel
    echo "intel${TARGET_DIR}/lib/libmfx* usr/lib/jellyfin-ffmpeg/lib" >> ${SOURCE_DIR}/debian/jellyfin-ffmpeg.install
    echo "intel${TARGET_DIR}/lib/mfx/*.so usr/lib/jellyfin-ffmpeg/lib/mfx" >> ${SOURCE_DIR}/debian/jellyfin-ffmpeg.install
    echo "intel${TARGET_DIR}/share/mfx/plugins.cfg usr/lib/jellyfin-ffmpeg/lib/mfx" >> ${SOURCE_DIR}/debian/jellyfin-ffmpeg.install
    popd
    popd
    popd

    # Download and install oneVPL-intel-gpu
    # Provides VPL runtime (libmfx-gen.so.1.2) for 11th Gen Tiger Lake and newer
    # Both MSDK and VPL runtime can be loaded by MFX dispatcher (libmfx.so.1)
    pushd ${SOURCE_DIR}
    git clone -b intel-onevpl-22.4.0 --depth=1 https://github.com/oneapi-src/oneVPL-intel-gpu
    pushd oneVPL-intel-gpu
    mkdir build && pushd build
    cmake -DCMAKE_INSTALL_PREFIX=${TARGET_DIR} ..
    make -j$(nproc) && make install && make install DESTDIR=${SOURCE_DIR}/intel
    echo "intel${TARGET_DIR}/lib/libmfx-gen* usr/lib/jellyfin-ffmpeg/lib" >> ${SOURCE_DIR}/debian/jellyfin-ffmpeg.install
    popd
    popd
    popd

    # Download and install media-driver
    # Full Feature Build: ENABLE_KERNELS=ON(Default) ENABLE_NONFREE_KERNELS=ON(Default)
    # Free Kernel Build: ENABLE_KERNELS=ON ENABLE_NONFREE_KERNELS=OFF
    pushd ${SOURCE_DIR}
    git clone -b intel-media-22.4.0 --depth=1 https://github.com/intel/media-driver
    pushd media-driver
    sed -i 's|find_package(X11)||g' media_softlet/media_top_cmake.cmake media_driver/media_top_cmake.cmake
    mkdir build && pushd build
    cmake -DCMAKE_INSTALL_PREFIX=${TARGET_DIR} \
          -DENABLE_KERNELS=ON \
          -DENABLE_NONFREE_KERNELS=ON \
          LIBVA_DRIVERS_PATH=${TARGET_DIR}/lib/dri \
          ..
    make -j$(nproc) && make install && make install DESTDIR=${SOURCE_DIR}/intel
    echo "intel${TARGET_DIR}/lib/libigfxcmrt.so* usr/lib/jellyfin-ffmpeg/lib" >> ${SOURCE_DIR}/debian/jellyfin-ffmpeg.install
    mkdir -p ${SOURCE_DIR}/intel/dri
    cp ${TARGET_DIR}/lib/dri/iHD*.so ${SOURCE_DIR}/intel/dri
    echo "intel/dri/iHD*.so usr/lib/jellyfin-ffmpeg/lib/dri" >> ${SOURCE_DIR}/debian/jellyfin-ffmpeg.install
    popd
    popd
    popd
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
    yes | apt-get install -y -o APT::Immediate-Configure=0 gcc-${GCC_VER}-source gcc-${GCC_VER}-arm-linux-gnueabihf g++-${GCC_VER}-arm-linux-gnueabihf libstdc++6-armhf-cross binutils-arm-linux-gnueabihf bison flex libtool gdb sharutils netbase libmpc-dev libmpfr-dev libgmp-dev systemtap-sdt-dev autogen expect chrpath zlib1g-dev zip libc6-dev:armhf linux-libc-dev:armhf libgcc1:armhf libcurl4-openssl-dev:armhf libfontconfig1-dev:armhf libfreetype6-dev:armhf libstdc++6:armhf
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
    yes | apt-get install -y -o APT::Immediate-Configure=0 gcc-${GCC_VER}-source gcc-${GCC_VER}-aarch64-linux-gnu g++-${GCC_VER}-aarch64-linux-gnu libstdc++6-arm64-cross binutils-aarch64-linux-gnu bison flex libtool gdb sharutils netbase libmpc-dev libmpfr-dev libgmp-dev systemtap-sdt-dev autogen expect chrpath zlib1g-dev zip libc6-dev:arm64 linux-libc-dev:arm64 libgcc1:arm64 libcurl4-openssl-dev:arm64 libfontconfig1-dev:arm64 libfreetype6-dev:arm64 libstdc++6:arm64
    popd
}

# Set the architecture-specific options
case ${ARCH} in
    'amd64')
        prepare_extra_common
        prepare_extra_amd64
        CONFIG_SITE=""
        DEP_ARCH_OPT=""
        BUILD_ARCH_OPT=""
    ;;
    'armhf')
        prepare_crossbuild_env_armhf
        ln -s /usr/bin/arm-linux-gnueabihf-gcc-${GCC_VER} /usr/bin/arm-linux-gnueabihf-gcc
        ln -s /usr/bin/arm-linux-gnueabihf-gcc-ar-${GCC_VER} /usr/bin/arm-linux-gnueabihf-gcc-ar
        ln -s /usr/bin/arm-linux-gnueabihf-g++-${GCC_VER} /usr/bin/arm-linux-gnueabihf-g++
        prepare_extra_common
        CONFIG_SITE="/etc/dpkg-cross/cross-config.${ARCH}"
        DEP_ARCH_OPT="--host-arch armhf"
        BUILD_ARCH_OPT="-aarmhf"
    ;;
    'arm64')
        prepare_crossbuild_env_arm64
        ln -s /usr/bin/aarch64-linux-gnu-gcc-${GCC_VER} /usr/bin/aarch64-linux-gnu-gcc
        ln -s /usr/bin/aarch64-linux-gnu-gcc-ar-${GCC_VER} /usr/bin/aarch64-linux-gnu-gcc-ar
        ln -s /usr/bin/aarch64-linux-gnu-g++-${GCC_VER} /usr/bin/aarch64-linux-gnu-g++
        prepare_extra_common
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
