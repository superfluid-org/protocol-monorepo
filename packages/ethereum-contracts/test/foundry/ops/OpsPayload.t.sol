// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Test} from "forge-std/Test.sol";
import {Resolver} from "../../../contracts/utils/Resolver.sol";
import {ResolverSetKey} from "../../../foundry-scripts/ResolverSetKey.s.sol";
import {GovAction} from "../../../foundry-scripts/GovAction.s.sol";
import {SuperfluidGovernanceBase} from "../../../contracts/gov/SuperfluidGovernanceBase.sol";
import {ISuperfluid} from "../../../contracts/interfaces/superfluid/ISuperfluid.sol";
import {ISuperfluidToken} from "../../../contracts/interfaces/superfluid/ISuperfluidToken.sol";

contract PayloadMultisig {
    address public target;
    bytes public data;
    uint256 public value;
    function required() external pure returns (uint256) { return 1; }
    function submitTransaction(address to, uint256 amount, bytes memory payload) external returns (uint256) {
        target = to; value = amount; data = payload; return 0;
    }
}
contract PayloadSafe {
    function VERSION() external pure returns (string memory) { return "1.3.0"; }
}
contract GovernanceTarget {
    address public owner;
    address public host;
    address public token;
    uint256 public deposit;
    constructor(address admin) { owner = admin; }
    function setSuperTokenMinimumDeposit(ISuperfluid h, ISuperfluidToken t, uint256 d) external {
        require(msg.sender == owner, "owner"); host = address(h); token = address(t); deposit = d;
    }
}
contract GovHost {
    address public getGovernance;
    constructor(address governance) { getGovernance = governance; }
}
contract GovPayloadHarness is GovAction {
    ISuperfluid private immutable host;
    constructor(address governance) { host = ISuperfluid(address(new GovHost(governance))); }
    function _host() internal view override returns (ISuperfluid) { return host; }
    function hostAddress() external view returns (address) { return address(host); }
}

contract OpsPayloadTest is Test {
    address constant VALUE = address(0x1234);
    string constant KEY = "supertokens.v1.TESTx";

    function setUp() public {
        vm.setEnv("DEPLOYER", vm.toString(tx.origin));
    }

    function resolverFor(address admin) internal returns (Resolver r) {
        r = new Resolver();
        r.grantRole(bytes32(0), admin);
        r.revokeRole(bytes32(0), address(this));
    }
    function govData(address host) internal pure returns (bytes memory) {
        return abi.encodeCall(SuperfluidGovernanceBase.setSuperTokenMinimumDeposit,
            (ISuperfluid(host), ISuperfluidToken(VALUE), uint256(42)));
    }
    function testResolverRejectsOccupiedEntry() public {
        Resolver r = resolverFor(tx.origin);
        ResolverSetKey script = new ResolverSetKey();
        script.run(r, KEY, VALUE, false);
        assertEq(r.get(KEY), VALUE);
        script.run(r, "unrelated", address(0xBEEF), false);
        vm.expectRevert("ALLOW_UPDATE=1 required");
        script.run(r, KEY, address(0xCAFE), false);
        assertEq(r.get(KEY), VALUE);
        script.run(r, KEY, address(0xCAFE), true);
        assertEq(r.get(KEY), address(0xCAFE));
        assertEq(r.get("unrelated"), address(0xBEEF));
    }
    function testResolverLegacyMultisigPayload() public {
        PayloadMultisig multi = new PayloadMultisig();
        Resolver r = resolverFor(address(multi));
        new ResolverSetKey().run(r, KEY, VALUE, false);
        assertEq(multi.target(), address(r));
        assertEq(multi.value(), 0);
        assertEq(multi.data(), abi.encodeCall(Resolver.set, (KEY, VALUE)));
        assertEq(r.get(KEY), address(0));
    }
    function testSafePayloadBindingAndCalldata() public {
        string memory file = ".tmp/ops-safe-test.jsonl";
        vm.createDir(".tmp", true);
        vm.setEnv("SAFE_PAYLOADS_FILE", file);
        vm.setEnv("SAFE_PAYLOAD_SIMULATED", "true");
        vm.writeFile(file, "");
        PayloadSafe safe = new PayloadSafe();
        Resolver r = resolverFor(address(safe));
        new ResolverSetKey().run(r, KEY, VALUE, false);
        string memory json = vm.readFile(file);
        assertEq(vm.parseJsonAddress(json, ".safeAddress"), address(safe));
        assertEq(vm.parseJsonString(json, ".chainId"), vm.toString(block.chainid));
        assertTrue(vm.parseJsonBool(json, ".simulated"));
        assertEq(vm.parseJsonAddress(json, ".to"), address(r));
        assertEq(vm.parseJsonString(json, ".value"), "0");
        assertEq(vm.parseJsonBytes(json, ".data"), abi.encodeCall(Resolver.set, (KEY, VALUE)));
        assertEq(r.get(KEY), address(0));
        vm.writeFile(file, "");
        vm.setEnv("SAFE_PAYLOAD_SIMULATED", "false");
        GovernanceTarget gov = new GovernanceTarget(address(safe));
        GovPayloadHarness harness = new GovPayloadHarness(address(gov));
        harness.setTokenMinimumDeposit(ISuperfluidToken(VALUE), 42);
        json = vm.readFile(file);
        assertEq(vm.parseJsonAddress(json, ".safeAddress"), address(safe));
        assertFalse(vm.parseJsonBool(json, ".simulated"));
        assertEq(vm.parseJsonAddress(json, ".to"), address(gov));
        assertEq(vm.parseJsonBytes(json, ".data"), govData(harness.hostAddress()));
        assertEq(gov.deposit(), 0);
    }
    function testGovTypedLegacyMultisigPayload() public {
        PayloadMultisig multi = new PayloadMultisig();
        GovernanceTarget gov = new GovernanceTarget(address(multi));
        GovPayloadHarness harness = new GovPayloadHarness(address(gov));
        harness.setTokenMinimumDeposit(ISuperfluidToken(VALUE), 42);
        assertEq(multi.target(), address(gov));
        assertEq(multi.data(), govData(harness.hostAddress()));
        assertEq(gov.deposit(), 0);
    }
}
