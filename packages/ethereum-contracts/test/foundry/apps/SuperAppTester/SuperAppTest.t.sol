// SPDX-License-Identifier: AGPLv3
pragma solidity ^0.8.23;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "../../FoundrySuperfluidTester.t.sol";
import { ISuperApp, ISuperfluid } from "../../../../contracts/interfaces/superfluid/ISuperfluid.sol";

import { Handler } from "./handlers/Handler.sol";

// app to be tested
import { FlowSplitter } from "./FlowSplitter.sol";

abstract contract SuperAppInvariants is Test {
    ISuperfluid public host;
    ISuperApp public superApp;
    Handler public handler; // Focus test to a set of operations

    function invariant_AppNeverJailed() external view InitializeTests {
        assertTrue(!host.isAppJailed(superApp));
    }

    function invariant_AppRegistered() external view InitializeTests {
        assertTrue(host.isApp(superApp));
    }

    function invariant_print() public view {
        handler.printCounters();
    }

    modifier InitializeTests() {
        if (address(superApp) == address(0)) revert("SuperAppTesterBase: no super app set");
        if (address(host) == address(0)) revert("SuperAppTesterBase: no host set");
        _;
    }
}

contract SuperAppTest is FoundrySuperfluidTester(10), SuperAppInvariants {
    int96 public constant MIN_FLOW_RATE = 1000;
    int96 public constant MAX_FLOW_RATE = (type(int96).max) >> 14;

    function setUp() public override {
        super.setUp();
        host = sf.host;
        // create super app
        superApp = ISuperApp(
            address(
                new FlowSplitter(
                address(0x51),
                address(0x52),
                300,
                superToken,
                sf.host
                )
            )
        );

        handler = new Handler(address(superApp), superToken, 1000, 0);
        // we only care about handler interactions
        targetContract(address(handler));
        // we only care about create, update, delete flow
        bytes4[] memory selectors = new bytes4[](3);
        selectors[0] = handler.createFlow.selector;
        selectors[1] = handler.updateFlow.selector;
        selectors[2] = handler.deleteFlow.selector;
        targetSelector(FuzzSelector({ addr: address(handler), selectors: selectors }));
        // we only care about tester accounts
        for (uint256 i = 0; i < TEST_ACCOUNTS.length; i++) {
            targetSender(TEST_ACCOUNTS[i]);
        }
    }
}
