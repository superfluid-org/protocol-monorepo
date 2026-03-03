#!/usr/bin/env bash

set -xe

pwd

PACKAGE_DIR="$1"
TAG="$2"
shift 2

echo "Publishing ${PACKAGE_DIR} @${TAG} to NPMJS registry"
npm publish --provenance --access public --tag "${TAG}" "${PACKAGE_DIR}" "$@"
