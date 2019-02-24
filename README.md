FFmpeg README
=============

FFmpeg is a collection of libraries and tools to process multimedia content
such as audio, video, subtitles and related metadata.

## For Jellyfin

This particular repository is designed to support building a static, portable,
FFMPEG release of 4.0.3 for the [Jellyfin project](https://github.com/jellyfin).

To build packages, use `./build <release> <arch>`, where `release` is one of:
  * `stretch` (Debian 9.X "Stretch")
  * `buster` (Debian 10.X "Buster")
  * `xenial` (Ubuntu 16.04 "Xenial Xerus")
  * `bionic` (Ubuntu 18.04 "Bionic Beaver")
  * `cosmic` (Ubuntu 18.10 "Cosmic Cuttlefish")

And `arch` is one of:
  * `amd64` (Standard 64-bit x86)
  * `armhf` (ARMv6, Raspberry Pi)

The build setup requires `docker` support and may use a significant amount of
disk space. Binary releases are available in the [repository](https://repo.jellyfin.org/releases/server).

For older Ubuntu releases in between these officially supported versions, the
oldest should generally be compatible.

The build setup will attempt to generate both `amd64` and `armhf` binary packages
if the release supports it.

## Libraries

* `libavcodec` provides implementation of a wider range of codecs.
* `libavformat` implements streaming protocols, container formats and basic I/O access.
* `libavutil` includes hashers, decompressors and miscellaneous utility functions.
* `libavfilter` provides a mean to alter decoded Audio and Video through chain of filters.
* `libavdevice` provides an abstraction to access capture and playback devices.
* `libswresample` implements audio mixing and resampling routines.
* `libswscale` implements color conversion and scaling routines.

## Tools

* [ffmpeg](https://ffmpeg.org/ffmpeg.html) is a command line toolbox to
  manipulate, convert and stream multimedia content.
* [ffplay](https://ffmpeg.org/ffplay.html) is a minimalistic multimedia player.
* [ffprobe](https://ffmpeg.org/ffprobe.html) is a simple analysis tool to inspect
  multimedia content.
* Additional small tools such as `aviocat`, `ismindex` and `qt-faststart`.

## Documentation

The offline documentation is available in the **doc/** directory.

The online documentation is available in the main [website](https://ffmpeg.org)
and in the [wiki](https://trac.ffmpeg.org).

### Examples

Coding examples are available in the **doc/examples** directory.

## License

FFmpeg codebase is mainly LGPL-licensed with optional components licensed under
GPL. Please refer to the LICENSE file for detailed information.

## Contributing

Patches should be submitted to the ffmpeg-devel mailing list using
`git format-patch` or `git send-email`. Github pull requests should be
avoided because they are not part of our review process and will be ignored.
