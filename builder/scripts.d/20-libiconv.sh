#!/bin/bash

SCRIPT_REPO="https://skia.googlesource.com/third_party/libiconv"
SCRIPT_COMMIT="v1.17"
SCRIPT_TAGFILTER="v?.*"

ffbuild_enabled() {
    return 0
}

ffbuild_dockerbuild() {
    # iconv is macOS built-in
    [[ $TARGET == mac* ]] && return 0

    git-mini-clone "$SCRIPT_REPO" "$SCRIPT_COMMIT" iconv
    cd iconv

    cat <<EOF > ./.gitmodules
[subcheckout "gnulib"]
	url = https://github.com/coreutils/gnulib.git
	path = gnulib
EOF

    ./gitsub.sh pull

    local myconf=(
        --prefix="$FFBUILD_PREFIX"
        --enable-extra-encodings
        --disable-shared
        --enable-static
        --with-pic
    )

    if [[ $TARGET == win* || $TARGET == linux* ]]; then
        myconf+=(
            --host="$FFBUILD_TOOLCHAIN"
        )
    else
        echo "Unknown target"
        return -1
    fi

    ./autogen.sh
    ./configure "${myconf[@]}"
    make -j$(nproc)
    make install
}

ffbuild_configure() {
    echo --enable-iconv
}

ffbuild_unconfigure() {
    echo --disable-iconv
}
