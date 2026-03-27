// SPDX-License-Identifier: AGPLv3
pragma solidity ^0.8.23;

import { EIP712 } from "@openzeppelin-v5/contracts/utils/cryptography/EIP712.sol";
import { SignatureChecker } from "@openzeppelin-v5/contracts/utils/cryptography/SignatureChecker.sol";
import { IAccessControl } from "@openzeppelin-v5/contracts/access/IAccessControl.sol";
import { IClearMacro } from "../interfaces/utils/IClearMacro.sol";
import { ISuperfluid } from "../interfaces/superfluid/ISuperfluid.sol";
import { ForwarderBase } from "./ForwarderBase.sol";
import { IClearMacroForwarderV1 } from "../interfaces/utils/IClearMacroForwarderV1.sol";


/**
 * Nonce management functionality following the semantics of ERC-4337.
 * Each nonce consists of a 192-bit key and a 64-bit sequence number.
 * This allows senders to both have a practically unlimited number of parallel operations
 * (meaning signed pending transactions can't block each other), and also the option to enforce
 * sequential execution according to the sequence number.
 */
abstract contract NonceManager {
    /// nonce already used or out of sequence
    error InvalidNonce(address sender, uint256 nonce);

    /// data structure keeping track of the next sequence number by sender and key
    mapping(address => mapping(uint192 => uint256)) internal _nonceSequenceNumber;

    /// Returns the next nonce for a given sender and key
    function getNonce(address sender, uint192 key) public virtual view returns (uint256 nonce) {
        return _nonceSequenceNumber[sender][key] | (uint256(key) << 64);
    }

    /// validates the nonce and updates the data structure for correct sequencing
    function _validateAndUpdateNonce(address sender, uint256 nonce) internal virtual {
        uint192 key = uint192(nonce >> 64);
        uint64 seq = uint64(nonce);
        if (_nonceSequenceNumber[sender][key]++ != seq) {
            revert InvalidNonce(sender, nonce);
        }
    }
}

/**
 * @dev EIP-712-aware macro forwarder.
 * Decodes a ClearMacro payload, verifies the signature, enforces the
 * security checks, and executes the macro on behalf of the signer.
 */
contract ClearMacroForwarderV1 is ForwarderBase, EIP712, NonceManager, IClearMacroForwarderV1 {

    // CONSTANTS, IMMUTABLES

    bytes internal constant _TYPEDEF_SECURITY =
        "Security(string domain,string provider,uint256 validAfter,uint256 validBefore,uint256 nonce)";

    bytes32 internal constant _TYPEHASH_SECURITY = keccak256(_TYPEDEF_SECURITY);

    /// Reserved provider value: when set, allows the signer to submit their own signed transaction.
    string public constant SELF_PROVIDER = "self";

    IAccessControl internal immutable _providerACL;

    // ERRORS

    error InvalidPayload(string message);
    error OutsideValidityWindow(uint256 blockTimestamp, uint256 validBefore, uint256 validAfter);
    error ProviderNotAuthorized(string provider, address msgSender);
    error InvalidSignature();

    // INITIALIZATION

    constructor(ISuperfluid host) ForwarderBase(host) EIP712("ClearMacro", "1") {
        _providerACL = IAccessControl(host.getSimpleACL());
    }

    // PUBLIC FUNCTIONS

    /**
     * @dev Runs the macro with an EIP-712 signed payload.
     * Reverts if the signature is invalid or if the payload fails security checks.
     * @param  m          Target macro.
     * @param  params     ABI-encoded `IClearMacroForwarderV1.Payload`.
     * @param  signer     Address which signed the payload and on whose behalf the macro runs.
     * @param  signature  EIP-712 signature over the payload digest.
     * @return success    True if the macro execution succeeded.
     */
    function runMacro(IClearMacro m, bytes calldata params, address signer, bytes calldata signature)
        external payable override
        returns (bool)
    {
        bytes32 digest = _getDigest(m, params);

        // verify the signature - this also works for ERC1271 (contract signatures)
        if (!SignatureChecker.isValidSignatureNow(signer, digest, signature)) {
            revert InvalidSignature();
        }

        _validatePayload(m, params, signer, msg.sender);
        return _executeValidatedMacro(m, params, signer);
    }

    /**
     * @dev Encodes the action and security data into the payload bytes expected by `runMacro`.
     * @param  params     ABI-encoded macro-specific parameters, opaque to the forwarder.
     * @param  security   Security parameters (domain, provider, validAfter, validBefore, nonce).
     * @return payload    ABI-encoded `IClearMacroForwarderV1.Payload`.
     */
    function encodeParams(
        bytes calldata params,
        IClearMacroForwarderV1.Security calldata security
    ) external pure override returns (bytes memory) {
        IClearMacroForwarderV1.Payload memory payload = IClearMacroForwarderV1.Payload({
            action: IClearMacroForwarderV1.EncodedAction({ params: params }),
            security: security
        });
        return abi.encode(payload);
    }

    function getTypeDefinition(IClearMacro m, bytes calldata params)
        external
        view
        override
        returns (string memory)
    {
        return _getTypeDefinition(m, params);
    }

    function getTypeHash(IClearMacro m, bytes calldata params) public view override returns (bytes32) {
        return keccak256(abi.encodePacked(_getTypeDefinition(m, params)));
    }

    function getStructHash(IClearMacro m, bytes calldata params) external view override returns (bytes32) {
        return _getStructHash(m, params);
    }

    function getDigest(IClearMacro m, bytes calldata params) external view override returns (bytes32) {
        return _getDigest(m, params);
    }

    function getNonce(address sender, uint192 key)
        public
        view
        override(NonceManager, IClearMacroForwarderV1)
        returns (uint256)
    {
        return NonceManager.getNonce(sender, key);
    }

    // INTERNAL FUNCTIONS

    function _validatePayload(
        IClearMacro,
        bytes calldata params,
        address signer,
        address executor
    ) internal {
        IClearMacroForwarderV1.Payload memory payload = abi.decode(params, (IClearMacroForwarderV1.Payload));

        // Provider authorization: either ACL role, or self-relay when provider is "self"
        if (keccak256(bytes(payload.security.provider)) == keccak256(bytes(SELF_PROVIDER))) {
            if (executor != signer) {
                revert ProviderNotAuthorized(payload.security.provider, executor);
            }
        } else {
            bytes32 providerRole = keccak256(bytes(payload.security.provider));
            if (!_providerACL.hasRole(providerRole, executor)) {
                revert ProviderNotAuthorized(payload.security.provider, executor);
            }
        }

        _validateAndUpdateNonce(signer, payload.security.nonce);

        if (block.timestamp < payload.security.validAfter) {
            revert OutsideValidityWindow(block.timestamp, payload.security.validBefore, payload.security.validAfter);
        }
        if (payload.security.validBefore != 0 && block.timestamp > payload.security.validBefore) {
            revert OutsideValidityWindow(block.timestamp, payload.security.validBefore, payload.security.validAfter);
        }
    }

    function _executeValidatedMacro(IClearMacro m, bytes calldata params, address signer)
        internal
        returns (bool)
    {
        IClearMacroForwarderV1.Payload memory payload = abi.decode(params, (IClearMacroForwarderV1.Payload));

        ISuperfluid.Operation[] memory operations =
            m.buildBatchOperations(_host, payload.action.params, signer);

        bool retVal = _forwardBatchCallWithSenderAndValue(operations, signer, msg.value);
        m.postCheck(_host, payload.action.params, signer);
        return retVal;
    }

    function _getTypeDefinition(IClearMacro m, bytes calldata params) internal view returns (string memory) {
        return string(abi.encodePacked(
            m.getPrimaryTypeName(params),
            "(Action action,Security security)",
            m.getActionTypeDefinition(params),
            _TYPEDEF_SECURITY
        ));
    }

    function _getStructHash(IClearMacro m, bytes calldata params) internal view returns (bytes32) {
        IClearMacroForwarderV1.Payload memory payload = abi.decode(params, (IClearMacroForwarderV1.Payload));
        bytes32 actionStructHash = m.getActionStructHash(payload.action.params);
        bytes32 securityStructHash = _getSecurityStructHash(payload.security);

        bytes32 primaryTypeHash = getTypeHash(m, params);

        bytes32 structHash = keccak256(
            abi.encode(
                primaryTypeHash,
                actionStructHash,
                securityStructHash
            )
        );
        return structHash;
    }

    function _getSecurityStructHash(IClearMacroForwarderV1.Security memory security) internal pure returns (bytes32) {
        return keccak256(abi.encode(
            _TYPEHASH_SECURITY,
            keccak256(bytes(security.domain)),
            keccak256(bytes(security.provider)),
            security.validAfter,
            security.validBefore,
            security.nonce
        ));
    }

    function _getDigest(IClearMacro m, bytes calldata params) internal view returns (bytes32) {
        bytes32 structHash = _getStructHash(m, params);
        return _hashTypedDataV4(structHash);
    }
}
