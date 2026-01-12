// SPDX-License-Identifier: AGPLv3
pragma solidity ^0.8.23;

import { Test } from "forge-std/Test.sol";
import { AaveYieldBackend } from "../../../../contracts/superfluid/AaveYieldBackend.sol";
import { IERC20, ISuperfluid } from "../../../../contracts/interfaces/superfluid/ISuperfluid.sol";
import { SuperToken } from "../../../../contracts/superfluid/SuperToken.sol";
import { IPool } from "aave-v3/src/contracts/interfaces/IPool.sol";

/**
 * @title AaveYieldBackendIntegrationTest
 * @notice Integration tests for AaveYieldBackend with USDC on Base
 * @author Superfluid
 */
contract AaveYieldBackendIntegrationTest is Test {
    address internal constant ALICE = address(0x420);
    address internal constant ADMIN = address(0xAAA);

    // Base network constants
    uint256 internal constant CHAIN_ID = 8453;
    string internal constant RPC_URL = "https://mainnet.base.org";

    // Aave V3 Pool on Base (verified address)
    address internal constant AAVE_POOL = 0xA238Dd80C259a72e81d7e4664a9801593F98d1c5;

    // Common tokens on Base
    address internal constant USDCX = 0xD04383398dD2426297da660F9CCA3d439AF9ce1b; // USDCx on Base
    address internal constant USDC = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913; // USDC on Base
    address internal constant A_USDC = 0x4e65fE4DbA92790696d040ac24Aa414708F5c0AB; // aUSDC on Base
    address internal constant SURPLUS_RECEIVER = 0xac808840f02c47C05507f48165d2222FF28EF4e1; // dao.superfluid.eth

    /// Rounding tolerance for Aave deposit/withdraw operations (in wei)
    uint256 internal constant AAVE_ROUNDING_TOLERANCE = 2;

    SuperToken public superToken;
    AaveYieldBackend public aaveBackend;
    IERC20 public underlyingToken;
    IPool public aavePool;
    /// Initial excess underlying balance (underlyingBalance - normalizedTotalSupply)
    uint256 public initialExcessUnderlying;

    /// @notice Set up the test environment by forking the chain and deploying AaveYieldBackend
    function setUp() public {
        vm.createSelectFork(RPC_URL);

        // Verify chain id
        assertEq(block.chainid, CHAIN_ID, "Chainid mismatch");

        // Get Aave Pool
        aavePool = IPool(AAVE_POOL);

        // Set up USDC
        underlyingToken = IERC20(USDC);
        superToken = SuperToken(USDCX);

        // Deploy AaveBackend
        aaveBackend = new AaveYieldBackend(IERC20(USDC), IPool(AAVE_POOL), SURPLUS_RECEIVER);

        // upgrade SuperToken to new logic (including the yield backend related code)
        SuperToken newSuperTokenLogic = new SuperToken(ISuperfluid(superToken.getHost()), superToken.POOL_ADMIN_NFT());
        vm.startPrank(address(superToken.getHost()));
        superToken.updateCode(address(newSuperTokenLogic));
        vm.stopPrank();

        // designate an admin for the SuperToken
        vm.startPrank(address(superToken.getHost()));
        superToken.changeAdmin(ADMIN);
        vm.stopPrank();

        // provide ALICE with underlying and let her approve for upgrade
        deal(USDC, ALICE, type(uint128).max);
        vm.startPrank(ALICE);
        IERC20(USDC).approve(address(superToken), type(uint256).max);
        vm.stopPrank();

        // Calculate and store initial excess underlying balance
        // The underlying balance may be greater than totalSupply due to rounding or initial state
        uint256 underlyingBalance = IERC20(USDC).balanceOf(address(superToken));
        (uint256 normalizedTotalSupply,) = superToken.toUnderlyingAmount(superToken.totalSupply());

        // assert that the underlying balance is equal or greater than total supply (aka the SuperToken is solvent)
        assertGe(
            underlyingBalance,
            normalizedTotalSupply,
            "underlyingBalance should be >= normalizedTotalSupply"
        );
        initialExcessUnderlying = underlyingBalance - normalizedTotalSupply;
    }

    function _enableYieldBackend() public {
        vm.startPrank(ADMIN);
        superToken.enableYieldBackend(aaveBackend);
        vm.stopPrank();
    }

    /// @notice Verify invariants for the SuperToken yield backend system
    /// @param preserveInitialExcess If true, expect initial excess to be preserved (not withdrawn as surplus)
    /// @param numAaveOperations Number of Aave deposit/withdraw operations that have occurred
    function _verifyInvariants(bool preserveInitialExcess, uint256 numAaveOperations) internal view {
        // underlyingBalance + aTokenBalance >= superToken.supply() [+ initialExcessUnderlying if preserved]
        // Allow for Aave rounding tolerance (may lose up to 2 wei per operation)
        uint256 underlyingBalance = IERC20(USDC).balanceOf(address(superToken));
        uint256 aTokenBalance = IERC20(A_USDC).balanceOf(address(superToken));
        (uint256 superTokenNormalizedSupply,) = superToken.toUnderlyingAmount(superToken.totalSupply());

        uint256 expectedMinTotalAssets = preserveInitialExcess
            ? superTokenNormalizedSupply + initialExcessUnderlying
            : superTokenNormalizedSupply;
        uint256 totalAssets = underlyingBalance + aTokenBalance;
        
        // Calculate total tolerance based on number of operations
        uint256 totalTolerance = numAaveOperations * AAVE_ROUNDING_TOLERANCE;
        
        // Add tolerance to actual to avoid underflow, equivalent to: actual >= expected - tolerance
        assertGe(
            totalAssets + totalTolerance,
            expectedMinTotalAssets,
            preserveInitialExcess
                ? "invariant failed: total assets should be >= supply + initial excess (accounting for rounding)"
                : "invariant failed: total assets should be >= supply (accounting for rounding)"
        );
    }

    /// @notice Test enabling yield backend
    function testEnableYieldBackend() public {
        // Record state before enabling
        uint256 underlyingBalanceBefore = IERC20(USDC).balanceOf(address(superToken));
        (uint256 normalizedTotalSupplyBefore,) = superToken.toUnderlyingAmount(superToken.totalSupply());
        uint256 expectedUnderlyingBefore = normalizedTotalSupplyBefore + initialExcessUnderlying;
        
        // Verify initial state
        assertGe(
            underlyingBalanceBefore,
            expectedUnderlyingBefore,
            "initial underlying should be >= supply + initial excess"
        );

        _enableYieldBackend();

        assertEq(address(superToken.getYieldBackend()), address(aaveBackend), "Yield backend mismatch");

        // the SuperToken should now have a zero USDC balance (all deposited)
        assertEq(IERC20(USDC).balanceOf(address(superToken)), 0, "USDC balance should be zero");
        
        uint256 aTokenBalanceAfter = IERC20(A_USDC).balanceOf(address(superToken));
        assertGe(
            aTokenBalanceAfter,
            underlyingBalanceBefore - AAVE_ROUNDING_TOLERANCE,
            "aUSDC balance should match previous underlying balance"
        );
        
        // The aToken balance should approximately match what was deposited
        // Account for initial excess and potential rounding in Aave
        assertGe(
            aTokenBalanceAfter,
            expectedUnderlyingBefore - 1000, // Allow some rounding tolerance
            "aToken balance should approximately match deposited amount"
        );

        // 1 operation: enable deposits all existing underlying
        _verifyInvariants(true, 1);
    }

    /// @notice Test disabling yield backend
    function testDisableYieldBackend() public {
        // verify: underlying >= totalSupply (with initial excess accounted for)
        uint256 underlyingBalanceBefore = IERC20(USDC).balanceOf(address(superToken));
        uint256 superTokenBalanceBefore = superToken.totalSupply();
        (uint256 normalizedTotalSupply,) = superToken.toUnderlyingAmount(superTokenBalanceBefore);
        uint256 expectedUnderlying = normalizedTotalSupply + initialExcessUnderlying;
        assertGe(
            underlyingBalanceBefore,
            expectedUnderlying,
            "precondition failed: underlyingBalanceBefore should be >= supply + initial excess"
        );

        _enableYieldBackend();

        vm.startPrank(ADMIN);
        superToken.disableYieldBackend();
        vm.stopPrank();
        assertEq(address(superToken.getYieldBackend()), address(0), "Yield backend mismatch");

        // the SuperToken should now have a non-zero USDC balance and a zero aUSDC balance
        uint256 underlyingBalanceAfter = IERC20(USDC).balanceOf(address(superToken));
        assertGt(underlyingBalanceAfter, 0, "USDC balance should be non-zero");
        assertEq(IERC20(A_USDC).balanceOf(address(superToken)), 0, "aUSDC balance should be zero");

        // After disabling, underlying balance should be at least the amount we had in aTokens + initial excess
        // (the aTokens were converted back to underlying)
        // Allow for Aave rounding tolerance (may lose up to 2 wei)
        // Add tolerance to actual to avoid underflow
        assertGe(
            underlyingBalanceAfter + AAVE_ROUNDING_TOLERANCE,
            expectedUnderlying,
            "underlying balance after disable should be >= original underlying + initial excess"
        );

        // 2 operations: enable deposits + disable withdraws
        _verifyInvariants(true, 2);
    }

    /// @notice Test upgrade and downgrade with fuzzed amount
    function testUpgradeDowngrade(uint256 amount) public {
        // Bound amount to reasonable range
        // USDC has 6 decimals, SuperToken has 18 decimals
        // Minimum: 1 USDC (1e6) = 1e18 SuperToken units
        // Maximum: 1M USDC (1e6 * 1e6) = 1e24 SuperToken units
        amount = bound(amount, 1e18, 1_000_000 * 1e18);

        _enableYieldBackend();

        vm.startPrank(ALICE);
        superToken.upgrade(amount);
        vm.stopPrank();

        // Downgrade
        vm.startPrank(ALICE);
        // Note: upgrade may have down-rounded the amount, but doesn't tell us (via return value).
        // In that case a consecutive downgrade (of the un-adjusted amount) might revert.
        // For fuzzing, we downgrade the actual balance ALICE received
        uint256 aliceBalance = superToken.balanceOf(ALICE);
        superToken.downgrade(aliceBalance);
        vm.stopPrank();

        // 3 operations: enable deposits + upgrade deposits + downgrade withdraws
        _verifyInvariants(true, 3);
    }

    /// @notice Test withdrawing surplus due to excess underlying balance
    function testWithdrawSurplusFromYieldBackendExcessUnderlying() public {
        _enableYieldBackend();

        // Upgrade tokens to create supply
        uint256 upgradeAmount = 1000 * 1e18;
        vm.startPrank(ALICE);
        superToken.upgrade(upgradeAmount);
        vm.stopPrank();

        // Manually add excess underlying to SuperToken to simulate surplus
        // This could happen if someone accidentally sends tokens to the SuperToken
        uint256 surplusAmount = 100 * 1e6; // 100 USDC
        deal(USDC, address(superToken), surplusAmount);

        uint256 receiverBalanceBefore = IERC20(USDC).balanceOf(SURPLUS_RECEIVER);
        uint256 underlyingBalanceBefore = IERC20(USDC).balanceOf(address(superToken));
        uint256 aTokenBalanceBefore = IERC20(A_USDC).balanceOf(address(superToken));

        // Verify there is excess underlying
        (uint256 normalizedTotalSupply,) = superToken.toUnderlyingAmount(superToken.totalSupply());
        uint256 totalAssetsBefore = underlyingBalanceBefore + aTokenBalanceBefore;
        assertGt(
            totalAssetsBefore,
            normalizedTotalSupply + 100, // withdrawSurplus uses -100 margin
            "Precondition: excess underlying should exist"
        );

        vm.startPrank(ADMIN);
        superToken.withdrawSurplusFromYieldBackend();
        vm.stopPrank();

        uint256 receiverBalanceAfter = IERC20(USDC).balanceOf(SURPLUS_RECEIVER);

        // Surplus should be withdrawn to receiver
        uint256 surplusWithdrawn = receiverBalanceAfter - receiverBalanceBefore;
        assertGt(surplusWithdrawn, 0, "Surplus should be withdrawn to receiver");
        // The surplus withdrawn should be approximately the excess (minus 100 wei margin)
        assertGe(
            surplusWithdrawn,
            surplusAmount - 200,
            "Surplus withdrawn should be approximately the excess"
        );
        
        // After withdrawing surplus, initial excess is also withdrawn, so don't expect it to be preserved
        // 3 operations: enable deposits + upgrade deposits + withdraw surplus
        _verifyInvariants(false, 3);
    }

    /// @notice Test withdrawing surplus generated by yield protocol (fast forward time)
    function testWithdrawSurplusFromYieldBackendYieldAccrued(uint256 timeForward) public {
        // Bound time forward between 1 hour and 365 days
        timeForward = bound(timeForward, 1 hours, 365 days);

        _enableYieldBackend();

        // Record initial state before yield accrual
        (uint256 normalizedTotalSupplyInitial,) = superToken.toUnderlyingAmount(superToken.totalSupply());

        // Fast forward time to accrue yield in Aave
        vm.warp(block.timestamp + timeForward);

        // Calculate total supply after time forward (should be unchanged)
        (uint256 normalizedTotalSupply,) =
            superToken.toUnderlyingAmount(superToken.totalSupply());
        assertEq(
            normalizedTotalSupply,
            normalizedTotalSupplyInitial,
            "Total supply should not change from time forward"
        );

        uint256 receiverBalanceBefore = IERC20(USDC).balanceOf(SURPLUS_RECEIVER);
        uint256 underlyingBalanceBefore = IERC20(USDC).balanceOf(address(superToken));
        uint256 aTokenBalanceBefore = IERC20(A_USDC).balanceOf(address(superToken));

        // Total assets should be greater than supply due to yield accrual
        // Note: Aave yield accrues by increasing the underlying value of aTokens over time
        uint256 totalAssetsBefore = underlyingBalanceBefore + aTokenBalanceBefore;
        
        // Check if there's actually surplus to withdraw (after the 100 wei margin used in withdrawSurplus)
        bool hasSurplus = totalAssetsBefore > normalizedTotalSupply + 100;
        assertTrue(hasSurplus, "no surplus, may need to review the lower bound for timeForward");

        vm.startPrank(ADMIN);
        superToken.withdrawSurplusFromYieldBackend();
        vm.stopPrank();

        uint256 receiverBalanceAfter = IERC20(USDC).balanceOf(SURPLUS_RECEIVER);
        uint256 aTokenBalanceAfter = IERC20(A_USDC).balanceOf(address(superToken));

        // Surplus should be withdrawn to receiver
        assertGt(receiverBalanceAfter, receiverBalanceBefore, "Surplus should be withdrawn to receiver");
        assertLt(aTokenBalanceAfter, aTokenBalanceBefore, "aToken balance should decrease");

        // After withdrawing surplus, initial excess is also withdrawn, so don't expect it to be preserved
        // 2 operations: enable deposits + withdraw surplus
        _verifyInvariants(false, 2);
    }
}

