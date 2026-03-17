#!/usr/bin/env bash
set -eu
set -o pipefail

# Usage:
# tasks/deploy-permit2-clearmacro-forwarder.sh <network>
#
# The invoking account needs to be (co-)owner of the resolver and governance
#
# important ENV vars:
# RELEASE_VERSION, PERMIT2CLEARMACROFWD_DEPLOYER_PK
# Fallback for backwards compatibility: PERMIT2MACROFWD_DEPLOYER_PK
# EXPECTED_ADDRESS: set after generating deployer with vanity-eth
#   (e.g. npx vanityeth -i 2712 --contract), or set SKIP_ADDRESS_CHECK=1 to skip.
#
# You can use the npm package vanity-eth to get a deployer account for a given contract address:
# Example use: npx vanityeth -i 2712 --contract
#
# For optimism the gas estimation doesn't work, requires setting EST_TX_COST
# (the value auto-detected for arbitrum should work).
#
# On some networks you may need to use override ENV vars for the deployment to succeed

# shellcheck source=/dev/null
source .env

set -x

network=$1
expectedContractAddr=${EXPECTED_ADDRESS:-"0x712F1ccD0472025EC75bB67A92AA6406cDA0031D"}

deployerPk=${PERMIT2CLEARMACROFWD_DEPLOYER_PK:-${PERMIT2MACROFWD_DEPLOYER_PK:-}}

skipDeploy=${SKIP_DEPLOY:-0}

tmpfile="/tmp/$(basename "$0").addr"

# deploy
if [ "$skipDeploy" -eq 0 ]; then
    DETERMINISTIC_DEPLOYER_PK=$deployerPk npx truffle exec --network "$network" ops-scripts/deploy-deterministically.js : Permit2ClearMacroForwarder | tee "$tmpfile"
    contractAddr=$(tail -n 1 "$tmpfile")
    rm "$tmpfile"
else
    contractAddr=$expectedContractAddr
fi

echo "deployed to $contractAddr"
if [[ -n "$expectedContractAddr" && $contractAddr != "$expectedContractAddr" ]]; then
    echo "contract address not as expected!"
    if [ -z "$SKIP_ADDRESS_CHECK" ]; then
        exit
    fi
fi

# verify (give it a few seconds to pick up the code)
sleep 5
# allow to fail
set +e
npx truffle run --network "$network" verify Permit2ClearMacroForwarder@"$contractAddr"
set -e

# set resolver
ALLOW_UPDATE=1 npx truffle exec --network "$network" ops-scripts/resolver-set-key-value.js : Permit2ClearMacroForwarder "$contractAddr"

# create gov action
npx truffle exec --network "$network" ops-scripts/gov-set-trusted-forwarder.js : 0x0000000000000000000000000000000000000000 "$contractAddr" 1

# TODO: on mainnets, the resolver entry should be set only after the gov action was signed & executed
