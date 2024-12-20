const Web3 = require("web3");
const {web3tx} = require("@decentral.ee/web3-helpers");
const {codeChanged} = require("../../ops-scripts/libs/common");
const deployFramework = require("../../ops-scripts/deploy-framework");
const deployTestToken = require("../../ops-scripts/deploy-test-token");
const deploySuperToken = require("../../ops-scripts/deploy-super-token");
const deployTestEnvironment = require("../../ops-scripts/deploy-test-environment");
const deployAuxContracts = require("../../ops-scripts/deploy-aux-contracts");
const {expect} = require("chai");
const Resolver = artifacts.require("Resolver");
const TestToken = artifacts.require("TestToken");
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

    it("codeChanged function", async () => {
        {
            const callbackGasLimit = 3000000;
            // with constructor param
            const a1 = await web3tx(Superfluid.new, "Superfluid.new 1")(
                false, // nonUpgradable
                false, // appWhiteListingEnabled
                callbackGasLimit, // callbackGasLimit
                ZERO_ADDRESS, // simpleForwarder
                ZERO_ADDRESS // erc2771Forwarder
            );
            assert.isFalse(
                await codeChanged(web3, Superfluid, a1.address, [
                    // replace immutables with 0
                    callbackGasLimit.toString(16).padStart(64, "0"),
                ])
            );
        }
        {
            // without constructor param
            const ConstantFlowAgreementV1 = artifacts.require(
                "ConstantFlowAgreementV1"
            );
            const a1 = await web3tx(
                ConstantFlowAgreementV1.new,
                "ConstantFlowAgreementV1.new 1"
            )(ZERO_ADDRESS);
            assert.isFalse(
                await codeChanged(web3, ConstantFlowAgreementV1, a1.address)
            );
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

                // .detectNetwork().then() was added due to hardhat truffle complaining
                // that no network was set
                SuperTokenFactory.detectNetwork().then(async () => {
                    assert.isFalse(
                        await codeChanged(
                            web3,
                            SuperTokenFactory,
                            s.superTokenFactoryLogic
                        )
                    );
                });
            });

            it("fresh deployment (useMocks=true)", async () => {
                await deployFramework(errorHandler, {
                    ...deploymentOptions,
                    useMocks: true,
                });
                const s = await getSuperfluidAddresses();
                // check if it useMocks=true
                SuperfluidMock.detectNetwork().then(async () => {
                    assert.isFalse(
                        await codeChanged(
                            web3,
                            SuperfluidMock,
                            s.superfluidCode
                        )
                    );
                });
                SuperTokenFactoryMock.detectNetwork().then(async () => {
                    assert.isFalse(
                        await codeChanged(
                            web3,
                            SuperTokenFactoryMock,
                            s.superTokenFactoryLogic
                        )
                    );
                });
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

            // TODO deployment script upgrades detection only works for truffle
            if (process.env.IS_TRUFFLE) {
                it("upgrades", async () => {
                    // use the same resolver for the entire test
                    const resolver = await web3tx(
                        Resolver.new,
                        "Resolver.new"
                    )();
                    process.env.RESOLVER_ADDRESS = resolver.address;

                    console.log("==== First deployment");
                    await deployFramework(errorHandler, deploymentOptions);
                    const s1 = await getSuperfluidAddresses();

                    console.log(
                        "==== Deploy again without logic contract changes"
                    );
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
                    assert.notEqual(
                        s1.superfluid.address,
                        s3.superfluid.address
                    );
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
            }
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
