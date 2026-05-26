#!/usr/bin/env bash
set -eu
set -o pipefail

# Full ClearMacroForwarderV1WithPermit2 rollout: deploy → verify → register → activate → grant provider role.
#
# Usage:
#   new-ops-scripts/deploy-clearmacro-forwarder-with-permit2.sh <network>
#
# Env (loaded from packages/ethereum-contracts/.env and packages/.env):
#   PERMIT2CLEARMACROFWD_DEPLOYER_PK — vanity deployer (nonce 0; npx vanityeth -i 2712 --contract)
#   EXPECTED_ADDRESS (default 0x712F1ccD0472025EC75bB67A92AA6406cDA0031D)
#   CLEARMACRO_PROVIDER_GRANTEE — OZ relayer signer (relay executor, not the forwarder)
#   CLEARMACRO_PROVIDER_NAME    — default macros.superfluid.eth
#   WALLET_NAME                 — Foundry keystore (resolver, gov, SimpleACL grant)
#   KEYSTORE_PASSWORD           — Foundry keystore password in .env (empty string is valid)
#   KEYSTORE_PASSWORD_FILE      — or path to password file
#   MACRO_PROVIDER_ADMIN_WALLET — optional override for grant step only
#   ETHERSCAN_API_V2_KEY, SCROLLSCAN_API_KEY (Scroll verify), SIMULATE=1
#   SKIP_DEPLOY, SKIP_VERIFY, SKIP_REGISTER, SKIP_ACTIVATE, SKIP_GRANT_PROVIDER
#
# Example:
#   cd packages/ethereum-contracts
#   # PERMIT2CLEARMACROFWD_DEPLOYER_PK in packages/ethereum-contracts/.env is loaded automatically
#   ./new-ops-scripts/deploy-clearmacro-forwarder-with-permit2.sh optimism-sepolia

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/lib/rollout-forwarder.sh"

network="${1:?Usage: $0 <network>}"
deployer_pk="${PERMIT2CLEARMACROFWD_DEPLOYER_PK:-}"
expected="${EXPECTED_ADDRESS:-0xC1EaB73855155D4e021f7EB4f866996Bac2fe25e}"

if [[ -z "$deployer_pk" && "${SKIP_DEPLOY:-0}" -ne 1 ]]; then
    echo "PERMIT2CLEARMACROFWD_DEPLOYER_PK is required (unless SKIP_DEPLOY=1)" >&2
    exit 1
fi

rollout_forwarder \
    "$network" \
    "ClearMacroForwarderV1WithPermit2" \
    "ClearMacroForwarderV1WithPermit2" \
    "$expected" \
    "$deployer_pk"
