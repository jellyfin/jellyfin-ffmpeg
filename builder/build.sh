#!/bin/bash
set -xe
shopt -s globstar
cd "$(dirname "$0")"
source util/vars.sh

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

source "variants/${TARGET}-${VARIANT}.sh"

for addin in ${ADDINS[*]}; do
    source "addins/${addin}.sh"
done

export FFBUILD_PREFIX="$(docker run --rm "$IMAGE" bash -c 'echo $FFBUILD_PREFIX')"

for script in scripts.d/**/*.sh; do
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

TESTFILE="uidtestfile"
rm -f "$TESTFILE"
docker run --rm -v "$PWD:/uidtestdir" "$IMAGE" touch "/uidtestdir/$TESTFILE"
DOCKERUID="$(stat -c "%u" "$TESTFILE")"
rm -f "$TESTFILE"
[[ "$DOCKERUID" != "$(id -u)" ]] && UIDARGS=( -u "$(id -u):$(id -g)" ) || UIDARGS=()

rm -rf ffbuild
mkdir -p ffbuild/ffmpeg
rsync -a .. ffbuild/ffmpeg --exclude=$(basename "$PWD")

BUILD_SCRIPT="$(mktemp)"
trap "rm -f -- '$BUILD_SCRIPT'" EXIT

cat <<EOF >"$BUILD_SCRIPT"
    set -xe
    cd /ffbuild
    rm -rf prefix
    cd ffmpeg

    if [[ -f "debian/patches/series" ]]; then
        ln -s /ffbuild/ffmpeg/debian/patches patches
        quilt push -a
    fi

    ./configure --prefix=/ffbuild/prefix \
        \$FFBUILD_TARGET_FLAGS \
        --extra-version="Jellyfin" \
        --extra-cflags='$FF_CFLAGS' \
        --extra-cxxflags='$FF_CXXFLAGS' \
        --extra-ldflags='$FF_LDFLAGS' \
        --extra-ldexeflags='$FF_LDEXEFLAGS' \
        --extra-libs='$FF_LIBS' \
        $FF_CONFIGURE
    make -j\$(nproc) V=1
    make install
EOF

[[ -t 1 ]] && TTY_ARG="-t" || TTY_ARG=""

docker run --rm -i $TTY_ARG "${UIDARGS[@]}" -v $PWD/ffbuild:/ffbuild -v "$BUILD_SCRIPT":/build.sh "$IMAGE" bash /build.sh

mkdir -p artifacts
ARTIFACTS_PATH="$PWD/artifacts"
PKG_VER=$(dpkg-parsechangelog --show-field Version -l ffbuild/ffmpeg/debian/changelog)
PKG_NAME="jellyfin-ffmpeg_${PKG_VER}_portable_${TARGET}-${VARIANT}${ADDINS_STR:+-}${ADDINS_STR}"

mkdir -p ffbuild/pkgroot
cp ffbuild/prefix/bin/* ffbuild/pkgroot
[ "$(ls -A ffbuild/prefix/lib | grep -i ".*\.so.*\$")" ] && cp ffbuild/prefix/lib/*.so* ffbuild/pkgroot

cd ffbuild/pkgroot
if [[ "${TARGET}" == win* ]]; then
    OUTPUT_FNAME="${PKG_NAME}.zip"
    zip -9 -r "${ARTIFACTS_PATH}/${OUTPUT_FNAME}" *
else
    OUTPUT_FNAME="${PKG_NAME}.tar.xz"
    tar cJf "${ARTIFACTS_PATH}/${OUTPUT_FNAME}" *
fi
cd -

rm -rf ffbuild

if [[ -n "$GITHUB_ACTIONS" ]]; then
    echo "build_name=${BUILD_NAME}" >> "$GITHUB_OUTPUT"
    echo "${OUTPUT_FNAME}" > "${ARTIFACTS_PATH}/${TARGET}-${VARIANT}${ADDINS_STR:+-}${ADDINS_STR}.txt"
fi
