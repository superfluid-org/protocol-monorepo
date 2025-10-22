// SPDX-License-Identifier: AGPLv3
pragma solidity ^0.8.23;

import { FoundrySuperfluidTester } from "../FoundrySuperfluidTester.t.sol";
import { SuperTokenFactory, IPoolMemberNFT } from "../../../contracts/superfluid/SuperTokenFactory.sol";
import { PoolAdminNFT, IPoolAdminNFT } from "../../../contracts/agreements/gdav1/PoolAdminNFT.sol";
import { ISuperToken, SuperToken } from "../../../contracts/superfluid/SuperToken.sol";
import { UUPSProxiable } from "../../../contracts/upgradability/UUPSProxiable.sol";

contract SuperTokenFactoryTest is FoundrySuperfluidTester {
    constructor() FoundrySuperfluidTester(0) { }

    function setUp() public override {
        super.setUp();
    }

    function testUpdateCodeSetsNewContracts() public {
        SuperToken newSuperTokenLogic = new SuperToken(
            sf.host,
            superToken.POOL_ADMIN_NFT()
        );
        PoolAdminNFT newPoolAdminNFTLogic = new PoolAdminNFT(sf.host, sf.gda);
        SuperTokenFactory newSuperTokenFactoryLogic = new SuperTokenFactory(
            sf.host,
            newSuperTokenLogic,
            newPoolAdminNFTLogic,
            IPoolMemberNFT(address(0))
        );
        vm.startPrank(address(sf.host));
        // We expect this to revert if the protocol is not upgradeable
        if (sf.host.NON_UPGRADABLE_DEPLOYMENT()) {
            vm.expectRevert("UUPSProxiable: not upgradable");
        }
        sf.superTokenFactory.updateCode(address(newSuperTokenFactoryLogic));
        vm.stopPrank();
    }
}
