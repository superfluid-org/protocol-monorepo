// NOTE: copied and modified from https://github.com/OpenZeppelin/openzeppelin-contracts/
import {SignerWithAddress} from "@nomiclabs/hardhat-ethers/signers";
import {BigNumber, BigNumberish, ContractTransaction} from "ethers";
import {ethers, expect} from "hardhat";

import {expectCustomError} from "../../utils/expectRevert";
import {toBN} from "../utils/helpers";

export function shouldBehaveLikeERC20(
    errorPrefix: string,
    initialSupply: BigNumber,
    setupAccounts: () => {
        initialHolder: string;
        recipient: string;
        anotherAccount: string;
    }
) {
    let initialHolder: string, recipient: string, anotherAccount: string;

    before(() => {
        ({initialHolder, recipient, anotherAccount} = setupAccounts());
    });

    describe("total supply", function () {
        it("returns the total amount of tokens", async function () {
            expect((await this.token.totalSupply()).toString()).to.be.equal(
                initialSupply.toString()
            );
        });
    });

    describe("balanceOf", function () {
        describe("when the requested account has no tokens", function () {
            it("returns zero", async function () {
                expect(
                    (await this.token.balanceOf(anotherAccount)).toString()
                ).to.be.equal("0");
            });
        });

        describe("when the requested account has some tokens", function () {
            it("returns the total amount of tokens", async function () {
                expect(
                    (await this.token.balanceOf(initialHolder)).toString()
                ).to.be.equal(initialSupply);
            });
        });
    });

    describe("transfer", function () {
        shouldBehaveLikeERC20Transfer(
            errorPrefix,
            initialSupply,
            () => ({
                from: initialHolder,
                to: recipient,
            }),
            async function (
                this: any,
                from: string,
                to: string,
                value: BigNumberish
            ) {
                const signer = await ethers.getSigner(from);
                return this.token.connect(signer).transfer(to, value);
            }
        );
    });

    describe("transfer from", function () {
        let spender: string, tokenOwner: string, to: string;
        let spenderSigner: SignerWithAddress,
            tokenOwnerSigner: SignerWithAddress;

        before(async () => {
            spender = recipient;
            tokenOwner = initialHolder;
            to = anotherAccount;
            spenderSigner = await ethers.getSigner(spender);
            tokenOwnerSigner = await ethers.getSigner(tokenOwner);
        });

        describe("when the token owner is not the zero address", function () {
            describe("when the recipient is not the zero address", function () {
                describe("when the spender has enough approved balance", function () {
                    beforeEach(async function () {
                        await this.token
                            .connect(tokenOwnerSigner)
                            .approve(spender, initialSupply);
                    });

                    describe("when the token owner has enough balance", function () {
                        const amount = initialSupply;

                        it("transfers the requested amount", async function () {
                            await this.token
                                .connect(spenderSigner)
                                .transferFrom(tokenOwner, to, amount);

                            expect(
                                (
                                    await this.token.balanceOf(tokenOwner)
                                ).toString()
                            ).to.be.equal("0");

                            expect(
                                (await this.token.balanceOf(to)).toString()
                            ).to.be.equal(amount);
                        });

                        it("decreases the spender allowance", async function () {
                            await this.token
                                .connect(spenderSigner)
                                .transferFrom(tokenOwner, to, amount);

                            expect(
                                (
                                    await this.token.allowance(
                                        tokenOwner,
                                        spender
                                    )
                                ).toString()
                            ).to.be.equal("0");
                        });

                        it("emits a transfer event", async function () {
                            await expect(
                                this.token
                                    .connect(spenderSigner)
                                    .transferFrom(tokenOwner, to, amount)
                            )
                                .to.emit(this.token, "Transfer")
                                .withArgs(tokenOwner, to, amount);
                        });
                    });

                    describe("when the token owner does not have enough balance", function () {
                        const amount = initialSupply.add(1);

                        it("reverts", async function () {
                            await expectCustomError(
                                this.token
                                    .connect(spenderSigner)
                                    .transferFrom(tokenOwner, to, amount),
                                this.token,
                                "SF_TOKEN_MOVE_INSUFFICIENT_BALANCE"
                            );
                        });
                    });
                });

                describe("when the spender does not have enough approved balance", function () {
                    beforeEach(async function () {
                        await this.token
                            .connect(tokenOwnerSigner)
                            .approve(spender, initialSupply.sub(1));
                    });

                    describe("when the token owner has enough balance", function () {
                        const amount = initialSupply;

                        it("reverts", async function () {
                            await expect(
                                this.token
                                    .connect(spenderSigner)
                                    .transferFrom(tokenOwner, to, amount)
                            ).to.be.revertedWith(
                                "SuperToken: transfer amount exceeds allowance"
                            );
                        });
                    });

                    describe("when the token owner does not have enough balance", function () {
                        const amount = initialSupply.add(1);

                        it("reverts", async function () {
                            await expectCustomError(
                                this.token
                                    .connect(spenderSigner)
                                    .transferFrom(tokenOwner, to, amount),
                                this.token,
                                "SF_TOKEN_MOVE_INSUFFICIENT_BALANCE"
                            );
                        });
                    });
                });
            });

            describe("when the recipient is the zero address", function () {
                const amount = initialSupply;
                const to = ethers.constants.AddressZero;

                beforeEach(async function () {
                    await this.token.approve(spender, amount);
                });

                it("reverts", async function () {
                    await expectCustomError(
                        this.token
                            .connect(spenderSigner)
                            .transferFrom(tokenOwner, to, amount),
                        this.token,
                        "SUPER_TOKEN_TRANSFER_TO_ZERO_ADDRESS"
                    );
                });
            });
        });

        describe("when the token owner is the zero address", function () {
            const amount = 0;
            const tokenOwner = ethers.constants.AddressZero;
            let to: string;

            before(() => {
                to = recipient;
            });

            it("reverts", async function () {
                await expectCustomError(
                    this.token
                        .connect(spenderSigner)
                        .transferFrom(tokenOwner, to, amount),
                    this.token,
                    "SUPER_TOKEN_TRANSFER_FROM_ZERO_ADDRESS"
                );
            });
        });
    });

    describe("approve", function () {
        shouldBehaveLikeERC20Approve(
            errorPrefix,
            initialSupply,
            () => ({
                owner: initialHolder,
                spender: recipient,
            }),
            async function (
                this: any,
                owner: string,
                spender: string,
                amount: BigNumberish
            ) {
                const signer = await ethers.getSigner(owner);
                return this.token.connect(signer).approve(spender, amount);
            }
        );
    });
}

export function shouldBehaveLikeERC20Transfer(
    _errorPrefix: string,
    balance: BigNumber,
    setupAccounts: () => {from: string; to: string},
    transfer: (
        this: any,
        from: string,
        to: string,
        amount: BigNumber
    ) => Promise<ContractTransaction>
) {
    let from: string, to: string;

    before(() => {
        ({from, to} = setupAccounts());
    });
    describe("when the recipient is not the zero address", function () {
        describe("when the sender does not have enough balance", function () {
            const amount = toBN(balance).add(1);

            it("reverts", async function () {
                await expectCustomError(
                    transfer.call(this, from, to, amount),
                    this.token,
                    "SF_TOKEN_MOVE_INSUFFICIENT_BALANCE"
                );
            });
        });

        describe("when the sender transfers all balance", function () {
            const amount = balance;

            it("transfers the requested amount", async function () {
                await transfer.call(this, from, to, amount);

                expect(
                    (await this.token.balanceOf(from)).toString()
                ).to.be.equal("0");

                expect((await this.token.balanceOf(to)).toString()).to.be.equal(
                    amount
                );
            });

            it("emits a transfer event", async function () {
                await expect(transfer.call(this, from, to, amount))
                    .to.emit(this.token, "Transfer")
                    .withArgs(from, to, amount.toString());
            });
        });

        describe("when the sender transfers zero tokens", function () {
            const amount = toBN("0");

            it("transfers the requested amount", async function () {
                await transfer.call(this, from, to, amount);

                expect((await this.token.balanceOf(from)).toString()).to.equal(
                    balance
                );

                expect((await this.token.balanceOf(to)).toString()).to.equal(
                    "0"
                );
            });

            it("emits a transfer event", async function () {
                await expect(transfer.call(this, from, to, amount))
                    .to.emit(this.token, "Transfer")
                    .withArgs(from, to, amount);
            });
        });
    });

    describe("when the recipient is the zero address", function () {
        it("reverts", async function () {
            await expectCustomError(
                transfer.call(
                    this,
                    from,
                    ethers.constants.AddressZero,
                    balance
                ),
                this.token,
                "SUPER_TOKEN_TRANSFER_TO_ZERO_ADDRESS"
            );
        });
    });
}

export function shouldBehaveLikeERC20Approve(
    errorPrefix: string,
    supply: BigNumber,
    setupAccounts: () => {owner: string; spender: string},
    approve: (
        this: any,
        owner: string,
        spender: string,
        amount: BigNumber
    ) => Promise<ContractTransaction>
) {
    let owner: string, spender: string;

    before(() => {
        ({owner, spender} = setupAccounts());
    });

    describe("when the spender is not the zero address", function () {
        describe("when the sender has enough balance", function () {
            const amount = supply;

            it("emits an approval event", async function () {
                await expect(approve.call(this, owner, spender, amount))
                    .to.emit(this.token, "Approval")
                    .withArgs(owner, spender, amount);
            });

            describe("when there was no approved amount before", function () {
                it("approves the requested amount", async function () {
                    await approve.call(this, owner, spender, amount);

                    expect(
                        (await this.token.allowance(owner, spender)).toString()
                    ).to.equal(amount);
                });
            });

            describe("when the spender had an approved amount", function () {
                beforeEach(async function () {
                    await approve.call(this, owner, spender, toBN(1));
                });

                it("approves the requested amount and replaces the previous one", async function () {
                    await approve.call(this, owner, spender, amount);

                    expect(
                        (await this.token.allowance(owner, spender)).toString()
                    ).to.equal(amount);
                });
            });
        });

        describe("when the sender does not have enough balance", function () {
            const amount = supply.add(1);

            it("emits an approval event", async function () {
                await expect(approve.call(this, owner, spender, amount))
                    .to.emit(this.token, "Approval")
                    .withArgs(owner, spender, amount);
            });

            describe("when there was no approved amount before", function () {
                it("approves the requested amount", async function () {
                    await approve.call(this, owner, spender, amount);

                    expect(
                        (await this.token.allowance(owner, spender)).toString()
                    ).to.equal(amount);
                });
            });

            describe("when the spender had an approved amount", function () {
                beforeEach(async function () {
                    await approve.call(this, owner, spender, toBN(1));
                });

                it("approves the requested amount and replaces the previous one", async function () {
                    await approve.call(this, owner, spender, amount);

                    expect(
                        (await this.token.allowance(owner, spender)).toString()
                    ).to.equal(amount);
                });
            });
        });
    });

    describe("when the spender is the zero address", function () {
        it("reverts", async function () {
            await expectCustomError(
                approve.call(this, owner, ethers.constants.AddressZero, supply),
                this.token,
                "SUPER_TOKEN_APPROVE_TO_ZERO_ADDRESS"
            );
        });
    });
}
