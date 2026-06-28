#!/usr/bin/env bash

# Multi-Network Governance Action Verification
#
# Runs verify-governance-action.sh for each mainnet network and then
# generates a consolidated HTML report across all networks.
#
# Usage:
#   tasks/verify-governance-action-all.sh [options] [-- extra-args-for-per-network-script]
#
# Options:
#   --networks <list>        Comma-separated list of networks (overrides default)
#   --addresses-url <url>    Passed through to per-network script (directory URL)
#   --verify-safe            Passed through to per-network script
#   --verify-etherscan       Passed through to per-network script
#   --output-dir <dir>       Base output directory (default: tmp/verification-all)
#   --title <text>           HTML report title
#   --continue-on-error      Don't stop on first network failure
#   --help                   Show this help message
#
# Environment variables:
#   PROVIDER_URL_<NETWORK>   Override RPC URL for a specific network (e.g. PROVIDER_URL_ETH_MAINNET)
#                            If not set, uses https://rpc-endpoints.superfluid.dev/<network>
#
# Examples:
#   # Verify all networks
#   tasks/verify-governance-action-all.sh --verify-safe --addresses-url https://example.com/addrs/v1.15.0/
#
#   # Verify specific networks
#   tasks/verify-governance-action-all.sh --networks base-mainnet,eth-mainnet --verify-safe
#
#   # With custom output dir and title
#   tasks/verify-governance-action-all.sh --output-dir tmp/v1.15.0 --title "v1.15.0 Verification"

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONTRACTS_DIR="$(dirname "$SCRIPT_DIR")"

# Default mainnet networks
DEFAULT_NETWORKS="eth-mainnet,polygon-mainnet,optimism-mainnet,arbitrum-one,base-mainnet,bsc-mainnet,avalanche-c,xdai-mainnet,celo-mainnet,scroll-mainnet,degenchain"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

print_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
print_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1"; }
print_header() { echo -e "\n${CYAN}========================================${NC}"; echo -e "${CYAN}  $1${NC}"; echo -e "${CYAN}========================================${NC}\n"; }

# Parse arguments
NETWORKS=""
ADDRESSES_URL=""
VERIFY_SAFE=false
VERIFY_ETHERSCAN=false
OUTPUT_DIR="$CONTRACTS_DIR/tmp/verification-all"
REPORT_TITLE="Governance Action Verification Report"
CONTINUE_ON_ERROR=false
EXTRA_ARGS=()

while [[ $# -gt 0 ]]; do
    case $1 in
        --help|-h)
            head -40 "$0" | grep -E "^#" | sed 's/^# //' | sed 's/^#//'
            exit 0
            ;;
        --networks)
            NETWORKS="$2"
            shift 2
            ;;
        --addresses-url)
            ADDRESSES_URL="$2"
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
        --title)
            REPORT_TITLE="$2"
            shift 2
            ;;
        --continue-on-error)
            CONTINUE_ON_ERROR=true
            shift
            ;;
        --)
            shift
            EXTRA_ARGS=("$@")
            break
            ;;
        *)
            print_error "Unknown option: $1"
            exit 1
            ;;
    esac
done

if [ -z "$NETWORKS" ]; then
    NETWORKS="$DEFAULT_NETWORKS"
fi

# Convert comma-separated to array
IFS=',' read -ra NETWORK_ARRAY <<< "$NETWORKS"

print_header "Multi-Network Verification"
print_info "Networks: ${NETWORK_ARRAY[*]}"
print_info "Output directory: $OUTPUT_DIR"

mkdir -p "$OUTPUT_DIR"

cd "$CONTRACTS_DIR"

# Track results
PASSED=()
FAILED=()
SKIPPED=()

# Run verification for each network
for NETWORK in "${NETWORK_ARRAY[@]}"; do
    print_header "Verifying: $NETWORK"

    NETWORK_OUTPUT_DIR="$OUTPUT_DIR/$NETWORK"

    # Determine provider URL
    # Check for network-specific override env var (e.g. PROVIDER_URL_ETH_MAINNET)
    ENV_VAR_NAME="PROVIDER_URL_$(echo "$NETWORK" | tr '[:lower:]-' '[:upper:]_')"
    NETWORK_PROVIDER_URL="${!ENV_VAR_NAME:-}"

    if [ -z "$NETWORK_PROVIDER_URL" ]; then
        NETWORK_PROVIDER_URL="https://rpc-endpoints.superfluid.dev/$NETWORK"
    fi

    print_info "RPC: $NETWORK_PROVIDER_URL"

    # Build arguments for per-network script
    PER_NETWORK_ARGS=("$NETWORK" "--output-dir" "$NETWORK_OUTPUT_DIR")

    if [ -n "$ADDRESSES_URL" ]; then
        PER_NETWORK_ARGS+=("--addresses-url" "$ADDRESSES_URL")
    fi

    if [ "$VERIFY_SAFE" = true ]; then
        PER_NETWORK_ARGS+=("--verify-safe")
    fi

    if [ "$VERIFY_ETHERSCAN" = true ]; then
        PER_NETWORK_ARGS+=("--verify-etherscan")
    fi

    # Append any extra args
    PER_NETWORK_ARGS+=("${EXTRA_ARGS[@]}")

    # Run the per-network script
    if PROVIDER_URL="$NETWORK_PROVIDER_URL" "$SCRIPT_DIR/verify-governance-action.sh" "${PER_NETWORK_ARGS[@]}"; then
        PASSED+=("$NETWORK")
        print_success "$NETWORK: PASSED"
    else
        EXIT_CODE=$?
        FAILED+=("$NETWORK")
        print_error "$NETWORK: FAILED (exit code $EXIT_CODE)"

        if [ "$CONTINUE_ON_ERROR" != true ]; then
            print_error "Stopping. Use --continue-on-error to continue past failures."
            break
        fi
    fi
done

echo ""
print_header "Generating Consolidated Report"

# Generate consolidated HTML report
if node "$CONTRACTS_DIR/scripts/generate-report.js" \
    --input-dir "$OUTPUT_DIR" \
    --output "$OUTPUT_DIR/verification-report.html" \
    --title "$REPORT_TITLE"; then
    print_success "HTML report: $OUTPUT_DIR/verification-report.html"
else
    print_warning "Failed to generate HTML report"
fi

# Print summary
echo ""
print_header "Summary"

if [ ${#PASSED[@]} -gt 0 ]; then
    print_success "Passed (${#PASSED[@]}): ${PASSED[*]}"
fi

if [ ${#FAILED[@]} -gt 0 ]; then
    print_error "Failed (${#FAILED[@]}): ${FAILED[*]}"
fi

TOTAL_RUN=$(( ${#PASSED[@]} + ${#FAILED[@]} ))
TOTAL_EXPECTED=${#NETWORK_ARRAY[@]}
if [ "$TOTAL_RUN" -lt "$TOTAL_EXPECTED" ]; then
    SKIPPED_COUNT=$(( TOTAL_EXPECTED - TOTAL_RUN ))
    print_warning "Skipped: $SKIPPED_COUNT network(s)"
fi

echo ""
echo "Output: $OUTPUT_DIR/"
echo "Report: $OUTPUT_DIR/verification-report.html"

# Exit with error if any failures
if [ ${#FAILED[@]} -gt 0 ]; then
    exit 1
fi
