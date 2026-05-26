#!/usr/bin/env bash
#
# Propose adding an owner to the Gnosis Safe that administers Superfluid governance on each chain
# where the on-chain governance owner matches the expected Safe address.
#
# Uses the same Safe Transaction Service flow as gov-action.sh / super-token-admin-action.sh
# (safe-ops.ts + SAFE_PROPOSER_PK, optional SAFE_API_KEY / SAFE_TX_SERVICE_URL).
#
# Env:
#   GOV_SAFE              — expected governance admin Safe (default: production multisig)
#   NEW_SAFE_OWNER        — address to add as Safe owner (default below)
#   GOV_SAFE_OPS_NETWORKS — optional comma-separated canonical network names from networks.json
#                           (e.g. "eth-mainnet,base-mainnet"). If unset, all entries in metadata are tried.
#   SIMULATE=1            — print payloads and run safe-ops with --dry-run (no proposal)
#   SAFE_ORIGIN           — optional label for the Safe UI (default: gov-safe-add-owner)
#   METADATA_JSON         — override path to networks.json
#
# Per-iteration RPC_URL is cleared so each network uses metadata RPCs (or PROVIDER_URL_TEMPLATE).
#
# TypeScript variant (same env, calls proposeSafeTx in-process): gov-safe-add-owner.ts
#
set -e
set -o pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
PKG_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
METADATA_JSON="${METADATA_JSON:-$PKG_ROOT/../metadata/networks.json}"

# shellcheck source=/dev/null
[ -f "$PKG_ROOT/.env" ] && . "$PKG_ROOT/.env"
# shellcheck source=/dev/null
[ -f "$PKG_ROOT/../.env" ] && . "$PKG_ROOT/../.env"
export SAFE_PROPOSER_PK="${SAFE_PROPOSER_PK:-}"
export SAFE_API_KEY="${SAFE_API_KEY:-}"
export SAFE_TX_SERVICE_URL="${SAFE_TX_SERVICE_URL:-}"
# shellcheck source=/dev/null
[ -f "$SCRIPT_DIR/lib/network-config.sh" ] && . "$SCRIPT_DIR/lib/network-config.sh"

GOV_SAFE="${GOV_SAFE:-0x06a858185b3b2abb246128bb9415d57e5c09aeb6}"
NEW_SAFE_OWNER="${NEW_SAFE_OWNER:-0x4289a2b29be2555b0973422167321bF42CC39A3B}"

if [[ ! "$GOV_SAFE" =~ ^0x[a-fA-F0-9]{40}$ ]]; then
    echo "Error: GOV_SAFE must be a valid Ethereum address: $GOV_SAFE" >&2
    exit 1
fi
if [[ ! "$NEW_SAFE_OWNER" =~ ^0x[a-fA-F0-9]{40}$ ]]; then
    echo "Error: NEW_SAFE_OWNER must be a valid Ethereum address: $NEW_SAFE_OWNER" >&2
    exit 1
fi

GOV_SAFE_LC=$(echo "$GOV_SAFE" | tr '[:upper:]' '[:lower:]')

GOV_SAFE_CHECKSUM=$(cast to-check-sum-address "$GOV_SAFE")
NEW_OWNER_CHECKSUM=$(cast to-check-sum-address "$NEW_SAFE_OWNER")

network_allowed() {
    local n=$1
    local filter="${GOV_SAFE_OPS_NETWORKS:-}"
    if [[ -z "$filter" ]]; then
        return 0
    fi
    local IFS=','
    local -a parts
    read -ra parts <<<"$filter"
    local p trimmed
    for p in "${parts[@]}"; do
        trimmed="${p//[[:space:]]/}"
        if [[ -z "$trimmed" ]]; then
            continue
        fi
        if [[ "$trimmed" == "$n" ]]; then
            return 0
        fi
    done
    return 1
}

echo "Expected governance Safe: $GOV_SAFE_CHECKSUM"
echo "New owner to add:         $NEW_OWNER_CHECKSUM"
if [[ -n "${GOV_SAFE_OPS_NETWORKS:-}" ]]; then
    echo "Network filter (GOV_SAFE_OPS_NETWORKS): $GOV_SAFE_OPS_NETWORKS"
else
    echo "Network filter: (none — all networks in metadata)"
fi
echo ""

SAFE_PAYLOADS_DIR="$PKG_ROOT/.tmp/safe-payloads"
mkdir -p "$SAFE_PAYLOADS_DIR"

proposed=0
skipped=0
errors=0

while IFS= read -r NETWORK; do
    if ! network_allowed "$NETWORK"; then
        continue
    fi
    if ! jq -e --arg n "$NETWORK" 'any(.[]; .name == $n)' "$METADATA_JSON" >/dev/null 2>&1; then
        echo "[$NETWORK] skip: not in metadata" >&2
        ((skipped++)) || true
        continue
    fi

    unset RPC_URL
    if ! PROVIDER_URL=$(get_rpc_url "$NETWORK"); then
        echo "[$NETWORK] skip: no RPC" >&2
        ((skipped++)) || true
        continue
    fi

    HOST_ADDRESS=$(get_host "$NETWORK")
    if [[ -z "$HOST_ADDRESS" || "$HOST_ADDRESS" == "null" || ! "$HOST_ADDRESS" =~ ^0x[a-fA-F0-9]{40}$ ]]; then
        echo "[$NETWORK] skip: invalid host in metadata" >&2
        ((skipped++)) || true
        continue
    fi

    echo "======== $NETWORK ========"

    GOV_ADDR=$(cast call "$HOST_ADDRESS" "getGovernance()(address)" --rpc-url "$PROVIDER_URL" 2>/dev/null) || {
        echo "[$NETWORK] skip: getGovernance failed" >&2
        ((skipped++)) || true
        continue
    }

    ADMIN_ADDR=$(cast call "$GOV_ADDR" "owner()(address)" --rpc-url "$PROVIDER_URL" 2>/dev/null) || {
        echo "[$NETWORK] skip: governance owner() failed" >&2
        ((skipped++)) || true
        continue
    }

    ADMIN_LC=$(echo "$ADMIN_ADDR" | tr '[:upper:]' '[:lower:]')
    if [[ "$ADMIN_LC" != "$GOV_SAFE_LC" ]]; then
        echo "[$NETWORK] skip: governance admin $ADMIN_ADDR is not GOV_SAFE (not Safe-owned by expected multisig)"
        ((skipped++)) || true
        continue
    fi

    if ! cast call "$ADMIN_ADDR" "VERSION()(string)" --rpc-url "$PROVIDER_URL" >/dev/null 2>&1; then
        echo "[$NETWORK] skip: admin matches address but does not respond like a Safe (VERSION)" >&2
        ((skipped++)) || true
        continue
    fi

    ALREADY=$(cast call "$ADMIN_ADDR" "isOwner(address)(bool)" "$NEW_OWNER_CHECKSUM" --rpc-url "$PROVIDER_URL" 2>/dev/null) || {
        echo "[$NETWORK] error: isOwner check failed" >&2
        ((errors++)) || true
        continue
    }
    if [[ "$ALREADY" == "true" ]]; then
        echo "[$NETWORK] skip: $NEW_OWNER_CHECKSUM is already an owner"
        ((skipped++)) || true
        continue
    fi

    THRESHOLD=$(cast call "$ADMIN_ADDR" "getThreshold()(uint256)" --rpc-url "$PROVIDER_URL" 2>/dev/null) || {
        echo "[$NETWORK] error: getThreshold failed" >&2
        ((errors++)) || true
        continue
    }

    CALLDATA=$(cast calldata "addOwnerWithThreshold(address,uint256)" "$NEW_OWNER_CHECKSUM" "$THRESHOLD") || {
        echo "[$NETWORK] error: calldata encode failed" >&2
        ((errors++)) || true
        continue
    }

    PAYLOAD_FILE=$(mktemp "$SAFE_PAYLOADS_DIR/gov-safe-add-owner.XXXXXX.jsonl")
    printf '%s\n' "{\"safeAddress\":\"$GOV_SAFE_CHECKSUM\",\"to\":\"$GOV_SAFE_CHECKSUM\",\"value\":\"0\",\"data\":\"$CALLDATA\",\"operation\":\"0\",\"actionType\":\"gov-safe-add-owner\"}" >"$PAYLOAD_FILE"

    echo "  RPC: $PROVIDER_URL"
    echo "  Governance: $GOV_ADDR"
    echo "  Safe admin: $ADMIN_ADDR"
    echo "  Preserving threshold: $THRESHOLD"
    echo "  addOwnerWithThreshold calldata: $CALLDATA"

    safe_ops_args=(
        propose-file
        --rpc-url "$PROVIDER_URL"
        --payload-file "$PAYLOAD_FILE"
        --mode single
        --origin "${SAFE_ORIGIN:-gov-safe-add-owner}"
    )
    if [[ -n "${SIMULATE:-}" ]]; then
        safe_ops_args+=(--dry-run)
    fi

    if (cd "$PKG_ROOT" && npx ts-node "$SCRIPT_DIR/safe-ops.ts" "${safe_ops_args[@]}"); then
        ((proposed++)) || true
    else
        echo "[$NETWORK] error: safe-ops failed" >&2
        ((errors++)) || true
    fi

    rm -f "$PAYLOAD_FILE"
    echo ""
done < <(jq -r '.[].name' "$METADATA_JSON")

echo "Done. Proposed (or dry-run printed): $proposed, skipped: $skipped, errors: $errors"
if [[ "$errors" -gt 0 ]]; then
    exit 1
fi
