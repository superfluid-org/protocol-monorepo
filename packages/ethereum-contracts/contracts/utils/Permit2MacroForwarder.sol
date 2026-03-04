// SPDX-License-Identifier: AGPLv3
pragma solidity ^0.8.23;

import { SignatureChecker } from "@openzeppelin-v5/contracts/utils/cryptography/SignatureChecker.sol";
import { IUserDefined712Macro } from "../interfaces/utils/IUserDefinedMacro.sol";
import { ISuperfluid, BatchOperation, ISuperToken, IERC20 } from "../interfaces/superfluid/ISuperfluid.sol";
import { IPermit2 } from "../interfaces/external/IPermit2.sol";
import { Only712MacroForwarder } from "./Only712MacroForwarder.sol";

/**
 * @dev Permit2-aware macro forwarder.
 * Single entry point: runPermit2AndMacro.
 *
 * When the signer designated this forwarder as the Permit2 spender and recipient,
 * we: (1) pull underlying via Permit2 to self, (2) upgrade to the signer, (3) run the macro.
 * Otherwise we only verify the witness and run the macro (caller must have handled funding).
 *
 * Use getPermit2WitnessTypeString to build the witness type string for signing.
 */
contract Permit2MacroForwarder is Only712MacroForwarder {

    /// @dev Canonical Permit2 address (same across all EVM chains)
    address public constant PERMIT2 = 0x000000000022D473030F116dDEE9F6B43aC78BA3;

    bytes32 private constant _TOKEN_PERMISSIONS_TYPEHASH =
        keccak256("TokenPermissions(address token,uint256 amount)");
    string private constant _PERMIT_WITNESS_TRANSFER_FROM_STUB =
        "PermitWitnessTransferFrom(TokenPermissions permitted,address spender,uint256 nonce,uint256 deadline,";

    constructor(ISuperfluid host) Only712MacroForwarder(host) {}

    /**
     * @dev Run macro with Permit2 witness. Upgrade is implied when this forwarder is the spender.
     * @param permit Permit2 permit data
     * @param transferDetails Where tokens go (to) and how much (requestedAmount)
     * @param owner Signer and token owner
     * @param witness Struct hash of the ClearSigning payload
     * @param witnessTypeString From getPermit2WitnessTypeString(m, params)
     * @param signature Permit2 signature
     * @param m Target macro
     * @param params Encoded ClearSigning payload
     */
    function runPermit2AndMacro(
        IPermit2.PermitTransferFrom calldata permit,
        IPermit2.SignatureTransferDetails calldata transferDetails,
        address owner,
        bytes32 witness,
        string calldata witnessTypeString,
        bytes calldata signature,
        IUserDefined712Macro m,
        bytes calldata params
    ) external payable returns (bool) {
        if (witness != this.getStructHash(m, params)) {
            revert InvalidPayload("witness mismatch");
        }

        bool weAreSpender = SignatureChecker.isValidSignatureNow(
            owner, _permit2Digest(permit, address(this), witness, witnessTypeString), signature
        );

        if (weAreSpender) {
            if (transferDetails.to != address(this)) {
                revert InvalidPayload("spender is self but transfer not to self");
            }
            _pullAndUpgrade(permit, transferDetails, owner, witness, witnessTypeString, signature, m, params);
        } else {
            if (
                !SignatureChecker.isValidSignatureNow(
                    owner, _permit2Digest(permit, msg.sender, witness, witnessTypeString), signature
                )
            ) {
                revert InvalidSignature();
            }
        }

        return _executeMacroLogic(m, params, owner);
    }

    function _pullAndUpgrade(
        IPermit2.PermitTransferFrom calldata permit,
        IPermit2.SignatureTransferDetails calldata transferDetails,
        address owner,
        bytes32 witness,
        string calldata witnessTypeString,
        bytes calldata signature,
        IUserDefined712Macro /* m */,
        bytes calldata params
    ) internal {
        IPermit2(PERMIT2).permitWitnessTransferFrom(
            permit, transferDetails, owner, witness, witnessTypeString, signature
        );
        _upgradeToSigner(params, owner, permit.permitted.token, permit.permitted.amount);
    }

    function _upgradeToSigner(
        bytes calldata params,
        address owner,
        address underlyingToken,
        uint256 underlyingAmount
    ) internal {
        (address superTokenAddr, uint256 amount) = _decodeSuperTokenAndAmount(params);
        if (ISuperToken(superTokenAddr).getUnderlyingToken() != underlyingToken) {
            revert InvalidPayload("permit token mismatch");
        }
        IERC20(underlyingToken).approve(superTokenAddr, underlyingAmount);
        ISuperfluid.Operation[] memory ops = new ISuperfluid.Operation[](1);
        ops[0] = ISuperfluid.Operation({
            operationType: BatchOperation.OPERATION_TYPE_SUPERTOKEN_UPGRADE_TO,
            target: superTokenAddr,
            data: abi.encode(owner, amount)
        });
        _host.batchCall(ops);
    }

    function _decodeSuperTokenAndAmount(bytes calldata params) internal pure returns (address, uint256) {
        PrimaryType memory payload = abi.decode(params, (PrimaryType));
        return abi.decode(payload.action.actionParams, (address, uint256));
    }

    function _permit2Digest(
        IPermit2.PermitTransferFrom calldata permit,
        address spender,
        bytes32 witness,
        string calldata witnessTypeString
    ) internal view returns (bytes32) {
        bytes32 typeHash = keccak256(abi.encodePacked(_PERMIT_WITNESS_TRANSFER_FROM_STUB, witnessTypeString));
        bytes32 tokenPermissionsHash = keccak256(abi.encode(_TOKEN_PERMISSIONS_TYPEHASH, permit.permitted));
        bytes32 structHash = keccak256(abi.encode(
            typeHash,
            tokenPermissionsHash,
            spender,
            permit.nonce,
            permit.deadline,
            witness
        ));
        return keccak256(abi.encodePacked("\x19\x01", IPermit2(PERMIT2).DOMAIN_SEPARATOR(), structHash));
    }

    /// Duplicated from Only712MacroForwarder — consider extracting _executeMacro in base.
    function _executeMacroLogic(IUserDefined712Macro m, bytes calldata params, address signer)
        internal
        returns (bool)
    {
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

        ISuperfluid.Operation[] memory operations =
            m.buildBatchOperations(_host, payload.action.actionParams, signer);

        bool retVal = _forwardBatchCallWithSenderAndValue(operations, signer, msg.value);
        m.postCheck(_host, payload.action.actionParams, signer);
        return retVal;
    }

    function getPermit2WitnessTypeString(IUserDefined712Macro m, bytes calldata params)
        external
        view
        returns (string memory)
    {
        string memory primaryName = m.getPrimaryTypeName(params);
        string memory actionDef = m.getActionTypeDefinition(params);
        string memory primaryDef = string(abi.encodePacked(
            primaryName,
            "(Action action,string domain,uint256 nonce,string provider,uint256 validAfter,uint256 validBefore)"
        ));
        string memory tokenPermDef = "TokenPermissions(address token,uint256 amount)";

        return string(abi.encodePacked(
            primaryName,
            " witness)",
            actionDef,
            primaryDef,
            tokenPermDef
        ));
    }
}