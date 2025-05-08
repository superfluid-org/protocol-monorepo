// SPDX-License-Identifier: AGPLv3
pragma solidity ^0.8.23;

import { console } from "forge-std/Test.sol";
import { FoundrySuperfluidTester, SuperTokenV1Library } from "../FoundrySuperfluidTester.t.sol";
import { ISuperToken } from "../../../contracts/superfluid/SuperToken.sol";

contract ConstantFlowAgreementV1IntegrationTest is FoundrySuperfluidTester {
    using SuperTokenV1Library for ISuperToken;

    constructor() FoundrySuperfluidTester(3) { }

    function testAlice2Bob(int96 flowRate) public {
        _helperCreateFlow(superToken, alice, bob, flowRate);

        _warpAndAssertAll(superToken);
    }

    function testBobAliceLoop(int96 flowRate) public {
        _helperCreateFlow(superToken, alice, bob, flowRate);

        _warpAndAssertAll(superToken);

        _helperCreateFlow(superToken, bob, alice, flowRate);

        _warpAndAssertAll(superToken);
    }

    // helper functions wrapping internal calls into external calls (needed for try/catch)

    function __external_createFlow(ISuperToken superToken, address sender, address receiver, int96 fr) external {
        vm.startPrank(sender);
        superToken.createFlow(receiver, fr);
        vm.stopPrank();
    }

    function __external_updateFlow(ISuperToken superToken, address sender, address receiver, int96 fr) external {
        vm.startPrank(sender);
        superToken.updateFlow(receiver, fr);
        vm.stopPrank();
    }

    function __external_deleteFlow(ISuperToken superToken, address sender, address receiver) external {
        vm.startPrank(sender);
        superToken.deleteFlow(sender, receiver);
        vm.stopPrank();
    }
}
