#!/usr/bin/env bash

set -ex

if ! which docker >/dev/null 2>&1 ; then
    echo "Please install 'docker' first"
    exit 1
fi

if ! docker compose --help >/dev/null 2>&1; then
    echo "Please install 'docker compose' first"
    exit 1
fi

if ! which jq >/dev/null 2>&1; then
    echo "Please install 'jq' first"
    exit 1
fi

# this creates the bridged network for the composed ervices (network id: subgraph_default)
docker compose up --no-start --wait
# we then extract the gateway ip address and export it
DOCKER_HOST_IP=$(docker network inspect subgraph_default | jq -r '.[0].IPAM.Config[].Gateway')

# docker compose with required variables
DOCKER_HOST_IP=$DOCKER_HOST_IP docker compose up --detach

# Wait for admin JSON-RPC (same URL as package.json create-local)
GRAPH_NODE_URL="${GRAPH_NODE_URL:-http://localhost:8020/}"
for _ in $(seq 1 30); do
    if curl -s --connect-timeout 2 -o /dev/null "$GRAPH_NODE_URL"; then
        echo "Graph node ready at $GRAPH_NODE_URL"
        exit 0
    fi
    sleep 2
done
echo "Graph node did not become ready at $GRAPH_NODE_URL" >&2
exit 1
