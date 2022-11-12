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
    [[ $TARGET == win* ]] && echo --enable-schannel
}

ffbuild_unconfigure() {
    [[ $TARGET == win* ]] && echo --disable-schannel
}
