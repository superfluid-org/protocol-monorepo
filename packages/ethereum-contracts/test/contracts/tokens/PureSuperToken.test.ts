import {assert} from "chai";
import {ethers} from "hardhat";

import {ISuperTokenFactory} from "../../../typechain-types";
import TestEnvironment from "../../TestEnvironment";
import {loggedTx} from "../../lib/logged-tx";
import {expectRevertedWith} from "../../utils/expectRevert";
import {toWad} from "../utils/helpers";

const artifacts = require("../../lib/artifacts");
const ISuperTokenFactoryTruffle = artifacts.require("ISuperTokenFactory");

describe("PureSuperToken Contract", function () {
    this.timeout(300e3);
    const t = TestEnvironment.getSingleton();

    let admin: string;
    let superTokenFactory: ISuperTokenFactory;

    before(async () => {
        await t.beforeTestSuite({
            nAccounts: 1,
        });

        ({admin} = t.aliases);
        superTokenFactory = await ISuperTokenFactoryTruffle.at(
            await t.contracts.superfluid.getSuperTokenFactory()
        );
    });

    beforeEach(async function () {
        await t.beforeEachTestCase();
        t.beforeEachTestCaseBenchmark(this);
    });

    afterEach(async () => {
        t.afterEachTestCaseBenchmark();
    });

    it("#1 initialization", async () => {
        const PureSuperTokenFactory =
            await ethers.getContractFactory("PureSuperToken");
        const PureSuperToken = await PureSuperTokenFactory.deploy();
        await loggedTx("superTokenFactory.initializeCustomSuperToken", () =>
            superTokenFactory.initializeCustomSuperToken(PureSuperToken.address)
        );
        await loggedTx("PureSuperToken.initialize", () =>
            PureSuperToken.initialize("Didi Token", "DD", toWad(42).toString())
        );
        const token = await ethers.getContractAt(
            "ISuperToken",
            PureSuperToken.address
        );
        assert.equal(
            (await token.balanceOf(admin)).toString(),
            toWad(42).toString()
        );
        await expectRevertedWith(
            PureSuperToken.initialize("Hacker", "HH", toWad(0).toString()),
            "Initializable: contract is already initialized"
        );
    });
});
