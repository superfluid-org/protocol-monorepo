import { expect } from "chai";
import { ethers } from "hardhat";
import { Framework } from "../src/index";
import { networkNameToChainIdMap } from "../src/constants";
import hre from "hardhat";
import { TestEnvironment, makeSuite } from "./TestEnvironment";

makeSuite("Framework Tests", (testEnv: TestEnvironment) => {
    describe("Validate Framework Constructor Options Tests", async () => {
        it("Should throw an error if no networkName or chainId", async () => {
            try {
                await Framework.create({
                    provider: testEnv.provider,
                    chainId: null as any,
                });
            } catch (err: any) {
                expect(err.name).to.equal("SFError");
                expect(err.message).to.equal(
                    "Framework Initialization Error: You must input chainId."
                );
                expect(err.cause).to.be.undefined;
            }
        });

        it("Should throw an error if your provider network and selected chainId/networkName don't match", async () => {
            const chainId = (await testEnv.provider.getNetwork()).chainId;
            try {
                await Framework.create({
                    // force cast because we know this exists
                    chainId: networkNameToChainIdMap.get("polygon-mainnet")!,
                    provider: testEnv.provider,
                });
            } catch (err: any) {
                expect(err.name).to.equal("SFError");
                expect(err.message).to.equal(
                    "Network Mismatch Error: Your provider network chainId is: " +
                        chainId +
                        " whereas your desired chainId is: " +
                        networkNameToChainIdMap.get("polygon-mainnet")!
                );
            }
        });

        it("Should throw an error if no provider, injected web3 or injected hardhat ethers provider", async () => {
            try {
                // NOTE: as any to get this to throw an error when test no provider initialization (as if this was JS)
                await Framework.create({
                    // force cast because we know this exists
                    chainId: networkNameToChainIdMap.get("polygon-mainnet")!,
                } as any);
            } catch (err: any) {
                expect(err.name).to.equal("SFError");
                expect(err.message).to.equal(
                    "Framework Initialization Error: You must pass in a provider, an injected web3.js or ethers.js instance when initializing the framework."
                );
                expect(err.cause).to.be.undefined;
            }
        });

        it("Should throw an error if resolver address is null on unsupported network", async () => {
            try {
                const chainId = (await testEnv.provider.getNetwork()).chainId;
                await Framework.create({
                    chainId,
                    provider: testEnv.provider,
                    protocolReleaseVersion: "test",
                });
            } catch (err: any) {
                expect(err.name).to.equal("SFError");
                expect(err.message).to.equal(
                    "Framework Initialization Error: You must input your own resolver address if you use an unsupported network."
                );
                expect(err.cause).to.be.undefined;
            }
        });
    });

    describe("Framework.create Tests", () => {
        it("Should throw an error if loadFramework fails", async () => {
            try {
                const chainId = (await testEnv.provider.getNetwork()).chainId;
                await Framework.create({
                    chainId,
                    provider: testEnv.provider,
                    resolverAddress:
                        "0x0000000000000000000000000000000000000000",
                    protocolReleaseVersion: "test",
                });
            } catch (err: any) {
                expect(err.name).to.equal("SFError");
                expect(err.message).to.contain(
                    "Framework Initialization Error: There was an error initializing the framework"
                );
                expect(err.cause).to.be.instanceOf(Error);
            }
        });

        it("Should be able to create a framework with chain id only", async () => {
            const customProvider = new ethers.providers.JsonRpcProvider(
                "https://polygon-rpc.com/",
                "matic"
            );
            await Framework.create({
                chainId: networkNameToChainIdMap.get("polygon-mainnet")!,
                provider: customProvider,
            });
        });

        it("Should be able to create a framework with web3.js via ethers.providers.Web3Provider", async () => {
            const provider = new ethers.providers.Web3Provider(
                (global as any).web3.currentProvider
            );
            const chainId = (await provider.getNetwork()).chainId;
            await Framework.create({
                chainId,
                provider,
                resolverAddress: testEnv.frameworkAddresses.resolver,
                protocolReleaseVersion: "test",
            });
        });

        it("Should be able to create a framework with injected web3", async () => {
            const chainId = (await testEnv.provider.getNetwork()).chainId;
            await Framework.create({
                chainId,
                provider: (global as any).web3,
                resolverAddress: testEnv.frameworkAddresses.resolver,
                protocolReleaseVersion: "test",
            });
        });

        it("Should be able to create a framework with injected hardhat ethers", async () => {
            const chainId = (await testEnv.provider.getNetwork()).chainId;
            await Framework.create({
                chainId,
                provider: hre.ethers,
                resolverAddress: testEnv.frameworkAddresses.resolver,
                protocolReleaseVersion: "test",
            });
        });
    });

    describe("Framework Function Tests", () => {
        it("Should catch error when creating a signer if minimum isn't passed in.", () => {
            try {
                testEnv.sdkFramework.createSigner({});
            } catch (err: any) {
                expect(err.message).to.equal(
                    "Create Signer Error: You must pass in a private key, provider or signer."
                );
                expect(err.cause).to.be.undefined;
            }
        });

        it("Should catch error when creating a signer with PK, but no provider.", () => {
            try {
                testEnv.sdkFramework.createSigner({
                    privateKey: testEnv.constants.HARDHAT_PRIVATE_KEY,
                });
            } catch (err: any) {
                expect(err.message).to.equal(
                    "Create Signer Error: You must pass in a provider with your private key."
                );
                expect(err.cause).to.be.undefined;
            }
        });

        it("Should be able to create a signer successfully with all different inputs.", () => {
            // create signer with private key
            testEnv.sdkFramework.createSigner({
                privateKey: testEnv.constants.HARDHAT_PRIVATE_KEY,
                provider: testEnv.provider,
            });

            // create signer directly
            testEnv.sdkFramework.createSigner({
                signer: testEnv.alice,
            });
        });

        it("Should be able to create an empty batch call with framework.", () => {
            testEnv.sdkFramework.batchCall([]);
        });

        it("Should be able to create an instance of a supertoken (with address) with framework.", async () => {
            const fDAIx = await testEnv.sdkFramework.loadSuperToken(
                testEnv.wrapperSuperToken.address
            );
            expect(fDAIx.settings.address).to.equal(
                testEnv.wrapperSuperToken.address
            );
        });

        it("Should be able to create an instance of a supertoken (with token symbol) with framework.", async () => {
            const tokenName = await testEnv.wrapperSuperToken.symbol({
                providerOrSigner: hre.ethers.provider,
            });
            const fDAIx = await testEnv.sdkFramework.loadSuperToken(tokenName);
            expect(fDAIx.settings.address).to.equal(
                testEnv.wrapperSuperToken.address
            );
        });

        it("Should be able to use contract object", async () => {
            const flowData = await testEnv.sdkFramework.contracts.cfaV1
                .connect(testEnv.alice)
                .getFlow(
                    testEnv.wrapperSuperToken.address,
                    testEnv.alice.address,
                    testEnv.bob.address
                );
            expect(flowData.timestamp).to.eq("0");
            expect(flowData.flowRate).to.eq("0");
            expect(flowData.deposit).to.eq("0");
            expect(flowData.owedDeposit).to.eq("0");
        });
    });
});
