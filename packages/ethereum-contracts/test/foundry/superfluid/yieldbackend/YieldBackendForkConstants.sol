// SPDX-License-Identifier: AGPLv3
pragma solidity ^0.8.23;

/**
 * @title YieldBackendForkConstants
 * @notice Shared pinned fork blocks for yield-backend unit and integration tests.
 * @dev Pin blocks so fork tests are stable as on-chain protocol state evolves.
 */
library YieldBackendForkConstants {
    uint256 internal constant CHAIN_ID_ETHEREUM = 1;
    uint256 internal constant CHAIN_ID_BASE = 8453;

    /// @notice Pinned fork block for Ethereum mainnet yield-backend fork tests
    uint256 internal constant FORK_BLOCK_ETHEREUM = 24_670_000;

    /// @notice Pinned fork block for Base mainnet yield-backend fork tests
    uint256 internal constant FORK_BLOCK_BASE = 43_400_000;
}
