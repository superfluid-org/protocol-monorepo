#!/usr/bin/env bash

# Writes the sizes of contracts (exluding those only used for ephemeral testing) to a file using foundry.
# It specifically also excludes SuperfluidFrameworkDeployer and SuperfluidFrameworkDeploymentSteps.

set -e

# shellcheck disable=SC2046
forge build --sizes $(find contracts -not -path 'contracts/mocks/*' -type f -name '*.sol' -not \( -name '*.t.sol' -o -name 'SuperfluidFrameworkDeploy*' \)) > build/contracts-sizes.txt
