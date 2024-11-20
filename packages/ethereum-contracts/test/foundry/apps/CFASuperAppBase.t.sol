// SPDX-License-Identifier: AGPLv3
pragma solidity ^0.8.23;

import "forge-std/console.sol";

import "../FoundrySuperfluidTester.t.sol";

import {
    ISuperToken,
    ISuperApp,
    SuperAppDefinitions
} from "../../../contracts/interfaces/superfluid/ISuperfluid.sol";
import { IConstantFlowAgreementV1 } from "../../../contracts/interfaces/agreements/IConstantFlowAgreementV1.sol";
import { SuperTokenV1Library } from "../../../contracts/apps/SuperTokenV1Library.sol";
import { CFASuperAppBase } from "../../../contracts/apps/CFASuperAppBase.sol";

import { CFASuperAppBaseTester } from "./CFASuperAppBaseTester.t.sol";

contract CFASuperAppBaseTest is FoundrySuperfluidTester {
    using SuperTokenV1Library for SuperToken;
    using SuperTokenV1Library for ISuperToken;

    CFASuperAppBaseTester superApp;
    address superAppAddress;
    ISuperToken otherSuperToken;

    constructor() FoundrySuperfluidTester(3) { }

    function setUp() public virtual override {
        super.setUp();
        vm.startPrank(admin);
        superApp = new CFASuperAppBaseTester(sf.host);
        superApp.selfRegister(true, true, true);
        superAppAddress = address(superApp);
        otherSuperToken = sfDeployer.deployPureSuperToken("FTT", "FTT", 1e27);
        otherSuperToken.transfer(alice, 1e21);
        vm.stopPrank();
    }

    function _genManifest(bool activateOnCreated, bool activateOnUpdated, bool activateOnDeleted)
        internal
        pure
        returns (uint256)
    {
        uint256 callBackDefinitions =
            SuperAppDefinitions.APP_LEVEL_FINAL | SuperAppDefinitions.BEFORE_AGREEMENT_CREATED_NOOP;

        if (!activateOnCreated) {
            callBackDefinitions |= SuperAppDefinitions.AFTER_AGREEMENT_CREATED_NOOP;
        }

        if (!activateOnUpdated) {
            callBackDefinitions |=
                SuperAppDefinitions.BEFORE_AGREEMENT_UPDATED_NOOP | SuperAppDefinitions.AFTER_AGREEMENT_UPDATED_NOOP;
        }

        if (!activateOnDeleted) {
            callBackDefinitions |= SuperAppDefinitions.BEFORE_AGREEMENT_TERMINATED_NOOP
                | SuperAppDefinitions.AFTER_AGREEMENT_TERMINATED_NOOP;
        }

        return callBackDefinitions;
    }

    function _deploySuperAppAndGetConfig(bool activateOnCreated, bool activateOnUpdated, bool activateOnDeleted)
        internal
        returns (CFASuperAppBaseTester, uint256 configWord)
    {
        CFASuperAppBaseTester mySuperApp = new CFASuperAppBaseTester(sf.host);
        mySuperApp.selfRegister(activateOnCreated, activateOnUpdated, activateOnDeleted);
        uint256 appConfig = _genManifest(activateOnCreated, activateOnUpdated, activateOnDeleted);
        return (mySuperApp, appConfig);
    }

    function testOnFlagsSetAppManifest(bool activateOnCreated, bool activateOnUpdated, bool activateOnDeleted) public {
        //all onOperations
        (CFASuperAppBaseTester mySuperApp, uint256 configWord) =
            _deploySuperAppAndGetConfig(activateOnCreated, activateOnUpdated, activateOnDeleted);

        (bool isSuperApp,, uint256 noopMask) = sf.host.getAppManifest(ISuperApp(mySuperApp));
        configWord = configWord & SuperAppDefinitions.AGREEMENT_CALLBACK_NOOP_BITMASKS;
        assertTrue(isSuperApp, "SuperAppBase: is superApp incorrect");
        assertEq(noopMask, configWord, "SuperAppBase: noopMask != configWord");
    }

    function testRegistrationByFactory(bool activateOnCreated, bool activateOnUpdated, bool activateOnDeleted) public {
        CFASuperAppBaseTester mySuperApp = new CFASuperAppBaseTester(sf.host);
        sf.host.registerApp(
            mySuperApp,
            mySuperApp.getConfigWord(activateOnCreated, activateOnUpdated, activateOnDeleted)
        );
        (bool isSuperApp,,) = sf.host.getAppManifest(ISuperApp(mySuperApp));
        assertTrue(isSuperApp, "SuperAppBase: is superApp incorrect");
    }

    function testAllowAllSuperTokensByDefault() public view {
        assertTrue(
            superApp.isAcceptedSuperToken(superToken), "SuperAppBase: unrestricted | primary SuperToken accepted"
        );
        assertTrue(
            superApp.isAcceptedSuperToken(otherSuperToken), "SuperAppBase: unrestricted | other SuperToken accepted"
        );
    }

    function testRestrictAllowedSuperTokens() public {
        // Using the setter activates the filter, ONLY this token shall be accepted now
        superApp.setAcceptedSuperToken(superToken, true);
        assertTrue(superApp.isAcceptedSuperToken(superToken), "SuperAppBase: restricted | primary SuperToken accepted");
        assertFalse(
            superApp.isAcceptedSuperToken(otherSuperToken), "SuperAppBase: restricted | other SuperToken not accepted"
        );
        superApp.setAcceptedSuperToken(otherSuperToken, true); // both shall now be accepted
        assertTrue(
            superApp.isAcceptedSuperToken(otherSuperToken), "SuperAppBase: restricted | other SuperToken now accepted"
        );
    }

    function testUnauthorizedHost() public {
        vm.startPrank(eve);

        vm.expectRevert(CFASuperAppBase.UnauthorizedHost.selector);
        superApp.afterAgreementCreated(superToken, address(sf.cfa), "0x", "0x", "0x", "0x");

        vm.expectRevert(CFASuperAppBase.UnauthorizedHost.selector);
        superApp.afterAgreementUpdated(superToken, address(sf.cfa), "0x", "0x", "0x", "0x");

        // termination callback doesn't revert, but should have no side effects
        superApp.afterAgreementTerminated(superToken, address(sf.cfa), "0x", "0x", "0x", "0x");
        assertEq(superApp.afterSenderHolder(), address(0));

        vm.stopPrank();
    }

    function testNotAcceptedAgreement() public {
        vm.startPrank(address(sf.host));

        // correct host, but wrong agreement (ida instead of cfa)
        superApp.afterAgreementCreated(superToken, address(sf.ida), "0x", "0x", "0x", "0x");
        // should have no side effects
        assertEq(
            superApp.afterSenderHolder(),
            address(0),
            "SuperAppBase: afterAgreementCreated | afterSenderHolder should be address(0)"
        );

        superApp.afterAgreementUpdated(superToken, address(sf.ida), "0x", "0x", "0x", "0x");
        assertEq(
            superApp.afterSenderHolder(),
            address(0),
            "SuperAppBase: afterAgreementUpdated | afterSenderHolder should be address(0)"
        );

        superApp.afterAgreementTerminated(superToken, address(sf.ida), "0x", "0x", "0x", "0x");
        assertEq(
            superApp.afterSenderHolder(),
            address(0),
            "SuperAppBase: afterAgreementTerminated | afterSenderHolder should be address(0)"
        );

        vm.stopPrank();
    }

    // test create flow
    function testCreateFlowToSuperApp(int96 flowRate) public {
        flowRate = int96(bound(flowRate, 1, int96(uint96(type(uint32).max))));
        vm.startPrank(alice);
        superToken.createFlow(superAppAddress, flowRate);
        assertEq(
            superToken.getFlowRate(alice, superAppAddress), flowRate, "SuperAppBase: createFlow | flowRate incorrect"
        );
        assertEq(superApp.afterSenderHolder(), alice, "SuperAppBase: createFlow | afterSenderHolder incorrect");
        vm.stopPrank();
    }

    // test update flow
    function testUpdateFlowToSuperApp(int96 flowRate, int96 updatedFlowRate) public {
        flowRate = int96(bound(flowRate, 1, int96(uint96(type(uint32).max))));
        updatedFlowRate = int96(bound(flowRate, 1, int96(uint96(type(uint32).max))));
        vm.startPrank(alice);
        superToken.createFlow(superAppAddress, flowRate);
        assertEq(
            superToken.getFlowRate(alice, superAppAddress), flowRate, "SuperAppBase: updateFlow | flowRate incorrect"
        );
        assertEq(superApp.afterSenderHolder(), alice, "SuperAppBase: updateFlow | afterSenderHolder incorrect");
        assertEq(superApp.oldFlowRateHolder(), 0, "SuperAppBase: updateFlow | oldFlowRateHolder incorrect");
        superToken.updateFlow(superAppAddress, updatedFlowRate);
        assertEq(
            superToken.getFlowRate(alice, superAppAddress),
            updatedFlowRate,
            "SuperAppBase: updateFlow2 | updatedFlowRate incorrect"
        );
        assertEq(superApp.afterSenderHolder(), alice, "SuperAppBase: updateFlow2 | afterSenderHolder incorrect");
        assertEq(superApp.oldFlowRateHolder(), flowRate, "SuperAppBase: updateFlow2 | oldFlowRateHolder incorrect");
        vm.stopPrank();
    }

    // test delete flow
    function testDeleteFlowToSuperApp(int96 flowRate) public {
        flowRate = int96(bound(flowRate, 1, int96(uint96(type(uint32).max))));
        vm.startPrank(alice);
        superToken.createFlow(superAppAddress, flowRate);
        assertEq(
            superToken.getFlowRate(alice, superAppAddress), flowRate, "SuperAppBase: deleteFlow | flowRate incorrect"
        );
        assertEq(superApp.afterSenderHolder(), alice, "SuperAppBase: deleteFlow | afterSenderHolder incorrect");
        assertEq(superApp.oldFlowRateHolder(), 0, "SuperAppBase: deleteFlow | oldFlowRateHolder incorrect");
        superToken.deleteFlow(alice, superAppAddress);
        assertEq(superToken.getFlowRate(alice, superAppAddress), 0, "SuperAppBase: deleteFlow2 | flowRate incorrect");
        assertEq(superApp.afterSenderHolder(), alice, "SuperAppBase: deleteFlow2 | afterSenderHolder incorrect");
        assertEq(
            superApp.afterReceiverHolder(), superAppAddress, "SuperAppBase: deleteFlow2 | afterReceiverHolder incorrect"
        );
        assertEq(superApp.oldFlowRateHolder(), flowRate, "SuperAppBase: deleteFlow2 | oldFlowRateHolder incorrect");
        vm.stopPrank();
    }

    function testMockBeforeAgreementCreated() public {
        vm.startPrank(alice);
        bytes memory data = superApp.beforeAgreementCreated(
            superToken,
            address(sf.host.getAgreementClass(keccak256("org.superfluid-finance.agreements.ConstantFlowAgreement.v1"))),
            keccak256(abi.encode(alice, bob)), // agreementId (flowId),
            abi.encode(alice, bob),
            "0x"
        );
        assertEq(data, "0x", "SuperAppBase: beforeAgreementCreated | data should be 0x");
        vm.stopPrank();
    }

    function testMockFailedBeforeAgreementTerminated() public {
        vm.startPrank(alice);
        bytes memory data = superApp.beforeAgreementTerminated(
            superToken,
            address(sf.host.getAgreementClass(keccak256("org.superfluid-finance.agreements.ConstantFlowAgreement.v1"))),
            keccak256(abi.encode(alice, bob)), // agreementId (flowId),
            abi.encode(alice, bob),
            "0x"
        );
        assertEq(data, "0x", "SuperAppBase: beforeAgreementTerminated | data should be 0x");
        vm.stopPrank();
    }

    function testFlowOfNotAcceptedSuperTokenToSuperApp() public {
        vm.startPrank(alice);
        // enable the filter
        superApp.setAcceptedSuperToken(superToken, true);
        vm.expectRevert(CFASuperAppBase.NotAcceptedSuperToken.selector);
        sf.host.callAgreement(
            sf.cfa,
            abi.encodeCall(sf.cfa.createFlow, (otherSuperToken, address(superApp), int96(69), new bytes(0))),
            new bytes(0) // userData
        );
        vm.stopPrank();
    }
}
