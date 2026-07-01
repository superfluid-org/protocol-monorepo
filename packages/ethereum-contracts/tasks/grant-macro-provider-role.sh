#!/usr/bin/env bash
set -eu
set -o pipefail

# Usage:
#   tasks/grant-macro-provider-role.sh <network> <grantee-address> [provider]
#
# Grants the macro provider role in SimpleACL. The role is keccak256(provider);
# default provider is "macros.superfluid.eth".
#
# Network: canonical name from metadata (e.g. optimism-sepolia, eth-sepolia).
# Grantee: address to grant the role (must be valid for the forwarder / macro runner).
#
# The caller must have DEFAULT_ADMIN_ROLE on SimpleACL (e.g. governance).
# Use your usual signer: private key (PRIVATE_KEY / --private-key), foundry wallet
# (--account), or other forge-supported options.
#
# Requires: jq, forge. Run from packages/ethereum-contracts (or repo root; script will cd).

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PKG_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
METADATA_JSON="$PKG_ROOT/../metadata/networks.json"

network="${1:?Usage: $0 <network> <grantee-address> [provider]}"
grantee="${2:?Usage: $0 <network> <grantee-address> [provider]}"
provider="${3:-macros.superfluid.eth}"
account="${FOUNDRY_ACCOUNT:-gh-agent}"

if [[ ! -f "$METADATA_JSON" ]]; then
    echo "Metadata not found: $METADATA_JSON" >&2
    exit 1
fi

host=$(jq -r '.[] | select(.name == "'"$network"'") | .contractsV1.host' "$METADATA_JSON")
rpc=$(jq -r '.[] | select(.name == "'"$network"'") | .publicRPCs[0]' "$METADATA_JSON")

if [[ -z "$host" || "$host" == "null" ]]; then
    echo "Unknown network: $network (no host in metadata)" >&2
    exit 1
fi
if [[ -z "$rpc" || "$rpc" == "null" ]]; then
    echo "No public RPC for network: $network" >&2
    exit 1
fi

echo "Network:  $network"
echo "Host:     $host"
echo "Grantee:  $grantee"
echo "Provider: $provider"
echo "RPC:      $rpc"
echo ""

cd "$PKG_ROOT"
forge script scripts/GrantMacroProviderRole.s.sol \
    --sig "run(address,address,string)" "$host" "$grantee" "$provider" \
    --rpc-url "$rpc" \
    --account "$account" \
    --broadcast
