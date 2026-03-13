#!/usr/bin/env bash
set -eu
set -o pipefail

# Usage:
#   ops-scripts/deploy-yield-backend.sh <network> aave <assetToken> <aavePool> <surplusReceiver>
#   ops-scripts/deploy-yield-backend.sh <network> spark <vault> <surplusReceiver> <referralId>
#
# Deploys a yield backend contract. Network is the canonical name from metadata (e.g. base-mainnet, eth-mainnet).
#
# Examples:
#   # AaveYieldBackend for USDC on Base
#   ops-scripts/deploy-yield-backend.sh base-mainnet aave 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913 0xA238Dd80C259a72e81d7e4664a9801593F98d1c5 0xac808840f02c47C05507f48165d2222FF28EF4e1
#
#   # SparkYieldBackend for USDC on Ethereum
#   ops-scripts/deploy-yield-backend.sh eth-mainnet spark 0xBc65ad17c5C0a2A4D159fa5a503f4992c7B545FE 0xac808840f02c47C05507f48165d2222FF28EF4e1 42
#
# ENV: RPC_URL, PROVIDER_URL_OVERRIDE, or PROVIDER_URL_TEMPLATE (with {{NETWORK}}) for RPC; metadata publicRPCs as fallback.
#      WALLET_NAME (default: sf-ops), ETHERSCAN_API_V2_KEY for verification.
#      SIMULATE=1 to run without --broadcast (simulate only, no on-chain tx).
#
# Requires: jq, forge. Run from packages/ethereum-contracts or repo root.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PKG_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
METADATA_JSON="${METADATA_JSON:-$PKG_ROOT/../metadata/networks.json}"

# shellcheck source=/dev/null
[[ -f "$PKG_ROOT/.env" ]] && source "$PKG_ROOT/.env"
# shellcheck source=/dev/null
[[ -f "$PKG_ROOT/../.env" ]] && source "$PKG_ROOT/../.env"
# shellcheck source=/dev/null
[[ -f "$SCRIPT_DIR/lib/network-config.sh" ]] && source "$SCRIPT_DIR/lib/network-config.sh"

network="${1:?Usage: $0 <network> aave|spark <args...>}"
backend_type="${2:?Usage: $0 <network> aave|spark <args...>}"

if [[ ! -f "$METADATA_JSON" ]]; then
    echo "Metadata not found: $METADATA_JSON" >&2
    exit 1
fi

rpc=$(get_rpc_url "$network") || exit 1
chain_id=$(get_chain_id "$network")
if [[ -z "$chain_id" || "$chain_id" == "null" ]]; then
    echo "No chainId for network: $network" >&2
    exit 1
fi

cd "$PKG_ROOT"

tmpfile=$(mktemp)
trap 'rm -f "$tmpfile"' EXIT

forge_args=(--rpc-url "$rpc")
if [[ -n "${SIMULATE:-}" ]]; then
    # Simulation: use well-known test key to avoid keystore access
    forge_args+=(--private-key 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80)
else
    forge_args+=(--account "${WALLET_NAME:-sf-ops}" --broadcast)
fi

if [[ -z "${SIMULATE:-}" && -n "${ETHERSCAN_API_V2_KEY:-}" ]]; then
    echo "Verification: enabled"
    forge_args+=(
        --verify
        --verifier etherscan
        --etherscan-api-key "$ETHERSCAN_API_V2_KEY"
        --chain-id "$chain_id"
        --delay 10
        --retries 15
    )
else
    echo "Verification: skipped (ETHERSCAN_API_V2_KEY not set)"
fi

case "$backend_type" in
    aave)
        asset_token="${3:?Usage: $0 <network> aave <assetToken> <aavePool> <surplusReceiver>}"
        aave_pool="${4:?Usage: $0 <network> aave <assetToken> <aavePool> <surplusReceiver>}"
        surplus_receiver="${5:?Usage: $0 <network> aave <assetToken> <aavePool> <surplusReceiver>}"
        echo "Network:  $network"
        echo "Backend:  AaveYieldBackend"
        echo "RPC:      $rpc"
        echo ""
        forge script scripts/DeployYieldBackend.s.sol:DeployYieldBackend \
            "${forge_args[@]}" \
            --sig "runAave(address,address,address)" "$asset_token" "$aave_pool" "$surplus_receiver" | tee "$tmpfile"
        contract_addr=$(grep -oE '0x[a-fA-F0-9]{40}' "$tmpfile" | tail -n 1)
        ;;
    spark)
        vault="${3:?Usage: $0 <network> spark <vault> <surplusReceiver> <referralId>}"
        surplus_receiver="${4:?Usage: $0 <network> spark <vault> <surplusReceiver> <referralId>}"
        referral_id="${5:?Usage: $0 <network> spark <vault> <surplusReceiver> <referralId>}"
        echo "Network:  $network"
        echo "Backend:  SparkYieldBackend"
        echo "RPC:      $rpc"
        echo ""
        forge script scripts/DeployYieldBackend.s.sol:DeployYieldBackend \
            "${forge_args[@]}" \
            --sig "runSpark(address,address,uint16)" "$vault" "$surplus_receiver" "$referral_id" | tee "$tmpfile"
        contract_addr=$(grep -oE '0x[a-fA-F0-9]{40}' "$tmpfile" | tail -n 1)
        ;;
    *)
        echo "Unknown backend type: $backend_type (use aave or spark)" >&2
        exit 1
        ;;
esac

if [[ -z "${contract_addr:-}" ]]; then
    echo "Could not determine deployed contract address from forge output" >&2
    exit 1
fi

echo ""
echo "Deployed to $contract_addr"
