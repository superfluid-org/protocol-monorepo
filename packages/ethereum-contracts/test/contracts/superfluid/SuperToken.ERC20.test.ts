import {SignerWithAddress} from "@nomiclabs/hardhat-ethers/signers";
import {expect} from "chai";
import {BigNumber} from "ethers";
import {ethers} from "hardhat";

import TestEnvironment from "../../TestEnvironment";
import {expectCustomError} from "../../utils/expectRevert";
import {toBN} from "../utils/helpers";

import {
    shouldBehaveLikeERC20,
    shouldBehaveLikeERC20Approve,
    shouldBehaveLikeERC20Transfer,
} from "./ERC20.behavior";

describe("SuperToken's ERC20 compliance", function () {
    this.timeout(300e3);
    const t = TestEnvironment.getSingleton();
    const {ZERO_ADDRESS} = t.constants;
    const initialSupply = toBN(100);

    let alice: string, bob: string, carol: string;
    let aliceSigner: SignerWithAddress;

    before(async function () {
        await t.beforeTestSuite({
            nAccounts: 4,
        });

        ({alice, bob, carol} = t.aliases);
        aliceSigner = await ethers.getSigner(alice);

        this.token = t.tokens.SuperToken;
        await this.token.connect(aliceSigner).upgrade(initialSupply);

        await t.pushEvmSnapshot();
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

    describe("ERC20 compliance", () => {
        shouldBehaveLikeERC20("SuperToken", initialSupply, () => ({
            initialHolder: alice,
            recipient: bob,
            anotherAccount: carol,
        }));
    });

    describe("decrease allowance", function () {
        describe("when the spender is not the zero address", function () {
            let spender: string;

            before(() => {
                spender = bob;
            });

            function shouldDecreaseApproval(amount: BigNumber) {
                describe("when there was no approved amount before", function () {
                    it("reverts", async function () {
                        await expect(
                            this.token
                                .connect(aliceSigner)
                                .decreaseAllowance(spender, amount)
                        ).to.be.revertedWith(
                            "SuperToken: decreased allowance below zero"
                        );
                    });
                });

                describe("when the spender had an approved amount", function () {
                    const approvedAmount = amount;

                    beforeEach(async function () {
                        ({logs: this.logs} = await this.token
                            .connect(aliceSigner)
                            .approve(spender, approvedAmount));
                    });

                    it("emits an approval event", async function () {
                        await expect(
                            this.token
                                .connect(aliceSigner)
                                .decreaseAllowance(spender, approvedAmount)
                        )
                            .to.emit(this.token, "Approval")
                            .withArgs(alice, bob, toBN(0));
                    });

                    it("decreases the spender allowance subtracting the requested amount", async function () {
                        await this.token
                            .connect(aliceSigner)
                            .decreaseAllowance(spender, approvedAmount.sub(1));

                        expect(
                            await this.token.allowance(alice, spender)
                        ).to.equal(toBN(1));
                    });

                    it("sets the allowance to zero when all allowance is removed", async function () {
                        await this.token
                            .connect(aliceSigner)
                            .decreaseAllowance(spender, approvedAmount);
                        expect(
                            await this.token.allowance(alice, spender)
                        ).to.equal(toBN(0));
                    });

                    it("reverts when more than the full allowance is removed", async function () {
                        await expect(
                            this.token
                                .connect(aliceSigner)
                                .decreaseAllowance(
                                    spender,
                                    approvedAmount.add(1)
                                )
                        ).to.be.revertedWith(
                            "SuperToken: decreased allowance below zero"
                        );
                    });
                });
            }

            describe("when the sender has enough balance", function () {
                const amount = initialSupply;

                shouldDecreaseApproval(amount);
            });

            describe("when the sender does not have enough balance", function () {
                const amount = initialSupply.add(1);

                shouldDecreaseApproval(amount);
            });
        });

        describe("when the spender is the zero address", function () {
            const amount = initialSupply;
            const spender = ZERO_ADDRESS;

            it("reverts", async function () {
                await expect(
                    this.token
                        .connect(aliceSigner)
                        .decreaseAllowance(spender, amount)
                ).to.be.revertedWith(
                    "SuperToken: decreased allowance below zero"
                );
            });
        });
    });

    describe("increase allowance", function () {
        const amount = initialSupply;

        describe("when the spender is not the zero address", function () {
            let spender: string;
            before(() => {
                spender = bob;
            });
            describe("when the sender has enough balance", function () {
                it("emits an approval event", async function () {
                    await expect(
                        this.token
                            .connect(aliceSigner)
                            .increaseAllowance(spender, amount)
                    )
                        .to.emit(this.token, "Approval")
                        .withArgs(alice, spender, amount);
                });

                describe("when there was no approved amount before", function () {
                    it("approves the requested amount", async function () {
                        await this.token
                            .connect(aliceSigner)
                            .increaseAllowance(spender, amount);

                        expect(
                            await this.token.allowance(alice, spender)
                        ).to.equal(toBN(amount));
                    });
                });

                describe("when the spender had an approved amount", function () {
                    beforeEach(async function () {
                        await this.token
                            .connect(aliceSigner)
                            .approve(spender, toBN(1));
                    });

                    it("increases the spender allowance adding the requested amount", async function () {
                        await this.token
                            .connect(aliceSigner)
                            .increaseAllowance(spender, amount);

                        expect(
                            await this.token.allowance(alice, spender)
                        ).to.equal(toBN(amount.add(1)));
                    });
                });
            });

            describe("when the sender does not have enough balance", function () {
                const amount = initialSupply.add(1);

                it("emits an approval event", async function () {
                    await expect(
                        this.token
                            .connect(aliceSigner)
                            .increaseAllowance(spender, amount)
                    )
                        .to.emit(this.token, "Approval")
                        .withArgs(alice, spender, amount);
                });

                describe("when there was no approved amount before", function () {
                    it("approves the requested amount", async function () {
                        await this.token
                            .connect(aliceSigner)
                            .increaseAllowance(spender, amount);

                        expect(
                            await this.token.allowance(alice, spender)
                        ).to.equal(toBN(amount));
                    });
                });

                describe("when the spender had an approved amount", function () {
                    beforeEach(async function () {
                        await this.token
                            .connect(aliceSigner)
                            .approve(spender, toBN(1));
                    });

                    it("increases the spender allowance adding the requested amount", async function () {
                        await this.token
                            .connect(aliceSigner)
                            .increaseAllowance(spender, amount);

                        expect(
                            await this.token.allowance(alice, spender)
                        ).to.equal(toBN(amount.add(1)));
                    });
                });
            });
        });

        describe("when the spender is the zero address", function () {
            const spender = ZERO_ADDRESS;

            it("reverts", async function () {
                await expectCustomError(
                    this.token
                        .connect(aliceSigner)
                        .increaseAllowance(spender, amount),
                    this.token,
                    "SUPER_TOKEN_APPROVE_TO_ZERO_ADDRESS"
                );
            });
        });
    });

    describe("_transfer", function () {
        shouldBehaveLikeERC20Transfer(
            "ERC20",
            initialSupply,
            () => ({
                from: alice,
                to: bob,
            }),
            function (this: any, from: string, to: string, amount: BigNumber) {
                return this.token.transferInternal(from, to, amount);
            }
        );

        describe("when the sender is the zero address", function () {
            it("reverts", async function () {
                await expectCustomError(
                    this.token.transferInternal(
                        ZERO_ADDRESS,
                        bob,
                        initialSupply
                    ),
                    this.token,
                    "SUPER_TOKEN_TRANSFER_FROM_ZERO_ADDRESS"
                );
            });
        });
    });

    describe("_approve", function () {
        shouldBehaveLikeERC20Approve(
            "ERC20",
            initialSupply,
            () => ({
                owner: alice,
                spender: bob,
            }),
            function (
                this: any,
                owner: string,
                spender: string,
                amount: BigNumber
            ) {
                return this.token.approveInternal(owner, spender, amount);
            }
        );

        describe("when the owner is the zero address", function () {
            it("reverts", async function () {
                await expectCustomError(
                    this.token.approveInternal(
                        ZERO_ADDRESS,
                        bob,
                        initialSupply
                    ),
                    this.token,
                    "SUPER_TOKEN_APPROVE_FROM_ZERO_ADDRESS"
                );
            });
        });
    });
});
