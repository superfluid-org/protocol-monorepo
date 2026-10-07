/** CommonJS loggedTx for legacy deploy scripts (ethers + truffle-shaped returns). */
const {ethers} = require("hardhat");

async function loggedTx(label, fn) {
    console.log(`${label}: started`);
    const result = await fn();
    if (result && typeof result.wait === "function") {
        const receipt = await result.wait();
        console.log(`${label}: done, gas used ${receipt.gasUsed.toString()}`);
        return Object.assign(result, {receipt, tx: receipt.transactionHash});
    }
    if (result?.receipt) {
        const gasUsed =
            result.receipt.gasUsed?.toString?.() ?? result.receipt.gasUsed;
        console.log(`${label}: done, gas used ${gasUsed}`);
        return result;
    }
    if (result?.transactionHash) {
        const receipt = await ethers.provider.getTransactionReceipt(
            result.transactionHash
        );
        console.log(
            `${label}: done, gas used ${receipt?.gasUsed?.toString?.() ?? "n/a"}`
        );
        return {...result, receipt, tx: result.transactionHash};
    }
    console.log(`${label}: done`);
    return result;
}

module.exports = {loggedTx};
