// SPDX-License-Identifier: AGPLv3
pragma solidity ^0.8.23;

import { ISuperfluid, BatchOperation } from "../../../contracts/interfaces/superfluid/ISuperfluid.sol";
import { ISuperToken } from "../../../contracts/superfluid/SuperToken.sol";
import { IConstantFlowAgreementV1 } from "../../../contracts/interfaces/agreements/IConstantFlowAgreementV1.sol";
import { IMacro } from "../../../contracts/interfaces/utils/IMacro.sol";

/**
 * @title GoodMacro
 * @dev Example IMacro: createFlow to multiple recipients. encodeCreateFlows for param encoding.
 */
contract GoodMacro is IMacro {
    function buildBatchOperations(ISuperfluid host, bytes memory params, address /*account*/)
        external
        override
        view
        returns (ISuperfluid.Operation[] memory operations)
    {
        IConstantFlowAgreementV1 cfa = IConstantFlowAgreementV1(address(host.getAgreementClass(
            keccak256("org.superfluid-finance.agreements.ConstantFlowAgreement.v1")
        )));
        (ISuperToken token, int96 flowRate, address[] memory recipients) =
            abi.decode(params, (ISuperToken, int96, address[]));
        operations = new ISuperfluid.Operation[](recipients.length);
        for (uint256 i = 0; i < recipients.length; ++i) {
            bytes memory callData = abi.encodeCall(cfa.createFlow,
                (token, recipients[i], flowRate, new bytes(0))
            );
            operations[i] = ISuperfluid.Operation({
                operationType: BatchOperation.OPERATION_TYPE_SUPERFLUID_CALL_AGREEMENT,
                target: address(cfa),
                data: abi.encode(callData, new bytes(0))
            });
        }
    }

    function postCheck(ISuperfluid, bytes memory, address) external view override { }

    function encodeCreateFlows(ISuperToken token, int96 flowRate, address[] calldata recipients)
        external
        pure
        returns (bytes memory)
    {
        return abi.encode(token, flowRate, recipients);
    }
}
