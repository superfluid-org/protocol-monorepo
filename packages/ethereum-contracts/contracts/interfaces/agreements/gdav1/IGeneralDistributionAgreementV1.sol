// SPDX-License-Identifier: AGPLv3
pragma solidity >=0.8.4;

import { ISuperAgreement } from "../../superfluid/ISuperAgreement.sol";
import { ISuperfluidToken } from "../../superfluid/ISuperfluidToken.sol";
import { ISuperfluidPool } from "../../agreements/gdav1/ISuperfluidPool.sol";

struct PoolConfig {
    /// @dev if true, the pool members can transfer their owned units
    /// else, only the pool admin can manipulate the units for pool members
    bool transferabilityForUnitsOwner;
    /// @dev if true, anyone can execute distributions via the pool
    /// else, only the pool admin can execute distributions via the pool
    bool distributionFromAnyAddress;
}

struct PoolERC20Metadata {
    string name;
    string symbol;
    uint8 decimals;
}

/**
 * @title General Distribution Agreement interface
 * @author Superfluid
 */
abstract contract IGeneralDistributionAgreementV1 is ISuperAgreement {

    // Custom Errors
    error GDA_DISTRIBUTE_FOR_OTHERS_NOT_ALLOWED();          // 0xf67d263e
    error GDA_DISTRIBUTE_FROM_ANY_ADDRESS_NOT_ALLOWED();    // 0x7761a5e5
    error GDA_FLOW_DOES_NOT_EXIST();                        // 0x29f4697e
    error GDA_NON_CRITICAL_SENDER();                        // 0x666f381d
    error GDA_INSUFFICIENT_BALANCE();                       // 0x33115c3f
    error GDA_NO_NEGATIVE_FLOW_RATE();                      // 0x15f25663
    error GDA_ADMIN_CANNOT_BE_POOL();                       // 0x9ab88a26
    error GDA_NOT_POOL_ADMIN();                             // 0x3a87e565
    error GDA_NO_ZERO_ADDRESS_ADMIN();                      // 0x82c5d837
    error GDA_ONLY_SUPER_TOKEN_POOL();                      // 0x90028c37


    // Events
    event InstantDistributionUpdated(
        ISuperfluidToken indexed token,
        ISuperfluidPool indexed pool,
        address indexed distributor,
        address operator,
        uint256 requestedAmount,
        uint256 actualAmount,
        bytes userData
    );

    event FlowDistributionUpdated(
        ISuperfluidToken indexed token,
        ISuperfluidPool indexed pool,
        address indexed distributor,
        // operator's have permission to liquidate critical flows
        // on behalf of others
        address operator,
        int96 oldFlowRate,
        int96 newDistributorToPoolFlowRate,
        int96 newTotalDistributionFlowRate,
        address adjustmentFlowRecipient,
        int96 adjustmentFlowRate,
        bytes userData
    );

    event PoolCreated(ISuperfluidToken indexed token, address indexed admin, ISuperfluidPool pool);

    event PoolConnectionUpdated(
        ISuperfluidToken indexed token,
        ISuperfluidPool indexed pool,
        address indexed account,
        bool connected,
        bytes userData
    );

    event BufferAdjusted(
        ISuperfluidToken indexed token,
        ISuperfluidPool indexed pool,
        address indexed from,
        int256 bufferDelta,
        uint256 newBufferAmount,
        uint256 totalBufferAmount
    );

    /// @dev ISuperAgreement.agreementType implementation
    function agreementType() external pure override returns (bytes32) {
        return keccak256("org.superfluid-finance.agreements.GeneralDistributionAgreement.v1");
    }

    /// @dev Gets the GDA net flow rate of `account` for `token`.
    /// @param token The token address
    /// @param account The account address
    /// @return net flow rate
    function getNetFlow(ISuperfluidToken token, address account) external view virtual returns (int96);

    /// @notice Gets the GDA flow rate of `from` to `to` for `token`.
    /// @dev This is primarily used to get the flow distribution flow rate from a distributor to a pool or the
    /// adjustment flow rate of a pool.
    /// @param token The token address
    /// @param from The sender address
    /// @param to The receiver address (the pool)
    /// @return flow rate
    function getFlowRate(ISuperfluidToken token, address from, ISuperfluidPool to)
        external
        view
        virtual
        returns (int96);

    /// @dev Gets the GDA flow data between `from` and `to` of `token`
    /// @param token The token address
    /// @param from The sender address
    /// @param to The receiver address
    /// @return lastUpdated The timestamp of when the flow was last updated
    /// @return flowRate The flow rate
    /// @return deposit The amount of deposit the flow
    function getFlow(ISuperfluidToken token, address from, ISuperfluidPool to)
        external
        view
        virtual
        returns (uint256 lastUpdated, int96 flowRate, uint256 deposit);

    /// @dev Gets the aggregated GDA flow info of `account` for `token`
    /// @param token The token address
    /// @param account The account address
    /// @return timestamp The timestamp of when the flow was last updated for account
    /// @return flowRate The net flow rate of token for account
    /// @return deposit The sum of all deposits for account's flows
    function getAccountFlowInfo(ISuperfluidToken token, address account)
        external
        view
        virtual
        returns (uint256 timestamp, int96 flowRate, uint256 deposit);

    /// @notice Executes an optimistic estimation of what the actual flow distribution flow rate may be.
    /// The actual flow distribution flow rate is the flow rate that will be sent from `from`.
    /// NOTE: this is only precise in an atomic transaction. DO NOT rely on this if querying off-chain.
    /// @dev The difference between the requested flow rate and the actual flow rate is the adjustment flow rate,
    /// this adjustment flow rate goes to the pool admin.
    /// @param token The token address
    /// @param from The sender address
    /// @param to The pool address
    /// @param requestedFlowRate The requested flow rate
    /// @return actualFlowRate and totalDistributionFlowRate
    function estimateFlowDistributionActualFlowRate(
        ISuperfluidToken token,
        address from,
        ISuperfluidPool to,
        int96 requestedFlowRate
    ) external view virtual returns (int96 actualFlowRate, int96 totalDistributionFlowRate);

    /// @notice Executes an optimistic estimation of what the actual amount distributed may be.
    /// The actual amount distributed is the amount that will be sent from `from`.
    /// NOTE: this is only precise in an atomic transaction. DO NOT rely on this if querying off-chain.
    /// @dev The difference between the requested amount and the actual amount is the adjustment amount.
    /// @param token The token address
    /// @param from The sender address
    /// @param to The pool address
    /// @param requestedAmount The requested amount
    /// @return actualAmount
    function estimateDistributionActualAmount(
        ISuperfluidToken token,
        address from,
        ISuperfluidPool to,
        uint256 requestedAmount
    ) external view virtual returns (uint256 actualAmount);

    /// @notice Gets the adjustment flow rate of `pool` for `token`.
    /// @param pool The pool address
    /// @return adjustment flow rate
    function getPoolAdjustmentFlowRate(address pool) external view virtual returns (int96);

    ////////////////////////////////////////////////////////////////////////////////
    // Pool Operations
    ////////////////////////////////////////////////////////////////////////////////

    /// @notice Creates a new pool for `token` where the admin is `admin`.
    /// @param token The token address
    /// @param admin The admin of the pool
    /// @param poolConfig The pool configuration (see PoolConfig struct)
    function createPool(ISuperfluidToken token, address admin, PoolConfig memory poolConfig)
        external
        virtual
        returns (ISuperfluidPool pool);

    /// @notice Creates a new pool for `token` with custom ERC20 metadata.
    /// @param token The token address
    /// @param admin The admin of the pool
    /// @param poolConfig The pool configuration (see PoolConfig struct)
    /// @param poolERC20Metadata The pool ERC20 metadata (see PoolERC20Metadata struct)
    /// @return pool The pool address
    function createPoolWithCustomERC20Metadata(
        ISuperfluidToken token,
        address admin,
        PoolConfig memory poolConfig,
        PoolERC20Metadata memory poolERC20Metadata
    ) external virtual returns (ISuperfluidPool pool);

    function updateMemberUnits(ISuperfluidPool pool, address memberAddress, uint128 newUnits, bytes calldata ctx)
        external
        virtual
        returns (bytes memory newCtx);

    function claimAll(ISuperfluidPool pool, address memberAddress, bytes calldata ctx)
        external
        virtual
        returns (bytes memory newCtx);

    /// @notice Connects `msg.sender` to `pool`.
    /// @dev This is used to connect a pool to the GDA.
    /// @param pool The pool address
    /// @param ctx Context bytes (see ISuperfluid.sol for Context struct)
    /// @return newCtx the new context bytes
    function connectPool(ISuperfluidPool pool, bytes calldata ctx) external virtual returns (bytes memory newCtx);

    /// @notice Disconnects `msg.sender` from `pool`.
    /// @dev This is used to disconnect a pool from the GDA.
    /// @param pool The pool address
    /// @param ctx Context bytes (see ISuperfluidPoolAdmin for Context struct)
    /// @return newCtx the new context bytes
    function disconnectPool(ISuperfluidPool pool, bytes calldata ctx) external virtual returns (bytes memory newCtx);

    /// @notice Checks whether `account` is a pool.
    /// @param token The token address
    /// @param account The account address
    /// @return true if `account` is a pool
    function isPool(ISuperfluidToken token, address account) external view virtual returns (bool);

    /// Check if an address is connected to the pool
    function isMemberConnected(ISuperfluidPool pool, address memberAddr) external view virtual returns (bool);

    /// Get pool adjustment flow information: (recipient, flowHash, flowRate)
    function getPoolAdjustmentFlowInfo(ISuperfluidPool pool) external view virtual returns (address, bytes32, int96);

    ////////////////////////////////////////////////////////////////////////////////
    // Agreement Operations
    ////////////////////////////////////////////////////////////////////////////////

    /// @notice Tries to distribute `requestedAmount` of `token` from `from` to `pool`.
    /// @dev NOTE: The actual amount distributed may differ.
    /// @param token The token address
    /// @param from The sender address
    /// @param pool The pool address
    /// @param requestedAmount The requested amount
    /// @param ctx Context bytes (see ISuperfluidPool for Context struct)
    /// @return newCtx the new context bytes
    function distribute(
        ISuperfluidToken token,
        address from,
        ISuperfluidPool pool,
        uint256 requestedAmount,
        bytes calldata ctx
    ) external virtual returns (bytes memory newCtx);

    /// @notice Tries to distributeFlow `requestedFlowRate` of `token` from `from` to `pool`.
    /// @dev NOTE: The actual distribution flow rate may differ.
    /// @param token The token address
    /// @param from The sender address
    /// @param pool The pool address
    /// @param requestedFlowRate The requested flow rate
    /// @param ctx Context bytes (see ISuperfluidPool for Context struct)
    /// @return newCtx the new context bytes
    function distributeFlow(
        ISuperfluidToken token,
        address from,
        ISuperfluidPool pool,
        int96 requestedFlowRate,
        bytes calldata ctx
    ) external virtual returns (bytes memory newCtx);

    ////////////////////////////////////////////////////////////////////////////////
    // Solvency Functions
    ////////////////////////////////////////////////////////////////////////////////

    /**
     * @dev Returns whether it is the patrician period based on host.getNow()
     * @param account The account we are interested in
     * @return isCurrentlyPatricianPeriod Whether it is currently the patrician period dictated by governance
     * @return timestamp The value of host.getNow()
     */
    function isPatricianPeriodNow(ISuperfluidToken token, address account)
        external
        view
        virtual
        returns (bool isCurrentlyPatricianPeriod, uint256 timestamp);

    /**
     * @dev Returns whether it is the patrician period based on timestamp
     * @param account The account we are interested in
     * @param timestamp The timestamp we are interested in observing the result of isPatricianPeriod
     * @return bool Whether it is currently the patrician period dictated by governance
     */
    function isPatricianPeriod(ISuperfluidToken token, address account, uint256 timestamp)
        public
        view
        virtual
        returns (bool);
}
