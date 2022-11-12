# jellyfin-ffmpeg portable versions builder

Portable versions builder of jellyfin-ffmpeg for Windows and Linux.

## Package List

For a list of included dependencies check the `scripts.d` directory.
Every file corresponds to its respective package.

## How to make a build

### Prerequisites

* bash
* docker

### Step 1: Build image of dependencies

* `./makeimage.sh target variant [addins]`

### Step 2: Build jellyfn-ffmpeg

* `./build.sh target variant [addins]`

On success, the resulting `zip` or `tar.xz` file will be in the `artifacts` subdir.

### Targets, Variants and Addins

Available targets:
* `win64` (x86_64 Windows, windows>=7)
* `linux64` (x86_64 Linux, glibc>=2.23, linux>=4.4)
* `linuxarm64` (arm64 (aarch64) Linux, glibc>=2.27, linux>=4.15)

Available variants:
* `gpl` Includes all dependencies, even those that require full GPL instead of just LGPL.
* `gpl-shared` Same as gpl, but comes with the `libav*` family of shared libs instead of pure static executables.

All of those can be optionally combined with any combination of addins.

Available addins:
* `debug` to not strip debug symbols from the binaries. This increases the output size by about 250MB.
