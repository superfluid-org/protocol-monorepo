#!/usr/bin/env bash
set -eu

# Usage:
# tasks/deploy-gda-forwarder.sh <network>
#
# The invoking account needs to be (co-)owner of the resolver and governance
#
# important ENV vars:
# RELEASE_VERSION, GDAFWD_DEPLOYER_PK
# VERIFIERS: optional truffle-plugin-verify list (e.g. sourcify). Unset keeps the plugin default.
# SKIP_VERIFY: set to skip verification (e.g. SKIP_VERIFY=1)
#
# You can use the npm package vanity-eth to get a deployer account for a given contract address:
# Example use: npx vanityeth -i 6da1 --contract
#
# For optimism the gas estimation doesn't work, requires setting EST_TX_COST
# (the value auto-detected for arbitrum should work).
#
# On some networks you may need to use override ENV vars for the deployment to succeed

# shellcheck source=/dev/null
source .env

set -x

network=$1
expectedContractAddr="0x6DA13Bde224A05a288748d857b9e7DDEffd1dE08"
deployerPk=$GDAFWD_DEPLOYER_PK

tmpfile="/tmp/deploy-gda-forwarder.sh"
# deploy
DETERMINISTIC_DEPLOYER_PK=$deployerPk npx truffle exec --network "$network" ops-scripts/deploy-deterministically.js : GDAv1Forwarder | tee $tmpfile
contractAddr=$(cat $tmpfile | tail -n 1)
rm $tmpfile

echo "deployed to $contractAddr"
if [[ $contractAddr != "$expectedContractAddr" ]]; then
    echo "oh no!"
    exit
fi

# set resolver
ALLOW_UPDATE=1 npx truffle exec --network "$network" ops-scripts/resolver-set-key-value.js : GDAv1Forwarder "$contractAddr"

# create gov action
npx truffle exec --network "$network" ops-scripts/gov-set-trusted-forwarder.js : 0x0000000000000000000000000000000000000000 "$contractAddr" 1

# TODO: on mainnets, the resolver entry should be set only after the gov action was signed & executed

# verify last: a verifier failure must not skip resolver or governance
if [[ -n "${SKIP_VERIFY:-}" ]]; then
    echo "skipping verification (SKIP_VERIFY)"
else
    sleep 5
    set +e
    npx truffle run --network "$network" ${VERIFIERS:+--verifiers=$VERIFIERS} verify GDAv1Forwarder@"$contractAddr"
    set -e
fi
