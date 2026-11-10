import {Contract} from "ethers";
import {ethers} from "hardhat";

import {Resolver} from "../../typechain-types";

import {loggedTx as send} from "./logged-tx";

const {deployERC1820} = require("../../dev-scripts/deploy-test-framework");

export const RELEASE_VERSION = "test";

const ZERO_ADDRESS = ethers.constants.AddressZero;
const LIQUIDATION_PERIOD = 3600;
const PATRICIAN_PERIOD = 720;
const APP_CALLBACK_GAS_LIMIT = 12_000_000;
const IDA_MAX_NUM_SUBSCRIPTIONS = 256;
const TRUSTED_FORWARDERS = [
    "0x3075b4dc7085C48A14A5A39BBa68F58B19545971",
    "0xcfA132E353cB4E398080B9700609bb008eceB125",
    "0x6dA170169d5Fca20F902b7E5755346a97c94B07c",
    "0xFD0268E33111565dE546af2675351A4b1587F89F",
];

export type DeployFrameworkOptions = {
    nonUpgradable?: boolean;
    appWhiteListing?: boolean;
};

async function deploy(
    name: string,
    args: unknown[] = [],
    libraries?: {[name: string]: string}
): Promise<Contract> {
    const factory = await ethers.getContractFactory(name, {libraries});
    const contract = await factory.deploy(...args);
    await contract.deployed();
    console.log(`${name} deployed at ${contract.address}`);
    return contract;
}

/**
 * Deploy a fresh framework with mock contracts (SuperfluidMock,
 * SuperTokenFactoryMock, SuperTokenMock) and a new resolver,
 * governed by TestGovernance owned by the first signer.
 */
export async function deployFramework({
    nonUpgradable = false,
    appWhiteListing = false,
}: DeployFrameworkOptions = {}): Promise<Resolver> {
    const [deployer] = await ethers.getSigners();

    await deployERC1820(ethers.provider);

    const resolver = (await deploy("Resolver")) as Resolver;
    const setResolver = (key: string, value: string) =>
        send(`resolver.set ${key}`, resolver.set(key, value));

    const loader = await deploy("SuperfluidLoader", [resolver.address]);
    await setResolver("SuperfluidLoader-v1", loader.address);

    const simpleForwarder = await deploy("SimpleForwarder");
    const erc2771Forwarder = await deploy("ERC2771Forwarder");
    const simpleAcl = await deploy("SimpleACL");

    const hostLogic = await deploy("SuperfluidMock", [
        nonUpgradable,
        appWhiteListing,
        APP_CALLBACK_GAS_LIMIT,
        simpleForwarder.address,
        erc2771Forwarder.address,
        simpleAcl.address,
    ]);
    let host = hostLogic;
    if (!nonUpgradable) {
        const proxy = await deploy("UUPSProxy");
        await send(
            "host proxy.initializeProxy",
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
    await send(
        "governance.initialize",
        governance.initialize(
            host.address,
            deployer.address,
            LIQUIDATION_PERIOD,
            PATRICIAN_PERIOD,
            TRUSTED_FORWARDERS
        )
    );
    await setResolver(`TestGovernance.${RELEASE_VERSION}`, governance.address);
    await setResolver(`Superfluid.${RELEASE_VERSION}`, host.address);

    const cfa = await deploy("ConstantFlowAgreementV1", [host.address]);
    await send(
        "governance registers CFA",
        governance.registerAgreementClass(host.address, cfa.address)
    );

    const slotsBitmap = await deploy("SlotsBitmapLibrary");
    const ida = await deploy(
        "InstantDistributionAgreementV1",
        [
            host.address,
            false /* newActivityFrozen */,
            IDA_MAX_NUM_SUBSCRIPTIONS,
        ],
        {SlotsBitmapLibrary: slotsBitmap.address}
    );
    await send(
        "governance registers IDA",
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
        "governance registers GDA",
        governance.registerAgreementClass(host.address, gdaLogic.address)
    );
    const gdaAddress = await host.getAgreementClass(
        ethers.utils.id(
            "org.superfluid-finance.agreements.GeneralDistributionAgreement.v1"
        )
    );

    const cfaForwarder = await deploy("CFAv1Forwarder", [host.address]);
    await send(
        "governance enables CFAv1Forwarder",
        governance.enableTrustedForwarder(
            host.address,
            ZERO_ADDRESS,
            cfaForwarder.address
        )
    );
    await setResolver("CFAv1Forwarder", cfaForwarder.address);

    const gdaForwarder = await deploy("GDAv1Forwarder", [host.address]);
    await send(
        "governance enables GDAv1Forwarder",
        governance.enableTrustedForwarder(
            host.address,
            ZERO_ADDRESS,
            gdaForwarder.address
        )
    );
    await setResolver("GDAv1Forwarder", gdaForwarder.address);

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
        const poolConnect = ethers.utils.id("ACL_POOL_CONNECT_EXCLUSIVE_ROLE");
        const poolConnectAdmin = ethers.utils.id(
            "ACL_POOL_CONNECT_EXCLUSIVE_ROLE_ADMIN"
        );
        await send(
            "simpleAcl.setRoleAdmin pool connect",
            simpleAcl.setRoleAdmin(poolConnect, poolConnectAdmin)
        );
        await send(
            "simpleAcl.grantRole pool connect admin",
            simpleAcl.grantRole(poolConnectAdmin, gdaAddress)
        );
    }

    const poolAdminNFTProxy = await deploy("UUPSProxy");
    const poolAdminNFTLogic = await deploy("PoolAdminNFT", [
        host.address,
        gdaAddress,
    ]);
    await send("PoolAdminNFT.castrate", poolAdminNFTLogic.castrate());
    await send(
        "PoolAdminNFT proxy.initializeProxy",
        poolAdminNFTProxy.initializeProxy(poolAdminNFTLogic.address)
    );
    await send(
        "PoolAdminNFT.initialize",
        poolAdminNFTLogic
            .attach(poolAdminNFTProxy.address)
            .initialize("Pool Admin NFT", "PA")
    );

    const superTokenLogic = await deploy("SuperTokenMock", [
        host.address,
        0 /* waterMark */,
        poolAdminNFTProxy.address,
    ]);
    const superTokenFactoryLogic = await deploy("SuperTokenFactoryMock", [
        host.address,
        superTokenLogic.address,
        poolAdminNFTLogic.address,
        ZERO_ADDRESS,
    ]);

    const poolLogic = await deploy("SuperfluidPool", [gdaAddress]);
    await send("SuperfluidPool.castrate", poolLogic.castrate());

    await send(
        "governance.updateContracts",
        governance.updateContracts(
            host.address,
            ZERO_ADDRESS,
            [],
            superTokenFactoryLogic.address,
            poolLogic.address
        )
    );

    return resolver;
}
