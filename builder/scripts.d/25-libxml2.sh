#!/bin/bash

SCRIPT_REPO="https://github.com/GNOME/libxml2.git"
SCRIPT_COMMIT="1c82bca6bd23d0f0858d7fc228ec3a91fda3e0e2"

ffbuild_enabled() {
    return 0
}

ffbuild_dockerstage() {
    to_df "RUN --mount=src=${SELF},dst=/stage.sh --mount=src=patches/libxml2/master,dst=/patches run_stage /stage.sh"
}

ffbuild_dockerbuild() {
    # libxml2 is macOS built-in
    [[ $TARGET == mac* ]] && return 0

    git-mini-clone "$SCRIPT_REPO" "$SCRIPT_COMMIT" libxml2
    cd libxml2

    for patch in /patches/*.patch; do
        echo "Applying $patch"
        patch -p1 < "$patch"
    done

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
    echo --disable-libxml2
}
