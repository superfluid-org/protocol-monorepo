// SPDX-License-Identifier: AGPLv3
pragma solidity ^0.8.23;

import { FoundrySuperfluidTester, SuperTokenV1Library } from "../FoundrySuperfluidTester.t.sol";
import {
    ISuperfluid,
    ISuperToken,
    IConstantOutflowNFT,
    IConstantInflowNFT,
    IPoolAdminNFT,
    IPoolMemberNFT,
    SuperToken
} from "../../../contracts/superfluid/SuperToken.sol";
import { ISuperfluidPool } from "../../../contracts/interfaces/agreements/gdav1/ISuperfluidPool.sol";
import { BatchLiquidator } from "../../../contracts/utils/BatchLiquidator.sol";
import "forge-std/Test.sol";

contract NonTransferableST is SuperToken {
    // transferFrom will always revert
    constructor(ISuperfluid host)
        SuperToken(
            host,
            IConstantOutflowNFT(address(0)),
            IConstantInflowNFT(address(0)),
            IPoolAdminNFT(address(0)),
            IPoolMemberNFT(address(0))
        ) // solhint-disable-next-line
            // no-empty-blocks
    { }

    function transferFrom(address, address, uint256) public pure override returns (bool) {
        revert();
    }

    function mintInternal(address to, uint256 amount) external {
        _mint(msg.sender, to, amount, false, /* invokeHook */ false, /* requireReceptionAck */ "", "");
    }
}

contract BatchLiquidatorTest is FoundrySuperfluidTester {
    using SuperTokenV1Library for ISuperToken;

    BatchLiquidator internal batchLiquidator;
    address internal liquidator = address(0x1234);

    int96 internal constant FLOW_RATE = 10000000000;

    ISuperToken badToken;

    constructor() FoundrySuperfluidTester(5) { }

    function setUp() public override {
        super.setUp();
        batchLiquidator = new BatchLiquidator(address(sf.host));
        badToken = new NonTransferableST(sf.host);
    }

    // Helpers

    function _transferAllToSink(address sender) internal {
        _helperTransferAll(superToken, sender, admin);
    }

    function _assertNoCFAFlow(address sender, address receiver) internal view {
        (, int96 flowRate,,) = sf.cfa.getFlow(superToken, sender, receiver);
        assertEq(flowRate, 0, "BatchLiquidator: CFA Flowrate should be 0");
    }

    function _assertNoGDAFlow(address sender, ISuperfluidPool pool) internal view {
        int96 flowRate = sf.gda.getFlowRate(superToken, sender, pool);
        assertEq(flowRate, 0, "BatchLiquidator: GDA Flowrate should be 0");
    }

    function _assertLiquidatorBalanceGreater(address _liqudidator, uint256 balanceBefore_) internal view {
        assertGt(
            superToken.balanceOf(_liqudidator),
            balanceBefore_,
            "BatchLiquidator: SL - Balance should be greater than before"
        );
    }

    function _createCFAFlowLiquidationData(address sender, address receiver)
        internal
        pure
        returns (BatchLiquidator.FlowLiquidationData memory)
    {
        return BatchLiquidator.FlowLiquidationData({
            agreementOperation: BatchLiquidator.FlowType.ConstantFlowAgreement,
            sender: sender,
            receiver: receiver
        });
    }

    function _createGDAFlowLiquidationData(address sender, ISuperfluidPool pool)
        internal
        pure
        returns (BatchLiquidator.FlowLiquidationData memory)
    {
        return BatchLiquidator.FlowLiquidationData({
            agreementOperation: BatchLiquidator.FlowType.GeneralDistributionAgreement,
            sender: sender,
            receiver: address(pool)
        });
    }

    function testCFAOnlySingleLiquidation() public {
        _helperCreateFlow(superToken, alice, bob, FLOW_RATE);
        _transferAllToSink(alice);

        vm.startPrank(liquidator);
        uint256 balanceBefore = superToken.balanceOf(liquidator);
        vm.warp(4 hours); // jump 4 hours
        batchLiquidator.deleteFlow(address(superToken), _createCFAFlowLiquidationData(alice, bob));
        _assertNoCFAFlow(alice, bob);

        _assertLiquidatorBalanceGreater(liquidator, balanceBefore);
        vm.stopPrank();
    }

    function testGDAOnlySingleLiquidation() public {
        ISuperfluidPool pool = _helperCreatePool(superToken, alice, alice);
        _helperUpdateMemberUnits(pool, alice, bob, 1);
        _helperDistributeFlow(superToken, alice, alice, pool, FLOW_RATE);

        _transferAllToSink(alice);

        vm.startPrank(liquidator);
        uint256 balanceBefore = superToken.balanceOf(liquidator);
        vm.warp(4 hours); // jump 4 hours
        batchLiquidator.deleteFlow(address(superToken), _createGDAFlowLiquidationData(alice, pool));
        _assertNoGDAFlow(alice, pool);

        _assertLiquidatorBalanceGreater(liquidator, balanceBefore);
        vm.stopPrank();
    }

    function testCFAOnlySingleLiquidationRevert() public {
        vm.startPrank(liquidator);
        vm.expectRevert();
        batchLiquidator.deleteFlow(address(superToken), _createCFAFlowLiquidationData(alice, bob));
        vm.stopPrank();
    }

    function testGDAOnlySingleLiquidationRevert() public {
        ISuperfluidPool pool = _helperCreatePool(superToken, alice, alice);
        vm.startPrank(liquidator);
        vm.expectRevert();
        batchLiquidator.deleteFlow(address(superToken), _createGDAFlowLiquidationData(alice, pool));
        vm.stopPrank();
    }

    function testCFAOnlyBatchLiquidation() public {
        _helperCreateFlow(superToken, alice, bob, FLOW_RATE);
        _helperCreateFlow(superToken, carol, bob, FLOW_RATE);
        _helperCreateFlow(superToken, dan, bob, FLOW_RATE);

        _transferAllToSink(alice);
        _transferAllToSink(carol);
        _transferAllToSink(dan);

        vm.startPrank(liquidator);
        uint256 balanceBefore = superToken.balanceOf(liquidator);
        vm.warp(4 hours); // jump 4 hours
        BatchLiquidator.FlowLiquidationData[] memory data = new BatchLiquidator.FlowLiquidationData[](3);
        data[0] = _createCFAFlowLiquidationData(alice, bob);
        data[1] = _createCFAFlowLiquidationData(carol, bob);
        data[2] = _createCFAFlowLiquidationData(dan, bob);

        batchLiquidator.deleteFlows(address(superToken), data);

        _assertNoCFAFlow(alice, bob);
        _assertNoCFAFlow(carol, bob);
        _assertNoCFAFlow(dan, bob);

        _assertLiquidatorBalanceGreater(liquidator, balanceBefore);
        vm.stopPrank();
    }

    function testGDAOnlyBatchLiquidation() public {
        ISuperfluidPool pool = _helperCreatePool(superToken, alice, alice);
        _helperUpdateMemberUnits(pool, alice, bob, 1);
        _helperDistributeFlow(superToken, alice, alice, pool, FLOW_RATE);
        _helperDistributeFlow(superToken, carol, carol, pool, FLOW_RATE);
        _helperDistributeFlow(superToken, dan, dan, pool, FLOW_RATE);

        int96 flowRate = sf.gda.getFlowRate(superToken, alice, pool);

        _transferAllToSink(alice);
        _transferAllToSink(carol);
        _transferAllToSink(dan);

        vm.startPrank(liquidator);
        uint256 balanceBefore = superToken.balanceOf(liquidator);
        vm.warp(4 hours); // jump 4 hours
        BatchLiquidator.FlowLiquidationData[] memory data = new BatchLiquidator.FlowLiquidationData[](3);
        data[0] = _createGDAFlowLiquidationData(alice, pool);
        data[1] = _createGDAFlowLiquidationData(carol, pool);
        data[2] = _createGDAFlowLiquidationData(dan, pool);
        batchLiquidator.deleteFlows(address(superToken), data);

        flowRate = sf.gda.getFlowRate(superToken, alice, pool);

        _assertNoGDAFlow(alice, pool);
        _assertNoGDAFlow(carol, pool);
        _assertNoGDAFlow(dan, pool);

        _assertLiquidatorBalanceGreater(liquidator, balanceBefore);
        vm.stopPrank();
    }

    function testCFAOnlyBatchLiquidationWithToleratedRevert() public {
        _helperCreateFlow(superToken, alice, bob, FLOW_RATE);
        _helperCreateFlow(superToken, dan, bob, FLOW_RATE);

        _transferAllToSink(alice);
        _transferAllToSink(dan);

        vm.startPrank(liquidator);
        uint256 balanceBefore = superToken.balanceOf(liquidator);
        vm.warp(4 hours); // jump 4 hours
        BatchLiquidator.FlowLiquidationData[] memory data = new BatchLiquidator.FlowLiquidationData[](3);
        data[0] = _createCFAFlowLiquidationData(alice, bob);
        data[1] = _createCFAFlowLiquidationData(carol, bob);
        data[2] = _createCFAFlowLiquidationData(dan, bob);

        batchLiquidator.deleteFlows(address(superToken), data);
        _assertNoCFAFlow(alice, bob);
        _assertNoCFAFlow(carol, bob);
        _assertNoCFAFlow(dan, bob);

        _assertLiquidatorBalanceGreater(liquidator, balanceBefore);
        vm.stopPrank();
    }

    function testGDAOnlyBatchLiquidationWithToleratedRevert() public {
        ISuperfluidPool pool = _helperCreatePool(superToken, alice, alice);
        _helperUpdateMemberUnits(pool, alice, bob, 1);
        _helperDistributeFlow(superToken, alice, alice, pool, FLOW_RATE);
        _helperDistributeFlow(superToken, dan, dan, pool, FLOW_RATE);

        int96 flowRate = sf.gda.getFlowRate(superToken, alice, pool);

        _transferAllToSink(alice);
        _transferAllToSink(dan);

        vm.startPrank(liquidator);
        uint256 balanceBefore = superToken.balanceOf(liquidator);
        vm.warp(4 hours); // jump 4 hours
        BatchLiquidator.FlowLiquidationData[] memory data = new BatchLiquidator.FlowLiquidationData[](3);
        data[0] = _createGDAFlowLiquidationData(alice, pool);
        data[1] = _createGDAFlowLiquidationData(carol, pool);
        data[2] = _createGDAFlowLiquidationData(dan, pool);

        batchLiquidator.deleteFlows(address(superToken), data);

        flowRate = sf.gda.getFlowRate(superToken, alice, pool);

        _assertNoGDAFlow(alice, pool);
        _assertNoGDAFlow(carol, pool);
        _assertNoGDAFlow(dan, pool);

        _assertLiquidatorBalanceGreater(liquidator, balanceBefore);
        vm.stopPrank();
    }

    function testBatchLiquidation() public {
        ISuperfluidPool pool = _helperCreatePool(superToken, alice, alice);
        _helperUpdateMemberUnits(pool, alice, bob, 1);
        _helperDistributeFlow(superToken, alice, alice, pool, FLOW_RATE);

        _helperCreateFlow(superToken, carol, bob, FLOW_RATE);
        _helperCreateFlow(superToken, dan, bob, FLOW_RATE);

        _transferAllToSink(alice);
        _transferAllToSink(carol);
        _transferAllToSink(dan);

        vm.startPrank(liquidator);
        uint256 balanceBefore = superToken.balanceOf(liquidator);
        vm.warp(4 hours); // jump 4 hours
        BatchLiquidator.FlowLiquidationData[] memory data = new BatchLiquidator.FlowLiquidationData[](4);
        data[0] = _createGDAFlowLiquidationData(alice, pool);
        data[1] = _createCFAFlowLiquidationData(carol, bob);
        data[2] = _createCFAFlowLiquidationData(dan, bob);

        batchLiquidator.deleteFlows(address(superToken), data);

        _assertNoGDAFlow(alice, pool);
        _assertNoCFAFlow(carol, bob);
        _assertNoCFAFlow(dan, bob);

        _assertLiquidatorBalanceGreater(liquidator, balanceBefore);
        vm.stopPrank();
    }

    function testBatchLiquidationWithToleratedRevert() public {
        ISuperfluidPool pool = _helperCreatePool(superToken, alice, alice);
        _helperUpdateMemberUnits(pool, alice, bob, 1);
        _helperDistributeFlow(superToken, alice, alice, pool, FLOW_RATE);

        _helperCreateFlow(superToken, dan, bob, FLOW_RATE);

        _transferAllToSink(alice);
        _transferAllToSink(dan);

        vm.startPrank(liquidator);
        uint256 balanceBefore = superToken.balanceOf(liquidator);
        vm.warp(4 hours); // jump 4 hours
        BatchLiquidator.FlowLiquidationData[] memory data = new BatchLiquidator.FlowLiquidationData[](4);

        data[0] = _createGDAFlowLiquidationData(alice, pool);
        data[1] = _createCFAFlowLiquidationData(carol, bob);
        data[2] = _createCFAFlowLiquidationData(dan, bob);

        batchLiquidator.deleteFlows(address(superToken), data);

        _assertNoGDAFlow(alice, pool);
        _assertNoCFAFlow(carol, bob);
        _assertNoCFAFlow(dan, bob);

        _assertLiquidatorBalanceGreater(liquidator, balanceBefore);
        vm.stopPrank();
    }

    function testCFALiquidationWithCustomTokenRevert() public {
        NonTransferableST(address(badToken)).mintInternal(alice, 10 ether);

        vm.startPrank(alice);
        badToken.createFlow(bob, FLOW_RATE);
        badToken.transferAll(admin);
        vm.warp(4 hours); // jump 4 hours
        vm.stopPrank();
        vm.startPrank(liquidator);

        BatchLiquidator.FlowLiquidationData memory data = _createCFAFlowLiquidationData(alice, bob);

        batchLiquidator.deleteFlow(address(badToken), data);
        _assertNoCFAFlow(alice, bob);

        assertTrue(superToken.balanceOf(liquidator) == 0, "BatchLiquidator: SL - Balance should be 0 because of revert");
        vm.stopPrank();
    }

    function testCFABatchLiquidationWithCustomTokenRevert() public {
        NonTransferableST(address(badToken)).mintInternal(alice, 10 ether);
        NonTransferableST(address(badToken)).mintInternal(bob, 10 ether);

        vm.startPrank(alice);
        badToken.createFlow(bob, FLOW_RATE);
        badToken.transferAll(admin);
        vm.stopPrank();

        vm.startPrank(bob);
        badToken.createFlow(carol, FLOW_RATE);
        badToken.transferAll(admin);
        vm.stopPrank();

        vm.warp(4 hours); // jump 4 hours

        vm.startPrank(liquidator);

        BatchLiquidator.FlowLiquidationData[] memory data = new BatchLiquidator.FlowLiquidationData[](2);
        data[0] = _createCFAFlowLiquidationData(alice, bob);
        data[1] = _createCFAFlowLiquidationData(bob, carol);

        batchLiquidator.deleteFlows(address(superToken), data);
        _assertNoCFAFlow(alice, bob);
        _assertNoCFAFlow(bob, carol);
    }
}
