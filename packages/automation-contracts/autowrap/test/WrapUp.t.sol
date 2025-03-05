// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import { ISuperToken } from "@superfluid-finance/ethereum-contracts/contracts/superfluid/SuperToken.sol";
import { SuperTokenV1Library } from "@superfluid-finance/ethereum-contracts/contracts/apps/SuperTokenV1Library.sol";
import { FoundrySuperfluidTester } from "@superfluid-finance/ethereum-contracts/test/foundry/FoundrySuperfluidTester.t.sol";
import { Manager } from "./../contracts/Manager.sol";
import { WrapStrategy } from "./../contracts/strategies/WrapStrategy.sol";
import { ISETH } from "@superfluid-finance/ethereum-contracts/contracts/interfaces/tokens/ISETH.sol";

/// @title ManagerTests
contract WrapTests is FoundrySuperfluidTester {
    using SuperTokenV1Library for ISuperToken;

    event WrapExecuted(bytes32 indexed id, uint256 WrapAmount);

    /// SETUP AND HELPERS

    constructor() FoundrySuperfluidTester(3) {}

    uint64 MIN_LOWER = 2 days;
    uint64 MIN_UPPER = 7 days;
    Manager public manager;
    WrapStrategy public wrapStrategy;
    uint256 internal _expectedTotalSupply;
    ISETH nativeSuperToken;
    uint64 constant EXPIRY = type(uint64).max;

    function setUp() override public virtual {
        super.setUp();
        nativeSuperToken = sfDeployer.deployNativeAssetSuperToken("xFTT", "xFTT");
        manager = new Manager(address(sf.cfa), MIN_LOWER, MIN_UPPER);
        wrapStrategy = new WrapStrategy(address(manager));
        manager.addApprovedStrategy(address(wrapStrategy));
    }

    function getWrapIndex(
        address user,
        address _superToken,
        address liquidityToken
    ) public pure returns (bytes32) {
        return keccak256(abi.encode(user, _superToken, liquidityToken));
    }

    function startStream(address sender, address receiver, int96 flowRate) public {
        vm.startPrank(sender);
        superToken.createFlow(receiver, flowRate);
        (,int96 flow,,) = sf.cfa.getFlow(superToken, alice, bob);
        assertEq(flowRate, flow, "startStream Flow rate are not the same");
        vm.stopPrank();
    }

    function stopStream(address sender, address receiver) public {
        vm.startPrank(sender);
        superToken.deleteFlow(sender, receiver);
        vm.stopPrank();
    }

    function setDefaultWrap(address sender) public {
        vm.startPrank(sender);
        token.approve(address(wrapStrategy), INIT_SUPER_TOKEN_BALANCE);
        manager.createWrapSchedule(
            address(superToken),
            address(wrapStrategy),
            address(token),
            EXPIRY,
            MIN_LOWER,
            MIN_UPPER
        );
        vm.stopPrank();
    }


    /// TESTS

    function testExecuteWrapCheckWrappedAmount() public {
        int96 flowRate = 10000;
        uint256 wrappedAmount = uint256(uint96(flowRate)) * 7 days;
        setDefaultWrap(alice);
        startStream(alice, bob, flowRate);
        vm.warp(1 days);
        vm.startPrank(alice);
        // take alice balance to zero
        (int256 availableBalance,,,) = superToken.realtimeBalanceOfNow(alice);
        superToken.downgrade(uint256(availableBalance));
        vm.stopPrank();
        vm.expectEmit(true, true, true, true);
        emit WrapExecuted(getWrapIndex(alice, address(superToken), address(token)), wrappedAmount);
        manager.executeWrap(alice, address(superToken), address(token));
        assertEq(wrappedAmount, superToken.balanceOf(alice), "Alice balance should match upper * flowrate");
    }

}
