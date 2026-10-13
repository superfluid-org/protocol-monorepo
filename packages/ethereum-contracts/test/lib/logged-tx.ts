import {ContractTransaction} from "ethers";
import {ethers} from "hardhat";

/** Minimal replacement for @decentral.ee/web3-helpers web3tx in tests. */
export async function loggedTx(label: string, fn: () => Promise<unknown>) {
    console.log(`${label}: started`);
    const result = await fn();

    if (
        result &&
        typeof result === "object" &&
        "tx" in result &&
        "receipt" in result
    ) {
        const {receipt} = result as {receipt: {gasUsed: {toString(): string}}};
        console.log(`${label}: done, gas used ${receipt.gasUsed.toString()}`);
        return result;
    }

    const tx = result as ContractTransaction;
    if (tx && typeof tx.wait === "function") {
        const receipt = await tx.wait();
        console.log(`${label}: done, gas used ${receipt.gasUsed.toString()}`);
        return {...receipt, tx: receipt.transactionHash};
    }

    if (
        result &&
        typeof result === "object" &&
        "transactionHash" in result &&
        typeof (result as {transactionHash: string}).transactionHash ===
            "string"
    ) {
        const receipt =
            (result as {receipt?: {gasUsed: {toString(): string}}}).receipt ??
            (await ethers.provider.getTransactionReceipt(
                (result as {transactionHash: string}).transactionHash
            ));
        console.log(
            `${label}: done, gas used ${receipt?.gasUsed?.toString?.() ?? "n/a"}`
        );
        return {
            ...(result as object),
            receipt,
            tx: (result as {transactionHash: string}).transactionHash,
        };
    }

    console.log(`${label}: done`);
    return result;
}
