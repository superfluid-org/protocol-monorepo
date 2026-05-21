
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import { IClearMacro } from "../interfaces/utils/IClearMacro.sol";
import { IClearMacroForwarderV1 } from "../interfaces/utils/IClearMacroForwarderV1.sol";
import { ISuperfluid } from "../interfaces/superfluid/ISuperfluid.sol";

/**
 * @dev Abstract base for ClearMacro implementations that support multiple actions.
 * The forwarder handles EIP-712, signature verification, security checks, and
 * extraction of `Payload.action.params`; this base dispatches the extracted action
 * params by `actionId`.
 *
 * This base expects `Payload.action.params` (`actionParams`) to be encoded as:
 * `abi.encode(uint8 actionId, bytes32 lang, bytes actionSpecificParams)`.
 *
 * The `lang` value is passed to the action hash builder for localized EIP-712
 * descriptions. `actionSpecificParams` is the action-specific payload consumed by the
 * registered action's hash/build/post-check handlers.
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

    /// @dev Decode `encodedPayload` (`abi.encode(Payload)`) to action id, lang, and action-specific params.
    function _decodePayloadAndAction(bytes memory encodedPayload)
        internal
        pure
        returns (uint8 actionId, bytes32 lang, bytes memory actionSpecificParams)
    {
        IClearMacroForwarderV1.Payload memory payload =
            abi.decode(encodedPayload, (IClearMacroForwarderV1.Payload));
        (actionId, lang, actionSpecificParams) = abi.decode(payload.action.params, (uint8, bytes32, bytes));
    }

    /// @dev Decode `Payload.action.params` (wire format: actionId, lang, actionSpecificParams).
    function _decodeActionParams(bytes memory actionParams)
        internal
        pure
        returns (uint8 actionId, bytes32 lang, bytes memory actionSpecificParams)
    {
        (actionId, lang, actionSpecificParams) = abi.decode(actionParams, (uint8, bytes32, bytes));
    }

    function getPrimaryTypeName(bytes memory encodedPayload) external view override returns (string memory) {
        (uint8 actionId, , ) = _decodePayloadAndAction(encodedPayload);
        return _getAction(actionId).primaryTypeName;
    }

    function getActionTypeDefinition(bytes memory encodedPayload) external view override returns (string memory) {
        (uint8 actionId, , ) = _decodePayloadAndAction(encodedPayload);
        return _getAction(actionId).actionTypeDefinition;
    }

    function getActionStructHash(bytes memory actionParams) external view override returns (bytes32) {
        (uint8 actionId, bytes32 lang, bytes memory actionSpecificParams) = _decodeActionParams(actionParams);
        return _getAction(actionId).getActionStructHash(actionSpecificParams, lang);
    }

    function buildBatchOperations(ISuperfluid host, bytes memory actionParams, address account)
        external
        view
        override
        returns (ISuperfluid.Operation[] memory)
    {
        (uint8 actionId, , bytes memory actionSpecificParams) = _decodeActionParams(actionParams);
        return _getAction(actionId).buildOperations(host, actionSpecificParams, account);
    }

    function postCheck(ISuperfluid host, bytes memory actionParams, address account) external view override {
        (uint8 actionId, , bytes memory actionSpecificParams) = _decodeActionParams(actionParams);
        _getAction(actionId).postCheck(host, actionSpecificParams, account);
    }
}
