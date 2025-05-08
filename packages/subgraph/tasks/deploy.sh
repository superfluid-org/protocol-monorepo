#!/usr/bin/env bash

set -eux

# shellcheck disable=SC2207
GRAPH_CLI="npx --package=@graphprotocol/graph-cli --yes -- graph"
# shellcheck disable=SC2207
GOLDSKY_CLI="npx --package=@goldskycom/cli --yes -- goldsky"
SUPPORTED_VENDORS=( "graph" "satsuma" "superfluid" "goldsky" "airstack" )


VENDOR=""
NETWORK=""
DEPLOYMENT_ENV=""
VERSION_LABEL=""

print_usage_and_exit() {
    echo "Usage: $0 -o graph|satsuma|superfluid|goldsky|airstack -n <network_name> -r <deployment_env> -v <version_label>"
    exit 1
}

# Command-line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -o|--vendor)
            VENDOR="${2}"
            shift 2
            ;;
        -n|--network)
            NETWORK="$2"
            shift 2
            ;;
        -r|--deployment-env)
            DEPLOYMENT_ENV="$2"
            shift 2
            ;;
        -v|--version-label)
            VERSION_LABEL="$2"
            shift 2
            ;;
        *)
            echo "Unknown option: $1"
            print_usage_and_exit
            ;;
    esac
done

prepare_deployment() {
  # Read environment variables directly, with a fallback Git command for commit_hash
  local commit_hash="${GITHUB_SHA:-$(git rev-parse HEAD)}"
  local configuration="${CONFIGURATION:-v1}"

  # Get ABI
  echo "Getting ABI..."
  node "./scripts/getAbi.js"

  # Prepare subgraph manifest
  echo "Preparing subgraph manifest..."
  ./tasks/prepare-manifest.sh mock

  # Generate meta.ignore.ts file
  echo "Generating meta.ignore.ts file..."
  COMMIT_HASH="$commit_hash" CONFIGURATION="$configuration" yarn generate-sf-meta

  # Generate AssemblyScript types
  echo "Generating AssemblyScript types..."
  yarn codegen

  # Get Hosted Service Networks from metadata
  echo "Getting Hosted Service Networks from metadata..."
  npx ts-node "./scripts/getHostedServiceNetworks.ts"
}

deploy_to_graph() {
    local network="$1"

    # name mapping for subgraphs created before introducing canonical names
    local -A legacyNetworkNames=(
        ["xdai-mainnet"]="xdai"
        ["polygon-mainnet"]="matic"
    )

    local graphNetwork="${legacyNetworkNames[$network]:-$network}"
    local subgraphName="protocol-$DEPLOYMENT_ENV-$graphNetwork"

    echo "********* Deploying $network subgraph $subgraphName to The Graph (hosted service). **********"

    if ! $GRAPH_CLI deploy --studio "$subgraphName" --deploy-key "$THE_GRAPH_ACCESS_TOKEN" --version-label "$VERSION_LABEL"; then
        echo "Error: Deployment to The Graph (hosted service) failed for $network"
        exit 1
    fi
}

deploy_to_satsuma() {
    local network="$1"

    # name mapping for subgraphs (no excuse here for not having canonical names)
    local -A legacyNetworkNames=(
        ["xdai-mainnet"]="xdai"
        ["polygon-mainnet"]="matic"
    )

    local satsumaNetwork="${legacyNetworkNames[$network]:-$network}"

    echo "********* Deploying $network subgraph to Satsuma. **********"
    $GRAPH_CLI deploy "$satsumaNetwork" \
        --version-label "$VERSION_LABEL" \
        --node https://subgraphs.alchemy.com/api/subgraphs/deploy \
        --deploy-key "$SATSUMA_DEPLOY_KEY" \
        --ipfs https://ipfs.satsuma.xyz
}

deploy_to_superfluid() {
    local network="$1"

    echo "********* Deploying $network subgraph to Superfluid (self hosted). **********"
    local nodeUrl="${SUBGRAPH_URL_TEMPLATE//\{\{NETWORK\}\}/$network}/admin/"
    local subgraphName="protocol-$DEPLOYMENT_ENV"
    echo "node url: $nodeUrl, subgraph name: $subgraphName"

    if ! $GRAPH_CLI create "$subgraphName" --node "$nodeUrl"; then
        echo "Error: Creation of subgraph $subgraphName on Superfluid (self hosted) failed for $network"
        exit 1
    fi
    if ! $GRAPH_CLI deploy "$subgraphName" --version-label "$VERSION_LABEL" --node "$nodeUrl" --ipfs "$SUPERFLUID_IPFS_API"; then
        echo "Error: Deployment to Superfluid (self hosted) failed for $network"
        exit 1
    fi
}

deploy_to_goldsky() {
    local network="$1"
    # TODO: use tagging?

    # Get subgraph version from package.json
    PACKAGE_JSON_PATH="package.json"
    SUBGRAPH_VERSION=$(jq -r '.version' $PACKAGE_JSON_PATH)

    local subgraphName="protocol-$DEPLOYMENT_ENV-$network/$SUBGRAPH_VERSION"

     # Note: when using Graph CLI to deploy, it implicitly triggers build too, but Goldsky CLI doesn't, so we do it explicitly.
    if ! $GRAPH_CLI build; then
        echo "Error: Build for Goldsky failed"
        exit 1
    fi

    echo "********* Deploying $network subgraph $subgraphName to Goldsky. **********"
    if ! $GOLDSKY_CLI subgraph deploy "$subgraphName" --path . --token "$GOLDSKY_API_KEY"; then
        echo "Error: Deployment to Goldsky failed for $network"
        exit 1
    fi
}

deploy_to_airstack() {
    local network="$1"
    local nodeUrl="https://subgraph.airstack.xyz/indexer/"
    local subgraphName="protocol-$DEPLOYMENT_ENV-$network"

    echo "********* Deploying $network subgraph $subgraphName to Airstack. **********"
    if ! $GRAPH_CLI create "$subgraphName" --node "$nodeUrl" --access-token "$AIRSTACK_API_KEY"; then
        echo "Error: Creation of subgraph $subgraphName on Airstack failed for $network"
        exit 1
    fi
    if ! $GRAPH_CLI deploy --version-label "$VERSION_LABEL" --node "$nodeUrl" --deploy-key "$AIRSTACK_API_KEY" --ipfs https://ipfs.airstack.xyz/ipfs/api/v0 --headers '{"Authorization": "'"$AIRSTACK_API_KEY"'"}' "$subgraphName"; then
        echo "Error: Deployment to Airstack failed for $network"
        exit 1
    fi
}

# Vendor specific function dispatcher
# Expected arguments:
# $1 - vendor
# $2 - canonical network name
deploy_to() {
    local vendor="$1"
    local network="$2"

    npx ts-node ./scripts/buildNetworkConfig.ts "$network" "$vendor"

    # prepare the manifest prior to deployment
    # this generates the subgraph.yaml and
    # inputs the correct addresses for the specified network ($2)
    ./tasks/prepare-manifest.sh "$network"

    case "$vendor" in
    graph)
        deploy_to_graph "$network"
        ;;
    satsuma)
        deploy_to_satsuma "$network"
        ;;
    superfluid)
        deploy_to_superfluid "$network"
        ;;
    goldsky)
        deploy_to_goldsky "$network"
        ;;
    airstack)
        deploy_to_airstack "$network"
        ;;
    *)
        print_usage_and_exit
        ;;
    esac
}

# Argument validation
if [ -z "$VENDOR" ] || [ -z "$NETWORK" ] || [ -z "$DEPLOYMENT_ENV" ] || [ -z "$VERSION_LABEL" ]; then
    print_usage_and_exit
fi

# We can safely ignore this warning, because the value in vendor won't contain whitespaces
# shellcheck disable=SC2199,SC2076
if [[ ! " ${SUPPORTED_VENDORS[@]} " =~ " $VENDOR " ]]; then
    print_usage_and_exit
fi

#Prepare deployment
# Prepare deployment
if ! prepare_deployment; then
    echo "Error: Failed to prepare deployment"
    exit 1
fi

# Deploy the specified network
deploy_to "$VENDOR" "$NETWORK"
