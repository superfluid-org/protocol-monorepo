// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Vm} from "forge-std/Vm.sol";
import {Test} from "forge-std/Test.sol";
import {Resolver} from "../../contracts/utils/Resolver.sol";
import {ResolverSetKey} from "../../foundry-scripts/ResolverSetKey.s.sol";
import {GovAction} from "../../foundry-scripts/GovAction.s.sol";
import {DeployUtils} from "../../foundry-scripts/utils/DeployUtils.sol";
import {SuperfluidGovernanceBase} from "../../contracts/gov/SuperfluidGovernanceBase.sol";
import {ISuperfluid} from "../../contracts/interfaces/superfluid/ISuperfluid.sol";
import {ISuperfluidToken} from "../../contracts/interfaces/superfluid/ISuperfluidToken.sol";
import {ISuperfluidGovernance} from "../../contracts/interfaces/superfluid/ISuperfluidGovernance.sol";

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
contract GovPayloadHarness is GovAction {
    function execute(address host, address governance, address admin) external {
        BaseConfig memory config = BaseConfig(host, ISuperfluidGovernance(governance), admin);
        _executeAction("setTokenMinimumDeposit", config);
    }
    function executeDirect(address host, address governance, address admin) external {
        BaseConfig memory config = BaseConfig(host, ISuperfluidGovernance(governance), admin);
        vm.startBroadcast(admin);
        _executeAction("setTokenMinimumDeposit", config);
        vm.stopBroadcast();
    }
}
contract ResolverPayloadHarness {
    function executeDirect(Resolver resolver, string memory key, address value, address admin) external {
        Vm vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));
        vm.startBroadcast(admin);
        DeployUtils.setResolverValue(resolver, key, value);
        vm.stopBroadcast();
    }
    function execute(Resolver resolver, string memory key, address value) external {
        DeployUtils.setResolverValue(resolver, key, value);
    }
}

contract OpsPayloadTest is Test {
    address constant VALUE = address(0x1234);
    address constant HOST = address(0x5678);
    string constant KEY = "supertokens.v1.TESTx";
    ResolverPayloadHarness resolverHarness;
    GovPayloadHarness govHarness;

    function setUp() public {
        resolverHarness = new ResolverPayloadHarness();
        govHarness = new GovPayloadHarness();
        vm.setEnv("TOKEN_ADDRESS", vm.toString(VALUE));
        vm.setEnv("MINIMUM_DEPOSIT", "42");
        vm.createDir(".tmp", true);
    }
    function resolverFor(address admin) internal returns (Resolver r) {
        r = new Resolver();
        r.grantRole(bytes32(0), admin);
        r.revokeRole(bytes32(0), address(this));
    }
    function govData() internal pure returns (bytes memory) {
        return abi.encodeWithSelector(SuperfluidGovernanceBase.setSuperTokenMinimumDeposit.selector,
            ISuperfluid(HOST), ISuperfluidToken(VALUE), uint256(42));
    }
    function testResolverDirectEOAAction() public {
        address admin = address(0xA11CE);
        Resolver r = new Resolver();
        r.grantRole(bytes32(0), admin);
        r.revokeRole(bytes32(0), address(this));
        vm.setEnv("RESOLVER_ADDRESS", vm.toString(address(r)));
        vm.setEnv("RESOLVER_KEY", KEY);
        vm.setEnv("RESOLVER_VALUE", vm.toString(VALUE));
        vm.setEnv("ALLOW_UPDATE", "");
        ResolverSetKey script = new ResolverSetKey();
        resolverHarness.executeDirect(r, KEY, VALUE, admin);
        assertEq(r.get(KEY), VALUE);
        vm.expectRevert("ALLOW_UPDATE=1 required");
        script.run();
    }
    function testResolverLegacyMultisigPayload() public {
        PayloadMultisig multi = new PayloadMultisig();
        Resolver r = resolverFor(address(multi));
        resolverHarness.execute(r, KEY, VALUE);
        assertEq(multi.target(), address(r));
        assertEq(multi.value(), 0);
        assertEq(multi.data(), abi.encodeWithSelector(Resolver.set.selector, KEY, VALUE));
        assertEq(r.get(KEY), address(0));
    }
    // vm.setEnv is process-global; keep both file-producing routes in one test.
    function testResolverAndGovSafePayloads() public {
        string memory file = ".tmp/resolver-safe-test.jsonl";
        vm.setEnv("DEPLOYER", vm.toString(VALUE));
        vm.setEnv("SAFE_PAYLOAD_SIMULATED", "true");
        vm.setEnv("SAFE_PAYLOADS_FILE", file);
        vm.writeFile(file, "");
        PayloadSafe safe = new PayloadSafe();
        Resolver r = resolverFor(address(safe));
        resolverHarness.execute(r, KEY, VALUE);
        string memory json = vm.readFile(file);
        assertEq(vm.parseJsonAddress(json, ".safeAddress"), address(safe));
        assertEq(vm.parseJsonString(json, ".chainId"), vm.toString(block.chainid));
        assertEq(vm.parseJsonAddress(json, ".deployer"), VALUE);
        assertTrue(vm.parseJsonBool(json, ".simulated"));
        assertEq(vm.parseJsonAddress(json, ".to"), address(r));
        assertEq(vm.parseJsonString(json, ".value"), "0");
        assertEq(vm.parseJsonBytes(json, ".data"), abi.encodeWithSelector(Resolver.set.selector, KEY, VALUE));
        assertEq(r.get(KEY), address(0));
        vm.writeFile(file, "");
        vm.setEnv("SAFE_PAYLOAD_SIMULATED", "false");
        GovernanceTarget gov = new GovernanceTarget(address(safe));
        govHarness.execute(HOST, address(gov), address(safe));
        json = vm.readFile(file);
        assertEq(vm.parseJsonAddress(json, ".safeAddress"), address(safe));
        assertFalse(vm.parseJsonBool(json, ".simulated"));
        assertEq(vm.parseJsonAddress(json, ".to"), address(gov));
        assertEq(vm.parseJsonString(json, ".value"), "0");
        assertEq(vm.parseJsonBytes(json, ".data"), govData());
        assertEq(gov.deposit(), 0);
    }
    function testGovDirectAction() public {
        address admin = address(0xA11CE);
        GovernanceTarget gov = new GovernanceTarget(admin);
        govHarness.executeDirect(HOST, address(gov), admin);
        assertEq(gov.host(), HOST); assertEq(gov.token(), VALUE); assertEq(gov.deposit(), 42);
    }
    function testGovLegacyMultisigPayload() public {
        PayloadMultisig multi = new PayloadMultisig();
        GovernanceTarget gov = new GovernanceTarget(address(multi));
        govHarness.execute(HOST, address(gov), address(multi));
        assertEq(multi.target(), address(gov)); assertEq(multi.value(), 0); assertEq(multi.data(), govData());
        assertEq(gov.deposit(), 0);
    }
}
