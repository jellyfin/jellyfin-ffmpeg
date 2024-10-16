#!/bin/bash

SCRIPT_REPO="https://github.com/intel/libvpl.git"
SCRIPT_COMMIT="5f6bd8a1e753c8f63a3fd8b36894d6968b808a6d"

ffbuild_enabled() {
    [[ $TARGET == mac* ]] && return -1
    [[ $TARGET == *arm64 ]] && return -1
    return 0
}

ffbuild_dockerbuild() {
    git-mini-clone "$SCRIPT_REPO" "$SCRIPT_COMMIT" libvpl
    cd libvpl

    mkdir build && cd build

    cmake -GNinja -DCMAKE_TOOLCHAIN_FILE="$FFBUILD_CMAKE_TOOLCHAIN" -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX="$FFBUILD_PREFIX" \
        -DCMAKE_INSTALL_BINDIR="$FFBUILD_PREFIX"/bin -DCMAKE_INSTALL_LIBDIR="$FFBUILD_PREFIX"/lib \
        -DINSTALL_DEV=ON -DINSTALL_LIB=ON \
        -DBUILD_EXAMPLES=OFF -DBUILD_EXPERIMENTAL=OFF \
        -DBUILD_SHARED_LIBS=OFF -DBUILD_TESTS=OFF ..

    ninja -j$(nproc)
    ninja install

    rm -rf "$FFBUILD_PREFIX"/{etc,share}
}

ffbuild_configure() {
    [[ $TARGET != *arm64 ]] && echo --enable-libvpl
}

ffbuild_unconfigure() {
    return 0
    [[ $TARGET != *arm64 ]] && echo --disable-libvpl
}
