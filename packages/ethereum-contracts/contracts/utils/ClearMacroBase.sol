
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import { IClearMacro } from "../interfaces/utils/IClearMacro.sol";
import { IClearMacroForwarderV1 } from "../interfaces/utils/IClearMacroForwarderV1.sol";
import { ISuperfluid } from "../interfaces/superfluid/ISuperfluid.sol";

/**
 * @dev Abstract base for ClearMacro implementations that support multiple actions.
 * The forwarder handles EIP-712 and signature verification; this base only provides
 * dispatch by action id.
 * Wire format: `abi.encode(uint8 actionId, bytes32 lang, bytes actionParams)`.
 * Caller must specify lang; it is passed to getActionStructHash for i18n descriptions.
 */
abstract contract ClearMacroBase is IClearMacro {

    error UnknownActionId(uint8 actionId);
    error UnsupportedLanguage();

    /// @dev Per-action specification. Set `postCheck` to `_noOpPostCheck` if not post check is needed.
    struct ActionSpec {
        string primaryTypeName;
        string actionTypeDefinition;
        function(bytes memory, bytes32) internal view returns (bytes32)
            getActionStructHash;
        function(ISuperfluid, bytes memory, address) internal view
            returns (ISuperfluid.Operation[] memory)
            buildOperations;
        function(ISuperfluid, bytes memory, address) internal view postCheck;
    }

    mapping(uint8 => ActionSpec) internal _actions;

    constructor() {
        _registerActions();
    }

    /// @dev Override to register the actions supported by this macro.
    function _registerActions() internal virtual;

    function _registerAction(uint8 actionId, ActionSpec memory spec) internal {
        _actions[actionId] = spec;
    }

    function _getAction(uint8 actionId) internal view returns (ActionSpec storage spec) {
        spec = _actions[actionId];
        if (bytes(spec.actionTypeDefinition).length == 0) revert UnknownActionId(actionId);
    }

    /// @dev No-op post check function which can be used if no post check is needed.
    // solhint-disable-next-line no-empty-blocks
    function _noOpPostCheck(ISuperfluid, bytes memory, address) internal pure { }

    /// @dev Decode full Payload and then action id + lang + inner params. Used when the forwarder passes full params.
    function _decodePayloadAndAction(bytes memory params)
        internal
        pure
        returns (uint8 actionId, bytes32 lang, bytes memory actionParams)
    {
        IClearMacroForwarderV1.Payload memory payload = abi.decode(params, (IClearMacroForwarderV1.Payload));
        (actionId, lang, actionParams) = abi.decode(payload.action.params, (uint8, bytes32, bytes));
    }

    function _decodeActionParams(bytes memory params)
        internal
        pure
        returns (uint8 actionId, bytes32 lang, bytes memory actionParams)
    {
        (actionId, lang, actionParams) = abi.decode(params, (uint8, bytes32, bytes));
    }

    function getPrimaryTypeName(bytes memory params) external view override returns (string memory) {
        (uint8 actionId, , ) = _decodePayloadAndAction(params);
        return _getAction(actionId).primaryTypeName;
    }

    function getActionTypeDefinition(bytes memory params) external view override returns (string memory) {
        (uint8 actionId, , ) = _decodePayloadAndAction(params);
        return _getAction(actionId).actionTypeDefinition;
    }

    function getActionStructHash(bytes memory params) external view override returns (bytes32) {
        (uint8 actionId, bytes32 lang, bytes memory actionParams) = _decodeActionParams(params);
        return _getAction(actionId).getActionStructHash(actionParams, lang);
    }

    function buildBatchOperations(ISuperfluid host, bytes memory params, address msgSender)
        external
        view
        override
        returns (ISuperfluid.Operation[] memory)
    {
        (uint8 actionId, , bytes memory actionParams) = _decodeActionParams(params);
        return _getAction(actionId).buildOperations(host, actionParams, msgSender);
    }

    function postCheck(ISuperfluid host, bytes memory params, address msgSender) external view override {
        (uint8 actionId, , bytes memory actionParams) = _decodeActionParams(params);
        _getAction(actionId).postCheck(host, actionParams, msgSender);
    }
}
