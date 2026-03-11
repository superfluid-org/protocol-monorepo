#!/usr/bin/env bash

# Governance Action Verification Script
#
# This script performs comprehensive verification of deployed contracts
# before executing a governance action. It can:
# 1. Fetch contract addresses from a URL or from the chain
# 2. Optionally fetch pending Safe transactions to extract new contract addresses
# 3. Verify bytecode of deployed contracts against built artifacts
# 4. Optionally run Etherscan verification
# 5. Generate a verification report
#
# Usage:
#   tasks/verify-governance-action.sh <network> [options]
#
# Options:
#   --addresses-url <url>    URL to fetch addresses file from (file or directory URL)
#   --addresses-file <file>  Local addresses file to use
#   --verify-safe            Fetch and verify pending Safe transaction
#   --verify-etherscan       Run Etherscan verification
#   --output-dir <dir>       Output directory for reports (default: tmp/verification)
#   --help                   Show this help message
#
# Environment variables:
#   PROVIDER_URL             RPC provider URL for the network [REQUIRED]
#   ETHERSCAN_API_KEY        API key for Etherscan verification
#   RESOLVER_ADDRESS         Resolver address for auto-detecting Safe (optional)
#   SAFE_ADDRESS             Safe address to query (optional, auto-detected if not set)
#   (other *SCAN_API_KEY variables as needed)
#
# Examples:
#   # Verify using addresses from URL (directory format)
#   PROVIDER_URL=https://... tasks/verify-governance-action.sh eth-mainnet --addresses-url https://example.com/addrs/v1.14.1/
#
#   # Verify using addresses file
#   PROVIDER_URL=https://... tasks/verify-governance-action.sh eth-mainnet --addresses-file addrs/v1.14.1/eth-mainnet
#
#   # Verify with Safe pending transaction
#   PROVIDER_URL=https://... tasks/verify-governance-action.sh eth-mainnet --verify-safe
#
#   # Full verification
#   PROVIDER_URL=https://... tasks/verify-governance-action.sh eth-mainnet --addresses-url https://example.com/addrs/v1.14.1/ --verify-safe --verify-etherscan

set -e

# Check required dependencies
for cmd in jq curl node; do
    if ! command -v "$cmd" &> /dev/null; then
        echo "Error: '$cmd' is required but not found in PATH"
        exit 1
    fi
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONTRACTS_DIR="$(dirname "$SCRIPT_DIR")"

# Resolve hardhat CLI path - npx can be unreliable in yarn workspaces
HARDHAT_CLI="$(node -e "console.log(require.resolve('hardhat/internal/cli/cli'))")"
run_hardhat() {
    node "$HARDHAT_CLI" "$@"
}

# Default values
NETWORK=""
ADDRESSES_URL=""
ADDRESSES_FILE=""
VERIFY_SAFE=false
VERIFY_ETHERSCAN=false
OUTPUT_DIR="$CONTRACTS_DIR/tmp/verification"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Print colored output
print_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
print_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Show help
show_help() {
    head -50 "$0" | grep -E "^#" | sed 's/^# //' | sed 's/^#//'
    exit 0
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --help|-h)
            show_help
            ;;
        --addresses-url)
            ADDRESSES_URL="$2"
            shift 2
            ;;
        --addresses-file)
            ADDRESSES_FILE="$2"
            shift 2
            ;;
        --verify-safe)
            VERIFY_SAFE=true
            shift
            ;;
        --verify-etherscan)
            VERIFY_ETHERSCAN=true
            shift
            ;;
        --output-dir)
            OUTPUT_DIR="$2"
            shift 2
            ;;
        -*)
            print_error "Unknown option: $1"
            exit 1
            ;;
        *)
            if [ -z "$NETWORK" ]; then
                NETWORK="$1"
            else
                print_error "Unexpected argument: $1"
                exit 1
            fi
            shift
            ;;
    esac
done

# Validate required arguments
if [ -z "$NETWORK" ]; then
    print_error "Network is required"
    echo "Usage: PROVIDER_URL=https://... tasks/verify-governance-action.sh <network> [options]"
    exit 1
fi

if [ -z "$PROVIDER_URL" ]; then
    print_error "PROVIDER_URL environment variable is required"
    echo "Usage: PROVIDER_URL=https://... tasks/verify-governance-action.sh <network> [options]"
    exit 1
fi

# Create output directory
mkdir -p "$OUTPUT_DIR"

print_info "Starting governance action verification for network: $NETWORK"
print_info "Output directory: $OUTPUT_DIR"

cd "$CONTRACTS_DIR"

# Step 1: Get addresses file
WORK_ADDRESSES_FILE="$OUTPUT_DIR/addresses.vars"

if [ -n "$ADDRESSES_FILE" ] && [ -f "$ADDRESSES_FILE" ]; then
    print_info "Using provided addresses file: $ADDRESSES_FILE"
    cp "$ADDRESSES_FILE" "$WORK_ADDRESSES_FILE"
elif [ -n "$ADDRESSES_URL" ]; then
    print_info "Fetching addresses from URL..."

    # Check if URL is a directory (ends with /) or a file
    if [[ "$ADDRESSES_URL" == */ ]]; then
        FETCH_URL="${ADDRESSES_URL}${NETWORK}"
    else
        FETCH_URL="$ADDRESSES_URL"
    fi

    print_info "Fetching from: $FETCH_URL"
    if curl -fsSL "$FETCH_URL" -o "$WORK_ADDRESSES_FILE"; then
        print_success "Addresses fetched successfully"
    else
        print_warning "Failed to fetch addresses from URL, will fetch from chain"
        rm -f "$WORK_ADDRESSES_FILE"
    fi
fi

# Fall back to fetching from chain using Truffle (existing script)
if [ ! -s "$WORK_ADDRESSES_FILE" ]; then
    print_info "Fetching addresses from chain..."
    npx truffle exec --network "$NETWORK" ops-scripts/info-print-contract-addresses.js : "$WORK_ADDRESSES_FILE"
    print_success "Addresses fetched from chain"
fi

print_info "Addresses file contents:"
cat "$WORK_ADDRESSES_FILE"
echo ""

# Step 2: Optionally fetch Safe pending transaction
# When --verify-safe is used, the extracted addresses from the Safe tx become
# the PRIMARY target for bytecode verification. The point is to verify that the
# pending governance action upgrades contracts to bytecode matching the repo.
SAFE_ADDRESSES_FILE=""

if [ "$VERIFY_SAFE" = true ]; then
    print_info "Fetching pending Safe governance transaction..."

    SAFE_TX_FILE="$OUTPUT_DIR/safe-pending-tx.json"

    # Set up environment for Hardhat script
    export OUTPUT_FILE="$SAFE_TX_FILE"

    if run_hardhat run --no-compile scripts/fetch-safe-pending-tx.ts 2>/dev/null; then
        if [ -f "$SAFE_TX_FILE" ] && [ -s "$SAFE_TX_FILE" ]; then
            print_success "Safe pending transaction fetched"

            # Extract and display key information
            echo ""
            print_info "Pending transaction details:"
            jq -r '
                "  Nonce: \(.transaction.nonce // "N/A")",
                "  To: \(.transaction.to // "N/A")",
                "  Confirmations: \(.transaction.confirmations // 0)/\(.transaction.confirmationsRequired // "?")",
                "  Function: \(.decodedAction.functionName // "unknown")"
            ' "$SAFE_TX_FILE"

            # Extract new contract addresses from the pending Safe transaction
            SAFE_ADDRESSES=$(jq -r '.extractedAddresses | to_entries | .[] | "\(.key)=\(.value)"' "$SAFE_TX_FILE" 2>/dev/null)
            if [ -n "$SAFE_ADDRESSES" ]; then
                # Write extracted addresses to a separate file for targeted verification
                SAFE_ADDRESSES_FILE="$OUTPUT_DIR/safe-addresses.vars"
                echo "# New contract addresses from pending Safe governance transaction" > "$SAFE_ADDRESSES_FILE"
                echo "$SAFE_ADDRESSES" >> "$SAFE_ADDRESSES_FILE"

                # Also include library addresses from the base addresses file (needed for linking)
                grep -E "^(SLOTS_BITMAP_LIBRARY|SUPERFLUID_POOL_DEPLOYER_LIBRARY)=" "$WORK_ADDRESSES_FILE" >> "$SAFE_ADDRESSES_FILE" 2>/dev/null || true

                print_info "New addresses from Safe transaction (these will be verified):"
                echo "$SAFE_ADDRESSES" | sed 's/^/  /'
            else
                print_warning "No contract addresses found in Safe transaction calldata"
            fi
        else
            print_warning "No pending Safe transaction found"
        fi
    else
        print_warning "Failed to fetch Safe pending transaction (may not be configured for this network)"
    fi
fi

echo ""

# Step 3: Verify bytecode using Hardhat
# When --verify-safe was used and addresses were extracted, verify ONLY those
# addresses (the new contracts the governance action will upgrade to).
# Otherwise, fall back to verifying all addresses from the base addresses file.
VERIFY_ADDRESSES_FILE="$WORK_ADDRESSES_FILE"

if [ -n "$SAFE_ADDRESSES_FILE" ] && [ -s "$SAFE_ADDRESSES_FILE" ]; then
    VERIFY_ADDRESSES_FILE="$SAFE_ADDRESSES_FILE"
    print_info "Verifying bytecode of NEW contracts from Safe transaction..."
else
    print_info "Verifying bytecode of existing deployed contracts..."
fi

BYTECODE_REPORT="$OUTPUT_DIR/bytecode-report.json"

# Set up environment for Hardhat script
export ADDRESSES_FILE="$VERIFY_ADDRESSES_FILE"
export JSON_OUTPUT=true

if run_hardhat run --no-compile scripts/verify-bytecode.ts > "$BYTECODE_REPORT"; then
    BYTECODE_STATUS=0
else
    BYTECODE_STATUS=$?
fi

if [ -f "$BYTECODE_REPORT" ] && [ -s "$BYTECODE_REPORT" ]; then
    # Extract summary
    VERIFIED=$(jq -r '.summary.verified // 0' "$BYTECODE_REPORT")
    MISMATCH=$(jq -r '.summary.mismatch // 0' "$BYTECODE_REPORT")
    NOT_DEPLOYED=$(jq -r '.summary.notDeployed // 0' "$BYTECODE_REPORT")
    ERRORS=$(jq -r '.summary.errors // 0' "$BYTECODE_REPORT")

    echo ""
    print_info "Bytecode verification results:"
    echo "  Verified: $VERIFIED"
    echo "  Mismatch: $MISMATCH"
    echo "  Not deployed: $NOT_DEPLOYED"
    echo "  Errors: $ERRORS"

    if [ "$MISMATCH" -gt 0 ]; then
        print_error "Bytecode mismatches detected!"
        echo ""
        print_info "Mismatched contracts:"
        jq -r '.contracts[] | select(.status == "mismatch") | "  - \(.key): \(.address) - \(.message)"' "$BYTECODE_REPORT"
    fi

    if [ "$ERRORS" -gt 0 ]; then
        print_warning "Errors during verification:"
        jq -r '.contracts[] | select(.status == "error") | "  - \(.key): \(.message)"' "$BYTECODE_REPORT"
    fi

    if [ "$MISMATCH" -eq 0 ] && [ "$ERRORS" -eq 0 ]; then
        print_success "All contracts verified successfully!"
    fi
else
    print_error "Failed to generate bytecode report"
fi

echo ""

# Step 4: Optionally run Etherscan verification
if [ "$VERIFY_ETHERSCAN" = true ]; then
    print_info "Running Etherscan verification..."

    ETHERSCAN_LOG="$OUTPUT_DIR/etherscan-verification.log"

    if "$SCRIPT_DIR/etherscan-verify-framework.sh" "$NETWORK" "$WORK_ADDRESSES_FILE" 2>&1 | tee "$ETHERSCAN_LOG"; then
        print_success "Etherscan verification completed"
    else
        print_warning "Some Etherscan verifications may have failed (check log for details)"
    fi
fi

# Step 5: Generate final report
print_info "Generating verification report..."

REPORT_FILE="$OUTPUT_DIR/verification-report.md"

cat > "$REPORT_FILE" << EOF
# Governance Action Verification Report

**Network:** $NETWORK
**Date:** $(date -u +"%Y-%m-%d %H:%M:%S UTC")
**Addresses Source:** ${ADDRESSES_URL:-${ADDRESSES_FILE:-"chain"}}

## Bytecode Verification

| Metric | Count |
|--------|-------|
| Verified | ${VERIFIED:-N/A} |
| Mismatch | ${MISMATCH:-N/A} |
| Not Deployed | ${NOT_DEPLOYED:-N/A} |
| Errors | ${ERRORS:-N/A} |

EOF

if [ -f "$BYTECODE_REPORT" ]; then
    echo "### Contract Details" >> "$REPORT_FILE"
    echo "" >> "$REPORT_FILE"
    echo "| Contract | Address | Status |" >> "$REPORT_FILE"
    echo "|----------|---------|--------|" >> "$REPORT_FILE"

    jq -r '.contracts[] | "| \(.key) | \(.address) | \(.status) |"' "$BYTECODE_REPORT" >> "$REPORT_FILE"

    echo "" >> "$REPORT_FILE"
fi

if [ "$VERIFY_SAFE" = true ] && [ -f "$SAFE_TX_FILE" ]; then
    cat >> "$REPORT_FILE" << EOF
## Safe Pending Transaction

EOF
    jq -r '
        "- **Nonce:** \(.transaction.nonce // "N/A")",
        "- **To:** \(.transaction.to // "N/A")",
        "- **Confirmations:** \(.transaction.confirmations // 0)/\(.transaction.confirmationsRequired // "?")",
        "- **Function:** \(.decodedAction.functionName // "unknown")",
        ""
    ' "$SAFE_TX_FILE" >> "$REPORT_FILE"

    if [ "$(jq -r '.extractedAddresses | length' "$SAFE_TX_FILE")" -gt 0 ]; then
        echo "### Extracted Addresses" >> "$REPORT_FILE"
        echo "" >> "$REPORT_FILE"
        jq -r '.extractedAddresses | to_entries | .[] | "- **\(.key):** \(.value)"' "$SAFE_TX_FILE" >> "$REPORT_FILE"
        echo "" >> "$REPORT_FILE"
    fi
fi

if [ "$VERIFY_ETHERSCAN" = true ]; then
    cat >> "$REPORT_FILE" << EOF
## Etherscan Verification

Etherscan verification was executed. See \`etherscan-verification.log\` for details.

EOF
fi

cat >> "$REPORT_FILE" << EOF
---

*Report generated by verify-governance-action.sh*
EOF

print_success "Report generated: $REPORT_FILE"

# Generate self-contained HTML report
HTML_REPORT="$OUTPUT_DIR/verification-report.html"
if node "$CONTRACTS_DIR/scripts/generate-report.js" \
    --input-dir "$OUTPUT_DIR" \
    --output "$HTML_REPORT" \
    --title "Verification Report: $NETWORK"; then
    print_success "HTML report generated: $HTML_REPORT"
else
    print_warning "Failed to generate HTML report"
fi

echo ""
print_info "=== Verification Summary ==="

# Final status
if [ "${MISMATCH:-0}" -gt 0 ] || [ "${ERRORS:-0}" -gt 0 ]; then
    print_error "VERIFICATION FAILED"
    echo ""
    echo "Output files:"
    echo "  - Addresses: $WORK_ADDRESSES_FILE"
    echo "  - Bytecode report: $BYTECODE_REPORT"
    echo "  - Full report: $REPORT_FILE"
    [ -f "$HTML_REPORT" ] && echo "  - HTML report: $HTML_REPORT"
    [ -f "$SAFE_TX_FILE" ] && echo "  - Safe TX: $SAFE_TX_FILE"
    [ -f "$ETHERSCAN_LOG" ] && echo "  - Etherscan log: $ETHERSCAN_LOG"
    exit 1
else
    print_success "VERIFICATION PASSED"
    echo ""
    echo "Output files:"
    echo "  - Addresses: $WORK_ADDRESSES_FILE"
    echo "  - Bytecode report: $BYTECODE_REPORT"
    echo "  - Full report: $REPORT_FILE"
    [ -f "$HTML_REPORT" ] && echo "  - HTML report: $HTML_REPORT"
    [ -f "$SAFE_TX_FILE" ] && echo "  - Safe TX: $SAFE_TX_FILE"
    [ -f "$ETHERSCAN_LOG" ] && echo "  - Etherscan log: $ETHERSCAN_LOG"
    exit 0
fi
