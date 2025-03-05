// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import { ISuperToken } from "@superfluid-finance/ethereum-contracts/contracts/superfluid/SuperToken.sol";
import { SuperTokenV1Library } from "@superfluid-finance/ethereum-contracts/contracts/apps/SuperTokenV1Library.sol";
import { FoundrySuperfluidTester } from "@superfluid-finance/ethereum-contracts/test/foundry/FoundrySuperfluidTester.t.sol";
import { Manager } from "./../contracts/Manager.sol";
import { WrapStrategy } from "./../contracts/strategies/WrapStrategy.sol";
import { IStrategy } from "./../contracts/interfaces/IStrategy.sol";
import { ISETH } from "@superfluid-finance/ethereum-contracts/contracts/interfaces/tokens/ISETH.sol";

/// @title ManagerTests
contract WrapStrategyTests is FoundrySuperfluidTester {
    using SuperTokenV1Library for ISuperToken;

    event Wrap(
        address indexed user,
        address indexed superToken,
        uint256 superTokenAmount
    );
    event ManagerChanged(
        address indexed oldManager,
        address indexed Manager
    );
    event EmergencyWithdrawInitiated(
        address indexed receiver,
        address indexed token,
        uint256 amount
    );

    /// SETUP AND HELPERS
    constructor() FoundrySuperfluidTester(3) {}

    uint64 MIN_LOWER = 2 days;
    uint64 MIN_UPPER = 7 days;
    Manager public manager;
    WrapStrategy public wrapStrategy;
    uint256 internal _expectedTotalSupply;
    ISETH nativeSuperToken;

    function setUp() override public virtual {
        super.setUp();
        nativeSuperToken = sfDeployer.deployNativeAssetSuperToken("xFTT", "xFTT");
        manager = new Manager(address(sf.cfa), MIN_LOWER, MIN_UPPER);
        wrapStrategy = new WrapStrategy(address(manager));
    }

    function startStream(address sender, address receiver, int96 flowRate) public {
        vm.startPrank(sender);
        superToken.createFlow(receiver, flowRate);
        vm.stopPrank();
    }

    function stopStream(address sender, address receiver) public {
        vm.startPrank(sender);
        superToken.deleteFlow(sender, receiver);
        vm.stopPrank();
    }


    /// TESTS

    function test_RevertWhen_DeploymentWithoutManager() public {
        vm.expectRevert(IStrategy.ZeroAddress.selector);
        new WrapStrategy(address(0));
    }

    function testDeploymentCheckData() public {
        WrapStrategy wrap = new WrapStrategy(address(manager));
        assertEq(address(manager), wrap.manager(), "manager address not equal");
    }

    // Manager operations

    function testCannotChangeManagerContractIfNotOwner() public {
        Manager newManager = new Manager(address(sf.cfa), MIN_LOWER, MIN_UPPER);
        vm.prank(admin);
        vm.expectRevert(bytes("Ownable: caller is not the owner"));
        wrapStrategy.changeManager(address(newManager));
    }

    function testCannotChangeManagerZeroAddress() public {
        vm.expectRevert(IStrategy.ZeroAddress.selector);
        wrapStrategy.changeManager(address(0));
    }

    function testChangeManagerContract() public {
        Manager newManager =  new Manager(address(sf.cfa), MIN_LOWER, MIN_UPPER);
        vm.expectEmit(true, true, true, true);
        emit ManagerChanged(address(manager), address(newManager));
        wrapStrategy.changeManager(address(newManager));
    }

    // SuperToken

    function testSupportedSuperToken() public {
        assertTrue(
            wrapStrategy.isSupportedSuperToken(superToken),
            "SuperToken should be supported"
        );
    }

    function testCannotNonSupportedSuperToken() public {
        assertTrue(
            !wrapStrategy.isSupportedSuperToken(nativeSuperToken),
            "Native SuperToken shouldn't be supported"
        );
    }

    // Wrap Strategy Operations

    function testCannotPerformWrapIfNotManager() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IStrategy.UnauthorizedCaller.selector, alice, address(manager)));
        wrapStrategy.wrap(bob, superToken, 1);
    }

}
