#!/bin/bash

# Builds the EXE/ZIP inside the Docker container

set -o errexit
set -o xtrace

# mingw-std-threads
mingw_threads_commit="c931bac289dd431f1dd30fc4a5d1a7be36668073"
git clone https://github.com/meganz/mingw-std-threads.git
pushd mingw-std-threads
git checkout ${mingw_threads_commit}
mkdir -p ${FF_DEPS_PREFIX}/include
mv *.h ${FF_DEPS_PREFIX}/include
popd

# ICONV
mkdir iconv
pushd iconv
iconv_ver="1.19"
iconv_link="https://mirrors.edge.kernel.org/gnu/libiconv/libiconv-${iconv_ver}.tar.gz"
wget ${iconv_link} -O iconv.tar.gz
tar xaf iconv.tar.gz
pushd libiconv-${iconv_ver}
./configure \
    --prefix=${FF_DEPS_PREFIX} \
    --host=${FF_TOOLCHAIN} \
    --disable-shared \
    --enable-{static,extra-encodings} \
    --with-pic
make -j$(nproc)
make install
popd
popd

# LIBXML2
git clone -b v2.15.3 --depth=1 https://github.com/GNOME/libxml2.git
pushd libxml2
./autogen.sh \
    --prefix=${FF_DEPS_PREFIX} \
    --host=${FF_TOOLCHAIN} \
    --disable-{shared,maintainer-mode} \
    --enable-static \
    --without-python
make -j$(nproc)
make install
popd

# ZLIB
git clone -b v1.3.2 --depth=1 https://github.com/madler/zlib.git
pushd zlib
./configure \
    --prefix=${FF_DEPS_PREFIX} \
    --static
make -j$(nproc) CC=${FF_CROSS_PREFIX}gcc AR=${FF_CROSS_PREFIX}ar
make install
popd

# FRIBIDI
git clone -b v1.0.16 --depth=1 https://github.com/fribidi/fribidi.git
meson setup fribidi fribidi_build \
    --prefix=${FF_DEPS_PREFIX} \
    --cross-file=${FF_MESON_TOOLCHAIN} \
    --buildtype=release \
    --default-library=static \
    -D{bin,docs,tests}=false
meson configure fribidi_build
ninja -j$(nproc) -C fribidi_build install
sed -i 's/Cflags:/Cflags: -DFRIBIDI_LIB_STATIC/' ${FF_DEPS_PREFIX}/lib/pkgconfig/fribidi.pc

# FREETYPE
git clone -b VER-2-14-3 --depth=1 https://github.com/freetype/freetype.git
pushd freetype
./autogen.sh
./configure \
    --prefix=${FF_DEPS_PREFIX} \
    --host=${FF_TOOLCHAIN} \
    --disable-shared \
    --enable-static
make -j$(nproc)
make install
popd

# GMP
mkdir gmp
pushd gmp
gmp_ver="6.3.0"
gmp_link="https://mirrors.edge.kernel.org/gnu/gmp/gmp-${gmp_ver}.tar.xz"
wget ${gmp_link} -O gmp.tar.gz
tar xaf gmp.tar.gz
pushd gmp-${gmp_ver}
autoreconf -i
./configure \
    --prefix=${FF_DEPS_PREFIX} \
    --host=${FF_TOOLCHAIN} \
    --disable-shared \
    --enable-static
make -j$(nproc)
make install
popd
popd

# FFTW3
mkdir fftw3
pushd fftw3
fftw3_ver="3.3.11"
fftw3_link="https://fftw.org/fftw-${fftw3_ver}.tar.gz"
wget ${fftw3_link} -O fftw3.tar.gz
tar xaf fftw3.tar.gz
pushd fftw-${fftw3_ver}
./configure \
    --prefix=${FF_DEPS_PREFIX} \
    --host=${FF_TOOLCHAIN} \
    --disable-{shared,doc} \
    --enable-{static,single,threads,fortran} \
    --enable-{sse2,avx,avx-128-fma,avx2,avx512} \
    --with-our-malloc \
    --with-combined-threads \
    --with-incoming-stack-boundary=2
make -j$(nproc)
make install
popd
popd

# CHROMAPRINT
git clone -b v1.6.0 --depth=1 https://github.com/acoustid/chromaprint.git
pushd chromaprint
mkdir build
pushd build
cmake \
    -DCMAKE_TOOLCHAIN_FILE=${FF_CMAKE_TOOLCHAIN} \
    -DCMAKE_INSTALL_PREFIX=${FF_DEPS_PREFIX} \
    -DCMAKE_BUILD_TYPE=Release \
    -DBUILD_SHARED_LIBS=OFF \
    -DBUILD_{TOOLS,TESTS}=OFF \
    -DFFT_LIB=fftw3f \
    ..
make -j$(nproc)
make install
echo "Libs.private: -lfftw3f -lstdc++" >> ${FF_DEPS_PREFIX}/lib/pkgconfig/libchromaprint.pc
echo "Cflags.private: -DCHROMAPRINT_NODLL" >> ${FF_DEPS_PREFIX}/lib/pkgconfig/libchromaprint.pc
popd
popd

# LZMA
git clone -b v5.8.3 --depth=1 https://github.com/tukaani-project/xz.git
pushd xz
./autogen.sh --no-po4a --no-doxygen
./configure \
    --prefix=${FF_DEPS_PREFIX} \
    --host=${FF_TOOLCHAIN} \
    --disable-symbol-versions \
    --disable-shared \
    --enable-static \
    --disable-nls \
    --with-pic
make -j$(nproc)
make install
popd

# FONTCONFIG
git clone -b 2.17.1 --depth=1 https://chromium.googlesource.com/external/fontconfig
meson setup fontconfig fontconfig_build \
    --prefix=${FF_DEPS_PREFIX} \
    --cross-file=${FF_MESON_TOOLCHAIN} \
    --buildtype=release \
    --wrap-mode=nofallback \
    --default-library=static \
    -Diconv=enabled \
    -Dxml-backend=libxml2 \
    -D{cache-build,doc,tests,tools}=disabled
meson configure fontconfig_build
ninja -j$(nproc) -C fontconfig_build install

# HARFBUZZ
git clone -b 14.2.1 --depth=1 https://github.com/harfbuzz/harfbuzz.git
meson setup harfbuzz harfbuzz_build \
    --prefix=${FF_DEPS_PREFIX} \
    --cross-file=${FF_MESON_TOOLCHAIN} \
    --buildtype=release \
    --default-library=static \
    -Dfreetype=enabled \
    -D{gpu,glib,gobject,cairo,chafa,icu}=disabled \
    -D{tests,introspection,docs,utilities}=disabled
meson configure harfbuzz_build
ninja -j$(nproc) -C harfbuzz_build install

# LIBUDFREAD
git clone -b 1.2.0 --depth=1 https://code.videolan.org/videolan/libudfread.git
sed -i 's/-DUDFREAD_API_EXPORT/-DUDFREAD_API_EXPORT_DISABLED/g' libudfread/src/meson.build
meson setup libudfread libudfread_build \
    --prefix=${FF_DEPS_PREFIX} \
    --cross-file=${FF_MESON_TOOLCHAIN} \
    --buildtype=release \
    --default-library=static \
    -Denable_examples=false
meson configure libudfread_build
ninja -j$(nproc) -C libudfread_build install

# UNIBREAK
git clone -b libunibreak_7_0 --depth=1 https://github.com/adah1972/libunibreak.git
pushd libunibreak
./bootstrap
./configure \
    --prefix=${FF_DEPS_PREFIX} \
    --host=${FF_TOOLCHAIN} \
    --disable-shared \
    --enable-static \
    --with-pic
make -j$(nproc)
make install
popd

# LIBASS
git clone -b 0.17.5 --depth=1 https://github.com/libass/libass.git
pushd libass
./autogen.sh
./configure \
    --prefix=${FF_DEPS_PREFIX} \
    --host=${FF_TOOLCHAIN} \
    --disable-shared \
    --enable-{static,libunibreak} \
    --with-pic
make -j$(nproc)
make install
popd

# LIBBLURAY
git clone -b 1.4.1 --depth=1 https://code.videolan.org/videolan/libbluray.git
sed -i 's/dec_init/libbluray_dec_init/g' libbluray/src/libbluray/disc/*.{c,h}
sed -i 's/-DBLURAY_API_EXPORT/-DBLURAY_API_EXPORT_DISABLED/g' libbluray/src/meson.build
meson setup libbluray libbluray_build \
    --prefix=${FF_DEPS_PREFIX} \
    --cross-file=${FF_MESON_TOOLCHAIN} \
    --buildtype=release \
    -Ddefault_library=static \
    -Denable_{docs,tools,devtools,examples}=false \
    -Dbdj_jar=disabled \
    -D{fontconfig,freetype,libxml2}=enabled
meson configure libbluray_build
ninja -j$(nproc) -C libbluray_build install

# LAME
mkdir lame
pushd lame
lame_ver="3.100"
lame_link="https://sourceforge.net/projects/lame/files/lame/${lame_ver}/lame-${lame_ver}.tar.gz/download"
wget ${lame_link} -O lame.tar.gz
tar xaf lame.tar.gz
pushd lame-${lame_ver}
./configure \
    --prefix=${FF_DEPS_PREFIX} \
    --host=${FF_TOOLCHAIN} \
    --disable-{shared,gtktest,cpml,frontend} \
    --enable-{static,nasm}
make -j$(nproc)
make install
popd
popd

# OGG
git clone -b v1.3.6 --depth=1 https://github.com/xiph/ogg.git
pushd ogg
./autogen.sh
./configure \
    --prefix=${FF_DEPS_PREFIX} \
    --host=${FF_TOOLCHAIN} \
    --disable-shared \
    --enable-static \
    --with-pic
make -j$(nproc)
make install
popd

# OPUS
git clone -b v1.6.1 --depth=1 https://github.com/xiph/opus.git
pushd opus
./autogen.sh
./configure \
    --prefix=${FF_DEPS_PREFIX} \
    --host=${FF_TOOLCHAIN} \
    --disable-{shared,extra-programs} \
    --enable-static
make -j$(nproc)
make install
popd

# THEORA
git clone -b v1.2.0 --depth=1 https://github.com/xiph/theora.git
pushd theora
./autogen.sh
./configure \
    --prefix=${FF_DEPS_PREFIX} \
    --host=${FF_TOOLCHAIN} \
    --disable-{shared,examples,extra-programs,oggtest,vorbistest,spec,doc} \
    --enable-static \
    --with-pic
make -j$(nproc)
make install
popd

# VORBIS
git clone -b v1.3.7 --depth=1 https://github.com/xiph/vorbis.git
pushd vorbis
./autogen.sh
./configure \
    --prefix=${FF_DEPS_PREFIX} \
    --host=${FF_TOOLCHAIN} \
    --disable-{shared,oggtest} \
    --enable-static
make -j$(nproc)
make install
popd

# OPENMPT
mkdir mpt
pushd mpt
mpt_ver="0.8.7"
mpt_link="https://lib.openmpt.org/files/libopenmpt/src/libopenmpt-${mpt_ver}+release.autotools.tar.gz"
wget ${mpt_link} -O mpt.tar.gz
tar xaf mpt.tar.gz
pushd libopenmpt-${mpt_ver}+release.autotools
./configure \
    --prefix=${FF_DEPS_PREFIX} \
    --host=${FF_TOOLCHAIN} \
    --enable-static \
    --disable-{shared,examples,tests,openmpt123} \
    --without-{mpg123,portaudio,portaudiocpp,sndfile,flac}
make -j$(nproc)
make install
popd
popd

# LIBWEBP
git clone -b v1.6.0 --depth=1 https://chromium.googlesource.com/webm/libwebp
pushd libwebp
./autogen.sh
./configure \
    --prefix=${FF_DEPS_PREFIX} \
    --host=${FF_TOOLCHAIN} \
    --disable-{shared,libwebpextras,libwebpdemux,sdl,gl,png,jpeg,tiff,gif} \
    --enable-{static,libwebpmux} \
    --with-pic
make -j$(nproc)
make install
popd

# LIBVPX
git clone -b v1.16.0 --depth=1 https://chromium.googlesource.com/webm/libvpx
pushd libvpx
export CROSS=${FF_CROSS_PREFIX}
./configure \
    --prefix=${FF_DEPS_PREFIX} \
    --target=x86_64-win64-gcc \
    --disable-{shared,unit-tests,examples,tools,docs,install-bins} \
    --enable-{static,pic,vp9-postproc,vp9-highbitdepth}
make -j$(nproc)
make install
popd

# ZIMG
git clone -b release-3.0.6 --recursive --depth=1 https://github.com/sekrit-twc/zimg.git
pushd zimg
./autogen.sh
./configure \
    --prefix=${FF_DEPS_PREFIX} \
    --host=${FF_TOOLCHAIN} \
    --disable-shared \
    --with-pic
make -j$(nproc)
make install
popd

# X264
x264_commit="0480cb05fa188d37ae87e8f4fd8f1aea3711f7ee"
git clone https://code.videolan.org/videolan/x264.git
pushd x264
git checkout ${x264_commit}
./configure \
    --prefix=${FF_DEPS_PREFIX} \
    --host=${FF_TOOLCHAIN} \
    --cross-prefix=${FF_CROSS_PREFIX} \
    --disable-cli \
    --enable-{static,strip,pic}
make -j$(nproc)
make install
popd

# X265
x265_commit="e9b88125dc21393b3fd8d68e98083bdfb89778a8"
git clone https://github.com/Multicorewareinc/x265.git
pushd x265_git
git checkout ${x265_commit}
# Unbreak GCC 15
sed -i '1i#include <cstdint>' source/dynamicHDR10/json11/json11.cpp
x265_conf="
    -DCMAKE_TOOLCHAIN_FILE=${FF_CMAKE_TOOLCHAIN}
    -DCMAKE_INSTALL_PREFIX=${FF_DEPS_PREFIX}
    -DCMAKE_BUILD_TYPE=Release
    -DCMAKE_ASM_NASM_FLAGS=-w-macro-params-legacy
    -DENABLE_ASSEMBLY=ON
    -DENABLE_SHARED=OFF
    -DENABLE_TESTS=OFF
    -DENABLE_CLI=OFF
    -DENABLE_PIC=ON
    -DENABLE_ALPHA=ON
"
mkdir 8b 10b 12b
cmake \
    ${x265_conf} \
    -DHIGH_BIT_DEPTH=ON \
    -DEXPORT_C_API=OFF \
    -DENABLE_HDR10_PLUS=ON \
    -DMAIN12=ON \
    -S source \
    -B 12b &
cmake \
    ${x265_conf} \
    -DHIGH_BIT_DEPTH=ON \
    -DEXPORT_C_API=OFF \
    -DENABLE_HDR10_PLUS=ON \
    -S source \
    -B 10b &
cmake \
    ${x265_conf} \
    -DEXTRA_LIB="x265_main10.a;x265_main12.a" \
    -DEXTRA_LINK_FLAGS=-L. \
    -DLINKED_{10,12}BIT=ON \
    -S source \
    -B 8b &
wait
cat > Makefile << "EOF"
all: 12b/libx265.a 10b/libx265.a 8b/libx265.a
%/libx265.a:
	$(MAKE) -C $(subst /libx265.a,,$@)
.PHONY: all
EOF
make -j$(nproc)
pushd 8b
mv ../12b/libx265.a ../8b/libx265_main12.a
mv ../10b/libx265.a ../8b/libx265_main10.a
mv libx265.a libx265_main.a
${FF_CROSS_PREFIX}ar -M << "EOF"
CREATE libx265.a
ADDLIB libx265_main.a
ADDLIB libx265_main10.a
ADDLIB libx265_main12.a
SAVE
END
EOF
make install
echo "Libs.private: -lstdc++" >> ${FF_DEPS_PREFIX}/lib/pkgconfig/x265.pc
popd
popd

# SVT-AV1
git clone -b v4.2.0 --depth=1 https://gitlab.com/AOMediaCodec/SVT-AV1.git
pushd SVT-AV1
mkdir build
pushd build
cmake \
    -DCMAKE_TOOLCHAIN_FILE=${FF_CMAKE_TOOLCHAIN} \
    -DCMAKE_INSTALL_PREFIX=${FF_DEPS_PREFIX} \
    -DCMAKE_BUILD_TYPE=Release \
    -DBUILD_{SHARED_LIBS,TESTING,APPS,DEC}=OFF \
    ..
make -j$(nproc)
make install
popd
popd

# DAV1D
git clone -b 1.5.4 --depth=1 https://code.videolan.org/videolan/dav1d.git
meson setup dav1d dav1d_build \
    --prefix=${FF_DEPS_PREFIX} \
    --cross-file=${FF_MESON_TOOLCHAIN} \
    --buildtype=release \
    --default-library=static \
    -Denable_asm=true \
    -Denable_{tools,tests,examples}=false
meson configure dav1d_build
ninja -j$(nproc) -C dav1d_build install

# FDK-AAC-STRIPPED
git clone -b stripped5 --depth=1 https://gitlab.freedesktop.org/wtaymans/fdk-aac-stripped.git
pushd fdk-aac-stripped
./autogen.sh
./configure \
    --prefix=${FF_DEPS_PREFIX} \
    --host=${FF_TOOLCHAIN} \
    --disable-{silent-rules,shared} \
    --enable-static \
    CFLAGS="-O3 -DNDEBUG" \
    CXXFLAGS="-O3 -DNDEBUG"
make -j$(nproc)
make install
popd

# OpenCL headers
git clone -b v2023.04.17 --depth=1 https://github.com/KhronosGroup/OpenCL-Headers.git
pushd OpenCL-Headers/CL
mkdir -p ${FF_DEPS_PREFIX}/include/CL
mv * ${FF_DEPS_PREFIX}/include/CL
popd

# OpenCL ICD loader
git clone -b v2023.04.17 --depth=1 https://github.com/KhronosGroup/OpenCL-ICD-Loader.git
pushd OpenCL-ICD-Loader
mkdir build
pushd build
cmake \
    -DCMAKE_TOOLCHAIN_FILE=${FF_CMAKE_TOOLCHAIN} \
    -DCMAKE_INSTALL_PREFIX=${FF_DEPS_PREFIX} \
    -DCMAKE_BUILD_TYPE=Release \
    -DOPENCL_ICD_LOADER_HEADERS_DIR=${FF_DEPS_PREFIX}/include \
    -DOPENCL_ICD_LOADER_{PIC,DISABLE_OPENCLON12}=ON \
    -DOPENCL_ICD_LOADER_{BUILD_SHARED_LIBS,BUILD_TESTING,REQUIRE_WDK}=OFF \
    ..
make -j$(nproc)
make install
popd
mkdir -p ${FF_DEPS_PREFIX}/lib/pkgconfig
cat > ${FF_DEPS_PREFIX}/lib/pkgconfig/OpenCL.pc << EOF
prefix=${FF_DEPS_PREFIX}
exec_prefix=\${prefix}
libdir=\${prefix}/lib
includedir=\${prefix}/include
Name: OpenCL
Description: OpenCL ICD Loader
Version: 3.0
Libs: -L\${libdir} -l:OpenCL.a
Cflags: -I\${includedir}
Libs.private: -lole32 -lshlwapi -lcfgmgr32
EOF
popd

# FFNVCODEC
git clone -b n12.0.16.1 --depth=1 https://github.com/FFmpeg/nv-codec-headers.git
pushd nv-codec-headers
make PREFIX=${FF_DEPS_PREFIX} install
popd

# AMF
mkdir amf-headers
pushd amf-headers
amf_ver="1.5.2"
amf_link="https://github.com/GPUOpen-LibrariesAndSDKs/AMF/releases/download/v${amf_ver}/AMF-headers-v${amf_ver}.tar.gz"
wget ${amf_link} -O amf.tar.gz
tar xaf amf.tar.gz
pushd amf-headers-v${amf_ver}/AMF
mkdir -p ${FF_DEPS_PREFIX}/include/AMF
mv * ${FF_DEPS_PREFIX}/include/AMF
popd
popd

# VPL
git clone -b v2.17.0 --depth=1 https://github.com/intel/libvpl.git
pushd libvpl
mkdir build && pushd build
cmake \
    -DCMAKE_TOOLCHAIN_FILE=${FF_CMAKE_TOOLCHAIN} \
    -DCMAKE_INSTALL_PREFIX=${FF_DEPS_PREFIX} \
    -DCMAKE_INSTALL_BINDIR=${FF_DEPS_PREFIX}/bin \
    -DCMAKE_INSTALL_LIBDIR=${FF_DEPS_PREFIX}/lib \
    -DCMAKE_BUILD_TYPE=Release \
    -DBUILD_SHARED_LIBS=OFF \
    -DINSTALL_{DEV,LIB}=ON \
    -DINSTALL_EXAMPLES=OFF \
    -DBUILD_{TESTS,EXAMPLES,EXPERIMENTAL}=OFF \
    ..
make -j$(nproc)
make install
echo "Libs.private: -lstdc++" >> ${FF_DEPS_PREFIX}/lib/pkgconfig/vpl.pc
popd
popd

# Jellyfin-FFmpeg
pushd ${SOURCE_DIR}
ffversion="$(dpkg-parsechangelog --show-field Version)"
if [[ -f "patches/series" ]]; then
    quilt push -a
fi
./configure \
    --prefix=${FF_PREFIX} \
    ${FF_TARGET_FLAGS} \
    --extra-version=Jellyfin \
    --disable-unstable \
    --disable-ffplay \
    --disable-debug \
    --disable-doc \
    --disable-sdl2 \
    --disable-w32threads \
    --enable-pthreads \
    --enable-shared \
    --enable-gpl \
    --enable-version3 \
    --enable-schannel \
    --enable-iconv \
    --enable-libxml2 \
    --enable-zlib \
    --enable-lzma \
    --enable-gmp \
    --enable-chromaprint \
    --enable-libfreetype \
    --enable-libfribidi \
    --enable-libfontconfig \
    --enable-libharfbuzz \
    --enable-libass \
    --enable-libbluray \
    --enable-libmp3lame \
    --enable-libopus \
    --enable-libtheora \
    --enable-libvorbis \
    --enable-libopenmpt \
    --enable-libwebp \
    --enable-libvpx \
    --enable-libzimg \
    --enable-libx264 \
    --enable-libx265 \
    --enable-libsvtav1 \
    --enable-libdav1d \
    --enable-libfdk-aac \
    --enable-opencl \
    --enable-dxva2 \
    --enable-d3d11va \
    --enable-mediafoundation \
    --enable-amf \
    --enable-libvpl \
    --enable-ffnvcodec \
    --enable-cuda \
    --enable-cuda-llvm \
    --enable-cuvid \
    --enable-nvdec \
    --enable-nvenc
make -j$(nproc)
make install
popd

# Zip and copy artifacts
mkdir -p ${ARTIFACT_DIR}/zip
pushd ${FF_PREFIX}/bin
ffpackage="jellyfin-ffmpeg_${ffversion}-portable_win64"
zip -9 -r ${ARTIFACT_DIR}/zip/${ffpackage}.zip ./*.{exe,dll}
pushd ${ARTIFACT_DIR}/zip
chown -Rc $(stat -c %u:%g ${ARTIFACT_DIR}) ${ARTIFACT_DIR}
popd
popd
