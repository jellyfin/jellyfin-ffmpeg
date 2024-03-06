#!/bin/bash
ffbuild_macbase() {
  git clone https://github.com/glennrp/libpng.git
  cd libpng
  git checkout v1.6.43
  mkdir build
  cd build

  cmake -DCMAKE_INSTALL_PREFIX="$FFBUILD_PREFIX" -DPNG_ARM_NEON=on -DPNG_INTEL_SSE=on -DPNG_SHARED=OFF -DPNG_EXECUTABLES=OFF -DPNG_TESTS=OFF ../

  make -j$(nproc)
  make install
}
