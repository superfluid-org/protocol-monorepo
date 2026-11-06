import {SignerWithAddress} from "@nomiclabs/hardhat-ethers/signers";
import {expect} from "chai";
import {BigNumber, ContractTransaction} from "ethers";
import {ethers} from "hardhat";

import {
    ERC777SenderRecipientMock,
    SuperTokenMock,
} from "../../../typechain-types";
import {expectEvent} from "../../utils/expectEvent";
import {expectCustomError, expectRevertedWith} from "../../utils/expectRevert";

// NOTE: copied and modified from https://github.com/OpenZeppelin/openzeppelin-contracts/
const ZERO_ADDRESS = ethers.constants.AddressZero;

export function shouldBehaveLikeERC777DirectSendBurn(
    setupAccounts: () => {holder: string; recipient: string},
    data: string
) {
    _shouldBehaveLikeERC777DirectSend(setupAccounts, data);
    _shouldBehaveLikeERC777DirectBurn(setupAccounts, data);
}

export function shouldBehaveLikeERC777OperatorSendBurn(
    setupAccounts: () => {holder: string; recipient: string; operator: string},
    data: string,
    operatorData: string,
    isDefaultOperator?: boolean
) {
    _shouldBehaveLikeERC777OperatorSend(
        setupAccounts,
        data,
        operatorData,
        isDefaultOperator
    );
    _shouldBehaveLikeERC777OperatorBurn(
        setupAccounts,
        data,
        operatorData,
        isDefaultOperator
    );
}

export function shouldBehaveLikeERC777UnauthorizedOperatorSendBurn(
    setupAccounts: () => {holder: string; recipient: string; operator: string},
    data: string,
    operatorData: string
) {
    _shouldBehaveLikeERC777UnauthorizedOperatorSend(
        setupAccounts,
        data,
        operatorData
    );
    _shouldBehaveLikeERC777UnauthorizedOperatorBurn(
        setupAccounts,
        data,
        operatorData
    );
}

function _shouldBehaveLikeERC777DirectSend(
    setupAccounts: () => {holder: string; recipient: string},
    data: string
) {
    let holder: string, recipient: string;
    let holderSigner: SignerWithAddress;
    let tokenContract: SuperTokenMock;

    before(async function () {
        ({holder, recipient} = setupAccounts());
        holderSigner = await ethers.getSigner(holder);
        tokenContract = await ethers.getContractAt(
            "SuperTokenMock",
            this.token.address
        );
    });

    describe("direct send", function () {
        describe("when the sender has tokens", function () {
            _shouldDirectSendTokens(
                () => ({
                    from: holder,
                    to: recipient,
                }),
                "0",
                data
            );
            _shouldDirectSendTokens(
                () => ({
                    from: holder,
                    to: recipient,
                }),
                "1",
                data
            );

            it("reverts when sending more than the balance", async function () {
                const balance = await this.token.balanceOf(holder);
                await expectCustomError(
                    tokenContract
                        .connect(holderSigner)
                        .send(
                            recipient,
                            BigNumber.from(balance.toString())
                                .add(1)
                                .toString(),
                            data
                        ),
                    tokenContract,
                    "SF_TOKEN_MOVE_INSUFFICIENT_BALANCE"
                );
            });

            it("reverts when sending to the zero address", async function () {
                await expectCustomError(
                    tokenContract
                        .connect(holderSigner)
                        .send(ZERO_ADDRESS, "1", data),
                    tokenContract,
                    "SUPER_TOKEN_TRANSFER_TO_ZERO_ADDRESS"
                );
            });
        });

        describe("when the sender has no tokens", function () {
            beforeEach(async function () {
                await _removeBalance(this.token, holder);
            });

            _shouldDirectSendTokens(
                () => ({
                    from: holder,
                    to: recipient,
                }),
                "0",
                data
            );

            it("reverts when sending a non-zero amount", async function () {
                await expectCustomError(
                    tokenContract
                        .connect(holderSigner)
                        .send(recipient, "1", data),
                    tokenContract,
                    "SF_TOKEN_MOVE_INSUFFICIENT_BALANCE"
                );
            });
        });
    });
}

function _shouldBehaveLikeERC777OperatorSend(
    setupAccounts: () => {holder: string; recipient: string; operator: string},
    data: string,
    operatorData: string,
    isDefaultOperator?: boolean
) {
    let holder: string, recipient: string, operator: string;
    let tokenContract: SuperTokenMock;

    before(async function () {
        ({holder, recipient, operator} = setupAccounts());
        tokenContract = await ethers.getContractAt(
            "SuperTokenMock",
            this.token.address
        );
    });

    describe("operator send", function () {
        describe("when the sender has tokens", async function () {
            _shouldOperatorSendTokens(
                () => ({
                    from: holder,
                    operator: operator,
                    to: recipient,
                }),
                "0",
                data,
                operatorData
            );
            _shouldOperatorSendTokens(
                () => ({
                    from: holder,
                    operator: operator,
                    to: recipient,
                }),
                "1",
                data,
                operatorData
            );

            it("reverts when sending more than the balance", async function () {
                const operatorSigner = await ethers.getSigner(operator);
                const balance = await this.token.balanceOf(holder);
                await expectCustomError(
                    tokenContract
                        .connect(operatorSigner)
                        .operatorSend(
                            holder,
                            recipient,
                            BigNumber.from(balance.toString())
                                .add(1)
                                .toString(),
                            data,
                            operatorData
                        ),
                    tokenContract,
                    "SF_TOKEN_MOVE_INSUFFICIENT_BALANCE"
                );
            });

            it("reverts when sending to the zero address", async function () {
                const operatorSigner = await ethers.getSigner(operator);
                await expectCustomError(
                    tokenContract
                        .connect(operatorSigner)
                        .operatorSend(
                            holder,
                            ZERO_ADDRESS,
                            "1",
                            data,
                            operatorData
                        ),
                    tokenContract,
                    "SUPER_TOKEN_TRANSFER_TO_ZERO_ADDRESS"
                );
            });
        });

        describe("when the sender has no tokens", function () {
            beforeEach(async function () {
                await _removeBalance(this.token, holder);
            });

            _shouldOperatorSendTokens(
                () => ({
                    from: holder,
                    operator: operator,
                    to: recipient,
                }),
                "0",
                data,
                operatorData
            );

            it("reverts when sending a non-zero amount", async function () {
                const operatorSigner = await ethers.getSigner(operator);
                await expectCustomError(
                    tokenContract
                        .connect(operatorSigner)
                        .operatorSend(
                            holder,
                            recipient,
                            "1",
                            data,
                            operatorData
                        ),
                    tokenContract,
                    "SF_TOKEN_MOVE_INSUFFICIENT_BALANCE"
                );
            });

            it("reverts when sending from the zero address", async function () {
                const operatorSigner = await ethers.getSigner(operator);
                // This is not yet reflected in the spec
                await expectCustomError(
                    tokenContract
                        .connect(operatorSigner)
                        .operatorSend(
                            ZERO_ADDRESS,
                            recipient,
                            "0",
                            data,
                            operatorData
                        ),
                    tokenContract,
                    isDefaultOperator
                        ? "SUPER_TOKEN_TRANSFER_FROM_ZERO_ADDRESS"
                        : "SUPER_TOKEN_CALLER_IS_NOT_OPERATOR_FOR_HOLDER"
                );
            });
        });
    });
}

function _shouldBehaveLikeERC777UnauthorizedOperatorSend(
    setupAccounts: () => {holder: string; recipient: string; operator: string},
    data: string,
    operatorData: string
) {
    let holder: string, recipient: string, operator: string;

    before(function () {
        ({holder, recipient, operator} = setupAccounts());
    });

    describe("operator send", function () {
        it("reverts", async function () {
            const operatorSigner = await ethers.getSigner(operator);
            const tokenContract = await ethers.getContractAt(
                "SuperTokenMock",
                this.token.address
            );
            await expectCustomError(
                tokenContract
                    .connect(operatorSigner)
                    .operatorSend(holder, recipient, "0", data, operatorData),
                tokenContract,
                "SUPER_TOKEN_CALLER_IS_NOT_OPERATOR_FOR_HOLDER"
            );
        });
    });
}

function _shouldBehaveLikeERC777DirectBurn(
    setupAccounts: () => {holder: string; recipient: string},
    data: string
) {
    let holder: string;

    before(function () {
        ({holder} = setupAccounts());
    });

    describe("direct burn", function () {
        describe("when the sender has tokens", function () {
            _shouldDirectBurnTokens(
                () => ({
                    from: holder,
                }),
                "0",
                data
            );
            _shouldDirectBurnTokens(
                () => ({
                    from: holder,
                }),
                "1",
                data
            );

            it("reverts when burning more than the balance", async function () {
                const balance = await this.token.balanceOf(holder);
                const holderSigner = await ethers.getSigner(holder);

                const tokenContract = await ethers.getContractAt(
                    "SuperTokenMock",
                    this.token.address
                );
                await expectCustomError(
                    tokenContract
                        .connect(holderSigner)
                        .burn(
                            BigNumber.from(balance.toString())
                                .add(1)
                                .toString(),
                            data
                        ),
                    tokenContract,
                    "SF_TOKEN_BURN_INSUFFICIENT_BALANCE"
                );
            });
        });

        describe("when the sender has no tokens", function () {
            beforeEach(async function () {
                await _removeBalance(this.token, holder);
            });

            _shouldDirectBurnTokens(
                () => ({
                    from: holder,
                }),
                "0",
                data
            );

            it("reverts when burning a non-zero amount", async function () {
                const holderSigner = await ethers.getSigner(holder);
                const tokenContract = await ethers.getContractAt(
                    "SuperTokenMock",
                    this.token.address
                );
                await expectCustomError(
                    tokenContract.connect(holderSigner).burn("1", data),
                    tokenContract,
                    "SF_TOKEN_BURN_INSUFFICIENT_BALANCE"
                );
            });
        });
    });
}

function _shouldBehaveLikeERC777OperatorBurn(
    setupAccounts: () => {holder: string; recipient: string; operator: string},
    data: string,
    operatorData: string,
    isDefaultOperator?: boolean
) {
    let holder: string, operator: string;

    before(function () {
        ({holder, operator} = setupAccounts());
    });

    describe("operator burn", function () {
        describe("when the sender has tokens", async function () {
            _shouldOperatorBurnTokens(
                () => ({
                    from: holder,
                    operator,
                }),
                "0",
                data,
                operatorData
            );
            _shouldOperatorBurnTokens(
                () => ({
                    from: holder,
                    operator,
                }),
                "1",
                data,
                operatorData
            );

            it("reverts when burning more than the balance", async function () {
                const balance = await this.token.balanceOf(holder);
                const operatorSigner = await ethers.getSigner(operator);
                const tokenContract = await ethers.getContractAt(
                    "SuperTokenMock",
                    this.token.address
                );
                await expectCustomError(
                    tokenContract
                        .connect(operatorSigner)
                        .operatorBurn(
                            holder,
                            BigNumber.from(balance.toString())
                                .add(1)
                                .toString(),
                            data,
                            operatorData
                        ),
                    tokenContract,
                    "SF_TOKEN_BURN_INSUFFICIENT_BALANCE"
                );
            });
        });

        describe("when the sender has no tokens", function () {
            beforeEach(async function () {
                await _removeBalance(this.token, holder);
            });

            _shouldOperatorBurnTokens(
                () => ({
                    from: holder,
                    operator,
                }),
                "0",
                data,
                operatorData
            );

            it("reverts when burning a non-zero amount", async function () {
                const tokenContract = await ethers.getContractAt(
                    "SuperTokenMock",
                    this.token.address
                );
                const operatorSigner = await ethers.getSigner(operator);
                await expectCustomError(
                    tokenContract
                        .connect(operatorSigner)
                        .operatorBurn(holder, "1", data, operatorData),
                    tokenContract,
                    "SF_TOKEN_BURN_INSUFFICIENT_BALANCE"
                );
            });

            it("reverts when burning from the zero address", async function () {
                const tokenContract = await ethers.getContractAt(
                    "SuperTokenMock",
                    this.token.address
                );
                const operatorSigner = await ethers.getSigner(operator);
                // This is not yet reflected in the spec
                await expectCustomError(
                    tokenContract
                        .connect(operatorSigner)
                        .operatorBurn(ZERO_ADDRESS, "0", data, operatorData),
                    tokenContract,
                    isDefaultOperator
                        ? "SUPER_TOKEN_BURN_FROM_ZERO_ADDRESS"
                        : "SUPER_TOKEN_CALLER_IS_NOT_OPERATOR_FOR_HOLDER"
                );
            });
        });
    });
}

function _shouldBehaveLikeERC777UnauthorizedOperatorBurn(
    setupAccounts: () => {holder: string; recipient: string; operator: string},
    data: string,
    operatorData: string
) {
    let holder: string, operator: string;

    before(function () {
        ({holder, operator} = setupAccounts());
    });

    describe("operator burn", function () {
        it("reverts", async function () {
            const tokenContract = await ethers.getContractAt(
                "SuperTokenMock",
                this.token.address
            );
            const operatorSigner = await ethers.getSigner(operator);
            await expectCustomError(
                tokenContract
                    .connect(operatorSigner)
                    .operatorBurn(holder, "0", data, operatorData),
                tokenContract,
                "SUPER_TOKEN_CALLER_IS_NOT_OPERATOR_FOR_HOLDER"
            );
        });
    });
}

function _shouldDirectSendTokens(
    setupAccounts: () => {from: string; to: string},
    amount: string,
    data: string
) {
    let from: string, to: string;

    before(function () {
        ({from, to} = setupAccounts());
    });

    _shouldSendTokens(
        () => ({
            from,
            operator: null,
            to,
        }),
        amount,
        data,
        null
    );
}

function _shouldOperatorSendTokens(
    setupAccounts: () => {from: string; to: string; operator: string},
    amount: string,
    data: string,
    operatorData: string
) {
    let from: string, operator: string, to: string;

    before(function () {
        ({from, operator, to} = setupAccounts());
    });

    _shouldSendTokens(
        () => ({
            from,
            operator,
            to,
        }),
        amount,
        data,
        operatorData
    );
}

function _shouldSendTokens(
    setupAccounts: () => {from: string; to: string; operator: string | null},
    amount: string,
    data: string,
    operatorData: string | null
) {
    let from: string, operator: string | null, to: string;
    let operatorCall = false;

    before(function () {
        ({from, operator, to} = setupAccounts());
        operatorCall = operator !== null;
    });

    it(`${
        operatorCall ? "operator " : ""
    }can send an amount of ${amount}`, async function () {
        const tokenContract = await ethers.getContractAt(
            "SuperTokenMock",
            this.token.address
        );
        const initialTotalSupply = await this.token.totalSupply();
        const initialFromBalance = await this.token.balanceOf(from);
        const initialToBalance = await this.token.balanceOf(to);

        let tx: ContractTransaction;
        if (!operatorCall) {
            tx = await tokenContract
                .connect(await ethers.getSigner(from))
                .send(to, amount, data);
            await expectEvent(tx, tokenContract, "Sent", {
                operator: from,
                from,
                to,
                amount,
                data,
                operatorData: null,
            });
        } else {
            tx = await tokenContract
                .connect(await ethers.getSigner(operator!))
                .operatorSend(from, to, amount, data, operatorData!);
            await expectEvent(tx, tokenContract, "Sent", {
                operator,
                from,
                to,
                amount,
                data,
                operatorData,
            });
        }

        await expectEvent(tx, tokenContract, "Transfer", {
            from,
            to,
            value: amount,
        });

        const finalTotalSupply = await this.token.totalSupply();
        const finalFromBalance = await this.token.balanceOf(from);
        const finalToBalance = await this.token.balanceOf(to);

        expect(finalTotalSupply).to.be.equal(initialTotalSupply);
        expect(finalToBalance.sub(initialToBalance)).to.be.equal(amount);
        expect(finalFromBalance.sub(initialFromBalance)).to.be.equal(
            Number(amount) * -1
        );
    });
}

function _shouldDirectBurnTokens(
    setupAccounts: () => {from: string},
    amount: string,
    data: string
) {
    let from: string;

    before(() => {
        ({from} = setupAccounts());
    });

    _shouldBurnTokens(
        () => ({
            from,
            operator: null,
        }),
        amount,
        data,
        null
    );
}

function _shouldOperatorBurnTokens(
    setupAccounts: () => {from: string; operator: string},
    amount: string,
    data: string,
    operatorData: string
) {
    let from: string, operator: string;

    before(() => {
        ({from, operator} = setupAccounts());
    });

    _shouldBurnTokens(
        () => ({
            from,
            operator,
        }),
        amount,
        data,
        operatorData
    );
}

function _shouldBurnTokens(
    setupAccounts: () => {from: string; operator: string | null},
    amount: string,
    data: string,
    operatorData: string | null
) {
    let from: string, operator: string | null;
    let operatorCall = false;

    before(() => {
        ({from, operator} = setupAccounts());
        operatorCall = operator !== null;
    });

    it(`${
        operatorCall ? "operator " : ""
    }can burn an amount of ${amount}`, async function () {
        const tokenContract = await ethers.getContractAt(
            "SuperTokenMock",
            this.token.address
        );
        const initialTotalSupply = await this.token.totalSupply();
        const initialFromBalance = await this.token.balanceOf(from);

        let tx: ContractTransaction;
        if (!operatorCall) {
            tx = await tokenContract
                .connect(await ethers.getSigner(from))
                .burn(amount, data);
            await expectEvent(tx, tokenContract, "Burned", {
                operator: from,
                from,
                amount,
                data,
                operatorData: null,
            });
        } else {
            tx = await tokenContract
                .connect(await ethers.getSigner(operator!))
                .operatorBurn(from, amount, data, operatorData!);
            await expectEvent(tx, tokenContract, "Burned", {
                operator,
                from,
                amount,
                data,
                operatorData,
            });
        }

        await expectEvent(tx, tokenContract, "Transfer", {
            from,
            to: ZERO_ADDRESS,
            value: amount,
        });

        const finalTotalSupply = await this.token.totalSupply();
        const finalFromBalance = await this.token.balanceOf(from);

        expect(finalTotalSupply.sub(initialTotalSupply)).to.be.equal(
            Number(amount) * -1
        );
        expect(finalFromBalance.sub(initialFromBalance)).to.be.equal(
            Number(amount) * -1
        );
    });
}

export function shouldBehaveLikeERC777SendBurnMintInternalWithReceiveHook(
    setupAccounts: () => {sender: string; recipient: string; operator: string},
    amount: string,
    data: string,
    operatorData: string
) {
    let operator: string, sender: string, recipient: string;
    let tokenContract: SuperTokenMock;

    before(async function () {
        tokenContract = await ethers.getContractAt(
            "SuperTokenMock",
            this.token.address
        );
    });

    beforeEach(() => {
        ({operator, sender, recipient} = setupAccounts());
    });

    describe("when TokensRecipient reverts", function () {
        beforeEach(async function () {
            await this.tokensRecipientImplementer.setShouldRevertReceive(true);
        });

        it("send reverts", async function () {
            await expectRevertedWith(
                _sendFromHolder(
                    tokenContract,
                    sender,
                    recipient,
                    amount.toString(),
                    data
                ),
                "_shouldRevertReceive"
            );
        });

        it("operatorSend reverts", async function () {
            const operatorSigner = await ethers.getSigner(operator);
            await expectRevertedWith(
                tokenContract
                    .connect(operatorSigner)
                    .operatorSend(
                        sender,
                        recipient,
                        amount.toString(),
                        data,
                        operatorData
                    ),
                "_shouldRevertReceive"
            );
        });

        it("mint (internal) reverts", async function () {
            const operatorSigner = await ethers.getSigner(operator);
            await expectRevertedWith(
                tokenContract
                    .connect(operatorSigner)
                    .mintInternal(
                        recipient,
                        amount.toString(),
                        data,
                        operatorData
                    ),
                "_shouldRevertReceive"
            );
        });
    });

    describe("when TokensRecipient does not revert", function () {
        beforeEach(async function () {
            await this.tokensRecipientImplementer.setShouldRevertSend(false);
        });

        it("TokensRecipient receives send data and is called after state mutation", async function () {
            const tx = await _sendFromHolder(
                this.token,
                sender,
                recipient,
                amount,
                data
            );

            const postSenderBalance = await this.token.balanceOf(sender);
            const postRecipientBalance = await this.token.balanceOf(recipient);

            await _assertTokensReceivedCalled(
                this.tokensRecipientImplementer,
                tx,
                this.token,
                sender,
                sender,
                recipient,
                amount,
                data,
                null,
                postSenderBalance,
                postRecipientBalance
            );
        });

        it("TokensRecipient receives operatorSend data and is called after state mutation", async function () {
            const tx = await tokenContract
                .connect(await ethers.getSigner(operator))
                .operatorSend(sender, recipient, amount, data, operatorData);

            const postSenderBalance = await this.token.balanceOf(sender);
            const postRecipientBalance = await this.token.balanceOf(recipient);

            await _assertTokensReceivedCalled(
                this.tokensRecipientImplementer,
                tx,
                this.token,
                operator,
                sender,
                recipient,
                amount,
                data,
                operatorData,
                postSenderBalance,
                postRecipientBalance
            );
        });

        it("TokensRecipient receives mint (internal) data and is called after state mutation", async function () {
            const tx = await tokenContract
                .connect(await ethers.getSigner(operator))
                .mintInternal(recipient, amount, data, operatorData);

            const postRecipientBalance = await this.token.balanceOf(recipient);

            await _assertTokensReceivedCalled(
                this.tokensRecipientImplementer,
                tx,
                this.token,
                operator,
                ZERO_ADDRESS,
                recipient,
                amount,
                data,
                operatorData,
                "0",
                postRecipientBalance
            );
        });
    });
}

export function shouldBehaveLikeERC777SendBurnWithSendHook(
    setupAccounts: () => {sender: string; recipient: string; operator: string},
    amount: string,
    data: string,
    operatorData: string
) {
    let sender: string, recipient: string, operator: string;
    let tokenContract: SuperTokenMock;

    before(async function () {
        tokenContract = await ethers.getContractAt(
            "SuperTokenMock",
            this.token.address
        );
    });

    beforeEach(() => {
        ({sender, recipient, operator} = setupAccounts());
    });

    describe("when TokensSender reverts", function () {
        beforeEach(async function () {
            await this.tokensSenderImplementer.setShouldRevertSend(true);
        });

        it("send reverts", async function () {
            await expectRevertedWith(
                _sendFromHolder(
                    this.token,
                    sender,
                    recipient,
                    amount.toString(),
                    data
                ),
                "_shouldRevertSend"
            );
        });

        it("operatorSend reverts", async function () {
            const operatorSigner = await ethers.getSigner(operator);
            await expectRevertedWith(
                tokenContract
                    .connect(operatorSigner)
                    .operatorSend(
                        sender,
                        recipient,
                        amount.toString(),
                        data,
                        operatorData
                    ),
                "_shouldRevertSend"
            );
        });

        it("burn reverts", async function () {
            await expectRevertedWith(
                _burnFromHolder(this.token, sender, amount.toString(), data),
                "_shouldRevertSend"
            );
        });

        it("operatorBurn reverts", async function () {
            const operatorSigner = await ethers.getSigner(operator);
            await expectRevertedWith(
                tokenContract
                    .connect(operatorSigner)
                    .operatorBurn(
                        sender,
                        amount.toString(),
                        data,
                        operatorData
                    ),
                "_shouldRevertSend"
            );
        });
    });

    describe("when TokensSender does not revert", function () {
        beforeEach(async function () {
            await this.tokensSenderImplementer.setShouldRevertSend(false);
        });

        it("TokensSender receives send data and is called before state mutation", async function () {
            const preSenderBalance = await this.token.balanceOf(sender);
            const preRecipientBalance = await this.token.balanceOf(recipient);

            const tx = await _sendFromHolder(
                this.token,
                sender,
                recipient,
                amount,
                data
            );

            await _assertTokensToSendCalled(
                this.tokensSenderImplementer,
                tx,
                this.token,
                sender,
                sender,
                recipient,
                amount,
                data,
                null,
                preSenderBalance,
                preRecipientBalance
            );
        });

        it("TokensSender receives operatorSend data and is called before state mutation", async function () {
            const preSenderBalance = await this.token.balanceOf(sender);
            const preRecipientBalance = await this.token.balanceOf(recipient);

            const tx = await tokenContract
                .connect(await ethers.getSigner(operator))
                .operatorSend(sender, recipient, amount, data, operatorData);

            await _assertTokensToSendCalled(
                this.tokensSenderImplementer,
                tx,
                this.token,
                operator,
                sender,
                recipient,
                amount,
                data,
                operatorData,
                preSenderBalance,
                preRecipientBalance
            );
        });

        it("TokensSender receives burn data and is called before state mutation", async function () {
            const preSenderBalance = await this.token.balanceOf(sender);

            const tx = await _burnFromHolder(this.token, sender, amount, data);

            await _assertTokensToSendCalled(
                this.tokensSenderImplementer,
                tx,
                this.token,
                sender,
                sender,
                ZERO_ADDRESS,
                amount,
                data,
                null,
                preSenderBalance
            );
        });

        it("TokensSender receives operatorBurn data and is called before state mutation", async function () {
            const preSenderBalance = await this.token.balanceOf(sender);

            const tx = await tokenContract
                .connect(await ethers.getSigner(operator))
                .operatorBurn(sender, amount, data, operatorData);

            await _assertTokensToSendCalled(
                this.tokensSenderImplementer,
                tx,
                this.token,
                operator,
                sender,
                ZERO_ADDRESS,
                amount,
                data,
                operatorData,
                preSenderBalance
            );
        });
    });
}

async function _removeBalance(token: SuperTokenMock, holder: string) {
    const holderSigner = await ethers.getSigner(holder);
    await token.connect(holderSigner).burn(await token.balanceOf(holder), "0x");
    expect(await token.balanceOf(holder)).to.be.equal("0");
}

async function _assertTokensReceivedCalled(
    implementer: ERC777SenderRecipientMock,
    tx: ContractTransaction,
    token: SuperTokenMock,
    operator: string,
    from: string,
    to: string,
    amount: string,
    data: string,
    operatorData: string | null,
    fromBalance: string,
    toBalance = "0"
) {
    await expectEvent(tx, implementer, "TokensReceivedCalled", {
        operator,
        from,
        to,
        amount,
        data,
        operatorData,
        token: token.address,
        fromBalance,
        toBalance,
    });
}

async function _assertTokensToSendCalled(
    implementer: ERC777SenderRecipientMock,
    tx: ContractTransaction,
    token: SuperTokenMock,
    operator: string,
    from: string,
    to: string,
    amount: string,
    data: string,
    operatorData: string | null,
    fromBalance: string,
    toBalance = "0"
) {
    await expectEvent(tx, implementer, "TokensToSendCalled", {
        operator,
        from,
        to,
        amount,
        data,
        operatorData,
        token: token.address,
        fromBalance,
        toBalance,
    });
}

async function _sendFromHolder(
    token: SuperTokenMock,
    holder: string,
    to: string,
    amount: string,
    data: string
): Promise<ContractTransaction> {
    if ((await ethers.provider.getCode(holder)) === "0x") {
        return token
            .connect(await ethers.getSigner(holder))
            .send(to, amount, data);
    }
    const mock = await ethers.getContractAt(
        "ERC777SenderRecipientMock",
        holder
    );
    const [signer] = await ethers.getSigners();
    return mock.connect(signer).send(token.address, to, amount, data);
}

async function _burnFromHolder(
    token: SuperTokenMock,
    holder: string,
    amount: string,
    data: string
): Promise<ContractTransaction> {
    if ((await ethers.provider.getCode(holder)) === "0x") {
        return token.connect(await ethers.getSigner(holder)).burn(amount, data);
    }
    const mock = await ethers.getContractAt(
        "ERC777SenderRecipientMock",
        holder
    );
    const [signer] = await ethers.getSigners();
    return mock.connect(signer).burn(token.address, amount, data);
}
