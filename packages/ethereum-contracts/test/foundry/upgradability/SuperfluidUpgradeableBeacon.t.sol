// SPDX-License-Identifier: AGPLv3
pragma solidity ^0.8.23;

import { Test } from "forge-std/Test.sol";

import { SuperfluidUpgradeableBeacon } from "../../../contracts/upgradability/SuperfluidUpgradeableBeacon.sol";

import { BeaconProxiable } from "../../../contracts/upgradability/BeaconProxiable.sol";

contract ProxiableBeacon is BeaconProxiable {
    function proxiableUUID() public pure override returns (bytes32) {
        return keccak256("ProxiableBeacon");
    }
}

contract BadProxiableBeacon is BeaconProxiable {
    function proxiableUUID() public pure override returns (bytes32) {
        return keccak256("BadProxiableBeacon");
    }
}

contract SuperfluidUpgradeableBeaconTest is Test {
    address public constant owner = address(0x420);
    SuperfluidUpgradeableBeacon public beacon;

    function setUp() public {
        vm.startPrank(owner);
        ProxiableBeacon proxiableBeacon = new ProxiableBeacon();
        beacon = new SuperfluidUpgradeableBeacon(address(proxiableBeacon));
        vm.stopPrank();
    }

    function testRevertNonOwnerUpgrade() public {
        ProxiableBeacon proxiableBeacon = new ProxiableBeacon();
        vm.expectRevert("Ownable: caller is not the owner");
        beacon.upgradeTo(address(proxiableBeacon));
    }

    function testRevertUpgradeToZeroAddress() public {
        vm.expectRevert(SuperfluidUpgradeableBeacon.ZERO_ADDRESS_IMPLEMENTATION.selector);
        vm.startPrank(owner);
        beacon.upgradeTo(address(0));
        vm.stopPrank();
    }

    function testRevertUpgradeToIncompatibleLogic() public {
        BadProxiableBeacon badProxiableBeacon = new BadProxiableBeacon();
        vm.expectRevert(SuperfluidUpgradeableBeacon.INCOMPATIBLE_LOGIC.selector);
        vm.startPrank(owner);
        beacon.upgradeTo(address(badProxiableBeacon));
        vm.stopPrank();
    }

    function testRevertWhenDoingProxyLoop() public {
        vm.expectRevert(SuperfluidUpgradeableBeacon.NO_PROXY_LOOP.selector);
        vm.startPrank(owner);
        beacon.upgradeTo(address(beacon));
        vm.stopPrank();
    }

    function testUpgradeTo() public {
        ProxiableBeacon proxiableBeacon = new ProxiableBeacon();
        vm.startPrank(owner);
        beacon.upgradeTo(address(proxiableBeacon));
        vm.stopPrank();
        assertEq(
            beacon.implementation(), address(proxiableBeacon), "SuperfluidUpgradeableBeacon.t: wrong implementation"
        );
    }
}
