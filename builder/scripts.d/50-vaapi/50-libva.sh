#!/bin/bash

SCRIPT_REPO="https://github.com/intel/libva.git"
SCRIPT_COMMIT="b8c7eed68846a8b9cdf1040be414880a4e0924a8"

ffbuild_enabled() {
    [[ $TARGET != linux* ]] && return -1
    [[ $TARGET == linuxarm64 ]] && return -1
    return 0
}

ffbuild_dockerbuild() {
    git-mini-clone "$SCRIPT_REPO" "$SCRIPT_COMMIT" libva
    cd libva

    autoreconf -i

    local myconf=(
        --prefix="$FFBUILD_PREFIX"
        --enable-shared
        --disable-static
        --with-pic
        --disable-docs
        --enable-drm
        --enable-x11
        --disable-glx
        --disable-wayland
    )

    if [[ $TARGET == linux64 ]]; then
        myconf+=(
            --host="$FFBUILD_TOOLCHAIN"
            --with-drivers-path="/usr/lib/x86_64-linux-gnu/dri"
            --sysconfdir="/etc"
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

    gen-implib "$FFBUILD_PREFIX"/lib/{libva.so.2,libva.a}
    gen-implib "$FFBUILD_PREFIX"/lib/{libva-drm.so.2,libva-drm.a}
    gen-implib "$FFBUILD_PREFIX"/lib/{libva-x11.so.2,libva-x11.a}
    rm "$FFBUILD_PREFIX"/lib/libva{,-drm,-x11}{.so*,.la}

    echo "Libs: -ldl" >> "$FFBUILD_PREFIX"/lib/pkgconfig/libva.pc
}

ffbuild_configure() {
    [[ $TARGET == linux* ]] && [[ $TARGET != linuxarm64 ]] && echo --enable-vaapi
}

ffbuild_unconfigure() {
    [[ $TARGET == linux* ]] && [[ $TARGET != linuxarm64 ]] && echo --disable-vaapi
}
