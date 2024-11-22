// SPDX-License-Identifier: AGPLv3
pragma solidity ^0.8.23;

import { IConstantFlowAgreementV1 } from "../../../contracts/interfaces/agreements/IConstantFlowAgreementV1.sol";
import { FoundrySuperfluidTester, ISuperToken, SuperTokenV1Library, ISuperfluidPool }
    from "../FoundrySuperfluidTester.t.sol";

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

    // TESTS ========================================================================================

    function testFlow() external {
        // initial createFlow
        superToken.flow(bob, DEFAULT_FLOWRATE);
        assertEq(_getCFAFlowRate(address(this), bob), DEFAULT_FLOWRATE, "createFlow unexpected result");

        // double it -> updateFlow
        superToken.flow(bob, DEFAULT_FLOWRATE * 2);
        assertEq(_getCFAFlowRate(address(this), bob), DEFAULT_FLOWRATE * 2, "updateFlow unexpected result");

        // set to 0 -> deleteFlow
        superToken.flow(bob, 0);
        assertEq(_getCFAFlowRate(address(this), bob), 0, "deleteFlow unexpected result");

        // invalid flowrate
        vm.expectRevert(IConstantFlowAgreementV1.CFA_INVALID_FLOW_RATE.selector);
        this.__externalflow(address(this), bob, -1);
    }

    function testflowFrom() external {
        // alice allows this Test contract to operate CFA flows on her behalf
        vm.startPrank(alice);
        sf.host.callAgreement(
            sf.cfa,
            abi.encodeCall(sf.cfa.authorizeFlowOperatorWithFullControl, (superToken, address(this), new bytes(0))),
            new bytes(0) // userData
        );
        vm.stopPrank();

        // initial createFlow
        superToken.flowFrom(alice, bob, DEFAULT_FLOWRATE);
        assertEq(_getCFAFlowRate(alice, bob), DEFAULT_FLOWRATE, "createFlow unexpected result");

        // double it -> updateFlow
        superToken.flowFrom(alice, bob, DEFAULT_FLOWRATE * 2);
        assertEq(_getCFAFlowRate(alice, bob), DEFAULT_FLOWRATE * 2, "updateFlow unexpected result");

        // set to 0 -> deleteFlow
        superToken.flowFrom(alice, bob, 0);
        assertEq(_getCFAFlowRate(alice, bob), 0, "deleteFlow unexpected result");

        vm.expectRevert(IConstantFlowAgreementV1.CFA_INVALID_FLOW_RATE.selector);
        this.__externalflowFrom(address(this), alice, bob, -1);
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

    function testCreatePool() external {
        ISuperfluidPool pool = superToken.createPool();
        assertEq(pool.admin(), address(this));
        _assertDefaultPoolConfig(pool);
    }

    function testCreatePoolWithAdmin() external {
        ISuperfluidPool pool = superToken.createPool(alice);
        assertEq(pool.admin(), alice);
        _assertDefaultPoolConfig(pool);
    }

    function testGetCFAFlowRate() external {
        assertEq(superToken.getCFAFlowRate(address(this), bob), 0);
        superToken.flow(bob, DEFAULT_FLOWRATE);
        assertEq(superToken.getCFAFlowRate(address(this), bob), DEFAULT_FLOWRATE);
    }

    function testGetCFAFlowInfo() external {
        superToken.flow(bob, DEFAULT_FLOWRATE);
        (uint256 refLastUpdated, int96 refFlowRate, uint256 refDeposit, uint256 refOwedDeposit)
            = sf.cfa.getFlow(superToken, address(this), bob);
        (uint256 lastUpdated, int96 flowRate, uint256 deposit, uint256 owedDeposit) =
            superToken.getCFAFlowInfo(address(this), bob);
        assertEq(refLastUpdated, lastUpdated);
        assertEq(refFlowRate, flowRate);
        assertEq(refDeposit, deposit);
        assertEq(refOwedDeposit, owedDeposit);
    }

    function testGetGDANetFlowRate() external {
        ISuperfluidPool pool = superToken.createPool();
        pool.updateMemberUnits(bob, 1);
        vm.startPrank(bob);
        superToken.connectPool(pool);
        vm.stopPrank();

        assertEq(superToken.getGDANetFlowRate(address(this)), 0);
        superToken.distributeFlow(pool, DEFAULT_FLOWRATE);
        assertEq(superToken.getGDANetFlowRate(address(this)), -DEFAULT_FLOWRATE, "sender unexpected net flowrate");
        assertEq(superToken.getGDANetFlowRate(bob), DEFAULT_FLOWRATE, "receiver unexpected net flowrate");
    }

    function testGetGDANetFlowInfo() external {
        ISuperfluidPool pool = superToken.createPool();
        pool.updateMemberUnits(bob, 1);
        vm.startPrank(bob);
        superToken.connectPool(pool);
        vm.stopPrank();

        (uint256 lastUpdated1, int96 flowRate1, uint256 deposit1, uint256 owedDeposit1) =
            superToken.getGDANetFlowInfo(address(this));
        assertEq(flowRate1, 0);
        assertEq(deposit1, 0);
        assertEq(owedDeposit1, 0);

        skip(1);
        superToken.distributeFlow(pool, DEFAULT_FLOWRATE);

        (uint256 lastUpdated2, int96 flowRate2, uint256 deposit2, uint256 owedDeposit2) =
            superToken.getGDANetFlowInfo(address(this));
        assertEq(flowRate2, -DEFAULT_FLOWRATE, "sender unexpected net flowrate");
        assert(deposit2 > 0);
        assertEq(owedDeposit2, 0); // GDA doesn't use owed deposits
        assert(lastUpdated2 > lastUpdated1);
    }

    function testGetTotalAmountReceivedFromPool() external {
        ISuperfluidPool pool = superToken.createPool();
        pool.updateMemberUnits(bob, 1);

        assertEq(superToken.getTotalAmountReceivedFromPool(pool, bob), 0);

        // Test with instant distribution
        superToken.transferX(address(pool), DEFAULT_AMOUNT);
        pool.claimAll(bob);
        assertEq(superToken.getTotalAmountReceivedFromPool(pool, bob), DEFAULT_AMOUNT);

        // Test with flow distribution
        superToken.flowX(address(pool), DEFAULT_FLOWRATE);
        // Wait a bit to accumulate some flow
        vm.warp(block.timestamp + 1);
        pool.claimAll(bob);
        assert(superToken.getTotalAmountReceivedFromPool(pool, bob) > DEFAULT_AMOUNT);

        // check alias function
        assertEq(
            superToken.getTotalAmountReceivedFromPool(pool, bob),
            superToken.getTotalAmountReceivedByMember(pool, bob)
        );
    }

    function testGetGDAFlowRate() external {
        ISuperfluidPool pool = superToken.createPool();
        pool.updateMemberUnits(bob, 1);

        assertEq(superToken.getGDAFlowRate(address(this), pool), 0);
        superToken.flowX(address(pool), DEFAULT_FLOWRATE);
        assertEq(superToken.getGDAFlowRate(address(this), pool), DEFAULT_FLOWRATE);
    }

    function testGetGDAFlowInfo() external {
        ISuperfluidPool pool = superToken.createPool();
        pool.updateMemberUnits(bob, 1);

        (uint256 lastUpdated1, int96 flowRate1, uint256 deposit1) =
            superToken.getGDAFlowInfo(address(this), pool);
        assertEq(flowRate1, 0);
        assertEq(deposit1, 0);

        superToken.flowX(address(pool), DEFAULT_FLOWRATE);

        (uint256 lastUpdated2, int96 flowRate2, uint256 deposit2) =
            superToken.getGDAFlowInfo(address(this), pool);
        assertEq(flowRate2, DEFAULT_FLOWRATE);
        assert(deposit2 > 0);
        assert(lastUpdated2 > lastUpdated1);
    }

    function testGetFlowRateWithCFA() external {
        // Test CFA flow
        assertEq(superToken.getFlowRate(address(this), bob), 0);
        superToken.flow(bob, DEFAULT_FLOWRATE);
        assertEq(superToken.getFlowRate(address(this), bob), DEFAULT_FLOWRATE);
    }

    function testGetFlowRateWithGDA() external {
        // Test GDA flow (flow distribution)
        ISuperfluidPool pool = superToken.createPool();
        pool.updateMemberUnits(bob, 1);

        assertEq(superToken.getFlowRate(address(this), address(pool)), 0);
        superToken.distributeFlow(pool, DEFAULT_FLOWRATE);
        assertEq(superToken.getFlowRate(address(this), address(pool)), DEFAULT_FLOWRATE);
    }

    function testGetFlowInfoWithCFA() external {
        // Test CFA flow
        (uint256 lastUpdated1, int96 flowRate1, uint256 deposit1, uint256 owedDeposit1) =
            superToken.getFlowInfo(address(this), bob);
        assertEq(flowRate1, 0);
        assertEq(deposit1, 0);
        assertEq(owedDeposit1, 0);

        superToken.flow(bob, DEFAULT_FLOWRATE);

        (uint256 lastUpdated2, int96 flowRate2, uint256 deposit2, uint256 owedDeposit2) =
            superToken.getFlowInfo(address(this), bob);
        assertEq(flowRate2, DEFAULT_FLOWRATE);
        assert(deposit2 > 0);
        assert(owedDeposit2 == 0); // No owed deposit in this case
        assert(lastUpdated2 > lastUpdated1);
    }

    function testGetFlowInfoWithGDA() external {
        // Test GDA flow (flow distribution)
        ISuperfluidPool pool = superToken.createPool();
        pool.updateMemberUnits(bob, 1);

        (uint256 lastUpdated1, int96 flowRate1, uint256 deposit1, uint256 owedDeposit1) =
            superToken.getFlowInfo(address(this), address(pool));
        assertEq(flowRate1, 0);
        assertEq(deposit1, 0);
        assertEq(owedDeposit1, 0);

        superToken.distributeFlow(pool, DEFAULT_FLOWRATE);

        (uint256 lastUpdated2, int96 flowRate2, uint256 deposit2, uint256 owedDeposit2) =
            superToken.getFlowInfo(address(this), address(pool));
        assertEq(flowRate2, DEFAULT_FLOWRATE);
        assert(deposit2 > 0);
        assertEq(owedDeposit2, 0); // GDA doesn't use owed deposits
        assert(lastUpdated2 > lastUpdated1);
    }

    // HELPER FUNCTIONS ========================================================================================

        // direct use of the agreement for assertions
    function _getCFAFlowRate(address sender, address receiver) public view returns (int96 flowRate) {
        (,flowRate,,) = sf.cfa.getFlow(superToken, sender, receiver);
    }

    // Note: this is without adjustmentFR
    function _getGDAFlowRate(address sender, ISuperfluidPool pool) public view returns (int96 flowRate) {
        return sf.gda.getFlowRate(superToken, sender, pool);
    }

    function _assertDefaultPoolConfig(ISuperfluidPool pool) internal view {
        assertEq(pool.transferabilityForUnitsOwner(), false);
        assertEq(pool.distributionFromAnyAddress(), true);
    }

    // helpers converting the lib call to an external call, for exception checking

    function __externalflow(address msgSender, address receiver, int96 flowRate) external {
        vm.startPrank(msgSender);
        superToken.flow(receiver, flowRate);
        vm.stopPrank();
    }

    function __externalflowFrom(address msgSender, address sender, address receiver, int96 flowRate) external {
        vm.startPrank(msgSender);
        superToken.flowFrom(sender, receiver, flowRate);
        vm.stopPrank();
    }
}