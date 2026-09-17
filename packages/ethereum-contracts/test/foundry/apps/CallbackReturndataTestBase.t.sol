// SPDX-License-Identifier: AGPLv3
pragma solidity ^0.8.23;

import "../FoundrySuperfluidTester.t.sol";
import {
    ISuperfluid,
    ISuperToken,
    ISuperApp,
    SuperAppDefinitions
} from "../../../contracts/interfaces/superfluid/ISuperfluid.sol";
import { IConstantFlowAgreementV1 } from "../../../contracts/interfaces/agreements/IConstantFlowAgreementV1.sol";
import { SuperTokenV1Library } from "../../../contracts/apps/SuperTokenV1Library.sol";

/// @dev Super App that bombs one termination-callback returndata channel.
///      Create/update callbacks are NOOP so only the terminate path is under test.
contract TerminationReturndataBombApp is ISuperApp {
    enum Mode {
        FatBeforeCbdata,
        FatAfterNewCtx,
        FatRevertData,
        EncodedBeforeCbdata,
        MaxInnerLength
    }

    uint256 public receivedCbdataLength;
    bytes32 public receivedCbdataHash;

    Mode public immutable mode;
    uint256 public immutable payloadSize;

    constructor(ISuperfluid host, Mode mode_, uint256 payloadSize_) {
        mode = mode_;
        payloadSize = payloadSize_;

        uint256 configWord = SuperAppDefinitions.APP_LEVEL_FINAL | SuperAppDefinitions.BEFORE_AGREEMENT_CREATED_NOOP
            | SuperAppDefinitions.AFTER_AGREEMENT_CREATED_NOOP | SuperAppDefinitions.BEFORE_AGREEMENT_UPDATED_NOOP
            | SuperAppDefinitions.AFTER_AGREEMENT_UPDATED_NOOP;
        if (mode_ == Mode.FatBeforeCbdata || mode_ == Mode.FatRevertData) {
            configWord |= SuperAppDefinitions.AFTER_AGREEMENT_TERMINATED_NOOP;
        } else if (mode_ == Mode.FatAfterNewCtx) {
            configWord |= SuperAppDefinitions.BEFORE_AGREEMENT_TERMINATED_NOOP;
        }
        host.registerApp(configWord);
    }

    function beforeAgreementCreated(ISuperToken, address, bytes32, bytes calldata, bytes calldata)
        external
        pure
        returns (bytes memory)
    {
        return "";
    }

    function afterAgreementCreated(ISuperToken, address, bytes32, bytes calldata, bytes calldata, bytes calldata ctx)
        external
        pure
        returns (bytes memory)
    {
        return ctx;
    }

    function beforeAgreementUpdated(ISuperToken, address, bytes32, bytes calldata, bytes calldata)
        external
        pure
        returns (bytes memory)
    {
        return "";
    }

    function afterAgreementUpdated(ISuperToken, address, bytes32, bytes calldata, bytes calldata, bytes calldata ctx)
        external
        pure
        returns (bytes memory)
    {
        return ctx;
    }

    function beforeAgreementTerminated(ISuperToken, address, bytes32, bytes calldata, bytes calldata)
        external
        view
        returns (bytes memory)
    {
        if (mode == Mode.EncodedBeforeCbdata) return new bytes(payloadSize);
        if (mode == Mode.MaxInnerLength) {
            // Small enough to copy, but the claimed length must be rejected without overflow.
            assembly {
                mstore(0x00, 0x20)
                mstore(0x20, not(0))
                return(0x00, 0x40)
            }
        }
        if (mode == Mode.FatRevertData) {
            _returnOrRevertFat(true);
        }
        if (mode == Mode.FatBeforeCbdata) {
            if (payloadSize == 0) return "";
            _returnOrRevertFat(false);
        }
        return "";
    }

    function afterAgreementTerminated(
        ISuperToken,
        address,
        bytes32,
        bytes calldata,
        bytes calldata cbdata,
        bytes calldata ctx
    ) external returns (bytes memory) {
        if (mode == Mode.FatAfterNewCtx) {
            _returnOrRevertFat(false);
        }
        if (mode == Mode.EncodedBeforeCbdata) {
            receivedCbdataLength = cbdata.length;
            receivedCbdataHash = keccak256(cbdata);
        }
        return ctx;
    }

    /// RETURN/REVERT expands memory to emit payloadSize raw bytes. This keeps payload generation
    /// within the callback stipend so the tests exercise the Host's returndata handling.
    function _returnOrRevertFat(bool doRevert) internal view {
        uint256 n = payloadSize;
        assembly {
            if doRevert { revert(0, n) }
            return(0, n)
        }
    }
}

abstract contract CallbackReturndataTestBase is FoundrySuperfluidTester {
    using SuperTokenV1Library for ISuperToken;

    int96 internal constant FLOW_RATE = 1e9;
    // Execution gas budget for the sender-initiated deleteFlow call.
    uint256 internal constant TERMINATION_GAS_BUDGET = 3_600_000;

    constructor() FoundrySuperfluidTester(3) { }

    function _openFlow(address app) internal {
        _addAccount(app);
        _helperCreateFlow(superToken, alice, app, FLOW_RATE);
        assertEq(superToken.getFlowRate(alice, app), FLOW_RATE, "setup: flow not open");
    }

    function deleteFlowAsAlice(address receiver) external {
        vm.startPrank(alice);
        superToken.deleteFlow(alice, receiver);
        vm.stopPrank();
    }

    function _terminateAtGasBudget(address app) internal {
        (bool ok,) = address(this).call{ gas: TERMINATION_GAS_BUDGET }(abi.encodeCall(this.deleteFlowAsAlice, (app)));
        assertTrue(ok, "termination must fit the gas budget");
        assertEq(superToken.getFlowRate(alice, app), 0, "flow should be closed");
    }

    function _expectJail(address app, uint256 reason) internal {
        vm.expectEmit(true, false, false, true, address(sf.host));
        emit ISuperfluid.Jail(ISuperApp(app), reason);
    }
}

/// @dev All after-hooks share a configurable response. Before-hooks are NOOP.
/// Shrink/Grow call the CFA through callAgreementWithContext to replace userData and obtain
/// an authenticated context. Counters and operator permissions expose rollback behavior.
contract ContextReturnApp is ISuperApp {
    enum Response {
        Echo,
        Shrink,
        Grow,
        Raw,
        Revert,
        InvalidContext,
        ShrinkThenOversize
    }
    ISuperfluid internal immutable _host;
    address public constant OPERATOR = address(0xBEEF);
    Response public response;
    uint256 public size;
    uint256 public calls;
    uint256 public inputCtxLength;
    uint256 public outputCtxLength;

    constructor(ISuperfluid host) {
        _host = host;
        host.registerApp(
            SuperAppDefinitions.APP_LEVEL_FINAL | SuperAppDefinitions.BEFORE_AGREEMENT_CREATED_NOOP
                | SuperAppDefinitions.BEFORE_AGREEMENT_UPDATED_NOOP
                | SuperAppDefinitions.BEFORE_AGREEMENT_TERMINATED_NOOP
        );
    }

    function configure(Response response_, uint256 size_) external {
        response = response_;
        size = size_;
    }

    function _after(ISuperToken token, address agreement, bytes calldata ctx) internal returns (bytes memory newCtx) {
        ++calls;
        inputCtxLength = ctx.length;
        Response r = response;
        newCtx = ctx;
        if (r == Response.Shrink || r == Response.Grow || r == Response.ShrinkThenOversize) {
            IConstantFlowAgreementV1 cfa = IConstantFlowAgreementV1(agreement);
            (newCtx,) = _host.callAgreementWithContext(
                cfa,
                abi.encodeCall(cfa.authorizeFlowOperatorWithFullControl, (token, OPERATOR, new bytes(0))),
                new bytes(r == Response.Grow ? size : 0),
                ctx
            );
        }
        outputCtxLength = newCtx.length;
        if (r == Response.Raw || r == Response.Revert || r == Response.ShrinkThenOversize) {
            // Zero-filled returndata has an invalid ABI bytes offset for every nonempty payload.
            uint256 n = size;
            bool isRevert = r == Response.Revert;
            assembly {
                let p := mload(0x40)
                calldatacopy(p, calldatasize(), n)
                if isRevert { revert(p, n) }
                return(p, n)
            }
        }
        if (r == Response.InvalidContext) return hex"01";
    }

    function beforeAgreementCreated(ISuperToken, address, bytes32, bytes calldata, bytes calldata)
        external
        pure
        returns (bytes memory)
    {
        return "";
    }

    function beforeAgreementUpdated(ISuperToken, address, bytes32, bytes calldata, bytes calldata)
        external
        pure
        returns (bytes memory)
    {
        return "";
    }

    function beforeAgreementTerminated(ISuperToken, address, bytes32, bytes calldata, bytes calldata)
        external
        pure
        returns (bytes memory)
    {
        return "";
    }

    function afterAgreementCreated(
        ISuperToken token,
        address agreement,
        bytes32,
        bytes calldata,
        bytes calldata,
        bytes calldata ctx
    ) external returns (bytes memory) {
        return _after(token, agreement, ctx);
    }

    function afterAgreementUpdated(
        ISuperToken token,
        address agreement,
        bytes32,
        bytes calldata,
        bytes calldata,
        bytes calldata ctx
    ) external returns (bytes memory) {
        return _after(token, agreement, ctx);
    }

    function afterAgreementTerminated(
        ISuperToken token,
        address agreement,
        bytes32,
        bytes calldata,
        bytes calldata,
        bytes calldata ctx
    ) external returns (bytes memory) {
        return _after(token, agreement, ctx);
    }
}
