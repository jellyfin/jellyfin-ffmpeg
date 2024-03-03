#!/bin/bash
ffbuild_macbase() {
  wget https://github.com/adah1972/libunibreak/releases/download/libunibreak_5_1/libunibreak-5.1.tar.gz -O libunibreadk.tar.gz
  tar xvf libunibreadk.tar.gz
  cd libunibreak-5.1
  ./configure --prefix="$FFBUILD_PREFIX" \
          --disable-shared \
          --enable-static \
          --disable-silent-rules
  make -j$(nproc)
  make install
}
