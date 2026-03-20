// SPDX-License-Identifier: AGPLv3
pragma solidity ^0.8.23;

import { YieldBackendIntegrationTestBase } from "./YieldBackendIntegrationTestBase.sol";
import { AaveYieldBackend } from "../../../../contracts/superfluid/AaveYieldBackend.sol";
import { IERC20 } from "../../../../contracts/interfaces/superfluid/ISuperfluid.sol";
import { IYieldBackend } from "../../../../contracts/interfaces/superfluid/IYieldBackend.sol";
import { IPool } from "aave-v3/src/contracts/interfaces/IPool.sol";

/**
 * @title AaveYieldBackendIntegrationTest
 * @notice Integration tests for AaveYieldBackend with USDC on Base
 * @author Superfluid
 */
contract AaveYieldBackendIntegrationTest is YieldBackendIntegrationTestBase {
    uint256 internal constant FORK_BLOCK_BASE = 43_400_000;

    // Aave V3 Pool on Base (verified address)
    address internal constant AAVE_POOL = 0xA238Dd80C259a72e81d7e4664a9801593F98d1c5;

    // Common tokens on Base
    address internal constant USDCX = 0xD04383398dD2426297da660F9CCA3d439AF9ce1b; // USDCx on Base
    address internal constant USDC = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913; // USDC on Base
    address internal constant A_USDC = 0x4e65fE4DbA92790696d040ac24Aa414708F5c0AB; // aUSDC on Base

    function _chainId() internal pure override returns (uint256) {
        return 8453;
    }

    function _forkBlockNumber() internal pure override returns (uint256) {
        return FORK_BLOCK_BASE;
    }

    function _rpcUrl() internal view override returns (string memory) {
        return vm.envOr("BASE_MAINNET_ARCHIVE_RPC_URL", string("https://mainnet.base.org"));
    }

    function _superToken() internal pure override returns (address) {
        return USDCX;
    }

    function _underlyingToken() internal pure override returns (address) {
        return USDC;
    }

    function _createBackend() internal override returns (IYieldBackend) {
        return IYieldBackend(address(new AaveYieldBackend(IERC20(_underlyingToken()), IPool(AAVE_POOL), SURPLUS_RECEIVER)));
    }

    function _getYieldAssets(address superToken_) internal view override returns (uint256) {
        return IERC20(A_USDC).balanceOf(superToken_);
    }

    function _assertYieldPositionZeroOrDustAfterDisable() internal view override {
        assertEq(IERC20(A_USDC).balanceOf(address(superToken)), 0, "aUSDC balance should be zero");
    }
}
