// SPDX-License-Identifier: AGPLv3
pragma solidity ^0.8.23;

import { YieldBackendUnitTestBase } from "./YieldBackendUnitTestBase.sol";
import { YieldBackendForkConstants } from "./YieldBackendForkConstants.sol";
import { AaveYieldBackend } from "../../../../contracts/superfluid/AaveYieldBackend.sol";
import { IYieldBackend } from "../../../../contracts/interfaces/superfluid/IYieldBackend.sol";
import { IERC20 } from "../../../../contracts/interfaces/superfluid/ISuperfluid.sol";
import { IPool } from "aave-v3/src/contracts/interfaces/IPool.sol";

/**
 * @title Unit tests for AaveYieldBackend with USDC on Base
 * Tests the backend in isolation using delegatecall
 */
contract AaveYieldBackendUnitTest is YieldBackendUnitTestBase {
    address internal constant AAVE_POOL = 0xA238Dd80C259a72e81d7e4664a9801593F98d1c5;
    address internal constant USDC = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;

    AaveYieldBackend internal aaveBackend;

    function getRpcUrl() internal view override returns (string memory) {
        return vm.envOr("BASE_MAINNET_ARCHIVE_RPC_URL", string("https://mainnet.base.org"));
    }

    function getChainId() internal pure override returns (uint256) {
        return YieldBackendForkConstants.CHAIN_ID_BASE;
    }

    function getForkBlockNumber() internal pure override returns (uint256) {
        return YieldBackendForkConstants.FORK_BLOCK_BASE;
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
        aaveBackend = new AaveYieldBackend(
            IERC20(USDC),
            IPool(AAVE_POOL),
            SURPLUS_RECEIVER
        );
        return IYieldBackend(address(aaveBackend));
    }

    function getAssetToken() internal pure override returns (IERC20) {
        return IERC20(USDC);
    }

    function fundTestContract() internal override {
        // Fund with 200M USDC (6 decimals)
        deal(USDC, address(this), 200_000_000 * 1e6);
    }

    function getAssetDecimals() internal pure override returns (uint8) {
        return 6;
    }

    function _getProtocolAddress() internal pure override returns (address) {
        return AAVE_POOL;
    }
}

