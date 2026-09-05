#!/bin/bash

SCRIPT_REPO="https://github.com/FFmpeg/nv-codec-headers.git"
SCRIPT_COMMIT="451da99614412a7f9526ef301a5ee0c7a6f9ad76"

ffbuild_enabled() {
    [[ $TARGET == mac* ]] && return -1
    return 0
}

ffbuild_dockerbuild() {
    git-mini-clone "$SCRIPT_REPO" "$SCRIPT_COMMIT" ffnvcodec
    cd ffnvcodec

    make PREFIX="$FFBUILD_PREFIX" install
}

ffbuild_configure() {
    [[ $TARGET == linuxriscv64 ]] && return 0
    echo --enable-ffnvcodec --enable-cuda --enable-cuda-llvm --enable-cuvid --enable-nvdec --enable-nvenc
}

ffbuild_unconfigure() {
    [[ $TARGET == mac* ]] && return 0
    echo --disable-ffnvcodec --disable-cuda --disable-cuda-llvm --disable-cuvid --disable-nvdec --disable-nvenc
}

ffbuild_cflags() {
    return 0
}

ffbuild_ldflags() {
    return 0
}
