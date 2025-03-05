// SPDX-License-Identifier: AGPLv3
pragma solidity ^0.8.23;

import { ISuperfluid, BatchOperation } from "../../../contracts/interfaces/superfluid/ISuperfluid.sol";
import { ISuperToken } from "../../../contracts/superfluid/SuperToken.sol";
import { IConstantFlowAgreementV1 } from "../../../contracts/interfaces/agreements/IConstantFlowAgreementV1.sol";
import { MacroForwarder, IUserDefinedMacro } from "../../../contracts/utils/MacroForwarder.sol";
import { FoundrySuperfluidTester, SuperTokenV1Library } from "../FoundrySuperfluidTester.t.sol";

using SuperTokenV1Library for ISuperToken;

// ============== Macro Contracts ==============

// not overriding IUserDefinedMacro here in order to avoid the compiler enforcing the function to be view-only.
contract NaugthyMacro {
    int naughtyCounter = -1;

    constructor(bool beNaughty) {
        if (beNaughty) naughtyCounter = 0;
    }

    // if naughtyCounter >= 0, this changes state, which leads to a revert in the context of a macro call
    function buildBatchOperations(ISuperfluid, bytes memory, address /*msgSender*/) external
        returns (ISuperfluid.Operation[] memory /*operation*/)
    {
        // Do the naughty thing (updating state as an expected view function)
        if (naughtyCounter >= 0) {
            naughtyCounter++;
        }
        return new ISuperfluid.Operation[](0);
    }

    function postCheck(ISuperfluid host, bytes memory params, address msgSender) external view { }
}

contract GoodMacro is IUserDefinedMacro {
    function buildBatchOperations(ISuperfluid host, bytes memory params, address /*msgSender*/) external override view
        returns (ISuperfluid.Operation[] memory operations)
    {
        // host-agnostic deployment. alternatively, you may hard code cfa too
        IConstantFlowAgreementV1 cfa = IConstantFlowAgreementV1(address(host.getAgreementClass(
            keccak256("org.superfluid-finance.agreements.ConstantFlowAgreement.v1")
        )));
        // parse params
        (ISuperToken token, int96 flowRate, address[] memory recipients) =
            abi.decode(params, (ISuperToken, int96, address[]));
        // construct batch operations
        operations = new ISuperfluid.Operation[](recipients.length);
        // Build batch call operations here
        for (uint i = 0; i < recipients.length; ++i) {
            bytes memory callData = abi.encodeCall(cfa.createFlow,
                                                   (token,
                                                    recipients[i],
                                                    flowRate,
                                                    new bytes(0) // placeholder
                                                   ));
            operations[i] = ISuperfluid.Operation({
                operationType : BatchOperation.OPERATION_TYPE_SUPERFLUID_CALL_AGREEMENT, // type
                target: address(cfa),
                data: abi.encode(callData, new bytes(0))
            });
        }
    }

    function postCheck(ISuperfluid host, bytes memory params, address msgSender) external view { }

    // recommended view function for parameter encoding
    function paramsCreateFlows(ISuperToken token, int96 flowRate, address[] calldata recipients) external pure returns (bytes memory) {
        return abi.encode(token, flowRate, recipients);
    }
}

// deletes a bunch of flows from one sender to muliple receivers
contract MultiFlowDeleteMacro is IUserDefinedMacro {
    error InsufficientReward();

    function buildBatchOperations(ISuperfluid host, bytes memory params, address /*msgSender*/) external override view
        returns (ISuperfluid.Operation[] memory operations)
    {
        IConstantFlowAgreementV1 cfa = IConstantFlowAgreementV1(address(host.getAgreementClass(
            keccak256("org.superfluid-finance.agreements.ConstantFlowAgreement.v1")
        )));

        // parse params
        (ISuperToken token, address sender, address[] memory receivers,) =
            abi.decode(params, (ISuperToken, address, address[], uint256));

        // construct batch operations
        operations = new ISuperfluid.Operation[](receivers.length);
        for (uint i = 0; i < receivers.length; ++i) {
            bytes memory callData = abi.encodeCall(cfa.deleteFlow,
                                                   (token,
                                                    sender,
                                                    receivers[i],
                                                    new bytes(0) // placeholder
                                                   ));
            operations[i] = ISuperfluid.Operation({
                operationType : BatchOperation.OPERATION_TYPE_SUPERFLUID_CALL_AGREEMENT, // type
                target: address(cfa),
                data: abi.encode(callData, new bytes(0))
            });
        }
    }

    // recommended view function for parameter encoding
    function paramsDeleteFlows(ISuperToken superToken, address sender, address[] memory receivers, uint256 minBalanceAfter)
        external pure
        returns (bytes memory)
    {
        return abi.encode(superToken, sender, receivers, minBalanceAfter);
    }

    function postCheck(ISuperfluid /*host*/, bytes memory params, address msgSender) external view {
        // parse params
        (ISuperToken superToken,,, uint256 minBalanceAfter) =
            abi.decode(params, (ISuperToken, address, address[], uint256));
        if (superToken.balanceOf(msgSender) < minBalanceAfter) {
            revert InsufficientReward();
        }
    }
}

/*
 * Example for a macro which has auint8 state needed, thus needs no additionalata
 * in the context of batch calls.
 * Important: state changes do NOT take place in the context of macro calls.
 */
contract StatefulMacro is IUserDefinedMacro {
    struct Config {
        MacroForwarder macroForwarder;
        ISuperToken superToken;
        int96 flowRate;
        address[] recipients;
        address referrer;
    }
    Config public config;

    // imagine this to be permissioned, e.g. using Ownable
    function setConfig(Config memory config_) public {
        config = config_;
    }

    function buildBatchOperations(ISuperfluid host, bytes memory /*params*/, address /*msgSender*/)
        external override view
        returns (ISuperfluid.Operation[] memory operations)
    {
        // host-agnostic deployment. alternatively, you may hard code cfa too
        IConstantFlowAgreementV1 cfa = IConstantFlowAgreementV1(address(host.getAgreementClass(
            keccak256("org.superfluid-finance.agreements.ConstantFlowAgreement.v1")
        )));

        // construct batch operations from persisted config
        operations = new ISuperfluid.Operation[](config.recipients.length);
        for (uint i = 0; i < config.recipients.length; ++i) {
            bytes memory callData = abi.encodeCall(cfa.createFlow,
                                                   (config.superToken,
                                                    config.recipients[i],
                                                    config.flowRate,
                                                    new bytes(0) // placeholder
                                                   ));
            operations[i] = ISuperfluid.Operation({
                operationType : BatchOperation.OPERATION_TYPE_SUPERFLUID_CALL_AGREEMENT, // type
                target: address(cfa),
                data: abi.encode(callData, abi.encode(config.referrer))
            });
        }
    }

    function postCheck(ISuperfluid host, bytes memory params, address msgSender) external view { }
}

/// Example for a macro which takes a fee for CFA operations
contract PaidCFAOpsMacro is IUserDefinedMacro {
    uint8 constant ACTION_CODE_CREATE_FLOW = 0;
    uint8 constant ACTION_CODE_UPDATE_FLOW = 1;
    uint8 constant ACTION_CODE_DELETE_FLOW = 2;

    address payable immutable FEE_RECEIVER;
    uint256 immutable FEE_AMOUNT;

    error UnknownAction();
    error FeeOverpaid();

    constructor(address payable feeReceiver, uint256 feeAmount) {
        FEE_RECEIVER = feeReceiver;
        FEE_AMOUNT = feeAmount;
    }

    function buildBatchOperations(ISuperfluid host, bytes memory params, address /*msgSender*/) external override view
        returns (ISuperfluid.Operation[] memory operations)
    {
        IConstantFlowAgreementV1 cfa = IConstantFlowAgreementV1(address(host.getAgreementClass(
            keccak256("org.superfluid-finance.agreements.ConstantFlowAgreement.v1")
        )));

        // first operation: take fee
        operations = new ISuperfluid.Operation[](2);

        operations[0] = ISuperfluid.Operation({
            operationType: BatchOperation.OPERATION_TYPE_SIMPLE_FORWARD_CALL,
            target: address(this),
            data: abi.encodeCall(this.takeFee, (FEE_AMOUNT))
        });

        // second operation: manage flow
        // param parsing is now a 2-step process.
        // first we parse the actionCode, then depending on its value the arguments
        (uint8 actionCode, bytes memory actionArgs) = abi.decode(params, (uint8, bytes));
        if (actionCode == ACTION_CODE_CREATE_FLOW) {
            (ISuperToken token, address receiver, int96 flowRate) =
                abi.decode(actionArgs, (ISuperToken, address, int96));
            operations[1] = ISuperfluid.Operation({
                operationType: BatchOperation.OPERATION_TYPE_SUPERFLUID_CALL_AGREEMENT,
                target: address(cfa),
                data: abi.encode(
                    abi.encodeCall(
                        cfa.createFlow,
                        (token, receiver, flowRate, new bytes(0))
                    ),
                    new bytes(0) // userdata
                )
            });
        } else if (actionCode == ACTION_CODE_UPDATE_FLOW) {
            (ISuperToken token, address receiver, int96 flowRate) =
                abi.decode(actionArgs, (ISuperToken, address, int96));
            operations[1] = ISuperfluid.Operation({
                operationType: BatchOperation.OPERATION_TYPE_SUPERFLUID_CALL_AGREEMENT,
                target: address(cfa),
                data: abi.encode(
                    abi.encodeCall(
                        cfa.updateFlow,
                        (token, receiver, flowRate, new bytes(0))
                    ),
                    new bytes(0) // userdata
                )
            });
        } else if (actionCode == ACTION_CODE_DELETE_FLOW) {
            (ISuperToken token, address sender, address receiver) =
                abi.decode(actionArgs, (ISuperToken, address, address));
            operations[1] = ISuperfluid.Operation({
                operationType: BatchOperation.OPERATION_TYPE_SUPERFLUID_CALL_AGREEMENT,
                target: address(cfa),
                data: abi.encode(
                    abi.encodeCall(
                        cfa.deleteFlow,
                        (token, sender, receiver, new bytes(0))
                    ),
                    new bytes(0) // userdata
                )
            });
        } else {
            revert UnknownAction();
        }
    }

    // Forwards a fee in native tokens to the FEE_RECEIVER.
    // Will fail if less than `amount` is provided.
    function takeFee(uint256 amount) external payable {
        FEE_RECEIVER.transfer(amount);
    }

    // Don't allow native tokens in excess of the required fee
    // Note: this is safe only as long as this contract can't receive native tokens through other means,
    // e.g. by implementing a fallback or receive function.
    function postCheck(ISuperfluid /*host*/, bytes memory /*params*/, address /*msgSender*/) external view {
        if (address(this).balance != 0) revert FeeOverpaid();
    }

    // recommended view functions for parameter construction
    // since this is a multi-method macro, a dispatch logic using actionCode codes is applied.

    // view function for getting params for createFlow
    function encodeCreateFlow(ISuperToken token, address receiver, int96 flowRate) external pure returns (bytes memory) {
        return abi.encode(
            ACTION_CODE_CREATE_FLOW, // actionCode
            abi.encode(token, receiver, flowRate) // actionArgs
        );
    }

    // view function for getting params for updateFlow
    function encodeUpdateFlow(ISuperToken token, address receiver, int96 flowRate) external pure returns (bytes memory) {
        return abi.encode(
            ACTION_CODE_UPDATE_FLOW, // actionCode
            abi.encode(token, receiver, flowRate) // actionArgs
        );
    }

    // view function for getting params for deleteFlow
    function encodeDeleteFlow(ISuperToken token, address sender, address receiver) external pure returns (bytes memory) {
        return abi.encode(
            ACTION_CODE_DELETE_FLOW, // actionCode
            abi.encode(token, sender, receiver) // actionArgs
        );
    }
}

// ============== Test Contract ==============

contract MacroForwarderTest is FoundrySuperfluidTester {
    constructor() FoundrySuperfluidTester(5) {
    }

    function testDummyMacro() external {
        NaugthyMacro m = new NaugthyMacro(false /* not naughty */);
        sf.macroForwarder.runMacro(IUserDefinedMacro(address(m)), new bytes(0));
    }

    function testNaugtyMacro() external {
        NaugthyMacro m = new NaugthyMacro(true /* naughty */);
        vm.expectRevert();
        // Note: need to cast the naughty macro
        sf.macroForwarder.runMacro(IUserDefinedMacro(address(m)), new bytes(0));
    }

    function testGoodMacro() external {
        GoodMacro m = new GoodMacro();
        address[] memory recipients = new address[](2);
        recipients[0] = bob;
        recipients[1] = carol;
        vm.startPrank(admin);
        // NOTE! This is different from abi.encode(superToken, int96(42), [bob, carol]),
        //       which is a fixed array: address[2].
        sf.macroForwarder.runMacro(m, m.paramsCreateFlows(superToken, int96(42), recipients));
        assertEq(sf.cfa.getNetFlow(superToken, bob), 42);
        assertEq(sf.cfa.getNetFlow(superToken, carol), 42);
        vm.stopPrank();
    }

    function testStatefulMacro() external {
        address[] memory recipients = new address[](2);
        recipients[0] = bob;
        recipients[1] = carol;
        StatefulMacro m = new StatefulMacro();
        m.setConfig(StatefulMacro.Config(
                sf.macroForwarder, superToken, 42, recipients, dan
        ));
        vm.startPrank(admin);
        sf.macroForwarder.runMacro(m, new bytes(0));
        assertEq(sf.cfa.getNetFlow(superToken, bob), 42);
        assertEq(sf.cfa.getNetFlow(superToken, carol), 42);
        vm.stopPrank();
    }

    function testMultiFlowDeleteMacro() external {
        MultiFlowDeleteMacro m = new MultiFlowDeleteMacro();
        address sender = alice;
        address[] memory recipients = new address[](3);
        recipients[0] = bob;
        recipients[1] = carol;
        recipients[2] = dan;

        vm.startPrank(sender);
        // flows to be deleted need to exist in the first place
        for (uint i = 0; i < recipients.length; ++i) {
            superToken.createFlow(recipients[i], 42);
        }
        // now batch-delete them
        sf.macroForwarder.runMacro(m, m.paramsDeleteFlows(superToken, sender, recipients, 0));

        for (uint i = 0; i < recipients.length; ++i) {
            assertEq(sf.cfa.getNetFlow(superToken, recipients[i]), 0);
        }
        vm.stopPrank();
    }

    function testPostCheck() external {
        MultiFlowDeleteMacro m = new MultiFlowDeleteMacro();
        address[] memory recipients = new address[](2);
        recipients[0] = bob;
        recipients[1] = carol;
        int96 flowRate = 1e18;

        vm.startPrank(alice);
        // flows to be deleted need to exist in the first place
        for (uint i = 0; i < recipients.length; ++i) {
            superToken.createFlow(recipients[i], flowRate);
        }
        vm.stopPrank();

        // fast forward 3000 days
        vm.warp(block.timestamp + 86400*3000);

        // alice is now insolvent, dan can batch-delete the flows
        vm.startPrank(dan);
        uint256 danBalanceBefore = superToken.balanceOf(dan);
        // unreasonable reward expectation: post check fails
        vm.expectRevert(MultiFlowDeleteMacro.InsufficientReward.selector);
        sf.macroForwarder.runMacro(m, abi.encode(superToken, alice, recipients, danBalanceBefore + 1e24));

        // reasonable reward expectation: post check passes
        sf.macroForwarder.runMacro(m, abi.encode(superToken, alice, recipients, danBalanceBefore + (uint256(uint96(flowRate)) * 600)));
    }

    function testPaidCFAOps() external {
        address payable feeReceiver = payable(address(0x420));
        uint256 feeAmount = 1e15;
        int96 flowRate1 = 42;
        int96 flowRate2 = 42;

        // alice needs funds for fee payment
        vm.deal(alice, 1 ether);

        PaidCFAOpsMacro m = new PaidCFAOpsMacro(feeReceiver, feeAmount);

        vm.startPrank(alice);

        // alice creates a flow to bob
        sf.macroForwarder.runMacro{value: feeAmount}(
            m,
            m.encodeCreateFlow(superToken, bob, flowRate1)
        );
        assertEq(feeReceiver.balance, feeAmount, "unexpected fee receiver balance");
        assertEq(sf.cfa.getNetFlow(superToken, bob), flowRate1);

        // ... then updates that flow
        sf.macroForwarder.runMacro{value: feeAmount}(
            m,
            m.encodeUpdateFlow(superToken, bob, flowRate2)
        );
        assertEq(feeReceiver.balance, feeAmount * 2, "unexpected fee receiver balance");
        assertEq(sf.cfa.getNetFlow(superToken, bob), flowRate2);

        // ... and finally deletes it
        sf.macroForwarder.runMacro{value: feeAmount}(
            m,
            m.encodeDeleteFlow(superToken, alice, bob)
        );
        assertEq(feeReceiver.balance, feeAmount * 3, "unexpected fee receiver balance");
        assertEq(sf.cfa.getNetFlow(superToken, bob), 0);
    }
}