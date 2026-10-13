/**
 * Fresh Superfluid framework deploy for the Hardhat suite.
 *
 * Supports the three options the tests use: useMocks, nonUpgradable, and
 * appWhiteListing. It always creates a new resolver. Upgrade detection and
 * the ops-script helpers stay in ops-scripts/deploy-framework.js.
 */
const {execSync} = require("child_process");
const {ethers} = require("hardhat");
const getConfig = require("../../ops-scripts/libs/getConfig");
const {deployERC1820} = require("../../dev-scripts/deploy-test-framework");

const ZERO = ethers.constants.AddressZero;

function versionStringToPseudoAddress(versionString) {
    const [versions, suffix] = versionString.split("-");
    const [major, minor, patch] = versions
        .split(".")
        .map((v) => v.padStart(2, "0"));
    return `0x000000000000000000${major}${minor}${patch}${suffix}`;
}

async function deploy(name, args = [], libraries) {
    const factory = await ethers.getContractFactory(
        name,
        libraries ? {libraries} : undefined
    );
    const contract = await factory.deploy(...args);
    await contract.deployed();
    console.log(`${name} ${contract.address}`);
    return contract;
}

async function send(label, txPromise) {
    console.log(`${label}: started`);
    const receipt = await (await txPromise).wait();
    console.log(`${label}: done, gas used ${receipt.gasUsed.toString()}`);
    return receipt;
}

async function setResolver(resolver, key, value) {
    console.log(`Setting resolver ${key} -> ${value}`);
    await send(`resolver.set ${key}`, resolver.set(key, value));
}

module.exports = async function deployVariantFramework(options = {}) {
    console.log("======== Deploying superfluid framework (fresh) ========");
    const protocolReleaseVersion =
        options.protocolReleaseVersion || process.env.RELEASE_VERSION || "test";
    const {chainId} = await ethers.provider.getNetwork();
    const config = getConfig(Number(chainId));
    const [deployer] = await ethers.getSigners();

    const useMocks = options.useMocks || !!process.env.USE_MOCKS;
    const nonUpgradable = options.nonUpgradable || !!process.env.NON_UPGRADABLE;
    const appWhiteListing =
        options.appWhiteListing ||
        config.gov_enableAppWhiteListing ||
        !!process.env.ENABLE_APP_WHITELISTING;
    const appCallbackGasLimit =
        options.appCallbackGasLimit || config.appCallbackGasLimit;
    const idaNewActivityFrozen = config.idaNewActivityFrozen;
    const idaMaxNumSubscriptions = Number(config.idaMaxNumSubscriptions);
    if (
        typeof idaNewActivityFrozen !== "boolean" ||
        !Number.isInteger(idaMaxNumSubscriptions) ||
        idaMaxNumSubscriptions < 1 ||
        idaMaxNumSubscriptions > 256
    ) {
        throw new Error(
            `Invalid IDA config for chain ${chainId}: ` +
                `frozen=${idaNewActivityFrozen} ` +
                `maxSlots=${config.idaMaxNumSubscriptions}`
        );
    }

    console.log("deployer:", deployer.address);
    console.log("useMocks:", useMocks);
    console.log("nonUpgradable:", nonUpgradable);
    console.log("appWhiteListing:", appWhiteListing);

    await deployERC1820(ethers.provider);

    const resolver = await deploy("Resolver");
    process.env.RESOLVER_ADDRESS = resolver.address;

    const loader = await deploy("SuperfluidLoader", [resolver.address]);
    await setResolver(resolver, "SuperfluidLoader-v1", loader.address);

    const simpleForwarder = await deploy("SimpleForwarder");
    const erc2771Forwarder = await deploy("ERC2771Forwarder");
    const simpleAcl = await deploy("SimpleACL");

    const hostName = useMocks ? "SuperfluidMock" : "Superfluid";
    const hostLogic = await deploy(hostName, [
        nonUpgradable,
        appWhiteListing,
        appCallbackGasLimit,
        simpleForwarder.address,
        erc2771Forwarder.address,
        simpleAcl.address,
    ]);
    let host = hostLogic;
    if (!nonUpgradable) {
        const proxy = await deploy("UUPSProxy");
        await send(
            "proxy.initializeProxy",
            proxy.initializeProxy(hostLogic.address)
        );
        host = hostLogic.attach(proxy.address);
    }
    await send(
        "simpleForwarder.transferOwnership",
        simpleForwarder.transferOwnership(host.address)
    );
    await send(
        "erc2771Forwarder.transferOwnership",
        erc2771Forwarder.transferOwnership(host.address)
    );

    const governance = await deploy("TestGovernance");
    await send("Superfluid.initialize", host.initialize(governance.address));
    const trustedForwarders = [
        ...(config.trustedForwarders || []),
        config.cfaFwd,
        config.gdaFwd,
        config.macroFwd,
    ].filter(Boolean);
    await send(
        "governance.initialize",
        governance.initialize(
            host.address,
            deployer.address,
            config.liquidationPeriod,
            config.patricianPeriod,
            trustedForwarders
        )
    );
    await setResolver(
        resolver,
        `TestGovernance.${protocolReleaseVersion}`,
        governance.address
    );
    await setResolver(
        resolver,
        `Superfluid.${protocolReleaseVersion}`,
        host.address
    );

    const cfa = await deploy("ConstantFlowAgreementV1", [host.address]);
    await send(
        "Governance registers CFA",
        governance.registerAgreementClass(host.address, cfa.address)
    );

    const slotsBitmap = await deploy("SlotsBitmapLibrary");
    const ida = await deploy(
        "InstantDistributionAgreementV1",
        [host.address, idaNewActivityFrozen, idaMaxNumSubscriptions],
        {SlotsBitmapLibrary: slotsBitmap.address}
    );
    await send(
        "Governance registers IDA",
        governance.registerAgreementClass(host.address, ida.address)
    );

    const poolPlaceholder = await deploy("SuperfluidPoolPlaceholder");
    const poolBeacon = await deploy("SuperfluidUpgradeableBeacon", [
        poolPlaceholder.address,
    ]);
    await send(
        "poolBeacon.transferOwnership",
        poolBeacon.transferOwnership(host.address)
    );
    const poolDeployer = await deploy("SuperfluidPoolDeployerLibrary");
    const gdaLogic = await deploy(
        "GeneralDistributionAgreementV1",
        [host.address, poolBeacon.address],
        {
            SlotsBitmapLibrary: slotsBitmap.address,
            SuperfluidPoolDeployerLibrary: poolDeployer.address,
        }
    );
    await send(
        "Governance registers GDA",
        governance.registerAgreementClass(host.address, gdaLogic.address)
    );
    const gdaType = ethers.utils.id(
        "org.superfluid-finance.agreements.GeneralDistributionAgreement.v1"
    );
    const gdaAddress = await host.getAgreementClass(gdaType);

    if (protocolReleaseVersion === "test") {
        const cfaForwarder = await deploy("CFAv1Forwarder", [host.address]);
        await send(
            "Governance set CFAv1Forwarder",
            governance.enableTrustedForwarder(
                host.address,
                ZERO,
                cfaForwarder.address
            )
        );
        await setResolver(resolver, "CFAv1Forwarder", cfaForwarder.address);

        const gdaForwarder = await deploy("GDAv1Forwarder", [host.address]);
        await send(
            "Governance set GDAv1Forwarder",
            governance.enableTrustedForwarder(
                host.address,
                ZERO,
                gdaForwarder.address
            )
        );
        await setResolver(resolver, "GDAv1Forwarder", gdaForwarder.address);
    }

    if (!nonUpgradable) {
        const registration = ethers.utils.id("ACL_SUPERAPP_REGISTRATION_ROLE");
        const registrationAdmin = ethers.utils.id(
            "ACL_SUPERAPP_REGISTRATION_ROLE_ADMIN"
        );
        await send(
            "simpleAcl.setRoleAdmin registration",
            simpleAcl.setRoleAdmin(registration, registrationAdmin)
        );
        await send(
            "simpleAcl.grantRole registration admin",
            simpleAcl.grantRole(registrationAdmin, deployer.address)
        );
        const poolRole = ethers.utils.id("ACL_POOL_CONNECT_EXCLUSIVE_ROLE");
        const poolRoleAdmin = ethers.utils.id(
            "ACL_POOL_CONNECT_EXCLUSIVE_ROLE_ADMIN"
        );
        await send(
            "simpleAcl.setRoleAdmin pool connect",
            simpleAcl.setRoleAdmin(poolRole, poolRoleAdmin)
        );
        await send(
            "simpleAcl.grantRole pool connect admin",
            simpleAcl.grantRole(poolRoleAdmin, gdaAddress)
        );
    }

    const poolAdminProxy = await deploy("UUPSProxy");
    const poolAdminLogic = await deploy("PoolAdminNFT", [
        host.address,
        gdaAddress,
    ]);
    await send("PoolAdminNFT.castrate", poolAdminLogic.castrate());
    await send(
        "PoolAdminNFT proxy.initializeProxy",
        poolAdminProxy.initializeProxy(poolAdminLogic.address)
    );
    const poolAdmin = poolAdminLogic.attach(poolAdminProxy.address);
    await send(
        "PoolAdminNFT.initialize",
        poolAdmin.initialize("Pool Admin NFT", "PA")
    );

    const tokenName = useMocks ? "SuperTokenMock" : "SuperToken";
    const tokenArgs = useMocks
        ? [host.address, 0, poolAdminProxy.address]
        : [host.address, poolAdminProxy.address];
    const superTokenLogic = await deploy(tokenName, tokenArgs);

    const factoryName = useMocks
        ? "SuperTokenFactoryMock"
        : "SuperTokenFactory";
    const factoryLogic = await deploy(factoryName, [
        host.address,
        superTokenLogic.address,
        poolAdminLogic.address,
        ZERO,
    ]);

    const poolLogic = await deploy("SuperfluidPool", [gdaAddress]);
    await send("SuperfluidPool.castrate", poolLogic.castrate());

    await send(
        "governance.updateContracts",
        governance.updateContracts(
            host.address,
            ZERO,
            [],
            factoryLogic.address,
            poolLogic.address
        )
    );

    const packageVersion = require("../../package.json").version;
    const gitRevision = execSync("git rev-parse HEAD")
        .toString()
        .slice(0, 16)
        .trim();
    const versionString = `${packageVersion}-${gitRevision}`;
    await setResolver(
        resolver,
        `versionString.${protocolReleaseVersion}`,
        versionStringToPseudoAddress(versionString)
    );

    console.log("======== Superfluid framework deployed ========");
    console.log(`export RESOLVER_ADDRESS=${resolver.address}`);
};
