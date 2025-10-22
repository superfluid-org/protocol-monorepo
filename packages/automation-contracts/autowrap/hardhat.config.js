require("dotenv").config();
require("@nomiclabs/hardhat-ethers");
require("@nomicfoundation/hardhat-verify");
require("hardhat-deploy");
require("hardhat/config");
const {TASK_COMPILE_GET_REMAPPINGS} = require("hardhat/builtin-tasks/task-names");

// You need to export an object to set up your config
// Go to https://hardhat.org/config/ to learn more

// Remapping for OpenZeppelin contracts
subtask(TASK_COMPILE_GET_REMAPPINGS).setAction(
    async (_, __, runSuper) => {
        const remappings = await runSuper();
        return {
            ...remappings,
            "@openzeppelin/contracts/": "@openzeppelin-v5/contracts/",
        };
    }
);

/**
 * @type import('hardhat/config').HardhatUserConfig
 */
module.exports = {
    solidity: {
        version: "0.8.23",
        settings: {
            optimizer: {
                enabled: true,
                runs: 200,
            },
        },
    },
    networks: {
        localhost: {
            url: "http://127.0.0.1:8545/",
            chainId: 31337,
        },
        polygon: {
            url: process.env.POLYGON_URL || "",
            accounts:
                process.env.PRIVATE_KEY !== undefined
                    ? [process.env.PRIVATE_KEY]
                    : [],
        },
        bsc: {
            url: process.env.BSC_URL || "",
            accounts:
                process.env.PRIVATE_KEY !== undefined
                    ? [process.env.PRIVATE_KEY]
                    : [],
        },
        opsepolia: {
            url: process.env.OPSEPOLIA_URL || "",
            accounts:
                process.env.PRIVATE_KEY !== undefined
                    ? [process.env.PRIVATE_KEY]
                    : [],
        },
        base: {
            url: process.env.BASE_URL || "",
            accounts:
                process.env.PRIVATE_KEY !== undefined
                    ? [process.env.PRIVATE_KEY]
                    : [],
        },
    },
    namedAccounts: {
        deployer: {
            default: 0,
        },
    },
    // see https://v2.hardhat.org/hardhat-runner/plugins/nomicfoundation-hardhat-verify
    etherscan: {
        apiKey: process.env.ETHERSCAN_API_V2_KEY,
        customChains: [
            {
                network: "opsepolia",
                chainId: 11155420,
                urls: {
                    apiURL: "https://api-sepolia-optimistic.etherscan.io/api",
                    browserURL: "https://sepolia-optimism.etherscan.io/",
                },
            },
        ],
    },
    sourcify: {
        enabled: true,
    },
};
