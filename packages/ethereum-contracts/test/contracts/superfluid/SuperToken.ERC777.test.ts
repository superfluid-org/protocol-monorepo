import {assert, expect} from "chai";
import {ethers} from "hardhat";

import {IERC1820Registry, SuperTokenMock} from "../../../typechain-types";
import TestEnvironment from "../../TestEnvironment";
import {expectEvent} from "../../utils/expectEvent";
import {expectCustomError, expectRevertedWith} from "../../utils/expectRevert";
import {keccak256, toWad} from "../utils/helpers";

import {
    shouldBehaveLikeERC777DirectSendBurn,
    shouldBehaveLikeERC777OperatorSendBurn,
    shouldBehaveLikeERC777SendBurnMintInternalWithReceiveHook,
    shouldBehaveLikeERC777SendBurnWithSendHook,
    shouldBehaveLikeERC777UnauthorizedOperatorSendBurn,
} from "./ERC777.behavior";

describe("SuperToken's ERC777 implementation", function () {
    this.timeout(300e3);
    const t = TestEnvironment.getSingleton();

    const {ZERO_ADDRESS} = t.constants;
    const initialSupply = toWad(50);
    const testData = keccak256("OZ777TestData");
    const operatorData = keccak256("OZ777TestOperatorData");

    let holder: string,
        defaultOperatorA: string,
        defaultOperatorB: string,
        newOperator: string,
        anyone: string;
    let erc1820: IERC1820Registry;
    let tokenContract: SuperTokenMock;

    async function newERC777SenderRecipientMock() {
        const factory = await ethers.getContractFactory(
            "ERC777SenderRecipientMock"
        );
        const mock = await factory.deploy();
        await mock.deployed();
        return mock;
    }

    before(async function () {
        await t.beforeTestSuite({
            nAccounts: 6,
        });

        ({
            alice: holder,
            bob: defaultOperatorA,
            carol: defaultOperatorB,
            dan: newOperator,
            eve: anyone,
        } = t.aliases);
        this.token = t.tokens.SuperToken;
        tokenContract = t.tokens.SuperToken;
        ({erc1820} = t.contracts);

        const holderSigner = await ethers.getSigner(holder);
        await this.token.connect(holderSigner).upgrade(initialSupply);
        await t.pushEvmSnapshot();
        this.testenv = t;
    });

    after(async function () {
        await t.popEvmSnapshot();
    });

    beforeEach(async function () {
        await t.beforeEachTestCase();
        t.beforeEachTestCaseBenchmark(this);
    });

    afterEach(async () => {
        t.afterEachTestCaseBenchmark();
    });

    context("with default operators", async () => {
        let defaultOperators: string[];

        before(() => {
            defaultOperators = [defaultOperatorA, defaultOperatorB];
        });

        beforeEach(async function () {
            await this.token.setupDefaultOperators(defaultOperators);
        });

        describe("basic information", function () {
            it("returns the name", async function () {
                expect(await this.token.name()).to.equal(
                    "Super TEST Fake Token"
                );
            });

            it("returns the symbol", async function () {
                expect(await this.token.symbol()).to.equal("TESTx");
            });

            it("returns decimals (non-ERC777 standard)", async function () {
                assert.equal(await this.token.decimals(), 18);
            });

            it("returns a granularity of 1", async function () {
                expect(await this.token.granularity()).to.equal("1");
            });

            it("returns the default operators", async function () {
                expect(await this.token.defaultOperators()).to.deep.equal(
                    defaultOperators
                );
            });

            it("default operators are operators for all accounts", async function () {
                for (const operator of defaultOperators) {
                    expect(
                        await this.token.isOperatorFor(operator, anyone)
                    ).to.equal(true);
                }
            });

            it("returns the total supply", async function () {
                expect(await this.token.totalSupply()).to.equal(initialSupply);
            });

            it("returns 18 when decimals is called", async function () {
                expect((await this.token.decimals()).toString()).to.equal("18");
            });

            it("the ERC777Token interface is registered in the registry", async function () {
                expect(
                    await erc1820.getInterfaceImplementer(
                        this.token.address,
                        keccak256("ERC777Token")
                    )
                ).to.equal(this.token.address);
            });

            it("the ERC20Token interface is registered in the registry", async function () {
                expect(
                    await erc1820.getInterfaceImplementer(
                        this.token.address,
                        keccak256("ERC20Token")
                    )
                ).to.equal(this.token.address);
            });
        });

        // it("does not emit AuthorizedOperator events for default operators", async function () {
        //     await expectEvent.notEmitted.inConstruction(this.token, "AuthorizedOperator");
        // });

        context(
            "with no ERC777TokensSender and no ERC777TokensRecipient implementers",
            function () {
                describe("send/burn", function () {
                    context("direct operations", function () {
                        shouldBehaveLikeERC777DirectSendBurn(
                            () => ({
                                holder,
                                recipient: anyone,
                            }),
                            testData
                        );
                    });

                    context("with self operator", function () {
                        shouldBehaveLikeERC777OperatorSendBurn(
                            () => ({
                                holder,
                                recipient: anyone,
                                operator: holder,
                            }),
                            testData,
                            operatorData
                        );
                    });

                    context("with first default operator", function () {
                        shouldBehaveLikeERC777OperatorSendBurn(
                            () => ({
                                holder,
                                recipient: anyone,
                                operator: defaultOperatorA,
                            }),
                            testData,
                            operatorData,
                            true
                        );
                    });

                    context("with second default operator", function () {
                        shouldBehaveLikeERC777OperatorSendBurn(
                            () => ({
                                holder,
                                recipient: anyone,
                                operator: defaultOperatorB,
                            }),
                            testData,
                            operatorData,
                            true
                        );
                    });

                    context("before authorizing a new operator", function () {
                        shouldBehaveLikeERC777UnauthorizedOperatorSendBurn(
                            () => ({
                                holder,
                                recipient: anyone,
                                operator: newOperator,
                            }),
                            testData,
                            operatorData
                        );
                    });

                    context("with new authorized operator", function () {
                        beforeEach(async function () {
                            await tokenContract
                                .connect(await ethers.getSigner(holder))
                                .authorizeOperator(newOperator);
                        });

                        shouldBehaveLikeERC777OperatorSendBurn(
                            () => ({
                                holder,
                                recipient: anyone,
                                operator: newOperator,
                            }),
                            testData,
                            operatorData
                        );

                        context("with revoked operator", function () {
                            beforeEach(async function () {
                                await tokenContract
                                    .connect(await ethers.getSigner(holder))
                                    .revokeOperator(newOperator);
                            });

                            shouldBehaveLikeERC777UnauthorizedOperatorSendBurn(
                                () => ({
                                    holder,
                                    recipient: anyone,
                                    operator: newOperator,
                                }),
                                testData,
                                operatorData
                            );
                        });
                    });
                });
            }
        );

        describe("operator management", function () {
            it("accounts are their own operator", async function () {
                expect(await this.token.isOperatorFor(holder, holder)).to.equal(
                    true
                );
            });

            it("reverts when self-authorizing", async function () {
                const holderSigner = await ethers.getSigner(holder);
                await expectRevertedWith(
                    tokenContract
                        .connect(holderSigner)
                        .authorizeOperator(holder),
                    "ERC777Operators: authorizing self as operator"
                );
            });

            it("reverts when self-revoking", async function () {
                const holderSigner = await ethers.getSigner(holder);
                await expectRevertedWith(
                    tokenContract.connect(holderSigner).revokeOperator(holder),
                    "ERC777Operators: revoking self as operator"
                );
            });

            it("non-operators can be revoked", async function () {
                expect(
                    await this.token.isOperatorFor(newOperator, holder)
                ).to.equal(false);

                const tx = await tokenContract
                    .connect(await ethers.getSigner(holder))
                    .revokeOperator(newOperator);
                await expectEvent(tx, tokenContract, "RevokedOperator", {
                    operator: newOperator,
                    tokenHolder: holder,
                });

                expect(
                    await this.token.isOperatorFor(newOperator, holder)
                ).to.equal(false);
            });

            it("non-operators can be authorized", async function () {
                expect(
                    await this.token.isOperatorFor(newOperator, holder)
                ).to.equal(false);

                const tx = await tokenContract
                    .connect(await ethers.getSigner(holder))
                    .authorizeOperator(newOperator);
                await expectEvent(tx, tokenContract, "AuthorizedOperator", {
                    operator: newOperator,
                    tokenHolder: holder,
                });

                expect(
                    await this.token.isOperatorFor(newOperator, holder)
                ).to.equal(true);
            });

            describe("new operators", function () {
                beforeEach(async function () {
                    await tokenContract
                        .connect(await ethers.getSigner(holder))
                        .authorizeOperator(newOperator);
                });

                it("are not added to the default operators list", async function () {
                    expect(await this.token.defaultOperators()).to.deep.equal(
                        defaultOperators
                    );
                });

                it("can be re-authorized", async function () {
                    const tx = await tokenContract
                        .connect(await ethers.getSigner(holder))
                        .authorizeOperator(newOperator);
                    await expectEvent(tx, tokenContract, "AuthorizedOperator", {
                        operator: newOperator,
                        tokenHolder: holder,
                    });

                    expect(
                        await this.token.isOperatorFor(newOperator, holder)
                    ).to.equal(true);
                });

                it("can be revoked", async function () {
                    const tx = await tokenContract
                        .connect(await ethers.getSigner(holder))
                        .revokeOperator(newOperator);
                    await expectEvent(tx, tokenContract, "RevokedOperator", {
                        operator: newOperator,
                        tokenHolder: holder,
                    });

                    expect(
                        await this.token.isOperatorFor(newOperator, holder)
                    ).to.equal(false);
                });
            });

            describe("default operators", function () {
                it("can be re-authorized", async function () {
                    const tx = await tokenContract
                        .connect(await ethers.getSigner(holder))
                        .authorizeOperator(defaultOperatorA);
                    await expectEvent(tx, tokenContract, "AuthorizedOperator", {
                        operator: defaultOperatorA,
                        tokenHolder: holder,
                    });

                    expect(
                        await this.token.isOperatorFor(defaultOperatorA, holder)
                    ).to.equal(true);
                });

                it("can be revoked", async function () {
                    const tx = await tokenContract
                        .connect(await ethers.getSigner(holder))
                        .revokeOperator(defaultOperatorA);
                    await expectEvent(tx, tokenContract, "RevokedOperator", {
                        operator: defaultOperatorA,
                        tokenHolder: holder,
                    });

                    expect(
                        await this.token.isOperatorFor(defaultOperatorA, holder)
                    ).to.equal(false);
                });

                it("cannot be revoked for themselves", async function () {
                    await expectRevertedWith(
                        tokenContract
                            .connect(await ethers.getSigner(defaultOperatorA))
                            .revokeOperator(defaultOperatorA),
                        "ERC777Operators: revoking self as operator"
                    );
                });

                context("with revoked default operator", function () {
                    beforeEach(async function () {
                        await tokenContract
                            .connect(await ethers.getSigner(holder))
                            .revokeOperator(defaultOperatorA);
                    });

                    it("default operator is not revoked for other holders", async function () {
                        expect(
                            await this.token.isOperatorFor(
                                defaultOperatorA,
                                anyone
                            )
                        ).to.equal(true);
                    });

                    it("other default operators are not revoked", async function () {
                        expect(
                            await this.token.isOperatorFor(
                                defaultOperatorB,
                                holder
                            )
                        ).to.equal(true);
                    });

                    it("default operators list is not modified", async function () {
                        expect(
                            await this.token.defaultOperators()
                        ).to.deep.equal(defaultOperators);
                    });

                    it("revoked default operator can be re-authorized", async function () {
                        const tx = await tokenContract
                            .connect(await ethers.getSigner(holder))
                            .authorizeOperator(defaultOperatorA);
                        await expectEvent(
                            tx,
                            tokenContract,
                            "AuthorizedOperator",
                            {
                                operator: defaultOperatorA,
                                tokenHolder: holder,
                            }
                        );

                        expect(
                            await this.token.isOperatorFor(
                                defaultOperatorA,
                                holder
                            )
                        ).to.equal(true);
                    });
                });
            });
        });

        describe("send and receive hooks", function () {
            const amount = toWad(1).toString();
            let sender: string, operator: string;

            before(function () {
                sender = holder;
                operator = defaultOperatorA;
            });

            describe("tokensReceived", function () {
                describe("with no ERC777TokensRecipient implementer", function () {
                    describe("with contract recipient", function () {
                        let recipient: string;

                        beforeEach(async function () {
                            this.tokensRecipientImplementer =
                                await newERC777SenderRecipientMock();
                            recipient = this.tokensRecipientImplementer.address;
                        });

                        it("send reverts", async function () {
                            const holderSigner = await ethers.getSigner(holder);
                            await expectCustomError(
                                tokenContract
                                    .connect(holderSigner)
                                    .send(
                                        recipient,
                                        amount.toString(),
                                        testData
                                    ),
                                tokenContract,
                                "SUPER_TOKEN_NOT_ERC777_TOKENS_RECIPIENT"
                            );
                        });

                        it("operatorSend reverts", async function () {
                            const operatorSigner =
                                await ethers.getSigner(operator);
                            await expectCustomError(
                                tokenContract
                                    .connect(operatorSigner)
                                    .operatorSend(
                                        sender,
                                        recipient,
                                        amount.toString(),
                                        testData,
                                        operatorData
                                    ),
                                tokenContract,
                                "SUPER_TOKEN_NOT_ERC777_TOKENS_RECIPIENT"
                            );
                        });

                        it("mint (internal) reverts", async function () {
                            const operatorSigner =
                                await ethers.getSigner(operator);
                            await expectCustomError(
                                tokenContract
                                    .connect(operatorSigner)
                                    .mintInternal(
                                        recipient,
                                        amount.toString(),
                                        testData,
                                        operatorData
                                    ),
                                tokenContract,
                                "SUPER_TOKEN_NOT_ERC777_TOKENS_RECIPIENT"
                            );
                        });

                        it("mint (internal) to zero address reverts", async function () {
                            const operatorSigner =
                                await ethers.getSigner(operator);
                            await expectCustomError(
                                tokenContract
                                    .connect(operatorSigner)
                                    .mintInternal(
                                        ZERO_ADDRESS,
                                        amount.toString(),
                                        testData,
                                        operatorData
                                    ),
                                tokenContract,
                                "SUPER_TOKEN_MINT_TO_ZERO_ADDRESS"
                            );
                        });

                        it("(ERC20) transfer succeeds", async function () {
                            await tokenContract
                                .connect(await ethers.getSigner(holder))
                                .upgrade(toWad(2));
                            await tokenContract
                                .connect(await ethers.getSigner(holder))
                                .transfer(recipient, amount);
                        });

                        it("(ERC20) transferFrom succeeds", async function () {
                            await tokenContract
                                .connect(await ethers.getSigner(holder))
                                .upgrade(toWad(2));
                            const approved = anyone;
                            await tokenContract
                                .connect(await ethers.getSigner(sender))
                                .approve(approved, amount);
                            await tokenContract
                                .connect(await ethers.getSigner(approved))
                                .transferFrom(sender, recipient, amount);
                        });
                    });
                });

                describe("with ERC777TokensRecipient implementer", function () {
                    describe("with contract as implementer for an externally owned account", function () {
                        let recipient: string;

                        beforeEach(async function () {
                            recipient = anyone;

                            this.tokensRecipientImplementer =
                                await newERC777SenderRecipientMock();

                            await this.tokensRecipientImplementer.recipientFor(
                                recipient
                            );

                            const signer = await ethers.getSigner(recipient);

                            await erc1820
                                .connect(signer)
                                .setInterfaceImplementer(
                                    recipient,
                                    keccak256("ERC777TokensRecipient"),
                                    this.tokensRecipientImplementer.address
                                );
                        });

                        shouldBehaveLikeERC777SendBurnMintInternalWithReceiveHook(
                            () => ({sender, recipient, operator}),
                            amount,
                            testData,
                            operatorData
                        );
                    });

                    describe("with contract as implementer for another contract", function () {
                        let recipient: string;

                        beforeEach(async function () {
                            this.recipientContract =
                                await newERC777SenderRecipientMock();
                            recipient = this.recipientContract.address;

                            this.tokensRecipientImplementer =
                                await newERC777SenderRecipientMock();
                            await this.tokensRecipientImplementer.recipientFor(
                                recipient
                            );
                            await this.recipientContract.registerRecipient(
                                this.tokensRecipientImplementer.address
                            );
                        });

                        shouldBehaveLikeERC777SendBurnMintInternalWithReceiveHook(
                            () => ({sender, recipient, operator}),
                            amount,
                            testData,
                            operatorData
                        );
                    });

                    describe("with contract as implementer for itself", function () {
                        let recipient: string;

                        beforeEach(async function () {
                            this.tokensRecipientImplementer =
                                await newERC777SenderRecipientMock();
                            recipient = this.tokensRecipientImplementer.address;

                            await this.tokensRecipientImplementer.recipientFor(
                                recipient
                            );
                        });

                        shouldBehaveLikeERC777SendBurnMintInternalWithReceiveHook(
                            () => ({sender, recipient, operator}),
                            amount,
                            testData,
                            operatorData
                        );
                    });
                });
            });

            describe("tokensToSend", function () {
                let recipient: string;

                before(() => {
                    recipient = anyone;
                });

                describe("with a contract as implementer for an externally owned account", function () {
                    beforeEach(async function () {
                        this.tokensSenderImplementer =
                            await newERC777SenderRecipientMock();

                        await this.tokensSenderImplementer.senderFor(sender);

                        const signer = await ethers.getSigner(sender);
                        await erc1820
                            .connect(signer)
                            .setInterfaceImplementer(
                                sender,
                                keccak256("ERC777TokensSender"),
                                this.tokensSenderImplementer.address
                            );
                    });

                    shouldBehaveLikeERC777SendBurnWithSendHook(
                        () => ({sender, recipient, operator}),
                        amount,
                        testData,
                        operatorData
                    );
                });

                describe("with contract as implementer for another contract", function () {
                    beforeEach(async function () {
                        this.senderContract =
                            await newERC777SenderRecipientMock();
                        sender = this.senderContract.address;

                        this.tokensSenderImplementer =
                            await newERC777SenderRecipientMock();
                        await this.tokensSenderImplementer.senderFor(sender);
                        await this.senderContract.registerSender(
                            this.tokensSenderImplementer.address
                        );
                        await this.senderContract.recipientFor(sender);
                        await tokenContract
                            .connect(await ethers.getSigner(holder))
                            .send(sender, amount, testData);
                    });

                    shouldBehaveLikeERC777SendBurnWithSendHook(
                        () => ({sender, recipient, operator}),
                        amount,
                        testData,
                        operatorData
                    );
                });

                describe("with a contract as implementer for itself", function () {
                    beforeEach(async function () {
                        this.tokensSenderImplementer =
                            await newERC777SenderRecipientMock();
                        sender = this.tokensSenderImplementer.address;

                        await this.tokensSenderImplementer.senderFor(sender);
                        await this.tokensSenderImplementer.recipientFor(sender);
                        await tokenContract
                            .connect(await ethers.getSigner(holder))
                            .send(sender, amount, testData);
                    });

                    shouldBehaveLikeERC777SendBurnWithSendHook(
                        () => ({sender, recipient, operator}),
                        amount,
                        testData,
                        operatorData
                    );
                });
            });
        });
    });

    context("with no default operators", function () {
        it("default operators list is empty", async function () {
            expect(await this.token.defaultOperators()).to.deep.equal([]);
        });
    });
});
