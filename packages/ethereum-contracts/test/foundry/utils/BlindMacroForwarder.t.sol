// SPDX-License-Identifier: AGPLv3
pragma solidity ^0.8.23;

// forge-lint: disable-start(unsafe-typecast, erc20-unchecked-transfer)

import { ISuperfluid, BatchOperation } from "../../../contracts/interfaces/superfluid/ISuperfluid.sol";
import { ISuperToken } from "../../../contracts/superfluid/SuperToken.sol";
import { IConstantFlowAgreementV1 } from "../../../contracts/interfaces/agreements/IConstantFlowAgreementV1.sol";
import { IMacro } from "../../../contracts/interfaces/utils/IMacro.sol";
import { BlindMacroForwarder } from "../../../contracts/utils/BlindMacroForwarder.sol";
import { GoodMacro } from "../macros/GoodMacro.t.sol";
import { MultiFlowDeleteMacro } from "../macros/MultiFlowDeleteMacro.t.sol";
import { PaidCFAOpsMacro } from "../macros/PaidCFAOpsMacro.t.sol";
import { FoundrySuperfluidTester, SuperTokenV1Library } from "../FoundrySuperfluidTester.t.sol";

using SuperTokenV1Library for ISuperToken;

// ============== Macro Contracts ==============

// not overriding IMacro here in order to avoid the compiler enforcing the function to be view-only.
contract NaugthyMacro {
    int naughtyCounter = -1;

    constructor(bool beNaughty) {
        if (beNaughty) naughtyCounter = 0;
    }

    // if naughtyCounter >= 0, this changes state, which leads to a revert in the context of a macro call
    function buildBatchOperations(ISuperfluid, bytes memory, address /*account*/) external
        returns (ISuperfluid.Operation[] memory /*operation*/)
    {
        // Do the naughty thing (updating state as an expected view function)
        if (naughtyCounter >= 0) {
            naughtyCounter++;
        }
        return new ISuperfluid.Operation[](0);
    }

    function postCheck(ISuperfluid host, bytes memory params, address account) external view { }
}

/*
 * Example for a macro which has auint8 state needed, thus needs no additionalata
 * in the context of batch calls.
 * Important: state changes do NOT take place in the context of macro calls.
 */
contract StatefulMacro is IMacro {
    struct Config {
        BlindMacroForwarder macroForwarder;
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

    function buildBatchOperations(ISuperfluid host, bytes memory /*params*/, address /*account*/)
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

    function postCheck(ISuperfluid host, bytes memory params, address account) external view { }
}

// ============== Test Contract ==============

contract BlindMacroForwarderTest is FoundrySuperfluidTester {
    constructor() FoundrySuperfluidTester(5) {
    }

    function testDummyMacro() external {
        NaugthyMacro m = new NaugthyMacro(false /* not naughty */);
        sf.macroForwarder.runMacro(IMacro(address(m)), new bytes(0));
    }

    function testNaugtyMacro() external {
        NaugthyMacro m = new NaugthyMacro(true /* naughty */);
        vm.expectRevert();
        // Note: need to cast the naughty macro
        sf.macroForwarder.runMacro(IMacro(address(m)), new bytes(0));
    }

    function testGoodMacro() external {
        GoodMacro m = new GoodMacro();
        address[] memory recipients = new address[](2);
        recipients[0] = bob;
        recipients[1] = carol;
        vm.startPrank(admin);
        // NOTE! This is different from abi.encode(superToken, int96(42), [bob, carol]),
        //       which is a fixed array: address[2].
        sf.macroForwarder.runMacro(m, m.encodeCreateFlows(superToken, int96(42), recipients));
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
        sf.macroForwarder.runMacro(m, m.encodeDeleteFlows(superToken, sender, recipients, 0));

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

// forge-lint: disable-end(unsafe-typecast, erc20-unchecked-transfer)
