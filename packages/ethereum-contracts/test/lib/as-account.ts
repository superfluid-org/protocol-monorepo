import {BigNumber, Contract, Signer} from "ethers";
import {ethers} from "hardhat";

const {toTruffleTxResponse} = require("./ethers-contract-loader");

function normalizeCallArg(value: unknown) {
    if (BigNumber.isBigNumber(value)) {
        return value;
    }
    if (
        value &&
        typeof value === "object" &&
        "toString" in value &&
        typeof (value as {toString: () => string}).toString === "function"
    ) {
        const asString = (value as {toString: () => string}).toString();
        if (/^[0-9]+$/.test(asString)) {
            return ethers.BigNumber.from(asString);
        }
        if (/^[0-9a-fA-F]+$/.test(asString)) {
            return ethers.BigNumber.from(`0x${asString}`);
        }
    }
    if (typeof value !== "string" || value.startsWith("0x")) {
        return value;
    }
    if (/^[0-9]+$/.test(value)) {
        return ethers.BigNumber.from(value);
    }
    if (!/^[0-9a-fA-F]+$/.test(value)) {
        return value;
    }
    if (value.length === 40) {
        return `0x${value}`;
    }
    return ethers.BigNumber.from(`0x${value}`);
}

function normalizeCallArgs(args: unknown[]) {
    return args.map(normalizeCallArg);
}

/** Truffle `{ from: addr }` → ethers `.connect(signer)` with truffle-shaped tx returns. */
export async function asAccount<T extends Contract>(
    contract: T,
    account: string
): Promise<T> {
    return contract.connect((await ethers.getSigner(account)) as Signer) as T;
}

export async function callAsAccount<T extends Contract>(
    contract: T,
    account: string,
    method: string,
    ...args: unknown[]
) {
    const connected = await asAccount(contract, account);
    const result = await (
        connected as Record<string, (...a: unknown[]) => unknown>
    )[method](...normalizeCallArgs(args));
    const contractName =
        (contract as T & {contractName?: string}).contractName ??
        "SuperTokenMock";
    const base = await ethers.getContractAt(contractName, contract.address);
    return toTruffleTxResponse(result, base);
}

module.exports = {asAccount, callAsAccount};
