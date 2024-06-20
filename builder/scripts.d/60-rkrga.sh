#!/bin/bash

SCRIPT_REPO="https://github.com/nyanmisaka/rk-mirrors.git"
SCRIPT_COMMIT="a9fc19e6b906d7cecd6bcefbd45e5e151831d33f"

ffbuild_enabled() {
    [[ $TARGET == linux* ]] && [[ $TARGET == *arm64 ]] && return 0
    return -1
}

ffbuild_dockerstage() {
    to_df "RUN --mount=src=${SELF},dst=/stage.sh --mount=src=patches/rkrga,dst=/patches run_stage /stage.sh"
}

ffbuild_dockerbuild() {
    git clone "$SCRIPT_REPO" rkrga
    cd rkrga
    git checkout "$SCRIPT_COMMIT"

    for patch in /patches/*.patch; do
        echo "Applying $patch"
        patch -p1 < "$patch"
    done

    cd ..

    meson setup rkrga rkrga_build \
        --cross-file=/cross.meson \
        --prefix=${FFBUILD_PREFIX} \
        --buildtype=release \
        --default-library=static \
        -Dcpp_args=-fpermissive \
        -Dlibdrm=false \
        -Dlibrga_demo=false

    meson configure rkrga_build
    ninja -C rkrga_build install

    echo "Libs.private: -lstdc++" >> "$FFBUILD_PREFIX"/lib/pkgconfig/librga.pc
}

ffbuild_configure() {
    echo --enable-rkrga
}

ffbuild_unconfigure() {
    echo --disable-rkrga
}