// SPDX-License-Identifier: MIT
pragma solidity >=0.8.11;

import { IMacro } from "./IMacro.sol";

/**
 * @dev Interface for a macro used with `ClearMacroForwarderV1`.
 * Implementations provide the EIP-712 metadata and hashing logic for the
 * macro-specific action encoded in `actionParams`.
 *
 * Calling convention for `bytes` arguments:
 * - `encodedPayload`: `abi.encode(IClearMacroForwarderV1.Payload)` - same bytes as
 *   `runMacro(..., encodedPayload, ...)`.
 * - `actionParams`: `Payload.action.params` only - passed to `getActionStructHash`,
 *   `IMacro.buildBatchOperations`, and `IMacro.postCheck` by the Clear forwarder.
 *
 * Implementations may extend `ClearMacroBase`, which decodes each form accordingly.
 */
interface IClearMacro is IMacro {
    /**
     * @dev Returns the primary EIP-712 type name.
     * This is usually rendered prominently by wallets and should concisely
     * describe the action or intent to be signed.
     * @param  encodedPayload ABI-encoded `IClearMacroForwarderV1.Payload`.
     * @return name           The primary type name.
     */
    function getPrimaryTypeName(bytes memory encodedPayload) external view returns (string memory);

    /**
     * @dev Returns the EIP-712 type definition of the action.
     * The type name must be `Action`; only the fields are implementation-specific.
     * The type shall be flat (not contain any nested struct types).
     * @param  encodedPayload ABI-encoded `IClearMacroForwarderV1.Payload`.
     * @return typeDef        The `Action(...)` type definition.
     */
    function getActionTypeDefinition(bytes memory encodedPayload) external view returns (string memory);

    /**
     * @dev Returns the EIP-712 struct hash of the action.
     * The hash must be constructed from the `Action` type definition and the
     * underlying action data according to the EIP-712 standard.
     * @param  actionParams `Payload.action.params` (macro-specific action encoding).
     * @return structHash   The EIP-712 struct hash of the action.
     */
    function getActionStructHash(bytes memory actionParams) external view returns (bytes32);
}
