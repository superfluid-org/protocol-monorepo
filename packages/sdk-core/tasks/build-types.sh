#!/usr/bin/env bash

# make sure that if any step fails, the script fails
set -xe

rm -rf ./src/typechain-types

# if the typechain files do not exist, we build
# hardhat so that it does exist
if [ ! -d "../ethereum-contracts/typechain-types" ]; then
  echo "typechain-types does not exist: You must build ethereum-contracts first to generate it."
  exit 1
fi

# copy the typechain files over from ethereum-contracts
cp -r ../ethereum-contracts/typechain-types ./src/typechain-types

# Remove the Address export from typechain-types to avoid conflict with mappedSubgraphTypes
# OpenZeppelin v5 added a custom error to Address library, giving it a non-empty ABI
# This causes typechain to generate types for it, but it's not needed for the SDK
sed -i '/export type { Address } from ".\/@openzeppelin\/contracts\/utils\/Address";/d' ./src/typechain-types/index.ts
sed -i '/export { Address__factory } from ".\/factories\/@openzeppelin\/contracts\/utils\/Address__factory";/d' ./src/typechain-types/index.ts

# compile the typechain files in sdk-core
tsc -p tsconfig.typechain.json
