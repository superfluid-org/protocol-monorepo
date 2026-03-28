// SPDX-License-Identifier: AGPLv3
pragma solidity ^0.8.23;

import {
    BatchOperation,
    ISuperfluid,
    ISuperToken
} from "../../../contracts/interfaces/superfluid/ISuperfluid.sol";
import { IERC20Metadata } from "@openzeppelin-v5/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { Strings } from "@openzeppelin-v5/contracts/utils/Strings.sol";
import { IConstantFlowAgreementV1 } from "../../../contracts/interfaces/agreements/IConstantFlowAgreementV1.sol";
import { ClearMacroBase } from "../../../contracts/utils/ClearMacroBase.sol";
import { FlowRateFormatter, AmountFormatter } from "../libs/FormatterLibs.sol";

using FlowRateFormatter for int96;
using AmountFormatter for uint256;

/**
 * @title MultiActionClearMacro
 * @dev Reference example for a ClearMacro with multiple actions.
 *
 * Demonstrates:
 * - declaring a stable action id enum used on the wire
 * - registering per-action metadata and handlers in `_registerActions()`
 * - exposing typed `encode...()` helpers for callers
 * - deriving localized EIP-712 descriptions from `(lang, actionParams)`
 */
contract MultiActionClearMacro is ClearMacroBase {

    // Stable action ids used both during registration and in the encoded payload.
    enum ActionId {
        CreateFlow,
        Upgrade
    }

    bytes32 private constant _LANG_EN = bytes32("en");
    bytes32 private constant _LANG_HU = bytes32("hu");

    string private constant _TYPEDEF_CREATE_FLOW =
        "Action(string description,address token,address receiver,int96 flowRate)";
    string private constant _TYPEDEF_UPGRADE =
        "Action(string description,address token,uint256 amount)";

    // Each registration entry must match the action id used by the corresponding encode helper.
    function _registerActions() internal override {
        _registerAction(uint8(ActionId.CreateFlow), ClearMacroBase.ActionSpec({
            primaryTypeName: "DashboardCreateFlow",
            actionTypeDefinition: _TYPEDEF_CREATE_FLOW,
            getActionStructHash: _getActionStructHashCreateFlow,
            buildOperations: _buildOperationsCreateFlow,
            postCheck: _noOpPostCheck
        }));
        _registerAction(uint8(ActionId.Upgrade), ClearMacroBase.ActionSpec({
            primaryTypeName: "DashboardUpgrade",
            actionTypeDefinition: _TYPEDEF_UPGRADE,
            getActionStructHash: _getActionStructHashUpgrade,
            buildOperations: _buildOperationsUpgrade,
            postCheck: _noOpPostCheck
        }));
    }

    // ClearMacroBase expects `abi.encode(uint8 actionId, bytes32 lang, bytes actionParams)`.
    function _encodeRaw(ActionId actionId, bytes32 lang, bytes memory actionParams)
        private
        pure
        returns (bytes memory)
    {
        return abi.encode(uint8(actionId), lang, actionParams);
    }

    // ---------- CreateFlow ----------

    function encodeCreateFlow(bytes32 lang, address token, address receiver, int96 flowRate)
        public
        pure
        returns (bytes memory)
    {
        return _encodeRaw(ActionId.CreateFlow, lang, abi.encode(token, receiver, flowRate));
    }

    function _descriptionCreateFlow(bytes32 lang, address token, address receiver, int96 flowRate)
        internal
        view
        returns (string memory)
    {
        if (lang != _LANG_EN) revert UnsupportedLanguage();
        return string.concat(
            "Create a new flow of ",
            flowRate.toFlowRatePerDay(),
            " ",
            ISuperToken(token).symbol(),
            "/day to ",
            Strings.toHexString(receiver)
        );
    }

    function _getActionStructHashCreateFlow(bytes memory actionParams, bytes32 lang)
        internal
        view
        returns (bytes32)
    {
        (address token, address receiver, int96 flowRate) =
            abi.decode(actionParams, (address, address, int96));
        string memory desc = _descriptionCreateFlow(lang, token, receiver, flowRate);
        return keccak256(abi.encode(
            keccak256(abi.encodePacked(_TYPEDEF_CREATE_FLOW)),
            keccak256(bytes(desc)),
            token,
            receiver,
            flowRate
        ));
    }

    function _buildOperationsCreateFlow(ISuperfluid host, bytes memory actionParams, address)
        internal
        view
        returns (ISuperfluid.Operation[] memory)
    {
        (address token, address receiver, int96 flowRate) =
            abi.decode(actionParams, (address, address, int96));
        IConstantFlowAgreementV1 cfa = IConstantFlowAgreementV1(address(host.getAgreementClass(
            keccak256("org.superfluid-finance.agreements.ConstantFlowAgreement.v1")
        )));
        bytes memory callData = abi.encodeCall(
            cfa.createFlow,
            (ISuperToken(token), receiver, flowRate, new bytes(0))
        );
        ISuperfluid.Operation[] memory ops = new ISuperfluid.Operation[](1);
        ops[0] = ISuperfluid.Operation({
            operationType: BatchOperation.OPERATION_TYPE_SUPERFLUID_CALL_AGREEMENT,
            target: address(cfa),
            data: abi.encode(callData, new bytes(0))
        });
        return ops;
    }

    // ---------- Upgrade ----------

    function encodeUpgrade(bytes32 lang, address token, uint256 amount)
        public
        pure
        returns (bytes memory)
    {
        return _encodeRaw(ActionId.Upgrade, lang, abi.encode(token, amount));
    }

    function _descriptionUpgrade(bytes32 lang, address token, uint256 amount)
        internal
        view
        returns (string memory)
    {
        ISuperToken superToken = ISuperToken(token);
        address underlyingToken = superToken.getUnderlyingToken();
        string memory amountStr = amount.toHumanReadable();
        string memory underlyingSymbol = IERC20Metadata(underlyingToken).symbol();
        string memory superSymbol = superToken.symbol();
        if (lang == _LANG_EN) {
            return string.concat(
                "Upgrade ", amountStr, " ", underlyingSymbol, " to ", superSymbol
            );
        }
        if (lang == _LANG_HU) {
            return string.concat(
                unicode"Frissítés ", amountStr, " ", underlyingSymbol, " to ", superSymbol
            );
        }
        revert UnsupportedLanguage();
    }

    function _getActionStructHashUpgrade(bytes memory actionParams, bytes32 lang)
        internal
        view
        returns (bytes32)
    {
        (address token, uint256 amount) = abi.decode(actionParams, (address, uint256));
        string memory desc = _descriptionUpgrade(lang, token, amount);
        return keccak256(abi.encode(
            keccak256(abi.encodePacked(_TYPEDEF_UPGRADE)),
            keccak256(bytes(desc)),
            token,
            amount
        ));
    }

    function _buildOperationsUpgrade(ISuperfluid, bytes memory actionParams, address)
        internal
        pure
        returns (ISuperfluid.Operation[] memory)
    {
        (address token, uint256 amount) = abi.decode(actionParams, (address, uint256));
        ISuperfluid.Operation[] memory ops = new ISuperfluid.Operation[](1);
        ops[0] = ISuperfluid.Operation({
            operationType: BatchOperation.OPERATION_TYPE_SUPERTOKEN_UPGRADE,
            target: token,
            data: abi.encode(amount)
        });
        return ops;
    }
}
