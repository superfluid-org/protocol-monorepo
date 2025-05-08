# Changelog

All notable changes to the Subgraph will be documented in this file.

This project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [2.2.0]

- Fix missing Token name/symbol in some cases
- Fix Pool's `totalAmountDistributed` being wrong in some cases
- Add `adminOfPoolCount` to AccountTokenSnapshot to count how many pools the account is admin of
- Add `balanceLastUpdatedFromRpcBlocknumber` to AccountTokenSnapshot to track when last RPC call was made
- Don't always make an RPC call when updating the balance of an AccountTokenSnapshot, use the balance delta for simple cases
- Account for GDA's adjustment flow when setting the `isLiquidationEstimateOptimistic` flag on AccountTokenSnapshot

## [2.1.0]

## Breaking

- Removed FlowNFT related entities and attributes

## [2.0.0]

### Changed
- Enabled history pruning which disables perfect time-travel queries.

## [1.7.1] - 2024-04-22

### Added
- Support for vendor "airstack"

### Fixes
- Various GDA related fixes

## [1.7.0] - 2024-02-05

### Added
- NFT specific event entities
- GDA event entities
- GDA HOL entities
- New properties on aggregate entities to distinguish between CFA and GDA data where applicable
- `scripts/buildNetworkConfig.ts` added for building network config from metadata in place of hardcoded config json files
- `getHostedServiceNetworks.ts` added for getting the list of networks in place of hardcoded `networks.json`, improves maintenance + adding

## [1.6.1] - 2023-08-15

### Added
- `totalNumberOfAccounts` and `totalNumberOfHolders` added to `TokenStatistic` and `TokenStatisticLog` entities

## [1.6.0] - 2023-07-13

## Changed

-   Deployment bash scripts refactored to explicitly handle subgraphs deployed to hosted service vs. satsuma

## Added

-   `SuperTokenMinimumDepositChangedEvent` event entity
-   `userData` property added to `Stream` HOL entity
-   `TokenGovernanceConfig` HOL entity added
-   `activeOutgoingStreamCount`, `activeIncomingStreamCount`, `inactiveOutgoingStreamCount` and `inactiveIncomingStreamCount` properties added to `AccountTokenSnapshot` aggregate entity

### Added

## [1.5.0] - 2022-12-19

## Added

-   TOGA events added
-   `gasUsed` property on event entities
-   `mostRecentStream` on `StreamRevision` entity
-   data integrity tests: validates subgraph data against blockchain data (RPC calls)
-   balance validation: validates feature subgraph balance data against v1 subgraph balance data
-   Implemented Matchstick Unit tests in favor of slowly deprecating integration tests
-   Added support for Satsuma deployment

## Changed

-   Updated README given all the changes
-   Moved over from ganache to hardhat running tests
-   Using docker-compose instead of graph-node fork for integration tests
-   Updated `schema.graphql` documentation
-   Removed hardcoded addresses and utilize new `deploy-test-framework` script
-   Simplified `addresses.template.ts`
-   Bumped specVersion (0.0.3 => 0.0.5) and apiVersion (0.0.6 => 0.0.7) in manifest file (`subgraph.template.yaml`) and include receipts in eventHandlers
-   Removed unnecessary `test-subgraph.template.yaml` duplicate file

## Fixes

-   Minor mapping fixes

## [1.4.5] - 2022-07-26

## Added

-   Support for `arbitrum-goerli`, `optimism-goerli` added

## Breaking

-   Support for `kovan`, `arbitrum-rinkeby`, `optimism-kovan` removed

## [1.4.5] - 2022-07-26

### Added

-   isNativeAssetSuperToken property added to Token entity

## [1.4.4] - 2022-07-12

### Added

-   Handle `Set` event from Resolver contract
-   New `SetEvent` and `ResolverEntry` entities

### Fixes

-   Handles unlisting of tokens in resolver

## [1.4.3] - 2022-06-30

### Breaking

-   `totalAmountStreamedUntilUpdatedAt` on `AccountTokenSnapshot` and `totalAmountStreamed` on `AccountTokenSnapshotLog` are no longer calculating the total amount streamed out from an account, but the net amount streamed through an account
    -   Migration: replace this with `totalAmountStreamedOutUntilUpdatedAt` and `totalAmountStreamedOut`, respectively

### Added

-   `gasPrice` added to event entities
-   `governanceAddress` added to governance related entities
-   `totalAmountStreamedInUntilUpdatedAt`, `totalAmountStreamedOutUntilUpdatedAt` added to `AccountTokenSnapshot`
-   `totalAmountStreamedIn`, `totalAmountStreamedOut` added to `AccountTokenSnapshotLog`
-   `TokenStatisticLog` entity added

### Fixes

-   GovernanceAddress is no longer hardcoded and subgraph detects new events from newly set governance contracts
-   `token` property added to `BurnedEvent`, `MintedEvent` and `SentEvent`

## [1.4.2] - 2022-06-29

### Added

-   BNB Chain support added

## [1.4.1] - 2022-06-11

### Changed

-   `maybeCriticalAtTimestamp` is nullable

### Fixes

-   Add back deprecated `rewardAccount` field on `AgreementLiquidatedV2Event` entity (use `rewardAmountReceiver`)

## [1.4.0] - 2022-05-31

### Breaking

-   `rewardAccount` renamed to `rewardAmountReceiver` on `AgreementLiquidatedV2Event` entity

### Fixes

-   Was not properly updating `updatedAtTimestamp` and `updatedAtBlockNumber`
-   Wasn't updating `totalAmountStreamedUntilUpdatedAt` for `TokenStats` whenever it was updated for `AccountTokenSnapshot`

### Changed

-   README updated to remove dead legacy endpoints, new v1/dev endpoints added
-   Subgraph tests use hardhat node, config changed in `hardhat.config.ts`

### Added

-   Script to check if subgraph is deployed on every network
-   `logIndex` and `order` properties added to all `Event` entities
-   `maybeCriticalAtTimestamp` and `isLiquidationEstimateOptimistic` properties added to `AccountTokenSnapshot` entity
-   `AccountTokenSnapshotLog` entity added (created on every update to `AccountTokenSnapshot`)
-   Tests added for new properties/entities
-   Tests fixed up given subgraph logic

## [1.3.4] - 2022-05-16

### Added

-   Avalanche C-Chain network support

## [1.3.3] - 2022-05-13

### Changed

-   Removed tests as they were not catching the [issue](https://github.com/graphprotocol/graph-node/issues/3553)

### Fixes

-   Removed (immutable: true) from `FlowOperatorUpdated` entity - No operators should

## [1.3.2] - 2022-05-11

### Changed

-   Zero address `Account` and `AccountTokenSnapshot` entities are not filtered out

### Fixes

-   Global `events` query fixed: global `events` query was breaking due to the `FlowUpdatedEvent` entity implementing the `Event` interface, but not having the immutable property like the other events
-   `AccountTokenSnapshot` query with `account { id }` fixed. Was breaking due to faulty logic of creating an `AccountTokenSnapshot` without creating an `Account` entity
-   Tests added to ensure this will be caught

## [1.3.1] - 2022-05-06

### Changed

-   Most event entities are immutable (except FlowUpdated)

### Added

-   New Access Control List (ACL) entities and properties added
    -   `FlowOperator` entity
    -   `flowOperator` property
    -   `deposit` and `totalDeposit` properties added to entities

### Fixes

-   Properly handle zero address throughout

## [1.3.0] - 2022-05-04

### Changed

-   Package updates (#550, #604)
-   Subgraph tests use `sdk-core` instead of `js-sdk` and general refactoring (#594, #621)

### Added

-   Subgraph supports new entities: `PPPConfigurationChangedEvent`, `AgreementLiquidatedV2Event` (#558)
-   Added complementary liquidation tests

### Fixed

-   +1 to `getRandomFlowRate` so flowRate is never 0 (#538)
-   `getLiquidations` script null case fix (#557)
-   handle updating of total supply for native super token (#584)

## [1.2.0] - 2021-12-13

### Added

-   Support for new test networks: `arbitrum-rinkeby`, `optimism-kovan` and `avalanche-fuji`.

## [1.1.1] - 2021-11-30

### Added

-   from property onto SentEvent (#493)
    Subgraph sfmeta entity (#491)

### Changed

-   Subgraph test added to canary build (#512)
-   using js-sdk@0.5.7
-   update subgraph dependency versions (target minor) (#509)

### Fixed

ci cd cleanup (#500)

-   single network deploy implemented (#506)

### Breaking

-   Due to subgraph schema version upgrades, isSet is now also a reserved keyword in the schema. Superfluid events
    that had isSet argument are all changed to using isKeySet instead.
    -   Migration: use `isKeySet` instead

## [1.1.0] - 2021-11-15

### Added

-   Add stream period entity
-   Name and addresses properties added to event entities

### Changed

-   Subgraph v1 underlying token added to Token entity
-   Decimals and underlying token added to Token entity
-   Tests added for new entity and properties: StreamPeriod entity, name and addresses properties on events, decimal and underlyingToken properties on Token

## [1.0.0] - 2021-10-29

### Added

-   Complete set of Superfluid event entities
-   HOL (Higher order level) entities
-   Aggregate entities
-   System testing suite for all entities
-   Shiny new docs coming to you soon
