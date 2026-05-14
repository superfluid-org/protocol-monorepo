#!/usr/bin/env bash
# Integration test for disable-yield-backend (super-token-admin-action disableYieldBackend).
# Runs in simulate mode against base-mainnet.
#
# Usage: from packages/ethereum-contracts, run: bash test/new-ops-scripts/disable-yield-backend.test.sh
# Note: Requires a SuperToken with admin and an enabled yield backend. USDCx on Base may not have these yet.

set -eu
set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PKG_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
DISABLE_SCRIPT="$PKG_ROOT/new-ops-scripts/disable-yield-backend.sh"

USDCX=0xD04383398dD2426297da660F9CCA3d439AF9ce1b

cd "$PKG_ROOT"
export RPC_URL="${RPC_URL:-${BASE_MAINNET_ARCHIVE_RPC_URL:-}}"
export SIMULATE=1

output=$(mktemp)
trap 'rm -f "$output"' EXIT

if ! "$DISABLE_SCRIPT" base-mainnet "$USDCX" 2>&1 | tee "$output"; then
    if grep -q "SuperToken has no admin" "$output" || grep -q "yield backend not set" "$output"; then
        echo "disable-yield-backend.test.sh: OK (script ran, token state not ready - expected)"
    else
        echo "disable-yield-backend.test.sh failed" >&2
        exit 1
    fi
else
    if grep -q "SuperToken Admin" "$output"; then
        echo "disable-yield-backend.test.sh: OK"
    else
        echo "disable-yield-backend.test.sh: unexpected success output" >&2
        exit 1
    fi
fi
