// SPDX-License-Identifier: AGPLv3
pragma solidity ^0.8.23;

import { Strings } from "@openzeppelin-v5/contracts/utils/Strings.sol";
import { BatchOperation, ISuperfluid } from "../../../contracts/interfaces/superfluid/ISuperfluid.sol";
import { IClearMacro } from "../../../contracts/interfaces/utils/IClearMacro.sol";

/**
 * @title MinimalClearMacro
 * @dev Minimal ClearMacro: single upgrade action, no postCheck.
 * Params (token, amount); EIP-712 Action(string description) with description derived from params.
 */
contract MinimalClearMacro is IClearMacro {
    string public constant PRIMARY_TYPE_NAME = "MinimalExample";
    string public constant ACTION_TYPE_DEFINITION = "Action(string description)";

    function _buildDescription(address token, uint256 amount) internal pure returns (string memory) {
        return string.concat(
            "Upgrade ",
            Strings.toString(amount),
            " ",
            Strings.toHexString(token)
        );
    }

    function buildBatchOperations(ISuperfluid, bytes memory params, address /*account*/)
        external
        pure
        override
        returns (ISuperfluid.Operation[] memory operations)
    {
        (address token, uint256 amount) = abi.decode(params, (address, uint256));
        operations = new ISuperfluid.Operation[](1);
        operations[0] = ISuperfluid.Operation({
            operationType: BatchOperation.OPERATION_TYPE_SUPERTOKEN_UPGRADE,
            target: token,
            data: abi.encode(amount)
        });
    }

    function postCheck(ISuperfluid, bytes memory, address) external view override {
        // intentionally empty
    }

    function getActionTypeDefinition(bytes memory /*params*/) external pure override returns (string memory) {
        return ACTION_TYPE_DEFINITION;
    }

    function getPrimaryTypeName(bytes memory /*params*/) external pure override returns (string memory) {
        return PRIMARY_TYPE_NAME;
    }

    function getActionStructHash(bytes memory params) external pure override returns (bytes32) {
        (address token, uint256 amount) = abi.decode(params, (address, uint256));
        string memory description = _buildDescription(token, amount);
        bytes32 actionTypeHash = keccak256(abi.encodePacked(ACTION_TYPE_DEFINITION));
        return keccak256(abi.encode(actionTypeHash, keccak256(bytes(description))));
    }
}
