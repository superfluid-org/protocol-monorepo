// SPDX-License-Identifier: MIT
pragma solidity >=0.8.11;

import { IUserDefinedMacro } from "./IUserDefinedMacro.sol";

/**
 * @dev Interface for a macro used with the ClearSigningMacroForwarder.
 * Implementations provide the EIP-712 metadata and hashing logic for the
 * macro-specific action encoded in `params`.
 */
interface IClearSigningMacro is IUserDefinedMacro {
    /**
     * @dev Returns the primary EIP-712 type name.
     * This is usually rendered prominently by wallets and should concisely
     * describe the action or intent to be signed.
     * @param  params Encoded macro-specific parameters.
     * @return name  The primary type name.
     */
    function getPrimaryTypeName(bytes memory params) external view returns (string memory);

    /**
     * @dev Returns the EIP-712 type definition of the action.
     * The type name must be `Action`; only the fields are implementation-specific.
     * @param  params     Encoded macro-specific parameters.
     * @return typeDef    The `Action(...)` type definition.
     */
    function getActionTypeDefinition(bytes memory params) external view returns (string memory);

    /**
     * @dev Returns the EIP-712 struct hash of the action encoded in `params`.
     * The hash must be constructed from the `Action` type definition and the
     * underlying action data according to the EIP-712 standard.
     * @param  params        Encoded macro-specific parameters.
     * @return structHash    The EIP-712 struct hash of the action.
     */
    function getActionStructHash(bytes memory params) external view returns (bytes32);
}
