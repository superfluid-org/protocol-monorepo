// SPDX-License-Identifier: AGPLv3
pragma solidity ^0.8.23;

import { Test } from "forge-std/Test.sol";
import { AaveETHYieldBackend } from "../../../../contracts/superfluid/AaveETHYieldBackend.sol";
import { IERC20, ISuperfluid } from "../../../../contracts/interfaces/superfluid/ISuperfluid.sol";
import { ISuperToken } from "../../../../contracts/interfaces/superfluid/ISuperToken.sol";
import { ISETH } from "../../../../contracts/interfaces/tokens/ISETH.sol";
import { SuperToken } from "../../../../contracts/superfluid/SuperToken.sol";
import { IPool } from "aave-v3/src/contracts/interfaces/IPool.sol";

/**
 * @title AaveETHYieldBackendIntegrationTest
 * @notice Integration tests for AaveETHYieldBackend with ETHx on Base
 * @author Superfluid
 */
contract AaveETHYieldBackendIntegrationTest is Test {
    address internal constant ALICE = address(0x420);
    address internal constant ADMIN = address(0xAAA);

    // Base network constants
    uint256 internal constant CHAIN_ID = 8453;
    uint256 internal constant FORK_BLOCK_BASE = 43_400_000;

    // Aave V3 Pool on Base (verified address)
    address internal constant AAVE_POOL = 0xA238Dd80C259a72e81d7e4664a9801593F98d1c5;

    // Common tokens on Base
    address internal constant ETHX = 0x46fd5cfB4c12D87acD3a13e92BAa53240C661D93; // ETHx on Base
    address internal constant WETH = 0x4200000000000000000000000000000000000006; // WETH on Base
    address internal SURPLUS_RECEIVER = 0xac808840f02c47C05507f48165d2222FF28EF4e1; // dao.superfluid.eth

    /// Rounding tolerance for Aave deposit/withdraw operations (in wei)
    uint256 internal constant AAVE_ROUNDING_TOLERANCE = 2;

    SuperToken public superToken;
    ISETH public superTokenETH; // For ETH-specific functions
    AaveETHYieldBackend public aaveETHBackend;
    IPool public aavePool;
    address public aWETH; // aWETH address (retrieved from Aave Pool)
    IERC20 public wethToken;
    /// Initial excess underlying balance (underlyingBalance - normalizedTotalSupply)
    uint256 public initialExcessUnderlying;

    /// @notice Set up the test environment by forking the chain and deploying AaveETHYieldBackend
    function setUp() public {
        vm.createSelectFork(
            vm.envOr("BASE_MAINNET_ARCHIVE_RPC_URL", string("https://mainnet.base.org")),
            FORK_BLOCK_BASE
        );

        // Verify chain id
        assertEq(block.chainid, CHAIN_ID, "Chainid mismatch");

        // Get Aave Pool
        aavePool = IPool(AAVE_POOL);

        // Get aWETH address from Aave Pool
        aWETH = aavePool.getReserveAToken(WETH);
        require(aWETH != address(0), "aWETH address not found");

        // Set up ETHx
        superToken = SuperToken(ETHX);
        superTokenETH = ISETH(ETHX);
        wethToken = IERC20(WETH);

        // Deploy AaveETHBackend
        aaveETHBackend = new AaveETHYieldBackend(IPool(AAVE_POOL), SURPLUS_RECEIVER);

        // upgrade SuperToken to new logic (including the yield backend related code)
        SuperToken newSuperTokenLogic = new SuperToken(ISuperfluid(superToken.getHost()), superToken.POOL_ADMIN_NFT());
        vm.startPrank(address(superToken.getHost()));
        superToken.updateCode(address(newSuperTokenLogic));
        vm.stopPrank();

        // designate an admin for the SuperToken
        vm.startPrank(address(superToken.getHost()));
        superToken.changeAdmin(ADMIN);
        vm.stopPrank();

        // provide ALICE with ETH (will be used for upgradeByETH)
        vm.deal(ALICE, type(uint128).max);

        // Calculate and store initial excess underlying balance
        // The underlying balance may be greater than totalSupply due to rounding or initial state
        uint256 underlyingBalance = address(superToken).balance;
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
        uint256 underlyingBalanceBefore = address(superToken).balance;

        vm.startPrank(ADMIN);
        vm.expectEmit(true, false, false, true);
        emit ISuperToken.YieldBackendEnabled(address(aaveETHBackend), underlyingBalanceBefore);
        superToken.enableYieldBackend(aaveETHBackend);
        vm.stopPrank();
    }

    /// @notice Verify invariants for the SuperToken yield backend system
    /// @param preserveInitialExcess If true, expect initial excess to be preserved (not withdrawn as surplus)
    /// @param numAaveOperations Number of Aave deposit/withdraw operations that have occurred
    function _verifyInvariants(bool preserveInitialExcess, uint256 numAaveOperations) internal view {
        // underlyingBalance (ETH) + aTokenBalance (aWETH) >= superToken.supply() [+ initialExcessUnderlying if preserved]
        // Allow for Aave rounding tolerance (may lose up to 2 wei per operation)
        uint256 underlyingBalance = address(superToken).balance;
        uint256 aTokenBalance = IERC20(aWETH).balanceOf(address(superToken));
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
        uint256 underlyingBalanceBefore = address(superToken).balance;
        (uint256 normalizedTotalSupplyBefore,) = superToken.toUnderlyingAmount(superToken.totalSupply());
        uint256 expectedUnderlyingBefore = normalizedTotalSupplyBefore + initialExcessUnderlying;
        
        // Verify initial state
        assertGe(
            underlyingBalanceBefore,
            expectedUnderlyingBefore,
            "initial underlying should be >= supply + initial excess"
        );

        _enableYieldBackend();

        assertEq(address(superToken.getYieldBackend()), address(aaveETHBackend), "Yield backend mismatch");

        // the SuperToken should now have a zero ETH balance (all deposited and wrapped to WETH)
        assertEq(address(superToken).balance, 0, "ETH balance should be zero");
        
        uint256 aTokenBalanceAfter = IERC20(aWETH).balanceOf(address(superToken));
        assertGe(
            aTokenBalanceAfter,
            underlyingBalanceBefore - AAVE_ROUNDING_TOLERANCE,
            "aWETH balance should match previous ETH balance"
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
        uint256 underlyingBalanceBefore = address(superToken).balance;
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
        vm.expectEmit(true, false, false, true);
        emit ISuperToken.YieldBackendDisabled(address(aaveETHBackend));
        superToken.disableYieldBackend();
        vm.stopPrank();
        assertEq(address(superToken.getYieldBackend()), address(0), "Yield backend mismatch");

        // the SuperToken should now have a non-zero ETH balance and a zero aWETH balance
        uint256 underlyingBalanceAfter = address(superToken).balance;
        assertGt(underlyingBalanceAfter, 0, "ETH balance should be non-zero");
        assertEq(IERC20(aWETH).balanceOf(address(superToken)), 0, "aWETH balance should be zero");

        // After disabling, underlying balance should be at least the amount we had in aTokens + initial excess
        // (the aTokens were converted back to underlying and unwrapped from WETH to ETH)
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
        // ETH has 18 decimals, SuperToken has 18 decimals (same)
        // Minimum: 0.001 ETH (1e15 wei) = 1e15 SuperToken units
        // Maximum: 1000 ETH (1000 * 1e18) = 1000 * 1e18 SuperToken units
        amount = bound(amount, 1e15, 1000 * 1e18);

        _enableYieldBackend();

        vm.startPrank(ALICE);
        superTokenETH.upgradeByETH{value: amount}();
        vm.stopPrank();

        // Downgrade
        vm.startPrank(ALICE);
        // Note: upgrade may have down-rounded the amount, but doesn't tell us (via return value).
        // In that case a consecutive downgrade (of the un-adjusted amount) might revert.
        // For fuzzing, we downgrade the actual balance ALICE received
        uint256 aliceBalance = superToken.balanceOf(ALICE);
        superTokenETH.downgradeToETH(aliceBalance);
        vm.stopPrank();

        // 3 operations: enable deposits + upgrade deposits + downgrade withdraws
        _verifyInvariants(true, 3);
    }


    // testWithdrawSurplusFromYieldBackendExcessUnderlying not possible for SETH
    // because there's no way to deposit ETH without also increasing totalSupply

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

        uint256 receiverBalanceBefore = wethToken.balanceOf(SURPLUS_RECEIVER);
        uint256 underlyingBalanceBefore = address(superToken).balance;
        uint256 aTokenBalanceBefore = IERC20(aWETH).balanceOf(address(superToken));

        // Total assets should be greater than supply due to yield accrual
        // Note: Aave yield accrues by increasing the underlying value of aTokens over time
        uint256 totalAssetsBefore = underlyingBalanceBefore + aTokenBalanceBefore;
        
        // Check if there's actually surplus to withdraw (after the 100 wei margin used in withdrawSurplus)
        bool hasSurplus = totalAssetsBefore > normalizedTotalSupply + 100;
        assertTrue(hasSurplus, "no surplus, may need to review the lower bound for timeForward");

        vm.startPrank(ADMIN);
        superToken.withdrawSurplusFromYieldBackend();
        vm.stopPrank();

        uint256 receiverBalanceAfter = wethToken.balanceOf(SURPLUS_RECEIVER);
        uint256 aTokenBalanceAfter = IERC20(aWETH).balanceOf(address(superToken));

        // Surplus should be withdrawn to receiver (as WETH)
        assertGt(receiverBalanceAfter, receiverBalanceBefore, "Surplus should be withdrawn to receiver");
        assertLt(aTokenBalanceAfter, aTokenBalanceBefore, "aToken balance should decrease");

        // After withdrawing surplus, initial excess is also withdrawn, so don't expect it to be preserved
        // 2 operations: enable deposits + withdraw surplus
        _verifyInvariants(false, 2);
    }
}

/**
 * @title Random Sequence Fuzz Tests
 * RPC-heavy fork fuzz suite for random yield-backend sequences.
 * Excluded from default CI: `yarn test` runs Foundry with `--no-match-contract Fork`.
 */
contract AaveETHYieldBackendIntegrationForkFuzzTest is AaveETHYieldBackendIntegrationTest {
    struct YieldBackendStep {
        uint8 a; // action type: 0 enable, 1 disable, 2 switch, 3 upgrade, 4 downgrade, 5 withdraw surplus
        uint32 v; // action param (amount for upgrade/downgrade, unused for others)
        uint16 dt; // time delta (for yield accrual simulation)
    }

    /// @notice Test random sequence of yield backend operations
    /// @dev Simulates real-world usage patterns with appropriate frequency distribution
    function testRandomYieldBackendSequence(YieldBackendStep[20] memory steps) external {
        // Track state
        bool backendEnabled = false;
        bool initialExcessPreserved = true; // Track if initial excess has been withdrawn via surplus
        uint256 numAaveOperations = 0;
        AaveETHYieldBackend currentBackend = aaveETHBackend;

        for (uint256 i = 0; i < steps.length; ++i) {
            YieldBackendStep memory s = steps[i];
            uint256 action = s.a % 20; // Use modulo 20 for frequency distribution

            // Action frequency distribution:
            // 0: Enable (5%)
            // 1: Disable (5%)
            // 2: Switch (5%)
            // 3-16: Upgrade/Downgrade (70%, split evenly: 3-9 upgrade, 10-16 downgrade)
            // 17-19: Withdraw surplus (15%)

            if (action == 0) {
                // Enable yield backend (5% frequency)
                if (!backendEnabled) {
                    vm.startPrank(ADMIN);
                    superToken.enableYieldBackend(currentBackend);
                    vm.stopPrank();
                    backendEnabled = true;
                    numAaveOperations += 1; // enable deposits all existing underlying
                }
            } else if (action == 1) {
                // Disable yield backend (5% frequency)
                if (backendEnabled) {
                    vm.startPrank(ADMIN);
                    superToken.disableYieldBackend();
                    vm.stopPrank();
                    backendEnabled = false;
                    numAaveOperations += 1; // disable withdraws max
                }
            } else if (action == 2) {
                // Switch yield backend: disable current, enable new (5% frequency)
                if (backendEnabled) {
                    // Disable current
                    vm.startPrank(ADMIN);
                    superToken.disableYieldBackend();
                    vm.stopPrank();
                    numAaveOperations += 1; // disable withdraws

                    // Deploy and enable new backend
                    AaveETHYieldBackend newBackend = new AaveETHYieldBackend(
                        IPool(AAVE_POOL),
                        SURPLUS_RECEIVER
                    );
                    vm.startPrank(ADMIN);
                    superToken.enableYieldBackend(newBackend);
                    vm.stopPrank();
                    currentBackend = newBackend;
                    numAaveOperations += 1; // enable deposits
                }
            } else if (action >= 3 && action <= 9) {
                // Upgrade (35% frequency)
                if (backendEnabled) {
                    // Bound upgrade amount to reasonable range
                    uint256 upgradeAmount = bound(uint256(s.v), 1e15, 1000 * 1e18);
                    vm.startPrank(ALICE);
                    superTokenETH.upgradeByETH{value: upgradeAmount}();
                    vm.stopPrank();
                    numAaveOperations += 1; // upgrade deposits
                }
            } else if (action >= 10 && action <= 16) {
                // Downgrade (35% frequency)
                if (backendEnabled) {
                    uint256 aliceBalance = superToken.balanceOf(ALICE);
                    if (aliceBalance >= 1e15) {
                        // Bound downgrade amount to available balance
                        uint256 downgradeAmount = bound(uint256(s.v), 1e15, aliceBalance);
                        // Don't downgrade more than available
                        if (downgradeAmount > aliceBalance) {
                            downgradeAmount = aliceBalance;
                        }
                        vm.startPrank(ALICE);
                        superTokenETH.downgradeToETH(downgradeAmount);
                        vm.stopPrank();
                        numAaveOperations += 1; // downgrade withdraws
                    }
                }
            } else if (action >= 17 && action <= 19) {
                // Withdraw surplus (15% frequency)
                if (backendEnabled) {
                    // Check if there's surplus to withdraw
                    uint256 underlyingBalance = address(superToken).balance;
                    uint256 aTokenBalance = IERC20(aWETH).balanceOf(address(superToken));
                    (uint256 normalizedTotalSupply,) = superToken.toUnderlyingAmount(superToken.totalSupply());
                    uint256 totalAssets = underlyingBalance + aTokenBalance;

                    // Only withdraw if there's actual surplus (after 100 wei margin)
                    if (totalAssets > normalizedTotalSupply + 100) {
                        vm.startPrank(ADMIN);
                        superToken.withdrawSurplusFromYieldBackend();
                        vm.stopPrank();
                        numAaveOperations += 1; // withdraw surplus
                        // After withdrawing surplus, initial excess is also withdrawn
                        initialExcessPreserved = false;
                    }
                }
            }

            // Warp time to simulate yield accrual (if dt > 0)
            if (s.dt > 0) {
                // Bound time warp to reasonable range (1 hour to 30 days)
                uint256 timeWarp = bound(uint256(s.dt), 1 hours, 30 days);
                vm.warp(block.timestamp + timeWarp);
            }

            // Verify invariants after each step
            // Initial excess should be preserved only if backend is enabled AND surplus hasn't been withdrawn
            bool preserveInitialExcess = backendEnabled && initialExcessPreserved;
            _verifyInvariants(preserveInitialExcess, numAaveOperations);
        }

        // Final invariant check
        bool finalPreserveInitialExcess = backendEnabled && initialExcessPreserved;
        _verifyInvariants(finalPreserveInitialExcess, numAaveOperations);
    }
}
