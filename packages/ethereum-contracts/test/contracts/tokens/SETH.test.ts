import {SignerWithAddress} from "@nomiclabs/hardhat-ethers/signers";
import {assert} from "chai";
import {ethers} from "hardhat";

import {
    ISETH,
    ISETH__factory,
    ISuperTokenFactory__factory,
    SETHProxy__factory,
    SuperToken__factory,
} from "../../../typechain-types";
import TestEnvironment from "../../TestEnvironment";
import {expectEvent} from "../../utils/expectEvent";
import {expectCustomError} from "../../utils/expectRevert";
import {toWad} from "../utils/helpers";

describe("Super ETH (SETH) Contract", function () {
    this.timeout(300e3);
    const t = TestEnvironment.getSingleton();

    let alice: string, bob: string;
    let aliceSigner: SignerWithAddress, bobSigner: SignerWithAddress;
    let seth: ISETH;

    before(async () => {
        await t.beforeTestSuite({
            nAccounts: 3,
        });
        ({alice, bob} = t.aliases);
        aliceSigner = await ethers.getSigner(alice);
        bobSigner = await ethers.getSigner(bob);

        const adminSigner = await ethers.getSigner(t.aliases.admin);
        const superTokenFactory = ISuperTokenFactory__factory.connect(
            await t.contracts.superfluid.getSuperTokenFactory(),
            adminSigner
        );
        const sethProxy = await new SETHProxy__factory(adminSigner).deploy();
        seth = ISETH__factory.connect(sethProxy.address, adminSigner);
        await (
            await superTokenFactory.initializeCustomSuperToken(seth.address)
        ).wait();
        await (
            await seth.initialize(
                t.constants.ZERO_ADDRESS,
                18,
                "Super ETH",
                "SETH"
            )
        ).wait();

        await t.pushEvmSnapshot();
    });

    after(async () => {
        await t.popEvmSnapshot();
    });

    beforeEach(async function () {
        await t.beforeEachTestCase();
        t.beforeEachTestCaseBenchmark(this);
    });

    afterEach(async () => {
        t.afterEachTestCaseBenchmark();
    });

    it("#1.1 upgradeByETH", async () => {
        const tx = await seth
            .connect(aliceSigner)
            .upgradeByETH({value: toWad(1)});
        await expectEvent(tx, seth, "TokenUpgraded", {
            account: alice,
            amount: toWad(1),
        });
        assert.equal(
            (await seth.balanceOf(alice)).toString(),
            toWad(1).toString()
        );
        assert.equal(
            (await ethers.provider.getBalance(seth.address)).toString(),
            toWad(1).toString()
        );
    });

    it("#1.2 upgradeByETHTo", async () => {
        const tx = await seth
            .connect(bobSigner)
            .upgradeByETHTo(alice, {value: toWad(1)});
        await expectEvent(tx, seth, "TokenUpgraded", {
            account: alice,
            amount: toWad(1),
        });
        assert.equal(
            (await seth.balanceOf(alice)).toString(),
            toWad(1).toString()
        );
        assert.equal(
            (await ethers.provider.getBalance(seth.address)).toString(),
            toWad(1).toString()
        );
    });

    it("#1.4 downgradeToETH", async () => {
        const aliceSeth = seth.connect(aliceSigner);
        await (await aliceSeth.upgradeByETH({value: toWad(1)})).wait();
        await expectCustomError(
            aliceSeth.downgradeToETH(toWad(1).add(1)),
            SuperToken__factory.connect(seth.address, aliceSigner),
            "SF_TOKEN_BURN_INSUFFICIENT_BALANCE"
        );

        const aliceBalance1 = await ethers.provider.getBalance(alice);
        const receipt = await (await aliceSeth.downgradeToETH(toWad(1))).wait();
        const aliceBalance2 = await ethers.provider.getBalance(alice);
        await expectEvent(receipt, seth, "TokenDowngraded", {
            account: alice,
            amount: toWad(1),
        });
        const txCost = receipt.gasUsed.mul(receipt.effectiveGasPrice);
        assert.equal(
            aliceBalance2.sub(aliceBalance1).add(txCost).toString(),
            toWad(1).toString()
        );
        assert.equal((await seth.balanceOf(alice)).toString(), "0");
        assert.equal(
            (await ethers.provider.getBalance(seth.address)).toString(),
            "0"
        );
    });

    it("#1.5 - Direct send Ether", async () => {
        await (
            await aliceSigner.sendTransaction({
                to: seth.address,
                value: toWad(1),
            })
        ).wait();
        assert.equal(
            (await seth.balanceOf(alice)).toString(),
            toWad(1).toString()
        );
        assert.equal(
            (await ethers.provider.getBalance(seth.address)).toString(),
            toWad(1).toString()
        );
    });
});
