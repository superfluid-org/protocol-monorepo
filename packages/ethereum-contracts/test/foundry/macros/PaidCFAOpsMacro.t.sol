// SPDX-License-Identifier: AGPLv3
pragma solidity ^0.8.23;

import { ISuperfluid, BatchOperation } from "../../../contracts/interfaces/superfluid/ISuperfluid.sol";
import { ISuperToken } from "../../../contracts/superfluid/SuperToken.sol";
import { IConstantFlowAgreementV1 } from "../../../contracts/interfaces/agreements/IConstantFlowAgreementV1.sol";
import { IMacro } from "../../../contracts/interfaces/utils/IMacro.sol";

/**
 * @title PaidCFAOpsMacro
 * @dev Example IMacro: multi-action (create/update/delete flow) with a native-token fee.
 * encodeCreateFlow, encodeUpdateFlow, encodeDeleteFlow for param encoding.
 */
contract PaidCFAOpsMacro is IMacro {
    uint8 constant ACTION_CODE_CREATE_FLOW = 0;
    uint8 constant ACTION_CODE_UPDATE_FLOW = 1;
    uint8 constant ACTION_CODE_DELETE_FLOW = 2;

    address payable immutable FEE_RECEIVER;
    uint256 immutable FEE_AMOUNT;

    error UnknownAction();
    error FeeOverpaid();

    constructor(address payable feeReceiver, uint256 feeAmount) {
        FEE_RECEIVER = feeReceiver;
        FEE_AMOUNT = feeAmount;
    }

    function buildBatchOperations(ISuperfluid host, bytes memory params, address /*account*/)
        external
        override
        view
        returns (ISuperfluid.Operation[] memory operations)
    {
        IConstantFlowAgreementV1 cfa = IConstantFlowAgreementV1(address(host.getAgreementClass(
            keccak256("org.superfluid-finance.agreements.ConstantFlowAgreement.v1")
        )));
        operations = new ISuperfluid.Operation[](2);
        operations[0] = ISuperfluid.Operation({
            operationType: BatchOperation.OPERATION_TYPE_SIMPLE_FORWARD_CALL,
            target: address(this),
            data: abi.encodeCall(this.takeFee, (FEE_AMOUNT))
        });
        (uint8 actionCode, bytes memory actionArgs) = abi.decode(params, (uint8, bytes));
        if (actionCode == ACTION_CODE_CREATE_FLOW) {
            (ISuperToken token, address receiver, int96 flowRate) =
                abi.decode(actionArgs, (ISuperToken, address, int96));
            operations[1] = ISuperfluid.Operation({
                operationType: BatchOperation.OPERATION_TYPE_SUPERFLUID_CALL_AGREEMENT,
                target: address(cfa),
                data: abi.encode(
                    abi.encodeCall(cfa.createFlow, (token, receiver, flowRate, new bytes(0))),
                    new bytes(0)
                )
            });
        } else if (actionCode == ACTION_CODE_UPDATE_FLOW) {
            (ISuperToken token, address receiver, int96 flowRate) =
                abi.decode(actionArgs, (ISuperToken, address, int96));
            operations[1] = ISuperfluid.Operation({
                operationType: BatchOperation.OPERATION_TYPE_SUPERFLUID_CALL_AGREEMENT,
                target: address(cfa),
                data: abi.encode(
                    abi.encodeCall(cfa.updateFlow, (token, receiver, flowRate, new bytes(0))),
                    new bytes(0)
                )
            });
        } else if (actionCode == ACTION_CODE_DELETE_FLOW) {
            (ISuperToken token, address sender, address receiver) =
                abi.decode(actionArgs, (ISuperToken, address, address));
            operations[1] = ISuperfluid.Operation({
                operationType: BatchOperation.OPERATION_TYPE_SUPERFLUID_CALL_AGREEMENT,
                target: address(cfa),
                data: abi.encode(
                    abi.encodeCall(cfa.deleteFlow, (token, sender, receiver, new bytes(0))),
                    new bytes(0)
                )
            });
        } else {
            revert UnknownAction();
        }
    }

    function takeFee(uint256 amount) external payable {
        FEE_RECEIVER.transfer(amount);
    }

    function postCheck(ISuperfluid /*host*/, bytes memory /*params*/, address /*account*/)
        external
        view
        override
    {
        if (address(this).balance != 0) revert FeeOverpaid();
    }

    function encodeCreateFlow(ISuperToken token, address receiver, int96 flowRate)
        external
        pure
        returns (bytes memory)
    {
        return abi.encode(ACTION_CODE_CREATE_FLOW, abi.encode(token, receiver, flowRate));
    }

    function encodeUpdateFlow(ISuperToken token, address receiver, int96 flowRate)
        external
        pure
        returns (bytes memory)
    {
        return abi.encode(ACTION_CODE_UPDATE_FLOW, abi.encode(token, receiver, flowRate));
    }

    function encodeDeleteFlow(ISuperToken token, address sender, address receiver)
        external
        pure
        returns (bytes memory)
    {
        return abi.encode(ACTION_CODE_DELETE_FLOW, abi.encode(token, sender, receiver));
    }
}
