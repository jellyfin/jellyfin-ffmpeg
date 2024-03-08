#!/bin/bash

SCRIPT_REPO="https://github.com/openssl/openssl.git"
SCRIPT_COMMIT="openssl-3.1.5"
SCRIPT_TAGFILTER="openssl-3.1.*"

ffbuild_enabled() {
    return 0
}

ffbuild_dockerbuild() {
    git-mini-clone "$SCRIPT_REPO" "$SCRIPT_COMMIT" openssl
    cd openssl
    git submodule update --init --recursive --depth=1

    local myconf=(
        threads
        zlib
        no-shared
        no-tests
        no-apps
        no-legacy
        no-ssl2
        no-ssl3
        enable-camellia
        enable-ec
        enable-srp
        --prefix="$FFBUILD_PREFIX"
        --libdir=lib
    )

    if [[ $TARGET == win64 ]]; then
        myconf+=(
            --cross-compile-prefix="$FFBUILD_CROSS_PREFIX"
            mingw64
        )
    elif [[ $TARGET == win32 ]]; then
        myconf+=(
            --cross-compile-prefix="$FFBUILD_CROSS_PREFIX"
            mingw
        )
    elif [[ $TARGET == linux64 ]]; then
        myconf+=(
            --cross-compile-prefix="$FFBUILD_CROSS_PREFIX"
            linux-x86_64
        )
    elif [[ $TARGET == linuxarm64 ]]; then
        myconf+=(
            --cross-compile-prefix="$FFBUILD_CROSS_PREFIX"
            linux-aarch64
        )
    elif [[ $TARGET == mac* ]]; then
        :
    else
        echo "Unknown target"
        return -1
    fi

    export CFLAGS="$CFLAGS -fno-strict-aliasing"
    export CXXFLAGS="$CXXFLAGS -fno-strict-aliasing"

    if [[ $TARGET == mac* ]]; then
        gsed -i '/^my @disablables =/ s/$/"apps",/' Configure
    else
        # OpenSSL build system prepends the cross prefix itself
        export CC="${CC/${FFBUILD_CROSS_PREFIX}/}"
        export CXX="${CXX/${FFBUILD_CROSS_PREFIX}/}"
        export AR="${AR/${FFBUILD_CROSS_PREFIX}/}"
        export RANLIB="${RANLIB/${FFBUILD_CROSS_PREFIX}/}"

        # Actually allow Configure to disable apps
        sed -i '/^my @disablables =/ s/$/"apps",/' Configure
    fi

    ./Configure "${myconf[@]}"

    if [[ $TARGET == mac* ]]; then
        gsed -i -e "/^CFLAGS=/s|=.*|=${CFLAGS}|" -e "/^LDFLAGS=/s|=[[:space:]]*$|=${LDFLAGS}|" Makefile
    else
        sed -i -e "/^CFLAGS=/s|=.*|=${CFLAGS}|" -e "/^LDFLAGS=/s|=[[:space:]]*$|=${LDFLAGS}|" Makefile

    fi

    make -j$(nproc) build_sw
    make install_sw
}

ffbuild_configure() {
    [[ $TARGET == win* ]] && return 0
    echo --enable-openssl
}
