// SPDX-License-Identifier: AGPLv3
pragma solidity ^0.8.23;

import { ISuperfluid, ISuperToken } from "../interfaces/superfluid/ISuperfluid.sol";
import { SuperAppDefinitions } from "../interfaces/superfluid/ISuperfluid.sol";
import { ISuperfluidPool } from "../interfaces/agreements/gdav1/ISuperfluidPool.sol";
import { PoolConfig } from "../interfaces/agreements/gdav1/IGeneralDistributionAgreementV1.sol";
import { SuperAppBase } from "../apps/SuperAppBase.sol";
import { SuperTokenV1Library } from "../apps/SuperTokenV1Library.sol";

contract SuperTokenLibraryCFAMock {

    using SuperTokenV1Library for ISuperToken;

     /**************************************************************************
     * View Functions
     *************************************************************************/

    function getFlowRateTest(
        ISuperToken token,
        address sender,
        address receiver
    ) public view returns (int96 rate) {
        return token.getFlowRate(sender, receiver);
    }

    function getFlowInfoTest(
        ISuperToken token,
        address sender,
        address receiver
    ) public view returns (uint256 lastUpdated, int96 flowRate, uint256 deposit, uint256 owedDeposit) {
        return token.getFlowInfo(sender, receiver);
    }

    function getNetFlowRateTest(
        ISuperToken token,
        address account
    ) public view returns (int96 netFlowRate) {
        return token.getNetFlowRate(account);
    }

    function getNetFlowInfoTest(
        ISuperToken token,
        address account
    ) public view returns  (uint256 lastUpdated, int96 flowRate, uint256 deposit, uint256 owedDeposit) {
        return token.getNetFlowInfo(account);
    }

    function getBufferAmountByFlowRateTest(
        ISuperToken token,
        int96 flowRate
    ) public view returns (uint256 bufferAmount) {
        return token.getBufferAmountByFlowRate(flowRate);
    }

    function getFlowPermissionsTest(
        ISuperToken token,
        address sender,
        address flowOperator
    ) public view returns (bool allowCreate, bool allowUpdate, bool allowDelete, int96 flowRateAllowance) {
        return token.getFlowPermissions(sender, flowOperator);
    }


      /**************************************************************************
     * CFA Operations
     *************************************************************************/

    function createFlowTest(
        ISuperToken token,
        address receiver,
        int96 flowRate
    ) public {
        token.createFlow(receiver, flowRate);
    }

    function createFlowWithUserDataTest(
        ISuperToken token,
        address receiver,
        int96 flowRate,
        bytes memory userData
    ) public {
        token.createFlow(receiver, flowRate, userData);
    }

    function deleteFlowTest(
        ISuperToken token,
        address sender,
        address receiver
    ) public {
        token.deleteFlow(sender, receiver);
    }

    function deleteFlowWithUserDataTest(
        ISuperToken token,
        address sender,
        address receiver,
        bytes memory userData
    ) public {
        token.deleteFlow(sender, receiver, userData);
    }

    function updateFlowWithUserDataTest(
        ISuperToken token,
        address receiver,
        int96 flowRate,
        bytes memory userData
    ) public {
        token.updateFlow(receiver, flowRate, userData);
    }

    function updateFlowTest(
        ISuperToken token,
        address receiver,
        int96 flowRate
    ) public {
        token.updateFlow(receiver, flowRate);
    }

    function createFlowFromTest(
        ISuperToken token,
        address sender,
        address receiver,
        int96 flowRate
    ) public {
        token.createFlowFrom(sender, receiver, flowRate);
    }

    function createFlowFromWithUserDataTest(
        ISuperToken token,
        address sender,
        address receiver,
        int96 flowRate,
        bytes memory userData
    ) public {
        token.createFlowFrom(sender, receiver, flowRate, userData);
    }

    function deleteFlowFromTest(
        ISuperToken token,
        address sender,
        address receiver
    ) public {
        token.deleteFlowFrom(sender, receiver);
    }

    function deleteFlowFromWithUserDataTest(
        ISuperToken token,
        address sender,
        address receiver,
        bytes memory userData
    ) public {
        token.deleteFlowFrom(sender, receiver, userData);
    }

    function updateFlowFromTest(
        ISuperToken token,
        address sender,
        address receiver,
        int96 flowRate
    ) public {
        token.updateFlowFrom(sender, receiver, flowRate);
    }

    function updateFlowFromWithUserDataTest(
        ISuperToken token,
        address sender,
        address receiver,
        int96 flowRate,
        bytes memory userData
    ) public {
        token.updateFlowFrom(sender, receiver, flowRate, userData);
    }

    function setFlowPermissionsTest(
        ISuperToken token,
        address flowOperator,
        bool allowCreate,
        bool allowUpdate,
        bool allowDelete,
        int96 flowRateAllowance
    ) public {
        token.setFlowPermissions(flowOperator, allowCreate, allowUpdate, allowDelete, flowRateAllowance);
    }


    function setMaxFlowPermissionsTest(
        address flowOperator,
        ISuperToken token
    ) public {
        token.setMaxFlowPermissions(flowOperator);
    }

    function revokeFlowPermissionsTest(
        address flowOperator,
        ISuperToken token
    ) public {
        token.revokeFlowPermissions(flowOperator);
    }

    function increaseFlowRateAllowanceTest(ISuperToken token, address flowOperator, int96 addedFlowRateAllowance)
        public
    {
        token.increaseFlowRateAllowance(flowOperator, addedFlowRateAllowance);
    }

    function decreaseFlowRateAllowanceTest(ISuperToken token, address flowOperator, int96 subtractedFlowRateAllowance)
        public
    {
        token.decreaseFlowRateAllowance(flowOperator, subtractedFlowRateAllowance);
    }

    function increaseFlowRateAllowanceWithUserDataTest(
        ISuperToken token,
        address flowOperator,
        int96 addedFlowRateAllowance,
        bytes memory userData
    ) public {
        token.increaseFlowRateAllowance(flowOperator, addedFlowRateAllowance, userData);
    }

    function decreaseFlowRateAllowanceWithUserDataTest(
        ISuperToken token,
        address flowOperator,
        int96 subtractedFlowRateAllowance,
        bytes memory userData
    ) public {
        token.decreaseFlowRateAllowance(flowOperator, subtractedFlowRateAllowance, userData);
    }

    function increaseFlowRateAllowanceWithPermissionsTest(
        ISuperToken token,
        address flowOperator,
        uint8 permissionsToAdd,
        int96 addedFlowRateAllowance
    ) public {
        token.increaseFlowRateAllowanceWithPermissions(flowOperator, permissionsToAdd, addedFlowRateAllowance);
    }

    function decreaseFlowRateAllowanceWithPermissionsTest(
        ISuperToken token,
        address flowOperator,
        uint8 permissionsToRemove,
        int96 subtractedFlowRateAllowance
    ) public {
        token.decreaseFlowRateAllowanceWithPermissions(flowOperator, permissionsToRemove, subtractedFlowRateAllowance);
    }

    function increaseFlowRateAllowanceWithPermissionsWithUserDataTest(
        ISuperToken token,
        address flowOperator,
        uint8 permissionsToAdd,
        int96 addedFlowRateAllowance,
        bytes memory userData
    ) public {
        token.increaseFlowRateAllowanceWithPermissions(
            flowOperator,
            permissionsToAdd,
            addedFlowRateAllowance,
            userData
        );
    }

    function decreaseFlowRateAllowanceWithPermissionsWithUserDataTest(
        ISuperToken token,
        address flowOperator,
        uint8 permissionsToRemove,
        int96 subtractedFlowRateAllowance,
        bytes memory userData
    ) public {
        token.decreaseFlowRateAllowanceWithPermissions(
            flowOperator, permissionsToRemove, subtractedFlowRateAllowance, userData
        );
    }
}

contract SuperTokenLibraryGDAMock {
    using SuperTokenV1Library for ISuperToken;
    //// View Functions ////

    function getFlowDistributionFlowRateTest(ISuperToken token, address from, ISuperfluidPool to)
        external
        view
        returns (int96)
    {
        return token.getFlowDistributionFlowRate(from, to);
    }

    function estimateFlowDistributionActualFlowRateTest(
        ISuperToken token,
        address from,
        ISuperfluidPool to,
        int96 requestedFlowRate
    ) external view returns (int96 actualFlowRate, int96 totalDistributionFlowRate) {
        return token.estimateFlowDistributionActualFlowRate(from, to, requestedFlowRate);
    }
    function estimateDistributionActualAmountTest(
        ISuperToken token,
        address from,
        ISuperfluidPool to,
        uint256 requestedAmount
    ) external view returns (uint256 actualAmount) {
        return token.estimateDistributionActualAmount(from, to, requestedAmount);
    }

    function isMemberConnectedTest(ISuperToken token, address pool, address member)
        external
        view
        returns (bool)
    {
        return token.isMemberConnected(pool, member);
    }

    //// Admin/Distributor Operations ////

    function createPoolTest(ISuperToken token, address admin, PoolConfig memory config)
        external
    {
        token.createPool(admin, config);
    }

    function distributeTest(ISuperToken token, address from, ISuperfluidPool pool, uint256 requestedAmount)
        external
    {
        token.distribute(from, pool, requestedAmount);
    }

    function distributeFlowTest(ISuperToken token, address from, ISuperfluidPool pool, int96 requestedFlowRate)
        external
    {
        token.distributeFlow(from, pool, requestedFlowRate);
    }

    //// Member Operations ////

    function connectPoolTest(ISuperToken token, ISuperfluidPool pool) external {
        token.connectPool(pool);
    }

    function disconnectPoolTest(ISuperToken token, ISuperfluidPool pool) external {
        token.disconnectPool(pool);
    }
}

contract SuperTokenLibraryCFASuperAppMock is SuperAppBase {

    using SuperTokenV1Library for ISuperToken;

    // default values for smoke tests
    address internal immutable sender;
    address internal immutable receiver;
    address internal immutable flowOperator;
    ISuperfluid internal immutable host;

    // for selectively testing functions in the same callback
    enum FunctionIndex {
        CREATE_FLOW,
        UPDATE_FLOW,
        DELETE_FLOW,
        CREATE_FLOW_BY_OPERATOR,
        UPDATE_FLOW_BY_OPERATOR,
        DELETE_FLOW_BY_OPERATOR,
        UPDATE_FLOW_OPERATOR_PERMISSIONS,
        AUTHORIZE_FLOW_OPERATOR_WITH_FULL_CONTROL,
        REVOKE_FLOW_OPERATOR_WITH_FULL_CONTROL
    }

    constructor(
        ISuperfluid _host,
        address defaultSender,
        address defaultReceiver,
        address defaultFlowOperator
    ) {
        host = _host;
        sender = defaultSender;
        receiver = defaultReceiver;
        flowOperator = defaultFlowOperator;

        uint256 configWord = SuperAppDefinitions.APP_LEVEL_FINAL |
            SuperAppDefinitions.BEFORE_AGREEMENT_CREATED_NOOP |
            // SuperAppDefinitions.AFTER_AGREEMENT_CREATED_NOOP |
            SuperAppDefinitions.BEFORE_AGREEMENT_UPDATED_NOOP |
            SuperAppDefinitions.AFTER_AGREEMENT_UPDATED_NOOP |
            SuperAppDefinitions.BEFORE_AGREEMENT_TERMINATED_NOOP |
            SuperAppDefinitions.AFTER_AGREEMENT_TERMINATED_NOOP;

        host.registerAppWithKey(configWord, "");
    }

    function createFlow(ISuperToken token) external {
        token.createFlow(receiver, 1000000000000);
    }

    // literally ONLY for the revokeFlowOperatorWithFullControlWithCtx test.
    function authorizeFlowOperatorWithFullControl(ISuperToken token) external {
        token.setMaxFlowPermissions(flowOperator);
    }

    function processTxAndReturnCtx(ISuperToken token, bytes memory ctx) internal returns (bytes memory updatedCtx) {
        uint8 functionIndex = abi.decode(host.decodeCtx(ctx).userData, (uint8));

        if (functionIndex == uint8(FunctionIndex.CREATE_FLOW))
            return token.createFlowWithCtx(receiver, 1000000000000, ctx);
        else if (functionIndex == uint8(FunctionIndex.UPDATE_FLOW))
            return token.updateFlowWithCtx(receiver, 2000000000000, ctx);
        else if (functionIndex == uint8(FunctionIndex.DELETE_FLOW))
            return token.deleteFlowWithCtx(address(this), receiver, ctx);
        else if (functionIndex == uint8(FunctionIndex.CREATE_FLOW_BY_OPERATOR))
            return token.createFlowFromWithCtx(sender, receiver, 1000000000000, ctx);
        else if (functionIndex == uint8(FunctionIndex.UPDATE_FLOW_BY_OPERATOR))
            return token.updateFlowFromWithCtx(sender, receiver, 2000000000000, ctx);
        else if (functionIndex == uint8(FunctionIndex.DELETE_FLOW_BY_OPERATOR))
            return token.deleteFlowFromWithCtx(sender, receiver, ctx);
        else if (functionIndex == uint8(FunctionIndex.UPDATE_FLOW_OPERATOR_PERMISSIONS))
            return token.setFlowPermissionsWithCtx(
                flowOperator,
                true,
                true,
                true,
                1000000000000,
                ctx
            );
        else if (functionIndex == uint8(FunctionIndex.AUTHORIZE_FLOW_OPERATOR_WITH_FULL_CONTROL))
            return token.setMaxFlowPermissionsWithCtx(flowOperator, ctx);
        else if (functionIndex == uint8(FunctionIndex.REVOKE_FLOW_OPERATOR_WITH_FULL_CONTROL))
            return token.revokeFlowPermissionsWithCtx(flowOperator, ctx);
        else revert("invalid function index");
    }

    function afterAgreementCreated(
        ISuperToken token,
        address,
        bytes32,
        bytes calldata,
        bytes calldata,
        bytes calldata ctx
    ) external override returns (bytes memory newCtx) {
        newCtx = processTxAndReturnCtx(token, ctx);
    }
}

// GDA LIBRARY SUPER APP CALLBACK MOCK
contract SuperTokenLibraryGDASuperAppMock is SuperTokenLibraryGDAMock, SuperAppBase {
    using SuperTokenV1Library for ISuperToken;

    ISuperfluid internal immutable host;

    constructor(ISuperfluid _host) {
        host = _host;
        uint256 configWord = SuperAppDefinitions.APP_LEVEL_FINAL | SuperAppDefinitions.BEFORE_AGREEMENT_CREATED_NOOP
            | SuperAppDefinitions.BEFORE_AGREEMENT_UPDATED_NOOP | SuperAppDefinitions.BEFORE_AGREEMENT_TERMINATED_NOOP
            | SuperAppDefinitions.AFTER_AGREEMENT_TERMINATED_NOOP;

        host.registerAppWithKey(configWord, "");
    }

    function afterAgreementCreated(
        ISuperToken token,
        address,
        bytes32,
        bytes calldata,
        bytes calldata,
        bytes calldata ctx
    ) external override returns (bytes memory newCtx) {
        return _callbackTest(token, ctx);
    }

    function afterAgreementUpdated(
        ISuperToken token,
        address,
        bytes32,
        bytes calldata,
        bytes calldata,
        bytes calldata ctx
    ) external override returns (bytes memory newCtx) {
        return _callbackTest(token, ctx);
    }

    enum FunctionIndex {
        UPDATE_MEMBER_UNITS,
        CONNECT_POOL,
        DISCONNECT_POOL,
        CLAIM_ALL,
        DISTRIBUTE,
        DISTRIBUTE_FLOW
    }

    /// @dev extracts some user data to test out all callback library functions
    /// @param token super token
    /// @param ctx Context string
    /// @return New Context
    function _callbackTest(ISuperToken token, bytes memory ctx) internal returns (bytes memory) {
        // extract userData, then decode everything else
        bytes memory userData = host.decodeCtx(ctx).userData;
        (
            uint8 functionIndex,
            address pool,
            address member,
            address from,
            uint128 units,
            uint256 requestedAmount,
            int96 requestedFlowRate
        ) = abi.decode(userData, (uint8, address, address, address, uint128, uint256, int96));

        if (functionIndex == uint8(FunctionIndex.UPDATE_MEMBER_UNITS)) {
            /*
            This used to be
            return token.updateMemberUnitsWithCtx(ISuperfluidPool(pool), member, units, ctx);
            But updateMemberUnits doesn't need ctx, so we can move it to the pool interface
            where it belongs.
            */
            ISuperfluidPool(pool).updateMemberUnits(member, units);
            return ctx;
        } else if (functionIndex == uint8(FunctionIndex.CONNECT_POOL)) {
            return token.connectPoolWithCtx(ISuperfluidPool(pool), ctx);
        } else if (functionIndex == uint8(FunctionIndex.DISCONNECT_POOL)) {
            return token.disconnectPoolWithCtx(ISuperfluidPool(pool), ctx);
        } else if (functionIndex == uint8(FunctionIndex.CLAIM_ALL)) {
            return token.claimAllWithCtx(ISuperfluidPool(pool), member, ctx);
        } else if (functionIndex == uint8(FunctionIndex.DISTRIBUTE)) {
            return token.distributeWithCtx(from, ISuperfluidPool(pool), requestedAmount, ctx);
        } else if (functionIndex == uint8(FunctionIndex.DISTRIBUTE_FLOW)) {
            return token.distributeFlowWithCtx(from, ISuperfluidPool(pool), requestedFlowRate, ctx);
        } else {
            revert("invalid function index");
        }
    }
}
