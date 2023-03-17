#!/bin/bash

SCRIPT_REPO="https://github.com/FFmpeg/nv-codec-headers.git"
SCRIPT_COMMIT="c5e4af74850a616c42d39ed45b9b8568b71bf8bf"

ffbuild_enabled() {
    [[ $TARGET == *arm64 ]] && return -1
    return 0
}

ffbuild_dockerbuild() {
    git-mini-clone "$SCRIPT_REPO" "$SCRIPT_COMMIT" ffnvcodec
    cd ffnvcodec

    make PREFIX="$FFBUILD_PREFIX" install
}

ffbuild_configure() {
    [[ $TARGET != *arm64 ]] && echo --enable-ffnvcodec --enable-cuda --enable-cuda-llvm --enable-cuvid --enable-nvdec --enable-nvenc
}

ffbuild_unconfigure() {
    [[ $TARGET != *arm64 ]] && echo --disable-ffnvcodec --disable-cuda --disable-cuda-llvm --disable-cuvid --disable-nvdec --disable-nvenc
}

ffbuild_cflags() {
    return 0
}

ffbuild_ldflags() {
    return 0
}
