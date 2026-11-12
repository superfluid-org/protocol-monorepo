// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Test} from "forge-std/Test.sol";
import {FrameworkScript, Superfluid, Resolver, SuperfluidGovernanceII, SuperToken} from "../../../foundry-scripts/Framework.s.sol";
import {ResolverSetKey} from "../../../foundry-scripts/ResolverSetKey.s.sol";
import {SlotsBitmapLibrary} from "../../../contracts/libs/SlotsBitmapLibrary.sol";
import {SuperfluidPoolDeployerLibrary} from "../../../contracts/agreements/gdav1/SuperfluidPoolDeployerLibrary.sol";

interface ForkSafe {
    function VERSION() external view returns (string memory);
    function getOwners() external view returns (address[] memory);
    function getThreshold() external view returns (uint256);
    function nonce() external view returns (uint256);
    function approveHash(bytes32) external;
    function getTransactionHash(address,uint256,bytes memory,uint8,uint256,uint256,uint256,address,address,uint256) external view returns (bytes32);
    function execTransaction(address,uint256,bytes memory,uint8,uint256,uint256,uint256,address,address payable,bytes memory) external returns (bool);
}
interface ForkMultisig {
    function getOwners() external view returns (address[] memory);
    function transactionCount() external view returns (uint256);
    function transactions(uint256) external view returns (address,uint256,bytes memory,bool);
}

/// @notice Opt-in only: all state changes occur inside a read-only RPC fork.
contract FrameworkForkTest is Test {
    function testForkUpgradeAndResolverRoutes() public {
        // A Foundry script is an offchain executor, not a contract deployed on the target chain.
        FrameworkScript script = new FrameworkScript();
        vm.makePersistent(address(script));
        vm.makePersistent(address(SlotsBitmapLibrary));
        vm.makePersistent(address(SuperfluidPoolDeployerLibrary));
        vm.createSelectFork(vm.envString("FORK_RPC_URL"));
        Superfluid host = Superfluid(vm.envAddress("FORK_HOST"));
        Resolver resolver = Resolver(vm.envAddress("FORK_RESOLVER"));
        address gov = address(host.getGovernance());
        address owner = SuperfluidGovernanceII(gov).owner();
        address sender = owner.code.length == 0 ? owner : address(0x1234);
        vm.deal(sender, 1000 ether);
        vm.setEnv("DEPLOYER", vm.toString(sender));
        vm.setEnv("HOST_ADDRESS", vm.toString(address(host)));
        string memory file = string.concat(".tmp/fork-", vm.toString(block.chainid), ".jsonl");
        vm.createDir(".tmp", true);
        vm.writeFile(file, "");
        vm.setEnv("SAFE_PAYLOADS_FILE", file);
        bytes memory beforeState = _state(script, host, resolver);
        address previousLogic = host.getCodeAddress();
        script.upgrade();
        if (owner.code.length > 0) {
            string memory json = vm.readFile(file);
            assertEq(vm.parseJsonAddress(json, ".safeAddress"), owner);
            assertEq(vm.parseJsonAddress(json, ".to"), gov);
            _executeSafe(ForkSafe(owner), gov, vm.parseJsonBytes(json, ".data"));
        }
        assertTrue(host.getCodeAddress() != previousLogic, "upgrade did not execute");
        assertEq(_state(script, host, resolver), beforeState, "upgrade changed deployed policy or authority");
        if (block.chainid == 1) _resolverMultisig(resolver);
    }

    function _state(FrameworkScript script, Superfluid host, Resolver resolver) internal view returns (bytes memory) {
        return abi.encode(script.policyOf(host),
            SuperfluidGovernanceII(address(host.getGovernance())).getRewardAddress(host, SuperToken(address(0))),
            address(host.SIMPLE_FORWARDER()), address(host.getERC2771Forwarder()),
            address(host.getSimpleACL()), resolver.get("Superfluid.v1"), resolver.get("CFAv1Forwarder"),
            resolver.get("GDAv1Forwarder"), resolver.get("TOGA"));
    }

    function _executeSafe(ForkSafe safe, address target, bytes memory data) internal {
        assertEq(safe.VERSION(), "1.3.0", "test must exercise the deployed Safe version");
        address[] memory owners = safe.getOwners();
        for (uint256 i = 1; i < owners.length; ++i) {
            for (uint256 j = i; j > 0 && owners[j] < owners[j - 1]; --j) {
                (owners[j], owners[j - 1]) = (owners[j - 1], owners[j]);
            }
        }
        bytes32 hash = safe.getTransactionHash(target, 0, data, 0, 0, 0, 0, address(0), address(0), safe.nonce());
        bytes memory signatures;
        uint256 threshold = safe.getThreshold();
        for (uint256 i; i < threshold; ++i) {
            vm.prank(owners[i]);
            safe.approveHash(hash);
            signatures = bytes.concat(signatures, abi.encodePacked(bytes32(uint256(uint160(owners[i]))), bytes32(0), uint8(1)));
        }
        assertTrue(safe.execTransaction(target, 0, data, 0, 0, 0, 0, address(0), payable(address(0)), signatures),
            "real Safe rejected governance payload");
    }

    function _resolverMultisig(Resolver resolver) internal {
        address admin = resolver.getRoleMember(bytes32(0), 0);
        ForkMultisig multisig = ForkMultisig(admin);
        address sender = multisig.getOwners()[0];
        uint256 count = multisig.transactionCount();
        string memory key = "supertokens.v1.ArchRegression";
        vm.setEnv("DEPLOYER", vm.toString(sender));
        new ResolverSetKey().run(resolver, key, address(0x1234), false);
        assertEq(multisig.transactionCount(), count + 1);
        (address target, uint256 value, bytes memory data, bool executed) = multisig.transactions(count);
        assertEq(target, address(resolver));
        assertEq(value, 0);
        assertEq(data, abi.encodeCall(Resolver.set, (key, address(0x1234))));
        assertTrue(executed, "one-confirmation legacy multisig did not execute");
        assertEq(resolver.get(key), address(0x1234), "legacy multisig did not update resolver");
    }
}
