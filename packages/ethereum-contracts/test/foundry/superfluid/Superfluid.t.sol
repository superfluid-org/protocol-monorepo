// SPDX-License-Identifier: AGPLv3
pragma solidity ^0.8.23;

import "../FoundrySuperfluidTester.t.sol";
import { UUPSProxiable } from "../../../contracts/upgradability/UUPSProxiable.sol";
import { SuperToken } from "../../../contracts/superfluid/SuperToken.sol";
import { SuperTokenV1Library } from "../../../contracts/apps/SuperTokenV1Library.sol";
import { ISuperAgreement } from "../../../contracts/interfaces/superfluid/ISuperAgreement.sol";
import { ISuperfluid, SuperAppDefinitions } from "../../../contracts/interfaces/superfluid/ISuperfluid.sol";
import { ISuperApp } from "../../../contracts/interfaces/superfluid/ISuperApp.sol";
import { AgreementMock } from "../../../contracts/mocks/AgreementMock.t.sol";
import { AllowList } from "../../../contracts/utils/AllowList.sol";

contract SuperfluidIntegrationTest is FoundrySuperfluidTester {
    using SuperTokenV1Library for SuperToken;

    uint32 private constant _NUM_AGREEMENTS = 3;

    constructor() FoundrySuperfluidTester(3) { }

    function testRevertRegisterMax256Agreements() public {
        uint32 maxNumAgreements = sf.host.MAX_NUM_AGREEMENTS();
        ISuperAgreement[] memory mocks = new ISuperAgreement[](
            maxNumAgreements
        );
        mocks[0] = ISuperAgreement(address(sf.cfa));
        mocks[1] = ISuperAgreement(address(sf.ida));
        mocks[2] = ISuperAgreement(address(sf.gda));
        for (uint256 i; i < maxNumAgreements - _NUM_AGREEMENTS; ++i) {
            bytes32 id = keccak256(abi.encode("type.", i));
            AgreementMock agreementMock = new AgreementMock(address(sf.host), id, i);

            vm.startPrank(sf.governance.owner());
            sf.governance.registerAgreementClass(sf.host, address(agreementMock));
            vm.stopPrank();
            agreementMock = sf.host.NON_UPGRADABLE_DEPLOYMENT() ? agreementMock : AgreementMock(address(sf.host.getAgreementClass(id)));
            mocks[i + _NUM_AGREEMENTS] = ISuperAgreement(address(agreementMock));
        }

        ISuperAgreement[] memory agreementClasses = sf.host.mapAgreementClasses(type(uint256).max);

        for (uint256 i; i < maxNumAgreements; ++i) {
            assertEq(address(agreementClasses[i]), address(mocks[i]), "Superfluid.t: agreement class not registered");
        }

        AgreementMock badmock = new AgreementMock(
            address(sf.host),
            keccak256(abi.encode("max.bad")),
            maxNumAgreements + 1
        );

        vm.startPrank(sf.governance.owner());
        vm.expectRevert(ISuperfluid.HOST_MAX_256_AGREEMENTS.selector);
        sf.governance.registerAgreementClass(sf.host, address(badmock));
        vm.stopPrank();
    }

    function testChangeSuperTokenAdmin(address newAdmin) public {
        vm.startPrank(address(sf.governance));
        sf.host.changeSuperTokenAdmin(superToken, newAdmin);
        vm.stopPrank();

        assertEq(superToken.getAdmin(), newAdmin, "Superfluid.t: super token admin not changed");
    }

    function testRevertChangeSuperTokenAdminWhenHostIsNotAdmin(address initialAdmin, address newAdmin) public {
        vm.assume(initialAdmin != address(0));
        vm.assume(newAdmin != address(0));
        vm.assume(initialAdmin != address(sf.host));

        vm.startPrank(address(sf.host));
        superToken.changeAdmin(initialAdmin);
        vm.stopPrank();

        vm.startPrank(address(sf.governance));
        vm.expectRevert(ISuperToken.SUPER_TOKEN_ONLY_ADMIN.selector);
        sf.host.changeSuperTokenAdmin(superToken, newAdmin);
        vm.stopPrank();
    }

    function testRevertChangeSuperTokenAdminWhenNotGovernanceCalling(address newAdmin) public {
        vm.assume(newAdmin != address(sf.governance));
        vm.startPrank(newAdmin);
        vm.expectRevert(ISuperfluid.HOST_ONLY_GOVERNANCE.selector);
        sf.host.changeSuperTokenAdmin(superToken, newAdmin);
        vm.stopPrank();
    }

    function testSuperAppRegistrationViaAllowList() public {
        AllowList allowList = new AllowList();
        Superfluid hostWithAllowList = new Superfluid(
            true, true, 3_000_000, address(0), address(0), address(allowList)
        );
        hostWithAllowList.initialize(sf.governance);

        // first, give permission to alice
        address allowlistAddress = address(hostWithAllowList.getSuperAppRegistrationAllowlist());
        // get allowlist owner
        address allowListOwner = AllowList(allowlistAddress).owner();

        // give permission to alice
        vm.startPrank(allowListOwner);
        AllowList(allowlistAddress).givePermission(alice);
        vm.stopPrank();

        // any address which is a contract is ok for the purpose of this test
        ISuperApp mockSuperApp = ISuperApp(address(this));

        // as bob, try to register a superapp - should revert
        vm.startPrank(bob);
        vm.expectRevert(ISuperfluid.HOST_NO_APP_REGISTRATION_PERMISSION.selector);
        hostWithAllowList.registerApp(mockSuperApp, SuperAppDefinitions.APP_LEVEL_FINAL);
        vm.stopPrank();

        // as alice, try to register a superapp - should succeed
        vm.startPrank(alice);
        hostWithAllowList.registerApp(mockSuperApp, SuperAppDefinitions.APP_LEVEL_FINAL);
        vm.stopPrank();
        vm.assertTrue(hostWithAllowList.isApp(mockSuperApp));

        // revoke permission from alice
        vm.startPrank(allowListOwner);
        AllowList(allowlistAddress).revokePermission(alice);
        vm.stopPrank();

        // as alice, try to register a superapp - should revert
        vm.startPrank(alice);
        vm.expectRevert(ISuperfluid.HOST_NO_APP_REGISTRATION_PERMISSION.selector);
        hostWithAllowList.registerApp(mockSuperApp, SuperAppDefinitions.APP_LEVEL_FINAL);
        vm.stopPrank();
    }
}
