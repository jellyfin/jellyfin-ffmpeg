#!/bin/bash

# Builds the DEB inside the Docker container

set -o errexit
set -o xtrace

ARCHIVE_ADDR=http://archive.ubuntu.com/ubuntu/
PORTS_ADDR=http://ports.ubuntu.com/

# Prepare common extra libs for amd64, armhf and arm64
prepare_extra_common() {
    # ZIMG
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

    # DAV1D
    pushd ${SOURCE_DIR}
    git clone -b 1.0.0 --depth=1 https://code.videolan.org/videolan/dav1d.git
    nasmver="$(nasm -v | cut -d ' ' -f3)"
    nasmminver="2.14.0"
    if [ "$(printf '%s\n' "$nasmminver" "$nasmver" | sort -V | head -n1)" = "$nasmminver" ]; then
        x86asm=true
    else
        x86asm=false
    fi
    if [ "${ARCH}" = "amd64" ]; then
        meson setup dav1d dav1d_build \
            --prefix=${TARGET_DIR} \
            --libdir=lib \
            -Ddefault_library=shared \
            -Denable_asm=$x86asm \
            -Denable_{tools,tests,examples}=false
        meson configure dav1d_build
        ninja -C dav1d_build install
        cp ${TARGET_DIR}/lib/libdav1d.so* ${SOURCE_DIR}/dav1d
        echo "dav1d/libdav1d.so* /usr/lib/jellyfin-ffmpeg/lib" >> ${SOURCE_DIR}/debian/jellyfin-ffmpeg.install
    fi
    if [ "${ARCH}" = "armhf" ] || [ "${ARCH}" = "arm64" ]; then
        meson setup dav1d dav1d_build \
            --cross-file=${SOURCE_DIR}/cross-${ARCH}.meson \
            --prefix=${TARGET_DIR} \
            --libdir=lib \
            --buildtype=release \
            -Ddefault_library=shared \
            -Denable_asm=true \
            -Denable_{tools,tests,examples}=false
        meson configure dav1d_build
        ninja -C dav1d_build install
        cp ${TARGET_DIR}/lib/libdav1d.so* ${SOURCE_DIR}/dav1d
        echo "dav1d/libdav1d.so* /usr/lib/jellyfin-ffmpeg/lib" >> ${SOURCE_DIR}/debian/jellyfin-ffmpeg.install
    fi
    popd

    # FDK-AAC-STRIPPED
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
    # FFNVCODEC
    pushd ${SOURCE_DIR}
    git clone -b n11.0.10.1 --depth=1 https://github.com/FFmpeg/nv-codec-headers
    pushd nv-codec-headers
    make
    make install
    popd
    popd

    # AMF
    # https://www.ffmpeg.org/general.html#AMD-AMF_002fVCE
    git clone --depth=1 https://github.com/GPUOpen-LibrariesAndSDKs/AMF
    pushd AMF/amf/public/include
    mkdir -p /usr/include/AMF
    mv * /usr/include/AMF
    popd

    # LIBDRM
    pushd ${SOURCE_DIR}
    git clone -b libdrm-2.4.110 --depth=1 https://gitlab.freedesktop.org/mesa/drm.git
    meson setup drm drm_build \
        --prefix=${TARGET_DIR} \
        --libdir=lib \
        --buildtype=release \
        -D{amdgpu,radeon,intel,udev}=true \
        -D{libkms,valgrind,freedreno,vc4,vmwgfx,nouveau,man-pages}=false
    meson configure drm_build
    ninja -C drm_build install
    cp ${TARGET_DIR}/lib/libdrm*.so* ${SOURCE_DIR}/drm
    cp ${TARGET_DIR}/share/libdrm/*.ids ${SOURCE_DIR}/drm
    echo "drm/libdrm*.so* usr/lib/jellyfin-ffmpeg/lib" >> ${SOURCE_DIR}/debian/jellyfin-ffmpeg.install
    echo "drm/*.ids usr/lib/jellyfin-ffmpeg/share/libdrm" >> ${SOURCE_DIR}/debian/jellyfin-ffmpeg.install
    popd

    # LIBVA
    pushd ${SOURCE_DIR}
    git clone --depth=1 https://github.com/intel/libva
    pushd libva
    sed -i 's|getenv("LIBVA_DRIVERS_PATH")|"/usr/lib/jellyfin-ffmpeg/lib/dri:/usr/lib/x86_64-linux-gnu/dri:/usr/lib/dri:/usr/local/lib/dri"|g' va/va.c
    sed -i 's|getenv("LIBVA_DRIVER_NAME")|getenv("LIBVA_DRIVER_NAME_JELLYFIN")|g' va/va.c
    ./autogen.sh
    ./configure \
        --prefix=${TARGET_DIR} \
        --enable-drm \
        --disable-{glx,x11,wayland,docs}
    make -j$(nproc) && make install && make install DESTDIR=${SOURCE_DIR}/intel
    echo "intel${TARGET_DIR}/lib/libva.so* usr/lib/jellyfin-ffmpeg/lib" >> ${SOURCE_DIR}/debian/jellyfin-ffmpeg.install
    echo "intel${TARGET_DIR}/lib/libva-drm.so* usr/lib/jellyfin-ffmpeg/lib" >> ${SOURCE_DIR}/debian/jellyfin-ffmpeg.install
    popd
    popd

    # LIBVA-UTILS
    pushd ${SOURCE_DIR}
    git clone --depth=1 https://github.com/intel/libva-utils
    pushd libva-utils
    ./autogen.sh
    ./configure --prefix=${TARGET_DIR}
    make -j$(nproc) && make install && make install DESTDIR=${SOURCE_DIR}/intel
    echo "intel${TARGET_DIR}/bin/vainfo usr/lib/jellyfin-ffmpeg" >> ${SOURCE_DIR}/debian/jellyfin-ffmpeg.install
    popd
    popd

    # INTEL-VAAPI-DRIVER
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

    # GMMLIB
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

    # MediaSDK
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

    # ONEVPL-INTEL-GPU
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

    # MEDIA-DRIVER
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

    # Vulkan Headers
    pushd ${SOURCE_DIR}
    git clone -b v1.3.212 --depth=1 https://github.com/KhronosGroup/Vulkan-Headers
    pushd Vulkan-Headers
    mkdir build && pushd build
    cmake \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_INSTALL_PREFIX=${TARGET_DIR} ..
    make -j$(nproc) && make install
    popd
    popd
    popd

    # Vulkan ICD Loader
    pushd ${SOURCE_DIR}
    git clone -b v1.3.212 --depth=1 https://github.com/KhronosGroup/Vulkan-Loader
    pushd Vulkan-Loader
    mkdir build && pushd build
    cmake \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_INSTALL_PREFIX=${TARGET_DIR} \
        -DVULKAN_HEADERS_INSTALL_DIR="${TARGET_DIR}" \
        -DCMAKE_INSTALL_SYSCONFDIR=${TARGET_DIR}/share \
        -DCMAKE_INSTALL_DATADIR=${TARGET_DIR}/share \
        -DCMAKE_INSTALL_LIBDIR=lib \
        -DBUILD_TESTS=OFF \
        -DBUILD_WSI_{XCB,XLIB,WAYLAND}_SUPPORT=ON ..
    make -j$(nproc) && make install
    cp ${TARGET_DIR}/lib/libvulkan.so* ${SOURCE_DIR}/Vulkan-Loader
    echo "Vulkan-Loader/libvulkan.so* usr/lib/jellyfin-ffmpeg/lib" >> ${SOURCE_DIR}/debian/jellyfin-ffmpeg.install
    popd
    popd
    popd

    # SHADERC
    pushd ${SOURCE_DIR}
    git clone -b v2022.1 --depth=1 https://github.com/google/shaderc
    pushd shaderc
    ./utils/git-sync-deps
    mkdir build && pushd build
    cmake \
        -GNinja \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_INSTALL_PREFIX=${TARGET_DIR} \
        -DSHADERC_SKIP_{TESTS,EXAMPLES,COPYRIGHT_CHECK}=ON \
        -DENABLE_{GLSLANG_BINARIES,EXCEPTIONS}=ON \
        -DENABLE_CTEST=OFF \
        -DSPIRV_SKIP_EXECUTABLES=ON \
        -DSPIRV_TOOLS_BUILD_STATIC=ON \
        -DBUILD_SHARED_LIBS=OFF ..
    ninja -j$(nproc)
    ninja install
    cp ${TARGET_DIR}/lib/libshaderc_shared.so* ${SOURCE_DIR}/shaderc
    echo "shaderc/libshaderc_shared* usr/lib/jellyfin-ffmpeg/lib" >> ${SOURCE_DIR}/debian/jellyfin-ffmpeg.install
    popd
    popd
    popd

    # MESA
    # Minimal libs for AMD VAAPI, AMD RADV and Intel ANV
    if [[ $( lsb_release -c -s ) != "bionic" ]]; then
        # llvm >= 11
        apt-get install -y llvm-11-dev
        pushd ${SOURCE_DIR}
        git clone -b mesa-22.0.2 --depth=1 https://gitlab.freedesktop.org/mesa/mesa.git
        meson setup mesa mesa_build \
            --prefix=${TARGET_DIR} \
            --libdir=lib \
            --buildtype=release \
            --wrap-mode=nofallback \
            -Db_ndebug=true \
            -Db_lto=false \
            -Dplatforms=x11\
            -Ddri-drivers=[] \
            -Dgallium-drivers=radeonsi \
            -Dvulkan-drivers=amd,intel \
            -Dvulkan-layers=device-select,overlay \
            -Ddri3=enabled \
            -Degl=disabled \
            -Dgallium-{extra-hud,nine}=false \
            -Dgallium-{omx,vdpau,xa,xvmc,opencl}=disabled \
            -Dgallium-va=enabled \
            -Dgbm=disabled \
            -Dgles1=disabled \
            -Dgles2=disabled \
            -Dopengl=false \
            -Dglvnd=false \
            -Dglx=disabled \
            -Dlibunwind=disabled \
            -Dllvm=enabled \
            -Dlmsensors=disabled \
            -Dosmesa=false \
            -Dshared-glapi=disabled \
            -Dvalgrind=disabled \
            -Dtools=[] \
            -Dzstd=enabled \
            -Dmicrosoft-clc=disabled
        meson configure mesa_build
        ninja -C mesa_build install
        cp ${TARGET_DIR}/lib/libvulkan_*.so ${SOURCE_DIR}/mesa
        cp ${TARGET_DIR}/lib/libVkLayer_MESA*.so ${SOURCE_DIR}/mesa
        cp ${TARGET_DIR}/lib/dri/radeonsi_drv_video.so ${SOURCE_DIR}/mesa
        echo "mesa/lib*.so usr/lib/jellyfin-ffmpeg/lib" >> ${SOURCE_DIR}/debian/jellyfin-ffmpeg.install
        echo "mesa/radeonsi_drv_video.so usr/lib/jellyfin-ffmpeg/lib/dri" >> ${SOURCE_DIR}/debian/jellyfin-ffmpeg.install
        cp ${TARGET_DIR}/share/drirc.d/*.conf ${SOURCE_DIR}/mesa
        echo "mesa/*defaults.conf usr/lib/jellyfin-ffmpeg/share/drirc.d" >> ${SOURCE_DIR}/debian/jellyfin-ffmpeg.install
        cp ${TARGET_DIR}/share/vulkan/{icd.d,explicit_layer.d,implicit_layer.d}/*.json ${SOURCE_DIR}/mesa
        echo "mesa/*icd.x86_64.json usr/lib/jellyfin-ffmpeg/share/vulkan/icd.d" >> ${SOURCE_DIR}/debian/jellyfin-ffmpeg.install
        echo "mesa/*overlay.json usr/lib/jellyfin-ffmpeg/share/vulkan/explicit_layer.d" >> ${SOURCE_DIR}/debian/jellyfin-ffmpeg.install
        echo "mesa/*device_select.json usr/lib/jellyfin-ffmpeg/share/vulkan/implicit_layer.d" >> ${SOURCE_DIR}/debian/jellyfin-ffmpeg.install
        popd
    fi

    # LIBPLACEBO
    pushd ${SOURCE_DIR}
    git clone --depth=1 https://github.com/haasn/libplacebo
    meson setup libplacebo placebo_build \
        --prefix=${TARGET_DIR} \
        --libdir=lib \
        --buildtype=release \
        --default-library=shared \
        -Dvulkan=enabled \
        -Dvulkan-link=false \
        -Dvulkan-registry=${TARGET_DIR}/share/vulkan/registry/vk.xml \
        -Dshaderc=enabled \
        -Dglslang=disabled \
        -D{demos,tests,bench,fuzz}=false
    meson configure placebo_build
    ninja -C placebo_build install
    cp ${TARGET_DIR}/lib/libplacebo.so* ${SOURCE_DIR}/libplacebo
    echo "libplacebo/libplacebo* usr/lib/jellyfin-ffmpeg/lib" >> ${SOURCE_DIR}/debian/jellyfin-ffmpeg.install
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
mv /jellyfin-ffmpeg{,5}_* ${ARTIFACT_DIR}/deb/
chown -Rc $(stat -c %u:%g ${ARTIFACT_DIR}) ${ARTIFACT_DIR}
