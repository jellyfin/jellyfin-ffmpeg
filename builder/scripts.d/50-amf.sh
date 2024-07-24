#!/bin/bash

SCRIPT_REPO="https://github.com/GPUOpen-LibrariesAndSDKs/AMF.git"
SCRIPT_COMMIT="6d7bec0469961e2891c6e1aaa5122b76ed82e1db"

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
