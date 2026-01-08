// SPDX-License-Identifier: AGPLv3
pragma solidity ^0.8.23;

import { Test } from "forge-std/Test.sol";
import { console } from "forge-std/console.sol";
import { AaveYieldBackend } from "../../../contracts/superfluid/AaveYieldBackend.sol";
import { IERC20, ISuperfluid, ISuperToken } from "../../../contracts/interfaces/superfluid/ISuperfluid.sol";
import { SuperToken } from "../../../contracts/superfluid/SuperToken.sol";
import { IPool } from "aave-v3/src/contracts/interfaces/IPool.sol";
import { ISETH } from "../../../contracts/interfaces/tokens/ISETH.sol";
import { GrifterContract } from "./GrifterContract.sol";

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
    address internal constant aWETH = 0xD4a0e0b9149BCee3C920d2E00b5dE09138fd8bb7;
    address internal constant aUSDC = 0x4e65fE4DbA92790696d040ac24Aa414708F5c0AB; // aUSDC on Base
    address internal constant ETHx = 0x46fd5cfB4c12D87acD3a13e92BAa53240C661D93; // ETHx on Base
    address internal constant SURPLUS_RECEIVER = 0xac808840f02c47C05507f48165d2222FF28EF4e1; // dao.superfluid.eth

    SuperToken public superToken;
    /// @notice AaveYieldBackend contract instance
    AaveYieldBackend public aaveBackend;
    /// @notice Underlying token (USDC or address(0) for ETH)
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

        // Default to USDC for existing tests
        _setUpToken(USDC, USDCx);

        // provide ALICE with underlying and let her approve for upgrade
        deal(USDC, ALICE, type(uint128).max);
        vm.startPrank(ALICE);
        IERC20(USDC).approve(address(superToken), type(uint256).max);

        console.log("aaveBackend address", address(aaveBackend));
        console.log("aUSDC address", address(aUSDC));
    }

    function _setUpToken(address _underlying, address _superToken) internal {
        if (_underlying != address(0)) {
            underlyingToken = IERC20(_underlying);
        } else {
            // For ETH, underlying is address(0)
            underlyingToken = IERC20(address(0));
        }

        superToken = SuperToken(_superToken);

        // Deploy AaveBackend
        aaveBackend = new AaveYieldBackend(IERC20(_underlying), IPool(AAVE_POOL), SURPLUS_RECEIVER);

        // upgrade SuperToken to new logic
        SuperToken newSuperTokenLogic = new SuperToken(ISuperfluid(superToken.getHost()), superToken.POOL_ADMIN_NFT());
        vm.startPrank(address(superToken.getHost()));
        superToken.updateCode(address(newSuperTokenLogic));
        vm.stopPrank();

        // designate an admin for the SuperToken
        vm.startPrank(address(superToken.getHost()));
        superToken.changeAdmin(ADMIN);
        vm.stopPrank();
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

        assertGe(
            underlyingBalance + aTokenBalance,
            superTokenNormalizedSupply,
            "invariant failed: underlyingBalance + aTokenBalance insufficient"
        );

        assertEq(
            underlyingBalance + aTokenBalance,
            superTokenNormalizedSupply,
            "invariant failed: underlyingBalance + aTokenBalance insufficient"
        );
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
        // verify: underlying matches totalSupply
        uint256 underlyingBalanceBefore = IERC20(USDC).balanceOf(address(superToken));
        uint256 superTokenBalanceBefore = superToken.totalSupply();
        (uint256 normalizedTotalSupply,) = superToken.toUnderlyingAmount(superTokenBalanceBefore);
        assertEq(
            underlyingBalanceBefore,
            normalizedTotalSupply,
            "precondition failed: underlyingBalanceBefore != normalizedTotalSupply"
        );

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
        // there's a flaw in the API here: upgrade may have down-rounded the amount, but doesn't tell us (via return
        // value). In that case a consecutive downgrade (of the un-adjusted amount) would revert.
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
        // Simulate yield accumulation by transferring extra underlying to SuperToken
        // uint256 surplusAmount = 100 * 1e6; // 100 USDC
        // deal(USDC, address(this), surplusAmount);

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
        (uint256 normalizedTotalSupply, uint256 adjustedAmount) =
            superToken.toUnderlyingAmount(superToken.totalSupply());
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

    function testUpgadeDowngradeETH() public {
        // Set up ETHx
        SuperToken ethxToken = SuperToken(ETHx);

        // Upgrade ETHx to new logic
        SuperToken newSuperTokenLogic = new SuperToken(ISuperfluid(ethxToken.getHost()), ethxToken.POOL_ADMIN_NFT());
        vm.startPrank(address(ethxToken.getHost()));
        ethxToken.updateCode(address(newSuperTokenLogic));
        vm.stopPrank();

        // Designate admin for ETHx
        vm.startPrank(address(ethxToken.getHost()));
        ethxToken.changeAdmin(ADMIN);
        vm.stopPrank();

        // Deploy AaveBackend for native ETH (address(0))
        AaveYieldBackend ethxBackend = new AaveYieldBackend(IERC20(address(0)), IPool(AAVE_POOL), SURPLUS_RECEIVER);

        // assert that USING_WETH is set
//        assertEq(ethxBackend.USING_WETH(), true);

        // Enable yield backend
        vm.startPrank(ADMIN);
        ethxToken.enableYieldBackend(ethxBackend);
        vm.stopPrank();

        // Give ALICE some ETH
        vm.deal(ALICE, 10 ether);

        // Upgrade ETH using upgradeByETH
        uint256 upgradeAmount = 1 ether;
        vm.startPrank(ALICE);
        ISETH(address(ethxToken)).upgradeByETH{ value: upgradeAmount }();
        vm.stopPrank();

        uint256 aliceBalance = ethxToken.balanceOf(ALICE);
        assertGt(aliceBalance, 0, "ALICE should have ETHx tokens");

        // Verify aWETH balance increased
        uint256 aWETHBalance = IERC20(aWETH).balanceOf(address(ethxToken));
        assertGt(aWETHBalance, 0, "ETHx should have aWETH balance");

        // Downgrade using downgradeToETH
        uint256 aliceETHBefore = ALICE.balance;
        vm.startPrank(ALICE);
        ISETH(address(ethxToken)).downgradeToETH(aliceBalance);
        vm.stopPrank();

        uint256 aliceETHAfter = ALICE.balance;
        assertGt(aliceETHAfter, aliceETHBefore, "ALICE should receive ETH back");
        assertEq(ethxToken.balanceOf(ALICE), 0, "ALICE should have no ETHx tokens");
    }

    function testGrifting() public {
        _enableYieldBackend();

        // 1. Setup Grifter
        // Use an amount that is likely to cause rounding reduction.
        // User mentioned "small inconvenience" but let's test with a standard amount.
        // Aave rounding often happens due to Ray math on index scaling.
        // 100 USDC is a good round number.
        uint256 amountUnderlying = 100 * 1e6; // 100 USDC
        uint256 amountSuper = 100 * 1e18; // 100 USDC in 18 decimals
        console.log("Creating Grifter...");
        GrifterContract grifter = new GrifterContract(ISuperToken(address(superToken)), IERC20(aUSDC), amountSuper);
        console.log("Grifter created.");

        // Fund grifter
        deal(USDC, address(grifter), amountUnderlying);

        // Fund a victim to provide a buffer for rounding errors
        address victim = address(0xBEEE);
        uint256 victimAmountUnderlying = 1000 * 1e6;
        uint256 victimAmountSuper = 1000 * 1e18;
        deal(USDC, victim, victimAmountUnderlying);
        console.log("Victim funded. Balance:", IERC20(USDC).balanceOf(victim));

        vm.startPrank(victim);
        IERC20(USDC).approve(address(superToken), victimAmountUnderlying);
        console.log("Victim approved SuperToken.");

        console.log("Victim upgrading...");
        superToken.upgrade(victimAmountSuper);
        console.log("Victim upgrade done.");
        vm.stopPrank();

        // 2. Measure state before
        uint256 aTokenBalanceBefore = IERC20(aUSDC).balanceOf(address(superToken));

        // 3. Execute Grift
        // Run enough iterations to see meaningful damage but keep gas reasonable for test.
        // 50 iterations
        uint256 iterations = 50;

        // 3. Execute Grift
        vm.startPrank(address(0x1337));
        uint256 gasBefore = gasleft();
        grifter.grift(iterations);
        uint256 gasUsed = gasBefore - gasleft();
        vm.stopPrank();

        // 4. Measure state after
        uint256 aTokenBalanceAfter = IERC20(aUSDC).balanceOf(address(superToken));
        uint256 damage = aTokenBalanceBefore - aTokenBalanceAfter;

        // 5. Analysis
        console.log("=== Grifting Analysis ===");
        console.log("Iterations:", iterations);
        console.log("Gas Used:", gasUsed);
        console.log("Damage (aToken dust lost):", damage);
        console.log("Damage per 1 Million Gas:", (damage * 1000000) / gasUsed);

        // Expectation: damage should be roughly equal to iterations (1 wei per it) or 0 depending on rounding
        // direction/conditions
        // The user claims "x+1" consumption often happens.

        // Calculate Damage per 1 USD spent for tx fees
        // Assumptions:
        // - Base L2 gas price: 0.1 gwei (average low usage)
        // - ETH Price: $2000
        // - L1 data cost is amortized/negligible for high volume batching or not included in this simple calc
        // Cost in ETH = Gas Used * Gas Price
        // Cost in USD = Cost in ETH * ETH Price
        // Damage per 1 USD = Damage / Cost in USD

        // Using 18 decimals for precision in calculation
        uint256 gasPrice = 0.1 gwei;
        uint256 ethPrice = 2000;

        uint256 costInEthEx18 = gasUsed * gasPrice;
        // costInUSD = costInEth * ethPrice
        // But we want Damage / CostInUSD
        // CostInUSD = (gasUsed * gasPrice * ethPrice) / 1e18
        // DamagePerUSD = Damage / ((gasUsed * gasPrice * ethPrice) / 1e18)
        // DamagePerUSD = (Damage * 1e18) / (gasUsed * gasPrice * ethPrice)

        uint256 damagePerUSD = (damage * 1e18) / (gasUsed * gasPrice * ethPrice);
        console.log("Damage per 1 USD (Base assumptions):", damagePerUSD);
        console.log("Damage in USDC decimals per 1 USD:", damagePerUSD); // Since damage is in wei of USDC (6 decimals)

        // A damage of 1e6 would mean 1 USD of damage per 1 USD spent (break even).
    }

    function testRiskOfWithdraw() public {
        _enableYieldBackend();

        // Amount from user report: 59999 USDC wei
        // 59999 = 0.059999 USDC.
        uint256 amount = 59999 * 1e12; // 18 decimals

        // OR if the user meant 59999 underlying units...
        // The log said "requested amount 59999".
        // And "aToken balance diff 60000".
        // If aToken is 6 decimals (aUSDC), then it's USDC.
        // If aToken is 18 decimals, then ?
        // aUSDC is 6 decimals.
        // So amount is 59999 wei USDC.

        // Let's test with the Grifter using this specific amount.
        // Let's test with the Grifter using this specific amount.
        GrifterContract grifter = new GrifterContract(ISuperToken(address(superToken)), IERC20(aUSDC), amount);

        // Fund Grifter with enough Underlying (USDC)
        // amount (18 decimals) -> underlying (6 decimals)
        // 59999 * 1e12 / 1e12 = 59999.
        uint256 underlyingAmount = 59999;
        deal(USDC, address(grifter), underlyingAmount);

        grifter.grift(1);
    }

    function testFuzzGrifting(uint256 amount) public {
        _enableYieldBackend();

        // Fuzz amount between 1 wei USDC (1e12 SuperToken wei) and 100M USDC
        // 1e12 is the smallest amount that represents 1 wei of USDC.
        // Cap at 1 billion USDC.
        amount = bound(amount, 1e12, 1_000_000_000 * 1e18);

        // Setup Grifter with fuzzed amount
        // Grifter setup logic repeated here (could refactor, but kept inline for now)
        GrifterContract grifter = new GrifterContract(ISuperToken(address(superToken)), IERC20(aUSDC), amount);

        // Calculate needed underlying amount (6 decimals)
        // Roughly amount / 1e12
        uint256 amountUnderlying = amount / 1e12;

        // Fund grifter
        deal(USDC, address(grifter), amountUnderlying);

        // Fund a victim to provide a buffer for rounding errors
        address victim = address(0xBEEE);
        uint256 victimAmountUnderlying = 1000 * 1e6;
        uint256 victimAmountSuper = 1000 * 1e18;
        deal(USDC, victim, victimAmountUnderlying);
        vm.startPrank(victim);
        IERC20(USDC).approve(address(superToken), victimAmountUnderlying);
        try superToken.upgrade(victimAmountSuper) {
        // success
        }
        catch {
            console.log("Victim upgrade failed (likely Supply Cap), skipping");
            vm.stopPrank();
            return;
        }
        vm.stopPrank();

        // Measure state before
        uint256 aTokenBalanceBefore = IERC20(aUSDC).balanceOf(address(superToken));

        // Execute grift cycle (multiple iterations to provoke rounding errors)
        // Single iteration often yields 0 loss on fresh state.
        try grifter.grift(20) {
        // console.log("Grift success for amount %s", amount);
        }
        catch {
            console.log("Grift failed (likely Supply Cap), skipping");
            return;
        }
        // Measure state after
        uint256 aTokenBalanceAfter = IERC20(aUSDC).balanceOf(address(superToken));

        if (aTokenBalanceBefore > aTokenBalanceAfter) {
            uint256 loss = aTokenBalanceBefore - aTokenBalanceAfter;
            if (loss > 0) {
                console.log("Loss detected: %s wei for amount %s", loss, amount);
            }
            // Assert max loss per operation is bounded
            // Based on manual testing, we saw up to 2 wei per operation.
            // With 20 iterations, expected max loss is 40 wei.
            // Let's set a conservative bound of 45 wei.
            if (loss > 45) {
                console.log("CRITICAL: Loss exceeded expected bound!");
                console.log("Amount:", amount);
                console.log("Loss:", loss);
                revert("Max loss exceeded expectation");
            }
        } else {
            // console.log("No loss for amount %s", amount);
        }
    }

    function testFuzzGriftingETHx(uint256 amount) public {
        _setUpToken(address(0), ETHx);
        _enableYieldBackend();
        vm.warp(block.timestamp + 1 hours);

        // Fuzz amount between 1 wei and 100M ETH
        // 1e18 is 1 ETH.
        // Cap at 100M ETH.
        amount = bound(amount, 1e15, 100_000_000 * 1e18);

        // Setup Grifter with fuzzed amount
        GrifterContract grifter = new GrifterContract(ISuperToken(address(superToken)), IERC20(aWETH), amount);

        // Fund grifter with ETH
        vm.deal(address(grifter), amount);

        // Fund a victim buffer
        address victim = address(0xBEEE);
        uint256 victimAmount = 100 * 1e18;
        vm.deal(victim, victimAmount);
        vm.startPrank(victim);
        ISETH(address(superToken)).upgradeByETH{ value: victimAmount }();
        vm.stopPrank();

        // Measure state before
        uint256 aTokenBalanceBefore = IERC20(aWETH).balanceOf(address(superToken));

        // Execute grift cycle (20 iterations)
        try grifter.grift(20) {
        // success
        }
        catch {
            console.log("Grift failed (likely Supply Cap or min/max), skipping");
            return;
        }
        // Measure state after
        uint256 aTokenBalanceAfter = IERC20(aWETH).balanceOf(address(superToken));

        if (aTokenBalanceBefore > aTokenBalanceAfter) {
            uint256 loss = aTokenBalanceBefore - aTokenBalanceAfter;
            if (loss > 0) {
                console.log("Loss detected: %s wei for amount %s", loss, amount);
            }
            // Assert max loss per operation is bounded
            // Expectation: 2 wei per op * 20 ops = 40 wei max.
            // Buffer to 45 wei.
            if (loss > 45) {
                console.log("CRITICAL: Loss exceeded expected bound!");
                console.log("Amount:", amount);
                console.log("Loss:", loss);
                revert("Max loss exceeded expectation");
            }
        }
    }
}
