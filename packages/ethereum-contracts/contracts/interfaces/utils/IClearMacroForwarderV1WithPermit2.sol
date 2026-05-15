// SPDX-License-Identifier: MIT
pragma solidity >=0.8.11;

import { IClearMacro } from "./IClearMacro.sol";
import { IClearMacroForwarderV1 } from "./IClearMacroForwarderV1.sol";
import { IPermit2 } from "../external/IPermit2.sol";


/**
 * @dev Permit2 witness extension for {ClearMacroForwarderV1}.
 *
 * Notes about Permit2:
 * - Permit2 has its own nonce and deadline management, independent of that of ClearMacro.
 * - the Permit2 transfer call requires msg.sender to be the designated `spender`.
 *
 * When using this extension, the argument `upgradeSuperToken` selects the Permit2 mode:
 * - Non-zero (`implied upgrade`): before running the macro, the forwarder executes the Permit2 transfer
 *   of underlying tokens and upgrades them to SuperTokens.
 *   The Permit2 transfer uses the full amount specified in `permit.permitted.amount`.
 *   This implies that for the macro call to succeed, this amount can't exceed the balance of the signer.
 *   This mode allows the bundling of upgrade and other operations into a single wallet action.
 * - Zero (`witness only`): the Permit2 specific payload is ignored.
 *   The forwarder just verifies the signature and executes the ClearMacro action(s).
 *   This mode is for use cases where the implied Permit2 transfer is about something else.
 */
interface IClearMacroPermit2Extension {
    struct Permit2Context {
        IPermit2.PermitTransferFrom permit;
        address owner;
        bytes32 witness;
        string witnessTypeString;
        bytes signature;
        /// @dev must be the address of this contract in implied upgrade mode.
        address spender;
        /// @dev Wrapper SuperToken for implied upgrade, or `address(0)` for witness-only mode.
        address upgradeSuperToken;
    }

    /**
     * @notice Run a signed macro after Permit2 witness validation (see interface docs for modes).
     * @param  permit2Context Permit2 permit, witness, and `upgradeSuperToken` mode.
     * @param  m              Target macro (must match `security.macroContract` in `params`).
     * @param  params         ABI-encoded `IClearMacroForwarderV1.Payload`.
     */
    function runPermit2AndMacro(
        Permit2Context calldata permit2Context,
        IClearMacro m,
        bytes calldata params
    ) external payable returns (bool);

    /**
     * @dev Struct hash of the ClearMacro payload for use as Permit2 witness.
     * @param m       Target macro.
     * @param params  ABI-encoded `IClearMacroForwarderV1.Payload`.
     * @param upgradeSuperToken Implied-upgrade SuperToken, or `address(0)` for witness-only mode.
     */
    function getPermit2WitnessStructHash(IClearMacro m, bytes calldata params, address upgradeSuperToken)
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

/// @title IClearMacroForwarderV1WithPermit2
/// @notice ClearMacro forwarder with optional Permit2 witness and implied underlying upgrade.
// solhint-disable-next-line no-empty-blocks
interface IClearMacroForwarderV1WithPermit2 is IClearMacroForwarderV1, IClearMacroPermit2Extension { }