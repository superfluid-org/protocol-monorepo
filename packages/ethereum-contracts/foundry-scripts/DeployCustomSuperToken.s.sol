// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {ISuperTokenFactory} from "../contracts/interfaces/superfluid/ISuperTokenFactory.sol";
import {ISuperToken} from "../contracts/interfaces/superfluid/ISuperToken.sol";
import {IERC20} from "@openzeppelin-v5/contracts/token/ERC20/IERC20.sol";
import {PureSuperToken} from "../contracts/tokens/PureSuperToken.sol";
import {SETHProxy} from "../contracts/tokens/SETH.sol";

// Factory.initializeCustomSuperToken and token.initialize are permissionless.
// Keep CREATE + both initialization calls in one transaction, not three cast sends.
contract CustomSuperTokenDeployment {
    address public immutable token;

    constructor(ISuperTokenFactory factory, string memory name, string memory symbol, bool nativeToken, uint256 supply) {
        if (nativeToken) {
            require(supply == 0, "Native token cannot premint");
            token = address(new SETHProxy());
            factory.initializeCustomSuperToken(token);
            ISuperToken(token).initialize(IERC20(address(0)), 18, name, symbol);
        } else {
            PureSuperToken pureToken = new PureSuperToken();
            token = address(pureToken);
            factory.initializeCustomSuperToken(token);
            pureToken.initialize(name, symbol, supply);
            require(ISuperToken(token).transfer(msg.sender, supply), "Supply transfer failed");
        }
    }
}

contract DeployCustomSuperToken is Script {
    function run() external returns (address token) {
        ISuperTokenFactory factory = ISuperTokenFactory(vm.envAddress("FACTORY_ADDRESS"));
        string memory name = vm.envString("TOKEN_NAME");
        string memory symbol = vm.envString("TOKEN_SYMBOL");
        bool nativeToken = vm.envBool("NATIVE_TOKEN");
        uint256 supply = vm.envOr("INITIAL_SUPPLY", uint256(0));
        vm.startBroadcast();
        CustomSuperTokenDeployment deployment = new CustomSuperTokenDeployment(factory, name, symbol, nativeToken, supply);
        vm.stopBroadcast();
        token = deployment.token();
        console.log("SuperToken deployed (not listed):", token);
    }
}
