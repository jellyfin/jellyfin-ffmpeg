#!/usr/bin/make
DISTRO=ubuntu:hirsute
FF_REV=1
.PHONY: Dockerfile
Dockerfile: Dockerfile.win64.in
	sed 's/DISTRO/$(DISTRO)/; s/FFMPEG_REV/$(FF_REV)/' $< > $@ || rm -f $@
clean:
	rm -f Dockerfile
