// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";

// Utils
import {DeployUtils} from "./utils/DeployUtils.sol";

// Core contracts
import {Superfluid} from "../contracts/superfluid/Superfluid.sol";
import {ISuperfluid} from "../contracts/interfaces/superfluid/ISuperfluid.sol";
import {ISuperfluidToken} from "../contracts/interfaces/superfluid/ISuperfluidToken.sol";
import {ISuperToken} from "../contracts/interfaces/superfluid/ISuperToken.sol";

// Governance interface
import {Ownable} from "@openzeppelin-v5/contracts/access/Ownable.sol";
import {ISuperfluidGovernance} from "../contracts/interfaces/superfluid/ISuperfluidGovernance.sol";
import {SuperfluidGovernanceBase} from "../contracts/gov/SuperfluidGovernanceBase.sol";

contract GovAction is Script {
    using DeployUtils for *;

    // Base configuration (common to all actions)
    struct BaseConfig {
        address host;
        ISuperfluidGovernance governance;
        address governanceAdmin;
    }

    function run() external {
        string memory actionTypeStr = vm.envOr("ACTION_TYPE", string(""));
        require(bytes(actionTypeStr).length > 0, "ACTION_TYPE must be set");

        console.log("======== Executing Governance Action ========");
        console.log("Action Type: %s", actionTypeStr);

        // Load base configuration
        BaseConfig memory baseConfig = _loadBaseConfig();

        // Route to appropriate action handler
        _executeAction(actionTypeStr, baseConfig);

        console.log("======== Governance Action Complete ========");
    }

    function _loadBaseConfig() internal view returns (BaseConfig memory config) {
        config.host = vm.envOr("HOST_ADDRESS", address(0));
        require(config.host != address(0), "HOST_ADDRESS must be set");

        Superfluid host = Superfluid(config.host);
        config.governance = ISuperfluidGovernance(address(host.getGovernance()));
        config.governanceAdmin = Ownable(address(config.governance)).owner();

        console.log("Host: %s", config.host);
        console.log("Governance: %s", address(config.governance));
        console.log("Governance Admin: %s", config.governanceAdmin);
    }

    function _executeAction(string memory actionTypeStr, BaseConfig memory baseConfig) internal {
        function(BaseConfig memory) internal handler = _getActionHandler(actionTypeStr);
        handler(baseConfig);
    }

    function _getActionHandler(string memory actionTypeStr) internal pure returns (function(BaseConfig memory) internal) {
        bytes32 hash = keccak256(bytes(actionTypeStr));

        // Single enumeration point: map action strings directly to handlers
        if (hash == keccak256(bytes("setTokenMinimumDeposit"))) return _executeSetTokenMinimumDeposit;
        if (hash == keccak256(bytes("set3PsConfig"))) return _executeSet3PsConfig;
        if (hash == keccak256(bytes("clear3PsConfig"))) return _executeClear3PsConfig;
        if (hash == keccak256(bytes("setRewardAddress"))) return _executeSetRewardAddress;
        if (hash == keccak256(bytes("clearRewardAddress"))) return _executeClearRewardAddress;
        if (hash == keccak256(bytes("enableTrustedForwarder"))) return _executeEnableTrustedForwarder;
        if (hash == keccak256(bytes("disableTrustedForwarder"))) return _executeDisableTrustedForwarder;
        if (hash == keccak256(bytes("changeSuperTokenAdmin"))) return _executeChangeSuperTokenAdmin;
        if (hash == keccak256(bytes("batchChangeSuperTokenAdmin"))) return _executeBatchChangeSuperTokenAdmin;
        if (hash == keccak256(bytes("registerAgreementClass"))) return _executeRegisterAgreementClass;
        if (hash == keccak256(bytes("replaceGovernance"))) return _executeReplaceGovernance;

        revert("Unknown action type");
    }

    // ============ Action Handlers ============

    function _executeSetTokenMinimumDeposit(BaseConfig memory baseConfig) internal {
        string memory tokenAddrStr = vm.envOr("TOKEN_ADDRESS", string(""));
        require(bytes(tokenAddrStr).length > 0, "TOKEN_ADDRESS must be set");
        address token = vm.parseAddress(tokenAddrStr);

        string memory minDepositStr = vm.envOr("MINIMUM_DEPOSIT", string(""));
        require(bytes(minDepositStr).length > 0, "MINIMUM_DEPOSIT must be set");
        uint256 minimumDeposit = vm.parseUint(minDepositStr);

        console.log("Token: %s", token);
        console.log("Minimum Deposit: %s", minimumDeposit);

        bytes memory actionData = abi.encodeWithSelector(
            SuperfluidGovernanceBase.setSuperTokenMinimumDeposit.selector,
            ISuperfluid(baseConfig.host),
            ISuperfluidToken(token),
            minimumDeposit
        );

        DeployUtils.executeGovernanceAction(
            address(baseConfig.governance),
            actionData,
            baseConfig.governanceAdmin
        );
    }

    function _executeSet3PsConfig(BaseConfig memory baseConfig) internal {
        string memory tokenAddrStr = vm.envOr("TOKEN_ADDRESS", string(""));
        require(bytes(tokenAddrStr).length > 0, "TOKEN_ADDRESS must be set");
        address token = vm.parseAddress(tokenAddrStr);

        string memory liquidationPeriodStr = vm.envOr("LIQUIDATION_PERIOD", string(""));
        require(bytes(liquidationPeriodStr).length > 0, "LIQUIDATION_PERIOD must be set");
        uint256 liquidationPeriod = vm.parseUint(liquidationPeriodStr);

        string memory patricianPeriodStr = vm.envOr("PATRICIAN_PERIOD", string(""));
        require(bytes(patricianPeriodStr).length > 0, "PATRICIAN_PERIOD must be set");
        uint256 patricianPeriod = vm.parseUint(patricianPeriodStr);

        console.log("Token: %s", token);
        console.log("Liquidation Period: %s", liquidationPeriod);
        console.log("Patrician Period: %s", patricianPeriod);

        bytes memory actionData = abi.encodeWithSelector(
            SuperfluidGovernanceBase.setPPPConfig.selector,
            ISuperfluid(baseConfig.host),
            ISuperfluidToken(token),
            liquidationPeriod,
            patricianPeriod
        );

        DeployUtils.executeGovernanceAction(
            address(baseConfig.governance),
            actionData,
            baseConfig.governanceAdmin
        );
    }

    function _executeClear3PsConfig(BaseConfig memory baseConfig) internal {
        string memory tokenAddrStr = vm.envOr("TOKEN_ADDRESS", string(""));
        require(bytes(tokenAddrStr).length > 0, "TOKEN_ADDRESS must be set");
        address token = vm.parseAddress(tokenAddrStr);

        console.log("Token: %s", token);

        bytes memory actionData = abi.encodeWithSelector(
            SuperfluidGovernanceBase.clearPPPConfig.selector,
            ISuperfluid(baseConfig.host),
            ISuperfluidToken(token)
        );

        DeployUtils.executeGovernanceAction(
            address(baseConfig.governance),
            actionData,
            baseConfig.governanceAdmin
        );
    }

    function _executeSetRewardAddress(BaseConfig memory baseConfig) internal {
        string memory tokenAddrStr = vm.envOr("TOKEN_ADDRESS", string(""));
        require(bytes(tokenAddrStr).length > 0, "TOKEN_ADDRESS must be set");
        address token = vm.parseAddress(tokenAddrStr);

        string memory rewardAddrStr = vm.envOr("REWARD_ADDRESS", string(""));
        require(bytes(rewardAddrStr).length > 0, "REWARD_ADDRESS must be set");
        address rewardAddress = vm.parseAddress(rewardAddrStr);

        console.log("Token: %s", token);
        console.log("Reward Address: %s", rewardAddress);

        bytes memory actionData = abi.encodeWithSelector(
            SuperfluidGovernanceBase.setRewardAddress.selector,
            ISuperfluid(baseConfig.host),
            ISuperfluidToken(token),
            rewardAddress
        );

        DeployUtils.executeGovernanceAction(
            address(baseConfig.governance),
            actionData,
            baseConfig.governanceAdmin
        );
    }

    function _executeClearRewardAddress(BaseConfig memory baseConfig) internal {
        string memory tokenAddrStr = vm.envOr("TOKEN_ADDRESS", string(""));
        require(bytes(tokenAddrStr).length > 0, "TOKEN_ADDRESS must be set");
        address token = vm.parseAddress(tokenAddrStr);

        console.log("Token: %s", token);

        bytes memory actionData = abi.encodeWithSelector(
            SuperfluidGovernanceBase.clearRewardAddress.selector,
            ISuperfluid(baseConfig.host),
            ISuperfluidToken(token)
        );

        DeployUtils.executeGovernanceAction(
            address(baseConfig.governance),
            actionData,
            baseConfig.governanceAdmin
        );
    }

    function _executeEnableTrustedForwarder(BaseConfig memory baseConfig) internal {
        string memory tokenAddrStr = vm.envOr("TOKEN_ADDRESS", string(""));
        require(bytes(tokenAddrStr).length > 0, "TOKEN_ADDRESS must be set");
        address token = vm.parseAddress(tokenAddrStr);

        string memory forwarderAddrStr = vm.envOr("FORWARDER_ADDRESS", string(""));
        require(bytes(forwarderAddrStr).length > 0, "FORWARDER_ADDRESS must be set");
        address forwarderAddress = vm.parseAddress(forwarderAddrStr);

        console.log("Token: %s", token);
        console.log("Forwarder Address: %s", forwarderAddress);

        bytes memory actionData = abi.encodeWithSelector(
            SuperfluidGovernanceBase.enableTrustedForwarder.selector,
            ISuperfluid(baseConfig.host),
            ISuperfluidToken(token),
            forwarderAddress
        );

        DeployUtils.executeGovernanceAction(
            address(baseConfig.governance),
            actionData,
            baseConfig.governanceAdmin
        );
    }

    function _executeDisableTrustedForwarder(BaseConfig memory baseConfig) internal {
        string memory tokenAddrStr = vm.envOr("TOKEN_ADDRESS", string(""));
        require(bytes(tokenAddrStr).length > 0, "TOKEN_ADDRESS must be set");
        address token = vm.parseAddress(tokenAddrStr);

        string memory forwarderAddrStr = vm.envOr("FORWARDER_ADDRESS", string(""));
        require(bytes(forwarderAddrStr).length > 0, "FORWARDER_ADDRESS must be set");
        address forwarderAddress = vm.parseAddress(forwarderAddrStr);

        console.log("Token: %s", token);
        console.log("Forwarder Address: %s", forwarderAddress);

        bytes memory actionData = abi.encodeWithSelector(
            SuperfluidGovernanceBase.disableTrustedForwarder.selector,
            ISuperfluid(baseConfig.host),
            ISuperfluidToken(token),
            forwarderAddress
        );

        DeployUtils.executeGovernanceAction(
            address(baseConfig.governance),
            actionData,
            baseConfig.governanceAdmin
        );
    }

    function _executeChangeSuperTokenAdmin(BaseConfig memory baseConfig) internal {
        string memory tokenAddrStr = vm.envOr("TOKEN_ADDRESS", string(""));
        require(bytes(tokenAddrStr).length > 0, "TOKEN_ADDRESS must be set");
        address token = vm.parseAddress(tokenAddrStr);

        string memory newAdminStr = vm.envOr("NEW_ADMIN", string(""));
        require(bytes(newAdminStr).length > 0, "NEW_ADMIN must be set");
        address newAdmin = vm.parseAddress(newAdminStr);

        console.log("Token: %s", token);
        console.log("New Admin: %s", newAdmin);

        bytes memory actionData = abi.encodeWithSelector(
            SuperfluidGovernanceBase.changeSuperTokenAdmin.selector,
            ISuperfluid(baseConfig.host),
            ISuperToken(token),
            newAdmin
        );

        DeployUtils.executeGovernanceAction(
            address(baseConfig.governance),
            actionData,
            baseConfig.governanceAdmin
        );
    }

    function _executeBatchChangeSuperTokenAdmin(BaseConfig memory baseConfig) internal {
        string memory tokensJson = vm.envOr("TOKEN_ADDRESSES_JSON", string(""));
        string memory adminsJson = vm.envOr("NEW_ADMINS_JSON", string(""));

        if (bytes(tokensJson).length > 0 && bytes(adminsJson).length > 0) {
            address[] memory tokenAddrs = abi.decode(vm.parseJson(tokensJson), (address[]));
            address[] memory adminAddrs = abi.decode(vm.parseJson(adminsJson), (address[]));

            require(tokenAddrs.length == adminAddrs.length, "TOKEN_ADDRESSES and NEW_ADMINS must have same length");

            ISuperToken[] memory tokens = new ISuperToken[](tokenAddrs.length);
            for (uint256 i = 0; i < tokenAddrs.length; i++) {
                tokens[i] = ISuperToken(tokenAddrs[i]);
            }

            console.log("Tokens count: %s", tokens.length);
            console.log("Admins count: %s", adminAddrs.length);

            bytes memory actionData = abi.encodeWithSelector(
                SuperfluidGovernanceBase.batchChangeSuperTokenAdmin.selector,
                ISuperfluid(baseConfig.host),
                tokens,
                adminAddrs
            );

            DeployUtils.executeGovernanceAction(
                address(baseConfig.governance),
                actionData,
                baseConfig.governanceAdmin
            );
        } else {
            revert("For batch operations, use TOKEN_ADDRESSES_JSON and NEW_ADMINS_JSON with JSON arrays");
        }
    }

    function _executeRegisterAgreementClass(BaseConfig memory baseConfig) internal {
        string memory agreementClassStr = vm.envOr("AGREEMENT_CLASS", string(""));
        require(bytes(agreementClassStr).length > 0, "AGREEMENT_CLASS must be set");
        address agreementClass = vm.parseAddress(agreementClassStr);

        console.log("Agreement Class: %s", agreementClass);

        bytes memory actionData = abi.encodeWithSelector(
            ISuperfluidGovernance.registerAgreementClass.selector,
            ISuperfluid(baseConfig.host),
            agreementClass
        );

        DeployUtils.executeGovernanceAction(
            address(baseConfig.governance),
            actionData,
            baseConfig.governanceAdmin
        );
    }

    function _executeReplaceGovernance(BaseConfig memory baseConfig) internal {
        string memory newGovStr = vm.envOr("NEW_GOVERNANCE", string(""));
        require(bytes(newGovStr).length > 0, "NEW_GOVERNANCE must be set");
        address newGov = vm.parseAddress(newGovStr);

        console.log("New Governance: %s", newGov);

        bytes memory actionData = abi.encodeWithSelector(
            ISuperfluidGovernance.replaceGovernance.selector,
            ISuperfluid(baseConfig.host),
            newGov
        );

        DeployUtils.executeGovernanceAction(
            address(baseConfig.governance),
            actionData,
            baseConfig.governanceAdmin
        );
    }
}
