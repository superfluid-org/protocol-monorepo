#!/usr/bin/env bash
set -eu
set -o pipefail

# Full ClearMacro rollout: deploy → verify → activate → confirm execution → register → grant provider role.
#
# Usage:
#   new-ops-scripts/deploy-clearmacro-forwarder.sh <network>
#
# Steps (each skippable):
#   1 deploy-deterministic-forwarder     SKIP_DEPLOY=1
#   2 verify-forwarder                   SKIP_VERIFY=1
#   3 activate-forwarder                 SKIP_ACTIVATE=1
#   4 register-forwarder (after execution) SKIP_REGISTER=1
#   5 grant-macro-provider-role          SKIP_GRANT_PROVIDER=1 (or omit CLEARMACRO_PROVIDER_GRANTEE)
#
# Env (loaded from packages/ethereum-contracts/.env and packages/.env):
#   CLEARMACROFWD_DEPLOYER_PK
#   EXPECTED_ADDRESS (default 0x712Fc5863F53AFBa980207006cfd74F6c25fE055)
#   CLEARMACRO_PROVIDER_GRANTEE — OZ relayer signer (relay executor, not the forwarder)
#   CLEARMACRO_PROVIDER_NAME    — default macros.superfluid.eth
#   WALLET_NAME                 — Foundry keystore (resolver, gov, SimpleACL grant)
#   KEYSTORE_PASSWORD           — Foundry keystore password in .env (empty string is valid)
#   KEYSTORE_PASSWORD_FILE      — or path to password file
#   MACRO_PROVIDER_ADMIN_WALLET — optional override for grant step only
#   ETHERSCAN_API_V2_KEY, SIMULATE=1
#
# Mainnet recovery (a Safe proposal is not execution):
#   SKIP_REGISTER=1 ./deploy-clearmacro-forwarder.sh eth-mainnet
#   # … Safe signs AND executes activate …
#   ALLOW_UPDATE=1 FORWARDER_PHASE=register ./deploy-clearmacro-forwarder.sh eth-mainnet
# ALLOW_UPDATE=1 deliberately permits replacing an occupied resolver entry.
# FORWARDER_PHASE also accepts deploy, verify, activate, or all (default).

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/lib/rollout-forwarder.sh"

network="${1:?Usage: $0 <network>}"
deployer_pk="${CLEARMACROFWD_DEPLOYER_PK:-}"
expected="${EXPECTED_ADDRESS:-0x712Fc5863F53AFBa980207006cfd74F6c25fE055}"


rollout_forwarder \
    "$network" \
    "ClearMacroForwarderV1" \
    "ClearMacroForwarderV1" \
    "$expected" \
    "$deployer_pk"
