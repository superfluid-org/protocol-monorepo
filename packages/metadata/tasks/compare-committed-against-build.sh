#!/usr/bin/env bash
# This script checks that the built files are consistent with the committed files.

set -xe

cd "$(dirname "$0")"/..

# Hash a file using sha256sum and cut the hash from the output
function hashFiles() {
    sha256sum "$1" | cut -d ' ' -f 1
}

# first of all, ensure that we have valid json
jq empty networks.json

# Hash the committed files
main_list_committed_hash=$(hashFiles ./main/networks/list.cjs)
module_list_committed_hash=$(hashFiles ./module/networks/list.js)

# Build the files
./build.sh

# Hash the built files
main_list_built_hash=$(hashFiles './main/networks/list.cjs')
module_list_built_hash=$(hashFiles './module/networks/list.js')

# Compare the hashes and exit if they are not equal
if [ "$main_list_committed_hash" != "$main_list_built_hash" ] || [ "$module_list_committed_hash" != "$module_list_built_hash" ]; then
    echo "The built files were not consistent with the committed files."
    echo "I just ran ./build.sh for you. You need to include those changes in the commit."
    exit 1
fi
