FF_CONFIGURE="--enable-gpl --enable-version3 --disable-ffplay --disable-debug --disable-doc --disable-ptx-compression --disable-sdl2"
FF_CFLAGS=""
FF_CXXFLAGS=""
FF_LDFLAGS=""
GIT_BRANCH="jellyfin"
LICENSE_FILE="COPYING.GPLv3"

[[ $TARGET == linux* ]] && FF_CONFIGURE+=" --disable-libxcb --disable-xlib --enable-lto=auto" || true
[[ $TARGET == win* ]] && FF_CONFIGURE+=" --enable-lto=auto" || true
[[ $TARGET == mac* ]] && FF_CONFIGURE+=" --enable-lto=thin" || true
