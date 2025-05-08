// SPDX-License-Identifier: AGPLv3
// solhint-disable not-rely-on-time
pragma solidity ^0.8.0;
import {
    ISuperfluid, ISuperToken, SuperAppDefinitions
} from "@superfluid-finance/ethereum-contracts/contracts/interfaces/superfluid/ISuperfluid.sol";
import { SuperAppBase } from "@superfluid-finance/ethereum-contracts/contracts/apps/SuperAppBase.sol";
import { SuperTokenV1Library } from "@superfluid-finance/ethereum-contracts/contracts/apps/SuperTokenV1Library.sol";
import { IFlowScheduler } from "./interface/IFlowScheduler.sol";

/**
 * @title Flow scheduler contract
 * @author Superfluid
 */
contract FlowScheduler is IFlowScheduler, SuperAppBase {

    using SuperTokenV1Library for ISuperToken;

    ISuperfluid public immutable HOST;
    mapping(bytes32 => FlowSchedule) public flowSchedules; // id = keccak(supertoken, sender, receiver)

    constructor(ISuperfluid host) {
        // super app registration. This is a dumb superApp, only for frontend batching calls.
        uint256 configWord = SuperAppDefinitions.APP_LEVEL_FINAL |
        SuperAppDefinitions.BEFORE_AGREEMENT_CREATED_NOOP |
        SuperAppDefinitions.AFTER_AGREEMENT_CREATED_NOOP |
        SuperAppDefinitions.BEFORE_AGREEMENT_UPDATED_NOOP |
        SuperAppDefinitions.AFTER_AGREEMENT_UPDATED_NOOP |
        SuperAppDefinitions.BEFORE_AGREEMENT_TERMINATED_NOOP |
        SuperAppDefinitions.AFTER_AGREEMENT_TERMINATED_NOOP;
        host.registerApp(configWord);
        HOST = host;
    }

    /// @dev IFlowScheduler.createFlowSchedule implementation.
    function createFlowSchedule(
        ISuperToken superToken,
        address receiver,
        uint32 startDate,
        uint32 startMaxDelay,
        int96 flowRate,
        uint256 startAmount,
        uint32 endDate,
        bytes memory userData,
        bytes memory ctx
    ) external returns(bytes memory newCtx) {
        newCtx = ctx;
        address sender = _getSender(ctx);

        if (receiver == address(0) || receiver == sender) revert AccountInvalid();
        if (address(superToken) == address(0)) revert ZeroAddress();

        // if user don't want to open a stream, he should provide only endDate
        if (startDate == 0) {
            if ( startMaxDelay != 0 || endDate == 0) revert TimeWindowInvalid();
        } else { // startDate != 0
            // solhint-disable-next-line not-rely-on-time
            if (startDate <= block.timestamp || (startDate >= endDate && endDate != 0)) revert TimeWindowInvalid();
        }
        // solhint-disable-next-line not-rely-on-time
        if ((endDate != 0 && endDate <= block.timestamp)) revert TimeWindowInvalid();

        flowSchedules[keccak256(
            abi.encodePacked(
                superToken,
                sender,
                receiver
            )
        )] = FlowSchedule(
            startDate,
            startMaxDelay,
            endDate,
            flowRate,
            startAmount,
            userData.length != 0 ? keccak256(userData) : bytes32(0x0)
        );

        emit FlowScheduleCreated(
            superToken,
            sender,
            receiver,
            startDate,
            startMaxDelay,
            flowRate,
            endDate,
            startAmount,
            userData
        );
    }
    /// @dev IFlowScheduler.deleteFlowSchedule implementation.
    function deleteFlowSchedule(ISuperToken superToken, address receiver, bytes memory ctx)
        external returns(bytes memory newCtx)
    {
        newCtx = ctx;
        address sender = _getSender(ctx);

        delete flowSchedules[keccak256(
            abi.encodePacked(
                superToken,
                sender,
                receiver
            ))];

        emit FlowScheduleDeleted(
            superToken,
            sender,
            receiver
        );
    }
    /// @dev IFlowScheduler.executeCreateFlow implementation.
    function executeCreateFlow(
        ISuperToken superToken,
        address sender,
        address receiver,
        bytes memory userData
    ) external returns(bool success) {
        bytes32 configHash = keccak256(abi.encodePacked(superToken,sender,receiver));
        FlowSchedule memory schedule = flowSchedules[configHash];
        //revert if start date is not defined, or if end date is defined and is in the past
        if (
            schedule.startDate == 0 ||
            schedule.startDate > block.timestamp ||
            schedule.startDate + schedule.startMaxDelay < block.timestamp
          ) {
            revert TimeWindowInvalid();
        }
        // revert if userData was set by user, but caller didn't provide it
        if ((userData.length != 0 ? keccak256(userData) : bytes32(0x0)) != schedule.userData) revert UserDataInvalid();

        if (schedule.startAmount != 0) {
            // remove transfer amount after transfer is complete
            delete flowSchedules[configHash].startAmount;
            superToken.transferFrom(
                sender,
                receiver,
                schedule.startAmount
            );
        }

        // delete configHash if there nothing more to perform or invalidate open stream configuration
        if (schedule.endDate == 0) {
            delete flowSchedules[configHash];
        } else {
            delete flowSchedules[configHash].startDate;
            delete flowSchedules[configHash].startMaxDelay;
            delete flowSchedules[configHash].flowRate;
        }

        // Create a flow accordingly as per the flow schedule data.
        superToken.createFlowFrom(sender, receiver, schedule.flowRate, userData);

        emit CreateFlowExecuted(
            superToken,
            sender,
            receiver,
            schedule.startDate,
            schedule.startMaxDelay,
            schedule.flowRate,
            schedule.startAmount,
            userData
        );

        return true;
    }
    /// @dev IFlowScheduler.executeDeleteFlow implementation.
    function executeDeleteFlow(
        ISuperToken superToken,
        address sender,
        address receiver,
        bytes memory userData
    ) external returns(bool success) {
        bytes32 configHash = keccak256(abi.encodePacked(superToken,sender,receiver));
        FlowSchedule memory schedule = flowSchedules[configHash];
        delete flowSchedules[configHash];
        //revert if start date is not defined, or if end date is defined and is in the past
        if (schedule.endDate == 0 || schedule.endDate > block.timestamp) revert TimeWindowInvalid();
        // revert if userData was set by user, but caller didn't provide it
        if ((userData.length != 0 ? keccak256(userData) : bytes32(0x0)) != schedule.userData) revert UserDataInvalid();

        superToken.deleteFlowFrom(sender, receiver, userData);

        emit DeleteFlowExecuted(
            superToken,
            sender,
            receiver,
            schedule.endDate,
            userData
        );

        return true;
    }
    /// @dev IFlowScheduler.getFlowSchedule implementation.
    function getFlowSchedule(address superToken, address sender, address receiver)
        external view returns (FlowSchedule memory)
    {
        return flowSchedules[keccak256(abi.encodePacked(superToken,sender,receiver))];
    }

    function _getSender(bytes memory ctx) internal view returns(address sender) {
        if(ctx.length != 0) {
            if(msg.sender != address(HOST)) revert HostInvalid();
            sender = HOST.decodeCtx(ctx).msgSender;
        } else {
            sender = msg.sender;
        }
        // This is an invariant and should never happen.
        assert(sender != address(0));
    }
}
