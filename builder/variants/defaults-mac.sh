MACOS_MAJOR_VER="$(sw_vers -productVersion | awk -F '.' '{print $1}')"
XCODE_MAJOR_VER="$(xcodebuild -version | grep 'Xcode' | awk '{print $2}' | cut -d '.' -f 1)"

FF_CFLAGS+="-I"$FFBUILD_PREFIX"/include"
FF_LDFLAGS+="-L"$FFBUILD_PREFIX"/lib"
FF_CONFIGURE+=" --disable-libjack --disable-indev=jack --enable-neon --enable-runtime-cpudetect --enable-audiotoolbox --enable-videotoolbox"
FFBUILD_TARGET_FLAGS="--disable-shared --enable-static --pkg-config-flags=\"--static\" --enable-pthreads --cc=clang"
FF_HOST_CFLAGS="-I/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include -I"$FFBUILD_PREFIX"/include"
FF_HOST_LDFLAGS=""
if [ $XCODE_MAJOR_VER -ge 15 ]; then
  FF_HOST_LDFLAGS+="-Wl,-ld_classic "
  export LDFLAGS="-Wl,-ld_classic"
fi
FF_HOST_LDFLAGS+="-L/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/lib -L"$FFBUILD_PREFIX"/lib"
export PKG_CONFIG_LIBDIR="/usr/lib/pkgconfig:/opt/homebrew/Library/Homebrew/os/mac/pkgconfig/$MACOS_MAJOR_VER:/usr/local/Homebrew/Library/Homebrew/os/mac/pkgconfig/$MACOS_MAJOR_VER"
export CMAKE_PREFIX_PATH=""$FFBUILD_PREFIX""
export PKG_CONFIG_PATH=""$FFBUILD_PREFIX"/lib/pkgconfig"
export RANLIB="/usr/bin/ranlib"
