// SPDX-License-Identifier: AGPLv3
pragma solidity ^0.8.23;

import { EIP712 } from "@openzeppelin-v5/contracts/utils/cryptography/EIP712.sol";
import { SignatureChecker } from "@openzeppelin-v5/contracts/utils/cryptography/SignatureChecker.sol";
import { IUserDefined712Macro } from "../interfaces/utils/IUserDefinedMacro.sol";
import { ISuperfluid } from "../interfaces/superfluid/ISuperfluid.sol";
import { ForwarderBase } from "./ForwarderBase.sol";

/**
 * @dev EIP-712-aware macro forwarder (clear signing).
 * In this minimal iteration: decodes payload as appParams and passes through to the macro.
 * Envelope verification, nonce, and registry checks to be added in follow-up.
 */
contract Only712MacroForwarder is ForwarderBase, EIP712 {

    // top-level data structure
    struct Payload {
        PayloadMeta meta;
        PayloadMessage message;
        PayloadSecurity security;
    }
    struct PayloadMeta {
        string domain;
        string version;
        //string language;
        //string disclaimer;
    }
    bytes32 internal constant _TYPEHASH_META = keccak256("Meta(string domain,string version)");
    struct PayloadMessage {
        string title;
        //string description;
        bytes customPayload;
    }
    // the message typehash is user macro specific
    struct PayloadSecurity {
        string provider;
        //uint256 validAfter;
        //uint256 validBefore;
        uint256 nonce;
    }
    bytes32 internal constant _TYPEHASH_SECURITY = keccak256("Security(string provider,uint256 nonce)");

    error InvalidPayload(string message);
    error InvalidProvider(string provider);
    error InvalidSignature();

    // TODO: should this be something like "Clear Sign" instead?
    constructor(ISuperfluid host, address /*registry*/) ForwarderBase(host) EIP712("Only712MacroForwarder", "1") {}

    /**
     * @dev Run the macro with encoded payload (generic + macro specific fragments).
     * @param m Target macro.
     * @param params Encoded payload
     */
    function runMacro(IUserDefined712Macro m, bytes calldata params, address signer, bytes calldata signature)
        external payable
        returns (bool)
    {
        // decode the payload
        Payload memory payload = abi.decode(params, (Payload));
        require(
            keccak256(bytes(payload.security.provider)) == keccak256(bytes("macros.superfluid.eth")),
            InvalidProvider(payload.security.provider)
        );
        // TODO: verify nonce (replay protection)

        bytes32 digest = _getDigest(m, payload);

        // verify the signature - this also works for ERC1271 (contract signatures)
        if (!SignatureChecker.isValidSignatureNow(signer, digest, signature)) {
            revert InvalidSignature();
        }

        // get the operations array from the user macro based on the payload message
        ISuperfluid.Operation[] memory operations =
            m.buildBatchOperations(_host, payload.message.customPayload, signer);

        // forward the operations
        bool retVal = _forwardBatchCallWithValue(operations, msg.value);
        // TODO: is customPayload the correct argument here?
        m.postCheck(_host, payload.message.customPayload, signer);
        return retVal;
    }

    function getDigest(IUserDefined712Macro m, bytes calldata params) external view returns (bytes32) {
        return _getDigest(m, abi.decode(params, (Payload)));
    }

    function _getDigest(IUserDefined712Macro m, Payload memory payload) internal view returns (bytes32) {
        bytes32 metaStructHash = _getMetaStructHash(payload.meta);

        // the message fragment is handled by the user macro.
        bytes32 messageStructHash = m.getMessageStructHash(
            abi.encode(payload.message.title, payload.message.customPayload)
        );

        bytes32 securityStructHash = _getSecurityStructHash(payload.security);

        // get the typehash
        bytes32 primaryTypeHash = keccak256(
            abi.encodePacked(
                // TODO: shall we name it "ClearSign"?
                "Payload(Meta meta,Message message,Security security)",
                // nested components need to be in alphabetical order
                m.getMessageTypeHash(),
                _TYPEHASH_META,
                _TYPEHASH_SECURITY
            )
        );

        // calculate the digest of the entire payload
        bytes32 digest = _hashTypedDataV4(
            keccak256(
                abi.encode(
                    primaryTypeHash,
                    metaStructHash,
                    messageStructHash,
                    securityStructHash
                )
            )      
        );
        return digest;
    }

    function _getMetaStructHash(PayloadMeta memory meta) internal pure returns (bytes32) {
        return keccak256(abi.encode(
            _TYPEHASH_META,
            keccak256(bytes(meta.domain)),
            keccak256(bytes(meta.version))
        ));
    }

    function _getSecurityStructHash(PayloadSecurity memory security) internal pure returns (bytes32) {
        return keccak256(abi.encode(
            _TYPEHASH_SECURITY,
            keccak256(bytes(security.provider)),
            security.nonce
        ));
    }
}
