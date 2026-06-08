// SPDX-License-Identifier: AGPLv3
pragma solidity ^0.8.23;

import { YieldBackendUnitTestBase } from "./YieldBackendUnitTestBase.sol";
import { ERC4626YieldBackend } from "../../../../contracts/superfluid/ERC4626YieldBackend.sol";
import { IYieldBackend } from "../../../../contracts/interfaces/superfluid/IYieldBackend.sol";
import { IERC20 } from "../../../../contracts/interfaces/superfluid/ISuperfluid.sol";
import { IERC4626 } from "@openzeppelin-v5/contracts/interfaces/IERC4626.sol";

/**
 * @title Unit tests for ERC4626YieldBackend with Spark USDS on Ethereum
 * Tests the backend in isolation using delegatecall
 */
contract ERC4626YieldBackendUnitTestEthereumSUSDS is YieldBackendUnitTestBase {
    uint256 internal constant CHAIN_ID = 1;
    address internal constant VAULT = 0xa3931d71877C0E7a3148CB7Eb4463524FEc27fbD; // sUSDS on Ethereum

    ERC4626YieldBackend internal erc4626Backend;

    function getRpcUrl() internal view override returns (string memory) {
        return vm.envOr("ETH_MAINNET_ARCHIVE_RPC_URL", string("https://eth.drpc.org"));
    }

    function getChainId() internal pure override returns (uint256) {
        return CHAIN_ID;
    }

    /// @notice toUnderlyingAmount for USDS (18 decimals) - uses base implementation
    /// @dev No override needed, USDS has 18 decimals like SuperToken

    function createBackend() internal override returns (IYieldBackend) {
        erc4626Backend = new ERC4626YieldBackend(
            IERC4626(VAULT),
            SURPLUS_RECEIVER
        );
        return IYieldBackend(address(erc4626Backend));
    }

    function getAssetToken() internal view override returns (IERC20) {
        return IERC20((IERC4626(VAULT)).asset());
    }

    function fundTestContract() internal override {
        // Fund with 10M USDS (18 decimals)
        deal(address(getAssetToken()), address(this), 10_000_000 * 1e18);
    }

    function getAssetDecimals() internal pure override returns (uint8) {
        return 18; // USDS has 18 decimals
    }

    function _getProtocolAddress() internal pure override returns (address) {
        return VAULT;
    }
}

/**
 * @title Unit tests for ERC4626YieldBackend with sUSDC Vault on Base
 * Tests the backend in isolation using delegatecall
 */
contract ERC4626YieldBackendUnitTestBaseSUSDC is YieldBackendUnitTestBase {
    uint256 internal constant CHAIN_ID = 8453;
    address internal constant VAULT = 0x3128a0F7f0ea68E7B7c9B00AFa7E41045828e858; // sUSDC Vault on Base

    ERC4626YieldBackend internal erc4626Backend;

    function getRpcUrl() internal view override returns (string memory) {
        return vm.envOr("BASE_MAINNET_ARCHIVE_RPC_URL", string("https://mainnet.base.org"));
    }

    function getChainId() internal pure override returns (uint256) {
        return CHAIN_ID;
    }

    /// @notice Override toUnderlyingAmount for USDC (6 decimals)
    function toUnderlyingAmount(uint256 amount)
        external
        pure
        override
        returns (uint256 underlyingAmount, uint256 adjustedAmount)
    {
        // USDC has 6 decimals, SuperToken has 18 decimals
        uint256 factor = 10 ** (18 - 6);
        underlyingAmount = amount / factor;
        adjustedAmount = underlyingAmount * factor;
    }

    function createBackend() internal override returns (IYieldBackend) {
        erc4626Backend = new ERC4626YieldBackend(
            IERC4626(VAULT),
            SURPLUS_RECEIVER
        );
        return IYieldBackend(address(erc4626Backend));
    }

    function getAssetToken() internal view override returns (IERC20) {
        return IERC20((IERC4626(VAULT)).asset());
    }

    function fundTestContract() internal override {
        // Fund with 10M USDC (6 decimals)
        deal(address(getAssetToken()), address(this), 10_000_000 * 1e6);
    }

    function getAssetDecimals() internal pure override returns (uint8) {
        return 6; // USDC has 6 decimals
    }

    function _getProtocolAddress() internal pure override returns (address) {
        return VAULT;
    }
}

