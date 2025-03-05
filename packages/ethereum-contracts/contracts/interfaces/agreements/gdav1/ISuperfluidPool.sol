// SPDX-License-Identifier: AGPLv3
pragma solidity >=0.8.4;

import { IERC20, IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { ISuperfluidToken } from "../../superfluid/ISuperfluidToken.sol";

/**
 * @dev The interface for any super token pool regardless of the distribution schemes.
 */
interface ISuperfluidPool is IERC20, IERC20Metadata {
    // Custom Errors

    error SUPERFLUID_POOL_INVALID_TIME();               // 0x83c35016
    error SUPERFLUID_POOL_NO_POOL_MEMBERS();            // 0xe10f405a
    error SUPERFLUID_POOL_NO_ZERO_ADDRESS();            // 0x54eb6ee6
    error SUPERFLUID_POOL_NOT_POOL_ADMIN_OR_GDA();      // 0x1c5fbdcb
    error SUPERFLUID_POOL_NOT_GDA();                    // 0xfcbe3f9e
    error SUPERFLUID_POOL_TRANSFER_UNITS_NOT_ALLOWED(); // 0x2285efba
    error SUPERFLUID_POOL_SELF_TRANSFER_NOT_ALLOWED();  // 0xceddc0be

    // Events
    event MemberUnitsUpdated(
        ISuperfluidToken indexed token, address indexed member, uint128 oldUnits, uint128 newUnits
    );
    event DistributionClaimed(
        ISuperfluidToken indexed token, address indexed member, int256 claimedAmount, int256 totalClaimed
    );

    /// @notice A boolean indicating whether pool members can transfer their units
    function transferabilityForUnitsOwner() external view returns (bool);

    /// @notice A boolean indicating whether addresses other than the pool admin can distribute via the pool
    function distributionFromAnyAddress() external view returns (bool);

    /// @notice The pool admin
    /// @dev The admin is the creator of the pool and has permissions to update member units
    /// and is the recipient of the adjustment flow rate
    function admin() external view returns (address);

    /// @notice The SuperToken for the pool
    function superToken() external view returns (ISuperfluidToken);

    /// @notice The total units of the pool
    function getTotalUnits() external view returns (uint128);

    /// @notice The total number of units of connected members
    function getTotalConnectedUnits() external view returns (uint128);

    /// @notice The total number of units of disconnected members
    function getTotalDisconnectedUnits() external view returns (uint128);

    /// @notice The total number of units for `memberAddr`
    /// @param memberAddr The address of the member
    function getUnits(address memberAddr) external view returns (uint128);

    /// @notice The total flow rate of the pool
    function getTotalFlowRate() external view returns (int96);

    /// @notice The flow rate of the connected members
    function getTotalConnectedFlowRate() external view returns (int96);

    /// @notice The flow rate of the disconnected members
    function getTotalDisconnectedFlowRate() external view returns (int96);

    /// @notice The balance of all the disconnected members at `time`
    /// @param time The time to query
    function getDisconnectedBalance(uint32 time) external view returns (int256 balance);

    /// @notice The total amount received by `memberAddr` in the pool
    /// @param memberAddr The address of the member
    /// @return totalAmountReceived The total amount received by the member
    function getTotalAmountReceivedByMember(address memberAddr) external view returns (uint256 totalAmountReceived);

    /// @notice The flow rate a member is receiving from the pool
    /// @param memberAddr The address of the member
    function getMemberFlowRate(address memberAddr) external view returns (int96);

    /// @notice The claimable balance for `memberAddr` at `time` in the pool
    /// @param memberAddr The address of the member
    /// @param time The time to query
    function getClaimable(address memberAddr, uint32 time) external view returns (int256);

    /// @notice The claimable balance for `memberAddr` at `block.timestamp` in the pool
    /// @param memberAddr The address of the member
    function getClaimableNow(address memberAddr) external view returns (int256 claimableBalance, uint256 timestamp);

    /// @notice Sets `memberAddr` ownedUnits to `newUnits`
    /// @param memberAddr The address of the member
    /// @param newUnits The new units for the member
    function updateMemberUnits(address memberAddr, uint128 newUnits) external returns (bool);

    /// @notice Claims the claimable balance for `memberAddr` at `block.timestamp`
    /// @param memberAddr The address of the member
    function claimAll(address memberAddr) external returns (bool);

    /// @notice Claims the claimable balance for `msg.sender` at `block.timestamp`
    function claimAll() external returns (bool);

    /// @notice Increases the allowance of `spender` by `addedValue`
    /// @param spender The address of the spender
    /// @param addedValue The amount to increase the allowance by
    /// @return true if successful
    function increaseAllowance(address spender, uint256 addedValue) external returns (bool);

    /// @notice Decreases the allowance of `spender` by `subtractedValue`
    /// @param spender The address of the spender
    /// @param subtractedValue The amount to decrease the allowance by
    /// @return true if successful
    function decreaseAllowance(address spender, uint256 subtractedValue) external returns (bool);
}
