import { HardhatUserConfig, subtask } from "hardhat/config";
import "@typechain/hardhat";
import "@nomiclabs/hardhat-ethers";
import "@nomicfoundation/hardhat-chai-matchers";
import "@nomiclabs/hardhat-web3";
import {
    TASK_COMPILE_SOLIDITY_GET_SOLC_BUILD,
} from "hardhat/builtin-tasks/task-names";
import { config as dotenvConfig } from "dotenv";
dotenvConfig();

// The built-in compiler (auto-downloaded if not yet present) can be overridden by setting SOLC
// If set, we assume it's a native compiler which matches the required Solidity version.
subtask(TASK_COMPILE_SOLIDITY_GET_SOLC_BUILD).setAction(
    async (args, hre, runSuper) => {
        console.log("subtask TASK_COMPILE_SOLIDITY_GET_SOLC_BUILD");
        if (process.env.SOLC !== undefined) {
            console.log(
                "Using Solidity compiler set in SOLC:",
                process.env.SOLC
            );
            return {
                compilerPath: process.env.SOLC,
                isSolcJs: false, // false for native compiler
                version: args.solcVersion,
            };
        } else {
            // fall back to the default
            return runSuper();
        }
    }
);

/**
 * This Hardhat config is only used for testing the SDK-Core.
 * Note: For tests to work, 0xf39fd6e51aad88f6f4ce6ab8827279cfffb92266
 * must be the deployer of the contracts.
 */
const config: HardhatUserConfig = {
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
        hardhat: {
            chainId: 31337,
            allowUnlimitedContractSize: true,
        },
        matic: {
            url: process.env.MATIC_PROVIDER_URL || "",
            chainId: 137,
        },
        bsc: {
            url: process.env.BSC_PROVIDER_URL || "",
            accounts: process.env.TEST_PRIVATE_KEY
                ? [process.env.TEST_PRIVATE_KEY || ""]
                : [],
            chainId: 56,
        },
    },
    mocha: {
        timeout: 250000,
    },
    typechain: {target: "ethers-v5"},
};

export default config;
