// SPDX-License-Identifier: MIT
pragma solidity >=0.8.11;

import { IClearMacro } from "./IClearMacro.sol";
import { IClearMacroForwarderV1 } from "./IClearMacroForwarderV1.sol";
import { IPermit2 } from "../external/IPermit2.sol";


/**
 * @dev Delta interface for Permit2-enabled ClearMacro forwarders.
 */
interface IClearMacroPermit2Extension {
    struct Permit2MacroParams {
        IPermit2.PermitTransferFrom permit;
        address owner;
        bytes32 witness;
        string witnessTypeString;
        bytes signature;
        address spender;
        address upgradeSuperToken;
    }

    /**
     * @dev Runs the macro with Permit2 witness validation.
     * If `upgradeSuperToken` is set, underlying tokens are first pulled via Permit2
     * and upgraded before the macro is executed.
     * @param  p       Permit2 data and optional upgrade configuration.
     * @param  m       Target macro.
     * @param  params  ABI-encoded `IClearMacroForwarderV1.Payload`.
     */
    function runPermit2AndMacro(
        Permit2MacroParams calldata p,
        IClearMacro m,
        bytes calldata params
    ) external payable returns (bool);

    /**
     * @dev Struct hash of the ClearMacro payload for use as Permit2 witness.
     */
    function getPermit2WitnessStructHash(IClearMacro m, bytes calldata params)
        external
        view
        returns (bytes32);

    /**
     * @dev Witness type string for Permit2 PermitWitnessTransferFrom.
     */
    function getPermit2WitnessTypeString(IClearMacro m, bytes calldata params)
        external
        view
        returns (string memory);
}

/**
 * @dev Full interface for Permit2-enabled ClearMacro forwarders.
 */
// solhint-disable-next-line no-empty-blocks
interface IClearMacroForwarderV1WithPermit2 is IClearMacroForwarderV1, IClearMacroPermit2Extension { }