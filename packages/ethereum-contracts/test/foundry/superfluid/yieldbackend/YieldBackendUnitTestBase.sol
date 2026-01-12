// SPDX-License-Identifier: AGPLv3
pragma solidity ^0.8.23;

import { Test } from "forge-std/Test.sol";
import { console } from "forge-std/console.sol";
import { IYieldBackend } from "../../../../contracts/interfaces/superfluid/IYieldBackend.sol";
import { IERC20 } from "../../../../contracts/interfaces/superfluid/ISuperfluid.sol";

/**
 * @title YieldBackendUnitTestBase
 * @notice Abstract base contract for unit testing yield backends in isolation.
 * @notice The test contract itself takes the role of SuperToken for delegatecall operations.
 * @notice Concrete implementations must provide backend-specific setup and configuration.
 */
abstract contract YieldBackendUnitTestBase is Test {
    // Constants (defined by concrete implementations)
    address internal constant SURPLUS_RECEIVER = 0xac808840f02c47C05507f48165d2222FF28EF4e1; // dao.superfluid.eth

    // State variables (set by concrete implementations)
    IYieldBackend internal backend;
    IERC20 internal assetToken;

    // ============ Abstract functions for network configuration ============

    /// @notice Get the RPC URL for forking
    function getRpcUrl() internal pure virtual returns (string memory);

    /// @notice Get the expected chain ID
    function getChainId() internal pure virtual returns (uint256);

    /// @notice Set up the test environment - must be implemented by concrete tests
    function setUp() public virtual {
        vm.createSelectFork(getRpcUrl());
        assertEq(block.chainid, getChainId(), "Chainid mismatch");
        
        // Deploy and configure backend (implemented by concrete tests)
        backend = createBackend();
        assetToken = getAssetToken();
        
        // Fund the test contract with underlying asset
        fundTestContract();
        
        // Enable the backend (usually sets ERC20 approvals)
        (bool success,) = address(backend).delegatecall(
            abi.encodeWithSelector(IYieldBackend.enable.selector)
        );
        require(success, "enable failed");
    }

    /// @notice Mock of toUnderlyingAmount - assumes 18 decimals by default
    /// @dev Can be overridden in concrete tests for different decimal configurations
    function toUnderlyingAmount(uint256 amount)
        external
        pure
        virtual
        returns (uint256 underlyingAmount, uint256 adjustedAmount)
    {
        // Default: assume same decimals (18)
        underlyingAmount = amount;
        adjustedAmount = amount;
    }

    // ============ Abstract functions to be implemented by concrete tests ============

    /// @notice Get the yield backend instance
    function createBackend() internal virtual returns (IYieldBackend);

    /// @notice Get the underlying asset token
    function getAssetToken() internal virtual returns (IERC20);

    /// @notice Fund the test contract with underlying asset
    function fundTestContract() internal virtual;

    /// @notice Get the asset token decimals (for proper amount handling)
    function getAssetDecimals() internal pure virtual returns (uint8);

    // ============ Helper functions ============

    /// @notice Execute deposit via delegatecall
    function _deposit(uint256 amount) internal {
        (bool success,) = address(backend).delegatecall(
            abi.encodeWithSelector(IYieldBackend.deposit.selector, amount)
        );
        require(success, "deposit failed");
    }

    /// @notice Execute withdraw via delegatecall
    function _withdraw(uint256 amount) internal {
        (bool success, ) = address(backend).delegatecall(
            abi.encodeWithSelector(IYieldBackend.withdraw.selector, amount)
        );
        require(success, "withdraw failed");
    }

    /// @notice Execute withdrawMax via delegatecall
    function _withdrawMax() internal {
        (bool success,) = address(backend).delegatecall(
            abi.encodeWithSelector(IYieldBackend.withdrawMax.selector)
        );
        require(success, "withdrawMax failed");
    }

    /// @notice Execute withdrawSurplus via delegatecall
    function _withdrawSurplus(uint256 totalSupply) internal {
        (bool success,) = address(backend).delegatecall(
            abi.encodeWithSelector(IYieldBackend.withdrawSurplus.selector, totalSupply)
        );
        require(success, "withdrawSurplus failed");
    }

    /// @notice Execute enable via delegatecall
    function _enable() internal {
        (bool success,) = address(backend).delegatecall(
            abi.encodeWithSelector(IYieldBackend.enable.selector)
        );
        require(success, "enable failed");
    }

    /// @notice Execute disable via delegatecall
    function _disable() internal {
        (bool success,) = address(backend).delegatecall(
            abi.encodeWithSelector(IYieldBackend.disable.selector)
        );
        require(success, "disable failed");
    }

    // ============ Test functions ============

    /// @notice Test enable() - assert: approval set
    function testEnable() public view {
        // already enabled in setUp
        // Verify approval is set to max
        uint256 allowanceAfter = assetToken.allowance(address(this), _getProtocolAddress());
        assertEq(allowanceAfter, type(uint256).max, "approval should be max after enable");
    }

    /// @notice Test disable() - assert: approval revoked
    function testDisable() public {
        // Disable backend
        _disable();
        
        // Check approval is revoked
        uint256 allowance = assetToken.allowance(address(this), _getProtocolAddress());
        assertEq(allowance, 0, "approval should be revoked");
    }

    /// @notice Test deposit() - assert: underlying asset balance decreased by amount
    function testDeposit(uint256 amount) public {
        amount = _boundAmount(amount);
        
        // Fund contract with more than amount
        _fundAsset(amount * 2);
        
        uint256 balanceBefore = _getAssetBalance();
        _deposit(amount);
        uint256 balanceAfter = _getAssetBalance();
        
        assertEq(balanceBefore - balanceAfter, amount, "balance should decrease by amount");
    }

    /// @notice Test withdraw() - assert: underlying asset balance increased by amount
    function testWithdraw(uint256 amount) public {
        amount = _boundAmount(amount);
        
        // Fund, deposit, then withdraw
        _fundAsset(amount * 2);
        _deposit(amount * 2);
        
        uint256 balanceBefore = _getAssetBalance();
        
        _withdraw(amount);
        
        uint256 balanceAfter = _getAssetBalance();
        
        assertEq(balanceAfter - balanceBefore, amount, "balance should increase by amount");
    }

    /// @notice Test withdrawMax() - prep: deposit random amount, fast forward random time
    /// @notice assert: balance after is > balance before (accrued yield)
    function testWithdrawMax(uint256 depositAmount, uint256 timeForward) public {
        depositAmount = _boundAmount(depositAmount);
        // Fast forward between 1 hour and 365 days
        timeForward = bound(timeForward, 1 hours, 365 days);
        
        // Fund and deposit
        _fundAsset(depositAmount);
        _deposit(depositAmount);
        
        // Fast forward time to accrue yield
        vm.warp(block.timestamp + timeForward);
        
        // Record balance before withdrawMax
        uint256 balanceBefore = _getAssetBalance();
        
        // Withdraw max
        _withdrawMax();
        
        // Record balance after
        uint256 balanceAfter = _getAssetBalance();
        
        // Balance after should be greater than before (yield accrued)
        assertGt(balanceAfter, balanceBefore, "balance after should be greater (yield accrued)");
    }

    /// @notice Test withdrawSurplus() - prep: deposit random amount, fast forward random time
    /// @notice assert: surplus receiver balance increased
    /// @dev Note: For ETH backends, surplus is paid in WETH, not ETH
    function testWithdrawSurplus(uint256 depositAmount, uint256 timeForward) public {
        depositAmount = _boundAmount(depositAmount);
        // Fast forward between 1 hour and 365 days
        timeForward = bound(timeForward, 1 hours, 365 days);
        
        // Fund and deposit
        _fundAsset(depositAmount);
        _deposit(depositAmount);
        
        // Fast forward time to accrue yield
        vm.warp(block.timestamp + timeForward);
        
        // Calculate total supply (in 18 decimals)
        uint256 totalSupply = depositAmount;
        // Note: normalizedTotalSupply not used directly, but toUnderlyingAmount is called for consistency
        this.toUnderlyingAmount(totalSupply);
        
        // Record surplus receiver balance before
        uint256 receiverBalanceBefore = _getSurplusReceiverBalance();
        
        // Withdraw surplus
        _withdrawSurplus(totalSupply);
        
        // Record surplus receiver balance after
        uint256 receiverBalanceAfter = _getSurplusReceiverBalance();
        
        // Receiver balance should increase
        assertGt(receiverBalanceAfter, receiverBalanceBefore, "surplus receiver balance should increase");
    }

    // ============ Internal helper functions ============

    /// @notice Bound amount to reasonable range based on asset decimals
    /// @dev Can be overridden in concrete tests for custom bounds
    function _boundAmount(uint256 amount) internal view virtual returns (uint256) {
        uint8 decimals = getAssetDecimals();
        uint256 minAmount = 10 ** decimals; // 1 token
        uint256 maxAmount = 1_000_000 * 10 ** decimals; // 1M tokens
        return bound(amount, minAmount, maxAmount);
    }

    /// @notice Fund the test contract with underlying asset
    function _fundAsset(uint256 amount) internal virtual {
        deal(address(assetToken), address(this), amount);
    }

    /// @notice Get the underlying asset balance of this contract
    function _getAssetBalance() internal view virtual returns (uint256) {
        return assetToken.balanceOf(address(this));
    }

    /// @notice Get the protocol address that needs approval (e.g., Aave Pool, ERC4626 Vault)
    function _getProtocolAddress() internal view virtual returns (address);

    /// @notice Get the surplus receiver balance
    function _getSurplusReceiverBalance() internal view virtual returns (uint256) {
        return assetToken.balanceOf(SURPLUS_RECEIVER);
    }
}

