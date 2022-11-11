#!/bin/bash

SCRIPT_REPO="https://github.com/acoustid/chromaprint.git"
SCRIPT_COMMIT="b6d5f131e0c693ea877cbf49e0174be9fb0f9856"

ffbuild_enabled() {
    return 0
}

ffbuild_dockerbuild() {
    git-mini-clone "$SCRIPT_REPO" "$SCRIPT_COMMIT_PINNED" chromaprint
    cd chromaprint

    mkdir build && cd build

    ls -lh "$FFBUILD_PREFIX"/lib/pkgconfig

    cmake -DCMAKE_TOOLCHAIN_FILE="$FFBUILD_CMAKE_TOOLCHAIN" -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX="$FFBUILD_PREFIX" -DBUILD_SHARED_LIBS=OFF -DBUILD_TOOLS=OFF -DBUILD_TESTS=OFF -DFFT_LIB=fftw3f ..
    make -j$(nproc)
    make install
}

ffbuild_configure() {
    echo --enable-chromaprint
}

ffbuild_unconfigure() {
    echo --disable-chromaprint
}

ffbuild_cflags() {
    [[ $TARGET == win* ]] && echo '-DCHROMAPRINT_NODLL'
}

ffbuild_libs() {
    echo '-lfftw3f -lstdc++'
}
