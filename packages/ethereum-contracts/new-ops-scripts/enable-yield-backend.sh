#!/usr/bin/env bash
# Convenience wrapper for super-token-admin-action.sh enableYieldBackend.
# Usage: enable-yield-backend.sh <network> <superToken> <yieldBackend> [adminOverride]
#   adminOverride: optional; use when on-chain admin not yet set (e.g. pending gov action)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
[ -n "${4:-}" ] && export SUPER_TOKEN_ADMIN_OVERRIDE="$4"
exec "$SCRIPT_DIR/super-token-admin-action.sh" "$1" enableYieldBackend "$2" "$3"
