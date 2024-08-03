#!/bin/bash

SCRIPT_SKIP="1"

ffbuild_enabled() {
    [[ $TARGET == win* ]]
}

ffbuild_dockerstage() {
    return 0
}

ffbuild_dockerbuild() {
    return 0
}

ffbuild_configure() {
    [[ $TARGET == win* ]] && echo --enable-dxva2 --enable-d3d11va --enable-d3d12va
}

ffbuild_unconfigure() {
    [[ $TARGET == win* ]] && echo --disable-dxva2 --disable-d3d11va --disable-d3d12va
}
