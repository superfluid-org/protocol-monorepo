// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import { ISuperToken } from "@superfluid-finance/ethereum-contracts/contracts/interfaces/superfluid/ISuperToken.sol";
import { FlowOperatorDefinitions } from "@superfluid-finance/ethereum-contracts/contracts/interfaces/superfluid/ISuperfluid.sol";
import { FlowScheduler } from "./../contracts/FlowScheduler.sol";
import { FlowSchedulerResolver } from "./../contracts/FlowSchedulerResolver.sol";
import { FoundrySuperfluidTester } from "@superfluid-finance/ethereum-contracts/test/foundry/FoundrySuperfluidTester.t.sol";
import { SuperToken } from "@superfluid-finance/ethereum-contracts/contracts/superfluid/SuperToken.sol";
import { SuperTokenV1Library } from "@superfluid-finance/ethereum-contracts/contracts/apps/SuperTokenV1Library.sol";

/// @title FlowSchedulerResolverTests
/// @notice Look at me , I am the captain now - Elvijs
contract FlowSchedulerResolverTest is FoundrySuperfluidTester {
    using SuperTokenV1Library for SuperToken;
    FlowSchedulerResolver internal flowSchedulerResolver;

    bytes4 constant INVALID_CFA_PERMISSIONS_ERROR_SIG = 0xa3eab6ac;
    FlowScheduler internal flowScheduler;

    // setting expected payloads from Gelato
    bytes createPayload;
    bytes deletePayload;

    constructor() FoundrySuperfluidTester(3) {}

    function setUp() override public virtual {
        super.setUp();
        flowScheduler = new FlowScheduler(sf.host);
        flowSchedulerResolver = new FlowSchedulerResolver(address(flowScheduler));
        createPayload = abi.encodeCall( FlowScheduler.executeCreateFlow,
            (
                ISuperToken(superToken),
                alice,
                bob,
                "" // not supporting user data until encoding challenges are solved
            )
        );

        deletePayload = abi.encodeCall( FlowScheduler.executeDeleteFlow,
            (
                ISuperToken(superToken),
                alice,
                bob,
                "" // not supporting user data until encoding challenges are solved
            )
        );
    }

    /// @dev expect payload to be empty and non-executable
    function expectUnexecutable() public {
        // Expect canExec to be false
        (bool canExec, bytes memory execPayload) = flowSchedulerResolver.checker(address(superToken), alice, bob);
        assertTrue(!canExec, "canExec - executable when it shouldn't have been");

        // And expect payload to not be executable
        (bool status, ) = address(flowScheduler).call(execPayload);
        assertTrue(!status, "status - unexpected success");
    }

    /// @dev expect payload to the expected and successfully executable
    function expectExecutable(bytes memory expectedPayload) public {
        // Expect canExec to be true
        (bool canExec, bytes memory execPayload) = flowSchedulerResolver.checker(address(superToken), alice, bob);
        assertTrue(canExec, "canExec - not executable when it should have been");
        assertEq(execPayload, expectedPayload, "wrong payload");

        // And expect payload to be executable
        (bool status, ) = address(flowScheduler).call(execPayload);
        assertTrue(status, "status - unexpected failure");
    }

    /// @dev Constants for Testing
    uint32 internal defaultStartDate = uint32(block.timestamp + 1);
    int96 defaultFlowRate = int96(1000);
    uint32 defaultStartMaxDelay = uint32(60);
    uint256 defaultStartAmount = 500;

    function testCreateSchedule() public {
        vm.prank(alice);

        uint32 defaultEndDate = defaultStartDate + uint32(3600);

        flowScheduler.createFlowSchedule(
            superToken,
            bob,
            defaultStartDate,
            defaultStartMaxDelay,
            defaultFlowRate,
            defaultStartAmount,
            defaultEndDate,
            "",
            ""
        );

        // shouldn't be given executable payload before defaultStartDate is reached
        (bool canExec, bytes memory execPayload) = flowSchedulerResolver.checker(address(superToken), alice, bob);
        assertTrue(!canExec);
        assertEq("0x", execPayload);
    }

    function testStartStreamWithIncorrectPermissions() public {
        vm.startPrank(alice);

        uint32 defaultEndDate = defaultStartDate + uint32(3600);

        flowScheduler.createFlowSchedule(
            superToken,
            bob,
            defaultStartDate,
            defaultStartMaxDelay,
            defaultFlowRate,
            defaultStartAmount,
            defaultEndDate,
            "",
            ""
        );

        // Give ERC20 approval to scheduler
        superToken.approve(address(flowScheduler), type(uint256).max);

        vm.stopPrank();
        vm.startPrank(admin);

        // -- Shouldn't be executable with no permissions

        // Advance time past defaultStartDate and before defaultStartDate + defaultStartMaxDelay
        vm.warp(defaultStartDate + defaultStartMaxDelay - defaultStartMaxDelay/2 );

        expectUnexecutable();

        vm.stopPrank();
        vm.startPrank(alice);

        // -- Shouldn't be executable with incorrect permissions

        // Give only create permissions to scheduler
        sf.host.callAgreement(
            sf.cfa,
            abi.encodeCall(
                sf.cfa.updateFlowOperatorPermissions,
                (
                    superToken,
                    address(flowScheduler),
                    FlowOperatorDefinitions.AUTHORIZE_FLOW_OPERATOR_CREATE, // not 5 or 7
                    type(int96).max,
                    new bytes(0)
                )
            ),
            new bytes(0)
        );

        vm.stopPrank();
        vm.startPrank(admin);
        // Advance time past defaultStartDate and before defaultStartDate + defaultStartMaxDelay
        vm.warp(defaultStartDate +
         defaultStartMaxDelay - defaultStartMaxDelay/2 );

        expectUnexecutable();
    }

    function testStartStreamWithTooLittleRateAllowance() public {
        vm.startPrank(alice);

        uint32 defaultEndDate = defaultStartDate + uint32(3600);

        flowScheduler.createFlowSchedule(
            superToken,
            bob,
            defaultStartDate,
            defaultStartMaxDelay,
            defaultFlowRate,
            defaultStartAmount,
            defaultEndDate,
            "",
            ""
        );

        // Give ERC20 approval to scheduler
        superToken.approve(address(flowScheduler), type(uint256).max);

        // Give to little permissions to scheduler
        sf.host.callAgreement(
            sf.cfa,
            abi.encodeCall(
                sf.cfa.updateFlowOperatorPermissions,
                (
                    superToken,
                    address(flowScheduler),
                    FlowOperatorDefinitions.AUTHORIZE_FULL_CONTROL,
                    defaultFlowRate - 1, // rate allowed is below what's needed
                    new bytes(0)
                )
            ),
            new bytes(0)
        );

        vm.stopPrank();
        vm.startPrank(admin);

        // Advance time past defaultStartDate and before defaultStartDate + defaultStartMaxDelay
        vm.warp(defaultStartDate + defaultStartMaxDelay - defaultStartMaxDelay/2 );

        expectUnexecutable();
    }

    function testStartStreamPastMaxDelay() public {
        vm.startPrank(alice);

        uint32 defaultEndDate = defaultStartDate + uint32(3600);

        flowScheduler.createFlowSchedule(
            superToken,
            bob,
            defaultStartDate,
            defaultStartMaxDelay,
            defaultFlowRate,
            defaultStartAmount,
            defaultEndDate,
            "",
            ""
        );

        // Give ERC20 approval to scheduler
        superToken.approve(address(flowScheduler), type(uint256).max);

        // Give full flow permissions to scheduler
        sf.host.callAgreement(
            sf.cfa,
            abi.encodeCall(
                sf.cfa.updateFlowOperatorPermissions,
                (
                    superToken,
                    address(flowScheduler),
                    FlowOperatorDefinitions.AUTHORIZE_FULL_CONTROL,
                    type(int96).max,
                    new bytes(0)
                )
            ),
            new bytes(0)
        );

        vm.stopPrank();
        vm.startPrank(admin);

        // -- Shouldn't be given executable payload if defaultStartDate + defaultStartMaxDelay has been passed

        // Advance time past defaultStartDate + defaultStartMaxDelay
        vm.warp(defaultStartDate + defaultStartMaxDelay + defaultStartMaxDelay/2 );

        expectUnexecutable();
    }

    function testStartStreamBeforeMaxDelay() public {
        vm.startPrank(alice);

        uint32 defaultEndDate = defaultStartDate + uint32(3600);

        flowScheduler.createFlowSchedule(
            superToken,
            bob,
            defaultStartDate,
            defaultStartMaxDelay,
            defaultFlowRate,
            defaultStartAmount,
            defaultEndDate,
            "",
            ""
        );

        // Give ERC20 approval to scheduler
        superToken.approve(address(flowScheduler), type(uint256).max);

        // Give full flow permissions to scheduler
        sf.host.callAgreement(
            sf.cfa,
            abi.encodeCall(
                sf.cfa.updateFlowOperatorPermissions,
                (
                    superToken,
                    address(flowScheduler),
                    FlowOperatorDefinitions.AUTHORIZE_FULL_CONTROL,
                    type(int96).max,
                    new bytes(0)
                )
            ),
            new bytes(0)
        );

        vm.stopPrank();
        vm.startPrank(admin);

        // -- Should be given executable payload if defaultStartDate has been passed but
        // defaultStartDate + defaultStartMaxDelay has not

        // Rewind time to before defaultStartDate + defaultStartMaxDelay
        vm.warp(defaultStartDate + defaultStartMaxDelay - defaultStartMaxDelay/2 );

        expectExecutable(createPayload);
    }

    function testDeleteStreamBeforeEndDate() public {
        vm.startPrank(alice);

        uint32 defaultEndDate = defaultStartDate + uint32(3600);

        flowScheduler.createFlowSchedule(
            superToken,
            bob,
            defaultStartDate,
            defaultStartMaxDelay,
            defaultFlowRate,
            defaultStartAmount,
            defaultEndDate,
            "",
            ""
        );

        // Give ERC20 approval to scheduler
        superToken.approve(address(flowScheduler), type(uint256).max);

        // Give full flow permissions to scheduler
        sf.host.callAgreement(
            sf.cfa,
            abi.encodeCall(
                sf.cfa.updateFlowOperatorPermissions,
                (
                    superToken,
                    address(flowScheduler),
                    FlowOperatorDefinitions.AUTHORIZE_FULL_CONTROL,
                    type(int96).max,
                    new bytes(0)
                )
            ),
            new bytes(0)
        );

        vm.stopPrank();
        vm.startPrank(admin);

        // create the stream
        vm.warp(defaultStartDate + defaultStartMaxDelay/2);
        expectExecutable(createPayload);

        // -- Should not give delete flow payload if defaultEndDate has not been passed

        // Move time to before defaultEndDate
        vm.warp(defaultEndDate - 1);

        expectUnexecutable();
    }

    function testDeleteNonExistantStreamAfterEndDate() public {
        vm.startPrank(alice);

        uint32 defaultEndDate = defaultStartDate + uint32(3600);

        flowScheduler.createFlowSchedule(
            superToken,
            bob,
            defaultStartDate,
            defaultStartMaxDelay,
            defaultFlowRate,
            defaultStartAmount,
            defaultEndDate,
            "",
            ""
        );

        // Give ERC20 approval to scheduler
        superToken.approve(address(flowScheduler), type(uint256).max);

        // Give full flow permissions to scheduler
        sf.host.callAgreement(
            sf.cfa,
            abi.encodeCall(
                sf.cfa.updateFlowOperatorPermissions,
                (
                    superToken,
                    address(flowScheduler),
                    FlowOperatorDefinitions.AUTHORIZE_FULL_CONTROL,
                    type(int96).max,
                    new bytes(0)
                )
            ),
            new bytes(0)
        );

        vm.stopPrank();
        vm.startPrank(admin);

        // -- Should not give delete flow payload if stream to delete does not exist in the first place

        // Move time to defaultEndDate
        vm.warp(defaultEndDate);

        expectUnexecutable();
    }

    function testDeleteStreamAfterEndDate() public {
        vm.startPrank(alice);

        uint32 defaultEndDate = defaultStartDate + uint32(3600);

        flowScheduler.createFlowSchedule(
            superToken,
            bob,
            defaultStartDate,
            defaultStartMaxDelay,
            defaultFlowRate,
            defaultStartAmount,
            defaultEndDate,
            "",
            ""
        );

        // Give ERC20 approval to scheduler
        superToken.approve(address(flowScheduler), type(uint256).max);

        // Give full flow permissions to scheduler
        sf.host.callAgreement(
            sf.cfa,
            abi.encodeCall(
                sf.cfa.updateFlowOperatorPermissions,
                (
                    superToken,
                    address(flowScheduler),
                    FlowOperatorDefinitions.AUTHORIZE_FULL_CONTROL,
                    type(int96).max,
                    new bytes(0)
                )
            ),
            new bytes(0)
        );

        vm.stopPrank();
        vm.startPrank(admin);

        // create the stream
        vm.warp(defaultStartDate + defaultStartMaxDelay/2);
        expectExecutable(createPayload);

        // -- Should give delete flow payload as we've passed defaultEndDate

        // Move time to defaultEndDate
        vm.warp(defaultEndDate);

        expectExecutable(deletePayload);
    }

}
