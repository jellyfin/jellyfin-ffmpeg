#!/bin/bash

SCRIPT_REPO="https://github.com/FFmpeg/nv-codec-headers.git"
SCRIPT_COMMIT="f8ae7a49bfef2f99d2c931a791dc3863fda67bf3"

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
