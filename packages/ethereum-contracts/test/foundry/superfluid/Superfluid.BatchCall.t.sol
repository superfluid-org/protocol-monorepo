// SPDX-License-Identifier: AGPLv3
pragma solidity ^0.8.23;

import { stdError } from "forge-std/Test.sol";

import { BatchOperation, ISuperfluid, Superfluid } from "../../../contracts/superfluid/Superfluid.sol";
import { SuperToken } from "../../../contracts/superfluid/SuperToken.sol";
import { IGeneralDistributionAgreementV1, ISuperfluidPool, PoolConfig } from "../../../contracts/interfaces/agreements/gdav1/IGeneralDistributionAgreementV1.sol";
import { IConstantFlowAgreementV1, ISuperToken, ISuperfluidToken } from "../../../contracts/interfaces/superfluid/ISuperfluid.sol";
import { FoundrySuperfluidTester } from "../FoundrySuperfluidTester.t.sol";
import { SuperTokenV1Library } from "../../../contracts/apps/SuperTokenV1Library.sol";
import { SuperAppMock } from "../../../contracts/mocks/SuperAppMocks.t.sol";
import { SimpleForwarder } from "../../../contracts/utils/SimpleForwarder.sol";
import { ERC2771Forwarder } from "../../../contracts/utils/ERC2771Forwarder.sol";
import { Ownable } from '@openzeppelin/contracts/access/Ownable.sol';
import { BaseRelayRecipient } from "../../../contracts/libs/BaseRelayRecipient.sol";

// A mock for an arbitrary external contract
contract TestContract {
    error SomeError();
    error IncorrectPayment();

    bool public stateChanged;

    function permissionlessFn() public returns (bool) {
        stateChanged = true;
        return true;
    }

    // accept native coins
    receive() external payable {}

    function pay(uint256 expectedAmount) external payable {
        if (msg.value != expectedAmount) revert IncorrectPayment();
    }

    function doRevert() external pure {
        revert SomeError();
    }
}

// A mock for an external contract that uses ERC-2771
contract TestContract2771 is TestContract, Ownable, BaseRelayRecipient {
    error NotOwner();

    // Expects the msgSender to be encoded in calldata as specified by ERC-2771.
    // Will revert if relayed for anybody but the contract owner.
    function privilegedFn() public returns (bool) {
        if (_getTransactionSigner() != owner()) revert NotOwner();
        stateChanged = true;
        return true;
    }

    // this can be used to check correct association of the payment
    function privilegedPay(uint256 expectedAmount) external payable {
        if (_getTransactionSigner() != owner()) revert NotOwner();
        if (msg.value != expectedAmount) revert IncorrectPayment();
    }

    /// @dev BaseRelayRecipient.isTrustedForwarder implementation
    function isTrustedForwarder(address /*forwarder*/) public view virtual override returns(bool) {
        // we don't enforce any restrictions for this test
        return true;
    }

    /// @dev IRelayRecipient.versionRecipient implementation
    function versionRecipient() external override pure returns (string memory) {
        return "v1";
    }
}

// Same as TestContract2771, but only trusts the host's ERC2771Forwarder
contract TestContract2771Checked is TestContract2771 {
    ISuperfluid internal _host;

    constructor(ISuperfluid host) {
        _host = host;
    }

    /// @dev BaseRelayRecipient.isTrustedForwarder implementation
    function isTrustedForwarder(address forwarder) public view override returns(bool) {
        return forwarder == address(_host.getERC2771Forwarder());
    }
}


contract SuperfluidBatchCallTest is FoundrySuperfluidTester {
    using SuperTokenV1Library for SuperToken;

    address someTrustedForwarder = address(0x1a1c);

    constructor() FoundrySuperfluidTester(3) { }

    function setUp() public override {
        super.setUp();
        vm.startPrank(address(sf.governance.owner()));
        sf.governance.enableTrustedForwarder(sf.host, ISuperToken(address(0)), someTrustedForwarder);
        vm.stopPrank();
    }

    function testRevertIfOperationIncreaseAllowanceIsNotCalledByHost(address notHost) public {
        vm.assume(notHost != address(sf.host));

        vm.expectRevert(ISuperfluidToken.SF_TOKEN_ONLY_HOST.selector);
        vm.prank(notHost);
        superToken.operationIncreaseAllowance(notHost, alice, 100);
    }

    function testRevertIfOperationDecreaseAllowanceIsNotCalledByHost(address notHost) public {
        vm.assume(notHost != address(sf.host));

        vm.expectRevert(ISuperfluidToken.SF_TOKEN_ONLY_HOST.selector);
        vm.prank(notHost);
        superToken.operationDecreaseAllowance(notHost, alice, 100);
    }

    function testRevertIfOperationDecreaseAllowanceUnderflows() public {
        vm.expectRevert("SuperToken: decreased allowance below zero");
        vm.prank(address(sf.host));
        superToken.operationDecreaseAllowance(alice, bob, 1);
    }

    function testRevertIfOperationIncreaseAllowanceOverflows() public {
        vm.startPrank(address(sf.host));
        superToken.operationIncreaseAllowance(alice, bob, type(uint256).max);
        vm.expectRevert(stdError.arithmeticError);
        superToken.operationIncreaseAllowance(alice, bob, 1);
        vm.stopPrank();
    }

    function testIfOperationIncreaseAllowanceIsCalledByHost() public {
        uint256 aliceToBobAllowanceBefore = superToken.allowance(alice, bob);

        vm.prank(address(sf.host));
        superToken.operationIncreaseAllowance(alice, bob, 100);
        uint256 aliceToBobAllowanceAfter = superToken.allowance(alice, bob);

        assertEq(aliceToBobAllowanceAfter, aliceToBobAllowanceBefore + 100);
    }

    function testIfOperationDecreaseAllowanceIsCalledByHost() public {
        uint256 aliceToBobAllowanceBefore = superToken.allowance(alice, bob);

        vm.startPrank(address(sf.host));
        superToken.operationIncreaseAllowance(alice, bob, 100);
        superToken.operationDecreaseAllowance(alice, bob, 31);
        vm.stopPrank();

        uint256 aliceToBobAllowanceAfter = superToken.allowance(alice, bob);
        assertEq(aliceToBobAllowanceAfter, aliceToBobAllowanceBefore + 69);
    }

    function testIncreaseAllowanceBatchCall(uint256 allowanceAmount) public {
        ISuperfluid.Operation[] memory ops = new ISuperfluid.Operation[](1);
        uint256 aliceToBobAllowanceBefore = superToken.allowance(alice, bob);
        ops[0] = ISuperfluid.Operation({
            operationType: BatchOperation.OPERATION_TYPE_ERC20_INCREASE_ALLOWANCE,
            target: address(superToken),
            data: abi.encode(bob, allowanceAmount)
        });
        vm.prank(alice);
        sf.host.batchCall(ops);
        uint256 aliceToBobAllowanceAfter = superToken.allowance(alice, bob);
        assertEq(aliceToBobAllowanceAfter, aliceToBobAllowanceBefore + allowanceAmount);
    }

    function testDecreaseAllowanceBatchCall(uint256 increaseAllowanceAmount, uint256 decreaseAllowanceAmount) public {
        vm.assume(increaseAllowanceAmount >= decreaseAllowanceAmount);

        ISuperfluid.Operation[] memory ops = new ISuperfluid.Operation[](1);
        vm.prank(alice);
        superToken.increaseAllowance(bob, increaseAllowanceAmount);
        uint256 aliceToBobAllowanceBefore = superToken.allowance(alice, bob);
        ops[0] = ISuperfluid.Operation({
            operationType: BatchOperation.OPERATION_TYPE_ERC20_DECREASE_ALLOWANCE,
            target: address(superToken),
            data: abi.encode(bob, decreaseAllowanceAmount)
        });
        vm.prank(alice);
        sf.host.batchCall(ops);
        uint256 aliceToBobAllowanceAfter = superToken.allowance(alice, bob);
        assertEq(aliceToBobAllowanceAfter, aliceToBobAllowanceBefore - decreaseAllowanceAmount);
    }

    function testIncreaseDecreaseTransferFromBatchCall() public {
        ISuperfluid.Operation[] memory ops = new ISuperfluid.Operation[](2);
        uint256 aliceToBobAllowanceBefore = superToken.allowance(alice, bob);
        uint256 bobBalanceBefore = superToken.balanceOf(bob);
        ops[0] = ISuperfluid.Operation({
            operationType: BatchOperation.OPERATION_TYPE_ERC20_INCREASE_ALLOWANCE,
            target: address(superToken),
            data: abi.encode(bob, 100)
        });
        ops[1] = ISuperfluid.Operation({
            operationType: BatchOperation.OPERATION_TYPE_ERC20_DECREASE_ALLOWANCE,
            target: address(superToken),
            data: abi.encode(bob, 50)
        });

        vm.prank(alice);
        sf.host.batchCall(ops);
        uint256 aliceToBobAllowanceAfter = superToken.allowance(alice, bob);
        assertEq(aliceToBobAllowanceAfter, aliceToBobAllowanceBefore + 50);

        vm.prank(bob);
        superToken.transferFrom(alice, bob, 50);
        uint256 bobBalanceAfter = superToken.balanceOf(bob);
        aliceToBobAllowanceAfter = superToken.allowance(alice, bob);
        assertEq(aliceToBobAllowanceAfter, 0);
        assertEq(bobBalanceAfter, bobBalanceBefore + 50);
    }

    function testIncreaseTransferAllowanceAndIncreaseFlowRateAllowance() public {
        ISuperfluid.Operation[] memory ops = new ISuperfluid.Operation[](2);
        uint256 aliceToBobAllowanceBefore = superToken.allowance(alice, bob);

        (,, int96 flowRateAllowanceBefore) = sf.cfa.getFlowOperatorData(superToken, alice, bob);

        ops[0] = ISuperfluid.Operation({
            operationType: BatchOperation.OPERATION_TYPE_ERC20_INCREASE_ALLOWANCE,
            target: address(superToken),
            data: abi.encode(bob, 100)
        });
        bytes memory increaseFlowRateAllowanceCallData =
            abi.encodeCall(IConstantFlowAgreementV1.increaseFlowRateAllowance, (superToken, bob, 100, new bytes(0)));
        ops[1] = ISuperfluid.Operation({
            operationType: BatchOperation.OPERATION_TYPE_SUPERFLUID_CALL_AGREEMENT,
            target: address(sf.cfa),
            data: abi.encode(increaseFlowRateAllowanceCallData, new bytes(0))
        });

        vm.prank(alice);
        sf.host.batchCall(ops);

        uint256 aliceToBobAllowanceAfter = superToken.allowance(alice, bob);
        (,, int96 flowRateAllowanceAfter) = sf.cfa.getFlowOperatorData(superToken, alice, bob);
        assertEq(aliceToBobAllowanceAfter, aliceToBobAllowanceBefore + 100);
        assertEq(flowRateAllowanceAfter, flowRateAllowanceBefore + 100);
    }

    function testBatchCallWithValue() public {
        SuperAppMock superAppMock = new SuperAppMock(sf.host, 0xF, false);
        ISuperfluid.Operation[] memory ops = new ISuperfluid.Operation[](2);
        // the ETH is forwraded with the first action.
        ops[0] = ISuperfluid.Operation({
            operationType: BatchOperation.OPERATION_TYPE_SUPERFLUID_CALL_APP_ACTION,
            target: address(superAppMock),
            data: abi.encodeCall(superAppMock.actionCallPayable, (""))
        });
        // Adding a 2nd action to make sure this is properly handled
        ops[1] = ISuperfluid.Operation({
            operationType: BatchOperation.OPERATION_TYPE_SUPERFLUID_CALL_APP_ACTION,
            target: address(superAppMock),
            data: abi.encodeCall(superAppMock.actionCallPayable, (""))
        });
        vm.deal(alice, 42);
        vm.prank(alice);
        sf.host.batchCall{value: 42}(ops);
        assertEq(address(superAppMock).balance, 42);
        assertEq(address(sf.host).balance, 0);
    }

    function testBatchCallWithValueFailIfNotForwarded() public {
        ISuperfluid.Operation[] memory ops = new ISuperfluid.Operation[](1);
        // random operation which doesn't consume the provided value
        ops[0] = ISuperfluid.Operation({
            operationType: BatchOperation.OPERATION_TYPE_ERC20_INCREASE_ALLOWANCE,
            target: address(superToken),
            data: abi.encode(bob, 100)
        });
        vm.deal(alice, 42);
        vm.prank(alice);
        sf.host.batchCall{value: 42}(ops);
        assertEq(address(alice).balance, 42);
        assertEq(address(sf.host).balance, 0);
    }

    function testBatchCallWithValueToNonPayableTarget() public {
        SuperAppMock superAppMock = new SuperAppMock(sf.host, 0xF, false);
        ISuperfluid.Operation[] memory ops = new ISuperfluid.Operation[](1);
        // the ETH is forwraded with the first action.
        ops[0] = ISuperfluid.Operation({
            operationType: BatchOperation.OPERATION_TYPE_SUPERFLUID_CALL_APP_ACTION,
            target: address(superAppMock),
            data: abi.encodeCall(superAppMock.actionCallActionNoop, (""))
        });
        vm.deal(alice, 42);
        vm.prank(alice);

        vm.expectRevert("CallUtils: target revert()");
        sf.host.batchCall{value: 42}(ops);
    }

    function testRevertIfOperationUpgradeToIsNotCalledByHost(address notHost) public {
        vm.assume(notHost != address(sf.host));

        vm.expectRevert(ISuperfluidToken.SF_TOKEN_ONLY_HOST.selector);
        vm.prank(notHost);
        superToken.operationUpgradeTo(alice, bob, 100);
    }

    function testUpgradeTo(uint256 amount) public {
        vm.assume(amount < type(uint64).max);

        vm.prank(alice);
        token.approve(address(superToken), amount);

        uint256 bobBalanceBefore = superToken.balanceOf(bob);
        vm.prank(address(sf.host));
        superToken.operationUpgradeTo(alice, bob, amount);
        uint256 bobBalanceAfter = superToken.balanceOf(bob);
        assertEq(bobBalanceAfter, bobBalanceBefore + amount, "Bob has unexpected final balance");
    }

    function testUpgradeToBatchCall(uint256 amount) public {
        vm.assume(amount < type(uint64).max);

        vm.prank(alice);
        token.approve(address(superToken), amount);

        ISuperfluid.Operation[] memory ops = new ISuperfluid.Operation[](1);
        uint256 bobBalanceBefore = superToken.balanceOf(bob);
        ops[0] = ISuperfluid.Operation({
            operationType: BatchOperation.OPERATION_TYPE_SUPERTOKEN_UPGRADE_TO,
            target: address(superToken),
            data: abi.encode(bob, amount)
        });
        vm.prank(alice);
        sf.host.batchCall(ops);
        uint256 bobBalanceAfter = superToken.balanceOf(bob);
        assertEq(bobBalanceAfter, bobBalanceBefore + amount, "Bob has unexpected final balance");
    }

    function testRevertIfOperationDowngradeToIsNotCalledByHost(address notHost) public {
        vm.assume(notHost != address(sf.host));

        vm.expectRevert(ISuperfluidToken.SF_TOKEN_ONLY_HOST.selector);
        vm.prank(notHost);
        superToken.operationDowngradeTo(alice, bob, 100);
    }

    function testDowngradeTo(uint256 amount) public {
        vm.assume(amount < type(uint64).max);

        uint256 bobBalanceBefore = token.balanceOf(bob);
        vm.prank(address(sf.host));
        superToken.operationDowngradeTo(alice, bob, amount);
        uint256 bobBalanceAfter = token.balanceOf(bob);
        assertEq(bobBalanceAfter, bobBalanceBefore + amount, "Bob has unexpected final balance");
    }

    function testDowngradeToBatchCall(uint256 amount) public {
        vm.assume(amount < type(uint64).max);

        ISuperfluid.Operation[] memory ops = new ISuperfluid.Operation[](1);
        uint256 bobBalanceBefore = token.balanceOf(bob);
        ops[0] = ISuperfluid.Operation({
            operationType: BatchOperation.OPERATION_TYPE_SUPERTOKEN_DOWNGRADE_TO,
            target: address(superToken),
            data: abi.encode(bob, amount)
        });
        vm.prank(alice);
        sf.host.batchCall(ops);
        uint256 bobBalanceAfter = token.balanceOf(bob);
        assertEq(bobBalanceAfter, bobBalanceBefore + amount, "Bob has unexpected final balance");
    }

    function testCallAgreementConnectPoolBatchCall() public {
        PoolConfig memory config = PoolConfig({ transferabilityForUnitsOwner: true, distributionFromAnyAddress: false });
        ISuperfluidPool pool = _helperCreatePool(superToken, alice, alice, false, config);

        ISuperfluid.Operation[] memory ops = new ISuperfluid.Operation[](1);
        bytes memory connectPoolCallData =
            abi.encodeCall(IGeneralDistributionAgreementV1.connectPool, (pool, new bytes(0)));
        ops[0] = ISuperfluid.Operation({
            operationType: BatchOperation.OPERATION_TYPE_SUPERFLUID_CALL_AGREEMENT,
            target: address(sf.gda),
            data: abi.encode(connectPoolCallData, new bytes(0))
        });

        vm.prank(alice);
        sf.host.batchCall(ops);

        assertTrue(sf.gda.isMemberConnected(pool, alice), "Alice: Pool is not connected");
    }

    function testSimpleForwardCall() public {
        SimpleForwarder forwarder = new SimpleForwarder();
        TestContract testContract = new TestContract();

        (bool success, bytes memory returnValue) = forwarder.forwardCall(
            address(testContract),
            abi.encodeCall(testContract.permissionlessFn, ())
        );
        // decoded return value
        bool retVal = abi.decode(returnValue, (bool));
        assertTrue(success, "SimpleForwarder: call failed");
        assertEq(retVal, true, "SimpleForwarder: unexpected return value");
    }

    function testSimpleForwardCallBatchCall() public {
        TestContract testContract = new TestContract();

        ISuperfluid.Operation[] memory ops = new ISuperfluid.Operation[](1);
        ops[0] = ISuperfluid.Operation({
            operationType: BatchOperation.OPERATION_TYPE_SIMPLE_FORWARD_CALL,
            target: address(testContract),
            data: abi.encodeCall(testContract.permissionlessFn, ())
        });
        sf.host.batchCall(ops);
        assertEq(testContract.stateChanged(), true, "TestContract: unexpected state");
    }

    function testSimpleForwardCallBatchCallRevert() public {
        TestContract testContract = new TestContract();

        ISuperfluid.Operation[] memory ops = new ISuperfluid.Operation[](1);
        ops[0] = ISuperfluid.Operation({
            operationType: BatchOperation.OPERATION_TYPE_SIMPLE_FORWARD_CALL,
            target: address(testContract),
            data: abi.encodeCall(testContract.doRevert, ())
        });

        vm.expectRevert(TestContract.SomeError.selector);
        sf.host.batchCall(ops);
    }

    function test2771ForwardCall() public {
        ERC2771Forwarder forwarder = new ERC2771Forwarder();

        TestContract2771 testContract = new TestContract2771();
        // alice has privileged access to the testContract
        testContract.transferOwnership(alice);

        // we relay a call for alice
        (bool success, bytes memory returnValue) = forwarder.forward2771Call(
            address(testContract),
            alice,
            abi.encodeCall(testContract.privilegedFn, ())
        );
        // decoded return value
        bool retVal = abi.decode(returnValue, (bool));
        assertTrue(success, "ERC2771Forwarder: call failed");
        assertEq(testContract.stateChanged(), true, "TestContract: unexpected state");
        assertEq(retVal, true, "ERC2771Forwarder: unexpected return value");

        // if relaying for bob, it should fail
        (success,) = forwarder.forward2771Call(
            address(testContract),
            bob,
            abi.encodeCall(testContract.privilegedFn, ())
        );
        assertFalse(success, "ERC2771Forwarder: call should have failed");

        // only the owner of the forwarder shall be allowed to relay
        vm.startPrank(eve);
        vm.expectRevert("Ownable: caller is not the owner");
        forwarder.forward2771Call(
            address(testContract),
            alice,
            abi.encodeCall(testContract.privilegedFn, ())
        );
        vm.stopPrank();
    }

    function test2771ForwardCallBatchCall() public {
        TestContract2771Checked testContract = new TestContract2771Checked(sf.host);
        testContract.transferOwnership(alice);

        ISuperfluid.Operation[] memory ops = new ISuperfluid.Operation[](1);
        ops[0] = ISuperfluid.Operation({
            operationType: BatchOperation.OPERATION_TYPE_ERC2771_FORWARD_CALL,
            target: address(testContract),
            data: abi.encodeCall(testContract.privilegedFn, ())
        });

        // should fail if called by bob (not the owner of testContract)
        vm.startPrank(bob);
        vm.expectRevert(TestContract2771.NotOwner.selector);
        sf.host.batchCall(ops);
        vm.stopPrank();

        // should succeed if called by alice
        vm.startPrank(alice);
        sf.host.batchCall(ops);
        assertEq(testContract.stateChanged(), true, "TestContract: unexpected state");
        vm.stopPrank();
    }

    function testSimpleForwardCallBatchCallWithValue() public {
        TestContract testContract = new TestContract();

        uint256 amount = 42;
        ISuperfluid.Operation[] memory ops = new ISuperfluid.Operation[](2);
        ops[0] = ISuperfluid.Operation({
            operationType: BatchOperation.OPERATION_TYPE_SIMPLE_FORWARD_CALL,
            target: address(testContract),
            data: abi.encodeCall(testContract.pay, (amount))
        });
        ops[1] = ISuperfluid.Operation({
            operationType: BatchOperation.OPERATION_TYPE_SIMPLE_FORWARD_CALL,
            target: address(testContract),
            data: abi.encodeCall(testContract.permissionlessFn, ())
        });

        // This shall work because we first forward native tokens to the contract,
        // then call the non-payable function
        sf.host.batchCall{value: amount}(ops);
        assertEq(address(testContract).balance, amount, "TestContract: unexpected balance");
    }

    function testSimpleForwardCallBatchCallWithValueUsingReceiveFn() public {
        TestContract testContract = new TestContract();

        uint256 amount = 42;
        ISuperfluid.Operation[] memory ops = new ISuperfluid.Operation[](2);
        ops[0] = ISuperfluid.Operation({
            operationType: BatchOperation.OPERATION_TYPE_SIMPLE_FORWARD_CALL,
            target: address(testContract),
            data: ""
        });
        ops[1] = ISuperfluid.Operation({
            operationType: BatchOperation.OPERATION_TYPE_SIMPLE_FORWARD_CALL,
            target: address(testContract),
            data: abi.encodeCall(testContract.permissionlessFn, ())
        });

        // the first operation shall forward the value, the second shall not (and thus succeed)
        sf.host.batchCall{value: amount}(ops);
        assertEq(address(testContract).balance, amount, "TestContract: unexpected balance");
    }

    function testSimpleForwardCallBatchCallWithValueUnsupportedOpsOrder() public {
        TestContract testContract = new TestContract();

        uint256 amount = 42;
        ISuperfluid.Operation[] memory ops = new ISuperfluid.Operation[](2);
        ops[0] = ISuperfluid.Operation({
            operationType: BatchOperation.OPERATION_TYPE_SIMPLE_FORWARD_CALL,
            target: address(testContract),
            data: abi.encodeCall(testContract.permissionlessFn, ())
        });
        ops[1] = ISuperfluid.Operation({
            operationType: BatchOperation.OPERATION_TYPE_SIMPLE_FORWARD_CALL,
            target: address(testContract),
            data: abi.encodeCall(testContract.pay, (amount))
        });

        // This fails because the native tokens are forwarded to the first operation,
        // which calls a non-payable function and thus reverts
        vm.expectRevert();
        sf.host.batchCall{value: amount}(ops);
    }

    function test2771ForwardCallBatchCallWithValue() public {
        TestContract2771Checked testContract = new TestContract2771Checked(sf.host);
        testContract.transferOwnership(alice);

        uint256 amount = 42;
        ISuperfluid.Operation[] memory ops = new ISuperfluid.Operation[](2);
        ops[0] = ISuperfluid.Operation({
            operationType: BatchOperation.OPERATION_TYPE_ERC2771_FORWARD_CALL,
            target: address(testContract),
            data: abi.encodeCall(testContract.privilegedPay, (amount))
        });
        ops[1] = ISuperfluid.Operation({
            operationType: BatchOperation.OPERATION_TYPE_ERC2771_FORWARD_CALL,
            target: address(testContract),
            data: abi.encodeCall(testContract.permissionlessFn, ())
        });

        vm.deal(alice, 1 ether);
        vm.startPrank(alice);
        sf.host.batchCall{value: amount}(ops);
        assertEq(address(testContract).balance, amount, "TestContract: unexpected test contract balance");
        vm.stopPrank();
    }

    function testRefundFromBatchCall() public {
        uint256 amount = 42;
        address sender = alice;

        vm.deal(sender, 1 ether);
        uint256 senderBalanceBefore = sender.balance;
        vm.startPrank(sender);
        sf.host.batchCall{value: amount}(new ISuperfluid.Operation[](0));
        vm.stopPrank();
        // no operation "consumed" the native tokens: we expect full refund
        assertEq(sender.balance, senderBalanceBefore, "batchCall sender: unexpected balance");
        assertEq(address(sf.host).balance, 0, "batchCall host: native tokens left");
    }

    function testRefundFromForwardBatchCall() public {
        uint256 amount = 42;

        vm.deal(someTrustedForwarder, 1 ether);
        vm.startPrank(someTrustedForwarder);
        bytes memory data = abi.encodeCall(sf.host.forwardBatchCall, (new ISuperfluid.Operation[](0)));
        // bob is 2771-encoded as msgSender
        (bool success, ) = address(sf.host).call{value: amount}(abi.encodePacked(data, bob));
        vm.stopPrank();
        // no operation "consumed" the native tokens: we expect full refund to bob
        assertTrue(success, "forwardBatchCall: call failed");
        assertEq(bob.balance, amount, "batchCall msgSender: unexpected balance");
        assertEq(address(sf.host).balance, 0, "batchCall host: native tokens left");
    }

    function testWithdrawLostNativeTokensFromSimpleForwarder() public {
        uint256 amount = 42;

        SimpleForwarder forwarder = new SimpleForwarder();

        // failing call which causes `amount` to get stuck in the forwarder contract
        (bool success, ) = forwarder.forwardCall{value: amount}(
            address(sf.host), new bytes(0x1));

        assertFalse(success, "SimpleForwarder: call should have failed");
        assertEq(address(forwarder).balance, amount, "SimpleForwarder: unexpected balance");

        // eve isn't allowed to withdraw
        vm.startPrank(eve);
        vm.expectRevert("Ownable: caller is not the owner");
        forwarder.withdrawLostNativeTokens(payable(bob));
        vm.stopPrank();

        // but we can withdraw
        forwarder.withdrawLostNativeTokens(payable(bob));
        assertEq(address(forwarder).balance, 0, "SimpleForwarder: balance still not 0");
        assertEq(bob.balance, amount, "SimpleForwarder: where did the money go?");
    }

    function testWithdrawLostNativeTokensFromERC2771Forwarder() public {
        uint256 amount = 42;

        ERC2771Forwarder forwarder = new ERC2771Forwarder();

        // failing call which causes `amount` to get stuck in the forwarder contract
        (bool success, ) = forwarder.forward2771Call{value: amount}(
            address(sf.host), address(this), new bytes(0x1));

        assertFalse(success, "ERC2771Forwarder: call should have failed");
        assertEq(address(forwarder).balance, amount, "ERC2771Forwarder: unexpected balance");

        // eve isn't allowed to withdraw
        vm.startPrank(eve);
        vm.expectRevert("Ownable: caller is not the owner");
        forwarder.withdrawLostNativeTokens(payable(bob));
        vm.stopPrank();

        // but we can withdraw
        forwarder.withdrawLostNativeTokens(payable(bob));
        assertEq(address(forwarder).balance, 0, "ERC2771Forwarder: balance still not 0");
        assertEq(bob.balance, amount, "ERC2771Forwarder: where did the money go?");
    }
}
