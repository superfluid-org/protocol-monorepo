#!/usr/bin/env bash
# Convenience wrapper for super-token-admin-action.sh disableYieldBackend.
# Usage: disable-yield-backend.sh <network> <superToken> [adminOverride]
#   adminOverride: optional; use when on-chain admin not yet set (e.g. pending gov action)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
[ -n "${3:-}" ] && export SUPER_TOKEN_ADMIN_OVERRIDE="$3"
exec "$SCRIPT_DIR/super-token-admin-action.sh" "$1" disableYieldBackend "$2"
