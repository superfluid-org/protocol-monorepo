// SPDX-License-Identifier: AGPLv3
pragma solidity ^0.8.23;

import { ISuperfluid, BatchOperation } from "../../../contracts/interfaces/superfluid/ISuperfluid.sol";
import { ISuperToken } from "../../../contracts/superfluid/SuperToken.sol";
import { IConstantFlowAgreementV1 } from "../../../contracts/interfaces/agreements/IConstantFlowAgreementV1.sol";
import { IMacro } from "../../../contracts/interfaces/utils/IMacro.sol";

/**
 * @title MultiFlowDeleteMacro
 * @dev Example IMacro: deleteFlow from one sender to many receivers. encodeDeleteFlows + postCheck.
 */
contract MultiFlowDeleteMacro is IMacro {
    error InsufficientReward();

    function buildBatchOperations(ISuperfluid host, bytes memory params, address /*account*/)
        external
        override
        view
        returns (ISuperfluid.Operation[] memory operations)
    {
        IConstantFlowAgreementV1 cfa = IConstantFlowAgreementV1(address(host.getAgreementClass(
            keccak256("org.superfluid-finance.agreements.ConstantFlowAgreement.v1")
        )));
        (ISuperToken token, address sender, address[] memory receivers,) =
            abi.decode(params, (ISuperToken, address, address[], uint256));
        operations = new ISuperfluid.Operation[](receivers.length);
        for (uint256 i = 0; i < receivers.length; ++i) {
            bytes memory callData = abi.encodeCall(cfa.deleteFlow,
                (token, sender, receivers[i], new bytes(0))
            );
            operations[i] = ISuperfluid.Operation({
                operationType: BatchOperation.OPERATION_TYPE_SUPERFLUID_CALL_AGREEMENT,
                target: address(cfa),
                data: abi.encode(callData, new bytes(0))
            });
        }
    }

    function encodeDeleteFlows(
        ISuperToken superToken,
        address sender,
        address[] memory receivers,
        uint256 minBalanceAfter
    ) external pure returns (bytes memory) {
        return abi.encode(superToken, sender, receivers, minBalanceAfter);
    }

    function postCheck(ISuperfluid /*host*/, bytes memory params, address account) external view override {
        (ISuperToken superToken,,, uint256 minBalanceAfter) =
            abi.decode(params, (ISuperToken, address, address[], uint256));
        if (superToken.balanceOf(account) < minBalanceAfter) {
            revert InsufficientReward();
        }
    }
}
