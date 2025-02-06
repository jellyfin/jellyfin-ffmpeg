#!/usr/bin/make
DISTRO=noble
GCC_VER=13
LLVM_VER=19
LLVMSPIRVLIB_VER=18
ARCH=amd64
.PHONY: Dockerfile
Dockerfile: Dockerfile.in
	sed 's/DISTRO/$(DISTRO)/; s/BUILD_ARCHITECTURE/$(ARCH)/; s/GCC_RELEASE_VERSION/$(GCC_VER)/; s/LLVM_RELEASE_VERSION/$(LLVM_VER)/; s/LLVMSPIRVLIB_RELEASE_VERSION/$(LLVMSPIRVLIB_VER)/' $< > $@ || rm -f $@
clean:
	rm -f Dockerfile
