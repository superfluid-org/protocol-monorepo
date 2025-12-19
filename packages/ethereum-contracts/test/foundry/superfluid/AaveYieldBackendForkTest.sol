// SPDX-License-Identifier: AGPLv3
pragma solidity ^0.8.23;

import { Test } from "forge-std/Test.sol";
import { console } from "forge-std/console.sol";
import { Math } from "@openzeppelin-v5/contracts/utils/math/Math.sol";
import { AaveYieldBackend } from "../../../contracts/superfluid/AaveYieldBackend.sol";
import { IERC20 } from "../../../contracts/interfaces/superfluid/ISuperfluid.sol";
import { IPool } from "aave-v3/src/contracts/interfaces/IPool.sol";

/**
 * @title AaveYieldBackendForkTest
 * @notice Fork test for testing AaveYieldBackend
 * @notice The test contract itself takes the role of SuperToken for delegatecall operations
 * @author Superfluid
 */
contract AaveYieldBackendForkTest is Test {
    uint256 internal constant CHAIN_ID = 8453;
    string internal constant RPC_URL = "https://mainnet.base.org";

    address internal constant AAVE_POOL = 0xA238Dd80C259a72e81d7e4664a9801593F98d1c5;

    address internal constant USDC = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;
    address internal constant aUSDC = 0x4e65fE4DbA92790696d040ac24Aa414708F5c0AB;
    address internal constant SURPLUS_RECEIVER = 0xac808840f02c47C05507f48165d2222FF28EF4e1;

    AaveYieldBackend internal aaveBackend;
    IERC20 internal assetToken;
    IERC20 internal aToken;
    IPool internal aavePool;

    /// @notice Set up the test environment by forking Base and deploying AaveYieldBackend
    function setUp() public {
        vm.createSelectFork(RPC_URL);

        assertEq(block.chainid, CHAIN_ID, "Chainid mismatch");

        aavePool = IPool(AAVE_POOL);

        assetToken = IERC20(USDC);
        aToken = IERC20(aUSDC);

        aaveBackend = new AaveYieldBackend(assetToken, aavePool, SURPLUS_RECEIVER);

        // Enable the backend (approves Aave pool)
        (bool success,) = address(aaveBackend).delegatecall(abi.encodeWithSelector(AaveYieldBackend.enable.selector));
        require(success, "enable failed");

        deal(USDC, address(this), 200_000_000 * 1e6); // 200M USDC
    }

    /// @notice Mock of toUnderlyingAmount, hardcoded to 18 to 6 decimals conversion
    function toUnderlyingAmount(uint256 amount)
        external
        pure
        returns (uint256 underlyingAmount, uint256 adjustedAmount)
    {
        uint256 factor = 10 ** (18 - 6);
        underlyingAmount = amount / factor;
        adjustedAmount = underlyingAmount * factor;
    }

    /// Generates a random number between 1 and 1e14 using an exponential distribution.
    function _getRandomWithExpDistribution() internal view returns (uint256) {
        uint256 MAX_VAL = 1e14;

        // 1. Determine max magnitude. 1e14 is approx 2^46.5
        uint256 maxMagnitude = Math.log2(MAX_VAL);

        // 2. Pick a random magnitude (bit-length) uniformly.
        // This ensures 1 digit numbers are as likely as 14 digit numbers to be "the range".
        uint256 magnitude = bound(vm.randomUint(), 0, maxMagnitude);

        // 3. Set the high bit (2^magnitude)
        uint256 base = 1 << magnitude;

        // 4. Fill the lower bits with random noise to get specific numbers like 14,532
        // We mod by 'base' so we don't spill into the next magnitude
        uint256 noise = vm.randomUint() % base;

        uint256 result = base + noise;

        // 5. Cap at strict MAX_VAL (handle slight overflow at top magnitude)
        return result > MAX_VAL ? MAX_VAL : result;
    }

    function _deposit(uint256 amount) internal {
        (bool success,) =
            address(aaveBackend).delegatecall(abi.encodeWithSelector(AaveYieldBackend.deposit.selector, amount));
        require(success, "deposit failed");
    }

    /// @notice Helper function to log amount in fixed point format (integer.fractional)
    function _logFixedPoint(string memory label, uint256 amount) internal pure {
        console.log(string.concat(label, " ", vm.toString(amount / 1e6), ".", vm.toString(amount % 1e6)));
    }

    /// @notice Helper function to perform a withdraw and return results
    function _withdrawAndGetResults(uint256 requestedAmount)
        internal
        returns (
            uint256 assetAmountReceived,
            uint256 aTokenAmountDecrease,
            int256 diffAssetRequestedReceived,
            int256 diffAtokenExpectedDecreased
        )
    {
        uint256 aTokenBalanceBefore = aToken.balanceOf(address(this));
        uint256 assetBalanceBefore = assetToken.balanceOf(address(this));

        (bool success,) = address(aaveBackend).delegatecall(
            abi.encodeWithSelector(AaveYieldBackend.withdraw.selector, requestedAmount)
        );
        require(success, "withdraw failed");

        uint256 aTokenBalanceAfter = aToken.balanceOf(address(this));
        uint256 assetBalanceAfter = assetToken.balanceOf(address(this));

        assetAmountReceived = assetBalanceAfter - assetBalanceBefore;
        aTokenAmountDecrease = aTokenBalanceBefore - aTokenBalanceAfter;

        diffAssetRequestedReceived = int256(assetAmountReceived) - int256(requestedAmount);
        diffAtokenExpectedDecreased = int256(assetAmountReceived) - int256(aTokenAmountDecrease);
    }

    /// @notice Test deposit/withdraw loop with random amounts
    /// This is to verify that the rounding error of the aToken decrease is narronwly bounded.
    function testDepositWithdrawLoop() public {
        // Do an initial deposit of 1 USDC that is not withdrawn
        // This provides a buffer against small rounding discrepancies which cause the
        // aToken amount to not precisely match the asset amount.
        uint256 initialDeposit = 1 * 1e6;
        _deposit(initialDeposit);

        uint256 iterations = 1000;

        for (uint256 i = 0; i < iterations; ++i) {
            uint256 randomAmount = _getRandomWithExpDistribution();
            if (randomAmount == 1) {
                // getting a revert with InvalidAmount() for 1
                randomAmount = 2;
            }

            _deposit(randomAmount);

            (
                uint256 assetAmountReceived,
                uint256 aTokenAmountDecrease,
                int256 diffAssetRequestedReceived,
                int256 diffAtokenExpectedDecreased
            ) = _withdrawAndGetResults(randomAmount);

            console.log("=== Iteration", i + 1, "===");
            console.log(
                string.concat(
                    "assetAmount requested: ", vm.toString(randomAmount / 1e6), ".", vm.toString(randomAmount % 1e6)
                )
            );
            console.log(
                string.concat(
                    "assetAmount received: ",
                    vm.toString(assetAmountReceived / 1e6),
                    ".",
                    vm.toString(assetAmountReceived % 1e6)
                )
            );
            console.log(
                string.concat(
                    "aTokenAmount decrease: ",
                    vm.toString(aTokenAmountDecrease / 1e6),
                    ".",
                    vm.toString(aTokenAmountDecrease % 1e6)
                )
            );
            console.log("diff (aToken decrease expected / actual):", vm.toString(diffAtokenExpectedDecreased));

            assertEq(diffAssetRequestedReceived, 0, "diffAssetRequestedReceived is not 0");
            assertGe(diffAtokenExpectedDecreased, -2, "diffAtokenExpectedDecreased is < -2");
        }
    }
}
