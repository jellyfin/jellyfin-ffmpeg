# jellyfin-ffmpeg portable versions builder for mac

Portable versions builder of jellyfin-ffmpeg for macOS.

This script is generally made for GitHub Actions' CI runner, and there will be some caveats when running it locally.

A significant limitation is that this script will mutate files in a way that prevents the script from being executed multiple times on a non-clean environment. Follow the instructions below to work with it.

## Package List

For a list of included dependencies check the `scripts.d` directory.
Every file corresponds to its respective package.

For macOS, there will be additionally packages located in `images/macos` as extra static libs. The `00-dep.sh` will also setup necessary environment on a GitHub Runner. You can modify or remove it if you find it unnecessary.

## How to make a build

### Prerequisites

* **[Homebrew](https://brew.sh)**: Make sure Homebrew is installed and set up on your system.
* **[Xcode](https://developer.apple.com/xcode/)**: Ensure that Xcode is installed and properly configured. It's essential to have the full Xcode installation as simply installing the command line toolchain won't include the Metal SDK required for ffmpeg.
  - **Verification**: To verify that you have the Metal SDK ready, run the command `xcrun -sdk macosx metal -v`. This command should display version information about the installed Metal SDK. If you encounter an error message such as `xcrun: error: unable to find utility "metal", not a developer tool or in PATH`, it indicates that the incorrect toolchain is selected. In such cases, manually select the Xcode toolchain by running the following command:
  ```
  sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer
  ```

### Prepare Prefix Directory

You will need to prepare a directory to install all the libraries to. The default is `/opt/ffbuild/prefix`, which is defined in `buildmac.sh` as `FFBUILD_PREFIX`. You can either create this folder manually and give permission to the user who runs the builder, or you can modify that value to point it to another folder.

### Run Builder

Once you have your environment set up, you can simply run `buildmac.sh`, and it will download libraries and start building. This may take some time, so please be patient.

Generated artifacts will be stored to `artifacts` folder.

### Prepare for next running.

To run another clean build, the easiest way is to remove the `FFBUILD_PREFIX` folder, and then remove `jellyfin-ffmpeg` and re-clone the repo.

If you don't want to rebuild all the dependencies, you can keep the `FFBUILD_PREFIX` folder and remove/comment out the following lines:

```shell
mkdir build
for macbase in images/macos/*.sh; do
    cd "$BUILDER_ROOT"/build
    source "$BUILDER_ROOT"/"$macbase"
    ffbuild_macbase || exit $?
done

cd "$BUILDER_ROOT"
for lib in scripts.d/*.sh; do
    cd "$BUILDER_ROOT"/build
    source "$BUILDER_ROOT"/"$lib"
    ffbuild_enabled || continue
    ffbuild_dockerbuild || exit $?
done
```

At this point, the repository could have our patches applied. You want to restore it with `quilt pop -af` before the next run.

## Known issue

- If you are on an Intel Mac and have `libx11` installed with Homebrew, ffmpeg will link to Homebrew's `libx11`, making your generated binary non-portable. We work around this on GitHub's Runner by removing all installed packages that use `libx11`.
