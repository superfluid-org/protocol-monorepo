// SPDX-License-Identifier: AGPLv3
pragma solidity ^0.8.23;

import { Test } from "forge-std/Test.sol";
import { IERC20, ISuperfluid } from "../../../../contracts/interfaces/superfluid/ISuperfluid.sol";
import { ISuperToken } from "../../../../contracts/interfaces/superfluid/ISuperToken.sol";
import { SuperToken } from "../../../../contracts/superfluid/SuperToken.sol";
import { IYieldBackend } from "../../../../contracts/interfaces/superfluid/IYieldBackend.sol";

/**
 * @title YieldBackendIntegrationTestBase
 * @notice Abstract base for yield backend integration tests. Concrete contracts provide
 *         chain- and backend-specific config via the virtual getters and hooks.
 * @author Superfluid
 */
abstract contract YieldBackendIntegrationTestBase is Test {
    address internal constant ALICE = address(0x420);
    address internal constant ADMIN = address(0xAAA);
    address internal constant SURPLUS_RECEIVER = 0xac808840f02c47C05507f48165d2222FF28EF4e1; // dao.superfluid.eth

    /// Rounding tolerance for deposit/withdraw operations (in wei)
    uint256 internal constant ROUNDING_TOLERANCE = 2;

    SuperToken public superToken;
    IYieldBackend internal backend;
    IERC20 public underlyingToken;
    /// Initial excess underlying balance (underlyingBalance - normalizedTotalSupply)
    uint256 public initialExcessUnderlying;

    // ============ Abstract hooks ============

    function _chainId() internal pure virtual returns (uint256);
    function _rpcUrl() internal view virtual returns (string memory);
    /// @notice Fork at this block (0 = latest). Use a fixed block so SuperToken has zero admin and no yield backend.
    function _forkBlockNumber() internal pure virtual returns (uint256) {
        return 0;
    }
    function _superToken() internal pure virtual returns (address);
    function _underlyingToken() internal pure virtual returns (address);
    function _createBackend() internal virtual returns (IYieldBackend);
    function _getYieldAssets(address superToken_) internal view virtual returns (uint256);
    function _assertYieldPositionZeroOrDustAfterDisable() internal virtual;

    /// @notice Yield position to assert decreases after surplus withdraw. Default: _getYieldAssets. ERC4626 overrides to vault shares.
    function _getYieldPositionForSurplusAssert(address superToken_) internal view virtual returns (uint256) {
        return _getYieldAssets(superToken_);
    }

    // ============ setUp ============

    /// @notice Set up the test environment by forking the chain and deploying the yield backend
    function setUp() public virtual {
        uint256 forkBlock = _forkBlockNumber();
        if (forkBlock == 0) {
            vm.createSelectFork(_rpcUrl());
        } else {
            vm.createSelectFork(_rpcUrl(), forkBlock);
        }

        assertEq(block.chainid, _chainId(), "Chainid mismatch");

        underlyingToken = IERC20(_underlyingToken());
        superToken = SuperToken(_superToken());
        backend = _createBackend();

        // upgrade SuperToken to new logic (including the yield backend related code)
        SuperToken newSuperTokenLogic = new SuperToken(ISuperfluid(superToken.getHost()), superToken.POOL_ADMIN_NFT());
        vm.startPrank(address(superToken.getHost()));
        superToken.updateCode(address(newSuperTokenLogic));
        vm.stopPrank();

        vm.startPrank(address(superToken.getHost()));
        superToken.changeAdmin(ADMIN);
        vm.stopPrank();

        deal(_underlyingToken(), ALICE, type(uint128).max);
        vm.startPrank(ALICE);
        IERC20(_underlyingToken()).approve(address(superToken), type(uint256).max);
        vm.stopPrank();

        uint256 underlyingBalance = IERC20(_underlyingToken()).balanceOf(address(superToken));
        (uint256 normalizedTotalSupply,) = superToken.toUnderlyingAmount(superToken.totalSupply());

        assertGe(
            underlyingBalance,
            normalizedTotalSupply,
            "underlyingBalance should be >= normalizedTotalSupply"
        );
        initialExcessUnderlying = underlyingBalance - normalizedTotalSupply;
    }

    // ============ Helpers ============

    function _enableYieldBackend() public {
        uint256 underlyingBalanceBefore = IERC20(_underlyingToken()).balanceOf(address(superToken));

        vm.startPrank(ADMIN);
        vm.expectEmit(true, false, false, true);
        emit ISuperToken.YieldBackendEnabled(address(backend), underlyingBalanceBefore);
        superToken.enableYieldBackend(backend);
        vm.stopPrank();
    }

    /// @notice Verify invariants for the SuperToken yield backend system
    function _verifyInvariants(bool preserveInitialExcess, uint256 numOps) internal view {
        uint256 underlyingBalance = IERC20(_underlyingToken()).balanceOf(address(superToken));
        uint256 yieldAssets = _getYieldAssets(address(superToken));
        (uint256 superTokenNormalizedSupply,) = superToken.toUnderlyingAmount(superToken.totalSupply());

        uint256 expectedMinTotalAssets = preserveInitialExcess
            ? superTokenNormalizedSupply + initialExcessUnderlying
            : superTokenNormalizedSupply;
        uint256 totalAssets = underlyingBalance + yieldAssets;
        uint256 totalTolerance = numOps * ROUNDING_TOLERANCE;

        assertGe(
            totalAssets + totalTolerance,
            expectedMinTotalAssets,
            preserveInitialExcess
                ? "invariant failed: total assets should be >= supply + initial excess (accounting for rounding)"
                : "invariant failed: total assets should be >= supply (accounting for rounding)"
        );
    }

    // ============ Tests ============

    /// @notice Test enabling yield backend
    function testEnableYieldBackend() public {
        uint256 underlyingBalanceBefore = IERC20(_underlyingToken()).balanceOf(address(superToken));
        (uint256 normalizedTotalSupplyBefore,) = superToken.toUnderlyingAmount(superToken.totalSupply());
        uint256 expectedUnderlyingBefore = normalizedTotalSupplyBefore + initialExcessUnderlying;

        assertGe(
            underlyingBalanceBefore,
            expectedUnderlyingBefore,
            "initial underlying should be >= supply + initial excess"
        );

        _enableYieldBackend();

        assertEq(address(superToken.getYieldBackend()), address(backend), "Yield backend mismatch");
        assertEq(IERC20(_underlyingToken()).balanceOf(address(superToken)), 0, "underlying balance should be zero");

        uint256 yieldAssetsAfter = _getYieldAssets(address(superToken));
        assertGe(
            yieldAssetsAfter,
            underlyingBalanceBefore - ROUNDING_TOLERANCE,
            "yield assets should match previous underlying balance"
        );
        assertGe(
            yieldAssetsAfter,
            expectedUnderlyingBefore - 1000,
            "yield assets should approximately match deposited amount"
        );

        _verifyInvariants(true, 1);
    }

    /// @notice Test disabling yield backend
    function testDisableYieldBackend() public {
        uint256 underlyingBalanceBefore = IERC20(_underlyingToken()).balanceOf(address(superToken));
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
        emit ISuperToken.YieldBackendDisabled(address(backend));
        superToken.disableYieldBackend();
        vm.stopPrank();
        assertEq(address(superToken.getYieldBackend()), address(0), "Yield backend mismatch");

        uint256 underlyingBalanceAfter = IERC20(_underlyingToken()).balanceOf(address(superToken));
        assertGt(underlyingBalanceAfter, 0, "underlying balance should be non-zero");
        _assertYieldPositionZeroOrDustAfterDisable();

        assertGe(
            underlyingBalanceAfter + ROUNDING_TOLERANCE,
            expectedUnderlying,
            "underlying balance after disable should be >= original underlying + initial excess"
        );

        _verifyInvariants(true, 2);
    }

    /// @notice Test upgrade and downgrade with fuzzed amount
    function testUpgradeDowngrade(uint256 amount) public {
        amount = bound(amount, 1e18, 1_000_000 * 1e18);

        _enableYieldBackend();

        vm.startPrank(ALICE);
        superToken.upgrade(amount);
        vm.stopPrank();

        vm.startPrank(ALICE);
        uint256 aliceBalance = superToken.balanceOf(ALICE);
        superToken.downgrade(aliceBalance);
        vm.stopPrank();

        _verifyInvariants(true, 3);
    }

    /// @notice Test withdrawing surplus due to excess underlying balance
    function testWithdrawSurplusFromYieldBackendExcessUnderlying() public {
        _enableYieldBackend();

        uint256 upgradeAmount = 1000 * 1e18;
        vm.startPrank(ALICE);
        superToken.upgrade(upgradeAmount);
        vm.stopPrank();

        uint256 surplusAmount = 100 * 1e6; // 100 USDC
        deal(_underlyingToken(), address(superToken), surplusAmount);

        uint256 receiverBalanceBefore = IERC20(_underlyingToken()).balanceOf(SURPLUS_RECEIVER);
        uint256 underlyingBalanceBefore = IERC20(_underlyingToken()).balanceOf(address(superToken));
        uint256 yieldAssetsBefore = _getYieldAssets(address(superToken));

        (uint256 normalizedTotalSupply,) = superToken.toUnderlyingAmount(superToken.totalSupply());
        uint256 totalAssetsBefore = underlyingBalanceBefore + yieldAssetsBefore;
        assertGt(
            totalAssetsBefore,
            normalizedTotalSupply + 100,
            "Precondition: excess underlying should exist"
        );

        vm.startPrank(ADMIN);
        superToken.withdrawSurplusFromYieldBackend();
        vm.stopPrank();

        uint256 receiverBalanceAfter = IERC20(_underlyingToken()).balanceOf(SURPLUS_RECEIVER);
        uint256 surplusWithdrawn = receiverBalanceAfter - receiverBalanceBefore;
        assertGt(surplusWithdrawn, 0, "Surplus should be withdrawn to receiver");
        assertGe(
            surplusWithdrawn,
            surplusAmount - 200,
            "Surplus withdrawn should be approximately the excess"
        );

        _verifyInvariants(false, 3);
    }

    /// @notice Test withdrawing surplus generated by yield protocol (fast forward time)
    function testWithdrawSurplusFromYieldBackendYieldAccrued(uint256 timeForward) public {
        timeForward = bound(timeForward, 1 hours, 365 days);

        _enableYieldBackend();

        (uint256 normalizedTotalSupplyInitial,) = superToken.toUnderlyingAmount(superToken.totalSupply());

        vm.warp(block.timestamp + timeForward);

        (uint256 normalizedTotalSupply,) = superToken.toUnderlyingAmount(superToken.totalSupply());
        assertEq(
            normalizedTotalSupply,
            normalizedTotalSupplyInitial,
            "Total supply should not change from time forward"
        );

        uint256 receiverBalanceBefore = IERC20(_underlyingToken()).balanceOf(SURPLUS_RECEIVER);
        uint256 underlyingBalanceBefore = IERC20(_underlyingToken()).balanceOf(address(superToken));
        uint256 yieldAssetsBefore = _getYieldAssets(address(superToken));
        uint256 totalAssetsBefore = underlyingBalanceBefore + yieldAssetsBefore;

        bool hasSurplus = totalAssetsBefore > normalizedTotalSupply + 100;
        assertTrue(hasSurplus, "no surplus, may need to review the lower bound for timeForward");

        uint256 yieldPosBefore = _getYieldPositionForSurplusAssert(address(superToken));

        vm.startPrank(ADMIN);
        superToken.withdrawSurplusFromYieldBackend();
        vm.stopPrank();

        uint256 receiverBalanceAfter = IERC20(_underlyingToken()).balanceOf(SURPLUS_RECEIVER);
        uint256 yieldPosAfter = _getYieldPositionForSurplusAssert(address(superToken));

        assertGt(receiverBalanceAfter, receiverBalanceBefore, "Surplus should be withdrawn to receiver");
        assertLt(yieldPosAfter, yieldPosBefore, "yield position should decrease");

        _verifyInvariants(false, 2);
    }

    /*//////////////////////////////////////////////////////////////////////////
                        Random Sequence Fuzz Tests
    //////////////////////////////////////////////////////////////////////////*/

    struct YieldBackendStep {
        uint8 a;   // action type: 0 enable, 1 disable, 2 switch, 3 upgrade, 4 downgrade, 5 withdraw surplus
        uint32 v;  // action param (amount for upgrade/downgrade, unused for others)
        uint16 dt; // time delta (for yield accrual simulation)
    }

    /// @notice Test random sequence of yield backend operations
    function testRandomYieldBackendSequence(YieldBackendStep[20] memory steps) external {
        bool backendEnabled = false;
        bool initialExcessPreserved = true;
        uint256 numOps = 0;
        IYieldBackend currentBackend = backend;

        for (uint256 i = 0; i < steps.length; ++i) {
            YieldBackendStep memory s = steps[i];
            uint256 action = s.a % 20;

            if (action == 0) {
                if (!backendEnabled) {
                    vm.startPrank(ADMIN);
                    superToken.enableYieldBackend(currentBackend);
                    vm.stopPrank();
                    backendEnabled = true;
                    numOps += 1;
                }
            } else if (action == 1) {
                if (backendEnabled) {
                    vm.startPrank(ADMIN);
                    superToken.disableYieldBackend();
                    vm.stopPrank();
                    backendEnabled = false;
                    numOps += 1;
                }
            } else if (action == 2) {
                if (backendEnabled) {
                    vm.startPrank(ADMIN);
                    superToken.disableYieldBackend();
                    vm.stopPrank();
                    numOps += 1;

                    IYieldBackend newBackend = _createBackend();
                    vm.startPrank(ADMIN);
                    superToken.enableYieldBackend(newBackend);
                    vm.stopPrank();
                    currentBackend = newBackend;
                    numOps += 1;
                }
            } else if (action >= 3 && action <= 9) {
                if (backendEnabled) {
                    uint256 upgradeAmount = bound(uint256(s.v), 1e18, 1_000_000 * 1e18);
                    vm.startPrank(ALICE);
                    superToken.upgrade(upgradeAmount);
                    vm.stopPrank();
                    numOps += 1;
                }
            } else if (action >= 10 && action <= 16) {
                if (backendEnabled) {
                    uint256 aliceBalance = superToken.balanceOf(ALICE);
                    if (aliceBalance > 0) {
                        uint256 downgradeAmount = bound(uint256(s.v), 1e18, aliceBalance);
                        if (downgradeAmount > aliceBalance) {
                            downgradeAmount = aliceBalance;
                        }
                        vm.startPrank(ALICE);
                        superToken.downgrade(downgradeAmount);
                        vm.stopPrank();
                        numOps += 1;
                    }
                }
            } else if (action >= 17 && action <= 19) {
                if (backendEnabled) {
                    uint256 underlyingBalance = IERC20(_underlyingToken()).balanceOf(address(superToken));
                    uint256 yieldAssets = _getYieldAssets(address(superToken));
                    (uint256 normalizedTotalSupply,) = superToken.toUnderlyingAmount(superToken.totalSupply());
                    uint256 totalAssets = underlyingBalance + yieldAssets;

                    if (totalAssets > normalizedTotalSupply + 100) {
                        vm.startPrank(ADMIN);
                        superToken.withdrawSurplusFromYieldBackend();
                        vm.stopPrank();
                        numOps += 1;
                        initialExcessPreserved = false;
                    }
                }
            }

            if (s.dt > 0) {
                uint256 timeWarp = bound(uint256(s.dt), 1 hours, 30 days);
                vm.warp(block.timestamp + timeWarp);
            }

            bool preserveInitialExcess = backendEnabled && initialExcessPreserved;
            _verifyInvariants(preserveInitialExcess, numOps);
        }

        bool finalPreserveInitialExcess = backendEnabled && initialExcessPreserved;
        _verifyInvariants(finalPreserveInitialExcess, numOps);
    }
}
