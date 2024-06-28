FF_CONFIGURE="--enable-gpl --enable-version3 --enable-lto --disable-ffplay --disable-debug --disable-doc --disable-ptx-compression --disable-sdl2"
FF_CFLAGS=""
FF_CXXFLAGS=""
FF_LDFLAGS=""
GIT_BRANCH="jellyfin"
LICENSE_FILE="COPYING.GPLv3"

[[ $TARGET == linux* ]] && FF_CONFIGURE+=" --disable-libxcb --disable-xlib" || true
[[ $TARGET == win* ]] && FF_CFLAGS+=" -Wa,-muse-unaligned-vector-move" || true
[[ $TARGET == win* ]] && FF_CXXFLAGS+=" -Wa,-muse-unaligned-vector-move" || true
