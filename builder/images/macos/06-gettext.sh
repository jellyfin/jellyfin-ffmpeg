wget https://ftpmirror.gnu.org/gettext/gettext-0.22.5.tar.gz -O gettext.tar.gz
tar xvf gettext.tar.gz
cd gettext-0.22.5
./configure --disable-silent-rules --disable-shared --enable-static --with-included-glib --with-included-libcroco --with-included-libunistring --with-included-libxml --with-emacs --with-lispdir=/opt/ffbuild/prefix/share --disable-java --disable-csharp --without-git --without-cvs --without-xz --with-included-gettext --prefix=/opt/ffbuild/prefix
make -j$(nproc)
make install
