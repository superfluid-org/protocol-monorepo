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
    
    /// @notice Admin address (this contract)
    address public admin;
    /// @notice Test user address
    address public user;
    
    /// @notice Set up the test environment by forking Base and deploying AaveYieldBackend
    function setUp() public {
        // Fork Base using public RPC
        vm.createSelectFork(RPC_URL);
        
        // Verify we're on Base
        assertEq(block.chainid, CHAIN_ID, "Chainid mismatch");
        
        // Initialize test accounts
        admin = address(this);
        user = address(0x1234);
        
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

        console.log("aaveBackend address", address(aaveBackend));
    }

    function _enableYieldBackend() public {
        vm.startPrank(address(superToken.getHost()));
        superToken.setYieldBackend(address(aaveBackend));
        vm.stopPrank();
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
    }

    function testDisableYieldBackend() public {
        // store underlying balance before enabling yield backend
        uint256 underlyingBalanceBefore = IERC20(USDC).balanceOf(address(superToken));

        _enableYieldBackend();

        vm.startPrank(address(superToken.getHost()));
        superToken.setYieldBackend(address(0));
        vm.stopPrank();
        assertEq(address(superToken.getYieldBackend()), address(0), "Yield backend mismatch");

        // the SuperToken should now have a non-zero USDC balance and a zero aUSDC balance
        assertGt(IERC20(USDC).balanceOf(address(superToken)), 0, "USDC balance should be non-zero");
        assertEq(IERC20(aUSDC).balanceOf(address(superToken)), 0, "aUSDC balance should be zero");

        // get underlying balance after disabling yield backend
        uint256 underlyingBalanceAfter = IERC20(USDC).balanceOf(address(superToken));
        //assertEq(underlyingBalanceAfter, underlyingBalanceBefore, "Underlying balance should be the same");
    }

    // TODO: bool fuzz arg for disabled/enabled backend
    function testUpgradeDowngrade() public {
        _enableYieldBackend();

        deal(USDC, ALICE, 1000 ether);

        uint256 aTokenBalanceBefore = IERC20(aUSDC).balanceOf(address(superToken));
        vm.startPrank(ALICE);
        IERC20(USDC).approve(address(superToken), type(uint256).max);
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

        uint256 aTokenBalanceAfterDowngrade = IERC20(aUSDC).balanceOf(address(superToken));
    }

    // ============ Gas Benchmarking Tests ============

    /// @notice Test gas cost of upgrade WITHOUT yield backend
    /// @dev Separate test function to avoid cold/warm storage slot interference
    function testGasUpgrade_WithoutYieldBackend() public {
        // Ensure yield backend is NOT set
        vm.startPrank(address(superToken.getHost()));
        superToken.setYieldBackend(address(0));
        vm.stopPrank();
        assertEq(address(superToken.getYieldBackend()), address(0), "Yield backend should not be set");

        // Prepare test state
        // 1000 USDC = 1000 * 1e6 (USDC has 6 decimals)
        // In SuperToken units (18 decimals), this is 1000 * 1e18
        uint256 upgradeAmount = 1000 * 1e18;
        deal(USDC, ALICE, 1000 * 1e6);
        vm.startPrank(ALICE);
        IERC20(USDC).approve(address(superToken), type(uint256).max);
        
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
        deal(USDC, ALICE, 1000 * 1e6);
        vm.startPrank(ALICE);
        IERC20(USDC).approve(address(superToken), type(uint256).max);
        
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
        vm.startPrank(address(superToken.getHost()));
        superToken.setYieldBackend(address(0));
        vm.stopPrank();

        // First, upgrade some tokens for ALICE to downgrade later
        // 1000 USDC = 1000 * 1e6 (USDC has 6 decimals)
        // In SuperToken units (18 decimals), this is 1000 * 1e18
        uint256 initialUpgradeAmount = 1000 * 1e18;
        deal(USDC, ALICE, 1000 * 1e6);
        vm.startPrank(ALICE);
        IERC20(USDC).approve(address(superToken), type(uint256).max);
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
        deal(USDC, ALICE, 1000 * 1e6);
        vm.startPrank(ALICE);
        IERC20(USDC).approve(address(superToken), type(uint256).max);
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
}

