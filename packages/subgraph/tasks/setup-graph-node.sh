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
docker compose up --no-start
# we then extract the gateway ip address and export it
DOCKER_HOST_IP=$(docker network inspect subgraph_default | jq -r '.[0].IPAM.Config[].Gateway')

# docker compose with required variables
DOCKER_HOST_IP=$DOCKER_HOST_IP docker compose up
