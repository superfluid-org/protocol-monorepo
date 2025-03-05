# Changelog
All notable changes to the metadata will be documented in this file.

This project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [v1.5.2]
### Changed
- New (payable) MacroForwarder for all networks

## [v1.5.1]
### Added
- VestingSchedulerV2 address on Base

## [v1.5.0]
### Added
- MacroForwarder addresses

### Changed
- Updated BatchLiquidator addresses

## [v1.4.1]
### Changed
- New & updated contracts on eth-mainnet

## [v1.4.0]
### Changed
- Removed FlowNFTs

## [v1.3.0]
### Added
- VestingScheduler v2

## [v1.2.6]
### Changed
- Added native token wrapper address for base-sepolia

## [v1.2.5]
### Changed
- Use superfluid public subgraph endpoints

## [v1.2.3]
### Changed
- Use Goldsky automation subgraphs over The Graph's hosted service ones

## [v1.2.2]
### Added
- Added Base v1 subgraph endpoint

## [v1.2.1]
### Added
- Added Base automation contracts
- Added OP Sepolia automation contracts

## [v1.2.0]
### Changed
- Removed Polygon Mumbai

## [v1.1.30]
### Added
- Degen Chain deployment

## [v1.1.29]
### Fixed
- Removed subgraph hosted endpoint entry for scroll-mainnet which doesn't exist

## [v1.1.28]
### Added
- toga and batchLiquidator for scroll-mainnet
### Changed
- removed eth-goerli and Görli based networks: optimism-goerli, arbitrun-goerli, base-goerli, polygon-zkevm-testnet
### Fixed
- Removed subgraph hosted endpoint entry for scroll-sepolia which doesn't exist

## [v1.1.27]
### Added
- gdaV1 and gdaV1Forwarder for all testnets
### Changed
- loader on those networks (now also loads the gda)
### Fixed
- agreement addresses of scroll-mainnet and scroll-sepolia

## [v1.1.26]
### Added
- gdaV1 and gdaV1Forwarder for several mainnets
### Changed
- loader on those networks (now also loads the gda)

## [v1.1.25]
### Changed
- updated gov contract of scroll-mainnet
### Fixed
- invalid networks.json

## [v1.1.24]
### Changed
- added forwarder addresses for scroll-sepolia, scroll-mainnet
### Fixed
- invalid networks.json

## [v1.1.23]
### Added
- new networks: optimism-sepolia, scroll-sepolia, scroll-mainnet

## [v1.1.22]
### Added
- `cliName` for `base-testnet`

## [v1.1.21]
### Changed
- New contract addresses for Resolver and SuperfluidLoader on xdai-mainnet and polygon-mainnet

## [v1.1.20]
### Changed
- New contract addresses for Resolver and SuperfluidLoader on eth-goerli and polygon-mumbai

## [v1.1.19]
### Added
- `cliName` property under "subgraphV1" for the canonical subgraph network names, see [here](https://thegraph.com/docs/en/developing/supported-networks/#hosted-service)

## [v1.1.18]
### Fixed
- Changed the `module/networks/list.d.ts` file to correctly reflect the `contractsV1` object in our `networks.json` file.

## [v1.1.17]
### Fixed
- Removed `governance` from testnets, changes frequently and can't be reliably kept up to date here
- Removed wrong contract entry for xdai-mainnet

## [v1.1.16]
### Fixed
- Fixed `gdaV1` address for `avalanche-fuji`

## [v1.1.15]
### Fixed
- Fixed `existentialNFTCloneFactory` address for `celo-mainnet`

## [v1.1.14]

### Added
- Added `constantOutflowNFT` and `constantInflowNFT`

## [v1.1.13]
### Added
- Added field `existentialNFTCloneFactory` to contract addresses

## [v1.1.12]
### Added
- Added subgraph endpoints for: Autowrap, FlowScheduler and Vesting contracts

## [v1.1.11]

### Added
- Added addresses of autowrap contracts

### Changed
- Node dependency updates.

## [v1.1.10] - 2023-07-25
### Fixes
- Fixed address of SuperTokenFactory for polygon-zkevm-testnet

## [v1.1.9] - 2023-07-19

### Added
- Added `base-mainnet`

## [v1.1.8] - 2023-07-12

### Changed
- Updated Type info of ContractAddresses and NetworkMetaData
- Renamed `zkevm-testnet` => `polygon-zkevm-testnet`
