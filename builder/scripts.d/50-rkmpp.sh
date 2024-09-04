#!/bin/bash

SCRIPT_REPO="https://github.com/nyanmisaka/mpp.git"
SCRIPT_COMMIT="4ded78b9510145fa79bcd51beb1591450c872277"

ffbuild_enabled() {
    [[ $TARGET == linux* ]] && [[ $TARGET == *arm64 ]] && return 0
    return -1
}

ffbuild_dockerbuild() {
    git-mini-clone "$SCRIPT_REPO" "$SCRIPT_COMMIT" rkmpp
    cd rkmpp

    mkdir rkmpp_build && cd rkmpp_build

    cmake -GNinja \
        -DCMAKE_TOOLCHAIN_FILE="$FFBUILD_CMAKE_TOOLCHAIN" \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_INSTALL_PREFIX="$FFBUILD_PREFIX" \
        -DBUILD_TEST=OFF \
        -DBUILD_SHARED_LIBS=OFF ..

    ninja -j$(nproc)
    ninja install

    echo "Libs.private: -lstdc++" >> "$FFBUILD_PREFIX"/lib/pkgconfig/rockchip_mpp.pc
}

ffbuild_configure() {
    echo --enable-rkmpp
}

ffbuild_unconfigure() {
    echo --disable-rkmpp
}
