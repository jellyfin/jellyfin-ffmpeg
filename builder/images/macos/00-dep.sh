#!/bin/bash

ffbuild_macbase() {
  if [[ $TARGET == mac64 ]]; then
    # For unknown reason ffmpeg insist to link to against libx11 and is hard to debug
    # It does not link against libx11 on arm64, which is strange
    # Remove everything using libx11 on github's x86 macOS host as a workaround
    brew uninstall ant cairo gradle harfbuzz kotlin libxext libxft libxrender maven openjdk r sbt selenium-server libx11
  fi
  brew install wget subversion mercurial autoconf automake cmake meson ninja pkg-config coreutils gcc make python-setuptools pcre2 libtool gnu-sed gnu-tar nasm quilt
  mkdir /opt/ffbuild/bin
  cp "$BUILDER_ROOT"/images/base/git-mini-clone.sh /opt/ffbuild/bin/git-mini-clone
  chmod +x /opt/ffbuild/bin/git-mini-clone
  cp "$BUILDER_ROOT"/images/base/retry-tool.sh /opt/ffbuild/bin/retry-tool
  chmod +x /opt/ffbuild/bin/retry-tool
  cp "$BUILDER_ROOT"/images/base/check-wget.sh /opt/ffbuild/bin/check-wget
  chmod +x /opt/ffbuild/bin/check-wget
  export PATH="/opt/ffbuild/bin:$PATH"
}
