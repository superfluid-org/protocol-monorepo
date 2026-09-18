// SPDX-License-Identifier: AGPLv3
pragma solidity ^0.8.23;

import {
    CallbackReturndataTestBase,
    TerminationReturndataBombApp,
    ContextReturnApp
} from "../apps/CallbackReturndataTestBase.t.sol";
import {
    ISuperfluid,
    ISuperApp,
    ISuperToken,
    SuperAppDefinitions
} from "../../../contracts/interfaces/superfluid/ISuperfluid.sol";
import { SuperTokenV1Library } from "../../../contracts/apps/SuperTokenV1Library.sol";
import { CallbackUtils } from "../../../contracts/libs/CallbackUtils.sol";

/// @dev Before-hook cbdata validation and round-trip tests. The returndata cap applies to ABI-encoded cbdata.
contract CallbackReturnSizeGriefTest is CallbackReturndataTestBase {
    using SuperTokenV1Library for ISuperToken;

    // A 200 KiB payload exceeds the 128 KiB returndata cap and can be encoded within the 3M callback stipend.
    uint256 internal constant BOMB_SIZE = 200 * 1024;

    function test_terminateCallback_smallReturn_doesNotJail() public {
        _assertAcceptedCbdata(32);
    }

    function test_terminateCallback_returnAtCap_roundtripsAtGasBudget() public {
        // Offset and length words occupy 64 bytes; this payload is word-aligned.
        _assertAcceptedCbdata(CallbackUtils.CALLBACK_RETURNDATA_CAP - 64);
    }

    function _assertAcceptedCbdata(uint256 size) internal {
        TerminationReturndataBombApp app =
            new TerminationReturndataBombApp(sf.host, TerminationReturndataBombApp.Mode.EncodedBeforeCbdata, size);
        _openFlow(address(app));
        _terminateAtGasBudget(address(app));
        assertFalse(sf.host.isAppJailed(ISuperApp(address(app))));
        assertEq(app.receivedCbdataLength(), size, "after callback must receive the entire inner payload");
        assertEq(app.receivedCbdataHash(), keccak256(new bytes(size)), "cbdata must survive downstream encoding");
    }

    function test_terminateCallback_oversizedReturn_operatorDeleteJails() public {
        _assertOperatorDeleteJails(TerminationReturndataBombApp.Mode.EncodedBeforeCbdata, BOMB_SIZE);
    }

    function test_terminateCallback_maxInnerLength_operatorDeleteJails() public {
        _assertOperatorDeleteJails(TerminationReturndataBombApp.Mode.MaxInnerLength, 0);
    }

    function test_contextAboveLimit_beforeOnly_revertsWithoutJail() public {
        TerminationReturndataBombApp app =
            new TerminationReturndataBombApp(sf.host, TerminationReturndataBombApp.Mode.FatBeforeCbdata, 0);
        _openFlow(address(app));

        vm.expectRevert(ISuperfluid.HOST_CALLBACK_CONTEXT_TOO_LARGE.selector);
        vm.prank(alice);
        superToken.deleteFlow(alice, address(app), new bytes(CallbackUtils.CALLBACK_CONTEXT_CAP - 479));
        assertFalse(sf.host.isAppJailed(ISuperApp(address(app))));
        assertEq(superToken.getFlowRate(alice, address(app)), FLOW_RATE);

        vm.prank(alice);
        superToken.deleteFlow(alice, address(app));
        assertEq(superToken.getFlowRate(alice, address(app)), 0, "retry must close the flow");
    }

    function test_contextAtLimit_beforeOnly_succeeds() public {
        TerminationReturndataBombApp app =
            new TerminationReturndataBombApp(sf.host, TerminationReturndataBombApp.Mode.FatBeforeCbdata, 0);
        _openFlow(address(app));
        vm.expectCall(address(app), abi.encodeWithSelector(ISuperApp.beforeAgreementTerminated.selector));
        vm.prank(alice);
        superToken.deleteFlow(alice, address(app), new bytes(CallbackUtils.CALLBACK_CONTEXT_CAP - 480));
        assertFalse(sf.host.isAppJailed(ISuperApp(address(app))));
        assertEq(superToken.getFlowRate(alice, address(app)), 0);
    }

    function test_allCallbacksNoop_contextAboveLimit_succeeds() public {
        TerminationReturndataBombApp app =
            new TerminationReturndataBombApp(sf.host, TerminationReturndataBombApp.Mode.AllNoop, 0);
        _openFlow(address(app));
        vm.prank(alice);
        superToken.deleteFlow(alice, address(app), new bytes(CallbackUtils.CALLBACK_RETURNDATA_CAP));
        assertFalse(sf.host.isAppJailed(ISuperApp(address(app))));
        assertEq(superToken.getFlowRate(alice, address(app)), 0);
    }

    /// A transfer between non-app accounts accepts 128 KiB of userData without invoking callbacks.
    function test_eoaToEoa_fatUserData_succeeds() public {
        _helperCreateFlow(superToken, alice, bob, FLOW_RATE);
        vm.prank(alice);
        superToken.deleteFlow(alice, bob, new bytes(CallbackUtils.CALLBACK_RETURNDATA_CAP));
        assertEq(superToken.getFlowRate(alice, bob), 0);
    }

    function _assertOperatorDeleteJails(TerminationReturndataBombApp.Mode mode, uint256 size) internal {
        TerminationReturndataBombApp app = new TerminationReturndataBombApp(sf.host, mode, size);
        _openFlow(address(app));
        vm.startPrank(alice);
        superToken.setMaxFlowPermissions(bob);
        vm.stopPrank();

        _expectJail(address(app), SuperAppDefinitions.APP_RULE_CTX_IS_MALFORMATED);
        vm.startPrank(bob);
        superToken.deleteFlow(alice, address(app));
        vm.stopPrank();

        assertTrue(sf.host.isAppJailed(ISuperApp(address(app))));
        assertEq(superToken.getFlowRate(alice, address(app)), 0);
    }
}

/// @dev Callback context and returndata boundaries.
/// Before invoking a callback, the Host requires ctx.length <= CALLBACK_CONTEXT_CAP (32 KiB).
/// Returned ABI-encoded bytes are limited to C = CALLBACK_RETURNDATA_CAP (128 KiB), including
/// the offset, length word and payload padding.
/// Exceeding the input bound reverts HOST_CALLBACK_CONTEXT_TOO_LARGE without invoking the hook.
/// The operation rolls back without jailing, and the caller can retry with smaller userData.
///
/// For input within the bound, after-hook results are handled as follows:
/// - Authenticated ctx with ABI-encoded size <= C: accept.
/// - Malformed ABI or returndata > C: APP_RULE_CTX_IS_MALFORMATED (22).
/// - Well-encoded ctx with invalid authentication stamp: APP_RULE_CTX_IS_READONLY (20).
/// - Callback revert: APP_RULE_NO_REVERT_ON_TERMINATION_CALLBACK (10) on termination;
///   creation/update propagate the revert.
/// Rules 22 and 20 jail and continue termination; creation/update revert APP_RULE.
/// Caller gas starvation reverts HOST_NEED_MORE_GAS and is tested in CallbackUtilsTest.
/// Before-only, all-NOOP, and non-app paths are covered in CallbackReturnSizeGriefTest.
contract AfterCallbackReturndataTest is CallbackReturndataTestBase {
    using SuperTokenV1Library for ISuperToken;

    // Encoded context has 480 bytes of overhead in addition to padded userData.
    uint256 internal constant USER_DATA_AT_CAP = CallbackUtils.CALLBACK_CONTEXT_CAP - 480;

    function test_contextAtLimit_succeeds() public {
        _assertEcho(USER_DATA_AT_CAP);
    }

    function test_contextAtLimit_unalignedUserData_succeeds() public {
        _assertEcho(USER_DATA_AT_CAP - 1);
    }

    function test_contextOneByteAboveLimit_revertsAndCanRetry() public {
        ContextReturnApp app = _app();
        _assertHostRevert(app, USER_DATA_AT_CAP + 1);
        _delete(app, 0);
        _assertClosed(app, false);
    }

    /// forge-config: default.fuzz.runs = 32
    /// forge-config: ci.fuzz.runs = 32
    function testFuzz_contextAboveLimit_rejectedForEveryResponse(uint8 response, uint256 excess) public {
        ContextReturnApp app = _app();
        app.configure(
            ContextReturnApp.Response(bound(response, 0, uint8(ContextReturnApp.Response.InvalidContext))),
            CallbackUtils.CALLBACK_RETURNDATA_CAP + 1
        );
        _assertHostRevert(app, USER_DATA_AT_CAP + bound(excess, 1, 1024));
    }

    function test_emptyReturndata_jails() public {
        _assertRawViolation(0);
    }

    function test_malformedReturndataAtCap_jails() public {
        _assertRawViolation(CallbackUtils.CALLBACK_RETURNDATA_CAP);
    }

    function test_returndataAboveCap_jails() public {
        _assertRawViolation(CallbackUtils.CALLBACK_RETURNDATA_CAP + 1);
    }

    function test_invalidContext_jails() public {
        ContextReturnApp app = _app();
        app.configure(ContextReturnApp.Response.InvalidContext, 0);
        _assertViolation(app, SuperAppDefinitions.APP_RULE_CTX_IS_READONLY);
    }

    function test_callbackRevert_jails() public {
        _assertRevertViolation(0);
    }

    function test_revertDataAboveCap_jails() public {
        _assertRevertViolation(CallbackUtils.CALLBACK_RETURNDATA_CAP + 1);
    }

    function test_createAndUpdate_contextAboveLimit_revertWithoutJail() public {
        ContextReturnApp app = new ContextReturnApp(sf.host);
        _addAccount(address(app));
        vm.expectRevert(ISuperfluid.HOST_CALLBACK_CONTEXT_TOO_LARGE.selector);
        _change(app, false, USER_DATA_AT_CAP + 1);
        assertEq(superToken.getFlowRate(alice, address(app)), 0);
        _change(app, false, 0);
        uint256 callsBefore = app.calls();
        vm.expectRevert(ISuperfluid.HOST_CALLBACK_CONTEXT_TOO_LARGE.selector);
        _change(app, true, USER_DATA_AT_CAP + 1);
        assertEq(superToken.getFlowRate(alice, address(app)), FLOW_RATE);
        assertEq(app.calls(), callsBefore);
        assertFalse(sf.host.isAppJailed(ISuperApp(address(app))));
    }

    function test_createAndUpdate_malformedResponse_revertsAppRule() public {
        ContextReturnApp app = new ContextReturnApp(sf.host);
        _addAccount(address(app));
        app.configure(ContextReturnApp.Response.Raw, 0);
        bytes memory reason =
            abi.encodeWithSelector(ISuperfluid.APP_RULE.selector, SuperAppDefinitions.APP_RULE_CTX_IS_MALFORMATED);
        vm.expectRevert(reason);
        _change(app, false, 0);
        app.configure(ContextReturnApp.Response.Echo, 0);
        _change(app, false, 0);
        app.configure(ContextReturnApp.Response.Raw, 0);
        vm.expectRevert(reason);
        _change(app, true, 0);
        assertEq(superToken.getFlowRate(alice, address(app)), FLOW_RATE);
        assertFalse(sf.host.isAppJailed(ISuperApp(address(app))));
    }

    function _app() internal returns (ContextReturnApp app) {
        app = new ContextReturnApp(sf.host);
        _openFlow(address(app));
    }

    function _assertEcho(uint256 userDataSize) internal {
        ContextReturnApp app = _app();
        _delete(app, userDataSize);
        _assertClosed(app, false);
        assertEq(app.inputCtxLength(), CallbackUtils.CALLBACK_CONTEXT_CAP);
    }

    function _assertHostRevert(ContextReturnApp app, uint256 userDataSize) internal {
        uint256 callsBefore = app.calls();
        vm.expectRevert(ISuperfluid.HOST_CALLBACK_CONTEXT_TOO_LARGE.selector);
        _delete(app, userDataSize);
        assertEq(superToken.getFlowRate(alice, address(app)), FLOW_RATE, "flow must survive rejection");
        assertFalse(sf.host.isAppJailed(ISuperApp(address(app))), "Host error must not jail");
        assertEq(app.calls(), callsBefore, "callback state must be unchanged");
    }

    function _assertRawViolation(uint256 rawSize) internal {
        ContextReturnApp app = _app();
        app.configure(ContextReturnApp.Response.Raw, rawSize);
        _assertViolation(app, SuperAppDefinitions.APP_RULE_CTX_IS_MALFORMATED);
    }

    function _assertRevertViolation(uint256 size) internal {
        ContextReturnApp app = _app();
        app.configure(ContextReturnApp.Response.Revert, size);
        _assertViolation(app, SuperAppDefinitions.APP_RULE_NO_REVERT_ON_TERMINATION_CALLBACK);
    }

    function _assertViolation(ContextReturnApp app, uint256 rule) internal {
        _expectJail(address(app), rule);
        _delete(app, USER_DATA_AT_CAP);
        _assertClosed(app, true);
    }

    function _assertClosed(ContextReturnApp app, bool jailed) internal view {
        assertEq(superToken.getFlowRate(alice, address(app)), 0);
        assertEq(sf.host.isAppJailed(ISuperApp(address(app))), jailed);
    }

    function _delete(ContextReturnApp app, uint256 userDataSize) internal {
        vm.prank(alice);
        sf.host
            .callAgreement(
                sf.cfa,
                abi.encodeCall(sf.cfa.deleteFlow, (superToken, alice, address(app), new bytes(0))),
                new bytes(userDataSize)
            );
    }

    function _change(ContextReturnApp app, bool update, uint256 userDataSize) internal {
        bytes memory callData = update
            ? abi.encodeCall(sf.cfa.updateFlow, (superToken, address(app), FLOW_RATE * 2, new bytes(0)))
            : abi.encodeCall(sf.cfa.createFlow, (superToken, address(app), FLOW_RATE, new bytes(0)));
        vm.prank(alice);
        sf.host.callAgreement(sf.cfa, callData, new bytes(userDataSize));
    }
}
