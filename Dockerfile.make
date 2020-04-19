#!/usr/bin/make
DISTRO=stretch
GCC_VER=6
ARCH=amd64
.PHONY: Dockerfile
Dockerfile: Dockerfile.in
	sed 's/DISTRO/$(DISTRO)/; s/BUILD_ARCHITECTURE/$(ARCH)/; s/GCC_RELEASE_VERSION/$(GCC_VER)/' $< > $@ || rm -f $@
clean:
	rm -f Dockerfile
