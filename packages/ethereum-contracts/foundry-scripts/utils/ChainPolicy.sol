// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

/// @notice Fresh-deployment policy. Upgrades MUST read the existing deployment instead.
/// @dev Matches docs/deployment-inventory.md, including Arc's permissionless apps
/// and the mainnet patrician period (1800, not the old computed 2880).
library ChainPolicy {
    struct Policy {
        uint64 callbackGasLimit;
        bool whitelisting;
        bool idaFrozen;
        uint32 idaSlots;
        uint256 liquidationPeriod;
        uint256 patricianPeriod;
        bool clearForwarderTrusted;
    }

    function get(uint256 chainId) internal pure returns (Policy memory p) {
        bool testnet = chainId == 43113 || chainId == 11155111 || chainId == 11155420
            || chainId == 84532 || chainId == 5042002 || chainId == 31337;
        bool mainnet = chainId == 1 || chainId == 100 || chainId == 137 || chainId == 10
            || chainId == 42161 || chainId == 43114 || chainId == 56 || chainId == 42220
            || chainId == 8453 || chainId == 534352 || chainId == 5042;
        require(testnet || mainnet, "Unsupported chain: add a reviewed ChainPolicy entry first");
        p = Policy(12_000_000, mainnet && chainId != 5042, true, 256,
            testnet ? 3600 : 14400, testnet ? 720 : 1800, mainnet);
        if (chainId == 1 || chainId == 534352) p.callbackGasLimit = 3_000_000;
        if (chainId == 100) p.callbackGasLimit = 8_500_000;
        if (chainId == 43113 || chainId == 43114) p.callbackGasLimit = 7_500_000;
        if (chainId == 10 || chainId == 11155420) {
            p.idaFrozen = false;
            p.idaSlots = 32;
        }
    }

    function guard(Policy memory previous, Policy memory next, bool reviewedOverride) internal pure {
        require(reviewedOverride || next.callbackGasLimit == previous.callbackGasLimit,
            "Callback gas change requires REVIEWED_IMMUTABLE_OVERRIDE=true");
        require(reviewedOverride || next.whitelisting == previous.whitelisting,
            "Whitelisting change requires REVIEWED_IMMUTABLE_OVERRIDE=true");
        require(reviewedOverride || next.idaFrozen == previous.idaFrozen,
            "IDA freeze change requires REVIEWED_IMMUTABLE_OVERRIDE=true");
        require(reviewedOverride || next.idaSlots == previous.idaSlots,
            "IDA slots change requires REVIEWED_IMMUTABLE_OVERRIDE=true");
    }
}
