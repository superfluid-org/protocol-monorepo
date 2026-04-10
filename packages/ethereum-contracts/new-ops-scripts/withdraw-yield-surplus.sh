#!/usr/bin/env bash
# Convenience wrapper: withdraw accumulated yield surplus for one SuperToken (admin → surplusReceiver).
# Usage: withdraw-yield-surplus.sh <network> <superToken> [adminOverride]
#   adminOverride: optional; same as SUPER_TOKEN_ADMIN_OVERRIDE when on-chain admin not yet set
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
[ -n "${3:-}" ] && export SUPER_TOKEN_ADMIN_OVERRIDE="$3"
exec "$SCRIPT_DIR/super-token-admin-action.sh" "$1" withdrawSurplusFromYieldBackend "$2"
