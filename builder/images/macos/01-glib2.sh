wget https://download.gnome.org/sources/glib/2.78/glib-2.78.4.tar.xz
tar xvf glib-2.78.4.tar.xz
cd glib-2.78.4
meson setup build --default-library=both \
      --localstatedir=/opt/ffbuild/prefix/var \
      -Dgio_module_dir=/opt/ffbuild/prefix/lib/gio/modules \
      -Dbsymbolic_functions=false \
      -Ddtrace=false \
      -Druntime_dir=/opt/ffbuild/prefix/var/run \
      -Dtests=false \
      --prefix=/opt/ffbuild/prefix \
      --buildtype=release \
      --default-library=static

sed -i '' 's/MacOSX11\.sdk/MacOSX\.sdk/g' build/build.ninja
meson compile -C build --verbose
meson install -C build
