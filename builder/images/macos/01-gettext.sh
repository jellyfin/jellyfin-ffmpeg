#!/bin/bash
ffbuild_macbase() {
  wget https://mirrors.kernel.org/gnu/gettext/gettext-0.22.5.tar.gz -O gettext.tar.gz
  tar xvf gettext.tar.gz
  cd gettext-0.22.5
  ./configure --disable-silent-rules --disable-shared --enable-static --with-included-glib --with-included-libcroco --with-included-libunistring --with-included-libxml --with-emacs --with-lispdir="$FFBUILD_PREFIX"/share --disable-java --disable-csharp --without-git --without-cvs --without-xz --with-included-gettext --prefix="$FFBUILD_PREFIX"
  make -j$(nproc)
  make install
}
