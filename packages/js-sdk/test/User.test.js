const {toBN, toWad} = require("@decentral.ee/web3-helpers");
const TestEnvironment = require("@superfluid-finance/ethereum-contracts/test/TestEnvironment");

const chai = require("chai");
const chaiAsPromised = require("chai-as-promised");
chai.use(chaiAsPromised);
const expect = chai.expect;

const emptyIda = {
    ida: {
        subscriptions: [],
    },
};

describe("User helper class", function () {
    this.timeout(300e3);
    const t = TestEnvironment.getSingleton();

    let adminAddress, aliceAddress, bobAddress, carolAddress;
    let alice, bob, carol;
    let sf;
    let superToken;

    before(async () => {
        await t.beforeTestSuite({
            isTruffle: false,
            web3,
            nAccounts: 4,
        });

        ({
            admin: adminAddress,
            alice: aliceAddress,
            bob: bobAddress,
            carol: carolAddress,
        } = t.aliases);
        ({superToken} = await t.deployNewToken("TEST2", {
            isTruffle: false,
            web3,
            doUpgrade: true,
        }));
        sf = t.sf;

        await t.pushEvmSnapshot();
    });

    after(async () => {
        await t.popEvmSnapshot();
    });

    beforeEach(async function () {
        await t.beforeEachTestCase();
        alice = sf.user({address: aliceAddress, token: superToken.address});
        bob = sf.user({address: bobAddress, token: superToken.address});
        carol = sf.user({address: carolAddress, token: superToken.address});
    });

    describe("initialize", () => {
        it("user", async () => {
            const admin = sf.user({
                address: adminAddress,
                token: superToken.address,
            });
            assert.equal(admin.address, adminAddress);
            assert.equal(admin.token, superToken.address);
            assert.equal(admin.sf, sf);
        });
    });

    describe("details", () => {
        it("shows user details", async () => {
            await alice.flow({
                recipient: bob.address,
                flowRate: "38580246913580", // 100 / mo
            });
            await bob.flow({
                recipient: carol.address,
                flowRate: "19290123456790", // 50 / mo
            });
            assert.deepEqual(await alice.details(), {
                cfa: {
                    flows: {
                        inFlows: [],
                        outFlows: [
                            {
                                sender: alice.address,
                                receiver: bob.address,
                                flowRate: "38580246913580",
                            },
                        ],
                    },
                    netFlow: "-38580246913580",
                },
                ...emptyIda,
            });
            assert.deepEqual(await bob.details(), {
                cfa: {
                    flows: {
                        inFlows: [
                            {
                                sender: alice.address,
                                receiver: bob.address,
                                flowRate: "38580246913580",
                            },
                        ],
                        outFlows: [
                            {
                                sender: bob.address,
                                receiver: carol.address,
                                flowRate: "19290123456790",
                            },
                        ],
                    },
                    netFlow: "19290123456790",
                },
                ...emptyIda,
            });
            console.log(JSON.stringify(await bob.details()));
        });
    });
    describe("new flows", () => {
        it("fail with null recipient", async () => {
            await expect(
                alice.flow({
                    recipient: null,
                    flowRate: "0",
                })
            ).to.be.rejectedWith(/You must provide a recipient and flowRate/);
        });
        it("fail with undefined recipient", async () => {
            await expect(
                alice.flow({
                    flowRate: "0",
                })
            ).to.be.rejectedWith(/You must provide a recipient and flowRate/);
        });
        it("fail with empty string recipient", async () => {
            await expect(
                alice.flow({
                    recipient: "",
                    flowRate: "0",
                })
            ).to.be.rejectedWith(/You must provide a recipient and flowRate/);
        });
        it("fail with null flowRate", async () => {
            // Using https://github.com/domenic/chai-as-promised
            await expect(
                alice.flow({
                    recipient: adminAddress,
                    flowRate: null,
                })
            ).to.be.rejectedWith(/You must provide a recipient and flowRate/);
        });
        it("fail with undefined flowRate", async () => {
            // Using https://github.com/domenic/chai-as-promised
            await expect(
                alice.flow({
                    recipient: adminAddress,
                })
            ).to.be.rejectedWith(/You must provide a recipient and flowRate/);
        });
        it("fail with a number flowRate", async () => {
            // Using https://github.com/domenic/chai-as-promised
            await expect(
                alice.flow({
                    recipient: adminAddress,
                    flowRate: 0,
                })
            ).to.be.rejectedWith(/You must provide flowRate as a string/);
        });
        it("create a new flow", async () => {
            const tx = await alice.flow({
                recipient: bob.address,
                flowRate: "38580246913580", // 100 / mo
            });
            // validate flow data
            const flow = await sf.cfa.getFlow({
                superToken: superToken.address,
                sender: alice.address,
                receiver: bob.address,
            });
            const block = await web3.eth.getBlock(tx.receipt.blockNumber);
            assert.equal(flow.timestamp.getTime(), block.timestamp * 1000);
            assert.equal(flow.flowRate, "38580246913580");
            assert.notEqual(flow.deposit, "0");
            assert.equal(flow.owedDeposit, "0");
            // validate account net flows
            assert.equal(
                (
                    await sf.cfa.getNetFlow({
                        superToken: superToken.address,
                        account: alice.address,
                    })
                ).toString(),
                "-38580246913580"
            );
            assert.equal(
                (
                    await sf.cfa.getNetFlow({
                        superToken: superToken.address,
                        account: bob.address,
                    })
                ).toString(),
                "38580246913580"
            );
        });
        it("create a new flow with onTransaction", async () => {
            let txHash;
            const tx = await alice.flow({
                recipient: bob.address,
                flowRate: "38580246913580", // 100 / mo
                onTransaction: (hash) => {
                    txHash = hash;
                },
            });
            assert.equal(txHash, tx.receipt.transactionHash);
        });
        it("create a new flow with User object argument", async () => {
            const tx = await alice.flow({
                // "bob" rather than "bob.address"
                recipient: bob,
                flowRate: "38580246913580", // 100 / mo
            });
            const flow = await sf.cfa.getFlow({
                superToken: superToken.address,
                sender: alice.address,
                receiver: bob.address,
            });
            const block = await web3.eth.getBlock(tx.receipt.blockNumber);
            assert.equal(flow.timestamp.getTime(), block.timestamp * 1000);
            assert.equal(flow.flowRate, "38580246913580");
        });
    });
    describe("existing flows", () => {
        beforeEach(async () => {
            const tx = await alice.flow({
                recipient: bob.address,
                flowRate: "38580246913580", // 100 / mo
            });
            const flow = await sf.cfa.getFlow({
                superToken: superToken.address,
                sender: alice.address,
                receiver: bob.address,
            });
            const block = await web3.eth.getBlock(tx.receipt.blockNumber);
            assert.equal(flow.timestamp.getTime(), block.timestamp * 1000);
            assert.equal(flow.flowRate, "38580246913580");
        });
        it("modify an existing flow", async () => {
            const tx = await alice.flow({
                recipient: bob.address,
                flowRate: "19290123456790", // 50 / mo
            });

            const flow = await sf.cfa.getFlow({
                superToken: superToken.address,
                sender: alice.address,
                receiver: bob.address,
            });
            const block = await web3.eth.getBlock(tx.receipt.blockNumber);
            assert.equal(flow.timestamp.getTime(), block.timestamp * 1000);
            assert.equal(flow.flowRate, "19290123456790");
        });
        it("modify an existing flow with onTransaction", async () => {
            let txHash;
            const tx = await alice.flow({
                recipient: bob.address,
                flowRate: "19290123456790", // 100 / mo
                onTransaction: (hash) => {
                    txHash = hash;
                },
            });
            assert.equal(txHash, tx.receipt.transactionHash);
        });
        it("stop an existing flow", async () => {
            const ethBefore = await web3.eth.getBalance(alice.address);
            await alice.flow({
                recipient: bob.address,
                flowRate: "0", // 0 / mo
            });
            const ethAfter = await web3.eth.getBalance(alice.address);
            assert.isTrue(toBN(ethAfter).lt(toBN(ethBefore)));
            assert.equal(
                (
                    await sf.cfa.getNetFlow({
                        superToken: superToken.address,
                        account: alice.address,
                    })
                ).toString(),
                "0"
            );
            assert.equal(
                (
                    await sf.cfa.getNetFlow({
                        superToken: superToken.address,
                        account: bob.address,
                    })
                ).toString(),
                "0"
            );
        });
        it("stop an existing flow with onTransaction", async () => {
            let txHash;
            const tx = await alice.flow({
                recipient: bob.address,
                flowRate: "0", // 100 / mo
                onTransaction: (hash) => {
                    txHash = hash;
                },
            });
            assert.equal(txHash, tx.receipt.transactionHash);
        });
    });
});
