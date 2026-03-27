// SPDX-License-Identifier: AGPLv3
pragma solidity ^0.8.23;

import { SignatureChecker } from "@openzeppelin-v5/contracts/utils/cryptography/SignatureChecker.sol";
import { IClearMacro } from "../interfaces/utils/IClearMacro.sol";
import { IERC20Metadata } from "@openzeppelin-v5/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { ISuperfluid, BatchOperation, ISuperToken, IERC20 } from "../interfaces/superfluid/ISuperfluid.sol";
import { IPermit2 } from "../interfaces/external/IPermit2.sol";
import { IClearMacroForwarderV1 } from "../interfaces/utils/IClearMacroForwarderV1.sol";
import { IClearMacroPermit2Extension } from "../interfaces/utils/IClearMacroForwarderV1WithPermit2.sol";
import { ClearMacroForwarderV1 } from "./ClearMacroForwarderV1.sol";

/**
 * @dev Permit2-aware extension of ClearMacroForwarderV1.
 * Supports Permit2 witness validation and, optionally, pulling underlying tokens
 * via Permit2 before upgrading and executing the macro.
 */
contract ClearMacroForwarderV1WithPermit2 is ClearMacroForwarderV1, IClearMacroPermit2Extension {
    /// @dev Canonical Permit2 address (same across all EVM chains)
    address public constant PERMIT2 = 0x000000000022D473030F116dDEE9F6B43aC78BA3;

    /// @dev Constant witness type name for nested ClearMacro payloads. Ensures deterministic
    /// alphabetical ordering (Action, ClearMacro, Security, TokenPermissions) regardless of macro.
    string private constant _CLEAR_MACRO_WITNESS_TYPE_NAME = "ClearMacro";

    bytes32 private constant _TOKEN_PERMISSIONS_TYPEHASH =
        keccak256("TokenPermissions(address token,uint256 amount)");
    string private constant _PERMIT_WITNESS_TRANSFER_FROM_STUB =
        "PermitWitnessTransferFrom(TokenPermissions permitted,address spender,uint256 nonce,uint256 deadline,";

    constructor(ISuperfluid host) ClearMacroForwarderV1(host) {}

    /**
     * @dev Runs the macro with Permit2 witness validation.
     * If `upgradeSuperToken` is set, underlying tokens are first pulled via Permit2
     * and upgraded before the macro is executed.
     * @param  p       Permit2 data and optional upgrade configuration.
     * @param  m       Target macro.
     * @param  params  ABI-encoded `IClearMacroForwarderV1.Payload`.
     */
    function runPermit2AndMacro(
        Permit2MacroParams calldata p,
        IClearMacro m,
        bytes calldata params
    ) external payable override returns (bool) {
        _validatePermitAndMaybePull(p, m, params);
        _validatePayload(m, params, p.owner, msg.sender);
        return _executeValidatedMacro(m, params, p.owner);
    }

    function _validatePermitAndMaybePull(
        Permit2MacroParams calldata p,
        IClearMacro m,
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

    /**
     * @dev Struct hash of the ClearMacro payload for use as Permit2 witness.
     * Uses constant type name "ClearMacro" with nested Security so the witness type string
     * has deterministic alphabetical ordering regardless of the macro's primary type name.
     */
    function getPermit2WitnessStructHash(IClearMacro m, bytes calldata params)
        external
        view
        override
        returns (bytes32)
    {
        return _getPermit2WitnessStructHash(m, params);
    }

    function _getPermit2WitnessStructHash(IClearMacro m, bytes calldata params)
        internal
        view
        returns (bytes32)
    {
        IClearMacroForwarderV1.Payload memory payload =
            abi.decode(params, (IClearMacroForwarderV1.Payload));
        bytes32 actionStructHash = m.getActionStructHash(payload.action.params);
        bytes32 securityStructHash = _getSecurityStructHash(payload.security);
        string memory typeDef = string(abi.encodePacked(
            _CLEAR_MACRO_WITNESS_TYPE_NAME,
            "(Action action,Security security)",
            m.getActionTypeDefinition(params),
            _TYPEDEF_SECURITY
        ));
        bytes32 primaryTypeHash = keccak256(abi.encodePacked(typeDef));
        return keccak256(abi.encode(
            primaryTypeHash,
            actionStructHash,
            securityStructHash
        ));
    }

    /**
     * @dev Witness type string for Permit2 PermitWitnessTransferFrom.
     * Uses constant "ClearMacro" with nested Security for deterministic alphabetical order:
     * Action, ClearMacro, Security, TokenPermissions.
     */
    function getPermit2WitnessTypeString(IClearMacro m, bytes calldata params)
        external
        view
        override
        returns (string memory)
    {
        string memory actionDef = m.getActionTypeDefinition(params);
        string memory clearMacroDef = string(abi.encodePacked(
            _CLEAR_MACRO_WITNESS_TYPE_NAME,
            "(Action action,Security security)"
        ));
        string memory tokenPermDef = "TokenPermissions(address token,uint256 amount)";

        return string(abi.encodePacked(
            _CLEAR_MACRO_WITNESS_TYPE_NAME,
            " witness)",
            actionDef,
            clearMacroDef,
            _TYPEDEF_SECURITY,
            tokenPermDef
        ));
    }
}
