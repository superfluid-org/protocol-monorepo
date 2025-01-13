// SPDX-License-Identifier: AGPLv3
pragma solidity ^0.8.23;

import { IConstantFlowAgreementV1, ISuperfluid, ISuperToken, ISuperfluidPool, ISuperApp, PoolConfig, PoolERC20Metadata }
    from "../../../contracts/interfaces/superfluid/ISuperfluid.sol";
import { CFASuperAppBase } from "../../../contracts/apps/CFASuperAppBase.sol";
import { SuperTokenV1Library } from "../../../contracts/apps/SuperTokenV1Library.sol";
import { FoundrySuperfluidTester } from "../FoundrySuperfluidTester.t.sol";

using SuperTokenV1Library for ISuperToken;

/*
* Note: since libs are used by contracts, not EOAs, do NOT try to use
* vm.prank() in tests. That will lead to unexpected outcomes.
* Instead, let the Test contract itself be the mock sender.
*/
contract SuperTokenV1LibraryTest is FoundrySuperfluidTester {
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
        this.__external_flow(address(this), bob, -1);
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
        this.__external_flowFrom(address(this), alice, bob, -1);
    }

    function testFlowXToAccount() external {
        int96 fr = superToken.flowX(bob, DEFAULT_FLOWRATE);
        assertEq(_getCFAFlowRate(address(this), bob), DEFAULT_FLOWRATE, "createFlow unexpected result");
        assertEq(fr, DEFAULT_FLOWRATE, "flowX wrong return value");

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

        int96 fr = superToken.flowX(address(pool), DEFAULT_FLOWRATE);
        assertEq(_getGDAFlowRate(address(this), pool), DEFAULT_FLOWRATE, "distrbuteFlow (new) unexpected result");
        assertEq(fr, DEFAULT_FLOWRATE, "flowX wrong return value");

        // double it -> updateFlow
        superToken.flowX(address(pool), DEFAULT_FLOWRATE * 2);
        assertEq(_getGDAFlowRate(address(this), pool), DEFAULT_FLOWRATE * 2, "distrbuteFlow (update) unexpected result");

        // set to 0 -> deleteFlow
        superToken.flowX(address(pool), 0);
        assertEq(_getGDAFlowRate(address(this), pool), 0, "distrbuteFlow (delete) unexpected result");
    }

    function testTransferXToAccount() external {
        uint256 bobBalBefore = superToken.balanceOf(bob);
        uint256 actualAmount = superToken.transferX(bob, DEFAULT_AMOUNT);
        assertEq(superToken.balanceOf(bob) - bobBalBefore, actualAmount, "transfer unexpected result");
        assertEq(actualAmount, DEFAULT_AMOUNT, "transferX wrong return value");
    }

    function testTransferXToPool() external {
        uint256 bobBalBefore = superToken.balanceOf(bob);
        ISuperfluidPool pool = superToken.createPool();
        pool.updateMemberUnits(bob, 1);

        uint256 actualAmount = superToken.transferX(address(pool), DEFAULT_AMOUNT);
        pool.claimAll(bob);
        assertEq(superToken.balanceOf(bob) - bobBalBefore, actualAmount, "distribute unexpected result");
        assertEq(actualAmount, DEFAULT_AMOUNT, "transferX wrong return value");
    }

    function testClaimAllToMsgSender() external {
        superToken.transfer(alice, DEFAULT_AMOUNT);

        uint256 balBefore = superToken.balanceOf(address(this));
        ISuperfluidPool pool = superToken.createPool();
        pool.updateMemberUnits(address(this), 1);

        vm.startPrank(alice);
        // using callAgreement here because prank won't work as expected with the lib function
        sf.host.callAgreement(
            sf.gda,
            abi.encodeCall(sf.gda.distribute, (superToken, alice, pool, DEFAULT_AMOUNT, new bytes(0))),
            new bytes(0) // userData
        );
        vm.stopPrank();

        superToken.claimAll(pool);
        assertEq(superToken.balanceOf(address(this)) - balBefore, DEFAULT_AMOUNT, "distribute unexpected result");
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

    function testCreatePoolWithCustomERC20Metadata() external {
        ISuperfluidPool pool = superToken.createPoolWithCustomERC20Metadata(
            alice,
            PoolConfig(true, true),
            PoolERC20Metadata("My Token", "MTK", 6)
        );

        assertEq(pool.name(), "My Token", "pool unexpected ERC20 name");
        assertEq(pool.symbol(), "MTK", "pool unexpected ERC20 symbol");
        assertEq(pool.decimals(), 6, "pool unexpected ERC20 decimals");
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

        assertEq(superToken.getFlowRate(address(this), address(pool)), 0, "getFlowRate to pool not zero");
        assertEq(superToken.getFlowRate(address(pool), bob), 0, "getFlowRate to pool member not zero");
        superToken.distributeFlow(pool, DEFAULT_FLOWRATE);
        assertEq(superToken.getFlowRate(address(this), address(pool)), DEFAULT_FLOWRATE, "getFlowRate to pool wrong");
        assertEq(superToken.getFlowRate(address(pool), bob), DEFAULT_FLOWRATE, "getFlowRate to pool member wrong");
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

        (uint256 lastUpdatedToPoolBefore, int96 flowRateToPoolBefore, uint256 depositToPoolBefore, uint256 owedDepositToPoolBefore) =
            superToken.getFlowInfo(address(this), address(pool));
        assertEq(flowRateToPoolBefore, 0);
        assertEq(depositToPoolBefore, 0);
        assertEq(owedDepositToPoolBefore, 0);

        (, int96 flowRateToMemberBefore, , ) = superToken.getFlowInfo(address(pool), bob);
        assertEq(flowRateToMemberBefore, 0);

        superToken.distributeFlow(pool, DEFAULT_FLOWRATE);

        (uint256 lastUpdatedToPoolAfter, int96 flowRateToPoolAfter, uint256 depositToPoolAfter, uint256 owedDepositToPoolAfter) =
            superToken.getFlowInfo(address(this), address(pool));
        assertEq(flowRateToPoolAfter, DEFAULT_FLOWRATE);
        assert(depositToPoolAfter > 0);
        assertEq(owedDepositToPoolAfter, 0); // GDA doesn't use owed deposits
        assert(lastUpdatedToPoolAfter > lastUpdatedToPoolBefore);

        (, int96 flowRateToMemberAfter, , ) = superToken.getFlowInfo(address(pool), bob);
        assertEq(flowRateToMemberAfter, DEFAULT_FLOWRATE);
    }

    // Make sure actualFlowrate and actualAmount returned by distributeFlow and distribute are always correct.
    // This is tested here because not provided by the GDA call itself, but added by the lib.
    function testDistributeAndDistributeFlowAndReturnCorrectActualFlowrate(
        uint32 u1, uint32 u2,
        int96 fr1, int96 fr2, int96 fr3,
        uint56 a1, uint56 a2, uint56 a3
    )
        external
    {
        fr1 = _boundFlowRate(fr1);
        fr2 = _boundFlowRate(fr2);
        fr3 = _boundFlowRate(fr3);

        // create distributors & fund them
        CallProxy sender1 = new CallProxy();
        CallProxy sender2 = new CallProxy();
        superToken.transfer(address(sender1), 5e18);
        superToken.transfer(address(sender2), 5e18);

        // create pool
        ISuperfluidPool pool = superToken.createPool(
            address(this),
            PoolConfig({
                transferabilityForUnitsOwner: false,    
                distributionFromAnyAddress: true
            })
        );

        // assign units to member1
        pool.updateMemberUnits(alice, u1);
        // distributeFlow from sender1 flowRate1
        {
            int96 actualFr = sender1.distributeFlow(superToken, pool, fr1);
            assertEq(actualFr, superToken.getFlowRate(address(sender1), address(pool)), "step 1 unexpected actual flowrate");
            // distribute from sender1 amount1
            uint256 balBefore = superToken.balanceOf(address(sender1));
            uint256 actualAmount = sender1.distribute(superToken, pool, a1);
            assertEq(actualAmount, balBefore - superToken.balanceOf(address(sender1)), "step 1 unexpected actual amount");
        }

        // assign units to member2
        pool.updateMemberUnits(bob, u2);
        // distributeFlow from sender2 flowRate2
        {
            int96 actualFr = sender2.distributeFlow(superToken, pool, fr2);
            assertEq(actualFr, superToken.getFlowRate(address(sender2), address(pool)), "step 2 unexpected actual flowrate");
            // distribute from sender2 amount2
            uint256 balBefore = superToken.balanceOf(address(sender2));
            uint256 actualAmount = sender2.distribute(superToken, pool, a2);
            assertEq(actualAmount, balBefore - superToken.balanceOf(address(sender2)), "step 2 unexpected actual amount");
        }

        // distributeFlow from sender1 flowRate3
        {
            int96 actualFr = sender1.distributeFlow(superToken, pool, fr3);
            assertEq(actualFr, superToken.getFlowRate(address(sender1), address(pool)), "step 3 unexpected actual flowrate");
            // distribute from sender1 amount3
            uint256 balBefore = superToken.balanceOf(address(sender1));
            uint256 actualAmount = sender1.distribute(superToken, pool, a3);
            assertEq(actualAmount, balBefore - superToken.balanceOf(address(sender1)), "step 3 unexpected actual amount");
        }
    }

    // tests flow[From]WithCtx by controlling flows to a mock SuperApp which mirrors/matches those flows using `flow[From]WithCtx`
    function testFlowWithCtx(bool useACL) external {
        SuperAppMock superApp = new SuperAppMock(sf.host);
        superApp.selfRegister(true, true, true);
        address superAppAddr = address(superApp);

        address flowSender = superAppAddr;
        address flowReceiver = address(this);

        if (useACL) {
            vm.startPrank(alice);
            superApp.setACLFlowSender();
            sf.host.callAgreement(
                sf.cfa,
                abi.encodeCall(sf.cfa.authorizeFlowOperatorWithFullControl, (superToken, superAppAddr, new bytes(0))),
                new bytes(0) // userData
            );
            vm.stopPrank();
            flowSender = alice;
        }

        // initial createFlow
        superToken.flow(superAppAddr, DEFAULT_FLOWRATE);
        assertEq(_getCFAFlowRate(flowSender, flowReceiver), DEFAULT_FLOWRATE, "createFlow unexpected result");

        // double it -> updateFlow
        superToken.flow(superAppAddr, DEFAULT_FLOWRATE * 2);
        assertEq(_getCFAFlowRate(flowSender, flowReceiver), DEFAULT_FLOWRATE * 2, "updateFlow unexpected result");

        if (! useACL) {
            // delete the mirrored flow (check if remains sticky)
            superToken.deleteFlow(superAppAddr, address(this));
            assertEq(_getCFAFlowRate(flowSender, flowReceiver), DEFAULT_FLOWRATE * 2, "flow not sticky");
        }

        // set to 0 -> deleteFlow
        superToken.flow(superAppAddr, 0);
        assertEq(_getCFAFlowRate(flowSender, flowReceiver), 0, "deleteFlow unexpected result");

        // invalid flowrate
        vm.expectRevert(IConstantFlowAgreementV1.CFA_INVALID_FLOW_RATE.selector);
        this.__external_flow(flowSender, superAppAddr, -1);

        assertFalse(sf.host.isAppJailed(ISuperApp(superAppAddr)), "superApp is jailed");
    }

    // HELPER FUNCTIONS ========================================================================================

    // direct use of the agreement for assertions
    function _getCFAFlowRate(address sender, address receiver) internal view returns (int96 flowRate) {
        (,flowRate,,) = sf.cfa.getFlow(superToken, sender, receiver);
    }

    // Note: this is without adjustmentFR
    function _getGDAFlowRate(address sender, ISuperfluidPool pool) internal view returns (int96 flowRate) {
        return sf.gda.getFlowRate(superToken, sender, pool);
    }

    function _assertDefaultPoolConfig(ISuperfluidPool pool) internal view {
        assertEq(pool.transferabilityForUnitsOwner(), false);
        assertEq(pool.distributionFromAnyAddress(), true);
    }

    function _boundFlowRate(int96 flowRate) internal pure returns (int96) {
        return int96(bound(flowRate, 1, int96(uint96(type(uint32).max))));
    }

    // helpers converting the lib call to an external call, for exception checking

    function __external_flow(address msgSender, address receiver, int96 flowRate) external {
        vm.startPrank(msgSender);
        superToken.flow(receiver, flowRate);
        vm.stopPrank();
    }

    function __external_flowFrom(address msgSender, address sender, address receiver, int96 flowRate) external {
        vm.startPrank(msgSender);
        superToken.flowFrom(sender, receiver, flowRate);
        vm.stopPrank();
    }
}


// needed to emulate "prank" for methods where prank doesn't work because of the lib using address(this)
contract CallProxy {
    function distributeFlow(ISuperToken token, ISuperfluidPool pool, int96 requestedFlowRate)
        external returns (int96 actualFlowRate)
    {
        return token.distributeFlow(pool, requestedFlowRate);
    }

    function distribute(ISuperToken token, ISuperfluidPool pool, uint256 requestedAmount)
        external returns (uint256 actualAmount)
    {
        return token.distribute(pool, requestedAmount);
    }
}


// SuperApp for testing withCtx methods.
// mirrors (default mode) or matches (ACL mode) the incoming flow
contract SuperAppMock is CFASuperAppBase {
    using SuperTokenV1Library for ISuperToken;

    // if not set (0), the SuperApp itself is the flowSender
    address aclFlowSender;

    constructor(ISuperfluid host) CFASuperAppBase(host) { }

    // enable ACL mode by setting a sender
    function setACLFlowSender() external {
        aclFlowSender = msg.sender;
    }

    function onFlowCreated(
        ISuperToken superToken,
        address sender,
        bytes calldata ctx
    ) internal virtual override returns (bytes memory /*newCtx*/) {
        return _mirrorOrMatchIncomingFlow(superToken, sender, ctx);
    }

    function onFlowUpdated(
        ISuperToken superToken,
        address sender,
        int96 /*previousFlowRate*/,
        uint256 /*lastUpdated*/,
        bytes calldata ctx
    ) internal virtual override returns (bytes memory /*newCtx*/) {
        return _mirrorOrMatchIncomingFlow(superToken, sender, ctx);
    }

    function onFlowDeleted(
        ISuperToken superToken,
        address sender,
        address receiver,
        int96 previousFlowRate,
        uint256 /*lastUpdated*/,
        bytes calldata ctx
    ) internal virtual override returns (bytes memory /*newCtx*/) {
        if (receiver == address(this)) {
            return _mirrorOrMatchIncomingFlow(superToken, sender, ctx);
        } else {
            // outflow was deleted by the sender we mirror to,
            // we make it "sticky" by simply restoring it.
            return superToken.flowWithCtx(receiver, previousFlowRate, ctx);
        }
    }

    function _mirrorOrMatchIncomingFlow(ISuperToken superToken, address senderAndReceiver, bytes memory ctx)
        internal returns (bytes memory newCtx)
    {
        int96 flowRate = superToken.getFlowRate(senderAndReceiver, address(this));
        if (aclFlowSender == address(0)) {
            return superToken.flowWithCtx(senderAndReceiver, flowRate, ctx);
        } else {
            return superToken.flowFromWithCtx(aclFlowSender, senderAndReceiver, flowRate, ctx);
        }
    }
}
