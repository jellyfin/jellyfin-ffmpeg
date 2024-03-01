#!/bin/bash

SCRIPT_REPO="https://github.com/harfbuzz/harfbuzz.git"
SCRIPT_COMMIT="846d5204c07b006adcca2ca0937e5d6935d66334"

ffbuild_enabled() {
    return 0
}

ffbuild_dockerbuild() {
    git-mini-clone "$SCRIPT_REPO" "$SCRIPT_COMMIT" harfbuzz
    cd harfbuzz

    local myconf=(
        --prefix="$FFBUILD_PREFIX"
        --disable-shared
        --enable-static
        --with-pic
    )

    if [[ $TARGET == win* || $TARGET == linux* ]]; then
        myconf+=(
            --host="$FFBUILD_TOOLCHAIN"
        )
    elif [[ $TARGET == mac* ]]; then
        # freetype's pkg-config usage cannot find static libbrotli
        export FREETYPE_LIBS="$(pkg-config --libs --static freetype2)"
    else
        echo "Unknown target"
        return -1
    fi

    export LIBS="-lpthread"

    ./autogen.sh "${myconf[@]}"
    make -j$(nproc)
    make install
}
