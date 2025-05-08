#!/usr/bin/env bash
# Synopsis: Create packages build set based on the files change set.
# Usage: create-build-set.sh SOURCE_REF BASE_REF [BASE_ORIGIN]
# Notes:
#   - The files change set is derived from the `git diff` between SOURCE_REF and BASE_REF.
#   - Optionally, it fetches BASE_REF first BASE_ORIGIN first before `git diff`.
#   - The packages build set is output to GITHUB_ENV or /dev/stdout in a form of "BUILD_*" environment variables.

console.debug() {
    echo "debug:" "$@" > /dev/stderr
}

set -e

SOURCE_REF=$1
BASE_REF=$2
BASE_ORIGIN=$3

console.debug "SOURCE_REF: $SOURCE_REF"
console.debug "BASE_REF: $BASE_REF"

# fetch the latest commit of the BASE_REF from BASE_ORIGIN
if [ -n "${BASE_ORIGIN}" ]; then
    git fetch "${BASE_ORIGIN}" --depth=1 refs/heads/"${BASE_REF}":refs/remotes/"${BASE_ORIGIN}"/"${BASE_REF}"
fi

# compare the source branch with the dev branch
CHANGED_FILES=changed-files.ignore.list
git diff --name-only "${SOURCE_REF}" refs/remotes/origin/"${BASE_REF}" > "$CHANGED_FILES"
console.debug "=== BEGIN CHANGED FILES"
cat "$CHANGED_FILES" > /dev/stderr
console.debug "=== END CHANGED FILES"

console.debug "=== BEGIN CREATE BUILD SET"

function setBuildAll() {
    BUILD_ETHEREUM_CONTRACTS=1
    BUILD_HOT_FUZZ=1
    BUILD_SDK_CORE=1
    BUILD_SDK_REDUX=1
    BUILD_SPEC_HASKELL=1
    BUILD_SUBGRAPH=1
    BUILD_AUTOMATION_CONTRACTS=1
    BUILD_SOLIDITY_SEMANTIC_MONEY=1
    console.debug "Everything will be tested."
}

# if ci workflows changed
if grep -E "^.github/workflows/ci\..*\.yml$" "$CHANGED_FILES" > /dev/null; then
    console.debug "CI workflows changed."
    setBuildAll
fi

# if call (reusable) workflows changed
if grep -E "^.github/workflows/call\..*\.yml$" "$CHANGED_FILES" > /dev/null; then
    console.debug "Call workflows changed."
    setBuildAll
fi

# if root package.json changed, rebuild everything
if grep -E "^(flake\.nix|flake\.lock|package\.json|yarn\.lock)$" "$CHANGED_FILES" > /dev/null; then
    console.debug "Root package.json changed."
    setBuildAll
fi

# if specified haskell folders and files changed
if grep -E "^packages/spec-haskell/" "$CHANGED_FILES" > /dev/null; then
    BUILD_SPEC_HASKELL=1
    console.debug SPEC-HASKELL will be tested.
fi

# if specified solidity-semantic-money folders and files changed
if grep -E "^packages/solidity-semantic-money/" "$CHANGED_FILES" > /dev/null; then
    BUILD_SOLIDITY_SEMANTIC_MONEY=1
    BUILD_ETHEREUM_CONTRACTS=1
    console.debug Solidity semantic money will be tested.
fi

# if specified ethereum-contracts folders and files changed
if grep -E "^packages/ethereum-contracts/" "$CHANGED_FILES" > /dev/null; then
    BUILD_ETHEREUM_CONTRACTS=1
    BUILD_SUBGRAPH=1
    BUILD_HOT_FUZZ=1
    BUILD_AUTOMATION_CONTRACTS=1
    console.debug Ethereum contracts, HotFuzz and Subgraph will be tested.
fi

# if specified sdk-core folders and files changed
if grep -E "^packages/sdk-core/" "$CHANGED_FILES" > /dev/null; then
    BUILD_SDK_CORE=1
    BUILD_SDK_REDUX=1
    BUILD_SUBGRAPH=1
    console.debug SDK-CORE, SDK-REDUX and SUBGRAPH will be tested.
fi

# if specified sdk-redux folders and files changed
if grep -E "^packages/sdk-redux/" "$CHANGED_FILES" > /dev/null; then
    BUILD_SDK_REDUX=1
    console.debug SDK-REDUX will be tested.
fi

# if specified hot-fuzz folders and files changed
if grep -E "^packages/hot-fuzz/" "$CHANGED_FILES" > /dev/null; then
    BUILD_HOT_FUZZ=1
    console.debug HotFuzz will be tested.
fi

# if specified subgraph folders and files changed
if grep -E "^packages/subgraph/" "$CHANGED_FILES" > /dev/null; then
    BUILD_SUBGRAPH=1
    console.debug Subgraph will be tested.
fi

# if specified automation-contracts/scheduler folders and files changed
if grep -E "^packages/automation-contracts/" "$CHANGED_FILES" > /dev/null; then
    BUILD_AUTOMATION_CONTRACTS=1
    console.debug Automation Contracts will be tested.
fi

if [ "$BUILD_ETHEREUM_CONTRACTS" == 1 ] || [ "$BUILD_SDK_CORE" == 1 ] || [ "$BUILD_SDK_REDUX" == 1 ]; then
    PUBLISH_PR_ARTIFACT=1
    console.debug "PR packages will be published."
fi

console.debug "=== END CREATE BUILD SET"

# print BUILD_* variables to $GITHUB_ENV, for local debugging GITHUB_ENV is default to /dev/stdout
{
    echo "BUILD_ETHEREUM_CONTRACTS=${BUILD_ETHEREUM_CONTRACTS}"
    echo "BUILD_HOT_FUZZ=${BUILD_HOT_FUZZ}"
    echo "BUILD_SDK_CORE=${BUILD_SDK_CORE}"
    echo "BUILD_SDK_REDUX=${BUILD_SDK_REDUX}"
    echo "BUILD_SUBGRAPH=${BUILD_SUBGRAPH}"
    echo "BUILD_SPEC_HASKELL=${BUILD_SPEC_HASKELL}"
    echo "BUILD_AUTOMATION_CONTRACTS=${BUILD_AUTOMATION_CONTRACTS}"
    echo "BUILD_SOLIDITY_SEMANTIC_MONEY=${BUILD_SOLIDITY_SEMANTIC_MONEY}"
    echo "PUBLISH_PR_ARTIFACT=${PUBLISH_PR_ARTIFACT}"
} >> "${GITHUB_ENV:-/dev/stdout}"
