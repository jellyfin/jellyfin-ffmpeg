#!/bin/bash

SCRIPT_REPO="https://github.com/GPUOpen-LibrariesAndSDKs/AMF.git"
SCRIPT_COMMIT="eadd00804d5f7e5cd8c85d540073198312870776"

ffbuild_enabled() {
    [[ $TARGET == mac* ]] && return -1
    [[ $TARGET == *arm64 ]] && return -1
    return 0
}

ffbuild_dockerbuild() {
    git-mini-clone "$SCRIPT_REPO" "$SCRIPT_COMMIT" amf
    cd amf

    mkdir -p "$FFBUILD_PREFIX"/include
    mv amf/public/include "$FFBUILD_PREFIX"/include/AMF
}

ffbuild_configure() {
    [[ $TARGET == linuxriscv64 ]] && return 0
    echo --enable-amf
}

ffbuild_unconfigure() {
    [[ $TARGET == mac* ]] && return 0
    [[ $TARGET == *arm64 ]] && return 0
    echo --disable-amf
}
