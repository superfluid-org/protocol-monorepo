const fs = require("fs");
const {deployContractsAndToken} = require("./deploy-contracts-and-token");

deployContractsAndToken()
    .then(async ({deployer, tokenDeploymentOutput}) => {
        const frameworkAddresses = await deployer.getFramework();

        const deploymentOutput = {
            network: "mainnet",
            testNetwork: "hardhat",
            hostStartBlock: 0,
            hostAddress: frameworkAddresses.host,
            cfaAddress: frameworkAddresses.cfa,
            idaAddress: frameworkAddresses.ida,
            gdaAddress: frameworkAddresses.gda,
            superTokenFactoryAddress: frameworkAddresses.superTokenFactory,
            resolverV1Address: frameworkAddresses.resolver,
            nativeAssetSuperTokenAddress:
                tokenDeploymentOutput.nativeAssetSuperTokenData
                    .nativeAssetSuperTokenAddress,
        };

        // create json output
        const JSONOutput = JSON.stringify(deploymentOutput);

        // console addresses
        delete deploymentOutput.nativeAssetSuperTokenAddress;
        console.log("Framework Deployment Output:", deploymentOutput);

        // write to hardhat.json in packages/subgraph for local testing
        const writeToDir =
            __dirname.split("ethereum-contracts")[0] +
            "subgraph/config/hardhat.json";
        fs.writeFile(writeToDir, JSONOutput, (err) => {
            if (err) {
                console.error(err);
                process.exit(1);
            } else {
                process.exit(0);
            }
        });
    })
    .catch((err) => {
        console.error(err);
        process.exit(1);
    });