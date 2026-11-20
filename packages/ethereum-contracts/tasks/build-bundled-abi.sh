#!/usr/bin/env bash
set -e

exec node "$(dirname "$0")/build-bundled-abi.js"
