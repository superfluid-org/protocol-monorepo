// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Script} from "forge-std/Script.sol";
import {DeployUtils} from "./utils/DeployUtils.sol";
import {ISuperfluid} from "../contracts/interfaces/superfluid/ISuperfluid.sol";
import {ISuperfluidToken} from "../contracts/interfaces/superfluid/ISuperfluidToken.sol";
import {ISuperToken} from "../contracts/interfaces/superfluid/ISuperToken.sol";
import {ISuperfluidGovernance} from "../contracts/interfaces/superfluid/ISuperfluidGovernance.sol";
import {SuperfluidGovernanceBase} from "../contracts/gov/SuperfluidGovernanceBase.sol";
import {Ownable} from "@openzeppelin-v5/contracts/access/Ownable.sol";

/// @notice Typed governance actions; only the deployment's host comes from the environment.
contract GovAction is Script {
    function _host() internal view virtual returns (ISuperfluid) {
        return ISuperfluid(vm.envAddress("HOST_ADDRESS"));
    }

    function _execute(bytes memory data) internal {
        address gov = address(_host().getGovernance());
        vm.startBroadcast(vm.envAddress("DEPLOYER"));
        DeployUtils.executeGovernanceAction(gov, data, Ownable(gov).owner());
        vm.stopBroadcast();
    }

    function setTokenMinimumDeposit(ISuperfluidToken token, uint256 amount) external {
        _execute(abi.encodeCall(SuperfluidGovernanceBase.setSuperTokenMinimumDeposit, (_host(), token, amount)));
    }

    function set3PsConfig(ISuperfluidToken token, uint256 liquidation, uint256 patrician) external {
        _execute(abi.encodeCall(SuperfluidGovernanceBase.setPPPConfig, (_host(), token, liquidation, patrician)));
    }

    function clear3PsConfig(ISuperfluidToken token) external {
        _execute(abi.encodeCall(SuperfluidGovernanceBase.clearPPPConfig, (_host(), token)));
    }

    function setRewardAddress(ISuperfluidToken token, address reward) external {
        _execute(abi.encodeCall(SuperfluidGovernanceBase.setRewardAddress, (_host(), token, reward)));
    }

    function clearRewardAddress(ISuperfluidToken token) external {
        _execute(abi.encodeCall(SuperfluidGovernanceBase.clearRewardAddress, (_host(), token)));
    }

    function enableTrustedForwarder(ISuperfluidToken token, address forwarder) external {
        _execute(abi.encodeCall(SuperfluidGovernanceBase.enableTrustedForwarder, (_host(), token, forwarder)));
    }

    function disableTrustedForwarder(ISuperfluidToken token, address forwarder) external {
        _execute(abi.encodeCall(SuperfluidGovernanceBase.disableTrustedForwarder, (_host(), token, forwarder)));
    }

    function changeSuperTokenAdmin(ISuperToken token, address admin) external {
        _execute(abi.encodeCall(SuperfluidGovernanceBase.changeSuperTokenAdmin, (_host(), token, admin)));
    }

    function batchChangeSuperTokenAdmin(ISuperToken[] calldata tokens, address[] calldata admins) external {
        require(tokens.length == admins.length, "Token/admin length mismatch");
        _execute(abi.encodeCall(SuperfluidGovernanceBase.batchChangeSuperTokenAdmin, (_host(), tokens, admins)));
    }

    function registerAgreementClass(address agreement) external {
        _execute(abi.encodeCall(ISuperfluidGovernance.registerAgreementClass, (_host(), agreement)));
    }

    function replaceGovernance(ISuperfluidGovernance governance) external {
        _execute(abi.encodeCall(ISuperfluidGovernance.replaceGovernance, (_host(), address(governance))));
    }

    function setAppRegistrationKey(address deployer, uint256 expiration, string calldata key) external {
        _execute(abi.encodeCall(SuperfluidGovernanceBase.setAppRegistrationKey, (_host(), deployer, key, expiration)));
    }
}
