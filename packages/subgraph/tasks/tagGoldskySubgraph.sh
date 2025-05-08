#!/bin/bash

# Default subgraph type
subgraph_type="protocol-v1"

# Default tag
tag="prod"

# Function to display usage instructions
usage() {
    echo "Usage: $0 --token <API_KEY> --version <version> [--network <network>|all] [--subgraph-type <subgraph-type>] [--tag <tag>]"
    exit 1
}

# Parse command-line arguments
while [[ "$#" -gt 0 ]]; do
    case $1 in
        --token) API_KEY="$2"; shift ;;
        --version) version="$2"; shift ;;
        --network) network="$2"; shift ;;
        --subgraph-type) subgraph_type="$2"; shift ;;
        --tag) tag="$2"; shift ;;
        *) echo "Unknown parameter passed: $1"; usage ;;
    esac
    shift
done

# Ensure required arguments are provided
if [ -z "$API_KEY" ] || [ -z "$version" ]; then
    usage
fi

# List of networks (modify this list as needed)
networks=("polygon-mainnet" "xdai-mainnet" "eth-mainnet" "base-mainnet" "optimism-mainnet" "arbitrum-one" "bsc-mainnet" "avalanche-c" "optimism-sepolia" "scroll-sepolia" "scroll-mainnet" "eth-sepolia" "avalanche-fuji" "base-sepolia")

# Function to generate goldsky commands for each network
generate_goldsky_commands() {
    local commands=""
    for net in "${networks[@]}"; do
        commands+="
        if ! goldsky subgraph tag create $subgraph_type-$net/$version --tag $tag; then
            echo 'Error: Failed to create subgraph tag for network: $net' >&2
            exit 1
        fi"
    done
    echo "$commands"
}

# Function to run the goldsky commands in Docker
run_goldsky_commands_in_docker() {
    local commands=$1
    if ! docker run --platform linux/x86_64 -it goldsky/indexed.xyz:latest /bin/bash -c "
        if ! goldsky login --token $API_KEY; then
            echo 'Error: Failed to login to Goldsky' >&2
            exit 1
        fi
        $commands
    "; then
        echo "Error: Command execution failed"
        exit 1
    fi
}

# Check if the network argument is 'all'
if [ "$network" == "all" ]; then
    goldsky_commands=$(generate_goldsky_commands)
    run_goldsky_commands_in_docker "$goldsky_commands"
elif [ -n "$network" ]; then
    run_goldsky_commands_in_docker "if ! goldsky subgraph tag create $subgraph_type-$network/$version --tag $tag; then
            echo 'Error: Failed to create subgraph tag for network: $network' >&2
            exit 1
        fi"
else
    usage
fi
