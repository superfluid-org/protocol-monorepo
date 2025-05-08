#!/usr/bin/env sh

{
    echo -n "$(git rev-parse --short HEAD)"
    [ -n "$(git status --porcelain)" ] && echo -n " (dirty)"
} | {
    if [ "$1" == forge_ffi_mode ]; then
        xxd -p
    else
        cat
    fi
}
