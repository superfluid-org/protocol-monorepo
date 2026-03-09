// SPDX-License-Identifier: AGPLv3
pragma solidity ^0.8.23;

import { SignatureChecker } from "@openzeppelin-v5/contracts/utils/cryptography/SignatureChecker.sol";
import { IUserDefined712Macro } from "../interfaces/utils/IUserDefinedMacro.sol";
import { IERC20Metadata } from "@openzeppelin-v5/contracts/token/ERC20/extensions/IERC20Metadata.sol";
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

    /// @dev Constant witness type name for nested ClearSigning payloads. Ensures deterministic
    /// alphabetical ordering (Action, ClearSigning, TokenPermissions) regardless of macro.
    string private constant _CLEAR_SIGNING_WITNESS_TYPE = "ClearSigning";

    bytes32 private constant _TOKEN_PERMISSIONS_TYPEHASH =
        keccak256("TokenPermissions(address token,uint256 amount)");
    string private constant _PERMIT_WITNESS_TRANSFER_FROM_STUB =
        "PermitWitnessTransferFrom(TokenPermissions permitted,address spender,uint256 nonce,uint256 deadline,";

    struct Permit2MacroParams {
        IPermit2.PermitTransferFrom permit;
        IPermit2.SignatureTransferDetails transferDetails;
        address owner;
        bytes32 witness;
        string witnessTypeString;
        bytes signature;
        address spender;
        address upgradeSuperToken;
    }

    constructor(ISuperfluid host) Only712MacroForwarder(host) {}

    /**
     * @dev Run macro with Permit2 witness.
     * @param p Permit2 data: permit, transferDetails, owner, witness, witnessTypeString, signature,
     *   spender (the address the owner signed for), upgradeSuperToken (when spender is self).
     * @param m Target macro
     * @param params Encoded ClearSigning payload
     */
    function runPermit2AndMacro(
        Permit2MacroParams calldata p,
        IUserDefined712Macro m,
        bytes calldata params
    ) external payable returns (bool) {
        _validatePermitAndMaybePull(p, m, params);
        return _executeMacroLogic(m, params, p.owner);
    }

    function _validatePermitAndMaybePull(
        Permit2MacroParams calldata p,
        IUserDefined712Macro m,
        bytes calldata params
    ) internal {
        if (p.witness != this.getPermit2WitnessStructHash(m, params)) {
            revert InvalidPayload("witness mismatch");
        }

        if (p.upgradeSuperToken != address(0)) {
            // No explicit checks needed: Permit2 reverts if the permit is invalid or spender != address(this);
            // we validate permit.permitted.token matches upgradeSuperToken's underlying in _pullAndUpgrade.
            _pullAndUpgrade(p);
        } else {
            if (!_verifyPermit2Signature(p.permit, p.owner, p.spender, p.witness, p.witnessTypeString, p.signature)) {
                revert InvalidSignature();
            }
        }
    }

    function _pullAndUpgrade(Permit2MacroParams calldata p) internal {
        IPermit2(PERMIT2).permitWitnessTransferFrom(
            p.permit, p.transferDetails, p.owner, p.witness, p.witnessTypeString, p.signature
        );
        address underlying = p.permit.permitted.token;
        uint256 underlyingAmount = p.permit.permitted.amount;
        if (ISuperToken(p.upgradeSuperToken).getUnderlyingToken() != underlying) {
            revert InvalidPayload("permit token mismatch");
        }
        uint256 amount = _toSuperTokenAmount(underlyingAmount, IERC20Metadata(underlying).decimals());
        IERC20(underlying).approve(p.upgradeSuperToken, underlyingAmount);
        ISuperfluid.Operation[] memory ops = new ISuperfluid.Operation[](1);
        ops[0] = ISuperfluid.Operation({
            operationType: BatchOperation.OPERATION_TYPE_SUPERTOKEN_UPGRADE_TO,
            target: p.upgradeSuperToken,
            data: abi.encode(p.owner, amount)
        });
        _host.batchCall(ops);
    }

    /// @dev Converts underlying amount (in underlying decimals) to SuperToken amount (18 decimals).
    function _toSuperTokenAmount(uint256 underlyingAmount, uint8 underlyingDecimals) internal pure returns (uint256) {
        uint256 factor;
        if (underlyingDecimals < 18) {
            factor = 10 ** (18 - underlyingDecimals);
            return underlyingAmount * factor;
        } else if (underlyingDecimals > 18) {
            factor = 10 ** (underlyingDecimals - 18);
            return underlyingAmount / factor;
        }
        return underlyingAmount;
    }

    function _verifyPermit2Signature(
        IPermit2.PermitTransferFrom calldata permit,
        address owner,
        address spender,
        bytes32 witness,
        string calldata witnessTypeString,
        bytes calldata signature
    ) internal view returns (bool) {
        return SignatureChecker.isValidSignatureNow(
            owner, _permit2Digest(permit, spender, witness, witnessTypeString), signature
        );
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

    /**
     * @dev Struct hash of the ClearSigning payload for use as Permit2 witness.
     * Uses constant type name "ClearSigning" so the witness type string has deterministic
     * alphabetical ordering regardless of the macro's primary type name.
     */
    function getPermit2WitnessStructHash(IUserDefined712Macro m, bytes calldata params)
        external
        view
        returns (bytes32)
    {
        return _getPermit2WitnessStructHash(m, params);
    }

    function _getPermit2WitnessStructHash(IUserDefined712Macro m, bytes calldata params)
        internal
        view
        returns (bytes32)
    {
        PrimaryType memory payload = abi.decode(params, (PrimaryType));
        bytes32 actionStructHash = m.getActionStructHash(payload.action.actionParams);
        string memory typeDef = string(abi.encodePacked(
            _CLEAR_SIGNING_WITNESS_TYPE,
            "(Action action,string domain,uint256 nonce,string provider,uint256 validAfter,uint256 validBefore)",
            m.getActionTypeDefinition(params)
        ));
        bytes32 primaryTypeHash = keccak256(abi.encodePacked(typeDef));
        return keccak256(abi.encode(
            primaryTypeHash,
            actionStructHash,
            keccak256(bytes(payload.domain)),
            payload.nonce,
            keccak256(bytes(payload.provider)),
            payload.validAfter,
            payload.validBefore
        ));
    }

    /**
     * @dev Witness type string for Permit2 PermitWitnessTransferFrom.
     * Uses constant "ClearSigning" for deterministic alphabetical order:
     * Action, ClearSigning, TokenPermissions.
     */
    function getPermit2WitnessTypeString(IUserDefined712Macro m, bytes calldata params)
        external
        view
        returns (string memory)
    {
        string memory actionDef = m.getActionTypeDefinition(params);
        string memory clearSigningDef = string(abi.encodePacked(
            _CLEAR_SIGNING_WITNESS_TYPE,
            "(Action action,string domain,uint256 nonce,string provider,uint256 validAfter,uint256 validBefore)"
        ));
        string memory tokenPermDef = "TokenPermissions(address token,uint256 amount)";

        return string(abi.encodePacked(
            _CLEAR_SIGNING_WITNESS_TYPE,
            " witness)",
            actionDef,
            clearSigningDef,
            tokenPermDef
        ));
    }
}