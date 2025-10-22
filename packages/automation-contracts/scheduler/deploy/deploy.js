/*
 * Usage: npx hardhat deploy --network <network>
 *
 * Notes:
 * You need to have a .env file based on .env-template.
 * If verification fails, you can run again this script to verify later.
 */

const metadata = require("@superfluid-finance/metadata");

const sleep = (waitTimeInMs) =>
    new Promise((resolve) => setTimeout(resolve, waitTimeInMs));

module.exports = async function ({ deployments, getNamedAccounts }) {
    const chainId = await hre.getChainId();
    const host = metadata.networks.filter((item) => item.chainId == chainId)[0]
        .contractsV1.host;
    if (host === undefined) {
        console.log("Host contract not found for this network");
        return;
    }

    const { deploy } = deployments;
    const { deployer } = await getNamedAccounts();

    console.log(`network: ${hre.network.name}`);
    console.log(`chainId: ${chainId}`);
    console.log(`rpc: ${hre.network.config.url}`);
    console.log(`host: ${host}`);

    const deployFlowScheduler =
        process.env.DEPLOY_FLOW_SCHEDULER?.toLowerCase() === "true";
    const deployVestingScheduler =
        process.env.DEPLOY_VESTING_SCHEDULER?.toLowerCase() === "true";
    const deployVestingSchedulerV2 =
        process.env.DEPLOY_VESTING_SCHEDULER_V2?.toLowerCase() === "true";
    const deployVestingSchedulerV3 =
        process.env.DEPLOY_VESTING_SCHEDULER_V3?.toLowerCase() === "true";

    console.log(`deployFlowScheduler: ${deployFlowScheduler}`);
    console.log(`deployVestingScheduler: ${deployVestingScheduler}`);
    console.log(`deployVestingSchedulerV2: ${deployVestingSchedulerV2}`);
    console.log(`deployVestingSchedulerV3: ${deployVestingSchedulerV3}`);

    if (deployFlowScheduler) {
        console.log("Deploying FlowScheduler...");
        const FlowScheduler = await deploy("FlowScheduler", {
            from: deployer,
            args: [host],
            log: true,
            skipIfAlreadyDeployed: false,
        });

        // wait for 15 seconds to allow etherscan to indexed the contracts
        await sleep(15000);

        console.log("Verifying FlowScheduler...");
        await hre.run("verify:verify", {
            address: FlowScheduler.address,
            constructorArguments: [host],
            contract: "contracts/FlowScheduler.sol:FlowScheduler",
        });
    }

    if (deployVestingScheduler) {
        console.log("Deploying VestingScheduler...");
        const VestingScheduler = await deploy("VestingScheduler", {
            from: deployer,
            args: [host],
            log: true,
            skipIfAlreadyDeployed: false,
        });

        // wait for 15 seconds to allow etherscan to indexed the contracts
        await sleep(15000);

        console.log("Verifying VestingScheduler...");
        await hre.run("verify:verify", {
            address: VestingScheduler.address,
            constructorArguments: [host],
            contract: "contracts/VestingScheduler.sol:VestingScheduler",
        });
    }

    if (deployVestingSchedulerV2) {
        console.log("Deploying VestingSchedulerV2...");
        const VestingSchedulerV2 = await deploy("VestingSchedulerV2", {
            from: deployer,
            args: [host],
            log: true,
            skipIfAlreadyDeployed: false,
        });

        // wait for 15 seconds to allow etherscan to indexed the contracts
        await sleep(15000);

        console.log("Verifying VestingSchedulerV2...");
        await hre.run("verify:verify", {
            address: VestingSchedulerV2.address,
            constructorArguments: [host],
            contract: "contracts/VestingSchedulerV2.sol:VestingSchedulerV2",
        });
    }

    if (deployVestingSchedulerV3) {
        console.log("Deploying VestingSchedulerV3...");
        const VestingSchedulerV3 = await deploy("VestingSchedulerV3", {
            from: deployer,
            args: [host],
            log: true,
            skipIfAlreadyDeployed: false,
        });

        // wait for 15 seconds to allow etherscan to indexed the contracts
        await sleep(15000);

        console.log("Verifying VestingSchedulerV3...");
        await hre.run("verify:verify", {
            address: VestingSchedulerV3.address,
            constructorArguments: [host],
            contract: "contracts/VestingSchedulerV3.sol:VestingSchedulerV3",
        });
    }

    console.log("Finished.");
};
