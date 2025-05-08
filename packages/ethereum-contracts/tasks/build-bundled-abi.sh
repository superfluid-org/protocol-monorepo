#!/usr/bin/env bash
# shellcheck disable=SC2207

set -e

cd "$(dirname "$0")/.." || exit 1

CONTRACTS=( $(jq -r .[] tasks/bundled-abi-contracts-list.json) ) || exit 2

{
    echo "if (typeof module === \"undefined\") module = {};"
    echo "// eslint-disable-next-line no-unused-vars"
    echo "let Superfluid_ABI;"
    echo "Superfluid_ABI = module.exports = {"

    # parallel processing of abi inputs
    echo "${CONTRACTS[@]}" | xargs -n1 -P4 bash -c "
        {
            echo -n \"    \$1: \"
            jq \".abi\" build/truffle/\"\$1\".json || exit 3
            echo ','
        } > build/bundled-abi.\$1.frag
        " --
    cat build/bundled-abi.*.frag
    rm build/bundled-abi.*.frag

    echo "};"

} > build/bundled-abi.js
node -e 'console.log(JSON.stringify(require("./build/bundled-abi")))' > build/bundled-abi.json

cp tasks/bundled-abi-contracts-list.json build/
