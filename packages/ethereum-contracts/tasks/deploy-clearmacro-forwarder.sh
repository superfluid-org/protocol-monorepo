#!/usr/bin/env bash
set -eu
set -o pipefail

# Usage:
# tasks/deploy-clearmacro-forwarder.sh <network>
#
# The invoking account needs to be (co-)owner of the resolver and governance
#
# important ENV vars:
# RELEASE_VERSION, CLEARMACROFWD_DEPLOYER_PK
# Fallback for backwards compatibility: ONLY712MACROFWD_DEPLOYER_PK
# EXPECTED_ADDRESS: set after generating deployer with vanity-eth
#   (e.g. npx vanityeth -i 712f --contract), or set SKIP_ADDRESS_CHECK=1 to skip.
#
# For ENS forward resolution (e.g. macros.sftest.eth):
# set ENS_NAME and make sure the default ENS-L1 truffle signer owns the domain
# (or its parent, e.g. sftest.eth). ENS network defaults to eth-sepolia for
# testnet deployments and eth-mainnet otherwise. Override with ENS_NETWORK.
#
# You can use the npm package vanity-eth to get a deployer account for a given contract address:
# Example use: npx vanityeth -i 712f --contract
#
# For optimism the gas estimation doesn't work, requires setting EST_TX_COST
# (the value auto-detected for arbitrum should work).
#
# On some networks you may need to use override ENV vars for the deployment to succeed

# shellcheck source=/dev/null
source .env

set -x

network=$1
expectedContractAddr=${EXPECTED_ADDRESS:-"0x712Fc5863F53AFBa980207006cfd74F6c25fE055"}
deployerPk=${CLEARMACROFWD_DEPLOYER_PK:-${ONLY712MACROFWD_DEPLOYER_PK:-}}

tmpfile="/tmp/$(basename "$0").addr"

# deploy
DETERMINISTIC_DEPLOYER_PK=$deployerPk npx truffle exec --network "$network" ops-scripts/deploy-deterministically.js : ClearMacroForwarder | tee "$tmpfile"
contractAddr=$(tail -n 1 "$tmpfile")
rm "$tmpfile"

echo "deployed to $contractAddr"
if [[ -n "$expectedContractAddr" && $contractAddr != "$expectedContractAddr" ]]; then
    echo "contract address not as expected!"
    if [ -z "${SKIP_ADDRESS_CHECK:-}" ]; then
        exit
    fi
fi

# verify (give it a few seconds to pick up the code)
sleep 5
# allow to fail
set +e
npx truffle run --network "$network" verify ClearMacroForwarder@"$contractAddr"
set -e

# set resolver (skip for test deployments using SKIP_ADDRESS_CHECK)
if [[ -n "${SKIP_ADDRESS_CHECK:-}" ]]; then
    echo "WARNING: skipping resolver update because SKIP_ADDRESS_CHECK is set." >&2
else
    ALLOW_UPDATE=1 npx truffle exec --network "$network" ops-scripts/resolver-set-key-value.js : ClearMacroForwarder "$contractAddr"
fi

# create gov action
npx truffle exec --network "$network" ops-scripts/gov-set-trusted-forwarder.js : 0x0000000000000000000000000000000000000000 "$contractAddr" 1

# ensure ENS forward resolution on the corresponding ENS L1 using the default ops signer
if [[ -n "${ENS_NAME:-}" && -z "${SKIP_ENS_FORWARD_CHECK:-}" ]]; then
    ensNetwork=${ENS_NETWORK:-}
    if [[ -z "$ensNetwork" ]]; then
        case "$network" in
            *sepolia*)
                ensNetwork="eth-sepolia"
                ;;
            *)
                ensNetwork="eth-mainnet"
                ;;
        esac
    fi

    set +e
    node ops-scripts/libs/ens.js "$ensNetwork" "$ENS_NAME" "$contractAddr"
    ensExitCode=$?
    set -e

    if [ "$ensExitCode" -ne 0 ]; then
        echo "WARNING: ENS forward sync failed; deployment itself succeeded." >&2
        echo "Re-run: node ops-scripts/libs/ens.js \"$ensNetwork\" \"$ENS_NAME\" \"$contractAddr\"" >&2
    fi
fi

# TODO: on mainnets, the resolver entry should be set only after the gov action was signed & executed
