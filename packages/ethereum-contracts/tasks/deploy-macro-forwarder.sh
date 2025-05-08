#!/usr/bin/env bash
set -eu
set -o pipefail

# Usage:
# tasks/deploy-macro-forwarder.sh <network>
#
# The invoking account needs to be (co-)owner of the resolver and governance
#
# important ENV vars:
# RELEASE_VERSION, MACROFWD_DEPLOYER_PK
#
# You can use the npm package vanity-eth to get a deployer account for a given contract address:
# Example use: npx vanityeth -i fd01 --contract
#
# For optimism the gas estimation doesn't work, requires setting EST_TX_COST
# (the value auto-detected for arbitrum should work).
#
# On some networks you may need to use override ENV vars for the deployment to succeed

# shellcheck source=/dev/null
source .env

set -x

network=$1
expectedContractAddr="0xFD0268E33111565dE546af2675351A4b1587F89F"
deployerPk=$MACROFWD_DEPLOYER_PK

tmpfile="/tmp/$(basename "$0").addr"

# deploy
DETERMINISTIC_DEPLOYER_PK=$deployerPk npx truffle exec --network "$network" ops-scripts/deploy-deterministically.js : MacroForwarder | tee "$tmpfile"
contractAddr=$(tail -n 1 "$tmpfile")
rm "$tmpfile"

echo "deployed to $contractAddr"
if [[ $contractAddr != "$expectedContractAddr" ]]; then
    echo "contract address not as expected!"
    if [ -z "$SKIP_ADDRESS_CHECK" ]; then
        exit
    fi
fi

# verify (give it a few seconds to pick up the code)
sleep 5
# allow to fail
set +e
npx truffle run --network "$network" verify MacroForwarder@"$contractAddr"
set -e

# set resolver
ALLOW_UPDATE=1 npx truffle exec --network "$network" ops-scripts/resolver-set-key-value.js : MacroForwarder "$contractAddr"

# create gov action
npx truffle exec --network "$network" ops-scripts/gov-set-trusted-forwarder.js : 0x0000000000000000000000000000000000000000 "$contractAddr" 1

# TODO: on mainnets, the resolver entry should be set only after the gov action was signed & executed
