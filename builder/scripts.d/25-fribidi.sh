#!/bin/bash

SCRIPT_REPO="https://github.com/fribidi/fribidi.git"
SCRIPT_COMMIT="e01a424c7cef4e805879ddcdc47f163f2a2f39dc"

ffbuild_enabled() {
    return 0
}

ffbuild_dockerbuild() {
    git-mini-clone "$SCRIPT_REPO" "$SCRIPT_COMMIT" fribidi
    cd fribidi

    mkdir build && cd build

    local myconf=(
        --prefix="$FFBUILD_PREFIX"
        --buildtype=release
        --default-library=static
        -Dbin=false
        -Ddocs=false
        -Dtests=false
    )

    if [[ $TARGET == win* || $TARGET == linux* ]]; then
        myconf+=(
            --cross-file=/cross.meson
        )
    elif [[ $TARGET == mac* ]]; then
        :
    else
        echo "Unknown target"
        return -1
    fi

    meson "${myconf[@]}" ..
    ninja -j$(nproc)
    ninja install

    if [[ $TARGET == mac* ]]; then
        gsed -i 's/Cflags:/Cflags: -DFRIBIDI_LIB_STATIC/' "$FFBUILD_PREFIX"/lib/pkgconfig/fribidi.pc
    else
        sed -i 's/Cflags:/Cflags: -DFRIBIDI_LIB_STATIC/' "$FFBUILD_PREFIX"/lib/pkgconfig/fribidi.pc
    fi
}

ffbuild_configure() {
    echo --enable-libfribidi
}

ffbuild_unconfigure() {
    echo --disable-libfribidi
}
