MACOS_MAJOR_VER="$(sw_vers -productVersion | awk -F '.' '{print $1}')"
XCODE_MAJOR_VER="$(xcodebuild -version | grep 'Xcode' | awk '{print $2}' | cut -d '.' -f 1)"
MACOS_BUILDER_CPU_ARCH="$(uname -m)"
MACOS_SDKROOT="$(xcrun --sdk macosx --show-sdk-path)"

FF_CFLAGS+="-I"$FFBUILD_PREFIX"/include"
FF_LDFLAGS+="-L"$FFBUILD_PREFIX"/lib"
FF_CONFIGURE+=" --disable-unstable --disable-libjack --disable-indev=jack --disable-libxcb --disable-xlib --enable-neon --enable-runtime-cpudetect --enable-audiotoolbox --enable-videotoolbox"
FFBUILD_TARGET_FLAGS="--disable-shared --enable-static --pkg-config-flags=\"--static\" --enable-pthreads --cc=clang"
FF_HOST_CFLAGS="-isysroot $MACOS_SDKROOT -I"$FFBUILD_PREFIX"/include"
FF_HOST_LDFLAGS=""

# As of Xcode 15.4, this workaround is no longer needed.
# If you enconters duplicated symbol linker error try uncomment the following
# if [ $XCODE_MAJOR_VER -ge 15 ]; then
#   FF_HOST_LDFLAGS+="-Wl,-ld_classic "
#   export LDFLAGS="-Wl,-ld_classic"
# fi

FF_HOST_LDFLAGS+="-isysroot $MACOS_SDKROOT -L"$FFBUILD_PREFIX"/lib"
export PKG_CONFIG_LIBDIR="/usr/lib/pkgconfig:/opt/homebrew/Library/Homebrew/os/mac/pkgconfig/$MACOS_MAJOR_VER:/usr/local/Homebrew/Library/Homebrew/os/mac/pkgconfig/$MACOS_MAJOR_VER"
export CMAKE_PREFIX_PATH=""$FFBUILD_PREFIX""
export PKG_CONFIG_PATH=""$FFBUILD_PREFIX"/lib/pkgconfig"
export RANLIB="/usr/bin/ranlib"
export MACOSX_DEPLOYMENT_TARGET="12.0"
export CMAKE_POLICY_VERSION_MINIMUM="3.5"

if [ "$MACOS_BUILDER_CPU_ARCH" = "arm64" ] && [ "$TARGET" = "mac64" ]; then
    CROSS_CFLAGS="-arch x86_64"
    CROSS_LDFLAGS="-arch x86_64"
    FF_CFLAGS+=" $CROSS_CFLAGS"
    FF_LDFLAGS+=" $CROSS_LDFLAGS"
    FFBUILD_TARGET_FLAGS+=" --enable-cross-compile --arch=x86_64"
    export CFLAGS="$CFLAGS $CROSS_CFLAGS"
    export CXXFLAGS="$CXXFLAGS $CROSS_CFLAGS"
    export LDFLAGS="$LDFLAGS $CROSS_LDFLAGS"
    export CMAKE_OSX_ARCHITECTURES="x86_64"
fi
