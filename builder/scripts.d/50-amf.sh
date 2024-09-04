#!/bin/bash

SCRIPT_REPO="https://github.com/GPUOpen-LibrariesAndSDKs/AMF.git"
SCRIPT_COMMIT="a6fca4a3bb5585bd0bca4d1a531c40e39f5f572b"

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
    [[ $TARGET != *arm64 ]] && echo --enable-amf
}

ffbuild_unconfigure() {
    [[ $TARGET != *arm64 ]] && echo --disable-amf
}
