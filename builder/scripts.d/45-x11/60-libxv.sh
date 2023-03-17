#!/bin/bash

SCRIPT_REPO="https://gitlab.freedesktop.org/xorg/lib/libxv.git"
SCRIPT_COMMIT="d419928942dbf1897c9627475aa4a2828a81240f"

ffbuild_enabled() {
    [[ $TARGET != linux* ]] && return -1
    [[ $ADDINS_STR == *4.4* ]] && return -1
    return 0
}

ffbuild_dockerbuild() {
    git-mini-clone "$SCRIPT_REPO" "$SCRIPT_COMMIT" libxv
    cd libxv

    autoreconf -i

    local myconf=(
        --prefix="$FFBUILD_PREFIX"
        --enable-shared
        --disable-static
        --with-pic
        --without-lint
    )

    if [[ $TARGET == linuxarm64 ]]; then
        myconf+=(
            --disable-malloc0returnsnull
        )
    fi

    if [[ $TARGET == linux* ]]; then
        myconf+=(
            --host="$FFBUILD_TOOLCHAIN"
        )
    else
        echo "Unknown target"
        return -1
    fi

    export CFLAGS="$RAW_CFLAGS"
    export LDFLAFS="$RAW_LDFLAGS"

    ./configure "${myconf[@]}"
    make -j$(nproc)
    make install

    gen-implib "$FFBUILD_PREFIX"/lib/{libXv.so.1,libXv.a}
    rm "$FFBUILD_PREFIX"/lib/libXv{.so*,.la}
}

ffbuild_configure() {
    return 0
    echo --enable-xlib
}

ffbuild_unconfigure() {
    return 0
    echo --disable-xlib
}
