// SPDX-License-Identifier: AGPLv3
pragma solidity ^0.8.23;

import { IConstantFlowAgreementV1 } from "../../../contracts/interfaces/agreements/IConstantFlowAgreementV1.sol";
import { FoundrySuperfluidTester, ISuperToken, SuperTokenV1Library, ISuperfluidPool }
    from "../FoundrySuperfluidTester.sol";

/*
* Note: since libs are used by contracts, not EOAs, do NOT try to use
* vm.prank() in tests. That will lead to unexpected outcomes.
* Instead, let the Test contract itself be the mock sender.
*/
contract SuperTokenV1LibraryTest is FoundrySuperfluidTester {
    using SuperTokenV1Library for ISuperToken;

    int96 internal constant DEFAULT_FLOWRATE = 1e12;
    uint256 internal constant DEFAULT_AMOUNT = 1e18;

    constructor() FoundrySuperfluidTester(3) {
    }

    function setUp() public override {
        super.setUp();

        // fund this Test contract with SuperTokens
        vm.startPrank(alice);
        superToken.transfer(address(this), 10e18);
        vm.stopPrank();
    }

    // direct use of the agreement for assertions
    function _getCFAFlowRate(address sender, address receiver) public view returns (int96 flowRate) {
        (,flowRate,,) = sf.cfa.getFlow(superToken, sender, receiver);
    }

    // Note: this is without adjustmentFR
    function _getGDAFlowRate(address sender, ISuperfluidPool pool) public view returns (int96 flowRate) {
        return sf.gda.getFlowRate(superToken, sender, pool);
    }

    function _assertDefaultPoolConfig(ISuperfluidPool pool) internal {
        assertEq(pool.transferabilityForUnitsOwner(), false);
        assertEq(pool.distributionFromAnyAddress(), true);
    }

    function testGetCFAFlowRate() external {
        assertEq(superToken.getCFAFlowRate(address(this), bob), 0);
        superToken.setCFAFlowRate(bob, DEFAULT_FLOWRATE);
        assertEq(superToken.getCFAFlowRate(address(this), bob), DEFAULT_FLOWRATE);
    }

    function testGetCFAFlowInfo() external {
        superToken.setCFAFlowRate(bob, DEFAULT_FLOWRATE);
        (uint256 refLastUpdated, int96 refFlowRate, uint256 refDeposit, uint256 refOwedDeposit)
            = sf.cfa.getFlow(superToken, address(this), bob);
        (uint256 lastUpdated, int96 flowRate, uint256 deposit, uint256 owedDeposit) =
            superToken.getCFAFlowInfo(address(this), bob);
        assertEq(refLastUpdated, lastUpdated);
        assertEq(refFlowRate, flowRate);
        assertEq(refDeposit, deposit);
        assertEq(refOwedDeposit, owedDeposit);
    }

    function testSetGetCFAFlowRate() external {
        // initial createFlow
        superToken.setCFAFlowRate(bob, DEFAULT_FLOWRATE);
        assertEq(_getCFAFlowRate(address(this), bob), DEFAULT_FLOWRATE, "createFlow unexpected result");

        // double it -> updateFlow
        superToken.setCFAFlowRate(bob, DEFAULT_FLOWRATE * 2);
        assertEq(_getCFAFlowRate(address(this), bob), DEFAULT_FLOWRATE * 2, "updateFlow unexpected result");

        // set to 0 -> deleteFlow
        superToken.setCFAFlowRate(bob, 0);
        assertEq(_getCFAFlowRate(address(this), bob), 0, "deleteFlow unexpected result");

        // invalid flowrate
        vm.expectRevert(IConstantFlowAgreementV1.CFA_INVALID_FLOW_RATE.selector);
        this.__externalSetCFAFlowRate(address(this), bob, -1);
    }

    function testSetCFAFlowRateFrom() external {
        // alice allows this Test contract to operate CFA flows on her behalf
        vm.startPrank(alice);
        sf.host.callAgreement(
            sf.cfa,
            abi.encodeCall(sf.cfa.authorizeFlowOperatorWithFullControl, (superToken, address(this), new bytes(0))),
            new bytes(0) // userData
        );
        vm.stopPrank();

        // initial createFlow
        superToken.setCFAFlowRateFrom(alice, bob, DEFAULT_FLOWRATE);
        assertEq(_getCFAFlowRate(alice, bob), DEFAULT_FLOWRATE, "createFlow unexpected result");

        // double it -> updateFlow
        superToken.setCFAFlowRateFrom(alice, bob, DEFAULT_FLOWRATE * 2);
        assertEq(_getCFAFlowRate(alice, bob), DEFAULT_FLOWRATE * 2, "updateFlow unexpected result");

        // set to 0 -> deleteFlow
        superToken.setCFAFlowRateFrom(alice, bob, 0);
        assertEq(_getCFAFlowRate(alice, bob), 0, "deleteFlow unexpected result");

        vm.expectRevert(IConstantFlowAgreementV1.CFA_INVALID_FLOW_RATE.selector);
        this.__externalSetCFAFlowRateFrom(address(this), alice, bob, -1);
    }

    function testFlowXToAccount() external {
        superToken.flowX(bob, DEFAULT_FLOWRATE);
        assertEq(_getCFAFlowRate(address(this), bob), DEFAULT_FLOWRATE, "createFlow unexpected result");

        // double it -> updateFlow
        superToken.flowX(bob, DEFAULT_FLOWRATE * 2);
        assertEq(_getCFAFlowRate(address(this), bob), DEFAULT_FLOWRATE * 2, "updateFlow unexpected result");

        // set to 0 -> deleteFlow
        superToken.flowX(bob, 0);
        assertEq(_getCFAFlowRate(address(this), bob), 0, "deleteFlow unexpected result");
    }

    function testFlowXToPool() external {
        ISuperfluidPool pool = superToken.createPool();
        pool.updateMemberUnits(bob, 1);

        superToken.flowX(address(pool), DEFAULT_FLOWRATE);
        assertEq(_getGDAFlowRate(address(this), pool), DEFAULT_FLOWRATE, "distrbuteFlow (new) unexpected result");

        // double it -> updateFlow
        superToken.flowX(address(pool), DEFAULT_FLOWRATE * 2);
        assertEq(_getGDAFlowRate(address(this), pool), DEFAULT_FLOWRATE * 2, "distrbuteFlow (update) unexpected result");

        // set to 0 -> deleteFlow
        superToken.flowX(address(pool), 0);
        assertEq(_getGDAFlowRate(address(this), pool), 0, "distrbuteFlow (delete) unexpected result");
    }

    function testTransferXToAccount() external {
        uint256 bobBalBefore = superToken.balanceOf(bob);
        superToken.transferX(bob, DEFAULT_AMOUNT);
        assertEq(superToken.balanceOf(bob) - bobBalBefore, DEFAULT_AMOUNT, "transfer unexpected result");
    }

    function testTransferXToPool() external {
        uint256 bobBalBefore = superToken.balanceOf(bob);
        ISuperfluidPool pool = superToken.createPool();
        pool.updateMemberUnits(bob, 1);

        superToken.transferX(address(pool), DEFAULT_AMOUNT);
        pool.claimAll(bob);
        assertEq(superToken.balanceOf(bob) - bobBalBefore, DEFAULT_AMOUNT, "distribute unexpected result");
    }

    function testCreatePoolWithAdmin() external {
        ISuperfluidPool pool = superToken.createPool(alice);
        assertEq(pool.admin(), alice);
        _assertDefaultPoolConfig(pool);
    }

    function testCreatePool() external {
        ISuperfluidPool pool = superToken.createPool();
        assertEq(pool.admin(), address(this));
        _assertDefaultPoolConfig(pool);
    }

    // helpers converting the lib call to an external call, for exception checking

    function __externalSetCFAFlowRate(address msgSender, address receiver, int96 flowRate) external {
        vm.startPrank(msgSender);
        superToken.setCFAFlowRate(receiver, flowRate);
        vm.stopPrank();
    }

    function __externalSetCFAFlowRateFrom(address msgSender, address sender, address receiver, int96 flowRate) external {
        vm.startPrank(msgSender);
        superToken.setCFAFlowRateFrom(sender, receiver, flowRate);
        vm.stopPrank();
    }
}