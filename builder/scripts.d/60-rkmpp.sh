#!/bin/bash

SCRIPT_REPO="https://github.com/nyanmisaka/mpp.git"
SCRIPT_COMMIT="2218dc0fc57062c0d33d06d350aea73d9fef5d57"

ffbuild_enabled() {
    [[ $TARGET == linux* ]] && [[ $TARGET == *arm64 ]] && return 0
    return -1
}

ffbuild_dockerstage() {
    to_df "RUN --mount=src=${SELF},dst=/stage.sh --mount=src=patches/rkmpp,dst=/patches run_stage /stage.sh"
}

ffbuild_dockerbuild() {
    git clone "$SCRIPT_REPO" mpp
    cd mpp
    git checkout "$SCRIPT_COMMIT"

    for patch in /patches/*.patch; do
        echo "Applying $patch"
        patch -p1 < "$patch"
    done

    mkdir rkmpp_build
    cd rkmpp_build
    cmake \
        -DCMAKE_INSTALL_PREFIX="$FFBUILD_PREFIX" \
        -DCMAKE_BUILD_TYPE=Release \
        -DBUILD_SHARED_LIBS=OFF \
        ..

    make -j$(nproc)
    make install

    echo "Libs.private: -lstdc++" >> "$FFBUILD_PREFIX"/lib/pkgconfig/rockchip_mpp.pc
}

ffbuild_configure() {
    echo --enable-rkmpp
}

ffbuild_unconfigure() {
    echo --disable-rkmpp
}
