// SPDX-License-Identifier: AGPLv3
pragma solidity ^0.8.23;

import { ISuperfluid, ISuperfluidToken } from "../interfaces/superfluid/ISuperfluid.sol";
import { ISuperfluidPool } from "../agreements/gdav1/SuperfluidPool.sol";
import {
    IGeneralDistributionAgreementV1,
    PoolConfig
} from "../interfaces/agreements/gdav1/IGeneralDistributionAgreementV1.sol";
import { ForwarderBase } from "./ForwarderBase.sol";

/**
 * @title GDAv1Forwarder
 * @author Superfluid
 * The GDAv1Forwarder contract provides an easy to use interface to
 * GeneralDistributionAgreementV1 specific functionality of Super Tokens.
 * Instances of this contract can operate on the protocol only if configured as "trusted forwarder"
 * by protocol governance.
 */
contract GDAv1Forwarder is ForwarderBase {
    IGeneralDistributionAgreementV1 internal immutable _gda;

    // is tied to a specific instance of host and agreement contracts at deploy time
    constructor(ISuperfluid host) ForwarderBase(host) {
        _gda = IGeneralDistributionAgreementV1(
            address(
                _host.getAgreementClass(keccak256("org.superfluid-finance.agreements.GeneralDistributionAgreement.v1"))
            )
        );
    }

    /**
     * @dev Creates a new Superfluid Pool.
     * @param token The Super Token address.
     * @param admin The pool admin address.
     * @param config The pool configuration (see PoolConfig in IGeneralDistributionAgreementV1.sol)
     * @return success A boolean value indicating whether the pool was created successfully.
     * @return pool The address of the deployed Superfluid Pool
     */
    function createPool(ISuperfluidToken token, address admin, PoolConfig memory config)
        external
        returns (bool success, ISuperfluidPool pool)
    {
        pool = _gda.createPool(token, admin, config);
        success = true;
    }

    /**
     * @dev Updates the units of a pool member.
     * @param pool The Superfluid Pool to update.
     * @param memberAddress The address of the member to update.
     * @param newUnits The new units of the member.
     * @param userData User-specific data.
     */
    function updateMemberUnits(ISuperfluidPool pool, address memberAddress, uint128 newUnits, bytes memory userData)
        external
        returns (bool success)
    {
        bytes memory callData = abi.encodeCall(_gda.updateMemberUnits, (pool, memberAddress, newUnits, new bytes(0)));

        return _forwardBatchCall(address(_gda), callData, userData);
    }

    /**
     * @dev Claims all tokens from the pool.
     * @param pool The Superfluid Pool to claim from.
     * @param memberAddress The address of the member to claim for.
     * @param userData User-specific data.
     */
    function claimAll(ISuperfluidPool pool, address memberAddress, bytes memory userData)
        external
        returns (bool success)
    {
        bytes memory callData = abi.encodeCall(_gda.claimAll, (pool, memberAddress, new bytes(0)));

        return _forwardBatchCall(address(_gda), callData, userData);
    }

    /**
     * @dev Connects a pool member to `pool`.
     * @param pool The Superfluid Pool to connect.
     * @param userData User-specific data.
     * @return A boolean value indicating whether the connection was successful.
     */
    function connectPool(ISuperfluidPool pool, bytes memory userData) external returns (bool) {
        bytes memory callData = abi.encodeCall(_gda.connectPool, (pool, new bytes(0)));

        return _forwardBatchCall(address(_gda), callData, userData);
    }

    /**
     * @dev Disconnects a pool member from `pool`.
     * @param pool The Superfluid Pool to disconnect.
     * @param userData User-specific data.
     * @return A boolean value indicating whether the disconnection was successful.
     */
    function disconnectPool(ISuperfluidPool pool, bytes memory userData) external returns (bool) {
        bytes memory callData = abi.encodeCall(_gda.disconnectPool, (pool, new bytes(0)));

        return _forwardBatchCall(address(_gda), callData, userData);
    }

    /**
     * @dev Tries to distribute `requestedAmount` amount of `token` from `from` to `pool`.
     * @param token The Super Token address.
     * @param from The address from which to distribute tokens.
     * @param pool The Superfluid Pool address.
     * @param requestedAmount The amount of tokens to distribute.
     * @param userData User-specific data.
     * @return A boolean value indicating whether the distribution was successful.
     */
    function distribute(
        ISuperfluidToken token,
        address from,
        ISuperfluidPool pool,
        uint256 requestedAmount,
        bytes memory userData
    ) external returns (bool) {
        bytes memory callData = abi.encodeCall(_gda.distribute, (token, from, pool, requestedAmount, new bytes(0)));

        return _forwardBatchCall(address(_gda), callData, userData);
    }

    /**
     * @dev Tries to distribute flow at `requestedFlowRate` of `token` from `from` to `pool`.
     * @param token The Super Token address.
     * @param from The address from which to distribute tokens.
     * @param pool The Superfluid Pool address.
     * @param requestedFlowRate The flow rate of tokens to distribute.
     * @param userData User-specific data.
     * @return A boolean value indicating whether the distribution was successful.
     */
    function distributeFlow(
        ISuperfluidToken token,
        address from,
        ISuperfluidPool pool,
        int96 requestedFlowRate,
        bytes memory userData
    ) external returns (bool) {
        bytes memory callData =
            abi.encodeCall(_gda.distributeFlow, (token, from, pool, requestedFlowRate, new bytes(0)));

        return _forwardBatchCall(address(_gda), callData, userData);
    }

    /**
     * @dev Checks if the specified account is a pool.
     * @param token The Super Token address.
     * @param account The account address to check.
     * @return A boolean value indicating whether the account is a pool.
     */
    function isPool(ISuperfluidToken token, address account) external view virtual returns (bool) {
        return _gda.isPool(token, account);
    }

    /**
     * @dev Gets the GDA net flow rate for the specified account.
     * @param token The Super Token address.
     * @param account The account address.
     * @return The gda net flow rate for the account.
     */
    function getNetFlow(ISuperfluidToken token, address account) external view returns (int96) {
        return _gda.getNetFlow(token, account);
    }

    /**
     * @dev Gets the flow rate of tokens between the specified accounts.
     * @param token The Super Token address.
     * @param from The sender address.
     * @param to The receiver address (the pool address).
     * @return The flow distribution flow rate
     */
    function getFlowDistributionFlowRate(ISuperfluidToken token, address from, ISuperfluidPool to)
        external
        view
        returns (int96)
    {
        return _gda.getFlowRate(token, from, to);
    }

    /**
     * @dev Gets the pool adjustment flow rate for the specified pool.
     * @param pool The pool address.
     * @return The pool adjustment flow rate.
     */
    function getPoolAdjustmentFlowRate(address pool) external view virtual returns (int96) {
        return _gda.getPoolAdjustmentFlowRate(pool);
    }

    /**
     * @dev Estimates the actual flow rate for flow distribution to the specified pool.
     * @param token The Super Token address.
     * @param from The sender address.
     * @param to The pool address.
     * @param requestedFlowRate The requested flow rate.
     * @return actualFlowRate
     * @return totalDistributionFlowRate
     */
    function estimateFlowDistributionActualFlowRate(
        ISuperfluidToken token,
        address from,
        ISuperfluidPool to,
        int96 requestedFlowRate
    ) external view returns (int96 actualFlowRate, int96 totalDistributionFlowRate) {
        return _gda.estimateFlowDistributionActualFlowRate(token, from, to, requestedFlowRate);
    }

    /**
     * @dev Estimates the actual amount for distribution to the specified pool.
     * @param token The Super Token address.
     * @param from The sender address.
     * @param to The pool address.
     * @param requestedAmount The requested amount.
     * @return actualAmount The actual amount for distribution.
     */
    function estimateDistributionActualAmount(
        ISuperfluidToken token,
        address from,
        ISuperfluidPool to,
        uint256 requestedAmount
    ) external view returns (uint256 actualAmount) {
        return _gda.estimateDistributionActualAmount(token, from, to, requestedAmount);
    }

    /**
     * @dev Checks if the specified member is connected to the pool.
     * @param pool The Superfluid Pool address.
     * @param member The member address.
     * @return A boolean value indicating whether the member is connected to the pool.
     */
    function isMemberConnected(ISuperfluidPool pool, address member) external view returns (bool) {
        return _gda.isMemberConnected(pool, member);
    }

    /**
     * @dev Gets the pool adjustment flow information for the specified pool.
     * @param pool The pool address.
     * @return The pool admin, pool ID, and pool adjustment flow rate.
     */
    function getPoolAdjustmentFlowInfo(ISuperfluidPool pool) external view virtual returns (address, bytes32, int96) {
        return _gda.getPoolAdjustmentFlowInfo(pool);
    }
}
