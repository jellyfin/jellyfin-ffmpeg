#!/bin/bash

# Builds the DEB inside the Docker container

set -o errexit
set -o xtrace

DEBIAN_ADDR=http://deb.debian.org/debian/
UBUNTU_ARCHIVE_ADDR=http://archive.ubuntu.com/ubuntu/
UBUNTU_PORTS_ADDR=http://ports.ubuntu.com/ubuntu-ports/

# Prepare common extra libs for amd64, armhf and arm64
prepare_extra_common() {
    case ${ARCH} in
        'amd64')
            CROSS_PREFIX_OPT=""
            CROSS_OPT=""
            CMAKE_TOOLCHAIN_OPT=""
            MESON_CROSS_OPT=""
        ;;
        'armhf')
            CROSS_PREFIX_OPT="arm-linux-gnueabihf-"
            CROSS_OPT="--host=armv7-linux-gnueabihf CC=arm-linux-gnueabihf-gcc CXX=arm-linux-gnueabihf-g++"
            CMAKE_TOOLCHAIN_OPT="-DCMAKE_TOOLCHAIN_FILE=${SOURCE_DIR}/toolchain-${ARCH}.cmake"
            MESON_CROSS_OPT="--cross-file=${SOURCE_DIR}/cross-${ARCH}.meson"
        ;;
        'arm64')
            CROSS_PREFIX_OPT="aarch64-linux-gnu-"
            CROSS_OPT="--host=aarch64-linux-gnu CC=aarch64-linux-gnu-gcc CXX=aarch64-linux-gnu-g++"
            CMAKE_TOOLCHAIN_OPT="-DCMAKE_TOOLCHAIN_FILE=${SOURCE_DIR}/toolchain-${ARCH}.cmake"
            MESON_CROSS_OPT="--cross-file=${SOURCE_DIR}/cross-${ARCH}.meson"
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

    # LIBXML2
    pushd ${SOURCE_DIR}
    libxml2_ver="v2.13.5"
    if [[ $( lsb_release -c -s ) == "focal" ]]; then
        # newer versions require automake 1.16.3+
        libxml2_ver="v2.9.14"
    fi
    git clone -b ${libxml2_ver} --depth=1 https://github.com/GNOME/libxml2.git
    pushd libxml2
    if [[ $(lsb_release -c -s) != "focal" ]]; then
        # Fallback to internal entropy when system native method failed
        git apply ${SOURCE_DIR}/builder/patches/libxml2/v2.13.5/0001-dict-Fallback-to-internal-entropy.patch
    fi
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
    git clone -b VER-2-13-3 --depth=1 https://gitlab.freedesktop.org/freetype/freetype.git
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
    fc_ver="2.16.0"
    fc_link="https://www.freedesktop.org/software/fontconfig/release/fontconfig-${fc_ver}.tar.xz"
    wget ${fc_link} -O fc.tar.gz
    tar xaf fc.tar.gz
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
    git clone -b 10.2.0 --depth=1 https://github.com/harfbuzz/harfbuzz.git
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

    # LIBASS
    pushd ${SOURCE_DIR}
    git clone -b 0.17.3 --depth=1 https://github.com/libass/libass.git
    pushd libass
    ./autogen.sh
    ./configure \
        ${CROSS_OPT} \
        --prefix=${TARGET_DIR} \
        --enable-shared \
        --disable-static \
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
    git clone -b 1.5.0 --depth=1 https://code.videolan.org/videolan/dav1d.git
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
    git clone -b v2.3.0 --depth=1 https://gitlab.com/AOMediaCodec/SVT-AV1.git
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
    # FFNVCODEC
    pushd ${SOURCE_DIR}
    git clone -b n12.0.16.1 --depth=1 https://github.com/FFmpeg/nv-codec-headers.git
    pushd nv-codec-headers
    make && make install
    popd
    popd

    # AMF
    # https://www.ffmpeg.org/general.html#AMD-AMF_002fVCE
    pushd ${SOURCE_DIR}
    mkdir amf-headers
    pushd amf-headers
    amf_ver="1.4.35"
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
    libdrm_ver="2.4.124"
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
    git clone -b 2.22.0 --depth=1 https://github.com/intel/libva.git
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
    git clone -b 2.22.0 --depth=1 https://github.com/intel/libva-utils.git
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
    git clone -b intel-gmmlib-22.6.0 --depth=1 https://github.com/intel/gmmlib.git
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
    # fix build in gcc 13
    wget -q -O - https://github.com/Intel-Media-SDK/MediaSDK/commit/8fb9f5f.patch | git apply
    # fix ADI issue with VPL patch
    wget -q -O - https://github.com/intel/vpl-gpu-rt/commit/e025c82.patch | git apply
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
    git clone -b v2.14.0 --depth=1 https://github.com/intel/libvpl.git
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
    echo "intel${TARGET_DIR}/lib/libvpl.so* usr/lib/jellyfin-ffmpeg/lib" >> ${DPKG_INSTALL_LIST}
    popd
    popd
    popd

    # VPL-GPU-RT (RT only)
    # Provides VPL runtime (libmfx-gen.so.1.2) for 11th Gen Tiger Lake and newer
    pushd ${SOURCE_DIR}
    git clone -b intel-onevpl-25.1.0 --depth=1 https://github.com/intel/vpl-gpu-rt.git
    pushd vpl-gpu-rt
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
    git clone -b intel-media-25.1.0 --depth=1 https://github.com/intel/media-driver.git
    pushd media-driver
    # Enable VC1 decode on DG2 (note that MTL+ is not supported)
    wget -q -O - https://github.com/intel/media-driver/commit/d5dd47b.patch | git apply
    # Fix DG1 support in upstream i915 KMD (prod DKMS is not required)
    wget -q -O - https://github.com/intel/media-driver/commit/620a0b7.patch | git apply
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
    git clone -b v1.4.305 --depth=1 https://github.com/KhronosGroup/Vulkan-Headers.git
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
    git clone -b v1.4.305 --depth=1 https://github.com/KhronosGroup/Vulkan-Loader.git
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
    shaderc_ver="v2023.7"
    if [[ ${GCC_VER} -lt 9 ]]; then
        shaderc_ver="v2023.5"
    fi
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
    if [[ ${LLVM_VER} -ge 11 ]]; then
        mesa_branch="llvm15"
        mesa_codecs="all"
        if [[ ${LLVM_VER} -lt 15 ]]; then
            mesa_branch="llvm11"
            mesa_codecs="vc1dec,h264dec,h264enc,h265dec,h265enc"
        fi
        apt-get install -y llvm-${LLVM_VER}-dev libudev-dev
        pushd ${SOURCE_DIR}
        git clone -b ${mesa_branch} --depth=1 https://gitlab.freedesktop.org/nyanmisaka/mesa.git
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
            -Dvideo-codecs=${mesa_codecs} \
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
        ninja -j$(nproc) -C mesa_build install
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
    git clone -b v7.349.0 --recursive --depth=1 https://github.com/haasn/libplacebo.git
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
    git clone -b jellyfin-mpp --depth=1 https://github.com/nyanmisaka/mpp.git rkmpp
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
    echo "rkmpp${TARGET_DIR}/lib/librockchip*.* usr/lib/jellyfin-ffmpeg/lib" >> ${DPKG_INSTALL_LIST}
    popd
    popd
    popd

    # RKRGA
    pushd ${SOURCE_DIR}
    git clone -b jellyfin-rga --depth=1 https://github.com/nyanmisaka/rk-mirrors.git rkrga
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
prepare_crossbuild_env_armhf() {
    # Prepare the Ubuntu-specific cross-build requirements
    if [[ $( lsb_release -i -s ) == "Debian" ]]; then
        CODENAME="$( lsb_release -c -s )"
        echo "deb [arch=amd64] ${DEBIAN_ADDR} ${CODENAME}-backports main restricted universe multiverse" >> /etc/apt/sources.list
        echo "deb [arch=armhf] ${DEBIAN_ADDR} ${CODENAME}-backports main restricted universe multiverse" >> /etc/apt/sources.list
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
    apt-get update && apt-get dist-upgrade -y
    yes | apt-get install -y cross-gcc-dev
    # Generate gcc cross source
    TARGET_LIST="armhf" cross-gcc-gensource ${GCC_VER}
    # Install dependencies
    pushd cross-gcc-packages-amd64/cross-gcc-${GCC_VER}-armhf
    ln -fs /usr/share/zoneinfo/America/Toronto /etc/localtime
    yes | apt-get install -y -o Dpkg::Options::="--force-overwrite" -o APT::Immediate-Configure=0 gcc-${GCC_VER}-source gcc-${GCC_VER}-arm-linux-gnueabihf g++-${GCC_VER}-arm-linux-gnueabihf libstdc++6-armhf-cross binutils-arm-linux-gnueabihf bison flex libtool gdb sharutils netbase libmpc-dev libmpfr-dev systemtap-sdt-dev autogen expect chrpath zip libc6-dev:armhf linux-libc-dev:armhf libgcc1:armhf libstdc++6:armhf
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
    # Update and install cross-gcc-dev
    apt-get update && apt-get dist-upgrade -y
    yes | apt-get install -y cross-gcc-dev
    # Generate gcc cross source
    TARGET_LIST="arm64" cross-gcc-gensource ${GCC_VER}
    # Install dependencies
    pushd cross-gcc-packages-amd64/cross-gcc-${GCC_VER}-arm64
    ln -fs /usr/share/zoneinfo/America/Toronto /etc/localtime
    yes | apt-get install -y -o Dpkg::Options::="--force-overwrite" -o APT::Immediate-Configure=0 gcc-${GCC_VER}-source gcc-${GCC_VER}-aarch64-linux-gnu g++-${GCC_VER}-aarch64-linux-gnu libstdc++6-arm64-cross binutils-aarch64-linux-gnu bison flex libtool gdb sharutils netbase libmpc-dev libmpfr-dev systemtap-sdt-dev autogen expect chrpath zip libc6-dev:arm64 linux-libc-dev:arm64 libgcc1:arm64 libstdc++6:arm64
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
    'armhf')
        prepare_crossbuild_env_armhf
        ln -s /usr/bin/arm-linux-gnueabihf-gcc-${GCC_VER} /usr/bin/arm-linux-gnueabihf-gcc
        ln -s /usr/bin/arm-linux-gnueabihf-gcc-ar-${GCC_VER} /usr/bin/arm-linux-gnueabihf-gcc-ar
        ln -s /usr/bin/arm-linux-gnueabihf-g++-${GCC_VER} /usr/bin/arm-linux-gnueabihf-g++
        prepare_extra_common
        prepare_extra_arm
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
        prepare_extra_arm
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
mv /jellyfin-ffmpeg{,7}_* ${ARTIFACT_DIR}/deb/
chown -Rc $(stat -c %u:%g ${ARTIFACT_DIR}) ${ARTIFACT_DIR}
