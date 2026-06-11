#!/bin/bash

SCRIPT_REPO="https://github.com/FFTW/fftw3.git"
SCRIPT_COMMIT="4fca9817e68f77c118e4704562d63e45c02d38bf"

ffbuild_enabled() {
    # Dependency of GPL-Only librubberband
    [[ $VARIANT == lgpl* ]] && return -1
    # Prefer macOS native vDSP
    [[ $TARGET == mac* ]] && return -1
    return 0
}

ffbuild_dockerbuild() {
    git-mini-clone "$SCRIPT_REPO" "$SCRIPT_COMMIT_PINNED" fftw3f
    cd fftw3f

    local myconf=(
        --prefix="$FFBUILD_PREFIX"
        --enable-maintainer-mode
        --disable-shared
        --enable-static
        --enable-single
        --disable-fortran
        --disable-doc
        --with-our-malloc
        --enable-threads
        --with-combined-threads
        --with-incoming-stack-boundary=2
    )

    if [[ $TARGET == *arm64 ]]; then
        myconf+=(
            --enable-neon
        )
    elif [[ $TARGET == linuxriscv64 ]]; then
        # RISC-V: no SIMD yet (vector extension support pending)
        :
    elif [[ $TARGET == linux64 || $TARGET == win64 ]]; then
        myconf+=(
            --enable-sse2
            --enable-avx
            --enable-avx-128-fma
            --enable-avx2
            --enable-avx512
        )
    fi

    if [[ $TARGET == win* || $TARGET == linux* ]]; then
        myconf+=(
            --host="$FFBUILD_TOOLCHAIN"
        )
    else
        echo "Unknown target"
        return -1
    fi

    ./bootstrap.sh "${myconf[@]}"
    make -j$(nproc)
    make install
}
