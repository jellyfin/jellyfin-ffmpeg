#!/bin/bash

SCRIPT_REPO="https://github.com/Haivision/srt.git"
SCRIPT_COMMIT="84b5bb8c2bfd331ac55aba70fe09e5d3cbb00dee"

ffbuild_enabled() {
    return 0
}

ffbuild_dockerbuild() {
    git-mini-clone "$SCRIPT_REPO" "$SCRIPT_COMMIT" srt
    cd srt

    mkdir build && cd build

    if [[ $TARGET == mac* ]]; then
        cmake -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX="$FFBUILD_PREFIX" \
        -DENABLE_SHARED=OFF -DENABLE_STATIC=ON -DENABLE_CXX_DEPS=ON -DUSE_STATIC_LIBSTDCXX=ON -DENABLE_ENCRYPTION=ON -DENABLE_APPS=OFF ..
    else
        cmake -DCMAKE_TOOLCHAIN_FILE="$FFBUILD_CMAKE_TOOLCHAIN" -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX="$FFBUILD_PREFIX" \
        -DENABLE_SHARED=OFF -DENABLE_STATIC=ON -DENABLE_CXX_DEPS=ON -DUSE_STATIC_LIBSTDCXX=ON -DENABLE_ENCRYPTION=ON -DENABLE_APPS=OFF ..
    fi
    make -j$(nproc)
    make install

    if [[ $TARGET != mac* ]]; then
        echo "Libs.private: -lstdc++" >> "$FFBUILD_PREFIX"/lib/pkgconfig/srt.pc
    fi
}

ffbuild_configure() {
    echo --enable-libsrt
}

ffbuild_unconfigure() {
    echo --disable-libsrt
}
