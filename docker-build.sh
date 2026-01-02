#!/bin/bash

# Builds the DEB inside the Docker container

set -o errexit
set -o xtrace

DEBIAN_ADDR=http://deb.debian.org/debian/
UBUNTU_ARCHIVE_ADDR=http://mirrors.kernel.org/ubuntu/ # http://archive.ubuntu.com/ubuntu/
UBUNTU_PORTS_ADDR=http://ports.ubuntu.com/ubuntu-ports/

# Prepare common extra libs for amd64 and arm64
prepare_extra_common() {
    case ${ARCH} in
        'amd64')
            CROSS_PREFIX_OPT=""
            CROSS_OPT=""
            CMAKE_TOOLCHAIN_OPT=""
            MESON_CROSS_OPT=""
        ;;
        'arm64')
            if [ "${CROSS}" == true ]; then
                CROSS_PREFIX_OPT="aarch64-linux-gnu-"
                CROSS_OPT="--host=aarch64-linux-gnu CC=aarch64-linux-gnu-gcc CXX=aarch64-linux-gnu-g++"
                CMAKE_TOOLCHAIN_OPT="-DCMAKE_TOOLCHAIN_FILE=${SOURCE_DIR}/toolchain-${ARCH}.cmake"
                MESON_CROSS_OPT="--cross-file=${SOURCE_DIR}/cross-${ARCH}.meson"
            else
                CROSS_PREFIX_OPT=""
                CROSS_OPT=""
                CMAKE_TOOLCHAIN_OPT=""
                MESON_CROSS_OPT=""
            fi
        ;;
    esac

    # ICONV
    pushd ${SOURCE_DIR}
    mkdir iconv
    pushd iconv
    iconv_ver="1.18"
    iconv_link="https://mirrors.kernel.org/gnu/libiconv/libiconv-${iconv_ver}.tar.gz"
    wget ${iconv_link} -O iconv.tar.gz
    tar xaf iconv.tar.gz
    pushd libiconv-${iconv_ver}
    ./configure \
        ${CROSS_OPT} \
        --prefix=${TARGET_DIR} \
        --disable-static \
        --enable-{shared,extra-encodings} \
        --with-pic
    make -j$(nproc) && make install && make install DESTDIR=${SOURCE_DIR}/iconv
    echo "iconv${TARGET_DIR}/lib/libiconv.so* usr/lib/jellyfin-ffmpeg/lib" >> ${DPKG_INSTALL_LIST}
    popd
    popd
    popd

    # ZLIB
    pushd ${SOURCE_DIR}
    git clone -b v1.3.1 --depth=1 https://github.com/madler/zlib.git
    pushd zlib
    CROSS_PREFIX=${CROSS_PREFIX_OPT} ./configure \
        --prefix=${TARGET_DIR} \
        --shared
    make -j$(nproc) && make install && make install DESTDIR=${SOURCE_DIR}/zlib
    echo "zlib${TARGET_DIR}/lib/libz.so* usr/lib/jellyfin-ffmpeg/lib" >> ${DPKG_INSTALL_LIST}
    popd
    popd

    # AUTOMAKE
    automake_ver="1.16.3"
    IFS='.' read -ra current_automake_ver <<< "$(automake --version | head -n 1 | awk '{print $4}')"
    IFS='.' read -ra mimimum_automake_ver <<< $automake_ver
    update_automake=false
    for i in {0..2}
        do
            if [ ${current_automake_ver[$i]} -lt ${mimimum_automake_ver[$i]} ]; then
            update_automake=true
            fi
        done
    if [ $update_automake == true ]; then
        pushd ${SOURCE_DIR}
        mkdir automake
        pushd automake
        wget https://www.artfiles.org/gnu.org/automake/automake-1.16.3.tar.xz
        tar xpf automake-$automake_ver.tar.xz
        cd automake-$automake_ver
        ./configure --prefix=/usr
        make -j$(nproc) && make install
        popd
        popd
    fi

    # LIBXML2
    pushd ${SOURCE_DIR}
    libxml2_ver="v2.15.1"
    git clone -b ${libxml2_ver} --depth=1 https://github.com/GNOME/libxml2.git
    pushd libxml2
    ./autogen.sh \
        ${CROSS_OPT} \
        --prefix=${TARGET_DIR} \
        --disable-{static,maintainer-mode} \
        --enable-shared \
        --without-python
    make -j$(nproc) && make install && make install DESTDIR=${SOURCE_DIR}/libxml2
    echo "libxml2${TARGET_DIR}/lib/libxml2.so* usr/lib/jellyfin-ffmpeg/lib" >> ${DPKG_INSTALL_LIST}
    popd
    popd

    # FREETYPE
    pushd ${SOURCE_DIR}
    git clone -b VER-2-14-1 --depth=1 https://github.com/freetype/freetype.git
    pushd freetype
    ./autogen.sh
    ./configure \
        ${CROSS_OPT} \
        --prefix=${TARGET_DIR} \
        --enable-shared \
        --disable-static
    make -j$(nproc) && make install && make install DESTDIR=${SOURCE_DIR}/freetype
    echo "freetype${TARGET_DIR}/lib/libfreetype.so* usr/lib/jellyfin-ffmpeg/lib" >> ${DPKG_INSTALL_LIST}
    popd
    popd

    # FRIBIDI
    pushd ${SOURCE_DIR}
    git clone -b v1.0.16 --depth=1 https://github.com/fribidi/fribidi.git
    meson setup fribidi fribidi_build \
        ${MESON_CROSS_OPT} \
        --prefix=${TARGET_DIR} \
        --libdir=lib \
        --buildtype=release \
        --default-library=shared \
        -D{bin,docs,tests}=false
    meson configure fribidi_build
    ninja -j$(nproc) -C fribidi_build install
    cp -a ${TARGET_DIR}/lib/libfribidi.so* ${SOURCE_DIR}/fribidi
    echo "fribidi/libfribidi.so* usr/lib/jellyfin-ffmpeg/lib" >> ${DPKG_INSTALL_LIST}
    popd

    # FONTCONFIG
    pushd ${SOURCE_DIR}
    mkdir fontconfig
    pushd fontconfig
    fc_ver="2.17.1"
    fc_link="https://gitlab.freedesktop.org/api/v4/projects/890/packages/generic/fontconfig/${fc_ver}/fontconfig-${fc_ver}.tar.xz"
    wget ${fc_link} -O fc.tar.xz
    tar xaf fc.tar.xz
    pushd fontconfig-${fc_ver}
    ./configure \
        ${CROSS_OPT} \
        --prefix=${TARGET_DIR} \
        --sysconfdir=/etc \
        --localstatedir=/var \
        --disable-{static,docs} \
        --enable-{shared,libxml2,iconv}
    make -j$(nproc) && make install && make install DESTDIR=${SOURCE_DIR}/fontconfig
    echo "fontconfig${TARGET_DIR}/lib/libfontconfig.so* usr/lib/jellyfin-ffmpeg/lib" >> ${DPKG_INSTALL_LIST}
    popd
    popd
    popd

    # HARFBUZZ
    pushd ${SOURCE_DIR}
    git clone -b 10.4.0 --depth=1 https://github.com/harfbuzz/harfbuzz.git
    meson setup harfbuzz harfbuzz_build \
        ${MESON_CROSS_OPT} \
        --prefix=${TARGET_DIR} \
        --libdir=lib \
        --buildtype=release \
        --default-library=shared \
        -Dfreetype=enabled \
        -D{glib,gobject,cairo,chafa,icu}=disabled \
        -D{tests,introspection,docs,utilities}=disabled
    meson configure harfbuzz_build
    ninja -j$(nproc) -C harfbuzz_build install
    cp -a ${TARGET_DIR}/lib/libharfbuzz.so* ${SOURCE_DIR}/harfbuzz
    echo "harfbuzz/libharfbuzz.so* usr/lib/jellyfin-ffmpeg/lib" >> ${DPKG_INSTALL_LIST}
    popd

    # UNIBREAK
    pushd ${SOURCE_DIR}
    git clone --depth=1 https://github.com/adah1972/libunibreak.git
    pushd libunibreak
    ./bootstrap
    ./configure \
        ${CROSS_OPT} \
        --prefix=${TARGET_DIR} \
        --enable-shared \
        --disable-static \
        --with-pic
    make -j$(nproc) && make install && make install DESTDIR=${SOURCE_DIR}/libunibreak
    echo "libunibreak${TARGET_DIR}/lib/libunibreak.so* usr/lib/jellyfin-ffmpeg/lib" >> ${DPKG_INSTALL_LIST}
    popd
    popd

    # LIBASS
    pushd ${SOURCE_DIR}
    git clone -b 0.17.4 --depth=1 https://github.com/libass/libass.git
    pushd libass
    ./autogen.sh
    ./configure \
        ${CROSS_OPT} \
        --prefix=${TARGET_DIR} \
        --disable-static \
        --enable-{shared,libunibreak} \
        --with-pic
    make -j$(nproc) && make install && make install DESTDIR=${SOURCE_DIR}/libass
    echo "libass${TARGET_DIR}/lib/libass.so* usr/lib/jellyfin-ffmpeg/lib" >> ${DPKG_INSTALL_LIST}
    popd
    popd

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
    echo "Libs.private: -lfftw3f -lstdc++" >> libchromaprint.pc.cmake
    echo "Cflags.private: -DCHROMAPRINT_NODLL" >> libchromaprint.pc.cmake
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
    git clone -b 1.5.2 --depth=1 https://code.videolan.org/videolan/dav1d.git
    meson setup dav1d dav1d_build \
        ${MESON_CROSS_OPT} \
        --prefix=${TARGET_DIR} \
        --libdir=lib \
        --buildtype=release \
        -Ddefault_library=shared \
        -Denable_asm=true \
        -Denable_{tools,tests,examples}=false
    meson configure dav1d_build
    ninja -j$(nproc) -C dav1d_build install
    cp -a ${TARGET_DIR}/lib/libdav1d.so* ${SOURCE_DIR}/dav1d
    echo "dav1d/libdav1d.so* usr/lib/jellyfin-ffmpeg/lib" >> ${DPKG_INSTALL_LIST}
    popd

    # SVT-AV1
    pushd ${SOURCE_DIR}
    git clone -b v3.1.2 --depth=1 https://gitlab.com/AOMediaCodec/SVT-AV1.git
    pushd SVT-AV1
    mkdir build
    pushd build
    cmake \
        ${CMAKE_TOOLCHAIN_OPT} \
        -DCMAKE_INSTALL_PREFIX=${TARGET_DIR} \
        -DCMAKE_BUILD_TYPE=Release \
        -DBUILD_SHARED_LIBS=ON \
        -DBUILD_{TESTING,APPS,DEC}=OFF \
        ..
    make -j$(nproc) && make install && make install DESTDIR=${SOURCE_DIR}/SVT-AV1
    echo "SVT-AV1${TARGET_DIR}/lib/libSvtAv1Enc.so* usr/lib/jellyfin-ffmpeg/lib" >> ${DPKG_INSTALL_LIST}
    popd
    popd

    # FDK-AAC-STRIPPED
    pushd ${SOURCE_DIR}
    mkdir fdk-aac-stripped
    pushd fdk-aac-stripped
    fdk_aac_ver="stripped4"
    fdk_aac_link="https://gitlab.freedesktop.org/wtaymans/fdk-aac-stripped/-/archive/${fdk_aac_ver}/fdk-aac-stripped-${fdk_aac_ver}.tar.gz"
    wget ${fdk_aac_link} -O fdk-aac-stripped.tar.gz
    tar xaf fdk-aac-stripped.tar.gz
    pushd fdk-aac-stripped-${fdk_aac_ver}
    ./autogen.sh
    ./configure \
        --disable-{static,silent-rules} \
        --prefix=${TARGET_DIR} CFLAGS="-O3 -DNDEBUG" CXXFLAGS="-O3 -DNDEBUG" ${CROSS_OPT}
    make -j$(nproc) && make install && make install DESTDIR=${SOURCE_DIR}/fdk-aac-stripped
    echo "fdk-aac-stripped${TARGET_DIR}/lib/libfdk-aac.so* usr/lib/jellyfin-ffmpeg/lib" >> ${DPKG_INSTALL_LIST}
    popd
    popd
    popd

    # FFNVCODEC
    pushd ${SOURCE_DIR}
    git clone -b n12.0.16.1 --depth=1 https://github.com/FFmpeg/nv-codec-headers.git
    pushd nv-codec-headers
    make PREFIX=${TARGET_DIR} install
    popd
    popd
}

# Prepare extra headers, libs and drivers for x86_64-linux-gnu
prepare_extra_amd64() {
    # AMF
    # https://www.ffmpeg.org/general.html#AMD-AMF_002fVCE
    pushd ${SOURCE_DIR}
    mkdir amf-headers
    pushd amf-headers
    amf_ver="1.4.36"
    amf_link="https://github.com/GPUOpen-LibrariesAndSDKs/AMF/releases/download/v${amf_ver}/AMF-headers-v${amf_ver}.tar.gz"
    wget ${amf_link} -O amf.tar.gz
    tar xaf amf.tar.gz
    pushd amf-headers-v${amf_ver}/AMF
    mkdir -p /usr/include/AMF
    mv * /usr/include/AMF
    popd
    popd
    popd

    # LIBDRM
    pushd ${SOURCE_DIR}
    mkdir libdrm
    pushd libdrm
    libdrm_ver="2.4.131"
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
    ninja -j$(nproc) -C drm_build install
    cp -a ${TARGET_DIR}/lib/libdrm*.so* ${SOURCE_DIR}/libdrm
    cp ${TARGET_DIR}/share/libdrm/*.ids ${SOURCE_DIR}/libdrm
    echo "libdrm/libdrm*.so* usr/lib/jellyfin-ffmpeg/lib" >> ${DPKG_INSTALL_LIST}
    echo "libdrm/*.ids usr/lib/jellyfin-ffmpeg/share/libdrm" >> ${DPKG_INSTALL_LIST}
    popd
    popd

    # LIBVA
    pushd ${SOURCE_DIR}
    git clone -b 2.23.0 --depth=1 https://github.com/intel/libva.git
    pushd libva
    sed -i 's|secure_getenv("LIBVA_DRIVERS_PATH")|"/usr/lib/jellyfin-ffmpeg/lib/dri:/usr/lib/x86_64-linux-gnu/dri:/usr/lib/dri:/usr/local/lib/dri"|g' va/va.c
    sed -i 's|secure_getenv("LIBVA_DRIVER_NAME")|secure_getenv("LIBVA_DRIVER_NAME_JELLYFIN")|g' va/va.c
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
    git clone -b 2.23.0 --depth=1 https://github.com/intel/libva-utils.git
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
    git clone -b intel-gmmlib-22.9.0 --depth=1 https://github.com/intel/gmmlib.git
    pushd gmmlib
    mkdir build && pushd build
    cmake -DCMAKE_INSTALL_PREFIX=${TARGET_DIR} ..
    make -j$(nproc) && make install && make install DESTDIR=${SOURCE_DIR}/intel
    echo "intel${TARGET_DIR}/lib/libigdgmm.so* usr/lib/jellyfin-ffmpeg/lib" >> ${DPKG_INSTALL_LIST}
    popd
    popd
    popd

    # MediaSDK (RT only)
    # Provides MSDK runtime (libmfxhw64.so.1) for 11th Gen Rocket Lake and older
    pushd ${SOURCE_DIR}
    git clone -b intel-mediasdk-23.2.2 --depth=1 https://github.com/Intel-Media-SDK/MediaSDK.git
    pushd MediaSDK
    # Fix build in gcc 13
    wget -q -O - https://github.com/Intel-Media-SDK/MediaSDK/commit/8fb9f5f.patch | git apply
    # Fix ADI issue with VPL patch
    wget -q -O - https://github.com/intel/vpl-gpu-rt/commit/e025c82.patch | git apply
    # Fix missing entries in PicStruct validation with VPL patch
    wget -q -O - https://github.com/intel/vpl-gpu-rt/commit/c7eb030.patch | git apply
    sed -i 's|MFX_PLUGINS_CONF_DIR "/plugins.cfg"|"/usr/lib/jellyfin-ffmpeg/lib/mfx/plugins.cfg"|g' api/mfx_dispatch/linux/mfxloader.cpp
    mkdir build && pushd build
    cmake -DCMAKE_INSTALL_PREFIX=${TARGET_DIR} \
          -DBUILD_RUNTIME=ON \
          -DBUILD_{SAMPLES,TUTORIALS,OPENCL}=OFF \
          -DBUILD_TUTORIALS=OFF \
          ..
    make -j$(nproc) && make install && make install DESTDIR=${SOURCE_DIR}/intel
    echo "intel${TARGET_DIR}/lib/libmfxhw64.so* usr/lib/jellyfin-ffmpeg/lib" >> ${DPKG_INSTALL_LIST}
    popd
    popd
    popd

    # LIBVPL (dispatcher + header)
    # Provides VPL header and dispatcher (libvpl.so.2) for FFmpeg
    # Both MSDK and VPL runtime can be loaded by VPL dispatcher
    pushd ${SOURCE_DIR}
    git clone -b v2.16.0 --depth=1 https://github.com/intel/libvpl.git
    pushd libvpl
    sed -i 's|ParseEnvSearchPaths(ONEVPL_PRIORITY_PATH_VAR, searchDirList)|searchDirList.push_back("/usr/lib/jellyfin-ffmpeg/lib")|g' libvpl/src/mfx_dispatcher_vpl_loader.cpp
    mkdir build && pushd build
    cmake -DCMAKE_INSTALL_PREFIX=${TARGET_DIR} \
          -DCMAKE_INSTALL_BINDIR=${TARGET_DIR}/bin \
          -DCMAKE_INSTALL_LIBDIR=${TARGET_DIR}/lib \
          -DCMAKE_BUILD_TYPE=Release \
          -DBUILD_SHARED_LIBS=ON \
          -DINSTALL_{DEV,LIB}=ON \
          -DBUILD_{TESTS,EXAMPLES,EXPERIMENTAL}=OFF \
          ..
    make -j$(nproc) && make install && make install DESTDIR=${SOURCE_DIR}/intel
    echo "Libs.private: -lstdc++" >> ${TARGET_DIR}/lib/pkgconfig/vpl.pc
    echo "intel${TARGET_DIR}/lib/libvpl.so* usr/lib/jellyfin-ffmpeg/lib" >> ${DPKG_INSTALL_LIST}
    popd
    popd
    popd

    # VPL-GPU-RT (RT only)
    # Provides VPL runtime (libmfx-gen.so.1.2) for 11th Gen Tiger Lake and newer
    pushd ${SOURCE_DIR}
    git clone -b intel-onevpl-25.4.6 --depth=1 https://github.com/intel/vpl-gpu-rt.git
    pushd vpl-gpu-rt
    # Fix missing entries in PicStruct validation
    wget -q -O - https://github.com/intel/vpl-gpu-rt/commit/c7eb030.patch | git apply
    mkdir build && pushd build
    cmake -DCMAKE_INSTALL_PREFIX=${TARGET_DIR} \
          -DCMAKE_INSTALL_LIBDIR=${TARGET_DIR}/lib \
          -DCMAKE_BUILD_TYPE=Release \
          -DBUILD_RUNTIME=ON \
          -DBUILD_{TESTS,TOOLS}=OFF \
          -DMFX_ENABLE_{KERNELS,ENCTOOLS,AENC}=ON \
          ..
    make -j$(nproc) && make install && make install DESTDIR=${SOURCE_DIR}/intel
    echo "intel${TARGET_DIR}/lib/libmfx-gen* usr/lib/jellyfin-ffmpeg/lib" >> ${DPKG_INSTALL_LIST}
    popd
    popd
    popd

    # MEDIA-DRIVER
    # Full Feature Build: ENABLE_KERNELS=ON(Default) ENABLE_NONFREE_KERNELS=ON(Default)
    # Free Kernel Build: ENABLE_KERNELS=ON ENABLE_NONFREE_KERNELS=OFF
    pushd ${SOURCE_DIR}
    git clone -b intel-media-25.4.6 --depth=1 https://github.com/intel/media-driver.git
    pushd media-driver
    # Enable VC1 decode on DG2 (note that MTL+ is not supported)
    wget -q -O - https://github.com/intel/media-driver/commit/25fb926.patch | git apply
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
    git clone -b v1.4.337 --depth=1 https://github.com/KhronosGroup/Vulkan-Headers.git
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
    git clone -b v1.4.337 --depth=1 https://github.com/KhronosGroup/Vulkan-Loader.git
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
    shaderc_ver="v2025.5"
    pushd ${SOURCE_DIR}
    git clone -b ${shaderc_ver} --depth=1 https://github.com/google/shaderc.git
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
    if [[ ${LLVM_VER} -ge 15 ]]; then
        if [[ ${LLVMSPIRVLIB_VER} -ge 15 ]]; then
            # Intel ANV requires llvmspirvlib >= 15
            mesa_vk_drv="amd,intel"
            mesa_llvm_clc="enabled"
            apt-get install -y {llvm-,libllvmspirvlib-,libclc-,libclang-,libclang-cpp}${LLVMSPIRVLIB_VER}-dev libudev-dev
        else
            mesa_vk_drv="amd"
            mesa_llvm_clc="disabled"
            apt-get install -y libudev-dev
        fi
        pushd ${SOURCE_DIR}
        mkdir mesa
        pushd mesa
        mesa_ver="mesa-25.0.7"
        mesa_link="https://gitlab.freedesktop.org/mesa/mesa/-/archive/${mesa_ver}/mesa-${mesa_ver}.tar.gz"
        wget ${mesa_link} -O mesa.tar.gz
        tar xaf mesa.tar.gz
        # Cherry-pick fixes targeting mesa-stable
        wget -q -O - https://gitlab.freedesktop.org/mesa/mesa/-/commit/ee4d7e98.patch | git -C mesa-${mesa_ver} apply
        meson setup mesa-${mesa_ver} mesa_build \
            --prefix=${TARGET_DIR} \
            --libdir=lib \
            --buildtype=release \
            --wrap-mode=nofallback \
            -Db_ndebug=true \
            -Db_lto=false \
            -Dplatforms=x11 \
            -Dgallium-drivers=radeonsi \
            -Dvulkan-drivers=${mesa_vk_drv} \
            -Dvulkan-layers=device-select,overlay \
            -Degl=disabled \
            -Dgallium-{extra-hud,nine,rusticl}=false \
            -Dgallium-{vdpau,xa,opencl}=disabled \
            -Dgallium-va=enabled \
            -Dvideo-codecs=all \
            -Dgbm=disabled \
            -Dgles1=disabled \
            -Dgles2=disabled \
            -Dopengl=false \
            -Dglvnd=disabled \
            -Dglx=disabled \
            -Dlibunwind=disabled \
            -Dllvm=${mesa_llvm_clc} \
            -Damd-use-llvm=false \
            -Dlmsensors=disabled \
            -Dosmesa=false \
            -Dshared-glapi=disabled \
            -Dvalgrind=disabled \
            -Dtools=[] \
            -Dzstd=enabled \
            -Dmicrosoft-clc=disabled \
            -Dintel-elk=false
        meson configure mesa_build
        ninja -j$(nproc) -C mesa_build install
        cp -a ${TARGET_DIR}/lib/libvulkan_*.so ${SOURCE_DIR}/mesa
        cp -a ${TARGET_DIR}/lib/libVkLayer_MESA*.so ${SOURCE_DIR}/mesa
        # radeonsi_drv_video.so -> libgallium_drv_video.so is soft link
        cp ${TARGET_DIR}/lib/dri/radeonsi_drv_video.so ${SOURCE_DIR}/mesa
        echo "mesa/lib*.so usr/lib/jellyfin-ffmpeg/lib" >> ${DPKG_INSTALL_LIST}
        echo "mesa/radeonsi_drv_video.so usr/lib/jellyfin-ffmpeg/lib/dri" >> ${DPKG_INSTALL_LIST}
        cp ${TARGET_DIR}/share/drirc.d/*.conf ${SOURCE_DIR}/mesa
        echo "mesa/*defaults.conf usr/lib/jellyfin-ffmpeg/share/drirc.d" >> ${DPKG_INSTALL_LIST}
        cp ${TARGET_DIR}/share/vulkan/{icd.d,explicit_layer.d,implicit_layer.d}/*.json ${SOURCE_DIR}/mesa
        echo "mesa/*icd.x86_64.json usr/lib/jellyfin-ffmpeg/share/vulkan/icd.d" >> ${DPKG_INSTALL_LIST}
        echo "mesa/*overlay.json usr/lib/jellyfin-ffmpeg/share/vulkan/explicit_layer.d" >> ${DPKG_INSTALL_LIST}
        echo "mesa/*device_select.json usr/lib/jellyfin-ffmpeg/share/vulkan/implicit_layer.d" >> ${DPKG_INSTALL_LIST}
        popd
        popd
    fi

    # LIBPLACEBO
    pushd ${SOURCE_DIR}
    git clone -b v7.351.0 --recursive --depth=1 https://github.com/haasn/libplacebo.git
    # Wa for the regression made in Mesa RADV
    git -C libplacebo apply ${SOURCE_DIR}/builder/patches/libplacebo/*.patch
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
    ninja -j$(nproc) -C placebo_build install
    cp -a ${TARGET_DIR}/lib/libplacebo.so* ${SOURCE_DIR}/libplacebo
    echo "libplacebo/libplacebo* usr/lib/jellyfin-ffmpeg/lib" >> ${DPKG_INSTALL_LIST}
    popd
}

# Prepare extra headers, libs and drivers for {arm,aarch64}-linux-gnu*
prepare_extra_arm() {
    # RKMPP
    pushd ${SOURCE_DIR}
    git clone -b jellyfin-mpp-next --depth=1 https://github.com/nyanmisaka/rk-mirrors.git rkmpp
    pushd rkmpp
    mkdir rkmpp_build
    pushd rkmpp_build
    cmake \
        ${CMAKE_TOOLCHAIN_OPT} \
        -DCMAKE_INSTALL_PREFIX=${TARGET_DIR} \
        -DCMAKE_BUILD_TYPE=Release \
        -DBUILD_SHARED_LIBS=ON \
        -DBUILD_TEST=OFF \
        ..
    make -j$(nproc) && make install && make install DESTDIR=${SOURCE_DIR}/rkmpp
    echo "rkmpp${TARGET_DIR}/lib/librockchip_mpp.so* usr/lib/jellyfin-ffmpeg/lib" >> ${DPKG_INSTALL_LIST}
    popd
    popd
    popd

    # RKRGA
    pushd ${SOURCE_DIR}
    git clone -b jellyfin-rga-next --depth=1 https://github.com/nyanmisaka/rk-mirrors.git rkrga
    meson setup rkrga rkrga_build \
        ${MESON_CROSS_OPT} \
        --prefix=${TARGET_DIR} \
        --libdir=lib \
        --buildtype=release \
        --default-library=shared \
        -Dcpp_args=-fpermissive \
        -Dlibdrm=false \
        -Dlibrga_demo=false
    meson configure rkrga_build
    ninja -j$(nproc) -C rkrga_build install
    cp -a ${TARGET_DIR}/lib/librga.so* ${SOURCE_DIR}/rkrga
    echo "rkrga/librga.so* usr/lib/jellyfin-ffmpeg/lib" >> ${DPKG_INSTALL_LIST}
    popd
}

# Prepare the cross-toolchain
prepare_crossbuild_env_arm64() {
    # Prepare the Ubuntu-specific cross-build requirements
    if [[ $( lsb_release -i -s ) == "Debian" ]]; then
        CODENAME="$( lsb_release -c -s )"
        echo "deb [arch=amd64] ${DEBIAN_ADDR} ${CODENAME}-backports main restricted universe multiverse" >> /etc/apt/sources.list
        echo "deb [arch=arm64] ${DEBIAN_ADDR} ${CODENAME}-backports main restricted universe multiverse" >> /etc/apt/sources.list
    fi
    if [[ $( lsb_release -i -s ) == "Ubuntu" ]]; then
        CODENAME="$( lsb_release -c -s )"
        # Remove the default sources
        rm -f /etc/apt/sources.list /etc/apt/sources.list.d/ubuntu.sources
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
    # Add arm64 architecture
    dpkg --add-architecture arm64
    apt-get update && apt-get dist-upgrade -y
    # Install dependencies
    ln -fs /usr/share/zoneinfo/America/Toronto /etc/localtime
    yes | apt-get install -y -o Dpkg::Options::="--force-overwrite" -o APT::Immediate-Configure=0 gcc-${GCC_VER}-source gcc-${GCC_VER}-aarch64-linux-gnu g++-${GCC_VER}-aarch64-linux-gnu libstdc++6-arm64-cross binutils-aarch64-linux-gnu bison flex libtool gdb sharutils netbase libmpc-dev libmpfr-dev systemtap-sdt-dev autogen expect chrpath zip libc6-dev:arm64 linux-libc-dev:arm64 libgcc1:arm64 libstdc++6:arm64
}

prepare_extra_jetson() {
    # JETSON-FFMPEG
    ffmpeg_patch="jetson-ffmpeg-add-nvmpi-support.patch"
    apt-get install -y quilt
    pushd ${SOURCE_DIR}
    git clone --depth=1 https://github.com/Keylost/jetson-ffmpeg.git

    # generate patch from ffpatch.sh in jetson-ffmpeg and add it to the series
    ln -s debian/patches patches
    quilt push -a
    quilt new $ffmpeg_patch
    quilt add configure Makefile libavcodec/Makefile libavcodec/allcodecs.c libavcodec/nvmpi_dec.c libavcodec/nvmpi_enc.c
    pushd jetson-ffmpeg
    ./ffpatch.sh ${SOURCE_DIR}
    popd
    quilt refresh
    quilt pop -a

    # build nvmpi
    pushd jetson-ffmpeg
    mkdir build
    pushd build
    cmake \
        ${CMAKE_TOOLCHAIN_OPT} \
        -DCMAKE_INSTALL_PREFIX=${TARGET_DIR} \
        -DCMAKE_BUILD_TYPE=Release \
        ..
    make -j$(nproc) && make install && make install DESTDIR=${SOURCE_DIR}/jetson-ffmpeg
    echo "jetson-ffmpeg${TARGET_DIR}/lib/libnvmpi.* usr/lib/jellyfin-ffmpeg/lib" >> ${DPKG_INSTALL_LIST}
    popd
    popd
    popd
}

# Set the architecture-specific options
case ${ARCH} in
    'amd64')
        apt-get update && apt-get dist-upgrade -y
        prepare_extra_common
        prepare_extra_amd64
        CONFIG_SITE=""
        DEP_ARCH_OPT=""
        BUILD_ARCH_OPT=""
    ;;
    'arm64')
        if [ "${CROSS}" == true ]; then
            prepare_crossbuild_env_arm64
            ln -s /usr/bin/aarch64-linux-gnu-gcc-${GCC_VER} /usr/bin/aarch64-linux-gnu-gcc
            ln -s /usr/bin/aarch64-linux-gnu-gcc-ar-${GCC_VER} /usr/bin/aarch64-linux-gnu-gcc-ar
            ln -s /usr/bin/aarch64-linux-gnu-g++-${GCC_VER} /usr/bin/aarch64-linux-gnu-g++
        else
            apt-get update && apt-get dist-upgrade -y
        fi
        prepare_extra_common
        if [ -d "/sys/bus/platform/drivers/tegra-fuse" ]; then
            prepare_extra_jetson
        else
            prepare_extra_arm
        fi
        if [ "${CROSS}" == true ]; then
            CONFIG_SITE="/etc/dpkg-cross/cross-config.${ARCH}"
            DEP_ARCH_OPT="--host-arch arm64"
            BUILD_ARCH_OPT="-aarm64"
        else
            CONFIG_SITE=""
            DEP_ARCH_OPT=""
            BUILD_ARCH_OPT=""
        fi
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
mv /jellyfin-ffmpeg{,7}_* ${ARTIFACT_DIR}/deb/
chown -Rc $(stat -c %u:%g ${ARTIFACT_DIR}) ${ARTIFACT_DIR}
