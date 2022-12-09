#!/bin/bash

SCRIPT_REPO="https://code.videolan.org/videolan/dav1d.git"
SCRIPT_COMMIT="c56e352b95960d8dd243f6a14c7f1d7a431ceced"

ffbuild_enabled() {
    return 0
}

ffbuild_dockerbuild() {
    git-mini-clone "$SCRIPT_REPO" "$SCRIPT_COMMIT" dav1d
    cd dav1d

    mkdir build && cd build

    local myconf=(
        --prefix="$FFBUILD_PREFIX"
        --buildtype=release
        --default-library=static
    )

    if [[ $TARGET == win* || $TARGET == linux* ]]; then
        myconf+=(
            --cross-file=/cross.meson
        )
    else
        echo "Unknown target"
        return -1
    fi

    meson "${myconf[@]}" ..
    ninja -j$(nproc)
    ninja install
}

ffbuild_configure() {
    echo --enable-libdav1d
}

ffbuild_unconfigure() {
    echo --disable-libdav1d
}
