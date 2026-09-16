// SPDX-License-Identifier: AGPLv3
pragma solidity ^0.8.23;

import { CallbackReturndataTestBase, TerminationReturndataBombApp } from "../apps/CallbackReturndataTestBase.t.sol";
import { ISuperApp, ISuperToken, SuperAppDefinitions } from "../../../contracts/interfaces/superfluid/ISuperfluid.sol";
import { SuperTokenV1Library } from "../../../contracts/apps/SuperTokenV1Library.sol";
import { CallbackUtils } from "../../../contracts/libs/CallbackUtils.sol";

contract CallbackReturnSizeGriefTest is CallbackReturndataTestBase {
    using SuperTokenV1Library for ISuperToken;

    // Above the cap, while ABI encoding still fits in the 3M callback stipend.
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
