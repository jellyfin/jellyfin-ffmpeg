#!/bin/bash
ffbuild_macbase() {
  wget https://ftpmirror.gnu.org/gnu/gettext/gettext-1.0.tar.gz -O gettext.tar.gz
  tar xvf gettext.tar.gz
  cd gettext-1.0
  ./configure --disable-silent-rules --disable-shared --enable-static --with-included-glib --with-included-libcroco --with-included-libunistring --with-included-libxml --with-emacs --with-lispdir="$FFBUILD_PREFIX"/share --disable-java --disable-csharp --without-git --without-cvs --without-xz --with-included-gettext --prefix="$FFBUILD_PREFIX" LDFLAGS="$LDFLAGS -liconv"
  make -j$(nproc)
  make install
}
