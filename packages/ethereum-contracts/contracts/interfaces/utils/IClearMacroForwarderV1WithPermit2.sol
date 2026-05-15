// SPDX-License-Identifier: MIT
pragma solidity >=0.8.11;

import { IClearMacro } from "./IClearMacro.sol";
import { IClearMacroForwarderV1 } from "./IClearMacroForwarderV1.sol";
import { IPermit2 } from "../external/IPermit2.sol";


/**
 * @dev Permit2 witness extension for {ClearMacroForwarderV1}.
 *
 * `upgradeSuperToken` selects the Permit2 mode:
 * - Non-zero (`implied upgrade`): Permit2 transfers underlying to the forwarder, which upgrades
 *   to `owner`, then the macro runs.
 * - Zero (`witness only`): Permit2 co-signs the same witness as the macro but does not pull
 *   underlying or consume the Permit2 nonce; the macro uses the signer's existing balances.
 *   Macro replay is still prevented by the ClearMacro EIP-712 nonce.
 */
interface IClearMacroPermit2Extension {
    struct Permit2Context {
        IPermit2.PermitTransferFrom permit;
        address owner;
        bytes32 witness;
        string witnessTypeString;
        bytes signature;
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