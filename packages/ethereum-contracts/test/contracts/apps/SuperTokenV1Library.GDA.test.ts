import {SignerWithAddress} from "@nomiclabs/hardhat-ethers/signers";
import {ContractReceipt} from "ethers";
import {ethers, expect, web3} from "hardhat";

import {
    ConstantFlowAgreementV1,
    SuperfluidMock,
    SuperfluidPool,
    SuperTokenLibraryGDAMock,
    SuperTokenLibraryGDASuperAppMock,
    SuperTokenMock,
} from "../../../typechain-types";
import TestEnvironment from "../../TestEnvironment";
import {toBN} from "../utils/helpers";

import {deploySuperTokenAndNFTContractsAndInitialize} from "./SuperTokenV1Library.CFA.test";

const mintAmount = "1000000000000000000000000000"; // a small loan of a billion dollars
const flowRate = "1000000000000";

const callbackFunctionIndex = {
    UPDATE_MEMBER_UNITS: 0,
    CONNECT_POOL: 1,
    DISCONNECT_POOL: 2,
    CLAIM_ALL: 3,
    DISTRIBUTE: 4,
    DISTRIBUTE_FLOW: 5,
};

const userData = (
    functionIndex: number,
    pool = ethers.constants.AddressZero,
    member = ethers.constants.AddressZero,
    from = ethers.constants.AddressZero,
    units = 0,
    requestedAmount = 0,
    requestedFlowRate = 0
) =>
    web3.eth.abi.encodeParameters(
        [
            "uint8",
            "address",
            "address",
            "address",
            "uint128",
            "uint256",
            "int96",
        ],
        [
            functionIndex,
            pool,
            member,
            from,
            units,
            requestedAmount,
            requestedFlowRate,
        ]
    );

describe("SuperTokenV1Library.GDA", function () {
    this.timeout(300e3);
    const t = TestEnvironment.getSingleton();
    let host: SuperfluidMock, cfa: ConstantFlowAgreementV1;
    let aliceSigner: SignerWithAddress;
    let createFlowCalldata: string;
    let superTokenLibGDASuperAppMock: SuperTokenLibraryGDASuperAppMock;

    const getPoolAddressFromReceipt = (receipt: ContractReceipt) => {
        const POOL_CREATED_TOPIC = ethers.utils.solidityKeccak256(
            ["string"],
            ["PoolCreated(address,address,address)"]
        );
        const event = receipt.events?.find((x) =>
            x.topics.includes(POOL_CREATED_TOPIC)
        );
        return event
            ? `0x${event.data.substring(event.data.length - 40)}`
            : ethers.constants.AddressZero;
    };

    let alice: string, bob: string;
    let superTokenLibraryGDAMock: SuperTokenLibraryGDAMock;
    let superToken: SuperTokenMock;

    before(async () => {
        await t.beforeTestSuite({
            isTruffle: true,
            nAccounts: 5,
        });
        ({alice, bob} = t.aliases);
        superToken = t.tokens.SuperToken;

        cfa = t.contracts.cfa;
        host = t.contracts.superfluid;
        aliceSigner = await ethers.getSigner(alice);
    });

    beforeEach(async function () {
        await t.beforeEachTestCase();
        const mockFactory = await ethers.getContractFactory(
            "SuperTokenLibraryGDAMock"
        );
        superTokenLibraryGDAMock = await mockFactory.deploy();

        t.beforeEachTestCaseBenchmark(this);
    });

    this.afterEach(() => {
        t.afterEachTestCaseBenchmark();
    });

    it("#1.1 Should be able to create pool", async () => {
        const createPoolTxn = await superTokenLibraryGDAMock.createPoolTest(
            superToken.address,
            alice,
            {
                transferabilityForUnitsOwner: true,
                distributionFromAnyAddress: true,
            }
        );
        const receipt = await createPoolTxn.wait();
        const poolAddress = getPoolAddressFromReceipt(receipt);

        const poolContract = await ethers.getContractAt(
            "SuperfluidPool",
            poolAddress
        );
        expect(await poolContract.admin()).to.equal(alice);
        expect(await poolContract.superToken()).to.equal(superToken.address);
    });

    context("With a pool", () => {
        let pool: SuperfluidPool;
        let admin: SignerWithAddress;

        beforeEach(async () => {
            admin = await ethers.getSigner(alice);
            const createPoolTxn = await superTokenLibraryGDAMock.createPoolTest(
                superToken.address,
                admin.address,
                {
                    transferabilityForUnitsOwner: true,
                    distributionFromAnyAddress: true,
                }
            );
            const receipt = await createPoolTxn.wait();
            const poolAddress = getPoolAddressFromReceipt(receipt);
            pool = await ethers.getContractAt("SuperfluidPool", poolAddress);

            // transfer tokens to the mock gda contract
            await t.upgradeBalance("alice", t.configs.INIT_BALANCE);
            await superToken
                .connect(admin)
                .transfer(
                    superTokenLibraryGDAMock.address,
                    t.configs.INIT_BALANCE
                );
        });

        it("#1.2 Should be able to distribute to pool", async () => {
            expect(await pool.getUnits(bob)).to.equal("0");
            await pool.connect(admin).updateMemberUnits(bob, "10");
            expect(await pool.getUnits(bob)).to.equal("10");
            const bobBalanceBefore = await superToken.balanceOf(bob);
            const requestedDistributionAmount = "100";
            const estimatedDistributionActualAmount =
                await superTokenLibraryGDAMock.estimateDistributionActualAmountTest(
                    superToken.address,
                    superTokenLibraryGDAMock.address,
                    pool.address,
                    requestedDistributionAmount
                );
            await superTokenLibraryGDAMock.distributeTest(
                superToken.address,
                superTokenLibraryGDAMock.address,
                pool.address,
                requestedDistributionAmount
            );
            const bobBalanceAfter = await superToken.balanceOf(bob);
            expect(
                bobBalanceAfter,
                bobBalanceBefore
                    .add(toBN(requestedDistributionAmount))
                    .toString()
            );
            expect(
                estimatedDistributionActualAmount,
                requestedDistributionAmount
            );
        });

        it("#1.3 Should be able to distribute flow to pool", async () => {
            expect(await pool.getUnits(bob)).to.equal("0");
            await pool.connect(admin).updateMemberUnits(bob, "10");
            expect(await pool.getUnits(bob)).to.equal("10");
            const requestedFlowRate = "99";
            const estimatedFlowDistributionActualFlowRate =
                await superTokenLibraryGDAMock.estimateFlowDistributionActualFlowRateTest(
                    superToken.address,
                    superTokenLibraryGDAMock.address,
                    pool.address,
                    requestedFlowRate
                );
            await superTokenLibraryGDAMock.distributeFlowTest(
                superToken.address,
                superTokenLibraryGDAMock.address,
                pool.address,
                requestedFlowRate
            );
            const flowDistributionFlowRate =
                await superTokenLibraryGDAMock.getFlowDistributionFlowRateTest(
                    superToken.address,
                    superTokenLibraryGDAMock.address,
                    pool.address
                );
            expect(
                flowDistributionFlowRate.toString(),
                estimatedFlowDistributionActualFlowRate.actualFlowRate.toString()
            );
        });

        it("#1.4 Should be able to connect to a pool", async () => {
            await superTokenLibraryGDAMock.connectPoolTest(
                superToken.address,
                pool.address
            );
            expect(
                await superTokenLibraryGDAMock.isMemberConnectedTest(
                    superToken.address,
                    pool.address,
                    superTokenLibraryGDAMock.address
                )
            ).to.equal(true);
        });

        it("#1.4 Should be able to disconnect from a pool", async () => {
            await superTokenLibraryGDAMock.connectPoolTest(
                superToken.address,
                pool.address
            );
            expect(
                await superTokenLibraryGDAMock.isMemberConnectedTest(
                    superToken.address,
                    pool.address,
                    superTokenLibraryGDAMock.address
                )
            ).to.equal(true);
            await superTokenLibraryGDAMock.disconnectPoolTest(
                superToken.address,
                pool.address
            );
            expect(
                await superTokenLibraryGDAMock.isMemberConnectedTest(
                    superToken.address,
                    pool.address,
                    superTokenLibraryGDAMock.address
                )
            ).to.equal(false);
        });

        context("#2 - Callback GDA Operations", async function () {
            let appCreatedPool: SuperfluidPool;
            let appSuperToken: SuperTokenMock;

            beforeEach(async () => {
                appSuperToken =
                    await deploySuperTokenAndNFTContractsAndInitialize(t);

                await appSuperToken.mintInternal(alice, mintAmount, "0x", "0x");

                const superTokenLibGDASuperAppMockFactory =
                    await ethers.getContractFactory(
                        "SuperTokenLibraryGDASuperAppMock"
                    );
                superTokenLibGDASuperAppMock =
                    await superTokenLibGDASuperAppMockFactory.deploy(
                        host.address
                    );

                const createPoolTxn =
                    await superTokenLibGDASuperAppMock.createPoolTest(
                        appSuperToken.address,
                        superTokenLibGDASuperAppMock.address,
                        {
                            transferabilityForUnitsOwner: true,
                            distributionFromAnyAddress: true,
                        }
                    );
                const receipt = await createPoolTxn.wait();
                const poolAddress = getPoolAddressFromReceipt(receipt);
                appCreatedPool = await ethers.getContractAt(
                    "SuperfluidPool",
                    poolAddress
                );
                createFlowCalldata =
                    t.agreementHelper.cfaInterface.encodeFunctionData(
                        "createFlow",
                        [
                            appSuperToken.address,
                            superTokenLibGDASuperAppMock.address,
                            flowRate,
                            "0x",
                        ]
                    );
            });

            it("#2.1 should updateMemberUnits in callback", async () => {
                await host
                    .connect(aliceSigner)
                    .callAgreement(
                        cfa.address,
                        createFlowCalldata,
                        userData(
                            callbackFunctionIndex.UPDATE_MEMBER_UNITS,
                            appCreatedPool.address,
                            bob,
                            ethers.constants.AddressZero,
                            10
                        )
                    );
                expect(await appCreatedPool.getUnits(bob)).to.equal("10");
            });

            it("#2.2 should connectPool in callback", async () => {
                await host
                    .connect(aliceSigner)
                    .callAgreement(
                        cfa.address,
                        createFlowCalldata,
                        userData(
                            callbackFunctionIndex.CONNECT_POOL,
                            appCreatedPool.address
                        )
                    );
                expect(
                    await t.contracts.gda["isMemberConnected(address,address)"](
                        appCreatedPool.address,
                        superTokenLibGDASuperAppMock.address
                    )
                ).to.equal(true);
            });

            it("#2.3 should call disconnectPool in callback without revert", async () => {
                await host
                    .connect(aliceSigner)
                    .callAgreement(
                        cfa.address,
                        createFlowCalldata,
                        userData(
                            callbackFunctionIndex.DISCONNECT_POOL,
                            appCreatedPool.address
                        )
                    );
            });

            it("#2.4 should claimAll in callback", async () => {
                await expect(
                    host
                        .connect(aliceSigner)
                        .callAgreement(
                            cfa.address,
                            createFlowCalldata,
                            userData(
                                callbackFunctionIndex.CLAIM_ALL,
                                appCreatedPool.address,
                                bob
                            )
                        )
                )
                    .to.emit(appCreatedPool, "DistributionClaimed")
                    .withArgs(appSuperToken.address, bob, 0, 0);
            });

            it("#2.5 should distribute in callback", async () => {
                await expect(
                    host
                        .connect(aliceSigner)
                        .callAgreement(
                            cfa.address,
                            createFlowCalldata,
                            userData(
                                callbackFunctionIndex.DISTRIBUTE,
                                appCreatedPool.address,
                                ethers.constants.AddressZero,
                                superTokenLibGDASuperAppMock.address,
                                0,
                                100
                            )
                        )
                )
                    .to.emit(t.contracts.gda, "InstantDistributionUpdated")
                    .withArgs(
                        ethers.utils.getAddress(appSuperToken.address),
                        ethers.utils.getAddress(appCreatedPool.address),
                        ethers.utils.getAddress(
                            superTokenLibGDASuperAppMock.address
                        ),
                        ethers.utils.getAddress(
                            superTokenLibGDASuperAppMock.address
                        ),
                        100,
                        0,
                        "0x3078"
                    );
            });

            it("#2.6 should distributeFlow in callback", async () => {
                await expect(
                    host
                        .connect(aliceSigner)
                        .callAgreement(
                            cfa.address,
                            createFlowCalldata,
                            userData(
                                callbackFunctionIndex.DISTRIBUTE_FLOW,
                                appCreatedPool.address,
                                ethers.constants.AddressZero,
                                superTokenLibGDASuperAppMock.address,
                                0,
                                0,
                                100
                            )
                        )
                )
                    .to.emit(t.contracts.gda, "FlowDistributionUpdated")
                    .withArgs(
                        ethers.utils.getAddress(appSuperToken.address),
                        ethers.utils.getAddress(appCreatedPool.address),
                        ethers.utils.getAddress(
                            superTokenLibGDASuperAppMock.address
                        ),
                        ethers.utils.getAddress(
                            superTokenLibGDASuperAppMock.address
                        ),
                        0,
                        0,
                        0,
                        ethers.utils.getAddress(
                            superTokenLibGDASuperAppMock.address
                        ),
                        0,
                        "0x3078"
                    );
            });
        });
    });
});
