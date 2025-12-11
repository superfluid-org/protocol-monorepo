// SPDX-License-Identifier: AGPLv3
pragma solidity ^0.8.23;

import { Test } from "forge-std/Test.sol";
import { console } from "forge-std/console.sol";
import { AaveYieldBackend } from "../../../contracts/superfluid/AaveYieldBackend.sol";
import { IERC20, ISuperfluid } from "../../../contracts/interfaces/superfluid/ISuperfluid.sol";
import { SuperToken } from "../../../contracts/superfluid/SuperToken.sol";
import { IPool } from "aave-v3/interfaces/IPool.sol";

/**
 * @title SuperTokenYieldForkTest
 * @notice Fork test for testing yield-related features with AaveYieldBackend
 * @author Superfluid
 */
contract SuperTokenYieldForkTest is Test {
    address constant ALICE = address(0x420);
    address constant ADMIN = address(0xAAA);

    // Base network constants
    uint256 internal constant CHAIN_ID = 8453;
    string internal constant RPC_URL = "https://mainnet.base.org";
    
    // Aave V3 Pool on Base (verified address)
    address internal constant AAVE_POOL = 0xA238Dd80C259a72e81d7e4664a9801593F98d1c5;
    
    // Common tokens on Base
    address internal constant USDCx = 0xD04383398dD2426297da660F9CCA3d439AF9ce1b; // USDCx on Base
    address internal constant USDC = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913; // USDC on Base
    address internal constant WETH = 0x4200000000000000000000000000000000000006; // WETH on Base
    address internal constant aUSDC = 0x4e65fE4DbA92790696d040ac24Aa414708F5c0AB; // aUSDC on Base
    
    SuperToken public superToken;
    /// @notice AaveYieldBackend contract instance
    AaveYieldBackend public aaveBackend;
    /// @notice Underlying token (USDC)
    IERC20 public underlyingToken;
    /// @notice Aave V3 Pool contract
    IPool public aavePool;
    
    /// @notice Set up the test environment by forking Base and deploying AaveYieldBackend
    function setUp() public {
        // Fork Base using public RPC
        vm.createSelectFork(RPC_URL);
        
        // Verify we're on Base
        assertEq(block.chainid, CHAIN_ID, "Chainid mismatch");
        
        // Get Aave Pool
        aavePool = IPool(AAVE_POOL);
        
        // Use USDC as the underlying token for testing
        underlyingToken = IERC20(USDC);

        superToken = SuperToken(USDCx);
        
        // Deploy AaveBackend
        // Note: In a real scenario, the owner would be the SuperToken contract
        // For testing, we use this contract as owner
        aaveBackend = new AaveYieldBackend(IERC20(USDC), IPool(AAVE_POOL));
        
        // Verify AaveBackend was deployed correctly
        assertEq(address(aaveBackend.ASSET_TOKEN()), USDC, "Asset token mismatch");
        assertEq(address(aaveBackend.AAVE_POOL()), AAVE_POOL, "Aave pool mismatch");

        // upgrade SuperToken to new logic
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

        console.log("aaveBackend address", address(aaveBackend));
    }

    function _enableYieldBackend() public {
        vm.startPrank(ADMIN);
        superToken.enableYieldBackend(aaveBackend);
        vm.stopPrank();
    }

    function _verifyInvariants() internal view {
        // underlyingBalance + aTokenBalance >= superToken.supply()
        uint256 underlyingBalance = IERC20(USDC).balanceOf(address(superToken));
        uint256 aTokenBalance = IERC20(aUSDC).balanceOf(address(superToken));
        (uint256 superTokenNormalizedSupply,) = superToken.toUnderlyingAmount(superToken.totalSupply());

        assertGe(underlyingBalance + aTokenBalance, superTokenNormalizedSupply, "invariant failed: underlyingBalance + aTokenBalance insufficient");
    }
    
    /// @notice Test that we're forking the correct Base network
    function testForkBaseNetwork() public view {
        assertEq(block.chainid, CHAIN_ID, "Chainid mismatch");
        assertTrue(AAVE_POOL.code.length > 0, "Aave Pool should exist");
        assertTrue(USDC.code.length > 0, "USDC should exist");
    }
    
    /// @notice Test AaveBackend deployment and initialization
    function testAaveBackendDeployment() public view {
        assertEq(address(aaveBackend.ASSET_TOKEN()), USDC, "Asset token should be USDC");
        assertEq(address(aaveBackend.AAVE_POOL()), AAVE_POOL, "Aave pool address should match");
        assertTrue(address(aaveBackend.A_TOKEN()) != address(0), "aToken should be set");
    }
    
    function testEnableYieldBackend() public {
        // log USDC balance of SuperToken
        console.log("USDC balance of SuperToken", IERC20(USDC).balanceOf(address(superToken)));

        _enableYieldBackend();

        assertEq(address(superToken.getYieldBackend()), address(aaveBackend), "Yield backend mismatch");
        
        // the SuperToken should now have a zero USDC balance and a non-zero aUSDC balance
        assertEq(IERC20(USDC).balanceOf(address(superToken)), 0, "USDC balance should be zero");
        assertGt(IERC20(aUSDC).balanceOf(address(superToken)), 0, "aUSDC balance should be non-zero");

        // log aUSDC balance of SuperToken
        console.log("aUSDC balance of SuperToken", IERC20(aUSDC).balanceOf(address(superToken)));
        // TODO: We'd want asset balance to equal aToken balance. But that's not exactly the case.
        // what else shall be require?
        _verifyInvariants();
    }

    function testDisableYieldBackend() public {
        _enableYieldBackend();

        vm.startPrank(ADMIN);
        superToken.disableYieldBackend();
        vm.stopPrank();
        assertEq(address(superToken.getYieldBackend()), address(0), "Yield backend mismatch");

        // the SuperToken should now have a non-zero USDC balance and a zero aUSDC balance
        assertGt(IERC20(USDC).balanceOf(address(superToken)), 0, "USDC balance should be non-zero");
        assertEq(IERC20(aUSDC).balanceOf(address(superToken)), 0, "aUSDC balance should be zero");

        _verifyInvariants();
    }

    // TODO: bool fuzz arg for disabled/enabled backend
    function testUpgradeDowngrade() public {
        _enableYieldBackend();

        uint256 aTokenBalanceBefore = IERC20(aUSDC).balanceOf(address(superToken));
        vm.startPrank(ALICE);
        superToken.upgrade(1 ether);
        vm.stopPrank();

        uint256 aTokenBalanceAfter = IERC20(aUSDC).balanceOf(address(superToken));

        // log superToken amount of ALICE
        console.log("superToken amount of ALICE", superToken.balanceOf(ALICE));

        // log aToken balance of superToken contract
        console.log("aToken balance of superToken contract", IERC20(aUSDC).balanceOf(address(superToken)));

        // log diff
        console.log("aToken balance diff", aTokenBalanceAfter - aTokenBalanceBefore);

        // downgrade
        vm.startPrank(ALICE);
        // there's a flaw in the API here: upgrade may have down-rounded the amount, but doesn't tell as (via return value). In that case a consecutive downgrade (of the un-adjusted amount) would revert.
        superToken.downgrade(1 ether);
        vm.stopPrank();

        _verifyInvariants();
    }

    // ============ Gas Benchmarking Tests ============

    /// @notice Test gas cost of upgrade WITHOUT yield backend
    /// @dev Separate test function to avoid cold/warm storage slot interference
    function testGasUpgrade_WithoutYieldBackend() public {
        // Ensure yield backend is NOT set
        assertEq(address(superToken.getYieldBackend()), address(0), "Yield backend should not be set");

        // Prepare test state
        // 1000 USDC = 1000 * 1e6 (USDC has 6 decimals)
        // In SuperToken units (18 decimals), this is 1000 * 1e18
        uint256 upgradeAmount = 1000 * 1e18;
        vm.startPrank(ALICE);
        // Measure gas for upgrade
        uint256 gasBefore = gasleft();
        superToken.upgrade(upgradeAmount);
        uint256 gasUsed = gasBefore - gasleft();
        vm.stopPrank();

        console.log("=== Gas: Upgrade WITHOUT Yield Backend ===");
        console.log("Gas used", gasUsed);
        console.log("Amount upgraded", upgradeAmount);
    }

    /// @notice Test gas cost of upgrade WITH yield backend
    /// @dev Separate test function to avoid cold/warm storage slot interference
    function testGasUpgrade_WithYieldBackend() public {
        // Enable yield backend
        _enableYieldBackend();
        assertEq(address(superToken.getYieldBackend()), address(aaveBackend), "Yield backend should be set");

        // Prepare test state
        // 1000 USDC = 1000 * 1e6 (USDC has 6 decimals)
        // In SuperToken units (18 decimals), this is 1000 * 1e18
        uint256 upgradeAmount = 1000 * 1e18;
        vm.startPrank(ALICE);
        // Measure gas for upgrade
        uint256 gasBefore = gasleft();
        superToken.upgrade(upgradeAmount);
        uint256 gasUsed = gasBefore - gasleft();
        vm.stopPrank();

        console.log("=== Gas: Upgrade WITH Yield Backend ===");
        console.log("Gas used", gasUsed);
        console.log("Amount upgraded", upgradeAmount);
    }

    /// @notice Test gas cost of downgrade WITHOUT yield backend
    /// @dev Separate test function to avoid cold/warm storage slot interference
    function testGasDowngrade_WithoutYieldBackend() public {
        // Ensure yield backend is NOT set
        assertEq(address(superToken.getYieldBackend()), address(0), "Yield backend should not be set");

        // First, upgrade some tokens for ALICE to downgrade later
        // 1000 USDC = 1000 * 1e6 (USDC has 6 decimals)
        // In SuperToken units (18 decimals), this is 1000 * 1e18
        uint256 initialUpgradeAmount = 1000 * 1e18;
        vm.startPrank(ALICE);
        superToken.upgrade(initialUpgradeAmount);
        vm.stopPrank();

        uint256 aliceBalance = superToken.balanceOf(ALICE);
        assertGt(aliceBalance, 0, "ALICE should have super tokens");

        // Now measure gas for downgrade
        vm.startPrank(ALICE);
        uint256 amountToDowngrade = aliceBalance / 2; // Downgrade half
        uint256 gasBefore = gasleft();
        superToken.downgrade(amountToDowngrade);
        uint256 gasUsed = gasBefore - gasleft();
        vm.stopPrank();

        console.log("=== Gas: Downgrade WITHOUT Yield Backend ===");
        console.log("Gas used", gasUsed);
        console.log("Amount downgraded", amountToDowngrade);
    }

    /// @notice Test gas cost of downgrade WITH yield backend
    /// @dev Separate test function to avoid cold/warm storage slot interference
    function testGasDowngrade_WithYieldBackend() public {
        // Enable yield backend
        _enableYieldBackend();

        // First, upgrade some tokens for ALICE to downgrade later
        // 1000 USDC = 1000 * 1e6 (USDC has 6 decimals)
        // In SuperToken units (18 decimals), this is 1000 * 1e18
        uint256 initialUpgradeAmount = 1000 * 1e18;
        vm.startPrank(ALICE);
        superToken.upgrade(initialUpgradeAmount);
        vm.stopPrank();

        uint256 aliceBalance = superToken.balanceOf(ALICE);
        assertGt(aliceBalance, 0, "ALICE should have super tokens");

        // Now measure gas for downgrade
        vm.startPrank(ALICE);
        uint256 amountToDowngrade = aliceBalance / 2; // Downgrade half
        uint256 gasBefore = gasleft();
        superToken.downgrade(amountToDowngrade);
        uint256 gasUsed = gasBefore - gasleft();
        vm.stopPrank();

        console.log("=== Gas: Downgrade WITH Yield Backend ===");
        console.log("Gas used", gasUsed);
        console.log("Amount downgraded", amountToDowngrade);
    }

    function testWithdrawSurplusFromYieldBackend() public {
        address SURPLUS_RECEIVER = 0xac808840f02c47C05507f48165d2222FF28EF4e1;
        
        // Simulate yield accumulation by transferring extra underlying to SuperToken
        uint256 surplusAmount = 100 * 1e6; // 100 USDC
        deal(USDC, address(this), surplusAmount);

        _enableYieldBackend();
        
        // Upgrade tokens to create supply
        uint256 upgradeAmount = 1000 * 1e18;
        vm.startPrank(ALICE);
        superToken.upgrade(upgradeAmount);
        vm.stopPrank();

        uint256 receiverBalanceBefore = IERC20(USDC).balanceOf(SURPLUS_RECEIVER);
        uint256 aTokenBalanceBefore = IERC20(aUSDC).balanceOf(address(superToken));

        // log USDC and aUSDC balances of SuperToken
        console.log("USDC balance of SuperToken", IERC20(USDC).balanceOf(address(superToken)));
        console.log("aUSDC balance of SuperToken", IERC20(aUSDC).balanceOf(address(superToken)));
        // log normalized total supply
        (uint256 normalizedTotalSupply, uint256 adjustedAmount) = superToken.toUnderlyingAmount(superToken.totalSupply());
        console.log("normalized total supply", normalizedTotalSupply);
        console.log("adjusted amount", adjustedAmount);
        
        vm.startPrank(ADMIN);
        superToken.withdrawSurplusFromYieldBackend();
        vm.stopPrank();
        
        uint256 receiverBalanceAfter = IERC20(USDC).balanceOf(SURPLUS_RECEIVER);
        uint256 aTokenBalanceAfter = IERC20(aUSDC).balanceOf(address(superToken));
        console.log("aToken balance after", aTokenBalanceAfter);
        console.log("aToken balance diff", aTokenBalanceBefore - aTokenBalanceAfter);
        
        assertGt(receiverBalanceAfter, receiverBalanceBefore, "Surplus should be withdrawn to receiver");
        assertLt(aTokenBalanceAfter, aTokenBalanceBefore, "aToken balance should decrease");
        _verifyInvariants();
    }
}

