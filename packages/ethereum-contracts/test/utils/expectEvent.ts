import {expect} from "chai";
import {
    BaseContract,
    BigNumber,
    ContractReceipt,
    ContractTransaction,
} from "ethers";
import _ from "lodash";

type TxOrReceipt = ContractTransaction | ContractReceipt;

async function toReceipt(tx: TxOrReceipt): Promise<ContractReceipt> {
    return "wait" in tx ? tx.wait() : tx;
}

async function decodeEvents(
    tx: TxOrReceipt,
    emitter: BaseContract,
    eventName: string
) {
    const receipt = await toReceipt(tx);
    const topic = emitter.interface.getEventTopic(eventName);
    return receipt.logs
        .filter(
            (log) =>
                log.topics[0] === topic &&
                log.address.toLowerCase() === emitter.address.toLowerCase()
        )
        .map((log) => emitter.interface.parseLog(log).args);
}

function normalize(value: unknown) {
    if (BigNumber.isBigNumber(value) || typeof value === "number") {
        return value.toString();
    }
    return value;
}

/**
 * Asserts that `emitter` emitted `eventName` in the transaction with at least
 * the given named arguments. `null` matches empty bytes.
 */
export async function expectEvent(
    tx: TxOrReceipt,
    emitter: BaseContract,
    eventName: string,
    expectedArgs: Record<string, unknown> = {}
) {
    const events = await decodeEvents(tx, emitter, eventName);
    expect(events.length, `No '${eventName}' event emitted`).to.be.gt(0);

    const mismatches: string[] = [];
    const match = events.find((args) =>
        Object.entries(expectedArgs).every(([key, expected]) => {
            expect(args, `Event argument '${key}' not found`).to.have.property(
                key
            );
            const actual = args[key];
            const equal =
                expected === null
                    ? actual === "0x"
                    : _.isEqual(normalize(actual), normalize(expected));
            if (!equal) {
                mismatches.push(`${key}: expected ${expected}, got ${actual}`);
            }
            return equal;
        })
    );
    expect(
        match,
        `No '${eventName}' event with matching arguments (${mismatches.join("; ")})`
    ).to.not.be.undefined;
    return match!;
}

export async function expectNoEvent(
    tx: TxOrReceipt,
    emitter: BaseContract,
    eventName: string
) {
    const events = await decodeEvents(tx, emitter, eventName);
    expect(events.length, `Unexpected '${eventName}' event emitted`).to.equal(
        0
    );
}
