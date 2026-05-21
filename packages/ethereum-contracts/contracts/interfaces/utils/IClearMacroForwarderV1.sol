// SPDX-License-Identifier: MIT
pragma solidity >=0.8.11;

import { IClearMacro } from "./IClearMacro.sol";

/**
 * @dev Interface for ClearMacro forwarders.
 * A ClearMacro forwarder executes EIP-712 signed meta-transactions whose
 * payload consists of macro-specific action data and additional security
 * parameters.
 */
interface IClearMacroForwarderV1 {
    /**
     * @dev Opaque macro-specific action parameters.
     * The forwarder does not decode these fields itself; the macro defines the
     * actual EIP-712 `Action` type and computes its struct hash from these bytes.
     * This is what `IClearMacro.getActionStructHash`, `IMacro.buildBatchOperations`,
     * and `IMacro.postCheck` receive from the Clear forwarder.
     */
    struct EncodedAction {
        bytes params;
    }

    /**
     * @dev Top-level wire format passed to `runMacro`.
     * Callers typically build this using `encodeParams`, but it can also be
     * constructed manually and ABI-encoded as `bytes`.
     */
    struct Payload {
        EncodedAction action;
        Security security;
    }

    /**
     * @dev Security parameters for a ClearMacro payload.
     * Includes the provider identifier, validity window, and ERC-4337-style nonce.
     */
    struct Security {
        string domain;
        address macroContract;
        string provider;
        uint256 validAfter;
        /// @dev If set to 0, there's no upper bound on the validity window.
        uint256 validBefore;
        uint256 nonce;
    }

    /**
     * @dev Runs the macro with an EIP-712 signed payload.
     * Reverts if the signature is invalid, the payload fails security checks, or
     * any nested call reverts.
     * @param  m               Target macro contract.
     * @param  encodedPayload  ABI-encoded `Payload`.
     * @param  signer          Address which signed the payload and on whose behalf the macro runs.
     * @param  signature       EIP-712 signature over the payload digest.
     * @return success         True if the macro execution succeeded.
     */
    function runMacro(
        IClearMacro m,
        bytes calldata encodedPayload,
        address signer,
        bytes calldata signature
    ) external payable returns (bool);

    /**
     * @dev Encodes action and security data into the payload bytes expected by `runMacro`.
     * @param  actionParams    Macro-specific action encoding (`Payload.action.params`).
     * @param  security        Security parameters (domain, macroContract, provider, validAfter, validBefore, nonce).
     * @return encodedPayload  ABI-encoded `Payload`.
     */
    function encodeParams(
        bytes calldata actionParams,
        Security calldata security
    ) external pure returns (bytes memory encodedPayload);

    /**
     * @dev Returns the full EIP-712 type definition string for the given macro and payload.
     * @param  m              Target macro contract.
     * @param  encodedPayload ABI-encoded `Payload`.
     * @return typeDef        Full EIP-712 type definition string.
     */
    function getTypeDefinition(IClearMacro m, bytes calldata encodedPayload)
        external
        view
        returns (string memory);

    /**
     * @dev Returns the keccak256 hash of the EIP-712 type definition.
     * @param  m              Target macro contract.
     * @param  encodedPayload ABI-encoded `Payload`.
     * @return typeHash       keccak256 hash of the type definition.
     */
    function getTypeHash(IClearMacro m, bytes calldata encodedPayload)
        external
        view
        returns (bytes32);

    /**
     * @dev Returns the EIP-712 struct hash of the payload.
     * @param  m              Target macro contract.
     * @param  encodedPayload ABI-encoded `Payload`.
     * @return structHash     EIP-712 struct hash of the payload.
     */
    function getStructHash(IClearMacro m, bytes calldata encodedPayload)
        external
        view
        returns (bytes32);

    /**
     * @dev Returns the EIP-712 digest of the payload (value to sign off-chain).
     * @param  m              Target macro contract.
     * @param  encodedPayload ABI-encoded `Payload`.
     * @return digest         EIP-712 digest of the payload.
     */
    function getDigest(IClearMacro m, bytes calldata encodedPayload)
        external
        view
        returns (bytes32);

    /**
     * @dev Returns the next nonce for the given sender and key.
     * Nonces follow ERC-4337-style semantics: `(uint256(key) << 64) | sequence`.
     * @param  sender    Address for which the nonce is queried.
     * @param  key       Nonce key.
     * @return nonce     The next nonce for (`sender`, `key`).
     */
    function getNonce(address sender, uint192 key) external view returns (uint256);
}
