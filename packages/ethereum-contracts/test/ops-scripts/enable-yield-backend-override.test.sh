#!/usr/bin/env bash
# Integration test for enable-yield-backend with SUPER_TOKEN_ADMIN_OVERRIDE.
# Uses a known Safe as override when on-chain admin is not yet set.
# Runs in simulate mode against base-mainnet.
#
# Usage: from packages/ethereum-contracts, run: bash test/ops-scripts/enable-yield-backend-override.test.sh

set -eu
set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PKG_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
ENABLE_SCRIPT="$PKG_ROOT/ops-scripts/enable-yield-backend.sh"

USDCX=0xD04383398dD2426297da660F9CCA3d439AF9ce1b
YIELD_BACKEND=0x44f6D470aFb44A4221fcf27EBaA577Ff9D86f4EC
# Known Safe on Base (used when token admin is pending gov action)
ADMIN_OVERRIDE=0x06a858185b3B2ABB246128Bb9415D57e5C09aEB6

cd "$PKG_ROOT"
export RPC_URL="${RPC_URL:-${BASE_MAINNET_ARCHIVE_RPC_URL:-}}"
export SIMULATE=1

output=$(mktemp)
trap 'rm -f "$output"' EXIT

if ! "$ENABLE_SCRIPT" base-mainnet "$USDCX" "$YIELD_BACKEND" "$ADMIN_OVERRIDE" 2>&1 | tee "$output"; then
    echo "enable-yield-backend-override.test.sh failed (script exited with error)" >&2
    exit 1
fi

if ! grep -q "SuperToken Admin (override)" "$output"; then
    echo "Expected output to contain 'SuperToken Admin (override)'" >&2
    exit 1
fi

if ! grep -q "<<<SAFE_TX:v1>>>" "$output"; then
    echo "Expected Safe transaction payload in output" >&2
    exit 1
fi

echo "enable-yield-backend-override.test.sh: OK"
