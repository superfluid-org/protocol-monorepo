import {expect} from "chai";
import {BigNumber, ethers} from "ethers";
import {ethers as hreEthers} from "hardhat";

export type EventEmitter =
    | {
          abi?: readonly (string | ethers.utils.Fragment)[];
          address?: string;
          contractName?: string;
      }
    | ethers.Contract;

type DecodedLog = {event: string; args: Record<string, unknown>};

async function resolveEmitter(emitter: EventEmitter) {
    if (emitter && typeof emitter === "object" && "interface" in emitter) {
        const contract = emitter as ethers.Contract;
        return {
            iface: contract.interface,
            address: contract.address as string | undefined,
        };
    }
    const legacy = emitter as {
        abi?: readonly (string | ethers.utils.Fragment)[];
        address?: string;
        contractName?: string;
    };
    if (legacy.abi) {
        return {
            iface: new ethers.utils.Interface(legacy.abi),
            address: legacy.address,
        };
    }
    if (legacy.contractName) {
        const factory = await hreEthers.getContractFactory(legacy.contractName);
        return {
            iface: factory.interface,
            address: legacy.address,
        };
    }
    throw new Error("Unknown contract emitter for expectEvent");
}

function argsFromParsed(parsed: ethers.utils.LogDescription) {
    const args: Record<string, unknown> = {};
    for (const input of parsed.eventFragment.inputs) {
        if (input.name) {
            args[input.name] = parsed.args[input.name];
        }
    }
    return args;
}

function normalizeValue(value: unknown): unknown {
    if (value === null || value === undefined) {
        return value;
    }
    if (BigNumber.isBigNumber(value)) {
        return value.toString();
    }
    if (typeof value === "bigint") {
        return value.toString();
    }
    return value;
}

function isEmptyBytes(value: unknown) {
    return (
        value === null || value === undefined || value === "0x" || value === ""
    );
}

function contains(args: Record<string, unknown>, key: string, value: unknown) {
    expect(key in args).to.equal(true, `Event argument '${key}' not found`);
    if (value === null) {
        expect(isEmptyBytes(args[key])).to.equal(
            true,
            `expected event argument '${key}' to be null but got ${args[key]}`
        );
    } else {
        expect(normalizeValue(args[key])).to.deep.equal(
            normalizeValue(value),
            `expected event argument '${key}' to have value ${value} but got ${args[key]}`
        );
    }
}

export function inLogs(
    logs: DecodedLog[],
    eventName: string,
    eventArgs: Record<string, unknown> = {}
) {
    const events = logs.filter((e) => e.event === eventName);
    expect(events.length > 0).to.equal(true, `No '${eventName}' events found`);

    const exception: Error[] = [];
    const event = events.find((e) => {
        for (const [key, value] of Object.entries(eventArgs)) {
            try {
                contains(e.args, key, value);
            } catch (error) {
                exception.push(error as Error);
                return false;
            }
        }
        return true;
    });

    if (event === undefined) {
        throw exception[0];
    }
    return event;
}

function notInLogs(logs: DecodedLog[], eventName: string) {
    expect(
        logs.find((e) => e.event === eventName),
        `Event ${eventName} was found`
    ).to.be.undefined;
}

function isTruffleDecodedLogs(logs: unknown[]): logs is DecodedLog[] {
    return (
        logs.length > 0 &&
        typeof logs[0] === "object" &&
        logs[0] !== null &&
        "event" in logs[0]
    );
}

async function decodeLogs(
    rawLogs: ethers.providers.Log[],
    emitter: EventEmitter,
    eventName: string
): Promise<DecodedLog[]> {
    const {iface, address} = await resolveEmitter(emitter);
    const topic = iface.getEventTopic(eventName);
    return rawLogs
        .filter(
            (log) =>
                log.topics[0] === topic &&
                (!address ||
                    log.address.toLowerCase() === address.toLowerCase())
        )
        .map((log) => {
            const parsed = iface.parseLog(log);
            return {event: eventName, args: argsFromParsed(parsed)};
        });
}

export async function expectEventInTransaction(
    txHash: string,
    emitter: EventEmitter,
    eventName: string,
    eventArgs: Record<string, unknown> = {}
) {
    const receipt = await hreEthers.provider.getTransactionReceipt(txHash);
    if (!receipt) {
        throw new Error(`No receipt for tx ${txHash}`);
    }
    const logs = await decodeLogs(receipt.logs, emitter, eventName);
    return inLogs(logs, eventName, eventArgs);
}

export async function expectEventNotInTransaction(
    txHash: string,
    emitter: EventEmitter,
    eventName: string
) {
    const receipt = await hreEthers.provider.getTransactionReceipt(txHash);
    if (!receipt) {
        throw new Error(`No receipt for tx ${txHash}`);
    }
    const logs = await decodeLogs(receipt.logs, emitter, eventName);
    notInLogs(logs, eventName);
}

export async function expectEventFromReceipt(
    receipt: ethers.providers.TransactionReceipt,
    emitter: EventEmitter,
    eventName: string,
    eventArgs: Record<string, unknown> = {}
) {
    const logs = await decodeLogs(receipt.logs, emitter, eventName);
    return inLogs(logs, eventName, eventArgs);
}

function expectEvent(
    receipt: ethers.providers.TransactionReceipt | {logs: DecodedLog[]},
    eventName: string,
    eventArgs: Record<string, unknown> = {},
    emitter?: EventEmitter
) {
    if ("logs" in receipt && isTruffleDecodedLogs(receipt.logs)) {
        return inLogs(receipt.logs, eventName, eventArgs);
    }
    if (!emitter) {
        throw new Error(
            "expectEvent on raw receipt requires an emitter contract"
        );
    }
    return expectEventFromReceipt(
        receipt as ethers.providers.TransactionReceipt,
        emitter,
        eventName,
        eventArgs
    );
}

expectEvent.inLogs = inLogs;
expectEvent.inTransaction = expectEventInTransaction;
expectEvent.notEmitted = {inTransaction: expectEventNotInTransaction};
expectEvent.fromReceipt = expectEventFromReceipt;

module.exports = expectEvent;
export default expectEvent;
