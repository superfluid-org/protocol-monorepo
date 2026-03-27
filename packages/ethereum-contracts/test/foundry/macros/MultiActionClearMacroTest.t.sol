// SPDX-License-Identifier: AGPLv3
pragma solidity ^0.8.23;

import {
    BatchOperation,
    ISuperfluid,
    ISuperToken
} from "../../../contracts/interfaces/superfluid/ISuperfluid.sol";
import { IERC20Metadata } from "@openzeppelin-v5/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { IConstantFlowAgreementV1 } from "../../../contracts/interfaces/agreements/IConstantFlowAgreementV1.sol";
import { ClearMacroBase } from "../../../contracts/utils/ClearMacroBase.sol";
import { FlowRateFormatter, AmountFormatter } from "../libs/FormatterLibs.sol";

using FlowRateFormatter for int96;
using AmountFormatter for uint256;

/**
 * @title MultiActionClearMacroTest
 * @dev Test macro with two actions: CreateFlow and Upgrade, for use with ClearMacroForwarderV1.
 * Description from (lang, actionParams); "en"/"hu" for Upgrade, "en" for CreateFlow.
 */
contract MultiActionClearMacroTest is ClearMacroBase {
    uint8 public constant ACTION_CREATE_FLOW = 1;
    uint8 public constant ACTION_UPGRADE = 2;

    bytes32 private constant _LANG_EN = bytes32("en");
    bytes32 private constant _LANG_HU = bytes32("hu");

    string private constant _TYPEDEF_CREATE_FLOW =
        "Action(string description,address token,address receiver,int96 flowRate)";
    string private constant _TYPEDEF_UPGRADE =
        "Action(string description,address token,uint256 amount)";

    function _getActions() internal pure override returns (ClearMacroBase.Action[] memory) {
        ClearMacroBase.Action[] memory actions = new ClearMacroBase.Action[](2);
        actions[0] = ClearMacroBase.Action({
            actionCode: ACTION_CREATE_FLOW,
            exists: true,
            getPrimaryTypeName: _getPrimaryTypeNameCreateFlow,
            getActionTypeDefinition: _getActionTypeDefinitionCreateFlow,
            getActionStructHash: _getActionStructHashCreateFlow,
            buildOperations: _buildOperationsCreateFlow,
            skipPostCheck: true,
            postCheckHandler: _noOpPostCheck
        });
        actions[1] = ClearMacroBase.Action({
            actionCode: ACTION_UPGRADE,
            exists: true,
            getPrimaryTypeName: _getPrimaryTypeNameUpgrade,
            getActionTypeDefinition: _getActionTypeDefinitionUpgrade,
            getActionStructHash: _getActionStructHashUpgrade,
            buildOperations: _buildOperationsUpgrade,
            skipPostCheck: true,
            postCheckHandler: _noOpPostCheck
        });
        return actions;
    }

    function _encodeRaw(uint8 actionCode, bytes32 lang, bytes memory actionParams)
        private
        pure
        returns (bytes memory)
    {
        return abi.encode(actionCode, lang, actionParams);
    }

    function encodeCreateFlow(bytes32 lang, address token, address receiver, int96 flowRate)
        public
        pure
        returns (bytes memory)
    {
        return _encodeRaw(ACTION_CREATE_FLOW, lang, abi.encode(token, receiver, flowRate));
    }

    function encodeUpgrade(bytes32 lang, address token, uint256 amount)
        public
        pure
        returns (bytes memory)
    {
        return _encodeRaw(ACTION_UPGRADE, lang, abi.encode(token, amount));
    }

    function _noOpPostCheck(ISuperfluid, bytes memory, address) internal pure {
        // no-op
    }

    // ---------- CreateFlow ----------
    function _descriptionCreateFlow(bytes32 lang, address token, address /* receiver */, int96 flowRate)
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
            "/day"
        );
    }

    function _getPrimaryTypeNameCreateFlow(bytes memory) internal pure returns (string memory) {
        return "DashboardCreateFlow";
    }

    function _getActionTypeDefinitionCreateFlow(bytes memory) internal pure returns (string memory) {
        return _TYPEDEF_CREATE_FLOW;
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

    function _getPrimaryTypeNameUpgrade(bytes memory) internal pure returns (string memory) {
        return "DashboardUpgrade";
    }

    function _getActionTypeDefinitionUpgrade(bytes memory) internal pure returns (string memory) {
        return _TYPEDEF_UPGRADE;
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
