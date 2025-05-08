#!/usr/bin/env bash
set -eu

# Usage:
# tasks/deploy-cfa-forwarder.sh <network>
#
# The invoking account needs to be (co-)owner of the resolver and governance
#
# important ENV vars:
# RELEASE_VERSION, CFAFWD_DEPLOYER_PK
#
# You can use the npm package vanity-eth to get a deployer account for a given contract address:
# Example use: npx vanityeth -i cfa1 --contract
#
# For optimism the gas estimation doesn't work, requires setting EST_TX_COST
# (the value auto-detected for arbitrum should work).
#
# On some networks you may need to use override ENV vars for the deployment to succeed

# shellcheck source=/dev/null
source .env

set -x

network=$1
expectedContractAddr="0xcfA132E353cB4E398080B9700609bb008eceB125"
deployerPk=$CFAFWD_DEPLOYER_PK

tmpfile="/tmp/deploy-cfa-forwarder.sh"
# deploy
DETERMINISTIC_DEPLOYER_PK=$deployerPk npx truffle exec --network "$network" ops-scripts/deploy-deterministically.js : CFAv1Forwarder | tee $tmpfile
contractAddr=$(cat $tmpfile | tail -n 1)
rm $tmpfile

echo "deployed to $contractAddr"
if [[ $contractAddr != "$expectedContractAddr" ]]; then
    echo "oh no!"
    exit
fi

# verify (give it a few seconds to pick up the code)
sleep 5
npx truffle run --network "$network" verify CFAv1Forwarder@"$contractAddr"

# set resolver
ALLOW_UPDATE=1 npx truffle exec --network "$network" ops-scripts/resolver-set-key-value.js : CFAv1Forwarder "$contractAddr"

# create gov action
npx truffle exec --network "$network" ops-scripts/gov-set-trusted-forwarder.js : 0x0000000000000000000000000000000000000000 "$contractAddr" 1

# TODO: on mainnets, the resolver entry should be set only after the gov action was signed & executed
