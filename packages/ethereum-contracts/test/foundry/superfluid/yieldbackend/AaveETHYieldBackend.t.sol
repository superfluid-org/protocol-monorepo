// SPDX-License-Identifier: AGPLv3
pragma solidity ^0.8.23;

import { YieldBackendUnitTestBase } from "./YieldBackendUnitTestBase.sol";
import { AaveETHYieldBackend } from "../../../../contracts/superfluid/AaveETHYieldBackend.sol";
import { IYieldBackend } from "../../../../contracts/interfaces/superfluid/IYieldBackend.sol";
import { IERC20 } from "../../../../contracts/interfaces/superfluid/ISuperfluid.sol";
import { IPool } from "aave-v3/src/contracts/interfaces/IPool.sol";

/**
 * @title tests for AaveETHYieldBackend with ETH/WETH on Base
 * Tests the backend in isolation using delegatecall
 */
contract AaveETHYieldBackendUnitTest is YieldBackendUnitTestBase {
    uint256 internal constant CHAIN_ID = 8453;
    string internal constant RPC_URL = "https://mainnet.base.org";

    address internal constant AAVE_POOL = 0xA238Dd80C259a72e81d7e4664a9801593F98d1c5;
    address internal constant WETH = 0x4200000000000000000000000000000000000006;

    AaveETHYieldBackend internal aaveETHBackend;

    function getRpcUrl() internal pure override returns (string memory) {
        return RPC_URL;
    }

    function getChainId() internal pure override returns (uint256) {
        return CHAIN_ID;
    }

    /// @notice toUnderlyingAmount for ETH (18 decimals) - uses base implementation
    /// @dev No override needed, ETH has 18 decimals like SuperToken

    function createBackend() internal override returns (IYieldBackend) {
        aaveETHBackend = new AaveETHYieldBackend(
            IPool(AAVE_POOL),
            SURPLUS_RECEIVER
        );
        return IYieldBackend(address(aaveETHBackend));
    }

    function getAssetToken() internal pure override returns (IERC20) {
        // For AaveETHYieldBackend, the asset token is WETH
        return IERC20(WETH);
    }

    function fundTestContract() internal override {
        // Fund with ETH (will be wrapped to WETH on deposit)
        vm.deal(address(this), 10_000 ether);
    }

    function getAssetDecimals() internal pure override returns (uint8) {
        return 18; // ETH/WETH has 18 decimals
    }

    function _getProtocolAddress() internal pure override returns (address) {
        return AAVE_POOL;
    }

    /// @notice Override _boundAmount to ensure minimum viable amounts for ETH
    /// @dev Aave may have minimum deposit requirements, so we use a higher minimum
    function _boundAmount(uint256 amount) internal pure override returns (uint256) {
        // Minimum: 0.001 ETH (1e15 wei) to avoid issues with very small amounts
        // Maximum: 1000 ETH
        uint256 minAmount = 1e15; // 0.001 ETH
        uint256 maxAmount = 1000 * 1e18; // 1000 ETH
        return bound(amount, minAmount, maxAmount);
    }

    /// @notice Override _fundAsset to handle ETH (native token)
    function _fundAsset(uint256 amount) internal override {
        // Ensure we have at least the amount in ETH
        uint256 currentBalance = address(this).balance;
        if (currentBalance < amount) {
            vm.deal(address(this), amount);
        }
    }

    /// @notice Override _getAssetBalance to handle ETH balance
    /// @dev For ETH backend, we track ETH balance (not WETH)
    /// @dev Before deposit: ETH balance
    /// @dev After deposit: ETH is wrapped and deposited, so ETH balance decreases
    /// @dev After withdraw: ETH is unwrapped back, so ETH balance increases
    function _getAssetBalance() internal view override returns (uint256) {
        // Track ETH balance directly (the native token)
        // WETH is just an intermediate step in the deposit/withdraw process
        return address(this).balance;
    }

    /// @notice Override _getSurplusReceiverBalance for WETH
    function _getSurplusReceiverBalance() internal view override returns (uint256) {
        // Note: Surplus is paid in WETH, not ETH
        // Use assetToken (IERC20) which has balanceOf
        return assetToken.balanceOf(SURPLUS_RECEIVER);
    }

    /// @notice Allow the test contract to receive ETH
    /// @dev Required for unwrapWETHAndForwardETH to send ETH back to the test contract
    receive() external payable { }
}

