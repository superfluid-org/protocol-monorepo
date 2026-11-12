// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Script, console} from "forge-std/Script.sol";
import {ChainPolicy} from "./utils/ChainPolicy.sol";
import {DeployUtils} from "./utils/DeployUtils.sol";
import {Superfluid, ISuperfluid, ISuperfluidGovernance} from "../contracts/superfluid/Superfluid.sol";
import {SuperfluidGovernanceII, SuperfluidGovernanceIIProxy} from "../contracts/gov/SuperfluidGovernanceII.sol";
import {SuperfluidGovernanceBase, ISuperfluidToken, ISuperToken} from "../contracts/gov/SuperfluidGovernanceBase.sol";
import {ConstantFlowAgreementV1} from "../contracts/agreements/ConstantFlowAgreementV1.sol";
import {InstantDistributionAgreementV1} from "../contracts/agreements/InstantDistributionAgreementV1.sol";
import {GeneralDistributionAgreementV1} from "../contracts/agreements/gdav1/GeneralDistributionAgreementV1.sol";
import {SuperfluidPool} from "../contracts/agreements/gdav1/SuperfluidPool.sol";
import {PoolAdminNFT, IPoolAdminNFT} from "../contracts/agreements/gdav1/PoolAdminNFT.sol";
import {SuperTokenFactory, IPoolMemberNFT} from "../contracts/superfluid/SuperTokenFactory.sol";
import {SuperToken} from "../contracts/superfluid/SuperToken.sol";
import {UUPSProxy} from "../contracts/upgradability/UUPSProxy.sol";
import {UUPSProxiable} from "../contracts/upgradability/UUPSProxiable.sol";
import {SuperfluidUpgradeableBeacon} from "../contracts/upgradability/SuperfluidUpgradeableBeacon.sol";
import {SimpleForwarder} from "../contracts/utils/SimpleForwarder.sol";
import {ERC2771Forwarder} from "../contracts/utils/ERC2771Forwarder.sol";
import {SimpleACL} from "../contracts/utils/SimpleACL.sol";
import {Resolver} from "../contracts/utils/Resolver.sol";
import {SuperfluidLoader} from "../contracts/utils/SuperfluidLoader.sol";
import {CFAv1Forwarder} from "../contracts/utils/CFAv1Forwarder.sol";
import {GDAv1Forwarder} from "../contracts/utils/GDAv1Forwarder.sol";
import {BlindMacroForwarder} from "../contracts/utils/BlindMacroForwarder.sol";
import {ClearMacroForwarderV1WithPermit2} from "../contracts/utils/ClearMacroForwarderV1WithPermit2.sol";
import {TOGA} from "../contracts/utils/TOGA.sol";
import {BatchLiquidator} from "../contracts/utils/BatchLiquidator.sol";

/// @notice Production upgradeable framework operations. No proposals are submitted here.
/// @dev Intentionally deploys fresh implementations on every upgrade. Resume an interrupted
/// broadcast with Foundry --resume, NOT another fresh invocation. Existing proxy types are
/// retained: deploy/initialize are separate transactions, as in legacy tooling.
contract FrameworkScript is Script {
    bytes32 internal constant CFA = keccak256("org.superfluid-finance.agreements.ConstantFlowAgreement.v1");
    bytes32 internal constant IDA = keccak256("org.superfluid-finance.agreements.InstantDistributionAgreement.v1");
    bytes32 internal constant GDA = keccak256("org.superfluid-finance.agreements.GeneralDistributionAgreement.v1");

    function _sender() internal view returns (address) { return vm.envAddress("DEPLOYER"); }

    function _preflight() internal view {
        require(address(0x1820a4B7618BdE71Dce8cdc73aAB6C95905faD24).code.length > 0,
            "ERC1820 missing: run deploy-erc1820.sh before deploying framework");
    }

    function _host(address target) internal view returns (Superfluid h) {
        h = Superfluid(target);
        require(!h.NON_UPGRADABLE_DEPLOYMENT(), "Production supports upgradeable hosts only");
        require(address(h.getGovernance()).code.length > 0, "Missing governance");
    }

    function _govOwner(address gov) internal view returns (address) {
        return SuperfluidGovernanceII(gov).owner();
    }

    function fresh() external returns (Superfluid, Resolver) {
        ChainPolicy.Policy memory p = ChainPolicy.get(block.chainid);
        _preflight();
        string memory release = vm.envOr("RELEASE_VERSION", string("v1"));
        require(bytes(release).length > 0, "Empty release");
        // An explicit supplied resolver is not a fresh deployment; do not overwrite a release.
        require(vm.envOr("RESOLVER_ADDRESS", address(0)) == address(0),
            "Fresh creates a new resolver; use resolver-set-key for an existing resolver");
        vm.startBroadcast(_sender());
        (Superfluid h, SuperfluidGovernanceII gov) = _freshHost(p);
        _freshAgreements(h, gov, p);
        _freshFactory(h, gov);
        Resolver resolver = _freshPeriphery(h, gov, release, p.clearForwarderTrusted);
        console.log("HOST_ADDRESS", address(h));
        console.log("RESOLVER_ADDRESS", address(resolver));
        console.log("GOVERNANCE_ADDRESS", address(gov));
        vm.stopBroadcast();
        return (h, resolver);
    }

    function _freshHost(ChainPolicy.Policy memory p) internal returns (Superfluid h, SuperfluidGovernanceII gov) {
        SuperfluidGovernanceII logic = new SuperfluidGovernanceII();
        logic.castrate();
        SuperfluidGovernanceIIProxy proxy = new SuperfluidGovernanceIIProxy();
        proxy.initializeProxy(address(logic));
        gov = SuperfluidGovernanceII(address(proxy));
        require(gov.owner() == _sender(), "Governance ownership initialization failed");
        SimpleForwarder simple = new SimpleForwarder();
        ERC2771Forwarder erc2771 = new ERC2771Forwarder();
        SimpleACL acl = new SimpleACL();
        acl.setRoleAdmin(keccak256("ACL_SUPERAPP_REGISTRATION_ROLE"),
            keccak256("ACL_SUPERAPP_REGISTRATION_ROLE_ADMIN"));
        Superfluid hostLogic = new Superfluid(false, p.whitelisting, p.callbackGasLimit,
            address(simple), address(erc2771), address(acl));
        UUPSProxy hostProxy = new UUPSProxy();
        hostProxy.initializeProxy(address(hostLogic));
        h = Superfluid(address(hostProxy));
        h.initialize(ISuperfluidGovernance(address(gov)));
        hostLogic.castrate();
        require(address(h.getGovernance()) == address(gov), "Host initialization failed");
        simple.transferOwnership(address(h));
        erc2771.transferOwnership(address(h));
        gov.setPPPConfig(h, ISuperfluidToken(address(0)), p.liquidationPeriod, p.patricianPeriod);
    }

    function _freshPeriphery(Superfluid h, SuperfluidGovernanceII gov, string memory release, bool mainnet) internal returns (Resolver resolver) {
        resolver = new Resolver();
        resolver.set(string.concat("Superfluid.", release), address(h));
        resolver.set("SuperfluidLoader-v1", address(new SuperfluidLoader(resolver)));
        address cfaFwd = address(new CFAv1Forwarder(h));
        address gdaFwd = address(new GDAv1Forwarder(h));
        address macroFwd = address(new BlindMacroForwarder(h));
        gov.enableTrustedForwarder(h, ISuperfluidToken(address(0)), cfaFwd);
        gov.enableTrustedForwarder(h, ISuperfluidToken(address(0)), gdaFwd);
        gov.enableTrustedForwarder(h, ISuperfluidToken(address(0)), macroFwd);
        resolver.set("CFAv1Forwarder", cfaFwd);
        resolver.set("GDAv1Forwarder", gdaFwd);
        resolver.set("BlindMacroForwarder", macroFwd);
        address clearFwd = address(new ClearMacroForwarderV1WithPermit2(h));
        resolver.set("ClearMacroForwarderV1WithPermit2", clearFwd);
        if (mainnet) gov.enableTrustedForwarder(h, ISuperfluidToken(address(0)), clearFwd);
        TOGA toga = new TOGA(h, 7 days);
        gov.setRewardAddress(h, ISuperfluidToken(address(0)), address(toga));
        resolver.set("TOGA", address(toga));
        resolver.set("BatchLiquidator", address(new BatchLiquidator(address(h))));
        require(resolver.hasRole(bytes32(0), _sender()), "Resolver ownership initialization failed");
    }

    function _freshAgreements(Superfluid h, SuperfluidGovernanceII gov, ChainPolicy.Policy memory p) internal {
        gov.registerAgreementClass(h, address(new ConstantFlowAgreementV1(h)));
        gov.registerAgreementClass(h, address(new InstantDistributionAgreementV1(h, p.idaFrozen, p.idaSlots)));
        SuperfluidPool bootstrap = new SuperfluidPool(GeneralDistributionAgreementV1(address(0)));
        bootstrap.castrate();
        SuperfluidUpgradeableBeacon beacon = new SuperfluidUpgradeableBeacon(address(bootstrap));
        gov.registerAgreementClass(h, address(new GeneralDistributionAgreementV1(h, beacon)));
        GeneralDistributionAgreementV1 gda = GeneralDistributionAgreementV1(address(h.getAgreementClass(GDA)));
        SuperfluidPool pool = new SuperfluidPool(gda);
        pool.castrate();
        beacon.upgradeTo(address(pool));
        beacon.transferOwnership(address(h));
        SimpleACL acl = SimpleACL(address(h.getSimpleACL()));
        bytes32 admin = keccak256("ACL_POOL_CONNECT_EXCLUSIVE_ROLE_ADMIN");
        acl.setRoleAdmin(gda.ACL_POOL_CONNECT_EXCLUSIVE_ROLE(), admin);
        acl.grantRole(admin, address(gda));
    }

    function _freshFactory(Superfluid h, SuperfluidGovernanceII gov) internal {
        GeneralDistributionAgreementV1 gda = GeneralDistributionAgreementV1(address(h.getAgreementClass(GDA)));
        PoolAdminNFT nftLogic = new PoolAdminNFT(h, gda);
        nftLogic.castrate();
        UUPSProxy proxy = new UUPSProxy();
        proxy.initializeProxy(address(nftLogic));
        PoolAdminNFT nft = PoolAdminNFT(address(proxy));
        nft.initialize("Pool Admin NFT", "PA");
        require(nft.getCodeAddress() == address(nftLogic), "NFT initialization failed");
        SuperToken token = new SuperToken(h, nft);
        token.castrate();
        SuperTokenFactory factory = new SuperTokenFactory(h, token, nftLogic, IPoolMemberNFT(address(0)));
        gov.updateContracts(h, address(0), new address[](0), address(factory), address(0));
    }

    function policyOf(Superfluid h) public view returns (ChainPolicy.Policy memory p) {
        InstantDistributionAgreementV1 ida = InstantDistributionAgreementV1(address(h.getAgreementClass(IDA)));
        // Fail closed on missing/malformed getters. No catch-and-assume-legacy policy.
        p.callbackGasLimit = h.CALLBACK_GAS_LIMIT();
        p.whitelisting = h.APP_WHITE_LISTING_ENABLED();
        p.idaFrozen = ida.NEW_ACTIVITY_FROZEN();
        p.idaSlots = ida.MAX_NUM_SUBSCRIPTIONS();
        (p.liquidationPeriod, p.patricianPeriod) = SuperfluidGovernanceBase(address(h.getGovernance()))
            .getPPPConfig(h, ISuperfluidToken(address(0)));
    }

    function upgrade() external {
        Superfluid h = _host(vm.envAddress("HOST_ADDRESS"));
        _upgrade(h, policyOf(h));
    }

    function _upgrade(Superfluid h, ChainPolicy.Policy memory next) internal {
        vm.startBroadcast(_sender());
        Superfluid hostLogic = new Superfluid(false, next.whitelisting, next.callbackGasLimit,
            address(h.SIMPLE_FORWARDER()), address(h.getERC2771Forwarder()), address(h.getSimpleACL()));
        address[] memory agreements = new address[](3);
        agreements[0] = address(new ConstantFlowAgreementV1(h));
        agreements[1] = address(new InstantDistributionAgreementV1(h, next.idaFrozen, next.idaSlots));
        GeneralDistributionAgreementV1 gda = GeneralDistributionAgreementV1(address(h.getAgreementClass(GDA)));
        agreements[2] = address(new GeneralDistributionAgreementV1(h, gda.superfluidPoolBeacon()));
        SuperfluidPool pool = new SuperfluidPool(gda);
        pool.castrate();
        address factory = _upgradeFactory(h, gda);
        address gov = address(h.getGovernance());
        DeployUtils.executeGovernanceAction(gov, abi.encodeCall(SuperfluidGovernanceBase.updateContracts,
            (h, address(hostLogic), agreements, factory, address(pool))), _govOwner(gov));
        vm.stopBroadcast();
    }

    function _upgradeFactory(Superfluid h, GeneralDistributionAgreementV1 gda) internal returns (address) {
        SuperTokenFactory oldFactory = SuperTokenFactory(address(h.getSuperTokenFactory()));
        SuperToken oldToken = SuperToken(address(oldFactory.getSuperTokenLogic()));
        PoolAdminNFT nftLogic = new PoolAdminNFT(h, gda);
        nftLogic.castrate();
        SuperToken token = new SuperToken(h, oldToken.POOL_ADMIN_NFT());
        token.castrate();
        return address(new SuperTokenFactory(h, token, nftLogic, oldFactory.POOL_MEMBER_NFT_LOGIC()));
    }

    function upgradeGovernance() external {
        Superfluid h = _host(vm.envAddress("HOST_ADDRESS"));
        address gov = address(h.getGovernance());
        // TestGovernance is deliberately not replaceable by this code-upgrade operation.
        (bool ok, bytes memory result) = gov.staticcall(abi.encodeWithSignature("getCodeAddress()"));
        require(ok && result.length == 32 && abi.decode(result, (address)) != address(0),
            "Governance logic upgrade requires GovernanceII proxy");
        require(UUPSProxiable(gov).proxiableUUID() == keccak256(
            "org.superfluid-finance.contracts.SuperfluidGovernanceII.implementation"),
            "Governance logic upgrade requires GovernanceII proxy");
        vm.startBroadcast(_sender());
        SuperfluidGovernanceII logic = new SuperfluidGovernanceII();
        logic.castrate();
        DeployUtils.executeGovernanceAction(gov, abi.encodeCall(SuperfluidGovernanceII.updateCode,
            (address(logic))), _govOwner(gov));
        vm.stopBroadcast();
    }

    function upgradeTokens(address[] calldata tokens) external {
        require(tokens.length > 0, "Explicit token list required; ALL discovery is not implemented");
        Superfluid h = _host(vm.envAddress("HOST_ADDRESS"));
        address canonical = address(h.getSuperTokenFactory().getSuperTokenLogic());
        bytes32 uuid = UUPSProxiable(canonical).proxiableUUID();
        for (uint256 i; i < tokens.length; ++i) {
            ISuperToken token = ISuperToken(tokens[i]);
            require(address(token.getHost()) == address(h), "Token belongs to another host");
            address admin = token.getAdmin();
            require(admin == address(0) || admin == address(h), "Token admin is not governed by this host");
            require(UUPSProxiable(tokens[i]).getCodeAddress() != address(0), "Token is not an upgradeable proxy");
            require(UUPSProxiable(tokens[i]).proxiableUUID() == uuid, "Token implementation UUID mismatch");
        }
        address gov = address(h.getGovernance());
        vm.startBroadcast(_sender());
        DeployUtils.executeGovernanceAction(gov, abi.encodeWithSignature("batchUpdateSuperTokenLogic(address,address[])",
            address(h), tokens), _govOwner(gov));
        vm.stopBroadcast();
    }

    function handoverACL(address targetAdmin) external {
        require(targetAdmin != address(0) && targetAdmin != _sender(), "Invalid ACL successor");
        SimpleACL acl = SimpleACL(address(_host(vm.envAddress("HOST_ADDRESS")).getSimpleACL()));
        vm.startBroadcast(_sender());
        acl.grantRole(bytes32(0), targetAdmin);
        acl.renounceRole(bytes32(0), _sender());
        vm.stopBroadcast();
    }

    function handoverGovernance(address targetOwner) external {
        require(targetOwner != address(0), "Zero governance owner");
        Superfluid h = _host(vm.envAddress("HOST_ADDRESS"));
        address gov = address(h.getGovernance());
        vm.startBroadcast(_sender());
        DeployUtils.executeGovernanceAction(gov, abi.encodeWithSignature("transferOwnership(address)", targetOwner),
            _govOwner(gov));
        vm.stopBroadcast();
    }

    /// @notice Grant first, wait for execution, then separately renounce from the old EOA/admin.
    /// Legacy multisig/Safe must use revokeResolverAdmin after grant execution instead.
    function grantResolverAdmin(address targetAdmin) external {
        require(targetAdmin != address(0), "Zero resolver admin");
        Resolver r = Resolver(vm.envAddress("RESOLVER_ADDRESS"));
        address admin = DeployUtils.getResolverAdmin(r);
        vm.startBroadcast(_sender());
        DeployUtils.executeResolverAction(address(r), abi.encodeWithSignature("grantRole(bytes32,address)",
            bytes32(0), targetAdmin), admin);
        vm.stopBroadcast();
    }

    function revokeResolverAdmin(address oldAdmin, address targetAdmin) external {
        Resolver r = Resolver(vm.envAddress("RESOLVER_ADDRESS"));
        require(oldAdmin != targetAdmin && r.hasRole(bytes32(0), targetAdmin), "Grant must execute before revocation");
        require(r.hasRole(bytes32(0), oldAdmin), "Old admin has no role");
        vm.startBroadcast(_sender());
        DeployUtils.executeResolverAction(address(r), abi.encodeWithSignature("revokeRole(bytes32,address)",
            bytes32(0), oldAdmin), oldAdmin);
        vm.stopBroadcast();
    }
}
