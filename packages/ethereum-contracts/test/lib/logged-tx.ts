import {ContractTransaction} from "ethers";

/** Waits for a transaction and logs its gas usage. */
export async function loggedTx(
    label: string,
    tx: Promise<ContractTransaction>
) {
    const receipt = await (await tx).wait();
    console.log(`${label}: gas used ${receipt.gasUsed.toString()}`);
    return receipt;
}
