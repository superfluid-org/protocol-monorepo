import {HardhatUserConfig, subtask} from "hardhat/config";
import "@typechain/hardhat";
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
import {execSync} from 'child_process';

try {
    dotenvConfig();
} catch (error) {
    console.error(
        "Loading .env file failed. Things will likely fail. You may want to copy .env.template and create a new one."
    );
}

// solc is the binary the nix devshell pins (flake.nix sets SOLC). No compiler download.
subtask(TASK_COMPILE_SOLIDITY_GET_SOLC_BUILD).setAction(
    async (args) => {
        const solc = process.env.SOLC;
        if (!solc) {
            throw new Error("SOLC is not set. Compile from the nix devshell (nix develop), which pins solc.");
        }
        const versionOutput = execSync(`${solc} --version`, { encoding: "utf8" }).trim();
        const longVersion = versionOutput.match(/Version: (.+)/)?.[1] || `${args.solcVersion}+commit.unknown.Linux.g++`;
        return {
            compilerPath: solc,
            isSolcJs: false,
            version: args.solcVersion,
            longVersion,
        };
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

/*
Note: for hardhat to find libs in node_modules, they need to look like an npm package, that is they need to have
a package.json at the directory level looking like the package.
E.g. if the first path component is prefixed with @, it will expect a package.json in the nested directory.
*/

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
        version: "0.8.35",
        settings: {
            optimizer: {
                enabled: true,
                runs: 200,
            },
            evmVersion: "cancun",
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
        ops: {
            url: process.env.RPC_URL || "http://127.0.0.1:8545",
            accounts: "remote",
        },
        hardhat: {
            // We defer the contract size limit test to foundry.
            allowUnlimitedContractSize: true,
            // Expected by testenv-ctl.sh
            accounts: {
                mnemonic: "candy maple cake sugar pudding cream honey rich smooth crumble sweet treat",
            },
        },
    },
    mocha: {
        timeout: 250000,
        parallel: !!Number(process.env.HARDHAT_RUN_PARALLEL),
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
    typechain: {
        target: "ethers-v5"
    },
};

export default config;
