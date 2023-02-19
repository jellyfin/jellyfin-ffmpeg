#!/bin/bash

SCRIPT_REPO="https://github.com/lu-zero/mfx_dispatch.git"
SCRIPT_COMMIT="5a3f178be7f406cec920b9f52f46c1ae29f29bb2"

ffbuild_enabled() {
    [[ $TARGET == *arm64 ]] && return -1
    return 0
}

ffbuild_dockerstage() {
    to_df "RUN --mount=src=${SELF},dst=/stage.sh --mount=src=patches/mfx,dst=/patches run_stage /stage.sh"
}

ffbuild_dockerbuild() {
    git-mini-clone "$SCRIPT_REPO" "$SCRIPT_COMMIT" mfx
    cd mfx

    for patch in /patches/*.patch; do
        echo "Applying $patch"
        patch -p1 < "$patch"
    done

    autoreconf -i

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
    else
        echo "Unknown target"
        return -1
    fi

    ./configure "${myconf[@]}"
    make -j$(nproc)
    make install

    ln -s libmfx.pc "$FFBUILD_PREFIX"/lib/pkgconfig/mfx.pc
}

ffbuild_configure() {
    [[ $TARGET != *arm64 ]] && echo --enable-libmfx
}

ffbuild_unconfigure() {
    [[ $TARGET != *arm64 ]] && echo --disable-libmfx
}
