// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;
import {Script, console} from "forge-std/Script.sol";
import {TestToken} from "../contracts/utils/TestToken.sol";
import {ISuperfluid} from "../contracts/interfaces/superfluid/ISuperfluid.sol";
import {ISuperTokenFactory} from "../contracts/interfaces/superfluid/ISuperTokenFactory.sol";
import {IERC20Metadata} from "@openzeppelin-v5/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {Resolver} from "../contracts/utils/Resolver.sol";
import {DeployUtils} from "./utils/DeployUtils.sol";
import {ChainPolicy} from "./utils/ChainPolicy.sol";

/// @notice Explicit opt-in public mintable test token and wrapper, never part of framework upgrades.
contract ProvisionTestToken is Script {
    function run(string memory name, string memory symbol, uint8 decimals, uint256 mintLimit) external {
        require(ChainPolicy.isTestnet(block.chainid), "Faucet provisioning is testnet/local only");
        require(decimals <= 18 && mintLimit > 0 && bytes(symbol).length > 0, "Invalid faucet parameters");
        Resolver resolver = Resolver(vm.envAddress("RESOLVER_ADDRESS"));
        string memory release = vm.envOr("RELEASE_VERSION", string("v1"));
        string memory underlyingKey = string.concat("tokens.", symbol);
        string memory superKey = string.concat("supertokens.", release, ".", symbol, "x");
        require(resolver.get(underlyingKey) == address(0) && resolver.get(superKey) == address(0),
            "Token keys occupied; faucet provisioning never overwrites");
        ISuperfluid host = ISuperfluid(resolver.get(string.concat("Superfluid.", release)));
        ISuperTokenFactory factory = host.getSuperTokenFactory();
        require(address(factory).code.length > 0, "Missing factory");
        address admin = DeployUtils.getResolverAdmin(resolver);
        vm.startBroadcast(vm.envAddress("DEPLOYER"));
        (TestToken token, address wrapper) = _deploy(factory, name, symbol, decimals, mintLimit);
        DeployUtils.executeResolverAction(address(resolver), abi.encodeCall(Resolver.set,
            (underlyingKey, address(token))), admin);
        DeployUtils.executeResolverAction(address(resolver), abi.encodeCall(Resolver.set,
            (superKey, wrapper)), admin);
        console.log("TEST_TOKEN", address(token));
        console.log("SUPER_TOKEN", wrapper);
        vm.stopBroadcast();
    }

    function _deploy(ISuperTokenFactory factory, string memory name, string memory symbol,
        uint8 decimals, uint256 mintLimit) private returns (TestToken token, address wrapper)
    {
        token = new TestToken(name, symbol, decimals, mintLimit);
        wrapper = address(factory.createERC20Wrapper(IERC20Metadata(address(token)), decimals,
            ISuperTokenFactory.Upgradability.SEMI_UPGRADABLE, string.concat("Super ", name),
            string.concat(symbol, "x"), address(0)));
    }
}
