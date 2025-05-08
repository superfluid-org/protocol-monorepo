#!/usr/bin/env bash

set -ex

cd "$(dirname "$0")"/..

LCOV="lcov --ignore-errors inconsistent"

# extract coverage for Superfluid contracts from forge coverage
$LCOV -e ../../lcov.info \
     "packages/ethereum-contracts/contracts/*" \
     -o lcov.info

# remove contracts whose coverage we don't care about (see .solcover.js)
$LCOV -r lcov.info \
     "packages/ethereum-contracts/contracts/mocks/*" \
     "packages/ethereum-contracts/contracts/apps/*Base*" \
     "packages/ethereum-contracts/contracts/utils/*Test*" \
     "packages/ethereum-contracts/contracts/utils/*Deploy*" \
     "packages/ethereum-contracts/contracts/apps/SuperfluidLoaderLibrary.sol" \
     -o lcov.info

# merge hardhat and forge coverage files
$LCOV -a lcov.info \
     -a coverage/lcov.info \
     -o coverage/lcov.info
