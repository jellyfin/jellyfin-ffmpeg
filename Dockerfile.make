#!/usr/bin/make
DISTRO=bullseye
GCC_VER=10
LLVM_VER=13
ARCH=amd64
.PHONY: Dockerfile
Dockerfile: Dockerfile.in
	sed 's/DISTRO/$(DISTRO)/; s/BUILD_ARCHITECTURE/$(ARCH)/; s/GCC_RELEASE_VERSION/$(GCC_VER)/' $< > $@ || rm -f $@
clean:
	rm -f Dockerfile
