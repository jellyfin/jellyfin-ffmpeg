#!/usr/bin/make
DISTRO=ubuntu:noble
.PHONY: Dockerfile
Dockerfile: Dockerfile.win64.in
	sed 's/DISTRO/$(DISTRO)/' $< > $@ || rm -f $@
clean:
	rm -f Dockerfile
