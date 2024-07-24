#!/bin/bash

SCRIPT_REPO="https://github.com/FFTW/fftw3.git"
SCRIPT_COMMIT="187045ea647ba19c55db5f503d11bd811ee6b56e"

ffbuild_enabled() {
    # Dependency of GPL-Only librubberband
    [[ $VARIANT == lgpl* ]] && return -1
    # Prefer macOS native vDSP
    [[ $TARGET == mac* ]] && return -1
    return 0
}

ffbuild_dockerbuild() {
    if [[ $TARGET != mac* ]]; then
        git-mini-clone "$SCRIPT_REPO" "$SCRIPT_COMMIT_PINNED" fftw3f
    else
        # The git does not build on macOS
        retry-tool check-wget "fftw-3.3.10.tar.gz" "http://fftw.org/fftw-3.3.10.tar.gz" "2d34b5ccac7b08740dbdacc6ebe451d8a34cf9d9bfec85a5e776e87adf94abfd803c222412d8e10fbaa4ed46f504aa87180396af1b108666cde4314a55610b40"
        tar xvf fftw-3.3.10.tar.gz
        mv fftw-3.3.10 fftw3f
    fi
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

    if [[ $TARGET != *arm64 ]]; then
        myconf+=(
            --enable-sse2
            --enable-avx
            --enable-avx-128-fma
            --enable-avx2
            --enable-avx512
        )
    else
        myconf+=(
            --enable-neon
        )
    fi

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

    ./bootstrap.sh "${myconf[@]}"
    if [[ $TARGET == mac* ]]; then
        sed -i '' 's/CC = gcc/CC = gcc-13/' Makefile
        sed -i '' 's/CPP = gcc/CPP = gcc-13/' Makefile
        gmake -j$(nproc)
        gmake install
    else
        make -j$(nproc)
        make install
    fi
}
