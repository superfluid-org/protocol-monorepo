import { Address, BigInt } from "@graphprotocol/graph-ts";
import {
    assert,
    beforeEach,
    clearStore,
    describe,
    test,
} from "matchstick-as/assembly/index";
import { handleFlowOperatorUpdated } from "../../../src/mappings/cfav1";
import {
    BIG_INT_ZERO,
    getFlowOperatorID,
    ZERO_ADDRESS,
} from "../../../src/utils";
import { assertEventBaseProperties } from "../../assertionHelpers";
import {
    alice,
    bob,
    maticXAddress,
    maticXName,
    maticXSymbol,
} from "../../constants";
import {
    createFlowOperatorUpdatedEvent,
    modifyFlowAndAssertFlowUpdatedEventProperties,
} from "../cfav1.helper";
import { mockedApprove } from "../../mockedFunctions";

const initialFlowRate = BigInt.fromI32(100);

describe("ConstantFlowAgreementV1 Event Entity Unit Tests", () => {
    beforeEach(() => {
        clearStore();
    });

    test("handleFlowUpdated() - Should create a new FlowUpdatedEvent entity (create)", () => {
        // create flow
        modifyFlowAndAssertFlowUpdatedEventProperties(
            maticXAddress,      // superToken
            maticXName,         // tokenName
            maticXSymbol,       // tokenSymbol
            alice,              // sender
            bob,                // receiver
            ZERO_ADDRESS,       // underlyingToken
            "0",                // expectedType
            BIG_INT_ZERO,       // expectedOwedDeposit
            initialFlowRate,    // flowRate
            BIG_INT_ZERO,       // previousSenderFlowRate
            BIG_INT_ZERO,       // previousReceiverFlowRate
            ""                  // userData
        );
    });

    test("handleFlowUpdated() - Should persist non-zero owedDeposit on Stream and FlowUpdatedEvent", () => {
        modifyFlowAndAssertFlowUpdatedEventProperties(
            maticXAddress,              // superToken
            maticXName,                 // tokenName
            maticXSymbol,               // tokenSymbol
            alice,                      // sender
            bob,                        // receiver
            ZERO_ADDRESS,               // underlyingToken
            "0",                        // expectedType
            BigInt.fromI32(123456),     // expectedOwedDeposit (non-zero: receiver is a SuperApp)
            initialFlowRate,            // flowRate
            BIG_INT_ZERO,               // previousSenderFlowRate
            BIG_INT_ZERO,               // previousReceiverFlowRate
            ""                          // userData
        );
    });

    test("handleFlowUpdated() - Should create new FlowUpdatedEvent entities (create => update)", () => {
        // create flow
        modifyFlowAndAssertFlowUpdatedEventProperties(
            maticXAddress,      // superToken
            maticXName,         // tokenName
            maticXSymbol,       // tokenSymbol
            alice,              // sender
            bob,                // receiver
            ZERO_ADDRESS,       // underlyingToken
            "0",                // expectedType
            BIG_INT_ZERO,       // expectedOwedDeposit
            initialFlowRate,    // flowRate
            BIG_INT_ZERO,       // previousSenderFlowRate
            BIG_INT_ZERO,       // previousReceiverFlowRate
            ""                  // userData
        );

        // update flow: increase flow rate
        const increasedFlowRate = initialFlowRate.plus(BigInt.fromI32(50));
        modifyFlowAndAssertFlowUpdatedEventProperties(
            maticXAddress,      // superToken
            maticXName,         // tokenName
            maticXSymbol,       // tokenSymbol
            alice,              // sender
            bob,                // receiver
            ZERO_ADDRESS,       // underlyingToken
            "1",                // expectedType
            BIG_INT_ZERO,       // expectedOwedDeposit
            increasedFlowRate,  // flowRate
            initialFlowRate,    // previousSenderFlowRate
            initialFlowRate,    // previousReceiverFlowRate
            ""                  // userData
        );

        // update flow: decrease flow rate
        modifyFlowAndAssertFlowUpdatedEventProperties(
            maticXAddress,      // superToken
            maticXName,         // tokenName
            maticXSymbol,       // tokenSymbol
            alice,              // sender
            bob,                // receiver
            ZERO_ADDRESS,       // underlyingToken
            "1",                // expectedType
            BIG_INT_ZERO,       // expectedOwedDeposit
            initialFlowRate,    // flowRate
            increasedFlowRate,  // previousSenderFlowRate
            increasedFlowRate,  // previousReceiverFlowRate
            ""                  // userData
        );
    });

    test("handleFlowUpdated() - Should create new FlowUpdatedEvent entities (create => update => delete)", () => {
        // create flow
        modifyFlowAndAssertFlowUpdatedEventProperties(
            maticXAddress,      // superToken
            maticXName,         // tokenName
            maticXSymbol,       // tokenSymbol
            alice,              // sender
            bob,                // receiver
            ZERO_ADDRESS,       // underlyingToken
            "0",                // expectedType
            BIG_INT_ZERO,       // expectedOwedDeposit
            initialFlowRate,    // flowRate
            BIG_INT_ZERO,       // previousSenderFlowRate
            BIG_INT_ZERO,       // previousReceiverFlowRate
            ""                  // userData
        );

        // update flow: increase flow rate
        const increasedFlowRate = initialFlowRate.plus(BigInt.fromI32(50));
        modifyFlowAndAssertFlowUpdatedEventProperties(
            maticXAddress,      // superToken
            maticXName,         // tokenName
            maticXSymbol,       // tokenSymbol
            alice,              // sender
            bob,                // receiver
            ZERO_ADDRESS,       // underlyingToken
            "1",                // expectedType
            BIG_INT_ZERO,       // expectedOwedDeposit
            increasedFlowRate,  // flowRate
            initialFlowRate,    // previousSenderFlowRate
            initialFlowRate,    // previousReceiverFlowRate
            ""                  // userData
        );


        // delete flow
        modifyFlowAndAssertFlowUpdatedEventProperties(
            maticXAddress,      // superToken
            maticXName,         // tokenName
            maticXSymbol,       // tokenSymbol
            alice,              // sender
            bob,                // receiver
            ZERO_ADDRESS,       // underlyingToken
            "2",                // expectedType
            BIG_INT_ZERO,       // expectedOwedDeposit
            BIG_INT_ZERO,       // flowRate
            increasedFlowRate,  // previousSenderFlowRate
            increasedFlowRate,  // previousReceiverFlowRate
            ""                  // userData
        );
    });

    test("handleFlowOperatorUpdated() - Should create a new FlowOperatorUpdatedEvent entity", () => {
        const superToken = maticXAddress;
        const permissions = 1; // create only
        const flowRateAllowance = BigInt.fromI32(100);
        const sender = alice;
        const flowOperator = bob;

        const flowOperatorUpdatedEvent = createFlowOperatorUpdatedEvent(
            superToken,
            sender,
            flowOperator,
            permissions,
            flowRateAllowance
        );
        mockedApprove(superToken, sender, flowOperator, BigInt.fromI32(0));

        handleFlowOperatorUpdated(flowOperatorUpdatedEvent);

        const id = assertEventBaseProperties(
            flowOperatorUpdatedEvent,
            "FlowOperatorUpdated"
        );
        const flowOperatorId = getFlowOperatorID(
            Address.fromString(flowOperator),
            Address.fromString(superToken),
            Address.fromString(sender)
        );
        assert.fieldEquals("FlowOperatorUpdatedEvent", id, "token", superToken);
        assert.fieldEquals("FlowOperatorUpdatedEvent", id, "sender", sender);
        assert.fieldEquals("FlowOperatorUpdatedEvent", id, "flowOperator", flowOperatorId);
        assert.fieldEquals("FlowOperatorUpdatedEvent", id, "permissions", permissions.toString());
        assert.fieldEquals("FlowOperatorUpdatedEvent", id, "flowRateAllowance", flowRateAllowance.toString());
    });
});
