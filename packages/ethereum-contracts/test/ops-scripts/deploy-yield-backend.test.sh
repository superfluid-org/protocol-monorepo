#!/usr/bin/env bash
# Integration test for ops-scripts/deploy-yield-backend.sh.
# Runs the script in simulate mode (no broadcast) against base-mainnet.
#
# Usage: from packages/ethereum-contracts, run: bash test/ops-scripts/deploy-yield-backend.test.sh
# Requires: RPC for Base (RPC_URL, PROVIDER_URL_OVERRIDE, metadata fallback, or BASE_MAINNET_ARCHIVE_RPC_URL).

set -eu
set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PKG_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
DEPLOY_SCRIPT="$PKG_ROOT/ops-scripts/deploy-yield-backend.sh"

# Base mainnet addresses (same as AaveYieldBackendIntegration.t.sol)
USDC=0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913
AAVE_POOL=0xA238Dd80C259a72e81d7e4664a9801593F98d1c5
SURPLUS_RECEIVER=0xac808840f02c47C05507f48165d2222FF28EF4e1

cd "$PKG_ROOT"

# Use BASE_MAINNET_ARCHIVE_RPC_URL if set (matches integration test), else let script use its RPC resolution
export RPC_URL="${RPC_URL:-${BASE_MAINNET_ARCHIVE_RPC_URL:-}}"
export SIMULATE=1

output=$(mktemp)
trap 'rm -f "$output"' EXIT

NATIVE_UNDERLYING=0x0000000000000000000000000000000000000000

if ! "$DEPLOY_SCRIPT" base-mainnet aave "$USDC" "$AAVE_POOL" "$SURPLUS_RECEIVER" 2>&1 | tee "$output"; then
    echo "deploy-yield-backend.sh failed (exit $?)" >&2
    exit 1
fi

if ! grep -q "Deployed AaveYieldBackend at:" "$output"; then
    echo "Expected output to contain 'Deployed AaveYieldBackend at:'" >&2
    exit 1
fi

if ! "$DEPLOY_SCRIPT" base-mainnet aave "$NATIVE_UNDERLYING" "$AAVE_POOL" "$SURPLUS_RECEIVER" 2>&1 | tee "$output"; then
    echo "deploy-yield-backend.sh (native underlying) failed (exit $?)" >&2
    exit 1
fi

if ! grep -q "Deployed AaveETHYieldBackend at:" "$output"; then
    echo "Expected output to contain 'Deployed AaveETHYieldBackend at:'" >&2
    exit 1
fi

echo "deploy-yield-backend.test.sh: OK"
