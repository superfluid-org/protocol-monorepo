# Changelog
All notable changes to the SDK-redux will be documented in this file.

## [Unreleased]

### Added
### Changed
### Fixed

## [0.6.1] - 2024-08-01

### Changed

- sdk-core dependency update

## [0.6.0] - 2023-05-01

### Changed

- Node dependency updates
- Reduce transaction tracking expiration from 10 minutes to 3 minutes

### Added
- Support for `Pool`, `PoolMember` and `PoolDistributor` queries

## [0.5.1] - 2023-05-17

### Added
- Support for `FlowOperator` query

## [0.5.0] - 2023-03-29

### Breaking
- Handle replaced/repriced transaction tracking

### Breaking
- Rename `signer` to `signerAddress`
- Removed `waitForConfirmation`
- Don't export `waitForOneConfirmation`

### Changes
- Use a simpler type for `initiateNewTransactionTrackingThunk.transactionResponse`
- Use `wait` from the TransactionResponse to track the transaction more reliably
- When `trySerializeTransaction` fails, use a warning over an error

## [0.4.0] - 2022-10-31

### Changes
- Fix transaction tracking erroneously registering reverted transactions as successful.
- Allow RTK-query `^1.7.0 || ^1.8.0 || ^1.9.0`

### Breaking
- Require SDK-core version `^0.6.0`
- Pass in `signer` through mutation payload
- Remove `setSignerForSdkRedux`
- Serialized `transactionResponse` is now possibly undefined on `TrackedTransaction` when serialization fails
- Update `@reduxjs/toolkit` & `@superfluid-finance/sdk-core` dependencies

### Added
- Query for transfer events
- Make it possible to pass in Ether's `Overrides` object through mutations
- Add `accountTokenSnapshotLog` & `tokenStatisticLog` endpoints
- Add `isSubgraphInSync` & `blockTransactionSucceededIn` to a tracked transaction
- Export `getSerializeQueryArgs` & `CacheTagTypes`

## [0.3.0] - 2022-04-13

### Many changes and additions

- Rename mutations and queries for better ordering in source/file explorers:
  - For example, "CreateFlow" renamed to "FlowCreateMutation" to go along with "FlowUpdateMutation" and "FlowDeleteMutation" etc
- "MonitorForEventsToInvalidateCache" moved to Subgraph API slice because it uses Subgraph, not an RPC
- Removed `sfApi` completely which combined Subgraph & RPC endpoints. Replaced by leaving just `subgraphApi` (only Subgraph as data source) & `rpcApi` (only RPC as data source)
- Redux slices are required to be set up using `*slice*.reducerPath` syntax
- Tracked transactions can now contain user defined extra data (see `*tracked transactin*.extraData`) which can be specified through the invoked mutation
- `userData` can now be specified through flow mutations
- Tracked transactions now have titles to identify the intent by
- Make it possible to initiate transaction tracking for old pending transactions (see `initiateOldPendingTransactionsTrackingThunk`)
- Transaction tracking invalidates RPC slice and Subgraph slice separately
  - RPC is invalidated in its entirety for now
  - Subgraph is polled for the block events of the successful transaction to invalidate the slice normally (based on the event type and its data)
- Save timestamp on the tracked transaction of when tracking started
- Simplify caching logic to just "GENERAL" & "SPECIFIC" tags (NOTE: cache tagging mechanism and the invalidation mechanism need more work)
  - The idea behind the simplified chaching logic is that sometimes we need to _force_ invalidate the whole chain or the whole token cache. That's then we use the _general_ tag for invalidation. As a rule of thumb, all queries _should_ provide general cache tags. Other times, when we're listening to the blockchain and only want to invalidate specific parts and not _over_ invalidate the cache, then we use the _specific_ cache tags.

## [0.2.2] - 2022-03-16

### Added

- Bump sdk-core version to include "optimism-mainnet" and "arbitrum-one" support.
- Change sdk-core peer dependency to allow patched updates.

## [0.2.1] - 2022-02-16

### Added

- Using SDK-Core@v0.3.1, SDK-core bug fix propagated to SDK-redux

## [0.2.0] - 2022-02-01

### Added
- Introduce new Redux slice `sfSubgraph` ([#571])
- Support improved querying functionality
  - Query all the Subgraph entities with all the possible filters and ordering capabilities

## [0.1.0] - 2021-12-01

### Added

- Initial preview version of SDK-Redux
- Features:
  - Wrap SDK-Core with Redux's RTK-Query to enable cache'ing of queries
    - Auto-generate React Hooks
    - Tracking loading state in order to show UI spinners
    - Tracking broadcasted transactions for UI notifications and data updates
    - Managing cache lifetimes
    - Avoiding duplicate requests for the same data
    - Monitoring blockchain events for data updates (including re-orgs)
    - Handle errors and offer user opportunity to retry


[0.2.1]: https://github.com/superfluid-finance/protocol-monorepo/compare/sdk-redux%40v0.2.0...sdk-redux%40v0.2.1
[0.2.0]: https://github.com/superfluid-finance/protocol-monorepo/compare/sdk-redux%40v0.1.0...sdk-redux%40v0.2.0
[0.1.0]: https://github.com/superfluid-finance/protocol-monorepo/releases/tag/sdk-redux%40v0.1.0


[#571]: https://github.com/superfluid-finance/protocol-monorepo/pull/571
