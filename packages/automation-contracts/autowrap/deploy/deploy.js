/*
 * Usage: npx hardhat deploy --network <network>
 *
 * Notes:
 * You need to have a .env file based on .env-example.
 * If verification fails, you can run again this script to verify later.
 */

const metadata = require("@superfluid-finance/metadata");

const sleep = (waitTimeInMs) =>
    new Promise((resolve) => setTimeout(resolve, waitTimeInMs));

module.exports = async function ({ deployments, getNamedAccounts }) {
    const chainId = await hre.getChainId();
    const cfaV1 = metadata.networks.filter((item) => item.chainId == chainId)[0]
        .contractsV1.cfaV1;
    if (cfaV1 === undefined) {
        console.log("cfaV1 contract not found for this network");
        return;
    }

    const minLower = 172800;
    const minUpper = 604800;

    const { deploy } = deployments;
    const { deployer } = await getNamedAccounts();

    console.log(`network: ${hre.network.name}`);
    console.log(`chainId: ${chainId}`);
    console.log(`rpc: ${hre.network.config.url}`);
    console.log(`cfaV1: ${cfaV1}`);

    const Manager = await deploy("Manager", {
        from: deployer,
        args: [cfaV1, minLower, minUpper],
        log: true,
        skipIfAlreadyDeployed: false,
    });

    const WrapStrategy = await deploy("WrapStrategy", {
        from: deployer,
        args: [Manager.address],
        log: true,
        skipIfAlreadyDeployed: false,
    });

    // Check if this is a fresh deployment or reusing existing contracts
    const isFreshDeployment = Manager.newlyDeployed && WrapStrategy.newlyDeployed;

    if (isFreshDeployment) {
        console.log("Fresh deployment detected - executing additional setup steps...");

        // approve strategy on manager contract directly
        console.log("Adding strategy to manager...");
        const managerContract = await hre.ethers.getContractAt("Manager", Manager.address);
        const addStrategyTx = await managerContract.addApprovedStrategy(WrapStrategy.address);
        await addStrategyTx.wait();
        console.log(`Strategy added. Tx hash: ${addStrategyTx.hash}`);

        // Renounce ownership on both contracts
        console.log("Renouncing ownership on Manager contract...");
        const renounceManagerTx = await managerContract.renounceOwnership();
        await renounceManagerTx.wait();
        console.log(`Manager ownership renounced. Tx hash: ${renounceManagerTx.hash}`);

        console.log("Renouncing ownership on WrapStrategy contract...");
        const wrapStrategyContract = await hre.ethers.getContractAt("WrapStrategy", WrapStrategy.address);
        const renounceStrategyTx = await wrapStrategyContract.renounceOwnership();
        await renounceStrategyTx.wait();
        console.log(`WrapStrategy ownership renounced. Tx hash: ${renounceStrategyTx.hash}`);
    } else {
        console.log("Reusing existing contracts - skipping additional setup steps");
    }

    console.log("Giving the explorer(s) 15 seconds to index before verification...");
    await sleep(15000);

    try {
        await hre.run("verify:verify", {
            address: Manager.address,
            constructorArguments: [cfaV1, minLower, minUpper],
            contract: "contracts/Manager.sol:Manager",
        });

        await hre.run("verify:verify", {
            address: WrapStrategy.address,
            constructorArguments: [Manager.address],
            contract: "contracts/strategies/WrapStrategy.sol:WrapStrategy",
        });
    } catch (err) {
        console.error(err);
    }
};
