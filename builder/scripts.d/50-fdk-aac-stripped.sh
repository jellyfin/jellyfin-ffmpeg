#!/bin/bash

SCRIPT_REPO="https://gitlab.freedesktop.org/wtaymans/fdk-aac-stripped.git"
SCRIPT_COMMIT="529b87452cd33d45e1d0a5066d20b64f10b38845"

ffbuild_enabled() {
    # Prefer AudioToolbox's AAC encoder on macOS
    [[ $TARGET == mac* ]] && return -1
    return 0
}

ffbuild_dockerbuild() {
    git-mini-clone "$SCRIPT_REPO" "$SCRIPT_COMMIT" fdk
    cd fdk

    ./autogen.sh

    local myconf=(
        --prefix="$FFBUILD_PREFIX"
        --disable-shared
        --enable-static
        --with-pic
        --disable-example
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
    make -j$(nproc)
    make install
}

ffbuild_configure() {
    echo --enable-libfdk-aac
}

ffbuild_unconfigure() {
    echo --disable-libfdk-aac
}
