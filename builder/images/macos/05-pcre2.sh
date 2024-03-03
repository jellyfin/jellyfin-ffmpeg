#!/bin/bash
# Although newer macOS has libpcre built-in, it is absent on macOS12
ffbuild_macbase() {
  wget https://github.com/PCRE2Project/pcre2/releases/download/pcre2-10.42/pcre2-10.42.tar.bz2
  tar xvf pcre2-10.42.tar.bz2
  cd pcre2-10.42
  ./configure --prefix=="$FFBUILD_PREFIX" \
          --disable-shared \
          --enable-static \
          --disable-dependency-tracking \
          --enable-pcre2-16 \
          --enable-pcre2-32 \
          --enable-pcre2grep-libz \
          --enable-pcre2grep-libbz2 \
          --enable-jit

  make -j$(nproc)
  make install
}
