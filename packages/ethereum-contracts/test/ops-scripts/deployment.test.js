const Web3 = require("web3");
const {web3tx} = require("@decentral.ee/web3-helpers");
const {codeChanged} = require("../../ops-scripts/libs/common");
const deployFramework = require("../../ops-scripts/deploy-framework");
const deployTestToken = require("../../ops-scripts/deploy-test-token");
const deploySuperToken = require("../../ops-scripts/deploy-super-token");
const deployTestEnvironment = require("../../ops-scripts/deploy-test-environment");
const deployAuxContracts = require("../../ops-scripts/deploy-aux-contracts");
const getConfig = require("../../ops-scripts/libs/getConfig");
const {assertIdaFreezeCannotBeReenabled} = deployFramework;
const {expect} = require("chai");
const Resolver = artifacts.require("Resolver");
const TestToken = artifacts.require("TestToken");
const InstantDistributionAgreementV1 = artifacts.require(
    "InstantDistributionAgreementV1"
);
const UUPSProxiable = artifacts.require("UUPSProxiable");
const Superfluid = artifacts.require("Superfluid");
const ISuperTokenFactory = artifacts.require("ISuperTokenFactory");
const {ZERO_ADDRESS} = require("@openzeppelin/test-helpers").constants;

contract("Embedded deployment scripts", (accounts) => {
    const errorHandler = (err) => {
        if (err) throw err;
    };
    const cfaV1Type = web3.utils.sha3(
        "org.superfluid-finance.agreements.ConstantFlowAgreement.v1"
    );
    const idaV1Type = web3.utils.sha3(
        "org.superfluid-finance.agreements.InstantDistributionAgreement.v1"
    );

    beforeEach(() => {
        // cleanup environment variables that might affect the test
        delete process.env.RESET_TOKEN;
        delete process.env.RELEASE_VERSION;
        delete process.env.RESOLVER_ADDRESS;
    });

    afterEach(() => {
        // cleanup environment after each test
        delete process.env.RESOLVER_ADDRESS;
    });

    async function getSuperfluidAddresses() {
        const version = "test";
        const superfluidName = `Superfluid.${version}`;
        const govName = `TestGovernance.${version}`;
        const resolver = await Resolver.at(process.env.RESOLVER_ADDRESS);
        const superfluidLoader = await resolver.get("SuperfluidLoader-v1");
        const superfluid = await Superfluid.at(
            await resolver.get(superfluidName)
        );
        const superfluidCode = await superfluid.getCodeAddress.call();
        const gov = await resolver.get(govName);
        const superTokenFactory = await superfluid.getSuperTokenFactory.call();
        const superTokenFactoryLogic =
            await superfluid.getSuperTokenFactoryLogic.call();
        const superTokenLogic = await (
            await ISuperTokenFactory.at(superTokenFactory)
        ).getSuperTokenLogic();
        const cfa = await (
            await UUPSProxiable.at(
                await superfluid.getAgreementClass(cfaV1Type)
            )
        ).getCodeAddress.call();
        const ida = await (
            await UUPSProxiable.at(
                await superfluid.getAgreementClass(idaV1Type)
            )
        ).getCodeAddress.call();
        const s = {
            superfluidLoader,
            superfluid,
            superfluidCode,
            gov,
            superTokenFactory,
            superTokenFactoryLogic,
            superTokenLogic,
            cfa,
            ida,
        };
        // validate addresses
        assert.notEqual(
            superfluidLoader,
            ZERO_ADDRESS,
            "superfluidLoader not set"
        );
        assert.notEqual(
            s.superfluidCode,
            ZERO_ADDRESS,
            "superfluidCode not set"
        );
        assert.notEqual(s.gov, ZERO_ADDRESS, "gov not set");
        assert.notEqual(
            s.superTokenFactory,
            ZERO_ADDRESS,
            "superTokenFactory not set"
        );
        assert.notEqual(
            s.superTokenFactoryLogic,
            ZERO_ADDRESS,
            "superTokenFactoryLogic not set"
        );
        assert.notEqual(
            s.superTokenLogic,
            ZERO_ADDRESS,
            "superTokenLogic not set"
        );
        assert.notEqual(s.cfa, ZERO_ADDRESS, "cfa not registered");
        assert.notEqual(s.ida, ZERO_ADDRESS, "ida not registered");
        assert.isTrue(
            await s.superfluid.isAgreementClassListed.call(
                await s.superfluid.getAgreementClass(cfaV1Type)
            )
        );
        assert.isTrue(
            await s.superfluid.isAgreementClassListed.call(
                await s.superfluid.getAgreementClass(idaV1Type)
            )
        );
        assert.isTrue(await s.superfluid.isAgreementTypeListed.call(cfaV1Type));
        assert.isTrue(await s.superfluid.isAgreementTypeListed.call(idaV1Type));
        return s;
    }

    // Keep the local node while exercising production chain policy from the same deployment script.
    async function withChainId(chainId, fn) {
        const getChainId = web3.eth.getChainId;
        web3.eth.getChainId = async () => chainId;
        try {
            return await fn();
        } finally {
            web3.eth.getChainId = getChainId;
        }
    }

    it("IDA freeze config is chain-dependent without env vars", () => {
        const optimism = getConfig(10);
        assert.isFalse(
            optimism.idaNewActivityFrozen,
            "optimism-mainnet should keep IDA enabled"
        );
        assert.equal(optimism.idaMaxNumSubscriptions, 32);

        const opSepolia = getConfig(11155420);
        assert.isFalse(
            opSepolia.idaNewActivityFrozen,
            "optimism-sepolia should keep IDA enabled"
        );
        assert.equal(opSepolia.idaMaxNumSubscriptions, 32);

        const polygon = getConfig(137);
        assert.isTrue(
            polygon.idaNewActivityFrozen,
            "polygon should freeze IDA new activity"
        );
        assert.equal(polygon.idaMaxNumSubscriptions, 256);

        const ethereum = getConfig(1);
        assert.isTrue(ethereum.idaNewActivityFrozen);
        assert.equal(ethereum.idaMaxNumSubscriptions, 256);

        const base = getConfig(8453);
        assert.isTrue(base.idaNewActivityFrozen);

        const local = getConfig(31337);
        assert.isFalse(
            local.idaNewActivityFrozen,
            "local tests keep IDA fully usable"
        );
        assert.equal(local.idaMaxNumSubscriptions, 256);
    });

    describe("IDA freeze preflight reads", () => {
        const proxy = "0x" + "11".repeat(20);
        const implementation = "0x" + "22".repeat(20);
        const selector = (signature) => web3.utils.sha3(signature).slice(0, 10);
        const word = (value) => web3.eth.abi.encodeParameter("uint256", value);
        const host = {getAgreementClass: {call: async () => proxy}};

        function reader({legacy = false, response = word(1), failure} = {}) {
            return {
                utils: web3.utils,
                eth: {
                    abi: web3.eth.abi,
                    getCode: async (address) => {
                        assert.equal(address.toLowerCase(), implementation);
                        return legacy
                            ? "0x60006000"
                            : selector("NEW_ACTIVITY_FROZEN()");
                    },
                    call: async ({data}) => {
                        if (data === selector("getCodeAddress()")) {
                            return web3.eth.abi.encodeParameter(
                                "address",
                                implementation
                            );
                        }
                        if (failure) throw new Error(failure);
                        if (data === selector("MAX_NUM_SUBSCRIPTIONS()"))
                            return word(256);
                        return response;
                    },
                },
            };
        }

        it("accepts legacy and active IDA, and preserves a freeze", async () => {
            await assertIdaFreezeCannotBeReenabled(
                reader({legacy: true}),
                host,
                idaV1Type,
                false
            );
            await assertIdaFreezeCannotBeReenabled(
                reader({response: word(0)}),
                host,
                idaV1Type,
                false
            );
            await assertIdaFreezeCannotBeReenabled(
                reader(),
                host,
                idaV1Type,
                true
            );
        });

        it("fails closed on RPC errors and malformed freeze responses", async () => {
            for (const options of [
                {failure: "RPC unavailable"},
                {failure: "execution reverted"},
                {legacy: true, failure: "RPC unavailable"},
                {response: "0x"},
                {response: word(2)},
            ]) {
                let error;
                try {
                    await assertIdaFreezeCannotBeReenabled(
                        reader(options),
                        host,
                        idaV1Type,
                        false
                    );
                } catch (err) {
                    error = err;
                }
                assert.exists(error, JSON.stringify(options));
            }
        });
    });

    it("codeChanged function", async () => {
        {
            const callbackGasLimit = 3000000;
            // with constructor param
            const a1 = await web3tx(Superfluid.new, "Superfluid.new 1")(
                false, // nonUpgradable
                false, // appWhiteListingEnabled
                callbackGasLimit, // callbackGasLimit
                ZERO_ADDRESS, // simpleForwarder
                ZERO_ADDRESS, // erc2771Forwarder
                ZERO_ADDRESS // simpleAcl
            );
            assert.isFalse(
                await codeChanged(web3, Superfluid, a1.address, [
                    false,
                    false,
                    callbackGasLimit,
                    ZERO_ADDRESS,
                    ZERO_ADDRESS,
                    ZERO_ADDRESS,
                ])
            );
        }
        {
            // address constructor param
            const ConstantFlowAgreementV1 = artifacts.require(
                "ConstantFlowAgreementV1"
            );
            const a1 = await web3tx(
                ConstantFlowAgreementV1.new,
                "ConstantFlowAgreementV1.new 1"
            )(ZERO_ADDRESS);
            assert.isFalse(
                await codeChanged(web3, ConstantFlowAgreementV1, a1.address, [
                    ZERO_ADDRESS,
                ])
            );
            assert.isTrue(
                await codeChanged(web3, ConstantFlowAgreementV1, a1.address, [
                    accounts[0],
                ])
            );
        }
    });

    it("codeChanged detects immutable changes and linked library changes", async () => {
        const IDA = artifacts.require("InstantDistributionAgreementV1");
        const Library = artifacts.require("SlotsBitmapLibrary");
        const library = await Library.new();
        IDA.link(library);
        const args = [accounts[0], false, 32];
        const ida = await IDA.new(...args);
        assert.isFalse(await codeChanged(web3, IDA, ida.address, args));
        for (const changedArgs of [
            [accounts[1], false, 32],
            [accounts[0], true, 32],
            [accounts[0], false, 256],
        ]) {
            assert.isTrue(
                await codeChanged(web3, IDA, ida.address, changedArgs)
            );
        }
        const relinkedIDA = artifacts.require("InstantDistributionAgreementV1");
        relinkedIDA.link(await Library.new());
        assert.isTrue(await codeChanged(web3, relinkedIDA, ida.address, args));
        assert.isTrue(await codeChanged(web3, IDA, ZERO_ADDRESS, args));
    });

    it("codeChanged rejects failed or empty creation simulations", async () => {
        const token = await TestToken.new("Test", "TEST", 18, 0);
        for (const call of [
            async () => "0x",
            async () => {
                throw new Error("simulation failed");
            },
        ]) {
            const reader = {
                eth: {
                    getCode: web3.eth.getCode.bind(web3.eth),
                    Contract: web3.eth.Contract,
                    call,
                },
            };
            let error;
            try {
                await codeChanged(reader, TestToken, token.address, [
                    "Test",
                    "TEST",
                    18,
                    0,
                ]);
            } catch (err) {
                error = err;
            }
            assert.exists(error);
            assert.match(error.message, /simulation.*(failed|no runtime code)/);
        }
    });

    context("Used in native truffle environment", () => {
        const deploymentOptions = {isTruffle: true};

        describe("ops-scripts/deploy-framework.js", () => {
            const SuperfluidMock = artifacts.require("SuperfluidMock");
            const SuperTokenFactory = artifacts.require("SuperTokenFactory");
            const SuperTokenFactoryMock = artifacts.require(
                "SuperTokenFactoryMock"
            );

            it("fresh deployment (default, nonUpgradable=false, useMocks=false)", async () => {
                await deployFramework(errorHandler, deploymentOptions);
                const s = await getSuperfluidAddresses();

                const factory = await SuperTokenFactory.at(
                    s.superTokenFactoryLogic
                );
                assert.isFalse(
                    await codeChanged(
                        web3,
                        SuperTokenFactory,
                        s.superTokenFactoryLogic,
                        [
                            s.superfluid.address,
                            s.superTokenLogic,
                            await factory.POOL_ADMIN_NFT_LOGIC(),
                            await factory.POOL_MEMBER_NFT_LOGIC(),
                        ]
                    )
                );
            });

            it("fresh deployment (useMocks=true)", async () => {
                await deployFramework(errorHandler, {
                    ...deploymentOptions,
                    useMocks: true,
                });
                const s = await getSuperfluidAddresses();
                await SuperfluidMock.detectNetwork();
                assert.isFalse(
                    await codeChanged(web3, SuperfluidMock, s.superfluidCode, [
                        false,
                        false,
                        await s.superfluid.CALLBACK_GAS_LIMIT(),
                        await s.superfluid.SIMPLE_FORWARDER(),
                        await s.superfluid.getERC2771Forwarder(),
                        await s.superfluid.getSimpleACL(),
                    ])
                );
                const factory = await SuperTokenFactoryMock.at(
                    s.superTokenFactoryLogic
                );
                assert.isFalse(
                    await codeChanged(
                        web3,
                        SuperTokenFactoryMock,
                        s.superTokenFactoryLogic,
                        [
                            s.superfluid.address,
                            s.superTokenLogic,
                            await factory.POOL_ADMIN_NFT_LOGIC(),
                            await factory.POOL_MEMBER_NFT_LOGIC(),
                        ]
                    )
                );
            });

            it("nonUpgradable deployment", async () => {
                // use the same resolver for the entire test
                const resolver = await web3tx(Resolver.new, "Resolver.new")();
                process.env.RESOLVER_ADDRESS = resolver.address;

                await deployFramework(errorHandler, {
                    ...deploymentOptions,
                    nonUpgradable: true,
                    useMocks: false,
                });
                try {
                    await deployFramework(errorHandler, {
                        ...deploymentOptions,
                        nonUpgradable: true,
                        useMocks: true, // force an update attempt
                    });
                } catch (err) {
                    if (process.env.IS_TRUFFLE) {
                        expect(err.message).to.include("Custom error");
                    } else {
                        expect(err.message).to.include("HOST_NON_UPGRADEABLE");
                    }
                }
            });

            it("upgrades", async () => {
                // use the same resolver for the entire test
                const resolver = await web3tx(Resolver.new, "Resolver.new")();
                process.env.RESOLVER_ADDRESS = resolver.address;

                console.log("==== First deployment");
                await deployFramework(errorHandler, deploymentOptions);
                const s1 = await getSuperfluidAddresses();

                console.log("==== Deploy again without logic contract changes");
                await deployFramework(errorHandler, deploymentOptions);
                const s2 = await getSuperfluidAddresses();
                assert.equal(
                    s1.superfluidLoader,
                    s2.superfluidLoader,
                    "SuperfluidLoader should stay the same address"
                );
                assert.equal(
                    s1.superfluid.address,
                    s2.superfluid.address,
                    "Superfluid proxy should stay the same address"
                );
                assert.equal(
                    s1.superfluidCode,
                    s2.superfluidCode,
                    "superfluid logic deployment not required"
                );
                assert.equal(
                    s1.gov,
                    s2.gov,
                    "Governance deployment not required"
                );
                assert.equal(
                    s1.superTokenFactory,
                    s2.superTokenFactory,
                    "superTokenFactory deployment not required"
                );
                assert.equal(
                    s1.superTokenFactoryLogic,
                    s2.superTokenFactoryLogic,
                    "superTokenFactoryLogic deployment not required"
                );
                assert.equal(
                    s1.superTokenLogic,
                    s2.superTokenLogic,
                    "superTokenLogic deployment not required"
                );
                assert.equal(s1.cfa, s2.cfa, "cfa deployment not required");
                assert.equal(s1.ida, s2.ida, "ida deployment not required");

                console.log("==== Reset all");
                await deployFramework(errorHandler, {
                    ...deploymentOptions,
                    resetSuperfluidFramework: true,
                });
                const s3 = await getSuperfluidAddresses();
                assert.notEqual(
                    s3.superfluidCode,
                    ZERO_ADDRESS,
                    "superfluidCode not set"
                );
                assert.notEqual(s3.gov, ZERO_ADDRESS, "gov not set");
                assert.notEqual(
                    s3.superTokenFactory,
                    ZERO_ADDRESS,
                    "superTokenFactory not set"
                );
                assert.notEqual(
                    s3.superTokenFactoryLogic,
                    ZERO_ADDRESS,
                    "superTokenFactoryLogic not set"
                );
                assert.notEqual(
                    s3.superTokenLogic,
                    ZERO_ADDRESS,
                    "superTokenLogic not set"
                );
                assert.notEqual(s3.cfa, ZERO_ADDRESS, "cfa not registered");
                assert.notEqual(s3.ida, ZERO_ADDRESS, "ida not registered");
                assert.notEqual(s1.superfluid.address, s3.superfluid.address);
                assert.notEqual(s1.superfluidCode, s3.superfluidCode);
                assert.notEqual(s1.gov, s3.gov);
                assert.notEqual(s1.superTokenFactory, s3.superTokenFactory);
                assert.notEqual(s1.superTokenLogic, s3.superTokenLogic);
                assert.notEqual(s1.cfa, s3.cfa);
                assert.notEqual(s1.ida, s3.ida);

                console.log("==== Deploy again with mock logic contract");
                await deployFramework(errorHandler, {
                    ...deploymentOptions,
                    useMocks: true,
                });
                const s4 = await getSuperfluidAddresses();
                assert.equal(
                    s3.superfluid.address,
                    s4.superfluid.address,
                    "Superfluid proxy should stay the same address"
                );
                assert.notEqual(
                    s3.superfluidCode,
                    s4.superfluidCode,
                    "superfluid logic deployment required"
                );
                assert.equal(
                    s3.gov,
                    s4.gov,
                    "Governance deployment not required"
                );
                assert.equal(
                    s3.superTokenFactory,
                    s4.superTokenFactory,
                    "superTokenFactory proxy should stay the same address"
                );
                assert.notEqual(
                    s3.superTokenFactoryLogic,
                    s4.superTokenFactoryLogic,
                    "superTokenFactoryLogic deployment required"
                );
                assert.notEqual(
                    s3.superTokenLogic,
                    s4.superTokenLogic,
                    "superTokenLogic update required"
                );
                assert.equal(s3.cfa, s4.cfa, "cfa deployment not required");
                assert.equal(s3.ida, s4.ida, "cfa deployment not required");
            });
        });

        it("uses chain config for IDA settings and is idempotent", async () => {
            const resolver = await web3tx(Resolver.new, "Resolver.new")();
            process.env.RESOLVER_ADDRESS = resolver.address;
            await deployFramework(errorHandler, deploymentOptions);
            const initial = await getSuperfluidAddresses();
            await withChainId(10, async () => {
                await deployFramework(errorHandler, deploymentOptions);
                const first = await getSuperfluidAddresses();
                const firstIDA = await InstantDistributionAgreementV1.at(
                    first.ida
                );
                assert.notEqual(
                    first.ida,
                    initial.ida,
                    "cap change must upgrade IDA logic"
                );
                assert.equal(
                    first.superfluid.address,
                    initial.superfluid.address
                );
                assert.isFalse(await firstIDA.NEW_ACTIVITY_FROZEN());
                assert.equal(
                    (await firstIDA.MAX_NUM_SUBSCRIPTIONS()).toString(),
                    "32"
                );
                await deployFramework(errorHandler, deploymentOptions);
                const second = await getSuperfluidAddresses();
                assert.equal(
                    second.ida,
                    first.ida,
                    "same configured IDA logic should not be redeployed"
                );
            });
            await withChainId(137, async () => {
                await deployFramework(errorHandler, deploymentOptions);
                const frozen = await getSuperfluidAddresses();
                assert.isTrue(
                    await (
                        await InstantDistributionAgreementV1.at(frozen.ida)
                    ).NEW_ACTIVITY_FROZEN()
                );
                assert.equal(
                    frozen.superfluid.address,
                    initial.superfluid.address
                );
                await deployFramework(errorHandler, deploymentOptions);
                assert.equal(
                    (await getSuperfluidAddresses()).ida,
                    frozen.ida,
                    "frozen IDA upgrade must be idempotent"
                );
            });
        });

        it("rejects a frozen-to-enabled change before deployment side effects", async () => {
            const resolver = await web3tx(Resolver.new, "Resolver.new")();
            process.env.RESOLVER_ADDRESS = resolver.address;
            await withChainId(999999, async () => {
                await deployFramework(errorHandler, {
                    ...deploymentOptions,
                    resetSuperfluidFramework: true,
                });
                const before = await getSuperfluidAddresses();
                const idaBefore = await InstantDistributionAgreementV1.at(
                    before.ida
                );
                assert.isTrue(await idaBefore.NEW_ACTIVITY_FROZEN());
                assert.equal(
                    (await idaBefore.MAX_NUM_SUBSCRIPTIONS()).toString(),
                    "256"
                );
                // Production release stays protected when another release is requested.
                await resolver.set("Superfluid.v1", before.superfluid.address);
                const nonceBefore = await web3.eth.getTransactionCount(
                    accounts[0]
                );
                for (const overrides of [
                    {},
                    {resetSuperfluidFramework: true},
                    {newTestResolver: true},
                    {protocolReleaseVersion: "another-release"},
                ]) {
                    let error;
                    await withChainId(10, async () => {
                        try {
                            await deployFramework(errorHandler, {
                                ...deploymentOptions,
                                ...overrides,
                            });
                        } catch (err) {
                            error = err;
                        }
                    });
                    assert.exists(
                        error,
                        "enabling IDA after a frozen deployment must fail"
                    );
                    assert.match(error.message, /Refusing to re-enable IDA/);
                }
                const after = await getSuperfluidAddresses();
                assert.equal(
                    after.ida,
                    before.ida,
                    "resolver must remain unchanged"
                );
                assert.equal(
                    await web3.eth.getTransactionCount(accounts[0]),
                    nonceBefore,
                    "guard must run before deployment transactions"
                );
            });
        });

        it("ops-scripts/deploy-test-token.js", async () => {
            const resolver = await web3tx(Resolver.new, "Resolver.new")();
            process.env.RESOLVER_ADDRESS = resolver.address;
            await deployFramework(errorHandler, {
                ...deploymentOptions,
                resetSuperfluidFramework: true,
            });

            // first deployment
            assert.equal(await resolver.get("tokens.TEST7262"), ZERO_ADDRESS);
            await deployTestToken(
                errorHandler,
                [":", "TEST7262"],
                deploymentOptions
            );
            const address1 = await resolver.get("tokens.TEST7262");
            assert.notEqual(address1, ZERO_ADDRESS);
            const testToken7262 = await TestToken.at(address1);
            assert.equal(18, await testToken7262.decimals());

            // second deployment
            await deployTestToken(
                errorHandler,
                [":", "TEST7262"],
                deploymentOptions
            );
            const address2 = await resolver.get("tokens.TEST7262");
            assert.equal(address2, address1);

            // new deployment after framework reset
            await deployFramework(errorHandler, {
                ...deploymentOptions,
                resetSuperfluidFramework: true,
            });
            await deployTestToken(
                errorHandler,
                [":", "TEST7262"],
                deploymentOptions
            );
            const address3 = await resolver.get("tokens.TEST7262");
            assert.equal(address3, address2);

            // deploy test token with 6 decimals
            await deployTestToken(
                errorHandler,
                [":", 6, "TEST6420"],
                deploymentOptions
            );
            const address4 = await resolver.get("tokens.TEST6420");
            const testToken6420 = await TestToken.at(address4);
            assert.equal(6, await testToken6420.decimals());
        });

        it("ops-scripts/deploy-super-token.js", async () => {
            const resolver = await web3tx(Resolver.new, "Resolver.new")();
            process.env.RESOLVER_ADDRESS = resolver.address;

            await deployFramework(errorHandler, deploymentOptions);

            // deploy test token first
            await deployTestToken(
                errorHandler,
                [":", "TEST7262"],
                deploymentOptions
            );

            // first deployment
            assert.equal(
                await resolver.get("supertokens.test.TEST7262x"),
                ZERO_ADDRESS
            );
            await deploySuperToken(
                errorHandler,
                [":", "TEST7262"],
                deploymentOptions
            );
            const s1 = await getSuperfluidAddresses();
            const address1 = await resolver.get("supertokens.test.TEST7262x");
            assert.notEqual(address1, ZERO_ADDRESS);
            assert.equal(
                s1.superTokenLogic,
                await (await UUPSProxiable.at(address1)).getCodeAddress()
            );

            // second deployment
            await deploySuperToken(
                errorHandler,
                [":", "TEST7262"],
                deploymentOptions
            );
            const s2 = await getSuperfluidAddresses();
            const address2 = await resolver.get("supertokens.test.TEST7262x");
            assert.equal(address1, address2);
            assert.equal(
                s2.superTokenLogic,
                await (await UUPSProxiable.at(address2)).getCodeAddress()
            );

            // new deployment after framework update
            await deployFramework(errorHandler, {
                ...deploymentOptions,
                useMocks: true,
            });
            await deploySuperToken(
                errorHandler,
                [":", "TEST7262"],
                deploymentOptions
            );
            const s3 = await getSuperfluidAddresses();
            const address3 = await resolver.get("supertokens.test.TEST7262x");
            assert.equal(address1, address2);
            assert.equal(
                s3.superTokenLogic,
                await (await UUPSProxiable.at(address3)).getCodeAddress()
            );

            // new deployment after framework reset
            await deployFramework(errorHandler, {
                ...deploymentOptions,
                resetSuperfluidFramework: true,
            });
            await deploySuperToken(
                errorHandler,
                [":", "TEST7262"],
                deploymentOptions
            );
            const s4 = await getSuperfluidAddresses();
            const address4 = await resolver.get("supertokens.test.TEST7262x");
            assert.notEqual(address4, address3);
            assert.equal(
                s4.superTokenLogic,
                await (await UUPSProxiable.at(address4)).getCodeAddress()
            );
        });

        it("ops-scripts/deploy-test-environment.js", async () => {
            await deployTestEnvironment(errorHandler, [], deploymentOptions);
        });

        it("ops-scripts/deploy-aux-contracts.js", async () => {
            const resolver = await web3tx(Resolver.new, "Resolver.new")();
            process.env.RESOLVER_ADDRESS = resolver.address;

            await deployFramework(errorHandler, deploymentOptions);

            await deployAuxContracts(errorHandler, deploymentOptions);
        });
    });

    context("Used in non-native truffle environment (web3)", () => {
        it("ops-scripts/deploy-test-environment.js", async () => {
            await deployTestEnvironment(errorHandler, [], {
                web3: new Web3(web3.currentProvider),
            });
        });
    });

    context("UUPS security", () => {
        it("UUPSProxiable should not be a proxy", async () => {
            const attacker = accounts[0];
            const Destructor = artifacts.require("SuperfluidDestructorMock");
            const destructor = await Destructor.new();
            await deployFramework(errorHandler, {isTruffle: true});
            const s = await getSuperfluidAddresses();
            const superfluidLogic = await Superfluid.at(s.superfluidCode);
            await superfluidLogic.initialize(attacker, {from: attacker});
            console.log("superfluid(proxy)", s.superfluid.address);
            console.log("*superfluid(logic)", superfluidLogic.address);
            console.log("**superfluid", await superfluidLogic.getCodeAddress());
            // @note we are no longer explicitly expecting the error message, but
            // instead are catching it using a try/catch.
            try {
                await superfluidLogic.updateCode(destructor.address);
            } catch (err) {
                expect(err.message).to.include("UUPSProxiable: not upgradable");
            }
        });

        it("UUPSProxy should not be a proxiable", async () => {
            const TestGovernance = artifacts.require("TestGovernance");
            await deployFramework(errorHandler, {isTruffle: true});
            const s = await getSuperfluidAddresses();
            const gov = await TestGovernance.at(s.gov);
            assert.equal(gov.address, await s.superfluid.getGovernance());
            // @note same as note above
            try {
                await gov.updateContracts(
                    s.superfluid.address,
                    s.superfluid.address, // a dead loop proxy
                    [],
                    ZERO_ADDRESS,
                    ZERO_ADDRESS
                );
            } catch (err) {
                expect(err.message).to.include("UUPSProxiable: proxy loop");
            }
        });
    });
});
