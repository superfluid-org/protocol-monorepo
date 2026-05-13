#!/usr/bin/env bash
# Integration test for enable-yield-backend (super-token-admin-action enableYieldBackend).
# Runs in simulate mode against base-mainnet.
#
# Usage: from packages/ethereum-contracts, run: bash test/new-ops-scripts/enable-yield-backend.test.sh
# Note: Requires a SuperToken with admin set. USDCx on Base may have admin=0 until changeSuperTokenAdmin is executed.

set -eu
set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PKG_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
ENABLE_SCRIPT="$PKG_ROOT/new-ops-scripts/enable-yield-backend.sh"

USDCX=0xD04383398dD2426297da660F9CCA3d439AF9ce1b
YIELD_BACKEND=0x1234567890123456789012345678901234567890

cd "$PKG_ROOT"
export RPC_URL="${RPC_URL:-${BASE_MAINNET_ARCHIVE_RPC_URL:-}}"
export SIMULATE=1

output=$(mktemp)
trap 'rm -f "$output"' EXIT

if ! "$ENABLE_SCRIPT" base-mainnet "$USDCX" "$YIELD_BACKEND" 2>&1 | tee "$output"; then
    if grep -q "SuperToken has no admin" "$output"; then
        echo "enable-yield-backend.test.sh: OK (script ran, token has no admin - expected before changeSuperTokenAdmin)"
    else
        echo "enable-yield-backend.test.sh failed" >&2
        exit 1
    fi
else
    if grep -q "SuperToken Admin" "$output"; then
        echo "enable-yield-backend.test.sh: OK"
    else
        echo "enable-yield-backend.test.sh: unexpected success output" >&2
        exit 1
    fi
fi
