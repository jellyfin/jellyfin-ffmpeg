#!/bin/bash

SCRIPT_REPO="https://gitlab.freedesktop.org/fontconfig/fontconfig.git"
SCRIPT_COMMIT="bd83c04aa6f3cb864ba60dc5eaf2b41c4c269c63"

ffbuild_enabled() {
    return 0
}

ffbuild_dockerbuild() {
    git-mini-clone "$SCRIPT_REPO" "$SCRIPT_COMMIT" fc
    cd fc

    if [[ $TARGET == mac* ]]; then
        autoreconf -iv
    else
        ./autogen.sh --noconf
    fi

    local myconf=(
        --prefix="$FFBUILD_PREFIX"
        --disable-docs
        --enable-libxml2
        --enable-iconv
        --disable-shared
        --enable-static
    )

    if [[ $TARGET == linux* ]]; then
        myconf+=(
            --sysconfdir=/etc
            --localstatedir=/var
            --host="$FFBUILD_TOOLCHAIN"
        )
    elif [[ $TARGET == win* ]]; then
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

    ./configure "${myconf[@]}"
    make -j$(nproc)
    make install
    #  Manually tell it to link against macOS builtin and static libintl
    if [[ $TARGET == mac* ]]; then
        sed -i '' '/^Libs:/ s/$/ -lintl -framework CoreFoundation/' "$FFBUILD_PREFIX"/lib/pkgconfig/fontconfig.pc
    fi
}

ffbuild_configure() {
    echo --enable-fontconfig
}

ffbuild_unconfigure() {
    echo --disable-fontconfig
}
