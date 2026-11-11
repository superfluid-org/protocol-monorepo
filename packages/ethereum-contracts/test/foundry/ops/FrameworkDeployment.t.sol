// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;
import {Test} from "forge-std/Test.sol";
import {FrameworkScript, Superfluid, Resolver, SuperfluidGovernanceII, SuperTokenFactory, SuperToken,
    GeneralDistributionAgreementV1, UUPSProxiable} from "../../../foundry-scripts/Framework.s.sol";
import {ChainPolicy} from "../../../foundry-scripts/utils/ChainPolicy.sol";
import {ERC1820RegistryCompiled} from "../../../contracts/libs/ERC1820RegistryCompiled.sol";
import {TestToken} from "../../../contracts/utils/TestToken.sol";
import {IERC20Metadata} from "@openzeppelin-v5/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {ISuperTokenFactory} from "../../../contracts/interfaces/superfluid/ISuperTokenFactory.sol";
import {SimpleACL} from "../../../contracts/utils/SimpleACL.sol";
import {SuperfluidPool} from "../../../contracts/agreements/gdav1/SuperfluidPool.sol";
import {PoolAdminNFT} from "../../../contracts/agreements/gdav1/PoolAdminNFT.sol";
import {TestGovernance} from "../../../contracts/utils/TestGovernance.sol";

contract FrameworkDeploymentTest is Test {
    FrameworkScript internal script;
    address internal deployer = address(0x1234);

    function setUp() public {
        vm.chainId(31337);
        vm.setEnv("DEPLOYER", vm.toString(deployer));
        vm.setEnv("RESOLVER_ADDRESS", "0x0000000000000000000000000000000000000000");
        vm.setEnv("RELEASE_VERSION", "regression");
        vm.setEnv("CALLBACK_GAS_LIMIT", "12000000");
        vm.setEnv("APP_WHITELISTING", "false");
        vm.setEnv("IDA_FROZEN", "true");
        vm.setEnv("IDA_SLOTS", "256");
        vm.setEnv("REVIEWED_IMMUTABLE_OVERRIDE", "false");
        vm.etch(ERC1820RegistryCompiled.ADDRESS, ERC1820RegistryCompiled.BYTECODE);
        script = new FrameworkScript();
    }

    function testFreshAndUpgradePreservesProductionShape() public {
        (Superfluid host, Resolver resolver) = script.fresh();
        assertEq(resolver.get("Superfluid.regression"), address(host));
        assertGt(resolver.get("SuperfluidLoader-v1").code.length, 0);
        assertFalse(host.NON_UPGRADABLE_DEPLOYMENT());
        assertEq(SuperfluidGovernanceII(address(host.getGovernance())).owner(), deployer);
        assertTrue(resolver.hasRole(bytes32(0), deployer));
        assertTrue(host.isTrustedForwarder(resolver.get("CFAv1Forwarder")));
        assertTrue(host.isTrustedForwarder(resolver.get("GDAv1Forwarder")));
        assertTrue(host.isTrustedForwarder(resolver.get("BlindMacroForwarder")));
        _assertUpgradeEntryPointGuards(host);
        ChainPolicy.Policy memory beforePolicy = script.policyOf(host);
        address oldHostLogic = host.getCodeAddress();
        address oldTokenLogic = address(host.getSuperTokenFactory().getSuperTokenLogic());
        address wrapped = address(host.getSuperTokenFactory().createERC20Wrapper(
            IERC20Metadata(address(new TestToken("Test", "TEST", 18, 1e24))), 18,
            ISuperTokenFactory.Upgradability.SEMI_UPGRADABLE, "Super Test", "TESTx", address(0)));
        vm.setEnv("HOST_ADDRESS", vm.toString(address(host)));
        _assertMalformedIDARejected(host);
        address[4] memory oldImplementations = _implementations(host);
        script.upgrade();
        address[4] memory nextImplementations = _implementations(host);
        for (uint256 i; i < 4; ++i) assertTrue(oldImplementations[i] != nextImplementations[i], "Implementation unchanged");
        _assertLinkage(host);
        assertTrue(host.getCodeAddress() != oldHostLogic);
        assertTrue(address(host.getSuperTokenFactory().getSuperTokenLogic()) != oldTokenLogic);
        assertEq(abi.encode(script.policyOf(host)), abi.encode(beforePolicy));
        assertEq(resolver.get("Superfluid.regression"), address(host));
        SuperTokenFactory factory = SuperTokenFactory(address(host.getSuperTokenFactory()));
        SuperToken tokenLogic = SuperToken(address(factory.getSuperTokenLogic()));
        assertEq(UUPSProxiable(address(tokenLogic.POOL_ADMIN_NFT())).getCodeAddress(), address(factory.POOL_ADMIN_NFT_LOGIC()));
        address[] memory batch = new address[](1);
        batch[0] = wrapped;
        script.upgradeTokens(batch);
        assertEq(UUPSProxiable(wrapped).getCodeAddress(), address(factory.getSuperTokenLogic()));
        _assertTokenAdminGuard(host, batch);
        assertGt(resolver.get("ClearMacroForwarderV1WithPermit2").code.length, 0);
        assertFalse(host.isTrustedForwarder(resolver.get("ClearMacroForwarderV1WithPermit2")));
        _assertProxySafety(host, tokenLogic);
        vm.expectRevert();
        host.initialize(SuperfluidGovernanceII(address(0)));
        _assertTestGovernanceRejected(host);
        script.upgradeGovernance();
        assertEq(SuperfluidGovernanceII(address(host.getGovernance())).owner(), deployer);
        vm.setEnv("RESOLVER_ADDRESS", vm.toString(address(resolver)));
        address target = address(0x4567);
        vm.expectRevert("Grant must execute before revocation");
        script.revokeResolverAdmin(deployer, target);
        script.grantResolverAdmin(target);
        script.revokeResolverAdmin(deployer, target);
        assertTrue(resolver.hasRole(bytes32(0), target));
        assertFalse(resolver.hasRole(bytes32(0), deployer));
        script.handoverGovernance(target);
        SimpleACL acl = SimpleACL(address(host.getSimpleACL()));
        assertEq(acl.getRoleAdmin(keccak256("ACL_SUPERAPP_REGISTRATION_ROLE")),
            keccak256("ACL_SUPERAPP_REGISTRATION_ROLE_ADMIN"));
        script.handoverACL(target);
        assertFalse(acl.hasRole(bytes32(0), deployer));
        assertTrue(acl.hasRole(bytes32(0), target));
        assertEq(SuperfluidGovernanceII(address(host.getGovernance())).owner(), target);
        vm.setEnv("RESOLVER_ADDRESS", "0x0000000000000000000000000000000000000000");
    }
    function _assertMalformedIDARejected(Superfluid host) internal {
        address ida = address(host.getAgreementClass(
            keccak256("org.superfluid-finance.agreements.InstantDistributionAgreement.v1")));
        uint64 nonce = vm.getNonce(deployer);
        vm.mockCall(ida, abi.encodeWithSignature("NEW_ACTIVITY_FROZEN()"), hex"");
        vm.expectRevert();
        script.upgrade();
        vm.clearMockedCalls();
        assertEq(vm.getNonce(deployer), nonce, "Malformed policy must fail before deployment");
    }

    function _assertProxySafety(Superfluid host, SuperToken logic) internal {
        vm.expectRevert();
        logic.updateCode(address(logic));
        SuperfluidGovernanceII gov = SuperfluidGovernanceII(address(host.getGovernance()));
        vm.prank(deployer);
        vm.expectRevert("UUPSProxiable: proxy loop");
        gov.updateContracts(host, address(host), new address[](0), address(0), address(0));
    }
    function _assertTokenAdminGuard(Superfluid host, address[] memory batch) internal {
        SuperfluidGovernanceII gov = SuperfluidGovernanceII(address(host.getGovernance()));
        vm.prank(deployer);
        gov.changeSuperTokenAdmin(host, SuperToken(batch[0]), address(0x9999));
        uint64 nonce = vm.getNonce(deployer);
        vm.expectRevert("Token admin is not governed by this host");
        script.upgradeTokens(batch);
        assertEq(vm.getNonce(deployer), nonce, "Non-governed token must fail before action execution");
    }



    function testMissingRegistryRejectsBeforeCreation() public {
        vm.etch(ERC1820RegistryCompiled.ADDRESS, hex"");
        uint64 nonce = vm.getNonce(deployer);
        vm.expectRevert("ERC1820 missing: run deploy-erc1820.sh before deploying framework");
        script.fresh();
        assertEq(vm.getNonce(deployer), nonce);
    }

    function _assertTestGovernanceRejected(Superfluid host) internal {
        address gov = address(host.getGovernance());
        bytes memory original = gov.code;
        vm.etch(gov, address(new TestGovernance()).code);
        uint64 nonce = vm.getNonce(deployer);
        vm.expectRevert("Governance logic upgrade requires GovernanceII proxy");
        script.upgradeGovernance();
        assertEq(vm.getNonce(deployer), nonce);
        vm.etch(gov, original);
    }

    function _implementations(Superfluid host) internal view returns (address[4] memory values) {
        string[3] memory names = [string("ConstantFlowAgreement"), "InstantDistributionAgreement", "GeneralDistributionAgreement"];
        for (uint256 i; i < 3; ++i) {
            values[i] = UUPSProxiable(address(host.getAgreementClass(
                keccak256(abi.encodePacked("org.superfluid-finance.agreements.", names[i], ".v1"))))).getCodeAddress();
        }
        GeneralDistributionAgreementV1 gda = GeneralDistributionAgreementV1(address(host.getAgreementClass(
            keccak256("org.superfluid-finance.agreements.GeneralDistributionAgreement.v1"))));
        values[3] = gda.superfluidPoolBeacon().implementation();
    }

    function _assertLinkage(Superfluid host) internal view {
        GeneralDistributionAgreementV1 gda = GeneralDistributionAgreementV1(address(host.getAgreementClass(
            keccak256("org.superfluid-finance.agreements.GeneralDistributionAgreement.v1"))));
        assertEq(address(SuperfluidPool(gda.superfluidPoolBeacon().implementation()).GDA()), address(gda));
        SuperToken token = SuperToken(address(host.getSuperTokenFactory().getSuperTokenLogic()));
        PoolAdminNFT nft = PoolAdminNFT(address(token.POOL_ADMIN_NFT()));
        assertEq(address(nft.HOST()), address(host));
        assertEq(address(nft.GENERAL_DISTRIBUTION_AGREEMENT_V1()), address(gda));
    }

    function _assertUpgradeEntryPointGuards(Superfluid host) internal {
        vm.setEnv("HOST_ADDRESS", vm.toString(address(host)));
        _rejectOverride("CALLBACK_GAS_LIMIT", "11999999", "12000000");
        _rejectOverride("CALLBACK_GAS_LIMIT", "12000001", "12000000");
        _rejectOverride("APP_WHITELISTING", "true", "false");
        _rejectOverride("IDA_FROZEN", "false", "true");
        _rejectOverride("IDA_SLOTS", "32", "256");
        vm.setEnv("CALLBACK_GAS_LIMIT", "7777777");
        vm.setEnv("APP_WHITELISTING", "true");
        vm.setEnv("IDA_FROZEN", "false");
        vm.setEnv("IDA_SLOTS", "32");
        vm.setEnv("REVIEWED_IMMUTABLE_OVERRIDE", "true");
        script.upgrade();
        assertEq(host.CALLBACK_GAS_LIMIT(), 7777777);
        assertTrue(host.APP_WHITE_LISTING_ENABLED());
        ChainPolicy.Policy memory policy = script.policyOf(host);
        assertFalse(policy.idaFrozen);
        assertEq(policy.idaSlots, 32);
        vm.setEnv("REVIEWED_IMMUTABLE_OVERRIDE", "false");
    }

    function _rejectOverride(string memory key, string memory value, string memory original) internal {
        vm.setEnv(key, value);
        uint64 nonce = vm.getNonce(deployer);
        vm.expectRevert();
        script.upgrade();
        assertEq(vm.getNonce(deployer), nonce, "Policy rejection must precede deployment");
        vm.setEnv(key, original);
    }

    function checkPolicy(ChainPolicy.Policy memory previous, ChainPolicy.Policy memory next, bool reviewed) external pure {
        ChainPolicy.guard(previous, next, reviewed);
    }

    function testImmutableGuards() public {
        ChainPolicy.Policy memory previous = ChainPolicy.get(1);
        ChainPolicy.Policy memory next = ChainPolicy.get(1);
        next.callbackGasLimit = 1;
        vm.expectRevert("Callback gas change requires REVIEWED_IMMUTABLE_OVERRIDE=true");
        this.checkPolicy(previous, next, false);
        next.callbackGasLimit = previous.callbackGasLimit;
        next.whitelisting = false;
        vm.expectRevert("Whitelisting change requires REVIEWED_IMMUTABLE_OVERRIDE=true");
        this.checkPolicy(previous, next, false);
        next.whitelisting = true;
        next.idaFrozen = false;
        vm.expectRevert("IDA freeze change requires REVIEWED_IMMUTABLE_OVERRIDE=true");
        this.checkPolicy(previous, next, false);
        this.checkPolicy(previous, next, true);
    }

    function testFreshChainPolicies() public pure {
        uint256[16] memory chains = [uint256(43113), 11155111, 11155420, 84532, 5042002,
            100, 137, 10, 42161, 43114, 56, 1, 42220, 8453, 534352, 5042];
        for (uint256 i; i < chains.length; ++i) {
            ChainPolicy.Policy memory p = ChainPolicy.get(chains[i]);
            assertEq(p.whitelisting, i >= 5 && chains[i] != 5042);
            assertEq(p.idaFrozen, chains[i] != 10 && chains[i] != 11155420);
            assertEq(p.idaSlots, p.idaFrozen ? 256 : 32);
            assertEq(p.clearForwarderTrusted, i >= 5);
            assertEq(p.liquidationPeriod, i < 5 ? 3600 : 14400);
            assertEq(p.patricianPeriod, i < 5 ? 720 : 1800);
        }
        assertEq(ChainPolicy.get(1).callbackGasLimit, 3_000_000);
        assertEq(ChainPolicy.get(534352).callbackGasLimit, 3_000_000);
        assertEq(ChainPolicy.get(100).callbackGasLimit, 8_500_000);
        assertEq(ChainPolicy.get(43113).callbackGasLimit, 7_500_000);
        assertEq(ChainPolicy.get(43114).callbackGasLimit, 7_500_000);
    }
}
