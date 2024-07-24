#!/bin/bash

SCRIPT_REPO="https://github.com/zapping-vbi/zvbi.git"
SCRIPT_COMMIT="a48ab3a0d72efe9968ebafa34c425c892e4afa50"

ffbuild_enabled() {
    return 0
}

ffbuild_dockerbuild() {
    git-mini-clone "$SCRIPT_REPO" "$SCRIPT_COMMIT" zvbi
    cd zvbi

    ./autogen.sh

    local myconf=(
        --prefix="$FFBUILD_PREFIX"
        --disable-shared
        --enable-static
        --with-pic
        --without-doxygen
        --without-x
        --disable-dvb
        --disable-bktr
        --disable-nls
        --disable-proxy
    )

    if [[ $TARGET == win* || $TARGET == linux* ]]; then
        myconf+=(
            --host="$FFBUILD_TOOLCHAIN"
        )
    elif [[ $TARGET == mac* ]]; then
        :
    else
        echo "Unknown target"
        return -1
    fi

    ./configure "${myconf[@]}"
    make -C src -j$(nproc)
    make -C src install
    make SUBDIRS=. install
}

ffbuild_configure() {
    echo --enable-libzvbi
}

ffbuild_unconfigure() {
    echo --disable-libzvbi
}
