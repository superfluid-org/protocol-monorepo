// SPDX-License-Identifier: AGPLv3
pragma solidity ^0.8.23;

import "forge-std/Test.sol";
import { FoundrySuperfluidTester, SuperTokenV1Library } from "../FoundrySuperfluidTester.t.sol";
import { ISuperToken } from "../../../contracts/superfluid/SuperToken.sol";
import { TOGA } from "../../../contracts/utils/TOGA.sol";
import { IERC1820Registry } from "@openzeppelin/contracts/interfaces/IERC1820Registry.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { TestToken } from "../../../contracts/utils/TestToken.sol";

/**
 * @title TOGAIntegrationTest
 * @dev A contract for testing the functionality of the TOGA contract.
 */
contract TOGAIntegrationTest is FoundrySuperfluidTester {
    using SuperTokenV1Library for ISuperToken;

    TOGA internal toga;

    uint256 internal immutable MIN_BOND_DURATION;
    uint256 internal constant DEFAULT_BOND_AMOUNT = 1e18;
    IERC1820Registry internal constant _ERC1820_REG = IERC1820Registry(0x1820a4B7618BdE71Dce8cdc73aAB6C95905faD24);

    constructor() FoundrySuperfluidTester(5) {
        MIN_BOND_DURATION = sfDeployer.DEFAULT_TOGA_MIN_BOND_DURATION(); // 1 weeks
    }

    // Events

    event NewPIC(ISuperToken indexed token, address pic, uint256 bond, int96 exitRate);
    event BondIncreased(ISuperToken indexed token, uint256 additionalBond);
    event ExitRateChanged(ISuperToken indexed token, int96 exitRate);

    /**
     * @dev Sets up the contract for testing.
     */
    function setUp() public override {
        super.setUp();
        toga = new TOGA(sf.host, MIN_BOND_DURATION);
        _addAccount(address(toga));
    }

    // Helpers

    /**
     * @dev Checks the net flow of an asset for an account.
     * @param superToken_ The Super Token representing the asset.
     * @param account The address of the account to check.
     * @param expectedNetFlow The expected net flow.
     */
    function _assertNetFlow(ISuperToken superToken_, address account, int96 expectedNetFlow) internal view {
        int96 flowRate = sf.cfa.getNetFlow(superToken_, account);
        assertEq(flowRate, expectedNetFlow, "_assertNetFlow: net flow not equal");
    }

    /**
     * @dev Admin sends `amount` `superToken_` to the `target` address.
     * @param superToken_ The Super Token representing the asset.
     * @param target The address of the target.
     * @param amount The amount to send.
     */
    function _helperDeal(ISuperToken superToken_, address target, uint256 amount) internal {
        TestToken underlyingToken = TestToken(superToken_.getUnderlyingToken());
        uint256 maxAmount = uint256(type(int256).max);
        vm.startPrank(admin);
        underlyingToken.mint(admin, maxAmount);
        underlyingToken.approve(address(superToken_), maxAmount);
        superToken_.transferAll(address(1));
        superToken_.upgrade(maxAmount);
        superToken_.transfer(target, amount);
        vm.stopPrank();
    }

    /**
     * @dev Sends a PIC bid.
     * @param sender The address of the sender.
     * @param superToken_ The Super Token representing the asset.
     * @param newBond The bond amount.
     * @param exitRate The exit rate.
     */
    function _helperSendPICBid(address sender, ISuperToken superToken_, uint256 newBond, int96 exitRate) internal {
        _helperSendPICBid(sender, superToken_, newBond, abi.encode(exitRate));
    }

    function _helperSendPICBid(address newPIC, ISuperToken superToken_, uint256 newBond, bytes memory data) internal {
        uint256 balanceOfTogaBefore = superToken_.balanceOf(address(toga));
        int96 netFlowRateBefore = sf.cfa.getNetFlow(superToken_, newPIC);
        // this should be 0
        (, int96 togaToPicFlowRate,,) = sf.cfa.getFlow(superToken_, address(toga), newPIC);

        (address picBefore, uint256 picBondBefore,) = toga.getCurrentPICInfo(superToken_);

        vm.startPrank(newPIC);
        superToken_.send(address(toga), newBond, data);
        vm.stopPrank();

        int96 desiredExitRate;
        if (data.length > 0) {
            (desiredExitRate) = abi.decode(data, (int96));
        } else {
            // if no exit rate is sent in the send call, we use the default exit rate for the supertoken based on the
            // newBond amount
            desiredExitRate = toga.getDefaultExitRateFor(superToken_, newBond);
        }

        // Assert PIC, Bond and Exit Rate are set correctly after a succesful send
        {
            (address pic, uint256 picBond, int96 picExitRate) = toga.getCurrentPICInfo(superToken_);
            assertEq(newPIC, pic, "_helperSendPICBid: PIC not equal");
            newBond = picBefore == address(0) && balanceOfTogaBefore > 0
                // if there was no pic before and there was balance in the TOGA contract
                // the new PIC gets the bond + existing balance
                ? balanceOfTogaBefore + newBond
                : picBefore == newPIC
                    // if it is the same pic sending tokens, they are just increasing the bond by newBond amount
                    ? newBond + picBondBefore
                    // otherwise, in the outbidding scenario, the new bond amount is set as is
                    : newBond;
            assertEq(newBond, picBond, "_helperSendPICBid: PIC bond not equal");
            assertEq(desiredExitRate, picExitRate, "_helperSendPICBid: PIC exit rate not equal");
        }

        // Assert Net Flow Rate of newPIC is correct after a succesful send
        {
            int96 netFlowRateAfter = sf.cfa.getNetFlow(superToken_, newPIC);
            int96 flowRateDelta = desiredExitRate - togaToPicFlowRate;
            assertEq(netFlowRateAfter, netFlowRateBefore + flowRateDelta, "_helperChangeExitRate: net flow not equal");
        }
    }

    function _helperChangeExitRate(ISuperToken superToken_, address pic, int96 newExitRate) internal {
        int96 netFlowRateBefore = sf.cfa.getNetFlow(superToken_, pic);
        (, int96 togaToPicFlowRate,,) = sf.cfa.getFlow(superToken_, address(toga), pic);
        int96 flowRateDelta = newExitRate - togaToPicFlowRate;

        vm.startPrank(pic);
        toga.changeExitRate(superToken, newExitRate);
        vm.stopPrank();

        int96 netFlowRateAfter = sf.cfa.getNetFlow(superToken_, pic);
        assertEq(netFlowRateAfter, netFlowRateBefore + flowRateDelta, "_helperChangeExitRate: net flow not equal");

        (,, int96 exitRate) = toga.getCurrentPICInfo(superToken_);
        assertEq(exitRate, newExitRate, "_helperChangeExitRate: exit rate not equal");
    }

    function _boundBondValue(uint256 bond_) internal pure returns (uint256 bond) {
        // User only has 64 bits test super tokens
        // setting the lower bound > 1 in order to avoid
        // failures due to the exit stream not having enough min deposit
        // (clipping related)
        bond = bound(bond_, 1e12, INIT_SUPER_TOKEN_BALANCE);
        // before allowing higher limits, also consider that
        // the values returned by toga.getMaxExitRateFor() may not be achievable in practice
        // because of the flowrate data type restriction
    }

    // Tests

    /**
     * @dev Tests the contract setup.
     */
    function testContractSetup() public view {
        assertEq(toga.minBondDuration(), MIN_BOND_DURATION, "minBondDuration");
    }

    function testNoPICExistsInitially() public view {
        assertEq(
            address(0), toga.getCurrentPIC(superToken), "testNoPICExistsInitially: current PIC should be address(0)"
        );
    }

    /**
     * @dev Tests that Alice becomes the PIC.
     */
    function testAliceBecomesPIC(uint256 bond, int96 exitRate) public {
        bond = _boundBondValue(bond);
        exitRate = int96(bound(exitRate, 0, toga.getMaxExitRateFor(superToken, bond)));

        vm.expectEmit(true, true, true, true, address(toga));
        emit NewPIC(superToken, alice, bond, exitRate);

        _helperSendPICBid(alice, superToken, bond, exitRate);
    }

    /**
     * @dev Tests that Bob can outbid Alice with a higher bond.
     */
    function testBobOutBidsAlice(uint256 aliceBond, uint256 bobBond) public {
        aliceBond = bound(aliceBond, 1, INIT_SUPER_TOKEN_BALANCE - 1);
        bobBond = bound(bobBond, aliceBond + 1, INIT_SUPER_TOKEN_BALANCE);

        // Send PIC bid from Alice
        _helperSendPICBid(alice, superToken, aliceBond, 0);

        // Assert Alice is the current PIC
        assertEq(toga.getCurrentPIC(superToken), alice);

        // Get the bond amount
        (, uint256 bond,) = toga.getCurrentPICInfo(superToken);
        assertEq(bond, aliceBond);

        vm.expectEmit(true, true, true, true, address(toga));
        emit NewPIC(superToken, bob, bobBond, 0);

        _helperSendPICBid(bob, superToken, bobBond, 0);
    }

    function testTOGARegisteredWithERC1820() public view {
        address implementer1 = _ERC1820_REG.getInterfaceImplementer(address(toga), keccak256("TOGAv1"));
        address implementer2 = _ERC1820_REG.getInterfaceImplementer(address(toga), keccak256("TOGAv2"));

        assertEq(implementer1, address(toga), "testTOGARegisteredWithERC1820: TOGA should be registered as TOGAv1");
        assertEq(implementer2, address(toga), "testTOGARegisteredWithERC1820: TOGA should be registered as TOGAv2");
    }

    function testRevertIfNegativeExitRateIsRequested() public {
        // lower limit: 0 wei/second (no negative value allowed)
        vm.expectRevert("TOGA: negative exitRate not allowed");
        vm.startPrank(alice);
        superToken.send(address(toga), DEFAULT_BOND_AMOUNT, abi.encode(-1));
        vm.stopPrank();
    }

    function testRevertIfBondIsEmpty() public {
        (address pic, uint256 bond,) = toga.getCurrentPICInfo(superToken);
        assertEq(bond, 0);

        vm.startPrank(pic);
        vm.expectRevert("TOGA: exitRate too high");
        toga.changeExitRate(superToken, 1);
        vm.stopPrank();
    }

    function testRevertIfBidSmallerThanCurrentPICBond(uint256 bond, uint256 smallerBond) public {
        bond = _boundBondValue(bond);
        smallerBond = bound(smallerBond, 1, bond);
        _helperSendPICBid(alice, superToken, bond, 0);

        vm.startPrank(bob);
        vm.expectRevert("TOGA: bid too low");
        superToken.send(address(toga), smallerBond, abi.encode(0));
        vm.stopPrank();
    }

    function testRevertIfExitRateTooHigh(uint256 bond) public {
        bond = _boundBondValue(bond);

        // upper limit + 1 wei/second
        int96 highExitRate = toga.getMaxExitRateFor(superToken, bond) + 1;
        vm.startPrank(alice);
        vm.expectRevert("TOGA: exitRate too high");
        superToken.send(address(toga), bond, abi.encode(highExitRate));
        vm.stopPrank();
    }

    function testRevertIfNonPICTriesToChangeExitRate(int96 exitRate) public {
        vm.expectRevert("TOGA: only PIC allowed");
        toga.changeExitRate(superToken, exitRate);
    }

    function testMaxExitRateForGreaterThanOrEqualToDefaultExitRate(uint256 bond) public view {
        bond = _boundBondValue(bond);

        // the max exit rate needs to be greater or equal than default exit rate
        assertGe(toga.getMaxExitRateFor(superToken, bond), toga.getDefaultExitRateFor(superToken, bond));
    }

    function testUseDefaultExitRateAsFallbackIfNoExitRateSpecified(uint256 bond) public {
        bond = _boundBondValue(bond);

        _helperSendPICBid(alice, superToken, bond, abi.encode());
        _assertNetFlow(superToken, alice, toga.getDefaultExitRateFor(superToken, bond));
    }

    function testFirstBidderGetsTokensPreOwnedByContract(uint256 prevReward, uint256 bond, uint256 outBidBond) public {
        bond = bound(bond, 2, INIT_SUPER_TOKEN_BALANCE / 2); // make sure bob can afford to outbid
        prevReward = bound(prevReward, 1, bond - 1); // make sure the bond exceeds it

        // simulate pre-existing accumulation of rewards
        _helperDeal(superToken, address(toga), prevReward);

        _helperSendPICBid(alice, superToken, bond, 0);
        (, uint256 aliceBond,) = toga.getCurrentPICInfo(superToken);

        // the tokens previously collected in the contract are attributed to Alice's bond
        assertEq(aliceBond, (prevReward + bond));

        outBidBond = bound(outBidBond, aliceBond + 1, INIT_SUPER_TOKEN_BALANCE);

        uint256 alicePreOutbidBal = superToken.balanceOf(alice);
        _helperSendPICBid(bob, superToken, outBidBond, 0);

        // the tokens previously collected are paid out to Alice if outbid
        assertEq(superToken.balanceOf(alice), (alicePreOutbidBal + aliceBond));
    }

    function testCurrentPICCanIncreaseBond(uint256 bond, uint256 increasedBond) public {
        bond = bound(bond, DEFAULT_BOND_AMOUNT, INIT_SUPER_TOKEN_BALANCE / 4);

        _helperSendPICBid(alice, superToken, bond, 0);

        uint256 aliceIntermediateBal = superToken.balanceOf(alice);
        increasedBond = bound(increasedBond, bond + 1, aliceIntermediateBal);

        vm.expectEmit(true, true, false, false, address(toga));
        emit BondIncreased(superToken, increasedBond);

        _helperSendPICBid(alice, superToken, increasedBond, 0);

        assertEq(superToken.balanceOf(alice), (aliceIntermediateBal - increasedBond));
    }

    function testPICCanChangeExitRate(int96 newExitRate) public {
        uint256 bond = DEFAULT_BOND_AMOUNT;

        newExitRate = int96(bound(newExitRate, 0, toga.getMaxExitRateFor(superToken, bond)));

        _helperSendPICBid(alice, superToken, bond, new bytes(0));

        vm.expectEmit(true, true, false, false, address(toga));
        emit ExitRateChanged(superToken, newExitRate);

        _helperChangeExitRate(superToken, alice, newExitRate);
    }

    function testPICClosesStream(uint256 bond) public {
        bond = _boundBondValue(bond);

        _helperSendPICBid(alice, superToken, bond, 1e3);

        vm.warp(block.timestamp + 1000);
        _helperDeleteFlow(superToken, alice, address(toga), alice);
        _assertNetFlow(superToken, alice, 0);

        _helperChangeExitRate(superToken, alice, 0);
        _helperChangeExitRate(superToken, alice, 1);

        // close flow again
        vm.warp(block.timestamp + 1000);
        _helperDeleteFlow(superToken, alice, address(toga), alice);
        _assertNetFlow(superToken, alice, 0);

        // bob sends a bid too
        _helperSendPICBid(bob, superToken, bond, 1e3);
        _assertNetFlow(superToken, alice, 0);
    }

    function testCollectedRewardsAreAddedToThePICBond(uint256 bond, uint256 rewards) public {
        bond = _boundBondValue(bond);
        rewards = bound(rewards, 1, INIT_SUPER_TOKEN_BALANCE - 1);

        _helperSendPICBid(alice, superToken, bond, 0);

        vm.startPrank(admin);
        superToken.transfer(address(toga), rewards);
        vm.stopPrank();

        (, uint256 picBond,) = toga.getCurrentPICInfo(superToken);
        assertEq(picBond, bond + rewards);
    }

    function testBondIsConsumedByExitFlow(uint256 aliceBond) public {
        aliceBond = bound(aliceBond, DEFAULT_BOND_AMOUNT, INIT_SUPER_TOKEN_BALANCE / 2);

        int96 maxRate = toga.getMaxExitRateFor(superToken, aliceBond);
        _helperSendPICBid(alice, superToken, aliceBond, maxRate);

        // critical stream is liquidated - remaining bond goes to zero
        vm.warp(block.timestamp + toga.minBondDuration());

        // A sentinel would do this (liquidate the exit stream)
        vm.startPrank(admin);
        superToken.deleteFlow(address(toga), alice);
        vm.stopPrank();

        _assertNetFlow(superToken, alice, 0);
        _assertNetFlow(superToken, address(toga), 0);

        // this assumes the flow deletion was not triggered by the PIC - otherwise rewards would be accrued
        (, uint256 bond,) = toga.getCurrentPICInfo(superToken);
        assertEq(bond, 0);

        // accumulate some new rewards...
        _helperDeal(superToken, address(toga), 1e15);

        (, uint256 bond2,) = toga.getCurrentPICInfo(superToken);
        assertGe(bond2, 1e12);

        _helperChangeExitRate(superToken, alice, toga.getMaxExitRateFor(superToken, bond2));

        uint256 alicePreBal = superToken.balanceOf(alice);
        (, uint256 aliceBondLeft,) = toga.getCurrentPICInfo(superToken);

        // bob outbids
        _helperSendPICBid(bob, superToken, aliceBondLeft + 1, toga.getMaxExitRateFor(superToken, aliceBondLeft + 1));
        _assertNetFlow(superToken, alice, 0);

        assertEq((alicePreBal + aliceBondLeft), superToken.balanceOf(alice));
    }

    // This test tests that our assumptions about bond and exit rate in the other tests
    // are safe to make by testing a larger range of values
    function testBondAndExitRateLimits(uint256 bond, int96 exitRate) public {
        bond = bound(
            bond,
            exitRate == 0 ? 1 : 1 << 32, // with small bonds, opening the stream can fail due to CFA deposit having a
                // flow of 1<<32 due to clipping
            uint256(type(int256).max) // SuperToken doesn't support the full uint256 range
        );

        int96 maxExitRate = toga.getMaxExitRateFor(superToken, bond) > (type(int96).max) >> 14
            // the clipped CFA deposit needs to fit into 64 bits - since that is flowrate multiplied by
            // liquidation period, 14 bits are added for 14400 seconds, so we can't use the full 96 bits
            ? (type(int96).max) >> 14
            // satisfy exitRate constraints of the TOGA
            : toga.getMaxExitRateFor(superToken, bond);

        exitRate = int96(bound(exitRate, 0, maxExitRate));

        vm.startPrank(alice);
        superToken.transferAll(address(1));
        vm.stopPrank();

        _helperDeal(superToken, alice, uint256(type(int256).max));

        _helperSendPICBid(alice, superToken, bond, exitRate);
    }

    function testMultiplePICsInParallel(uint256 bond) public {
        bond = _boundBondValue(bond);

        (, ISuperToken superToken2) =
            sfDeployer.deployWrapperSuperToken("TEST2", "TEST2", 18, type(uint256).max, address(0));

        _helperDeal(superToken2, alice, INIT_SUPER_TOKEN_BALANCE);
        _helperDeal(superToken2, bob, INIT_SUPER_TOKEN_BALANCE);

        _helperSendPICBid(alice, superToken, bond, toga.getDefaultExitRateFor(superToken, bond));
        _helperSendPICBid(bob, superToken2, bond, toga.getDefaultExitRateFor(superToken, bond));

        // let this run for a while...
        vm.warp(block.timestamp + 1e6);

        // alice takes over superToken2
        uint256 bobPreBal = superToken2.balanceOf(bob);
        (, uint256 bobBondLeft,) = toga.getCurrentPICInfo(superToken2);

        _helperSendPICBid(alice, superToken2, bobBondLeft + 1, 0);

        assertEq((bobPreBal + bobBondLeft), superToken2.balanceOf(bob));
    }
}
