import {assert} from "chai";
import {ethers} from "hardhat";

import {
    AgreementMock,
    SuperfluidMock,
    SuperToken,
    TestGovernance,
} from "../../../typechain-types";
import TestEnvironment from "../../TestEnvironment";
import {loggedTx} from "../../lib/logged-tx";
import {expectCustomError} from "../../utils/expectRevert";
import {sha3} from "../utils/helpers";

describe("SuperfluidToken implementation", function () {
    this.timeout(300e3);
    const t = TestEnvironment.getSingleton();

    const {ZERO_BYTES32, ZERO_ADDRESS} = t.constants;

    let admin: string, alice: string, bob: string;
    let superToken: SuperToken;
    let superfluid: SuperfluidMock;
    let governance: TestGovernance;
    let acA: AgreementMock;
    let acB: AgreementMock;

    // Lots of the tests are using 0x42 to test, but it needs to be zero padded
    const formattedData = ethers.utils.hexZeroPad("0x42", 32);

    async function createAgreementMock(type: string, version: number) {
        const agreementMockFactory =
            await ethers.getContractFactory("AgreementMock");
        return await agreementMockFactory.deploy(
            superfluid.address,
            type,
            version
        );
    }

    before(async () => {
        await t.beforeTestSuite({
            nAccounts: 3,
        });

        ({admin, alice, bob} = t.aliases);
        ({superfluid, governance} = t.contracts);
        superToken = t.tokens.SuperToken;
        superToken = await ethers.getContractAt(
            "SuperToken",
            superToken.address
        );

        const acALogic = await createAgreementMock(sha3("typeA")!, 1);
        await loggedTx("register agreement class typeA", async () => {
            const owner = await governance.owner();
            return governance
                .connect(await ethers.getSigner(owner))
                .registerAgreementClass(superfluid.address, acALogic.address);
        });
        acA = await ethers.getContractAt(
            "AgreementMock",
            await superfluid.getAgreementClass(sha3("typeA")!)
        );
        const acBLogic = await createAgreementMock(sha3("typeB")!, 1);
        await loggedTx("register agreement class typeB", async () => {
            const owner = await governance.owner();
            return governance
                .connect(await ethers.getSigner(owner))
                .registerAgreementClass(superfluid.address, acBLogic.address);
        });
        acB = await ethers.getContractAt(
            "AgreementMock",
            await superfluid.getAgreementClass(sha3("typeB")!)
        );

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

    async function expectRealtimeBalance(
        address: string,
        expectedBalance: string[]
    ) {
        const balance = await superToken.realtimeBalanceOfNow(address);
        assert.deepEqual(
            [
                balance[0].toString(),
                balance[1].toString(),
                balance[2].toString(),
            ],
            expectedBalance
        );
    }

    async function availableBalanceOf(address: string) {
        return (
            await superToken.realtimeBalanceOfNow(address)
        ).availableBalance.toString();
    }

    describe("#1 basic information", () => {
        it("#1.1 should return host", async () => {
            assert.equal(await superToken.getHost(), superfluid.address);
        });
    });

    describe("#2 real-time balance", () => {
        it("#2.1 default real-time balance is zeros", async () => {
            await expectRealtimeBalance(alice, ["0", "0", "0"]);
            await expectRealtimeBalance(bob, ["0", "0", "0"]);
        });

        context("#2.a single agreement real-time balance", () => {
            it("#2.a.1 without deposit", async () => {
                await loggedTx("setRealtimeBalanceFor", () =>
                    acA.setRealtimeBalanceFor(
                        superToken.address,
                        bob,
                        "10",
                        "0",
                        "0"
                    )
                );
                await expectRealtimeBalance(bob, ["10", "0", "0"]);
            });

            it("#2.a.2 with deposit", async () => {
                await loggedTx("setRealtimeBalanceFor", () =>
                    acA.setRealtimeBalanceFor(
                        superToken.address,
                        bob,
                        "10",
                        "2",
                        "0"
                    )
                );
                await expectRealtimeBalance(bob, ["8", "2", "0"]);
            });

            it("#2.a.3 with deposit and small owedDeposit", async () => {
                await loggedTx("setRealtimeBalanceFor", () =>
                    acA.setRealtimeBalanceFor(
                        superToken.address,
                        bob,
                        "10",
                        "2",
                        "1"
                    )
                );
                await expectRealtimeBalance(bob, ["9", "2", "1"]);
            });

            it("#2.a.4 with deposit and equal owedDeposit", async () => {
                await loggedTx("setRealtimeBalanceFor", () =>
                    acA.setRealtimeBalanceFor(
                        superToken.address,
                        bob,
                        "10",
                        "2",
                        "2"
                    )
                );
                await expectRealtimeBalance(bob, ["10", "2", "2"]);
            });

            it("#2.a.5 with deposit and large owedDeposit", async () => {
                await loggedTx("setRealtimeBalanceFor", () =>
                    acA.setRealtimeBalanceFor(
                        superToken.address,
                        bob,
                        "10",
                        "2",
                        "4"
                    )
                );
                await expectRealtimeBalance(bob, ["10", "2", "4"]);
            });
        });

        context("#2.b double agreement real-time balances", () => {
            it("#2.b.1 without deposit", async () => {
                await expectRealtimeBalance(alice, ["0", "0", "0"]);
                await acA.setRealtimeBalanceFor(
                    superToken.address,
                    bob,
                    "10",
                    "0",
                    "0"
                );
                await acB.setRealtimeBalanceFor(
                    superToken.address,
                    bob,
                    "5",
                    "0",
                    "0"
                );
                await expectRealtimeBalance(bob, ["15", "0", "0"]);
            });

            it("#2.b.2 with deposit", async () => {
                await expectRealtimeBalance(alice, ["0", "0", "0"]);
                await acA.setRealtimeBalanceFor(
                    superToken.address,
                    bob,
                    "10",
                    "2",
                    "0"
                );
                await acB.setRealtimeBalanceFor(
                    superToken.address,
                    bob,
                    "5",
                    "1",
                    "0"
                );
                await expectRealtimeBalance(bob, ["12", "3", "0"]);
            });

            it("#2.b.3 with deposit and owed deposit case 1", async () => {
                await expectRealtimeBalance(alice, ["0", "0", "0"]);
                await acA.setRealtimeBalanceFor(
                    superToken.address,
                    bob,
                    "10",
                    "2",
                    "2"
                ); // full deposit refund
                await acB.setRealtimeBalanceFor(
                    superToken.address,
                    bob,
                    "5",
                    "1",
                    "5"
                ); // deposit refund up to 1
                await expectRealtimeBalance(bob, ["15", "3", "7"]);
            });

            it("#2.b.4 with deposit and owed deposit case 2", async () => {
                await expectRealtimeBalance(alice, ["0", "0", "0"]);
                await acA.setRealtimeBalanceFor(
                    superToken.address,
                    bob,
                    "10",
                    "0",
                    "5"
                ); // deposit owed but without deposit
                await acB.setRealtimeBalanceFor(
                    superToken.address,
                    bob,
                    "5",
                    "5",
                    "0"
                ); // deposit without refund from `acA`
                await expectRealtimeBalance(bob, ["10", "5", "5"]);
            });
        });
    });

    describe("#3 agreement hosting functions", () => {
        const testData = [
            "0xdead000000000000000000000000000000000000000000000000000000000000",
            "0x000000000000000000000000000000000000000000000000000000000000beaf",
        ];
        const testData2 = [
            "0x771c362cd8f0f3f5c1ef27d2a79641f3d14131fcfefd59ccac42c13a52831384",
            "0x3887e65223d48ea8470b791ed887db139f831bb98e66a607531b3a7be4977cfb",
        ];

        context("#3.a agreement data", () => {
            it("#3.a.1 should create new agreement", async function () {
                await loggedTx("createAgreementFor", () =>
                    acA.createAgreementFor(
                        superToken.address,
                        formattedData,
                        testData
                    )
                );
                assert.deepEqual(
                    await superToken.getAgreementData(
                        acA.address,
                        formattedData,
                        2
                    ),
                    testData
                );
                assert.deepEqual(
                    await superToken.getAgreementData(
                        acA.address,
                        formattedData,
                        1
                    ),
                    [testData[0]]
                );
                assert.deepEqual(
                    await superToken.getAgreementData(
                        acA.address,
                        formattedData,
                        3
                    ),
                    [...testData, ZERO_BYTES32]
                );
            });

            it("#3.a.2 should not create the same agreement twice", async () => {
                await loggedTx("createAgreementFor", () =>
                    acA.createAgreementFor(
                        superToken.address,
                        formattedData,
                        testData
                    )
                );
                await expectCustomError(
                    acA.createAgreementFor(
                        superToken.address,
                        formattedData,
                        testData
                    ),
                    superToken,
                    "SF_TOKEN_AGREEMENT_ALREADY_EXISTS"
                );
                // try overlapping data
                await expectCustomError(
                    acA.createAgreementFor(superToken.address, formattedData, [
                        testData[0],
                    ]),
                    superToken,
                    "SF_TOKEN_AGREEMENT_ALREADY_EXISTS"
                );
                await expectCustomError(
                    acA.createAgreementFor(superToken.address, formattedData, [
                        ...testData,
                        ...testData,
                    ]),
                    superToken,
                    "SF_TOKEN_AGREEMENT_ALREADY_EXISTS"
                );
            });

            it("#3.a.3 should not overlap data", async () => {
                await loggedTx("createAgreementFor", () =>
                    acA.createAgreementFor(
                        superToken.address,
                        formattedData,
                        testData
                    )
                );
                assert.deepEqual(
                    await superToken.getAgreementData(
                        acA.address,
                        ethers.utils.hexZeroPad("0x43", 32),
                        1
                    ),
                    [ZERO_BYTES32]
                );
            });

            it("#3.a.4 should update data", async () => {
                await loggedTx("createAgreementFor", () =>
                    acA.createAgreementFor(
                        superToken.address,
                        formattedData,
                        testData
                    )
                );
                await loggedTx("updateAgreementDataFor", () =>
                    acA.updateAgreementDataFor(
                        superToken.address,
                        formattedData,
                        testData2
                    )
                );
                assert.deepEqual(
                    await superToken.getAgreementData(
                        acA.address,
                        formattedData,
                        2
                    ),
                    testData2
                );
            });

            it("#3.a.5 should terminate agreement", async () => {
                await loggedTx("createAgreementFor", () =>
                    acA.createAgreementFor(
                        superToken.address,
                        formattedData,
                        testData
                    )
                );
                await loggedTx("terminateAgreementFor", () =>
                    acA.terminateAgreementFor(
                        superToken.address,
                        formattedData,
                        2
                    )
                );
                assert.deepEqual(
                    await superToken.getAgreementData(
                        acA.address,
                        formattedData,
                        2
                    ),
                    [ZERO_BYTES32, ZERO_BYTES32]
                );
            });

            it("#3.a.6 should not terminate agreement twice", async () => {
                await loggedTx("createAgreementFor", () =>
                    acA.createAgreementFor(
                        superToken.address,
                        formattedData,
                        testData
                    )
                );
                await loggedTx("terminateAgreementFor", () =>
                    acA.terminateAgreementFor(
                        superToken.address,
                        formattedData,
                        2
                    )
                );
                await expectCustomError(
                    acA.terminateAgreementFor(
                        superToken.address,
                        formattedData,
                        2
                    ),
                    superToken,
                    "SF_TOKEN_AGREEMENT_DOES_NOT_EXIST"
                );
            });
        });

        context("#3.b agreement account state", () => {
            it("#3.b.1 should update agreement state", async () => {
                await acA.updateAgreementStateSlotFor(
                    superToken.address,
                    bob,
                    42,
                    testData
                );
                assert.deepEqual(
                    await superToken.getAgreementStateSlot(
                        acA.address,
                        bob,
                        42,
                        2
                    ),
                    testData
                );
                assert.deepEqual(
                    await superToken.getAgreementStateSlot(
                        acA.address,
                        bob,
                        42,
                        1
                    ),
                    [testData[0]]
                );
                assert.deepEqual(
                    await superToken.getAgreementStateSlot(
                        acA.address,
                        bob,
                        42,
                        3
                    ),
                    [...testData, ZERO_BYTES32]
                );
                await acA.updateAgreementStateSlotFor(
                    superToken.address,
                    bob,
                    42,
                    testData2
                );
                assert.deepEqual(
                    await superToken.getAgreementStateSlot(
                        acA.address,
                        bob,
                        42,
                        2
                    ),
                    testData2
                );
            });

            it("#3.b.2 should overlap agreement state data", async () => {
                await acA.updateAgreementStateSlotFor(
                    superToken.address,
                    bob,
                    42,
                    testData
                );
                await acA.updateAgreementStateSlotFor(
                    superToken.address,
                    bob,
                    43,
                    testData2
                );
                assert.deepEqual(
                    await superToken.getAgreementStateSlot(
                        acA.address,
                        bob,
                        42,
                        2
                    ),
                    testData
                );
                assert.deepEqual(
                    await superToken.getAgreementStateSlot(
                        acA.address,
                        bob,
                        43,
                        2
                    ),
                    testData2
                );
            });
        });

        context("#3.c static balance", () => {
            it("#3.c.1 should only be called by listed agreement", async () => {
                const acBad = await createAgreementMock(sha3("typeBad")!, 1);
                await expectCustomError(
                    acBad.settleBalanceFor(superToken.address, bob, "1"),
                    superToken,
                    "SF_TOKEN_ONLY_LISTED_AGREEMENT"
                );
            });

            it("#3.c.1 should adjust static balance", async () => {
                assert.equal(await availableBalanceOf(bob), "0");
                await loggedTx("settleBalanceFor", () =>
                    acA.settleBalanceFor(superToken.address, bob, "5")
                );
                assert.equal(await availableBalanceOf(bob), "5");
                await loggedTx("settleBalanceFor", () =>
                    acA.settleBalanceFor(superToken.address, bob, "-10")
                );
                assert.equal(await availableBalanceOf(bob), "-5");

                assert.equal(await availableBalanceOf(alice), "0");
                await loggedTx("settleBalanceFor", () =>
                    acA.settleBalanceFor(superToken.address, alice, "42")
                );
                assert.equal(await availableBalanceOf(bob), "-5");
                assert.equal(await availableBalanceOf(alice), "42");
            });
        });
    });

    describe("#4 liquidation rules", () => {
        it("#4.1 should only be called by listed agreement", async () => {
            const acBad = await createAgreementMock(sha3("typeBad")!, 1);
            await expectCustomError(
                acBad.makeLiquidationPayoutsFor(
                    superToken.address,
                    formattedData,
                    true,
                    bob,
                    alice,
                    0,
                    0
                ),
                superToken,
                "SF_TOKEN_ONLY_LISTED_AGREEMENT"
            );
        });

        context("#4.a default reward account (admin)", () => {
            before(async () => {
                await governance.setRewardAddress(
                    superfluid.address,
                    ZERO_ADDRESS,
                    admin
                );
            });

            it("#4.a.1 liquidation without bailout by alice (liquidator)", async () => {
                await acA.makeLiquidationPayoutsFor(
                    superToken.address,
                    formattedData,
                    true,
                    alice /* liquidator account */,
                    bob /* target account */,
                    "10" /* reward */,
                    "-10"
                );
                assert.equal(await availableBalanceOf(admin), "10");
                assert.equal(await availableBalanceOf(bob), "-10");
                assert.equal(await availableBalanceOf(alice), "0");
            });

            it("#4.a.2 liquidation without bailout by admin (reward address) directly", async () => {
                await acA.makeLiquidationPayoutsFor(
                    superToken.address,
                    formattedData,
                    true,
                    admin /* liquidator account */,
                    bob /* target account */,
                    "10" /* reward */,
                    "-10" /* targetAccountBalanceDelta */
                );
                assert.equal(await availableBalanceOf(admin), "10");
                assert.equal(await availableBalanceOf(bob), "-10");
                assert.equal(await availableBalanceOf(alice), "0");
            });

            it("#4.a.3 liquidation with bailout by alice (liquidator)", async () => {
                await acA.makeLiquidationPayoutsFor(
                    superToken.address,
                    formattedData,
                    false,
                    alice /* liquidator account */,
                    bob /* target account */,
                    "10" /* reward */,
                    "5" /* targetAccountBalanceDelta */
                );
                assert.equal(await availableBalanceOf(admin), "-15");
                assert.equal(await availableBalanceOf(bob), "5");
                assert.equal(await availableBalanceOf(alice), "10");
            });
        });

        context("#4.b zero reward account", () => {
            beforeEach(async () => {
                await governance.setRewardAddress(
                    superfluid.address,
                    ZERO_ADDRESS,
                    ZERO_ADDRESS
                );
            });

            it("#4.b.1 liquidation without bailout by alice (liquidator)", async () => {
                await acA.makeLiquidationPayoutsFor(
                    superToken.address,
                    formattedData,
                    true,
                    alice /* liquidator account */,
                    bob /* target account */,
                    "10",
                    "-10"
                );
                assert.equal(await availableBalanceOf(bob), "-10");
                assert.equal(await availableBalanceOf(alice), "10");
            });

            it("#4.b.2 liquidation with bailout by alice (liquidator and bailout account)", async () => {
                await acA.makeLiquidationPayoutsFor(
                    superToken.address,
                    formattedData,
                    false,
                    alice /* liquidator account */,
                    bob /* target account */,
                    "10",
                    "5"
                );
                assert.equal(await availableBalanceOf(bob), "5");
                assert.equal(await availableBalanceOf(alice), "-5");
            });
        });
    });
});
