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

    // top-level data structure (security fields flattened; Action remains nested)
    struct PrimaryType {
        ActionType action;
        string domain;
        uint256 nonce;
        string provider;
        uint256 validAfter;
        uint256 validBefore;
    }
    struct ActionType {
        bytes actionParams;
    }

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
        bytes32 providerRole = keccak256(bytes(payload.provider));
        if (!_providerACL.hasRole(providerRole, msg.sender)) {
            revert ProviderNotAuthorized(payload.provider, msg.sender);
        }

        _validateAndUpdateNonce(signer, payload.nonce);

        if (block.timestamp < payload.validAfter) {
            revert OutsideValidityWindow(block.timestamp, payload.validBefore, payload.validAfter);
        }
        if (payload.validBefore != 0 && block.timestamp > payload.validBefore) {
            revert OutsideValidityWindow(block.timestamp, payload.validBefore, payload.validAfter);
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

    /**
     * @dev Encode action and security params into the payload bytes expected by runMacro.
     * @param actionParams params specific to the macro action, already ABI-encoded by the caller.
     * @param domain security domain
     * @param provider security provider (must be authorized via ACL)
     * @param validAfter block timestamp after which the payload is valid
     * @param validBefore block timestamp before which the payload is valid (0 = unbounded)
     * @param nonce replay-protection nonce
     * @return Encoded payload to pass to runMacro()
     */
    function encodeParams(
        bytes calldata actionParams,
        string calldata domain,
        string calldata provider,
        uint256 validAfter,
        uint256 validBefore,
        uint256 nonce
    ) external pure returns (bytes memory) {
        PrimaryType memory payload = PrimaryType({
            action: ActionType({ actionParams: actionParams }),
            domain: domain,
            nonce: nonce,
            provider: provider,
            validAfter: validAfter,
            validBefore: validBefore
        });
        return abi.encode(payload);
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
            "(Action action,string domain,uint256 nonce,string provider,uint256 validAfter,uint256 validBefore)",
            m.getActionTypeDefinition(params)
        ));
    }

    function _getStructHash(IUserDefined712Macro m, bytes calldata params) internal view returns (bytes32) {
        PrimaryType memory payload = abi.decode(params, (PrimaryType));
        // the action fragment is handled by the user macro.
        bytes32 actionStructHash = m.getActionStructHash(payload.action.actionParams);

        // get the typehash
        bytes32 primaryTypeHash = getTypeHash(m, params);

        // struct hash: fields in type-def order (action, domain, nonce, provider, validAfter, validBefore)
        bytes32 structHash = keccak256(
            abi.encode(
                primaryTypeHash,
                actionStructHash,
                keccak256(bytes(payload.domain)),
                payload.nonce,
                keccak256(bytes(payload.provider)),
                payload.validAfter,
                payload.validBefore
            )
        );
        return structHash;
    }

    function _getDigest(IUserDefined712Macro m, bytes calldata params) internal view returns (bytes32) {
        bytes32 structHash = _getStructHash(m, params);
        return _hashTypedDataV4(structHash);
    }
}
