// SPDX-License-Identifier: AGPLv3
pragma solidity ^0.8.23;

import { FoundrySuperfluidTester } from "./FoundrySuperfluidTester.t.sol";
import { IPureSuperToken, ISETH, TestToken, SuperToken } from "../../contracts/utils/SuperfluidFrameworkDeployer.t.sol";
import { SuperfluidLoader } from "../../contracts/utils/SuperfluidLoader.sol";

contract SuperfluidFrameworkDeployerTest is FoundrySuperfluidTester {
    constructor() FoundrySuperfluidTester(1) { }

    function testAllContractsDeployed() public view {
        assertTrue(address(sf.governance) != address(0), "SFDeployer: governance not deployed");
        assertTrue(address(sf.host) != address(0), "SFDeployer: host not deployed");
        assertTrue(address(sf.cfa) != address(0), "SFDeployer: cfa not deployed");
        assertTrue(address(sf.ida) != address(0), "SFDeployer: ida not deployed");
        assertTrue(address(sf.gda) != address(0), "SFDeployer: gda not deployed");
        assertTrue(address(sf.superTokenFactory) != address(0), "SFDeployer: superTokenFactory not deployed");
        assertTrue(address(sf.superTokenLogic) != address(0), "SFDeployer: superTokenLogic not deployed");
        assertTrue(address(sf.resolver) != address(0), "SFDeployer: resolver not deployed");
        assertTrue(address(sf.superfluidLoader) != address(0), "SFDeployer: superfluidLoader not deployed");
        assertTrue(address(sf.cfaV1Forwarder) != address(0), "SFDeployer: cfaV1Forwarder not deployed");
        assertTrue(address(sf.gdaV1Forwarder) != address(0), "SFDeployer: gdaV1Forwarder not deployed");
        assertTrue(address(sf.macroForwarder) != address(0), "SFDeployer: macroForwarder not deployed");
        assertTrue(address(sf.batchLiquidator) != address(0), "SFDeployer: batchLiquidator not deployed");
    }

    function testResolverGetsGovernance() public view {
        assertEq(
            sf.resolver.get("TestGovernance.test"), address(sf.governance), "SFDeployer: governance not registered"
        );
    }

    function testResolverGetsHost() public view {
        assertEq(sf.resolver.get("Superfluid.test"), address(sf.host), "SFDeployer: host not registered");
    }

    function testResolverGetsLoader() public view {
        assertEq(
            sf.resolver.get("SuperfluidLoader-v1"),
            address(sf.superfluidLoader),
            "SFDeployer: superfluidLoader not registered"
        );
    }

    function testLoaderGetsFramework() public view {
        SuperfluidLoader.Framework memory loadedSf = sf.superfluidLoader.loadFramework("test");

        assertEq(address(loadedSf.superfluid), address(sf.host), "SFDeployer: host not loaded");
        assertEq(address(loadedSf.agreementCFAv1), address(sf.cfa), "SFDeployer: cfa not loaded");
        assertEq(address(loadedSf.agreementIDAv1), address(sf.ida), "SFDeployer: ida not loaded");
    }

    function testTransferOwnership() public {
        assertEq(sf.governance.owner(), address(sfDeployer), "SFDeployer: governance not owned by deployer");
        sfDeployer.transferOwnership(address(420));
        assertEq(sf.governance.owner(), address(420), "SFDeployer: governance not owned by address(420)");
    }

    //// SuperToken Deployment Tests ////

    function testDeployWrapperSuperToken(
        string calldata _name,
        string calldata _symbol,
        uint8 _decimals,
        uint256 _mintLimit
    ) public {
        (TestToken underlyingToken, SuperToken _superToken) =
            sfDeployer.deployWrapperSuperToken(_name, _symbol, _decimals, _mintLimit, address(0));

        // assert underlying erc20 name/symbol properly set
        assertEq(underlyingToken.name(), _name, "SFDeployer: Underlying token name not properly set");
        assertEq(underlyingToken.symbol(), _symbol, "SFDeployer: Underlying token symbol not properly set");

        // assert super token name/symbol properly set
        assertEq(_superToken.name(), string.concat("Super ", _symbol), "SFDeployer: Super token name not properly set");
        assertEq(_superToken.symbol(), string.concat(_symbol, "x"), "SFDeployer: Super token symbol not properly set");

        // assert proper resolver listing for underlying and wrapper super token
        address resolverUnderlyingTokenAddress =
            sf.resolver.get(string.concat("tokens.test.", underlyingToken.symbol()));
        assertEq(
            resolverUnderlyingTokenAddress,
            address(underlyingToken),
            "SFDeployer: Underlying token not properly registered"
        );
        address resolverSuperTokenAddress = sf.resolver.get(string.concat("supertokens.test.", _superToken.symbol()));
        assertEq(resolverSuperTokenAddress, address(_superToken), "SFDeployer: Super token not properly registered");
    }

    function testDeployNativeAssetSuperToken(string calldata _name, string calldata _symbol) public {
        ISETH nativeAssetSuperToken = sfDeployer.deployNativeAssetSuperToken(_name, _symbol);

        // assert native asset super token name/symbol properly set
        assertEq(nativeAssetSuperToken.name(), _name, "SFDeployer: Native asset super token name not properly set");
        assertEq(
            nativeAssetSuperToken.symbol(), _symbol, "SFDeployer: Native asset super token symbol not properly set"
        );

        // assert proper resolver listing
        address resolverTokenAddress =
            sf.resolver.get(string.concat("supertokens.test.", nativeAssetSuperToken.symbol()));
        assertEq(
            resolverTokenAddress,
            address(nativeAssetSuperToken),
            "SFDeployer: Native asset super token not properly registered"
        );
    }

    function testDeployPureSuperToken(string calldata _name, string calldata _symbol, uint256 _initialSupply) public {
        vm.assume(_initialSupply <= uint256(type(int256).max));

        IPureSuperToken pureSuperToken = sfDeployer.deployPureSuperToken(_name, _symbol, _initialSupply);

        // assert pure super token name/symbol properly set
        assertEq(pureSuperToken.name(), _name, "SFDeployer: Pure super token name not properly set");
        assertEq(pureSuperToken.symbol(), _symbol, "SFDeployer: Pure super token symbol not properly set");

        // assert proper resolver listing
        address resolverTokenAddress = sf.resolver.get(string.concat("supertokens.test.", pureSuperToken.symbol()));
        assertEq(resolverTokenAddress, address(pureSuperToken), "SFDeployer: Pure super token not properly registered");
    }
}
