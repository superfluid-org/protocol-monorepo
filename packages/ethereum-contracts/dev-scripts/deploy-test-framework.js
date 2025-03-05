const {ethers} = require("hardhat");
const {JsonRpcProvider} = require("@ethersproject/providers");

const SuperfluidPoolDeployerLibraryArtifact = require("@superfluid-finance/ethereum-contracts/build/hardhat/contracts/agreements/gdav1/SuperfluidPoolDeployerLibrary.sol/SuperfluidPoolDeployerLibrary.json");
const SuperfluidGovDeployerLibraryArtifact = require("@superfluid-finance/ethereum-contracts/build/hardhat/contracts/utils/SuperfluidFrameworkDeploymentSteps.t.sol/SuperfluidGovDeployerLibrary.json");
const SuperfluidHostDeployerLibraryArtifact = require("@superfluid-finance/ethereum-contracts/build/hardhat/contracts/utils/SuperfluidFrameworkDeploymentSteps.t.sol/SuperfluidHostDeployerLibrary.json");
const SuperfluidCFAv1DeployerLibraryArtifact = require("@superfluid-finance/ethereum-contracts/build/hardhat/contracts/utils/SuperfluidFrameworkDeploymentSteps.t.sol/SuperfluidCFAv1DeployerLibrary.json");
const SuperfluidIDAv1DeployerLibraryArtifact = require("@superfluid-finance/ethereum-contracts/build/hardhat/contracts/utils/SuperfluidFrameworkDeploymentSteps.t.sol/SuperfluidIDAv1DeployerLibrary.json");
const SuperfluidGDAv1DeployerLibraryArtifact = require("@superfluid-finance/ethereum-contracts/build/hardhat/contracts/utils/SuperfluidFrameworkDeploymentSteps.t.sol/SuperfluidGDAv1DeployerLibrary.json");
const SuperTokenDeployerLibraryArtifact = require("@superfluid-finance/ethereum-contracts/build/hardhat/contracts/utils/SuperfluidFrameworkDeploymentSteps.t.sol/SuperTokenDeployerLibrary.json");
const SuperfluidPeripheryDeployerLibraryArtifact = require("@superfluid-finance/ethereum-contracts/build/hardhat/contracts/utils/SuperfluidFrameworkDeploymentSteps.t.sol/SuperfluidPeripheryDeployerLibrary.json");
const SuperfluidPoolLogicDeployerLibraryArtifact = require("@superfluid-finance/ethereum-contracts/build/hardhat/contracts/utils/SuperfluidFrameworkDeploymentSteps.t.sol/SuperfluidPoolLogicDeployerLibrary.json");
const SuperfluidPoolNFTLogicDeployerLibraryArtifact = require("@superfluid-finance/ethereum-contracts/build/hardhat/contracts/utils/SuperfluidFrameworkDeploymentSteps.t.sol/SuperfluidPoolNFTLogicDeployerLibrary.json");
const ProxyDeployerLibraryArtifact = require("@superfluid-finance/ethereum-contracts/build/hardhat/contracts/utils/SuperfluidFrameworkDeploymentSteps.t.sol/ProxyDeployerLibrary.json");
const CFAv1ForwarderDeployerLibraryArtifact = require("@superfluid-finance/ethereum-contracts/build/hardhat/contracts/utils/SuperfluidFrameworkDeploymentSteps.t.sol/CFAv1ForwarderDeployerLibrary.json");
const GDAv1ForwarderDeployerLibraryArtifact = require("@superfluid-finance/ethereum-contracts/build/hardhat/contracts/utils/SuperfluidFrameworkDeploymentSteps.t.sol/GDAv1ForwarderDeployerLibrary.json");
const SuperTokenFactoryDeployerLibraryArtifact = require("@superfluid-finance/ethereum-contracts/build/hardhat/contracts/utils/SuperfluidFrameworkDeploymentSteps.t.sol/SuperTokenFactoryDeployerLibrary.json");
const SuperfluidFrameworkDeployerArtifact = require("@superfluid-finance/ethereum-contracts/build/hardhat/contracts/utils/SuperfluidFrameworkDeployer.t.sol/SuperfluidFrameworkDeployer.json");
const SlotsBitmapLibraryArtifact = require("@superfluid-finance/ethereum-contracts/build/hardhat/contracts/libs/SlotsBitmapLibrary.sol/SlotsBitmapLibrary.json");
const TokenDeployerLibraryArtifact = require("@superfluid-finance/ethereum-contracts/build/hardhat/contracts/utils/SuperfluidFrameworkDeploymentSteps.t.sol/TokenDeployerLibrary.json");

const ERC1820Registry = require("../dev-scripts/artifacts/ERC1820Registry.json");

const ERC1820_ADDRESS = "0x1820a4b7618bde71dce8cdc73aab6c95905fad24";
const ERC1820_BIN = ERC1820Registry.bin;
const ERC1820_DEPLOYER = "0xa990077c3205cbDf861e17Fa532eeB069cE9fF96";
const ERC1820_PAYLOAD =
    "0xf90a388085174876e800830c35008080b909e5" +
    ERC1820_BIN +
    "1ba01820182018201820182018201820182018201820182018201820182018201820a01820182018201820182018201820182018201820182018201820182018201820";

async function deployERC1820(provider) {
    if (process.env.DEBUG_CONSOLE === true) {
        console.log("Deploying ERC1820...");
    }
    const code = await provider.send("eth_getCode", [
        ERC1820_ADDRESS,
        "latest",
    ]);
    if (code === "0x") {
        const [from] = await provider.send("eth_accounts", []);

        await provider.send("eth_sendTransaction", [
            {
                from,
                to: ERC1820_DEPLOYER,
                value: "0x11c37937e080000",
            },
        ]);
        await provider.send("eth_sendRawTransaction", [ERC1820_PAYLOAD]);

        if (process.env.DEBUG_CONSOLE === true) {
            console.log("ERC1820 registry successfully deployed");
        }
    }
}

/**
 * Gets the address of the deployed contract.
 * This is for handling the different contract objects in ethers v5 (contract.address)
 * vs ethers v6 (contract.target), that is, v6 does not have contract.address and vice versa.
 * @param {ethers.Contract} contract
 * @returns
 */
const getContractAddress = (contract) => {
    return contract.address || contract.target;
};

const _getFactoryAndReturnDeployedContract = async (
    contractName,
    artifact,
    signerOrOptions,
    ...args
) => {
    if (process.env.DEBUG_CONSOLE === true) {
        console.log(`Deploying ${contractName}...`);
    }
    const ContractFactory = await ethers.getContractFactoryFromArtifact(
        artifact,
        signerOrOptions
    );
    const contract = await ContractFactory.deploy(...args);
    // ethers v5
    if (contract.deployed) {
        await contract.deployed();
    } else if (!contract.deployed) {
        // ethers v6
        await contract.waitForDeployment();
    }

    if (process.env.DEBUG_CONSOLE === true) {
        console.log(
            `${contractName} Deployed At:`,
            getContractAddress(contract)
        );
    }
    return contract;
};

const deployTestFrameworkWithEthersV6 = async (privateKey, provider) => {
    if (!privateKey) throw new Error("You must pass a private key.");
    if (!provider) throw new Error("You must pass a provider.");

    const signer = new ethers.Wallet(privateKey, provider);

    return await _deployTestFramework(provider, signer);
};

const deployTestFrameworkWithEthersV5 = async (ethersV5Signer) => {
    if (!ethersV5Signer.provider)
        throw new Error("Your signer must have a provider.");
    return await _deployTestFramework(ethersV5Signer.provider, ethersV5Signer);
};

const _deployTestFramework = async (provider, signer) => {
    await deployERC1820(provider);
    const SlotsBitmapLibrary = await _getFactoryAndReturnDeployedContract(
        "SlotsBitmapLibrary",
        SlotsBitmapLibraryArtifact,
        signer
    );
    const SuperfluidGovDeployerLibrary =
        await _getFactoryAndReturnDeployedContract(
            "SuperfluidGovDeployerLibrary",
            SuperfluidGovDeployerLibraryArtifact,
            signer
        );
    const SuperfluidHostDeployerLibrary =
        await _getFactoryAndReturnDeployedContract(
            "SuperfluidHostDeployerLibrary",
            SuperfluidHostDeployerLibraryArtifact,
            signer
        );
    const SuperfluidCFAv1DeployerLibrary =
        await _getFactoryAndReturnDeployedContract(
            "SuperfluidCFAv1DeployerLibrary",
            SuperfluidCFAv1DeployerLibraryArtifact,
            signer
        );
    const SuperfluidIDAv1DeployerLibrary =
        await _getFactoryAndReturnDeployedContract(
            "SuperfluidIDAv1DeployerLibrary",
            SuperfluidIDAv1DeployerLibraryArtifact,
            {
                signer,
                libraries: {
                    SlotsBitmapLibrary: getContractAddress(SlotsBitmapLibrary),
                },
            }
        );

    const SuperfluidPoolDeployerLibrary =
        await _getFactoryAndReturnDeployedContract(
            "SuperfluidPoolDeployerLibrary",
            SuperfluidPoolDeployerLibraryArtifact,
            signer
        );

    const SuperfluidGDAv1DeployerLibrary =
        await _getFactoryAndReturnDeployedContract(
            "SuperfluidGDAv1DeployerLibrary",
            SuperfluidGDAv1DeployerLibraryArtifact,
            {
                signer,
                libraries: {
                    SuperfluidPoolDeployerLibrary:
                        SuperfluidPoolDeployerLibrary.address,
                    SlotsBitmapLibrary: SlotsBitmapLibrary.address,
                },
            }
        );
    const SuperTokenDeployerLibrary =
        await _getFactoryAndReturnDeployedContract(
            "SuperTokenDeployerLibrary",
            SuperTokenDeployerLibraryArtifact,
            {
                signer,
            }
        );
    const SuperfluidPeripheryDeployerLibrary =
        await _getFactoryAndReturnDeployedContract(
            "SuperfluidPeripheryDeployerLibrary",
            SuperfluidPeripheryDeployerLibraryArtifact,
            signer
        );

    const SuperfluidPoolLogicDeployerLibrary =
        await _getFactoryAndReturnDeployedContract(
            "SuperfluidPoolLogicDeployerLibrary",
            SuperfluidPoolLogicDeployerLibraryArtifact,
            signer
        );
    const SuperfluidPoolNFTLogicDeployerLibrary =
        await _getFactoryAndReturnDeployedContract(
            "SuperfluidPoolNFTLogicDeployerLibrary",
            SuperfluidPoolNFTLogicDeployerLibraryArtifact,
            signer
        );
    const ProxyDeployerLibrary = await _getFactoryAndReturnDeployedContract(
        "ProxyDeployerLibrary",
        ProxyDeployerLibraryArtifact,
        signer
    );
    const CFAv1ForwarderDeployerLibrary =
        await _getFactoryAndReturnDeployedContract(
            "CFAv1ForwarderDeployerLibrary",
            CFAv1ForwarderDeployerLibraryArtifact,
            signer
        );
    const GDAv1ForwarderDeployerLibrary =
        await _getFactoryAndReturnDeployedContract(
            "GDAv1ForwarderDeployerLibrary",
            GDAv1ForwarderDeployerLibraryArtifact,
            signer
        );
    const SuperTokenFactoryDeployerLibrary =
        await _getFactoryAndReturnDeployedContract(
            "SuperTokenFactoryDeployerLibrary",
            SuperTokenFactoryDeployerLibraryArtifact,
            signer
        );
    const TokenDeployerLibrary = await _getFactoryAndReturnDeployedContract(
        "TokenDeployerLibrary",
        TokenDeployerLibraryArtifact,
        signer
    );

    const sfDeployer = await _getFactoryAndReturnDeployedContract(
        "SuperfluidFrameworkDeployer",
        SuperfluidFrameworkDeployerArtifact,
        {
            signer,
            libraries: {
                SuperfluidGovDeployerLibrary: getContractAddress(
                    SuperfluidGovDeployerLibrary
                ),
                SuperfluidHostDeployerLibrary: getContractAddress(
                    SuperfluidHostDeployerLibrary
                ),
                SuperfluidCFAv1DeployerLibrary: getContractAddress(
                    SuperfluidCFAv1DeployerLibrary
                ),
                SuperfluidIDAv1DeployerLibrary: getContractAddress(
                    SuperfluidIDAv1DeployerLibrary
                ),
                SuperfluidGDAv1DeployerLibrary: getContractAddress(
                    SuperfluidGDAv1DeployerLibrary
                ),
                SuperfluidPeripheryDeployerLibrary: getContractAddress(
                    SuperfluidPeripheryDeployerLibrary
                ),
                SuperTokenDeployerLibrary: getContractAddress(
                    SuperTokenDeployerLibrary
                ),
                SuperfluidPoolLogicDeployerLibrary: getContractAddress(
                    SuperfluidPoolLogicDeployerLibrary
                ),
                SuperfluidPoolNFTLogicDeployerLibrary: getContractAddress(
                    SuperfluidPoolNFTLogicDeployerLibrary
                ),
                ProxyDeployerLibrary: getContractAddress(ProxyDeployerLibrary),
                CFAv1ForwarderDeployerLibrary: getContractAddress(
                    CFAv1ForwarderDeployerLibrary
                ),
                GDAv1ForwarderDeployerLibrary: getContractAddress(
                    GDAv1ForwarderDeployerLibrary
                ),
                SuperTokenFactoryDeployerLibrary: getContractAddress(
                    SuperTokenFactoryDeployerLibrary
                ),
                TokenDeployerLibrary: getContractAddress(TokenDeployerLibrary),
            },
        }
    );
    const numSteps = await sfDeployer.getNumSteps();
    for (let i = 0; i < numSteps; i++) {
        await sfDeployer.executeStep(i);
    }
    return {frameworkDeployer: sfDeployer};
};

const printProtocolFrameworkAddresses = (framework) => {
    const output = {
        Host: framework.host,
        CFAv1: framework.cfa,
        IDAv1: framework.ida,
        SuperTokenFactory: framework.superTokenFactory,
        SuperTokenLogic: framework.superTokenLogic,
        Resolver: framework.resolver,
        SuperfluidLoader: framework.superfluidLoader,
        CFAv1Forwarder: framework.cfaV1Forwarder,
    };

    console.log(JSON.stringify(output, null, 2));

    return output;
};

/**
 * {DEPRECATED}
 * Deploys Superfluid Framework in local testing environments.
 *
 * NOTE: This only works with Hardhat + ethers v5.
 * @returns SuperfluidFrameworkDeployer Contract object
 */
const deployTestFramework = async () => {
    const signer = (await ethers.getSigners())[0];
    return await deployTestFrameworkWithEthersV5(signer);
};

module.exports = {
    deployTestFramework,
    deployTestFrameworkWithEthersV5,
    deployTestFrameworkWithEthersV6,
    printProtocolFrameworkAddresses,
};
