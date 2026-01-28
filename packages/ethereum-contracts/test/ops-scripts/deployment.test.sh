#!/usr/bin/env bash

export TESTENV_SNAPSHOT_VARS=$PWD/test.ignore.vars
VITALIK_ADDRESS=0xd8dA6BF26964aF9D7eEd9e03E53415D37aA96045

# Exit script as soon as a command fails.
set -o errexit

# Executes cleanup function at script exit.
trap cleanup EXIT

cleanup() {
    rm -f $TESTENV_SNAPSHOT_VARS
    yarn testenv:stop
}
yarn testenv:start >/dev/null &

# wait for the test environment to boot
sleep 5

#
# Test the scripts
#

# unset potential interfering environment varibles
unset RESOLVER_ADDRESS
unset CREATE_NEW_RESOLVER
unset RESET_SUPERFLUID_FRAMEWORK
unset RELEASE_VERSION
unset USE_MOCKS
unset NON_UPGRADABLE
unset ENABLE_APP_WHITELISTING

# if any of them fail, exit
set -xe

npx truffle exec ops-scripts/deploy-test-environment.js

# deployment result is stored in TESTENV_SNAPSHOT_VARS
cat $TESTENV_SNAPSHOT_VARS

# Use the newly created resolver
source $TESTENV_SNAPSHOT_VARS
export RESOLVER_ADDRESS=$RESOLVER_ADDRESS

# Test all info scripts
npx truffle exec ops-scripts/info-scan-deployments.js
npx truffle exec ops-scripts/info-show-protocol.js
npx truffle exec ops-scripts/info-print-contract-addresses.js : >(cat)
npx truffle exec ops-scripts/info-inspect-account.js : $VITALIK_ADDRESS
npx truffle exec ops-scripts/info-list-apps.js

npx truffle exec ops-scripts/gov-transfer-framework-ownership.js : $VITALIK_ADDRESS
