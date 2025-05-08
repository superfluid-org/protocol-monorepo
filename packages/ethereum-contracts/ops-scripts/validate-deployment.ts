import { assert, ethers } from "hardhat";
import metadata from "@superfluid-finance/metadata";

const cfaAgreementType = ethers.utils.solidityKeccak256(["string"], ["org.superfluid-finance.agreements.ConstantFlowAgreement.v1"]);
const idaAgreementType = ethers.utils.solidityKeccak256(["string"], ["org.superfluid-finance.agreements.InstantDistributionAgreement.v1"]);
const gdaAgreementType = ethers.utils.solidityKeccak256(["string"], ["org.superfluid-finance.agreements.GeneralDistributionAgreement.v1"]);

const superTokenFactoryUuid = ethers.utils.solidityKeccak256(["string"], ["org.superfluid-finance.contracts.SuperTokenFactory.implementation"]);
const superTokenUUID = ethers.utils.solidityKeccak256(["string"], ["org.superfluid-finance.contracts.SuperToken.implementation"]);
const superfluidPoolUUID = ethers.utils.solidityKeccak256(["string"], ["org.superfluid-finance.contracts.SuperfluidPool.implementation"]);

function assertLog(condition: boolean, message: string) {
    console.log("ASSERTING:", message);
    assert(condition, "[ASSERTION ERROR]: " + message);
    console.log("ASSERTION PASSED!", "\n")
}

async function main() {
    const networkId = (await ethers.provider.getNetwork()).chainId;
    const networkMetadata = metadata.getNetworkByChainId(networkId);

    if (networkMetadata === undefined) {
        throw new Error("Network not supported");
    }

    const RESOLVER_ADDRESS = networkMetadata.contractsV1.resolver;

    const resolver = await ethers.getContractAt("Resolver", RESOLVER_ADDRESS || "");

    const hostAddress = await resolver.get("Superfluid.v1");
    const hostContract = await ethers.getContractAt("Superfluid", hostAddress);

    const superTokenFactoryAddress = await hostContract.getSuperTokenFactory();
    const superTokenFactoryContract = await ethers.getContractAt("SuperTokenFactory", superTokenFactoryAddress);
    console.log("SuperTokenFactory Address:", superTokenFactoryAddress, "\n");
    const superTokenFactoryLiveUUID = await superTokenFactoryContract.proxiableUUID();
    assertLog(superTokenFactoryUuid === superTokenFactoryLiveUUID, "SuperTokenFactory Deployed UUID matches live UUID");

    const isCFAv1ForwarderATrustedForwarder = await hostContract.isTrustedForwarder(networkMetadata.contractsV1.cfaV1Forwarder);
    assertLog(isCFAv1ForwarderATrustedForwarder, "CFAv1 Forwarder is set as trusted forwarder");

    const superTokenFactoryLogicAddress = await hostContract.getSuperTokenFactoryLogic();
    console.log("SuperTokenFactory Logic Address:", superTokenFactoryLogicAddress, "\n");

    assertLog(superTokenFactoryLogicAddress === await superTokenFactoryContract.getCodeAddress(), "Canonical Factory Logic Address matches Factory Proxy Logic Address");

    const superTokenLogicAddress = await superTokenFactoryContract.getSuperTokenLogic();
    console.log("SuperToken Logic Address:", superTokenLogicAddress, "\n");

    const superTokenLogicContract = await ethers.getContractAt("SuperToken", superTokenLogicAddress);
    const superTokenLiveUUID = await superTokenLogicContract.proxiableUUID();
    assertLog(superTokenUUID === superTokenLiveUUID, "SuperTokenFactory Deployed UUID matches live UUID");

    // validate pool NFTs
    const poolAdminNFTCanonicalLogic = await superTokenFactoryContract.POOL_ADMIN_NFT_LOGIC();
    console.log("PoolAdminNFT Canonical Logic (on Factory):", poolAdminNFTCanonicalLogic);
    const poolMemberNFTCanonicalLogic = await superTokenFactoryContract.POOL_MEMBER_NFT_LOGIC();
    console.log("PoolMemberNFT Canonical Logic (on Factory):", poolMemberNFTCanonicalLogic, "\n");

    const poolAdminNFProxy = await superTokenLogicContract.POOL_ADMIN_NFT();
    const paNFTContract = await ethers.getContractAt("PoolAdminNFT", poolAdminNFProxy);
    console.log("PoolAdminNFT:", poolAdminNFProxy);
    const poolAdminProxyLogic = await paNFTContract.getCodeAddress();
    console.log("PoolAdmin NFT Logic (on Proxy):", poolAdminProxyLogic, "\n");
    assertLog(await paNFTContract.baseURI() === "https://nft.superfluid.finance/pool/v2/getmeta", "PoolAdminNFT baseURI is equal to https://nft.superfluid.finance/pool/v2/getmeta");

    const poolMemberNFProxy = await superTokenLogicContract.POOL_MEMBER_NFT();
    console.log("PoolMemberNFT:", poolMemberNFProxy);
    const pmNFTContract = await ethers.getContractAt("PoolMemberNFT", poolMemberNFProxy);
    assertLog(await pmNFTContract.baseURI() === "https://nft.superfluid.finance/pool/v2/getmeta", "PoolMemberNFT baseURI is equal to https://nft.superfluid.finance/pool/v2/getmeta");

    const poolMemberProxyLogic = await pmNFTContract.getCodeAddress();
    console.log("ConstantInflow NFT Logic (on Proxy):", poolMemberProxyLogic);

    assertLog(await paNFTContract.proxiableUUID() !== await pmNFTContract.proxiableUUID(), "NFT proxies have different implementation.");

    assertLog(poolAdminProxyLogic === poolAdminNFTCanonicalLogic, "Pool admin proxy logic is equal to canonical pool admin logic");
    assertLog(poolMemberProxyLogic === poolMemberNFTCanonicalLogic, "Pool member proxy logic is equal to canonical pool member logic");

    const cfaAddress = await hostContract.getAgreementClass(cfaAgreementType);
    const idaAddress = await hostContract.getAgreementClass(idaAgreementType);
    const gdaAddress = await hostContract.getAgreementClass(gdaAgreementType);

    assertLog(cfaAddress !== ethers.constants.AddressZero, "CFA Address is not zero address");
    assertLog(idaAddress !== ethers.constants.AddressZero, "IDA Address is not zero address");
    assertLog(gdaAddress !== ethers.constants.AddressZero, "GDA Address is not zero address");

    const cfaContract = await ethers.getContractAt("ConstantFlowAgreementV1", cfaAddress);
    const idaContract = await ethers.getContractAt("InstantDistributionAgreementV1", idaAddress);
    const gdaContract = await ethers.getContractAt("GeneralDistributionAgreementV1", gdaAddress);

    assertLog(await cfaContract.agreementType() === cfaAgreementType, "CFA AgreementType is equal to expected agreementType")
    assertLog(await idaContract.agreementType() === idaAgreementType, "IDA AgreementType is equal to expected agreementType")
    assertLog(await gdaContract.agreementType() === gdaAgreementType, "GDA AgreementType is equal to expected agreementType")

    // GDA specific validation
    const superfluidPoolBeaconAddress = await gdaContract.superfluidPoolBeacon();
    assertLog(superfluidPoolBeaconAddress !== ethers.constants.AddressZero, "SuperfluidPoolBeaconAddress is not zero address")

    const beaconContract = await ethers.getContractAt("IBeacon", superfluidPoolBeaconAddress);
    const sfPoolBeaconImplementationAddress = await beaconContract.implementation();
    assertLog(sfPoolBeaconImplementationAddress !== ethers.constants.AddressZero, "SFPool beacon implementation is not zero address");

    const superfluidPoolContract = await ethers.getContractAt("SuperfluidPool", sfPoolBeaconImplementationAddress);
    const sfPoolLiveUUID = await superfluidPoolContract.proxiableUUID();

    assertLog(sfPoolLiveUUID === superfluidPoolUUID, "SFPool Deployed UUID is equal to expected SFPool UUID");
}

main();