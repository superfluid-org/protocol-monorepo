// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {Strings} from "@openzeppelin-v5/contracts/utils/Strings.sol";

// Core contracts
import {Resolver} from "../contracts/utils/Resolver.sol";
import {Superfluid} from "../contracts/superfluid/Superfluid.sol";

// Agreement contracts
import {ConstantFlowAgreementV1} from "../contracts/agreements/ConstantFlowAgreementV1.sol";
import {InstantDistributionAgreementV1} from "../contracts/agreements/InstantDistributionAgreementV1.sol";
import {GeneralDistributionAgreementV1} from "../contracts/agreements/gdav1/GeneralDistributionAgreementV1.sol";

// SuperToken contracts
import {SuperTokenFactory} from "../contracts/superfluid/SuperTokenFactory.sol";
import {SuperToken} from "../contracts/superfluid/SuperToken.sol";
import {PoolAdminNFT} from "../contracts/agreements/gdav1/PoolAdminNFT.sol";
import {IPoolMemberNFT} from "../contracts/superfluid/SuperToken.sol";

// Forwarder contracts
import {SimpleForwarder} from "../contracts/utils/SimpleForwarder.sol";
import {ERC2771Forwarder} from "../contracts/utils/ERC2771Forwarder.sol";
import {SimpleACL} from "../contracts/utils/SimpleACL.sol";

// Pool contracts
import {SuperfluidPool} from "../contracts/agreements/gdav1/SuperfluidPool.sol";
import {SuperfluidUpgradeableBeacon} from "../contracts/upgradability/SuperfluidUpgradeableBeacon.sol";
import {IPoolAdminNFT} from "../contracts/interfaces/agreements/gdav1/IPoolAdminNFT.sol";

// Admin detection interfaces
import {IMultiSigWallet} from "../contracts/interfaces/utils/IMultiSigWallet.sol";
import {ISafe} from "../contracts/interfaces/utils/ISafe.sol";
import {Ownable} from "@openzeppelin-v5/contracts/access/Ownable.sol";
import {ISuperfluidGovernance} from "../contracts/interfaces/superfluid/ISuperfluidGovernance.sol";

contract DeployFramework is Script {
    // Configuration struct for upgrades
    struct DeploymentConfig {
        string version;
        address deployer;
        address existingHost;
        address existingResolver;
    }

    // Existing deployed contracts struct (loaded for upgrades)
    struct DeployedContracts {
        Resolver resolver;
        Superfluid host;
        ISuperfluidGovernance governance;
        ConstantFlowAgreementV1 cfa;
        InstantDistributionAgreementV1 ida;
        GeneralDistributionAgreementV1 gda;
        SuperTokenFactory factory;
        SuperfluidUpgradeableBeacon poolBeacon;
        SuperfluidPool poolLogic;
        SuperToken superTokenLogic;
        PoolAdminNFT poolAdminNFT;
    }

    // Newly deployed contracts for upgrades
    struct NewDeployedContracts {
        Superfluid hostLogic;
        ConstantFlowAgreementV1 cfaLogic;
        //InstantDistributionAgreementV1 idaLogic;
        GeneralDistributionAgreementV1 gdaLogic;
        SuperTokenFactory factoryLogic;
        SuperToken superTokenLogic;
        SuperfluidPool poolLogic;
    }

    function run() external {
        DeploymentConfig memory config = _loadConfig();

        console.log("======== Upgrading Superfluid Framework ========");
        console.log("Release version: %s", config.version);
        console.log("Deployer: %s", config.deployer);

        // Start broadcasting - Forge will use the account specified via --account flag
        vm.startBroadcast();

        _deployUpgrade(config);

        vm.stopBroadcast();

        console.log("======== Upgrade Complete ========");
    }

    function _loadConfig() internal view returns (DeploymentConfig memory config) {
        config.version = vm.envOr("RELEASE_VERSION", string("v1"));
        config.existingHost = vm.envOr("HOST_ADDRESS", address(0));
        config.existingResolver = vm.envOr("RESOLVER_ADDRESS", address(0));
        config.deployer = msg.sender;
    }

    function _deployUpgrade(DeploymentConfig memory config) internal returns (DeployedContracts memory contracts) {
        console.log("Deploying upgrade...");
        
        // Validate required addresses for upgrade
        require(config.existingHost != address(0), "HOST_ADDRESS must be set");
        require(config.existingResolver != address(0), "RESOLVER_ADDRESS must be set");
        
        // Load existing contracts
        contracts = _loadExistingContracts(config);
        
        // Deploy all new contract logics
        NewDeployedContracts memory newContracts = _deployAllNewContracts(config, contracts);
        
        // Create governance action to update contracts
        _createGovernanceAction(contracts, newContracts);
        
        // Update resolver with version string
        _updateResolver(contracts, config);
        
        console.log("Upgrade deployment completed successfully");
    }

    function _loadExistingContracts(DeploymentConfig memory config) internal returns (DeployedContracts memory contracts) {
        // Load existing contracts
        contracts.host = Superfluid(config.existingHost);
        contracts.resolver = Resolver(config.existingResolver);

        // get from host: governance, factory, cfa, ida, gda
        contracts.governance = ISuperfluidGovernance(address(contracts.host.getGovernance()));
        contracts.factory = SuperTokenFactory(address(contracts.host.getSuperTokenFactory()));
        contracts.cfa = ConstantFlowAgreementV1(address(contracts.host.getAgreementClass(
            keccak256("org.superfluid-finance.agreements.ConstantFlowAgreement.v1")
        )));
        contracts.ida = InstantDistributionAgreementV1(address(contracts.host.getAgreementClass(
            keccak256("org.superfluid-finance.agreements.InstantDistributionAgreement.v1")
        )));
        contracts.gda = GeneralDistributionAgreementV1(address(contracts.host.getAgreementClass(
            keccak256("org.superfluid-finance.agreements.GeneralDistributionAgreement.v1")
        )));

        // get from factory: superTokenLogic, poolAdminNFT
        contracts.superTokenLogic = SuperToken(address(contracts.factory.getSuperTokenLogic()));

        // get from superToken: poolAdminNFT (proxy)
        contracts.poolAdminNFT = PoolAdminNFT(address(contracts.superTokenLogic.POOL_ADMIN_NFT()));

        // get from gda: superfluidPoolBeacon
        contracts.poolBeacon = SuperfluidUpgradeableBeacon(contracts.gda.superfluidPoolBeacon());

        // get from poolBeacon: poolLogic
        contracts.poolLogic = SuperfluidPool(contracts.poolBeacon.implementation());

        // TODO verify:
        // - factory logic in host matches factory logic in proxy
        // - poolAdminNFT logic in factory matches proxy logic

        console.log("Loaded existing contracts:");
        console.log("  Resolver: %s", address(contracts.resolver));
        console.log("  Host: %s", address(contracts.host));
        console.log("  Governance: %s", address(contracts.governance));
        console.log("  Factory: %s", address(contracts.factory));
        console.log("  SuperToken Logic: %s", address(contracts.superTokenLogic));
        console.log("  Pool Admin NFT: %s", address(contracts.poolAdminNFT));
        console.log("  Pool Beacon: %s", address(contracts.poolBeacon));
        console.log("  Pool Logic: %s", address(contracts.poolLogic));
    }

    /**
     * @dev Deploy all new contract logics for upgrade
     * @param config Deployment configuration
     * @param existingContracts Existing deployed contracts
     * @return newContracts All newly deployed contract logics
     */
    function _deployAllNewContracts(
        DeploymentConfig memory config,
        DeployedContracts memory existingContracts
    ) internal returns (NewDeployedContracts memory newContracts) {
        console.log("Deploying all new contract logics...");
        
        // Validate existing contracts are properly loaded
        require(address(existingContracts.host) != address(0), "Host not loaded");
        require(address(existingContracts.poolBeacon) != address(0), "Pool beacon not loaded");
        require(address(existingContracts.poolAdminNFT) != address(0), "Pool admin NFT not loaded");
        
        // Deploy new host logic
        newContracts.hostLogic = _deployNewHostLogic(config, existingContracts.host);
        
        // Deploy new agreement logics
        newContracts.cfaLogic = new ConstantFlowAgreementV1(existingContracts.host);
        console.log("New CFA logic deployed at %s", address(newContracts.cfaLogic));

        // we assume IDA to not change anymore because deprecated
        console.log("IDA logic not deployed (skipping because deprecated)");
        // newContracts.idaLogic = new InstantDistributionAgreementV1(existingContracts.host);
        // console.log("New IDA logic deployed at %s", address(newContracts.idaLogic));

        console.log("  GDA dependencies:");
        console.log("  Pool Beacon: %s", address(existingContracts.poolBeacon));
        
        // Deploy new GDA logic
        newContracts.gdaLogic = new GeneralDistributionAgreementV1(
            existingContracts.host, 
            existingContracts.poolBeacon
        );
        console.log("New GDA logic deployed at %s", address(newContracts.gdaLogic));
        
        // Deploy new SuperToken logic
        newContracts.superTokenLogic = new SuperToken(
            existingContracts.host, 
            existingContracts.poolAdminNFT
        );
        console.log("New SuperToken logic deployed at %s", address(newContracts.superTokenLogic));

        // Get poolAdminNFT logic
        address poolAdminNFTLogic = existingContracts.poolAdminNFT.getCodeAddress();
        // Get poolMemberNFT logic - deprecated
        // We still need to forward the set address, otherwise when upgrading a deployment
        // which still has the safety check in `updateCode`, it would revert if setting the zero address.
        address poolMemberNFTLogic = address(existingContracts.factory.POOL_MEMBER_NFT_LOGIC());
        
        // Deploy new SuperToken factory logic
        newContracts.factoryLogic = new SuperTokenFactory(
            existingContracts.host,
            newContracts.superTokenLogic,
            IPoolAdminNFT(poolAdminNFTLogic),
            IPoolMemberNFT(poolMemberNFTLogic)
        );
        console.log("New SuperToken factory logic deployed at %s", address(newContracts.factoryLogic));
        
        // Deploy new SuperfluidPool logic
        newContracts.poolLogic = new SuperfluidPool(existingContracts.gda);
        newContracts.poolLogic.castrate();
        console.log(
            "New SuperfluidPool logic deployed at %s", 
            address(newContracts.poolLogic)
        );
        
        // Validate all contracts were deployed successfully
        require(address(newContracts.hostLogic) != address(0), "Host logic deployment failed");
        require(address(newContracts.cfaLogic) != address(0), "CFA logic deployment failed");
        //require(address(newContracts.idaLogic) != address(0), "IDA logic deployment failed");
        require(address(newContracts.gdaLogic) != address(0), "GDA logic deployment failed");
        require(address(newContracts.superTokenLogic) != address(0), "SuperToken logic deployment failed");
        require(address(newContracts.factoryLogic) != address(0), "Factory logic deployment failed");
        require(address(newContracts.poolLogic) != address(0), "Pool logic deployment failed");
        
        console.log("All new contract logics deployed successfully");
    }

    function _deployNewHostLogic(DeploymentConfig memory, Superfluid host) internal returns (Superfluid newHostLogic) {
        // collect constructor args from existing host
        address simpleAclAddress = address(host.getSimpleACL());
        address simpleForwarderAddress = address(host.SIMPLE_FORWARDER());
        address erc2771ForwarderAddress = address(host.getERC2771Forwarder());
        uint256 prevCallbackGasLimit = host.CALLBACK_GAS_LIMIT();
        bool nonUpgradable = host.NON_UPGRADABLE_DEPLOYMENT();
        bool appWhiteListing = host.APP_WHITE_LISTING_ENABLED();
        
        console.log("Collected host constructor args:");
        console.log("  SimpleACL: %s", simpleAclAddress);
        console.log("  SimpleForwarder: %s", simpleForwarderAddress);
        console.log("  ERC2771Forwarder: %s", erc2771ForwarderAddress);
        console.log("  CallbackGasLimit: %s", prevCallbackGasLimit);
        console.log("  NonUpgradable: %s", nonUpgradable);
        console.log("  AppWhiteListing: %s", appWhiteListing);
        
        // TODO: add a way to change the callback gas limit
        uint256 newCallbackGasLimit = prevCallbackGasLimit;
        // Validate callback gas limit doesn't decrease
        if (prevCallbackGasLimit > newCallbackGasLimit) {
            revert("Cannot decrease app callback gas limit");
        }
        
        // deploy new logic with collected arguments
        newHostLogic = new Superfluid(
            nonUpgradable,
            appWhiteListing,
            uint64(newCallbackGasLimit),
            simpleForwarderAddress,
            erc2771ForwarderAddress,
            simpleAclAddress
        );
        console.log("New Superfluid host logic deployed at %s", address(newHostLogic));
    }


    /**
     * @dev Create governance action to update contracts
     * @param existingContracts Existing deployed contracts
     * @param newContracts Newly deployed contract logics
     */
    function _createGovernanceAction(
        DeployedContracts memory existingContracts,
        NewDeployedContracts memory newContracts
    ) internal {
        // Validate inputs
        require(address(existingContracts.host) != address(0), "Existing host is zero address");
        require(address(newContracts.hostLogic) != address(0), "New host logic is zero address");
        require(address(newContracts.cfaLogic) != address(0), "New CFA logic is zero address");
        //require(address(newContracts.idaLogic) != address(0), "New IDA logic is zero address");
        require(address(newContracts.gdaLogic) != address(0), "New GDA logic is zero address");
        require(address(newContracts.factoryLogic) != address(0), "New factory logic is zero address");
        require(address(newContracts.poolLogic) != address(0), "New pool logic is zero address");
        
        // Prepare governance action arguments aligned with ISuperfluidGovernance.updateContracts
        address[] memory agreementClassNewLogics = new address[](2);
        agreementClassNewLogics[0] = address(newContracts.cfaLogic);
        //agreementClassNewLogics[1] = address(newContracts.idaLogic);
        agreementClassNewLogics[1] = address(newContracts.gdaLogic);
        
        // Create governance action
        console.log("Creating governance action...");
        console.log("  Governance action: updateContracts");
        console.log("    Host: %s", address(existingContracts.host));
        console.log("    New Host Logic: %s", address(newContracts.hostLogic));
        console.log("    New CFA Logic: %s", address(newContracts.cfaLogic));
        //console.log("  New IDA Logic: %s", address(newContracts.idaLogic));
        console.log("    New GDA Logic: %s", address(newContracts.gdaLogic));
        console.log("    New Factory Logic: %s", address(newContracts.factoryLogic));
        console.log("    New Pool Logic: %s", address(newContracts.poolLogic));
        
        // Get governance contract and admin address
        address governanceAddr = address(existingContracts.host.getGovernance());
        require(governanceAddr != address(0), "Governance address is zero");
        
        address governanceAdmin = Ownable(governanceAddr).owner();
        require(governanceAdmin != address(0), "Governance admin is zero");
        
        // Encode the updateContracts call with properly aligned arguments
        bytes memory actionData = abi.encodeWithSelector(
            ISuperfluidGovernance.updateContracts.selector,
            existingContracts.host,                    // host
            address(newContracts.hostLogic),            // hostNewLogic
            agreementClassNewLogics,                    // agreementClassNewLogics
            address(newContracts.factoryLogic),         // superTokenFactoryNewLogic
            address(newContracts.poolLogic)              // beaconNewLogic
        );
        
        // Execute governance action
        _executeGovernanceAction(governanceAddr, actionData, governanceAdmin);
    }


    function _updateResolver(DeployedContracts memory contracts, DeploymentConfig memory config) internal {
        string memory versionString = vm.envOr("VERSION_STRING", string(""));
        require(bytes(versionString).length > 0, "VERSION_STRING not set");
        
        string memory versionKey = string(abi.encodePacked("versionString.", config.version));
        
        // Get and log previous version string
        address prevEncodedVersion = contracts.resolver.get(versionKey);
        string memory prevVersionString = _pseudoAddressToVersionString(prevEncodedVersion);
        console.log("previous versionString: %s", prevVersionString);
        console.log("new versionString:      %s", versionString);
        
        // Encode and set new version string
        address encodedVersionString = _versionStringToPseudoAddress(versionString);
        _setResolverValue(contracts.resolver, versionKey, encodedVersionString);
        
        console.log("Resolver updated with new version string");
    }
    
    /// @dev Encode version string to pseudo address: [x]x.[y]y.[z]z-rrrr... -> 0x000000000000000000MMPPSSRRRR...
    function _versionStringToPseudoAddress(string memory versionString) internal pure returns (address) {
        bytes memory v = bytes(versionString);
        uint dot1; uint dot2; uint dash;
        for (uint i = 0; i < v.length; i++) {
            if (v[i] == '.' && dot1 == 0) dot1 = i;
            else if (v[i] == '.' && dot2 == 0) dot2 = i;
            else if (v[i] == '-') { dash = i; break; }
        }
        require(dot1 > 0 && dot2 > dot1 && dash > dot2, "Invalid version format");
        
        // Parse version numbers and build hex string: "000000000000000000" + MM + PP + SS + revision
        bytes memory hexStr = abi.encodePacked(
            "000000000000000000",
            _pad2(v, 0, dot1),
            _pad2(v, dot1 + 1, dot2),
            _pad2(v, dot2 + 1, dash),
            _slice(v, dash + 1, v.length)
        );
        
        // Convert hex string to address
        uint160 result;
        for (uint i = 0; i < 40 && i < hexStr.length; i++) {
            result = result * 16 + _hexVal(hexStr[i]);
        }
        return address(result);
    }
    
    /// @dev Decode pseudo address back to version string
    function _pseudoAddressToVersionString(address addr) internal pure returns (string memory) {
        if (addr == address(0)) return "";
        bytes memory b = abi.encodePacked(addr);
        for (uint i = 0; i < 9; i++) if (b[i] != 0) return ""; // Check prefix zeros
        
        // Convert to hex and parse: bytes 9-11 contain MM PP SS as hex chars
        bytes memory hexStr = bytes(Strings.toHexString(uint160(addr), 20));
        uint maj = (uint8(hexStr[20]) - 48) * 10 + (uint8(hexStr[21]) - 48);
        uint min = (uint8(hexStr[22]) - 48) * 10 + (uint8(hexStr[23]) - 48);
        uint pat = (uint8(hexStr[24]) - 48) * 10 + (uint8(hexStr[25]) - 48);
        
        // Extract revision (trim trailing zeros)
        uint len = 16;
        for (uint i = 41; i >= 26 && i < 42; i--) if (hexStr[i] != '0') { len = i - 25; break; }
        
        return string(abi.encodePacked(
            Strings.toString(maj), ".",
            Strings.toString(min), ".",
            Strings.toString(pat), "-",
            _slice(hexStr, 26, 26 + len)
        ));
    }
    
    // Helpers
    function _pad2(bytes memory s, uint start, uint end) private pure returns (bytes memory) {
        uint n; for (uint i = start; i < end; i++) n = n * 10 + uint8(s[i]) - 48;
        return bytes(n < 10 ? string(abi.encodePacked("0", Strings.toString(n))) : Strings.toString(n));
    }
    
    function _slice(bytes memory s, uint start, uint end) private pure returns (bytes memory) {
        bytes memory r = new bytes(end - start);
        for (uint i = 0; i < r.length; i++) r[i] = s[start + i];
        return r;
    }
    
    function _hexVal(bytes1 c) private pure returns (uint8) {
        uint8 v = uint8(c);
        if (v >= 48 && v <= 57) return v - 48;
        if (v >= 97 && v <= 102) return v - 87;
        if (v >= 65 && v <= 70) return v - 55;
        revert("Invalid hex char");
    }

    /****************************************************************
     * Admin type detection and action execution utilities
     ****************************************************************/
    
    /**
     * @dev Admin type enum
     */
    enum AdminType {
        OWNABLE,
        MULTISIG,
        SAFE
    }
    
    /**
     * @dev Probes the given account to see what kind of admin it is
     * @param account The account address to probe
     * @return AdminType The detected admin type
     */
    function _autodetectAdminType(address account) public view returns (AdminType) {
        console.log("  Auto detecting admin type of", account);
        
        // Check if account is a contract
        if (account.code.length == 0) {
            console.log("  Account has no code, assuming ownable contract.");
            return AdminType.OWNABLE;
        }
        
        // Try to detect MultiSig wallet
        try IMultiSigWallet(account).required() returns (uint256) {
            console.log("  Detected MultiSig wallet");
            return AdminType.MULTISIG;
        } catch {
            console.log("  Not detecting MultiSig wallet fingerprint.");
        }
        
        // Try to detect Safe wallet
        try ISafe(account).VERSION() returns (string memory version) {
            console.log("  Detected Safe version", version);
            return AdminType.SAFE;
        } catch {
            console.log("  Not detecting Safe fingerprint.");
        }
        
        revert("Unknown admin contract type");
    }
    
    /**
     * @dev Execute admin action based on admin type (shared logic for governance and resolver)
     * @param targetContract The target contract address
     * @param actionData The encoded action data
     * @param adminAddress The admin address
     * @param actionType The type of action for logging (e.g., "governance", "resolver")
     */
    function _executeAdminAction(
        address targetContract,
        bytes memory actionData,
        address adminAddress,
        string memory actionType
    ) internal {
        console.log("  %s address: %s", actionType, targetContract);
        console.log("  %s admin: %s", actionType, adminAddress);
        
        AdminType adminType = _autodetectAdminType(adminAddress);
        
        if (adminType == AdminType.MULTISIG) {
            console.log("  %s Admin Type: MultiSig", actionType);
            IMultiSigWallet multis = IMultiSigWallet(adminAddress);
            console.log("  MultiSig address: %s", adminAddress);
            console.log("  MultiSig data:");
            console.logBytes(actionData);
            console.log("  Sending %s action to multisig...", actionType);
            multis.submitTransaction(targetContract, 0, actionData);
            console.log("*** %s action sent, but it may still need confirmation(s). ***", actionType);
            
        } else if (adminType == AdminType.OWNABLE) {
            console.log("  %s Admin Type: Direct Ownership (default)", actionType);
            console.log("  Executing %s action...", actionType);
            // For ownable contracts, we need to call the function directly
            (bool success, bytes memory returnData) = targetContract.call(actionData);
            require(success, string(abi.encodePacked(actionType, " action failed")));
            console.log("*** %s action executed. ***", actionType);
            
        } else if (adminType == AdminType.SAFE) {
            console.log("  %s Admin Type: Safe", actionType);
            // TODO: Implement Safe transaction execution
            console.log("  Safe admin type detected but not yet implemented");
            revert("Safe admin type not yet implemented");
            
        } else {
            revert("Unknown admin type");
        }
    }
    
    /**
     * @dev Execute governance action based on admin type
     * @param governance The governance contract
     * @param actionData The encoded action data
     * @param adminAddress The admin address
     */
    function _executeGovernanceAction(
        address governance, 
        bytes memory actionData, 
        address adminAddress
    ) internal {
        _executeAdminAction(governance, actionData, adminAddress, "Governance");
    }
    
    /**
     * @dev Execute resolver action based on admin type
     * @param resolver The resolver contract
     * @param actionData The encoded action data
     * @param adminAddress The admin address
     */
    function _executeResolverAction(
        address resolver,
        bytes memory actionData,
        address adminAddress
    ) internal {
        _executeAdminAction(resolver, actionData, adminAddress, "Resolver");
    }
    
    /**
     * @dev Get resolver admin address from AccessControlEnumerable
     * @param resolver The resolver contract
     * @return adminAddress The admin address
     */
    function _getResolverAdmin(Resolver resolver) internal view returns (address adminAddress) {
        bytes32 ADMIN_ROLE = 0x0000000000000000000000000000000000000000000000000000000000000000; // DEFAULT_ADMIN_ROLE
        uint256 adminCount = resolver.getRoleMemberCount(ADMIN_ROLE);
        
        if (adminCount > 0) {
            // Get the last admin (following the legacy pattern)
            adminAddress = resolver.getRoleMember(ADMIN_ROLE, adminCount - 1);
        } else {
            console.log("!!! resolver.getRoleMemberCount() returned 0. Using deployer as resolver admin.");
            adminAddress = msg.sender;
        }
    }
    
    /**
     * @dev Set resolver key-value with multisig support
     * @param resolver The resolver contract
     * @param key The key to set
     * @param value The value to set
     */
    function _setResolverValue(Resolver resolver, string memory key, address value) internal {
        console.log("Setting resolver %s -> %s ...", key, value);
        
        // Get resolver admin
        address resolverAdmin = _getResolverAdmin(resolver);
        
        // Encode the set call
        bytes memory actionData = abi.encodeWithSelector(
            resolver.set.selector,
            key,
            value
        );
        
        // Execute resolver action
        _executeResolverAction(address(resolver), actionData, resolverAdmin);
    }
}