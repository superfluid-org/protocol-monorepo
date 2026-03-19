
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import { IClearMacro } from "../interfaces/utils/IClearMacro.sol";
import { IClearMacroForwarder } from "../interfaces/utils/IClearMacroForwarder.sol";
import { ISuperfluid } from "../interfaces/superfluid/ISuperfluid.sol";

/**
 * @dev Abstract base for ClearMacro implementations that support multiple actions.
 * The forwarder handles EIP-712 and signature verification; this base only provides
 * dispatch by action code.
 * Wire format: `abi.encode(uint8 actionCode, bytes32 lang, bytes actionParams)`.
 * Caller must specify lang; it is passed to getActionStructHash for i18n descriptions.
 */
abstract contract ClearMacroBase is IClearMacro {

    error UnknownActionCode(uint8 actionCode);
    error UnsupportedLanguage();

    /**
     * @dev Per-action handler. All function pointers use the same signatures so they can be stored and dispatched.
     */
    struct Action {
        uint8 actionCode;
        bool exists;
        function(bytes memory) internal view returns (string memory) getPrimaryTypeName;
        function(bytes memory) internal view returns (string memory) getActionTypeDefinition;
        function(bytes memory, bytes32) internal view returns (bytes32)
            getActionStructHash;
        function(ISuperfluid, bytes memory, address) internal view
            returns (ISuperfluid.Operation[] memory)
            buildOperations;
        bool skipPostCheck;
        function(ISuperfluid, bytes memory, address) internal view postCheckHandler;
    }

    mapping(uint8 => Action) internal _actionHandlers;

    constructor() {
        Action[] memory actions = _getActions();
        for (uint256 i = 0; i < actions.length; i++) {
            _actionHandlers[actions[i].actionCode] = actions[i];
        }
    }

    /**
     * @dev Override to return the list of actions supported by this macro.
     */
    function _getActions() internal view virtual returns (Action[] memory);

    /**
     * @dev Decode full Payload and then action code + lang + inner params. Used when the forwarder passes full params.
     */
    function _decodePayloadAndAction(bytes memory params)
        internal
        pure
        returns (uint8 actionCode, bytes32 lang, bytes memory actionParams)
    {
        IClearMacroForwarder.Payload memory payload = abi.decode(params, (IClearMacroForwarder.Payload));
        (actionCode, lang, actionParams) = abi.decode(payload.action.params, (uint8, bytes32, bytes));
    }

    /**
     * @dev Decode action params (actionCode, lang, actionParams). Used when the
     * forwarder passes only payload.action.params.
     */
    function _decodeActionParams(bytes memory params)
        internal
        pure
        returns (uint8 actionCode, bytes32 lang, bytes memory actionParams)
    {
        (actionCode, lang, actionParams) = abi.decode(params, (uint8, bytes32, bytes));
    }

    function getPrimaryTypeName(bytes memory params) external view override returns (string memory) {
        (uint8 actionCode, , bytes memory actionParams) = _decodePayloadAndAction(params);
        if (!_actionHandlers[actionCode].exists) revert UnknownActionCode(actionCode);
        return _actionHandlers[actionCode].getPrimaryTypeName(actionParams);
    }

    function getActionTypeDefinition(bytes memory params) external view override returns (string memory) {
        (uint8 actionCode, , bytes memory actionParams) = _decodePayloadAndAction(params);
        if (!_actionHandlers[actionCode].exists) revert UnknownActionCode(actionCode);
        return _actionHandlers[actionCode].getActionTypeDefinition(actionParams);
    }

    function getActionStructHash(bytes memory params) external view override returns (bytes32) {
        (uint8 actionCode, bytes32 lang, bytes memory actionParams) = _decodeActionParams(params);
        if (!_actionHandlers[actionCode].exists) revert UnknownActionCode(actionCode);
        return _actionHandlers[actionCode].getActionStructHash(actionParams, lang);
    }

    function buildBatchOperations(ISuperfluid host, bytes memory params, address msgSender)
        external
        view
        override
        returns (ISuperfluid.Operation[] memory)
    {
        (uint8 actionCode, , bytes memory actionParams) = _decodeActionParams(params);
        if (!_actionHandlers[actionCode].exists) revert UnknownActionCode(actionCode);
        return _actionHandlers[actionCode].buildOperations(host, actionParams, msgSender);
    }

    function postCheck(ISuperfluid host, bytes memory params, address msgSender) external view override {
        (uint8 actionCode, , bytes memory actionParams) = _decodeActionParams(params);
        if (_actionHandlers[actionCode].skipPostCheck) return;
        if (!_actionHandlers[actionCode].exists) revert UnknownActionCode(actionCode);
        _actionHandlers[actionCode].postCheckHandler(host, actionParams, msgSender);
    }
}
