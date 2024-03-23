#!/usr/bin/make
DISTRO=noble
GCC_VER=13
LLVM_VER=17
ARCH=amd64
.PHONY: Dockerfile
Dockerfile: Dockerfile.in
	sed 's/DISTRO/$(DISTRO)/; s/BUILD_ARCHITECTURE/$(ARCH)/; s/GCC_RELEASE_VERSION/$(GCC_VER)/; s/LLVM_RELEASE_VERSION/$(LLVM_VER)/' $< > $@ || rm -f $@
clean:
	rm -f Dockerfile
