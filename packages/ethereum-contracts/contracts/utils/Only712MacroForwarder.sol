// SPDX-License-Identifier: AGPLv3
pragma solidity ^0.8.23;

import { EIP712 } from "@openzeppelin-v5/contracts/utils/cryptography/EIP712.sol";
import { SignatureChecker } from "@openzeppelin-v5/contracts/utils/cryptography/SignatureChecker.sol";
import { IAccessControl } from "@openzeppelin-v5/contracts/access/IAccessControl.sol";
import { IUserDefined712Macro } from "../interfaces/utils/IUserDefinedMacro.sol";
import { ISuperfluid } from "../interfaces/superfluid/ISuperfluid.sol";
import { ForwarderBase } from "./ForwarderBase.sol";


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
 * @dev EIP-712-aware macro forwarder (clear signing).
 * In this minimal iteration: decodes payload as appParams and passes through to the macro.
 * Envelope verification, nonce, and registry checks to be added in follow-up.
 *
 * TODO:
 * -[X] use SimpleACL for provider authorization
 * -[X] add nonce verification
 * -[X] add timeframe (validAfter, validBefore) validation
 * -[] add missing fields
 * -[] extract interface definition
 * -[] review naming
 */
contract Only712MacroForwarder is ForwarderBase, EIP712, NonceManager {

    // STRUCTS, CONSTANTS, IMMUTABLES

    // top-level data structure
    struct PrimaryType {
        ActionType action;
        SecurityType security;
    }
    struct ActionType {
        bytes actionParams;
    }
    // the action typehash is macro specific
    struct SecurityType {
        string domain;
        string provider;
        uint256 validAfter;
        uint256 validBefore;
        uint256 nonce;
    }
    bytes internal constant _TYPEDEF_SECURITY =
        "Security(string domain,string provider,uint256 validAfter,uint256 validBefore,uint256 nonce)";

    bytes32 internal constant _TYPEHASH_SECURITY = keccak256(_TYPEDEF_SECURITY);

    IAccessControl internal immutable _providerACL;

    // ERRORS

    error InvalidPayload(string message);
    error OutsideValidityWindow(uint256 blockTimestamp, uint256 validBefore, uint256 validAfter);
    error ProviderNotAuthorized(string provider, address msgSender);
    error InvalidSignature();

    // INITIALIZATION

    // Here EIP712 domain name and version are set.
    // TODO: should the name include "Superfluid"?
    constructor(ISuperfluid host) ForwarderBase(host) EIP712("ClearSigning", "1") {
        _providerACL = IAccessControl(host.getSimpleACL());
    }

    // PUBLIC FUNCTIONS

    /**
     * @dev Run the macro with encoded payload (generic + macro specific fragments).
     * @param m Target macro.
     * @param params Encoded payload
     * @param signer The signer of the payload
     * @param signature The signature of the payload
     * @return bool True if the macro was executed successfully
     */
    function runMacro(IUserDefined712Macro m, bytes calldata params, address signer, bytes calldata signature)
        external payable
        returns (bool)
    {
        // decode the payload
        PrimaryType memory payload = abi.decode(params, (PrimaryType));
        bytes32 providerRole = keccak256(bytes(payload.security.provider));
        if (!_providerACL.hasRole(providerRole, msg.sender)) {
            revert ProviderNotAuthorized(payload.security.provider, msg.sender);
        }

        _validateAndUpdateNonce(signer, payload.security.nonce);

        if (block.timestamp < payload.security.validAfter) {
            revert OutsideValidityWindow(block.timestamp, payload.security.validBefore, payload.security.validAfter);
        }
        if (payload.security.validBefore != 0 && block.timestamp > payload.security.validBefore) {
            revert OutsideValidityWindow(block.timestamp, payload.security.validBefore, payload.security.validAfter);
        }

        bytes32 digest = _getDigest(m, params);

        // verify the signature - this also works for ERC1271 (contract signatures)
        if (!SignatureChecker.isValidSignatureNow(signer, digest, signature)) {
            revert InvalidSignature();
        }

        // get the operations array from the user macro based on the action params
        ISuperfluid.Operation[] memory operations =
            m.buildBatchOperations(_host, payload.action.actionParams, signer);

        // forward the operations
        bool retVal = _forwardBatchCallWithSenderAndValue(operations, signer, msg.value);
        m.postCheck(_host, payload.action.actionParams, signer);
        return retVal;
    }

    // TODO: should this exist?
    function getTypeDefinition(IUserDefined712Macro m, bytes calldata params) external view returns (string memory) {
        return _getTypeDefinition(m, params);
    }

    // TODO: should this exist?
    function getTypeHash(IUserDefined712Macro m, bytes calldata params) public view returns (bytes32) {
        return keccak256(abi.encodePacked(_getTypeDefinition(m, params)));
    }

    // TODO: should this exist?
    function getStructHash(IUserDefined712Macro m, bytes calldata params) external view returns (bytes32) {
        return _getStructHash(m, params);
    }

    function getDigest(IUserDefined712Macro m, bytes calldata params) external view returns (bytes32) {
        return _getDigest(m, params);
    }

    // INTERNAL FUNCTIONS

    function _getTypeDefinition(IUserDefined712Macro m, bytes calldata params) internal view returns (string memory) {
        return string(abi.encodePacked(
            m.getPrimaryTypeName(params),
            "(Action action,Security security)",
            // nested components need to be in alphabetical order
            m.getActionTypeDefinition(params),
            _TYPEDEF_SECURITY
        ));
    }

    function _getStructHash(IUserDefined712Macro m, bytes calldata params) internal view returns (bytes32) {
        PrimaryType memory payload = abi.decode(params, (PrimaryType));
        // the action fragment is handled by the user macro.
        bytes32 actionStructHash = m.getActionStructHash(payload.action.actionParams);

        bytes32 securityStructHash = _getSecurityStructHash(payload.security);

        // get the typehash
        bytes32 primaryTypeHash = getTypeHash(m, params);

        // calculate the struct hash
        bytes32 structHash = keccak256(
            abi.encode(
                primaryTypeHash,
                actionStructHash,
                securityStructHash
            )
        );
        return structHash;
    }

    function _getDigest(IUserDefined712Macro m, bytes calldata params) internal view returns (bytes32) {
        bytes32 structHash = _getStructHash(m, params);
        return _hashTypedDataV4(structHash);
    }

    function _getSecurityStructHash(SecurityType memory security) internal pure returns (bytes32) {
        return keccak256(abi.encode(
            _TYPEHASH_SECURITY,
            keccak256(bytes(security.domain)),
            keccak256(bytes(security.provider)),
            security.validAfter,
            security.validBefore,
            security.nonce
        ));
    }
}
