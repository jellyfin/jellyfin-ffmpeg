#!/bin/bash
set -xe
cd "$(dirname "$0")"
export BUILDER_ROOT="$(pwd)"
export FFBUILD_PREFIX="/opt/ffbuild/prefix"

get_output() {
    (
        SELF="$1"
        source $1
        if ffbuild_enabled; then
            ffbuild_$2 || exit 0
        else
            ffbuild_un$2 || exit 0
        fi
    )
}

arch=$(uname -m)
TARGET="macarm64"
VARIANT="gpl"
if [ "$arch" = "arm64" ]; then
    TARGET="macarm64"
elif [ "$arch" = "x86_64" ]; then
    TARGET="mac64"
else
    echo "Unknown architecture"
    exit 1
fi

source "variants/${TARGET}-gpl.sh"

for addin in ${ADDINS[*]}; do
    source "addins/${addin}.sh"
done

for script in scripts.d/*.sh; do
    FF_CONFIGURE+=" $(get_output $script configure)"
    FF_CFLAGS+=" $(get_output $script cflags)"
    FF_CXXFLAGS+=" $(get_output $script cxxflags)"
    FF_LDFLAGS+=" $(get_output $script ldflags)"
    FF_LDEXEFLAGS+=" $(get_output $script ldexeflags)"
    FF_LIBS+=" $(get_output $script libs)"
done

FF_CONFIGURE="$(xargs <<< "$FF_CONFIGURE")"
FF_CFLAGS="$(xargs <<< "$FF_CFLAGS")"
FF_CXXFLAGS="$(xargs <<< "$FF_CXXFLAGS")"
FF_LDFLAGS="$(xargs <<< "$FF_LDFLAGS")"
FF_LDEXEFLAGS="$(xargs <<< "$FF_LDEXEFLAGS")"
FF_LIBS="$(xargs <<< "$FF_LIBS")"
FF_HOST_CFLAGS="$(xargs <<< "$FF_HOST_CFLAGS")"
FF_HOST_LDFLAGS="$(xargs <<< "$FF_HOST_LDFLAGS")"
FFBUILD_TARGET_FLAGS="$(xargs <<< "$FFBUILD_TARGET_FLAGS")"

mkdir build
for macbase in images/macos/*.sh; do
    cd "$BUILDER_ROOT"/build
    source $macbase
    ffbuild_macbase || exit $?
done

cd "$BUILDER_ROOT"
for lib in scripts.d/*.sh; do
    cd "$BUILDER_ROOT"/build
    source $lib
    ffbuild_enabled || exit 0
    ffbuild_dockerstage || exit $?
done

cd "$BUILDER_ROOT"
cd ..
if [[ -f "debian/patches/series" ]]; then
    ln -s debian/patches patches
    quilt push -a
fi

./configure --prefix=/ffbuild/prefix \
    $FFBUILD_TARGET_FLAGS \
    --host-cflags="$FF_HOST_CFLAGS" \
    --host-ldflags="$FF_HOST_LDFLAGS" \
    --extra-version="Jellyfin" \
    --extra-cflags="$FF_CFLAGS" \
    --extra-cxxflags="$FF_CXXFLAGS" \
    --extra-ldflags="$FF_LDFLAGS" \
    --extra-ldexeflags="$FF_LDEXEFLAGS" \
    --extra-libs="$FF_LIBS" \
    $FF_CONFIGURE
make -j$(nproc) V=1
