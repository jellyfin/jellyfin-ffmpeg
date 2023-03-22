#!/bin/bash

# Builds the DEB inside the Docker container

set -o errexit
set -o xtrace

DEBIAN_ADDR=http://deb.debian.org/debian/
UBUNTU_ARCHIVE_ADDR=http://archive.ubuntu.com/ubuntu/
UBUNTU_PORTS_ADDR=http://ports.ubuntu.com/

# Prepare common extra libs for amd64, armhf and arm64
prepare_extra_common() {
    case ${ARCH} in
        'amd64')
            CROSS_OPT=""
            CMAKE_TOOLCHAIN_OPT=""
            MESON_CROSS_OPT=""
        ;;
        'armhf')
            CROSS_OPT="--host=armv7-linux-gnueabihf CC=arm-linux-gnueabihf-gcc CXX=arm-linux-gnueabihf-g++"
            CMAKE_TOOLCHAIN_OPT="-DCMAKE_TOOLCHAIN_FILE=${SOURCE_DIR}/toolchain-${ARCH}.cmake"
            MESON_CROSS_OPT="--cross-file=${SOURCE_DIR}/cross-${ARCH}.meson"
        ;;
        'arm64')
            CROSS_OPT="--host=aarch64-linux-gnu CC=aarch64-linux-gnu-gcc CXX=aarch64-linux-gnu-g++"
            CMAKE_TOOLCHAIN_OPT="-DCMAKE_TOOLCHAIN_FILE=${SOURCE_DIR}/toolchain-${ARCH}.cmake"
            MESON_CROSS_OPT="--cross-file=${SOURCE_DIR}/cross-${ARCH}.meson"
        ;;
    esac

    # FFTW3
    pushd ${SOURCE_DIR}
    mkdir fftw3
    pushd fftw3
    fftw3_ver="3.3.10"
    fftw3_link="https://fftw.org/fftw-${fftw3_ver}.tar.gz"
    wget ${fftw3_link} -O fftw3.tar.gz
    tar xaf fftw3.tar.gz
    pushd fftw-${fftw3_ver}
    if [ "${ARCH}" = "amd64" ]; then
        fftw3_optimizations="--enable-sse2 --enable-avx --enable-avx-128-fma --enable-avx2 --enable-avx512"
    else
        fftw3_optimizations="--enable-neon"
    fi
    ./configure \
        ${CROSS_OPT} \
        --prefix=${TARGET_DIR} \
        --disable-{static,doc} \
        --enable-{shared,single,threads,fortran} \
        $fftw3_optimizations \
        --with-our-malloc \
        --with-combined-threads \
        --with-incoming-stack-boundary=2
    make -j$(nproc) && make install && make install DESTDIR=${SOURCE_DIR}/fftw3
    echo "fftw3${TARGET_DIR}/lib/libfftw3f.so* usr/lib/jellyfin-ffmpeg/lib" >> ${DPKG_INSTALL_LIST}
    popd
    popd
    popd

    # CHROMAPRINT
    pushd ${SOURCE_DIR}
    git clone --depth=1 https://github.com/acoustid/chromaprint.git
    pushd chromaprint
    mkdir build
    pushd build
    cmake \
        ${CMAKE_TOOLCHAIN_OPT} \
        -DCMAKE_INSTALL_PREFIX=${TARGET_DIR} \
        -DCMAKE_BUILD_TYPE=Release \
        -DBUILD_SHARED_LIBS=ON \
        -DBUILD_{TOOLS,TESTS}=OFF \
        -DFFT_LIB=fftw3f \
        ..
    make -j$(nproc) && make install && make install DESTDIR=${SOURCE_DIR}/chromaprint
    echo "chromaprint${TARGET_DIR}/lib/libchromaprint.so* usr/lib/jellyfin-ffmpeg/lib" >> ${DPKG_INSTALL_LIST}
    popd
    popd
    popd

    # ZIMG
    pushd ${SOURCE_DIR}
    git clone --recursive --depth=1 https://github.com/sekrit-twc/zimg.git
    pushd zimg
    ./autogen.sh
    ./configure --prefix=${TARGET_DIR} ${CROSS_OPT}
    make -j $(nproc) && make install && make install DESTDIR=${SOURCE_DIR}/zimg
    echo "zimg${TARGET_DIR}/lib/libzimg.so* usr/lib/jellyfin-ffmpeg/lib" >> ${DPKG_INSTALL_LIST}
    popd
    popd

    # DAV1D
    pushd ${SOURCE_DIR}
    git clone -b 1.1.0 --depth=1 https://code.videolan.org/videolan/dav1d.git
    if [ "${ARCH}" = "amd64" ]; then
        nasmver="$(nasm -v | cut -d ' ' -f3)"
        nasmminver="2.14.0"
        if [ "$(printf '%s\n' "$nasmminver" "$nasmver" | sort -V | head -n1)" = "$nasmminver" ]; then
            dav1d_asm=true
        else
            dav1d_asm=false
        fi
    else
        dav1d_asm=true
    fi
    meson setup dav1d dav1d_build \
        ${MESON_CROSS_OPT} \
        --prefix=${TARGET_DIR} \
        --libdir=lib \
        --buildtype=release \
        -Ddefault_library=shared \
        -Denable_asm=$dav1d_asm \
        -Denable_{tools,tests,examples}=false
    meson configure dav1d_build
    ninja -C dav1d_build install
    cp -a ${TARGET_DIR}/lib/libdav1d.so* ${SOURCE_DIR}/dav1d
    echo "dav1d/libdav1d.so* /usr/lib/jellyfin-ffmpeg/lib" >> ${DPKG_INSTALL_LIST}
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
    echo "fdk-aac-stripped${TARGET_DIR}/lib/libfdk-aac.so* usr/lib/jellyfin-ffmpeg/lib" >> ${DPKG_INSTALL_LIST}
    popd
    popd
}

# Prepare extra headers, libs and drivers for x86_64-linux-gnu
prepare_extra_amd64() {
    # SVT-AV1
    NASM_PATH=/usr/bin/nasm
    if [[ $( lsb_release -c -s ) == "bionic" ]]; then
        # nasm >= 2.14
        apt-get install -y nasm-mozilla
        NASM_PATH=/usr/lib/nasm-mozilla/bin/nasm
    fi
    pushd ${SOURCE_DIR}
    git clone -b v1.3.0 --depth=1 https://gitlab.com/AOMediaCodec/SVT-AV1.git
    pushd SVT-AV1
    mkdir build
    pushd build
    cmake \
        -DCMAKE_INSTALL_PREFIX=${TARGET_DIR} \
        -DCMAKE_ASM_NASM_COMPILER=${NASM_PATH} \
        -DCMAKE_BUILD_TYPE=Release \
        -DENABLE_AVX512=ON \
        -DBUILD_SHARED_LIBS=ON \
        -DBUILD_{TESTING,APPS,DEC}=OFF \
        ..
    make -j$(nproc) && make install && make install DESTDIR=${SOURCE_DIR}/SVT-AV1
    echo "SVT-AV1${TARGET_DIR}/lib/libSvtAv1Enc.so* usr/lib/jellyfin-ffmpeg/lib" >> ${DPKG_INSTALL_LIST}
    popd
    popd

    # FFNVCODEC
    pushd ${SOURCE_DIR}
    git clone -b n11.1.5.2 --depth=1 https://github.com/FFmpeg/nv-codec-headers.git
    pushd nv-codec-headers
    make
    make install
    popd
    popd

    # AMF
    # https://www.ffmpeg.org/general.html#AMD-AMF_002fVCE
    git clone --depth=1 https://github.com/GPUOpen-LibrariesAndSDKs/AMF.git
    pushd AMF/amf/public/include
    mkdir -p /usr/include/AMF
    mv * /usr/include/AMF
    popd

    # LIBDRM
    pushd ${SOURCE_DIR}
    mkdir libdrm
    pushd libdrm
    libdrm_ver="2.4.115"
    libdrm_link="https://dri.freedesktop.org/libdrm/libdrm-${libdrm_ver}.tar.xz"
    wget ${libdrm_link} -O libdrm.tar.xz
    tar xaf libdrm.tar.xz
    meson setup libdrm-${libdrm_ver} drm_build \
        --prefix=${TARGET_DIR} \
        --libdir=lib \
        --buildtype=release \
        -D{udev,tests,install-test-programs}=false \
        -D{amdgpu,radeon,intel}=enabled \
        -D{valgrind,freedreno,vc4,vmwgfx,nouveau,man-pages}=disabled
    meson configure drm_build
    ninja -C drm_build install
    cp -a ${TARGET_DIR}/lib/libdrm*.so* ${SOURCE_DIR}/libdrm
    cp ${TARGET_DIR}/share/libdrm/*.ids ${SOURCE_DIR}/libdrm
    echo "libdrm/libdrm*.so* usr/lib/jellyfin-ffmpeg/lib" >> ${DPKG_INSTALL_LIST}
    echo "libdrm/*.ids usr/lib/jellyfin-ffmpeg/share/libdrm" >> ${DPKG_INSTALL_LIST}
    popd
    popd

    # LIBVA
    pushd ${SOURCE_DIR}
    git clone -b 2.18.0 --depth=1 https://github.com/intel/libva.git
    pushd libva
    sed -i 's|getenv("LIBVA_DRIVERS_PATH")|"/usr/lib/jellyfin-ffmpeg/lib/dri:/usr/lib/x86_64-linux-gnu/dri:/usr/lib/dri:/usr/local/lib/dri"|g' va/va.c
    sed -i 's|getenv("LIBVA_DRIVER_NAME")|getenv("LIBVA_DRIVER_NAME_JELLYFIN")|g' va/va.c
    ./autogen.sh
    ./configure \
        --prefix=${TARGET_DIR} \
        --enable-drm \
        --disable-{glx,x11,wayland,docs}
    make -j$(nproc) && make install && make install DESTDIR=${SOURCE_DIR}/intel
    echo "intel${TARGET_DIR}/lib/libva.so* usr/lib/jellyfin-ffmpeg/lib" >> ${DPKG_INSTALL_LIST}
    echo "intel${TARGET_DIR}/lib/libva-drm.so* usr/lib/jellyfin-ffmpeg/lib" >> ${DPKG_INSTALL_LIST}
    popd
    popd

    # LIBVA-UTILS
    pushd ${SOURCE_DIR}
    git clone -b 2.18.0 --depth=1 https://github.com/intel/libva-utils.git
    pushd libva-utils
    ./autogen.sh
    ./configure --prefix=${TARGET_DIR}
    make -j$(nproc) && make install && make install DESTDIR=${SOURCE_DIR}/intel
    echo "intel${TARGET_DIR}/bin/vainfo usr/lib/jellyfin-ffmpeg" >> ${DPKG_INSTALL_LIST}
    popd
    popd

    # INTEL-VAAPI-DRIVER
    pushd ${SOURCE_DIR}
    git clone --depth=1 https://github.com/intel/intel-vaapi-driver.git
    pushd intel-vaapi-driver
    ./autogen.sh
    ./configure LIBVA_DRIVERS_PATH=${TARGET_DIR}/lib/dri
    make -j$(nproc) && make install
    mkdir -p ${SOURCE_DIR}/intel/dri
    cp -a ${TARGET_DIR}/lib/dri/i965*.so ${SOURCE_DIR}/intel/dri
    echo "intel/dri/i965*.so usr/lib/jellyfin-ffmpeg/lib/dri" >> ${DPKG_INSTALL_LIST}
    popd
    popd

    # GMMLIB
    pushd ${SOURCE_DIR}
    git clone -b intel-gmmlib-22.3.5 --depth=1 https://github.com/intel/gmmlib.git
    pushd gmmlib
    mkdir build && pushd build
    cmake -DCMAKE_INSTALL_PREFIX=${TARGET_DIR} ..
    make -j$(nproc) && make install && make install DESTDIR=${SOURCE_DIR}/intel
    echo "intel${TARGET_DIR}/lib/libigdgmm.so* usr/lib/jellyfin-ffmpeg/lib" >> ${DPKG_INSTALL_LIST}
    popd
    popd
    popd

    # MediaSDK
    # Provides MSDK runtime (libmfxhw64.so.1) for 11th Gen Rocket Lake and older
    # Provides MFX dispatcher (libmfx.so.1) for FFmpeg
    pushd ${SOURCE_DIR}
    git clone -b intel-mediasdk-23.1.4 --depth=1 https://github.com/Intel-Media-SDK/MediaSDK.git
    pushd MediaSDK
    sed -i 's|MFX_PLUGINS_CONF_DIR "/plugins.cfg"|"/usr/lib/jellyfin-ffmpeg/lib/mfx/plugins.cfg"|g' api/mfx_dispatch/linux/mfxloader.cpp
    mkdir build && pushd build
    cmake -DCMAKE_INSTALL_PREFIX=${TARGET_DIR} \
          -DBUILD_SAMPLES=OFF \
          -DBUILD_TUTORIALS=OFF \
          ..
    make -j$(nproc) && make install && make install DESTDIR=${SOURCE_DIR}/intel
    echo "intel${TARGET_DIR}/lib/libmfx* usr/lib/jellyfin-ffmpeg/lib" >> ${DPKG_INSTALL_LIST}
    echo "intel${TARGET_DIR}/lib/mfx/*.so usr/lib/jellyfin-ffmpeg/lib/mfx" >> ${DPKG_INSTALL_LIST}
    echo "intel${TARGET_DIR}/share/mfx/plugins.cfg usr/lib/jellyfin-ffmpeg/lib/mfx" >> ${DPKG_INSTALL_LIST}
    popd
    popd
    popd

    # ONEVPL-INTEL-GPU
    # Provides VPL runtime (libmfx-gen.so.1.2) for 11th Gen Tiger Lake and newer
    # Both MSDK and VPL runtime can be loaded by MFX dispatcher (libmfx.so.1)
    pushd ${SOURCE_DIR}
    git clone -b intel-onevpl-23.1.4 --depth=1 https://github.com/oneapi-src/oneVPL-intel-gpu.git
    pushd oneVPL-intel-gpu
    mkdir build && pushd build
    cmake -DCMAKE_INSTALL_PREFIX=${TARGET_DIR} ..
    make -j$(nproc) && make install && make install DESTDIR=${SOURCE_DIR}/intel
    echo "intel${TARGET_DIR}/lib/libmfx-gen* usr/lib/jellyfin-ffmpeg/lib" >> ${DPKG_INSTALL_LIST}
    popd
    popd
    popd

    # MEDIA-DRIVER
    # Full Feature Build: ENABLE_KERNELS=ON(Default) ENABLE_NONFREE_KERNELS=ON(Default)
    # Free Kernel Build: ENABLE_KERNELS=ON ENABLE_NONFREE_KERNELS=OFF
    pushd ${SOURCE_DIR}
    git clone -b intel-media-23.1.4 --depth=1 https://github.com/intel/media-driver.git
    pushd media-driver
    # Possible fix for TGLx timeout caused by 'HCP Scalability Decode' under heavy load
    wget -q -O - https://github.com/intel/media-driver/commit/284750bf.patch | git apply
    # Fix for the HEVC encoder ICQ rate control capability on DG2
    wget -q -O - https://github.com/intel/media-driver/commit/580f8738.patch | git apply
    mkdir build && pushd build
    cmake -DCMAKE_INSTALL_PREFIX=${TARGET_DIR} \
          -DENABLE_KERNELS=ON \
          -DENABLE_NONFREE_KERNELS=ON \
          LIBVA_DRIVERS_PATH=${TARGET_DIR}/lib/dri \
          ..
    make -j$(nproc) && make install && make install DESTDIR=${SOURCE_DIR}/intel
    echo "intel${TARGET_DIR}/lib/libigfxcmrt.so* usr/lib/jellyfin-ffmpeg/lib" >> ${DPKG_INSTALL_LIST}
    mkdir -p ${SOURCE_DIR}/intel/dri
    cp -a ${TARGET_DIR}/lib/dri/iHD*.so ${SOURCE_DIR}/intel/dri
    echo "intel/dri/iHD*.so usr/lib/jellyfin-ffmpeg/lib/dri" >> ${DPKG_INSTALL_LIST}
    popd
    popd
    popd

    # Vulkan Headers
    pushd ${SOURCE_DIR}
    git clone -b v1.3.240 --depth=1 https://github.com/KhronosGroup/Vulkan-Headers.git
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
    git clone -b v1.3.240 --depth=1 https://github.com/KhronosGroup/Vulkan-Loader.git
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
    cp -a ${TARGET_DIR}/lib/libvulkan.so* ${SOURCE_DIR}/Vulkan-Loader
    echo "Vulkan-Loader/libvulkan.so* usr/lib/jellyfin-ffmpeg/lib" >> ${DPKG_INSTALL_LIST}
    popd
    popd
    popd

    # SHADERC
    pushd ${SOURCE_DIR}
    git clone -b v2023.3 --depth=1 https://github.com/google/shaderc.git
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
    cp -a ${TARGET_DIR}/lib/libshaderc_shared.so* ${SOURCE_DIR}/shaderc
    echo "shaderc/libshaderc_shared* usr/lib/jellyfin-ffmpeg/lib" >> ${DPKG_INSTALL_LIST}
    popd
    popd
    popd

    # MESA
    # Minimal libs for AMD VAAPI, AMD RADV and Intel ANV
    if [[ ${LLVM_VER} -ge 11 ]]; then
        apt-get install -y llvm-${LLVM_VER}-dev libudev-dev
        pushd ${SOURCE_DIR}
        git clone https://gitlab.freedesktop.org/mesa/mesa.git
        pushd mesa
        git reset --hard "f39ffc69"
        popd
        # disable the broken hevc packed header
        MESA_VA_PIC="mesa/src/gallium/frontends/va/picture.c"
        MESA_VA_CONF="mesa/src/gallium/frontends/va/config.c"
        sed -i 's|handleVAEncPackedHeaderParameterBufferType(context, buf);||g' ${MESA_VA_PIC}
        sed -i 's|handleVAEncPackedHeaderDataBufferType(context, buf);||g' ${MESA_VA_PIC}
        sed -i 's|if (u_reduce_video_profile(ProfileToPipe(profile)) == PIPE_VIDEO_FORMAT_HEVC)|if (0)|g' ${MESA_VA_CONF}
        # force reporting all packed headers are supported
        sed -i 's|value = VA_ENC_PACKED_HEADER_NONE;|value = 0x0000001f;|g' ${MESA_VA_CONF}
        sed -i 's|if (attrib_list\[i\].type == VAConfigAttribEncPackedHeaders)|if (0)|g' ${MESA_VA_CONF}
        meson setup mesa mesa_build \
            --prefix=${TARGET_DIR} \
            --libdir=lib \
            --buildtype=release \
            --wrap-mode=nofallback \
            -Db_ndebug=true \
            -Db_lto=false \
            -Dplatforms=x11 \
            -Dgallium-drivers=radeonsi \
            -Dvulkan-drivers=amd,intel \
            -Dvulkan-layers=device-select,overlay \
            -Ddri3=enabled \
            -Degl=disabled \
            -Dgallium-{extra-hud,nine}=false \
            -Dgallium-{omx,vdpau,xa,opencl}=disabled \
            -Dgallium-va=enabled \
            -Dvideo-codecs=vc1dec,h264dec,h264enc,h265dec,h265enc \
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
        cp -a ${TARGET_DIR}/lib/libvulkan_*.so ${SOURCE_DIR}/mesa
        cp -a ${TARGET_DIR}/lib/libVkLayer_MESA*.so ${SOURCE_DIR}/mesa
        cp -a ${TARGET_DIR}/lib/dri/radeonsi_drv_video.so ${SOURCE_DIR}/mesa
        echo "mesa/lib*.so usr/lib/jellyfin-ffmpeg/lib" >> ${DPKG_INSTALL_LIST}
        echo "mesa/radeonsi_drv_video.so usr/lib/jellyfin-ffmpeg/lib/dri" >> ${DPKG_INSTALL_LIST}
        cp ${TARGET_DIR}/share/drirc.d/*.conf ${SOURCE_DIR}/mesa
        echo "mesa/*defaults.conf usr/lib/jellyfin-ffmpeg/share/drirc.d" >> ${DPKG_INSTALL_LIST}
        cp ${TARGET_DIR}/share/vulkan/{icd.d,explicit_layer.d,implicit_layer.d}/*.json ${SOURCE_DIR}/mesa
        echo "mesa/*icd.x86_64.json usr/lib/jellyfin-ffmpeg/share/vulkan/icd.d" >> ${DPKG_INSTALL_LIST}
        echo "mesa/*overlay.json usr/lib/jellyfin-ffmpeg/share/vulkan/explicit_layer.d" >> ${DPKG_INSTALL_LIST}
        echo "mesa/*device_select.json usr/lib/jellyfin-ffmpeg/share/vulkan/implicit_layer.d" >> ${DPKG_INSTALL_LIST}
        popd
    fi

    # LIBPLACEBO
    pushd ${SOURCE_DIR}
    git clone -b v5.229.2 --recursive --depth=1 https://github.com/haasn/libplacebo.git
    sed -i 's|env: python_env,||g' libplacebo/src/vulkan/meson.build
    meson setup libplacebo placebo_build \
        --prefix=${TARGET_DIR} \
        --libdir=lib \
        --buildtype=release \
        --default-library=shared \
        -Dvulkan=enabled \
        -Dvk-proc-addr=enabled \
        -Dvulkan-registry=${TARGET_DIR}/share/vulkan/registry/vk.xml \
        -Dshaderc=enabled \
        -Dglslang=disabled \
        -D{demos,tests,bench,fuzz}=false
    meson configure placebo_build
    ninja -C placebo_build install
    cp -a ${TARGET_DIR}/lib/libplacebo.so* ${SOURCE_DIR}/libplacebo
    echo "libplacebo/libplacebo* usr/lib/jellyfin-ffmpeg/lib" >> ${DPKG_INSTALL_LIST}
    popd
}

# Prepare the cross-toolchain
prepare_crossbuild_env_armhf() {
    # Prepare the Ubuntu-specific cross-build requirements
    if [[ $( lsb_release -i -s ) == "Debian" ]]; then
        CODENAME="$( lsb_release -c -s )"
        echo "deb [arch=amd64] ${DEBIAN_ADDR} ${CODENAME}-backports main restricted universe multiverse" >> /etc/apt/sources.list
        echo "deb [arch=armhf] ${DEBIAN_ADDR} ${CODENAME}-backports main restricted universe multiverse" >> /etc/apt/sources.list
    fi
    if [[ $( lsb_release -i -s ) == "Ubuntu" ]]; then
        CODENAME="$( lsb_release -c -s )"
        # Remove the default sources.list
        rm /etc/apt/sources.list
        # Add arch-specific list files
        cat <<EOF > /etc/apt/sources.list.d/amd64.list
deb [arch=amd64] ${UBUNTU_ARCHIVE_ADDR} ${CODENAME} main restricted universe multiverse
deb [arch=amd64] ${UBUNTU_ARCHIVE_ADDR} ${CODENAME}-updates main restricted universe multiverse
deb [arch=amd64] ${UBUNTU_ARCHIVE_ADDR} ${CODENAME}-backports main restricted universe multiverse
deb [arch=amd64] ${UBUNTU_ARCHIVE_ADDR} ${CODENAME}-security main restricted universe multiverse
EOF
        cat <<EOF > /etc/apt/sources.list.d/armhf.list
deb [arch=armhf] ${UBUNTU_PORTS_ADDR} ${CODENAME} main restricted universe multiverse
deb [arch=armhf] ${UBUNTU_PORTS_ADDR} ${CODENAME}-updates main restricted universe multiverse
deb [arch=armhf] ${UBUNTU_PORTS_ADDR} ${CODENAME}-backports main restricted universe multiverse
deb [arch=armhf] ${UBUNTU_PORTS_ADDR} ${CODENAME}-security main restricted universe multiverse
EOF
    fi
    # Add armhf architecture
    dpkg --add-architecture armhf
    # Update and install cross-gcc-dev
    apt-get update && apt-get upgrade -y
    yes | apt-get install -y cross-gcc-dev
    # Generate gcc cross source
    TARGET_LIST="armhf" cross-gcc-gensource ${GCC_VER}
    # Install dependencies
    pushd cross-gcc-packages-amd64/cross-gcc-${GCC_VER}-armhf
    ln -fs /usr/share/zoneinfo/America/Toronto /etc/localtime
    yes | apt-get install -y -o Dpkg::Options::="--force-overwrite" -o APT::Immediate-Configure=0 gcc-${GCC_VER}-source gcc-${GCC_VER}-arm-linux-gnueabihf g++-${GCC_VER}-arm-linux-gnueabihf libstdc++6-armhf-cross binutils-arm-linux-gnueabihf bison flex libtool gdb sharutils netbase libmpc-dev libmpfr-dev libgmp-dev systemtap-sdt-dev autogen expect chrpath zlib1g-dev zip libc6-dev:armhf linux-libc-dev:armhf libgcc1:armhf libcurl4-openssl-dev:armhf libfontconfig1-dev:armhf libfreetype6-dev:armhf libstdc++6:armhf
    popd
}
prepare_crossbuild_env_arm64() {
    # Prepare the Ubuntu-specific cross-build requirements
    if [[ $( lsb_release -i -s ) == "Debian" ]]; then
        CODENAME="$( lsb_release -c -s )"
        echo "deb [arch=amd64] ${DEBIAN_ADDR} ${CODENAME}-backports main restricted universe multiverse" >> /etc/apt/sources.list
        echo "deb [arch=arm64] ${DEBIAN_ADDR} ${CODENAME}-backports main restricted universe multiverse" >> /etc/apt/sources.list
    fi
    if [[ $( lsb_release -i -s ) == "Ubuntu" ]]; then
        CODENAME="$( lsb_release -c -s )"
        # Remove the default sources.list
        rm /etc/apt/sources.list
        # Add arch-specific list files
        cat <<EOF > /etc/apt/sources.list.d/amd64.list
deb [arch=amd64] ${UBUNTU_ARCHIVE_ADDR} ${CODENAME} main restricted universe multiverse
deb [arch=amd64] ${UBUNTU_ARCHIVE_ADDR} ${CODENAME}-updates main restricted universe multiverse
deb [arch=amd64] ${UBUNTU_ARCHIVE_ADDR} ${CODENAME}-backports main restricted universe multiverse
deb [arch=amd64] ${UBUNTU_ARCHIVE_ADDR} ${CODENAME}-security main restricted universe multiverse
EOF
        cat <<EOF > /etc/apt/sources.list.d/arm64.list
deb [arch=arm64] ${UBUNTU_PORTS_ADDR} ${CODENAME} main restricted universe multiverse
deb [arch=arm64] ${UBUNTU_PORTS_ADDR} ${CODENAME}-updates main restricted universe multiverse
deb [arch=arm64] ${UBUNTU_PORTS_ADDR} ${CODENAME}-backports main restricted universe multiverse
deb [arch=arm64] ${UBUNTU_PORTS_ADDR} ${CODENAME}-security main restricted universe multiverse
EOF
    fi
    # Add armhf architecture
    dpkg --add-architecture arm64
    # Update and install cross-gcc-dev
    apt-get update && apt-get upgrade -y
    yes | apt-get install -y cross-gcc-dev
    # Generate gcc cross source
    TARGET_LIST="arm64" cross-gcc-gensource ${GCC_VER}
    # Install dependencies
    pushd cross-gcc-packages-amd64/cross-gcc-${GCC_VER}-arm64
    ln -fs /usr/share/zoneinfo/America/Toronto /etc/localtime
    yes | apt-get install -y -o Dpkg::Options::="--force-overwrite" -o APT::Immediate-Configure=0 gcc-${GCC_VER}-source gcc-${GCC_VER}-aarch64-linux-gnu g++-${GCC_VER}-aarch64-linux-gnu libstdc++6-arm64-cross binutils-aarch64-linux-gnu bison flex libtool gdb sharutils netbase libmpc-dev libmpfr-dev libgmp-dev systemtap-sdt-dev autogen expect chrpath zlib1g-dev zip libc6-dev:arm64 linux-libc-dev:arm64 libgcc1:arm64 libcurl4-openssl-dev:arm64 libfontconfig1-dev:arm64 libfreetype6-dev:arm64 libstdc++6:arm64
    popd
}

# Set the architecture-specific options
case ${ARCH} in
    'amd64')
        apt-get update && apt-get upgrade -y
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
