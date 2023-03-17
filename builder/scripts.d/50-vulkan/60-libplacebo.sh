#!/bin/bash

SCRIPT_REPO="https://code.videolan.org/videolan/libplacebo.git"
SCRIPT_COMMIT="2394aea167a5995860387a2511f8972143cd5b82"

ffbuild_enabled() {
    return 0
}

ffbuild_dockerbuild() {
    git-mini-clone "$SCRIPT_REPO" "$SCRIPT_COMMIT" placebo
    cd placebo
    git submodule update --init --recursive

    mkdir build && cd build

    local myconf=(
        --prefix="$FFBUILD_PREFIX"
        --buildtype=release
        --default-library=static
        -Dvulkan=enabled
        -Dvk-proc-addr=disabled
        -Dvulkan-registry="$FFBUILD_PREFIX"/share/vulkan/registry/vk.xml
        -Dshaderc=enabled
        -Dglslang=disabled
        -Ddemos=false
        -Dtests=false
        -Dbench=false
        -Dfuzz=false
    )

    if [[ $TARGET == win* ]]; then
        myconf+=(
            -Dd3d11=enabled
        )
    fi

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

    echo "Libs.private: -lstdc++" >> "$FFBUILD_PREFIX"/lib/pkgconfig/libplacebo.pc
}

ffbuild_configure() {
    echo --enable-libplacebo
}

ffbuild_unconfigure() {
    [[ $ADDINS_STR == *4.4* ]] && return 0
    echo --disable-libplacebo
}
