// SPDX-License-Identifier: AGPLv3
pragma solidity ^0.8.23;

import { Test } from "forge-std/Test.sol";
import { console } from "forge-std/console.sol";
import { ERC4626YieldBackend } from "../../../contracts/superfluid/ERC4626YieldBackend.sol";
import { IERC20, ISuperfluid } from "../../../contracts/interfaces/superfluid/ISuperfluid.sol";
import { SuperToken } from "../../../contracts/superfluid/SuperToken.sol";
import { IERC4626 } from "@openzeppelin-v5/contracts/interfaces/IERC4626.sol";

/**
 * @title SparkYieldBackendForkTest
 * @notice Fork test for testing yield-related features with SparkYieldBackend on Base
 * @author Superfluid
 */
contract SparkYieldBackendForkTest is Test {
    address internal constant ALICE = address(0x420);
    address internal constant ADMIN = address(0xAAA);
    address internal constant SURPLUS_RECEIVER = 0xac808840f02c47C05507f48165d2222FF28EF4e1; // dao.superfluid.eth

    // Base network constants
    uint256 internal constant CHAIN_ID = 8453;
    string internal constant RPC_URL = "https://mainnet.base.org";

    // Spark USDC Vault on Base (sUSDC)
    address internal constant SPARK_VAULT = 0x3128a0F7f0ea68E7B7c9B00AFa7E41045828e858;

    // Common tokens on Base
    address internal constant USDCx = 0xD04383398dD2426297da660F9CCA3d439AF9ce1b;
    address internal constant USDC = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;

    SuperToken internal superToken;
    ERC4626YieldBackend internal sparkBackend;
    IERC20 internal underlyingToken;
    IERC4626 internal vault;

    function setUp() public {
        vm.createSelectFork(RPC_URL);
        assertEq(block.chainid, CHAIN_ID, "Chainid mismatch");

        vault = IERC4626(SPARK_VAULT);
        underlyingToken = IERC20(USDC);

        superToken = SuperToken(USDCx);

        sparkBackend = new ERC4626YieldBackend(vault, SURPLUS_RECEIVER);

        assertEq(address(sparkBackend.ASSET_TOKEN()), USDC, "Asset token mismatch");
        assertEq(address(sparkBackend.VAULT()), SPARK_VAULT, "Vault mismatch");

        // upgrade SuperToken to new logic (mocking upgrade to enable features if needed,
        // essentially ensuring we have a fresh state or compatible logic)
        // Note: SuperToken on Base might already be up to date, but we re-deploy logic for safety in test
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
    }

    function _enableYieldBackend() public {
        vm.startPrank(ADMIN);
        superToken.enableYieldBackend(sparkBackend);
        vm.stopPrank();
    }

    function _verifyInvariants() internal view {
        // underlyingBalance + vaultAssets >= superToken.supply()
        uint256 underlyingBalance = IERC20(USDC).balanceOf(address(superToken));
        // vault balance is in shares, need to convert to assets
        uint256 vaultAssets = vault.convertToAssets(vault.balanceOf(address(superToken)));

        (uint256 superTokenNormalizedSupply,) = superToken.toUnderlyingAmount(superToken.totalSupply());

        // We use approx because of potential rounding/yield accruing differently per block
        // But assets should be >= supply
        assertGe(
            underlyingBalance + vaultAssets,
            superTokenNormalizedSupply,
            "invariant failed: underlying + vaultAssets insufficient"
        );
    }

    function testSparkBackendDeployment() public view {
        assertEq(address(sparkBackend.ASSET_TOKEN()), USDC, "Asset token should be USDC");
        assertEq(address(sparkBackend.VAULT()), SPARK_VAULT, "Vault address should match");
    }

    function testEnableYieldBackend() public {
        _enableYieldBackend();

        assertEq(address(superToken.getYieldBackend()), address(sparkBackend), "Yield backend mismatch");

        // For new deposits, we need to upgrade
        uint256 amount = 100 * 1e18;
        vm.startPrank(ALICE);
        superToken.upgrade(amount);
        vm.stopPrank();

        // the SuperToken should now have a zero USDC balance (all deposited)
        assertEq(IERC20(USDC).balanceOf(address(superToken)), 0, "USDC balance should be zero");

        // And non-zero vault balance
        assertGt(vault.balanceOf(address(superToken)), 0, "Vault share balance should be non-zero");

        _verifyInvariants();
    }

    function testDisableYieldBackend() public {
        _enableYieldBackend();

        // Deposit some funds first so we have something to withdraw
        vm.startPrank(ALICE);
        superToken.upgrade(100 * 1e18);
        vm.stopPrank();

        vm.startPrank(ADMIN);
        superToken.disableYieldBackend();
        vm.stopPrank();
        assertEq(address(superToken.getYieldBackend()), address(0), "Yield backend mismatch");

        // the SuperToken should now have a non-zero USDC balance and a zero vault balance
        assertGt(IERC20(USDC).balanceOf(address(superToken)), 0, "USDC balance should be non-zero");
        assertEq(vault.balanceOf(address(superToken)), 0, "Vault balance should be zero");

        _verifyInvariants();
    }

    function testUpgradeDowngrade() public {
        _enableYieldBackend();

        uint256 vaultSharesBefore = vault.balanceOf(address(superToken));
        uint256 amount = 100 * 1e18; // 100 USDCx

        vm.startPrank(ALICE);
        superToken.upgrade(amount);
        vm.stopPrank();

        uint256 vaultSharesAfter = vault.balanceOf(address(superToken));

        assertGt(vaultSharesAfter, vaultSharesBefore, "Vault shares should increase");

        // downgrade
        vm.startPrank(ALICE);
        superToken.downgrade(amount);
        vm.stopPrank();

        uint256 vaultSharesFinal = vault.balanceOf(address(superToken));
        assertLt(vaultSharesFinal, vaultSharesAfter, "Vault shares should decrease");

        _verifyInvariants();
    }

    function testWithdrawSurplusFromYieldBackend() public {
        // simulate the SuperToken having a surplus of underlying from the start
        uint256 surplusAmount = 100 * 1e6; // 100 USDC
        deal(USDC, address(superToken), surplusAmount);

        _enableYieldBackend();

        uint256 receiverBalanceBefore = IERC20(USDC).balanceOf(SURPLUS_RECEIVER);

        vm.startPrank(ADMIN);
        superToken.withdrawSurplusFromYieldBackend();
        vm.stopPrank();

        uint256 receiverBalanceAfter = IERC20(USDC).balanceOf(SURPLUS_RECEIVER);

        console.log("Receiver balance before", receiverBalanceBefore);
        console.log("Receiver balance after", receiverBalanceAfter);
        console.log("Diff", receiverBalanceAfter - receiverBalanceBefore);

        assertGt(receiverBalanceAfter, receiverBalanceBefore, "Surplus should be withdrawn to receiver");
        _verifyInvariants();
    }
}
