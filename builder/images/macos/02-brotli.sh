wget https://github.com/google/brotli/archive/refs/tags/v1.1.0.tar.gz -O broti.tar.gz
tar xvf broti.tar.gz
cd brotli-1.1.0

# Google hardcodes their libs to be dynamic and does not horner -DENABLE_STATIC=ON
sed -i '' 's/add_library(brotlicommon/add_library(brotlicommon STATIC/' CMakeLists.txt
sed -i '' 's/add_library(brotlidec/add_library(brotlidec STATIC/' CMakeLists.txt
sed -i '' 's/add_library(brotlienc/add_library(brotlienc STATIC/' CMakeLists.txt

mkdir build
cd build

cmake ../ -DCMAKE_INSTALL_PREFIX=/opt/ffbuild/prefix \
        -DCMAKE_BUILD_TYPE=Release \
        -DENABLE_SHARED=OFF \
        -DENABLE_STATIC=ON \
        -DBUILD_STATIC_LIBS=ON
make -j$(nproc)
make install
