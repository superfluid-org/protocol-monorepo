import {HardhatUserConfig, subtask} from "hardhat/config";
import "@typechain/hardhat";
import "@nomiclabs/hardhat-web3";
import "@nomiclabs/hardhat-truffle5";
import "@nomicfoundation/hardhat-chai-matchers";
import "@nomiclabs/hardhat-ethers";
import {
    TASK_COMPILE_SOLIDITY_GET_SOURCE_PATHS,
    TASK_COMPILE_SOLIDITY_GET_SOLC_BUILD,
} from "hardhat/builtin-tasks/task-names";
import "solidity-coverage";
import {config as dotenvConfig} from "dotenv";
import {NetworkUserConfig} from "hardhat/types";
import "solidity-docgen";
import {relative} from "path";

try {
    dotenvConfig();
} catch (error) {
    console.error(
        "Loading .env file failed. Things will likely fail. You may want to copy .env.template and create a new one."
    );
}

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

// hardhat mixin magic: https://github.com/NomicFoundation/hardhat/issues/2306#issuecomment-1039452928
// filter out foundry test codes
subtask(TASK_COMPILE_SOLIDITY_GET_SOURCE_PATHS).setAction(
    async (_, __, runSuper) => {
        const paths = await runSuper();
        return paths.filter((p: string) => !p.includes("test/foundry"));
    }
);

const chainIds = {
    "eth-mainnet": 1,
    "eth-sepolia": 11155111,

    "xdai-mainnet": 100,

    "optimism-mainnet": 10,

    "arbitrum-one": 42161,

    "polygon-mainnet": 137,

    "avalanche-c": 43114,
    "avalanche-fuji": 43113,

    "bsc-mainnet": 56,

    "celo-mainnet": 42220,

    "scroll-sepolia": 534351,
    "scroll-mainnet": 534352,

    localhost: 31337,
    hardhat: 31337,
};

function createNetworkConfig(
    network: keyof typeof chainIds
): NetworkUserConfig {
    return {
        accounts:
            process.env.PRIVATE_KEY !== undefined
                ? [process.env.PRIVATE_KEY]
                : [],
        chainId: chainIds[network],
    };
}

const config: HardhatUserConfig = {
    solidity: {
        version: "0.8.26",
        settings: {
            optimizer: {
                enabled: true,
                runs: 200,
            },
            evmVersion: "paris",
        },
    },
    paths: {
        artifacts: "build/hardhat",
    },
    networks: {
        "bsc-mainnet": {
            ...createNetworkConfig("bsc-mainnet"),
            url: process.env.BSC_MAINNET_PROVIDER_URL || "",
        },
        "xdai-mainnet": {
            ...createNetworkConfig("xdai-mainnet"),
            url: process.env.XDAI_MAINNET_PROVIDER_URL || "",
        },
        "optimism-mainnet": {
            ...createNetworkConfig("optimism-mainnet"),
            url: process.env.OPTIMISM_MAINNET_PROVIDER_URL || "",
        },
        "arbitrum-one": {
            ...createNetworkConfig("arbitrum-one"),
            url: process.env.ARBITRUM_ONE_PROVIDER_URL || "",
        },
        "polygon-mainnet": {
            ...createNetworkConfig("polygon-mainnet"),
            url: process.env.POLYGON_MAINNET_PROVIDER_URL || "",
        },
        "avalanche-c": {
            ...createNetworkConfig("avalanche-c"),
            url: process.env.AVALANCHE_C_PROVIDER_URL || "",
        },
        "avalanche-fuji": {
            ...createNetworkConfig("avalanche-fuji"),
            url: process.env.AVALANCHE_FUJI_PROVIDER_URL || "",
        },
        "celo-mainnet": {
            ...createNetworkConfig("celo-mainnet"),
            url: process.env.CELO_MAINNET_PROVIDER_URL || "",
        },
        "eth-sepolia": {
            ...createNetworkConfig("eth-sepolia"),
            url: process.env.ETH_SEPOLIA_PROVIDER_URL || "",
        },
        "scroll-sepolia": {
            ...createNetworkConfig("scroll-sepolia"),
            url: process.env.SCROLL_SEPOLIA_PROVIDER_URL || "",
        },
        "scroll-mainnet": {
            ...createNetworkConfig("scroll-mainnet"),
            url: process.env.SCROLL_MAINNET_PROVIDER_URL || "",
        },
        hardhat: {
            // We defer the contract size limit test to foundry.
            allowUnlimitedContractSize: true,
        },
    },
    mocha: {
        timeout: 250000,
        parallel: !!+process.env.HARDHAT_RUN_PARALLEL,
        jobs: process.env.HARDHAT_TEST_JOBS
            ? parseInt(process.env.HARDHAT_TEST_JOBS)
            : undefined,
    },
    docgen: {
        outputDir: "docs/api",
        templates: "./docs/docgen-templates",
        pages: (item: any, file: any) =>
            file.absolutePath.startsWith("contracts/interfaces/")
                ? relative("contracts", file.absolutePath).replace(
                      ".sol",
                      ".md"
                  )
                : undefined,
    },
    typechain: {target: "ethers-v5"},
};

export default config;
