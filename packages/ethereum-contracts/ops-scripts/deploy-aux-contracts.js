const {
    getScriptRunnerFactory: S,
    extractWeb3Options,
    warnProductionUUPSProxyInitRisk,
} = require("./libs/common");
const getConfig = require("./libs/getConfig");

const SuperfluidSDK = require("@superfluid-finance/js-sdk");

const SuperfluidGovernanceIIProxy = artifacts.require(
    "SuperfluidGovernanceIIProxy"
);
const SuperfluidGovernanceII = artifacts.require("SuperfluidGovernanceII");
const TOGA = artifacts.require("TOGA");

const BatchLiquidator = artifacts.require("BatchLiquidator");

/**
 * @dev Deploy auxiliary contracts: governance, TOGA, BatchLiquidator
 * To be used after a community mainnet deployment,
 * with the "handover account" set as message sender.
 * - deploy SuperfluidGovernanceII with proxy
 * - set 3Ps config
 * - deploy TOGA
 * - set TOGA as rewardAddress
 * - deploy BatchLiquidator
 * - replace governance
 *
 * SECURITY: SuperfluidGovernanceIIProxy is deployed and initializeProxy'd in
 * separate txs below. On production networks this has the same permissionless
 * initializeProxy / impl-slot-reset risk as deploy-framework.js — see UUPSProxy.sol.
 *
 * @param web3 The web3 instance to be used
 * @param from address to use for funding the deployer account
 *
 * Usage: npx truffle exec ops-scripts/deploy-aux-contracts.js
 *
 * (optional) ENV vars:
 * - GOV_LIQUIDATION_PERIOD overrides the default value of 4 hours
 * - GOV_PATRICIAN_PERIOD overrides the default value of 30 minutes
 * - TOGA_MIN_BOND_DURATION overrides the default value of 7 days
 *
 * You may also need to set RESOLVER_ADDRESS if not yet set in metadata.
 */
module.exports = eval(`(${S.toString()})({skipArgv: true})`)(async function (
    args,
    options = {}
) {
    let {protocolReleaseVersion} = options;

    console.log("======== Deploying auxiliary contracts ========");

    const chainId = await web3.eth.getChainId();
    const config = getConfig(chainId);
    if (!config.isTestnet) {
        warnProductionUUPSProxyInitRisk(
            "deploy-aux-contracts.js: SuperfluidGovernanceIIProxy deploy + initializeProxy (separate txs)"
        );
    }

    const sf = new SuperfluidSDK.Framework({
        ...extractWeb3Options(options),
        version: protocolReleaseVersion,
    });
    await sf.initialize();

    const oldGov = await sf.contracts.ISuperfluidGovernance.at(
        await sf.host.getGovernance.call()
    );
    console.log(`previous governance: ${oldGov.address}`);

    console.log("deploying production governance...");
    // SECURITY: split-tx UUPS bootstrap — see file header and UUPSProxy.sol.
    const govProxy = await SuperfluidGovernanceIIProxy.new();
    console.log("governance proxy deployed at:", govProxy.address);
    const govLogic = await SuperfluidGovernanceII.new();
    console.log("governance logic deployed at:", govLogic.address);
    await govLogic.castrate();
    console.log("marked gov logic as initialized (castrate)");
    await govProxy.initializeProxy(govLogic.address);
    console.log("governance proxy initialized with logic");
    const gov = await SuperfluidGovernanceII.at(govProxy.address);

    const liquidationPeriod = process.env.GOV_LIQUIDATION_PERIOD || 14400;
    const patricianPeriod = process.env.GOV_PATRICIAN_PERIOD || 1800;
    await gov.setPPPConfig(
        sf.host.address,
        "0x0000000000000000000000000000000000000000", // default - for all tokens
        liquidationPeriod,
        patricianPeriod
    );
    console.log(
        `set 3Ps config to liquidation period of ${liquidationPeriod} and patrician period of ${patricianPeriod}`
    );

    console.log("deploying solvency related contracts");
    const minBondDuration = process.env.TOGA_MIN_BOND_DURATION || 604800;
    const toga = await TOGA.new(sf.host.address, minBondDuration);
    console.log("TOGA deployed at:", toga.address);

    await gov.setRewardAddress(
        sf.host.address,
        "0x0000000000000000000000000000000000000000",
        toga.address
    );
    console.log("reward address set to TOGA");

    const batchLiquidator = await BatchLiquidator.new(sf.host.address);
    console.log("BatchLiquidator deployed at:", batchLiquidator.address);

    await oldGov.replaceGovernance(sf.host.address, govProxy.address);
    console.log("replaced governance");
});
