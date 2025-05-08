#!/usr/bin/env bash
# Synopsis: find duplicated devDependencies in packages

P=$(jq -r ".workspaces.packages | .[]" package.json | xargs printf "%s/package.json\n")
P="package.json $P"
echo "$P" | \
    xargs -- jq -r "if .devDependencies? then .devDependencies | keys | .[] else empty end" | \
    sort | uniq -c | \
    grep -ve '^ *1 ' | awk '{print $2}' | while read -r i; do
        echo "$i"
        echo "$P" | xargs -- grep "\"$i\""
        echo
    done
