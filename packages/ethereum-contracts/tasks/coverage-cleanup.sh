#!/usr/bin/env bash

set -ex

cd "$(dirname "$0")"/..

LCOV="lcov --ignore-errors inconsistent"

# extract coverage for Superfluid contracts from forge coverage
$LCOV -e lcov.info \
     "contracts/*" \
     -o lcov.info

# merge hardhat and forge coverage files
$LCOV -a lcov.info \
     -a coverage/lcov.info \
     -o coverage/lcov.info
