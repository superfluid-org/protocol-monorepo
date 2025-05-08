#!/usr/bin/env bash
# Synopsis: The wrapper of mk-cache-key.nix taking into accoutn git submodule dependencies.

oops() { echo "$@" >&2; exit 1; }

cd "$(dirname "$0")"/.. || oops "cd failed"

modulePath=$(readlink -f "$1")
[ -d "$modulePath" ] || oops "invalid module: ${modulePath}"

# create additional build context
{
    # include git submodule status
    git submodule status
} > additional-build-context.ignored

mk-cache-key.nix "$PWD" "$modulePath" ./additional-build-context.ignored --json
