#!/bin/bash

SCRIPT_REPO="https://github.com/GNOME/libxml2.git"
SCRIPT_COMMIT="12ce9b5ffeba776ede786c075795a4dbae94bfa1"

ffbuild_enabled() {
    # libxml2 is macOS built-in
    [[ $TARGET == mac* ]] && return -1
    return 0
}

ffbuild_dockerbuild() {
    git-mini-clone "$SCRIPT_REPO" "$SCRIPT_COMMIT" libxml2
    cd libxml2

    local myconf=(
        --prefix="$FFBUILD_PREFIX"
        --without-python
        --disable-maintainer-mode
        --disable-shared
        --enable-static
    )

    if [[ $TARGET == win* || $TARGET == linux* ]]; then
        myconf+=(
            --host="$FFBUILD_TOOLCHAIN"
        )
    else
        echo "Unknown target"
        return -1
    fi

    ./autogen.sh "${myconf[@]}"
    make -j$(nproc)
    make install
}

ffbuild_configure() {
    echo --enable-libxml2
}

ffbuild_unconfigure() {
    if [[ $TARGET == mac* ]]; then
        echo --enable-libxml2
    else
        echo --disable-libxml2
    fi
}
