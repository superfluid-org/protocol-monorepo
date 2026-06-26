#!/usr/bin/env sh

set -e

# Need to be git root directory (in sync with foundry.toml)
cd "$(dirname "$0")/../../.." || exit 1

slither packages/ethereum-contracts \
        --compile-force-framework foundry \
        --foundry-out-directory build/foundry/default \
        --filter-paths "(test|mocks|node_modules)"
