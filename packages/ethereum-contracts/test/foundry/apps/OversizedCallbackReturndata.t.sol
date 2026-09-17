// SPDX-License-Identifier: AGPLv3
pragma solidity ^0.8.23;

import { CallbackReturndataTestBase, TerminationReturndataBombApp } from "./CallbackReturndataTestBase.t.sol";
import { ISuperApp, SuperAppDefinitions } from "../../../contracts/interfaces/superfluid/ISuperfluid.sol";

/// @dev Termination with a 3.6M execution gas budget. Each app either returns or reverts with
///      1,000,000 bytes, exceeding the 128 KiB returndata cap. The Host discards the payload,
///      jails the app under the applicable callback rule, and completes deletion of the flow.
contract OversizedCallbackReturndataTest is CallbackReturndataTestBase {
    /// Raw payload emitted within the 3M callback stipend; exceeds the 128 KiB returndata cap.
    uint256 internal constant FAT_PAYLOAD_SIZE = 1_000_000;

    function test_honestTerminate_succeedsAtGasBudget() public {
        TerminationReturndataBombApp app =
            new TerminationReturndataBombApp(sf.host, TerminationReturndataBombApp.Mode.FatBeforeCbdata, 0);
        _openFlow(address(app));
        _terminateAtGasBudget(address(app));
        assertFalse(sf.host.isAppJailed(ISuperApp(address(app))), "honest app must not be jailed");
    }

    function test_fatBeforeCbdata_terminateJailsAndClosesFlow() public {
        TerminationReturndataBombApp app = new TerminationReturndataBombApp(
            sf.host, TerminationReturndataBombApp.Mode.FatBeforeCbdata, FAT_PAYLOAD_SIZE
        );
        _openFlow(address(app));
        _assertTerminateJailsAndCloses(address(app), SuperAppDefinitions.APP_RULE_CTX_IS_MALFORMATED);
    }

    function test_fatAfterNewCtx_terminateJailsAndClosesFlow() public {
        TerminationReturndataBombApp app = new TerminationReturndataBombApp(
            sf.host, TerminationReturndataBombApp.Mode.FatAfterNewCtx, FAT_PAYLOAD_SIZE
        );
        _openFlow(address(app));
        _assertTerminateJailsAndCloses(address(app), SuperAppDefinitions.APP_RULE_CTX_IS_MALFORMATED);
    }

    function test_fatRevertData_terminateJailsAndClosesFlow() public {
        TerminationReturndataBombApp app = new TerminationReturndataBombApp(
            sf.host, TerminationReturndataBombApp.Mode.FatRevertData, FAT_PAYLOAD_SIZE
        );
        _openFlow(address(app));
        _assertTerminateJailsAndCloses(address(app), SuperAppDefinitions.APP_RULE_NO_REVERT_ON_TERMINATION_CALLBACK);
    }

    function _assertTerminateJailsAndCloses(address app, uint256 reason) internal {
        _expectJail(app, reason);
        _terminateAtGasBudget(app);
        assertTrue(sf.host.isAppJailed(ISuperApp(app)), "app should be jailed");
    }
}
