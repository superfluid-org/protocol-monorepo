const fs = require("fs");
const util = require("util");
const getConfig = require("./libs/getConfig");
const SuperfluidSDK = require("@superfluid-finance/js-sdk");
const {
    getScriptRunnerFactory: S,
    getCodeAddress,
    extractWeb3Options,
    ZERO_ADDRESS,
} = require("./libs/common");

/**
 * @dev Inspect accounts and their agreements
 * @param {Array} argv Overriding command line arguments
 * @param {boolean} options.isTruffle Whether the script is used within native truffle framework
 * @param {Web3} options.web3  Injected web3 instance
 * @param {Address} options.from Address to deploy contracts from
 * @param {boolean} options.skipTokens Don't iterate through tokens
 *                  (overriding env: SKIP_TOKENS)
 *
 * Usage: npx truffle exec ops-scripts/info-print-contract-addresses : {OUTPUT_FILE}
 */
module.exports = eval(`(${S.toString()})()`)(async function (
    args,
    options = {}
) {
    let output = "";

    let {
        protocolReleaseVersion,
        skipTokens
    } = options;
    skipTokens = skipTokens || process.env.SKIP_TOKENS;

    if (args.length !== 1) {
        throw new Error("Wrong number of arguments");
    }
    const outputFilename = args.shift();

    const networkType = await web3.eth.net.getNetworkType();
    const networkId = await web3.eth.net.getId();
    const chainId = await web3.eth.getChainId();
    console.log("network Type: ", networkType);
    console.log("network ID: ", networkId);
    console.log("chain ID: ", chainId);
    const config = getConfig(chainId);

    const sf = new SuperfluidSDK.Framework({
        ...extractWeb3Options(options),
        version: protocolReleaseVersion,
        tokens: skipTokens ? [] : config.tokenList,
        loadSuperNativeToken: !skipTokens, // defaults to true
        additionalContracts: ["UUPSProxiable"],
    });
    await sf.initialize();

    const SuperToken = artifacts.require("SuperToken");
    const UUPSProxiable = artifacts.require("UUPSProxiable");
    const ISuperTokenFactory = artifacts.require("ISuperTokenFactory");
    const GeneralDistributionAgreementV1 = artifacts.require(
        "GeneralDistributionAgreementV1"
    );
    const SuperfluidUpgradeableBeacon = artifacts.require(
        "SuperfluidUpgradeableBeacon"
    );

    if (config.isTestnet) {
        output += "IS_TESTNET=1\n";
    }

    output += `NETWORK_ID=${networkId}\n`;
    output += `RESOLVER=${sf.resolver.address}\n`;
    output += `SUPERFLUID_LOADER=${sf.loader.address}\n`;
    output += `SUPERFLUID_HOST_PROXY=${sf.host.address}\n`;
    output += `SUPERFLUID_HOST_LOGIC=${await getCodeAddress(
        UUPSProxiable,
        sf.host.address
    )}\n`;
    output += `SUPERFLUID_GOVERNANCE=${await sf.host.getGovernance()}\n`;

    // If govenrnance is upgradable, also add the logic
    try {
        const gov = await sf.contracts.UUPSProxiable.at(
            await sf.host.getGovernance.call()
        );
        output += `SUPERFLUID_GOVERNANCE_LOGIC=${await gov.getCodeAddress()}\n`;
    } catch (e) {
        // ignore
    }

    output += `SUPER_TOKEN_FACTORY_PROXY=${await sf.host.getSuperTokenFactory()}\n`;
    output += `SUPER_TOKEN_FACTORY_LOGIC=${await sf.host.getSuperTokenFactoryLogic()}\n`;
    output += `CFA_PROXY=${sf.agreements.cfa.address}\n`;
    output += `CFA_LOGIC=${await getCodeAddress(
        UUPSProxiable,
        sf.agreements.cfa.address
    )}\n`;
    output += `IDA_PROXY=${sf.agreements.ida.address}\n`;
    output += `SLOTS_BITMAP_LIBRARY=${
        "0x" +
        (
            await web3.eth.call({
                to: sf.agreements.ida.address,
                data: "0x3fd4176a", //SLOTS_BITMAP_LIBRARY()
            })
        ).slice(-40)
    }\n`;
    output += `IDA_LOGIC=${await getCodeAddress(
        UUPSProxiable,
        sf.agreements.ida.address
    )}\n`;
    const gdaProxy = await sf.host.getAgreementClass(
        web3.utils.sha3(
            "org.superfluid-finance.agreements.GeneralDistributionAgreement.v1"
        )
    );
    output += `GDA_PROXY=${gdaProxy}\n`;
    output += `GDA_SLOTS_BITMAP_LIBRARY=${
        "0x" +
        (
            await web3.eth.call({
                to: gdaProxy,
                data: "0x3fd4176a", //SLOTS_BITMAP_LIBRARY()
            })
        ).slice(-40)
    }\n`;
    output += `GDA_LOGIC=${await getCodeAddress(UUPSProxiable, gdaProxy)}\n`;

    const gdaContract = await GeneralDistributionAgreementV1.at(gdaProxy);
    const superfluidPoolBeaconContract = await SuperfluidUpgradeableBeacon.at(
        await gdaContract.superfluidPoolBeacon()
    );
    output += `SUPERFLUID_POOL_DEPLOYER_LIBRARY=${await gdaContract.SUPERFLUID_POOL_DEPLOYER_ADDRESS()}\n`;
    output += `SUPERFLUID_POOL_BEACON=${superfluidPoolBeaconContract.address}\n`;
    output += `SUPERFLUID_POOL_LOGIC=${await superfluidPoolBeaconContract.implementation()}\n`;

    const superTokenLogicAddress = await (
        await ISuperTokenFactory.at(await sf.host.getSuperTokenFactory())
    ).getSuperTokenLogic();
    output += `SUPER_TOKEN_LOGIC=${superTokenLogicAddress}\n`;

    const superTokenLogicContract = await SuperToken.at(superTokenLogicAddress);

    // not yet deployed on all networks
    // TODO: remove try after rollout
    try {
        const poolAdminNFTProxyAddress =
            await superTokenLogicContract.POOL_ADMIN_NFT();
        output += `POOL_ADMIN_NFT_PROXY=${poolAdminNFTProxyAddress}\n`;

        const poolAdminNFTLogicAddress = await (
            await UUPSProxiable.at(poolAdminNFTProxyAddress)
        ).getCodeAddress();
        output += `POOL_ADMIN_NFT_LOGIC=${poolAdminNFTLogicAddress}\n`;

        const poolMemberNFTProxyAddress =
            await superTokenLogicContract.POOL_MEMBER_NFT();
        output += `POOL_MEMBER_NFT_PROXY=${poolMemberNFTProxyAddress}\n`;

        const poolMemberNFTLogicAddress = await (
            await UUPSProxiable.at(poolMemberNFTProxyAddress)
        ).getCodeAddress();
        output += `POOL_MEMBER_NFT_LOGIC=${poolMemberNFTLogicAddress}\n`;
    } catch (e) {
        console.warn("POOL_ADMIN_NFT or POOL_MEMBER_NFT probably not deployed yet");
    }

    try {
        const erc2771ForwarderAddr = await sf.host.getERC2771Forwarder();
        output += `ERC2771_FORWARDER=${erc2771ForwarderAddr}\n`;
        // not working - apparently we only get the ISuperfluid in sf.host
        const simpleForwarderAddr = await sf.host.SIMPLE_FORWARDER();
        output += `SIMPLE_FORWARDER=${simpleForwarderAddr}\n`;
    } catch(e) {
        console.warn("[Simple|ERC2771]Forwarder probably not deployed yet");
    }

    if (! skipTokens) {
        await Promise.all(
            config.tokenList.map(async (tokenName) => {
                output += `SUPER_TOKEN_${tokenName.toUpperCase()}=${
                    sf.tokens[tokenName].address
                }\n`;
                const underlyingTokenSymbol = await sf.tokens[
                    tokenName
                ].underlyingToken.symbol.call();
                output += `NON_SUPER_TOKEN_${underlyingTokenSymbol.toUpperCase()}=${
                    sf.tokens[tokenName].underlyingToken.address
                }\n`;
            })
        );
        if (sf.config.nativeTokenSymbol) {
            output += `SUPER_TOKEN_NATIVE_COIN=${
                sf.tokens[sf.config.nativeTokenSymbol + "x"].address
            }\n`;
        }
    }

    // forwarders
    if (config.metadata?.contractsV1?.cfaV1Forwarder) {
        output += `CFAV1_FORWARDER=${config.metadata.contractsV1.cfaV1Forwarder}\n`;
    }
    if (config.metadata?.contractsV1?.gdaV1Forwarder) {
        output += `GDAV1_FORWARDER=${config.metadata.contractsV1.gdaV1Forwarder}\n`;
    }

    // optional periphery contracts

    if (config.metadata?.contractsV1?.toga) {
        output += `TOGA=${config.metadata.contractsV1.toga}\n`;
    }
    if (config.metadata?.contractsV1?.batchLiquidator) {
        output += `BATCH_LIQUIDATOR=${config.metadata.contractsV1.batchLiquidator}\n`;
    }
    if (config.metadata?.contractsV1?.flowScheduler) {
        output += `FLOW_SCHEDULER=${config.metadata.contractsV1.flowScheduler}\n`;
    }
    if (config.metadata?.contractsV1?.vestingScheduler) {
        output += `VESTING_SCHEDULER=${config.metadata.contractsV1.vestingScheduler}\n`;
    }

    await util.promisify(fs.writeFile)(outputFilename, output);
});
