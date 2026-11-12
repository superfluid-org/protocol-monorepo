// Local test fixture only; never use this non-upgradeable host for persistent deployments.
const {ethers} = require("hardhat");
const {deployTestFrameworkWithEthersV5, printProtocolFrameworkAddresses} = require("./deploy-test-framework");

async function main() {
    const chainId = (await ethers.provider.getNetwork()).chainId;
    if (chainId !== 31337) throw new Error("Local fixture requires chain ID 31337; use new-ops-scripts/framework.sh for persistent networks");
    const [signer] = await ethers.getSigners();
    const {frameworkDeployer} = await deployTestFrameworkWithEthersV5(signer);
    for (const [name, symbol, decimals] of [["Fake DAI", "fDAI", 18], ["Fake USDC", "fUSDC", 6], ["Fake TUSD", "fTUSD", 18]]) {
        await (await frameworkDeployer.deployWrapperSuperToken(name, symbol, decimals,
            ethers.utils.parseUnits("1000000000", decimals), signer.address)).wait();
    }
    await (await frameworkDeployer.deployNativeAssetSuperToken("Super ETH", "ETHx")).wait();
    printProtocolFrameworkAddresses(await frameworkDeployer.getFramework());
}
main().catch((error) => { console.error(error); process.exitCode = 1; });
