// SPDX-License-Identifier: AGPLv3
pragma solidity ^0.8.23;

import { SignatureChecker } from "@openzeppelin-v5/contracts/utils/cryptography/SignatureChecker.sol";
import { IClearMacro } from "../interfaces/utils/IClearMacro.sol";
import { IERC20Metadata } from "@openzeppelin-v5/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { SafeERC20 } from "@openzeppelin-v5/contracts/token/ERC20/utils/SafeERC20.sol";
import { ISuperfluid, BatchOperation, ISuperToken, IERC20 } from "../interfaces/superfluid/ISuperfluid.sol";
import { IPermit2 } from "../interfaces/external/IPermit2.sol";
import { IClearMacroForwarderV1 } from "../interfaces/utils/IClearMacroForwarderV1.sol";
import { IClearMacroPermit2Extension } from "../interfaces/utils/IClearMacroForwarderV1WithPermit2.sol";
import { ClearMacroForwarderV1 } from "./ClearMacroForwarderV1.sol";

/**
 * @title ClearMacroForwarderV1WithPermit2
 * @notice {ClearMacroForwarderV1} with Permit2 witness binding; see {IClearMacroPermit2Extension}.
 */
contract ClearMacroForwarderV1WithPermit2 is ClearMacroForwarderV1, IClearMacroPermit2Extension {
    using SafeERC20 for IERC20;

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

    /// @inheritdoc IClearMacroPermit2Extension
    function runPermit2AndMacro(
        Permit2Context calldata permit2Context,
        IClearMacro m,
        bytes calldata params
    ) external payable override returns (bool) {
        _validatePermitAndMaybePull(permit2Context, m, params);
        _validatePayload(m, params, permit2Context.owner, msg.sender);
        return _executeValidatedMacro(m, params, permit2Context.owner);
    }

    function _validatePermitAndMaybePull(
        Permit2Context calldata permit2Context,
        IClearMacro m,
        bytes calldata params
    ) internal {
        if (permit2Context.witness != this.getPermit2WitnessStructHash(m, params, permit2Context.upgradeSuperToken)) {
            revert InvalidPayload("witness mismatch");
        }

        if (permit2Context.upgradeSuperToken != address(0)) {
            // Implied upgrade: Permit2 pull + upgrade, then macro (spender must be this contract).
            _pullAndUpgrade(permit2Context);
        } else {
            // Witness only: verify Permit2 signature; no transfer and no Permit2 nonce consumption.
            if (!_verifyPermit2Signature(
                    permit2Context.permit,
                    permit2Context.owner,
                    permit2Context.spender,
                    permit2Context.witness,
                    permit2Context.witnessTypeString,
                    permit2Context.signature
                )) {
                revert InvalidSignature();
            }
        }
    }

    function _pullAndUpgrade(Permit2Context calldata permit2Context) internal {
        IPermit2(PERMIT2).permitWitnessTransferFrom(
            permit2Context.permit,
            IPermit2.SignatureTransferDetails({
                to: address(this), requestedAmount: permit2Context.permit.permitted.amount
            }),
            permit2Context.owner,
            permit2Context.witness,
            permit2Context.witnessTypeString,
            permit2Context.signature
        );
        address underlying = permit2Context.permit.permitted.token;
        uint256 underlyingAmount = permit2Context.permit.permitted.amount;
        if (ISuperToken(permit2Context.upgradeSuperToken).getUnderlyingToken() != underlying) {
            revert InvalidPayload("permit token mismatch");
        }
        uint256 amount = _toSuperTokenAmount(underlyingAmount, IERC20Metadata(underlying).decimals());
        IERC20(underlying).forceApprove(permit2Context.upgradeSuperToken, underlyingAmount);
        ISuperfluid.Operation[] memory ops = new ISuperfluid.Operation[](1);
        ops[0] = ISuperfluid.Operation({
            operationType: BatchOperation.OPERATION_TYPE_SUPERTOKEN_UPGRADE_TO,
            target: permit2Context.upgradeSuperToken,
            data: abi.encode(permit2Context.owner, amount)
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
     * Binds `upgradeSuperToken` (`address(0)` selects witness-only mode).
     */
    function getPermit2WitnessStructHash(IClearMacro m, bytes calldata params, address upgradeSuperToken)
        external
        view
        override
        returns (bytes32)
    {
        return _getPermit2WitnessStructHash(m, params, upgradeSuperToken);
    }

    function _permit2WitnessInnerTypeDefinition(IClearMacro m, bytes calldata params)
        internal
        view
        returns (string memory)
    {
        return string(abi.encodePacked(
            _CLEAR_MACRO_WITNESS_TYPE_NAME,
            "(address upgradeSuperToken,Action action,Security security)",
            m.getActionTypeDefinition(params),
            _TYPEDEF_SECURITY
        ));
    }

    function _getPermit2WitnessStructHash(IClearMacro m, bytes calldata params, address upgradeSuperToken)
        internal
        view
        returns (bytes32)
    {
        IClearMacroForwarderV1.Payload memory payload =
            abi.decode(params, (IClearMacroForwarderV1.Payload));
        bytes32 actionStructHash = m.getActionStructHash(payload.action.params);
        bytes32 securityStructHash = _getSecurityStructHash(payload.security);
        bytes32 primaryTypeHash = keccak256(abi.encodePacked(_permit2WitnessInnerTypeDefinition(m, params)));
        return keccak256(abi.encode(
            primaryTypeHash,
            upgradeSuperToken,
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
            "(address upgradeSuperToken,Action action,Security security)"
        ));
        string memory tokenPermDef = "TokenPermissions(address token,uint256 amount)";

        // Uses constant type name "ClearMacro" with nested Security so the witness type string
        // has deterministic alphabetical ordering regardless of the macro's primary type name.
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
