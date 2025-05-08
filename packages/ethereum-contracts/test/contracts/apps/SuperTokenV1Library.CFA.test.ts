import {SignerWithAddress} from "@nomiclabs/hardhat-ethers/signers";
import {assert, ethers, expect, web3} from "hardhat";

import {
    // CFALibrarySuperAppMock,
    ConstantFlowAgreementV1,
    SuperfluidMock,
    SuperTokenLibraryCFAMock,
    SuperTokenLibraryCFASuperAppMock,
    SuperTokenMock,
} from "../../../typechain-types";
import TestEnvironment from "../../TestEnvironment";
import {toBN} from "../utils/helpers";

const abiCoder = ethers.utils.defaultAbiCoder;
const defaultUserData = abiCoder.encode(["uint256"], [690420]);

const mintAmount = "1000000000000000000000000000"; // a small loan of a billion dollars
const flowRate = "1000000000000";
const updatedFlowRate = "2000000000000";

// used to trigger different functions to test in the same callback
const callbackFunctionIndex = {
    CREATE_FLOW: 0,
    UPDATE_FLOW: 1,
    DELETE_FLOW: 2,
    CREATE_FLOW_BY_OPERATOR: 3,
    UPDATE_FLOW_BY_OPERATOR: 4,
    DELETE_FLOW_BY_OPERATOR: 5,
    UPDATE_FLOW_OPERATOR_PERMISSIONS: 6,
    AUTHORIZE_FLOW_OPERATOR_WITH_FULL_CONTROL: 7,
    REVOKE_FLOW_OPERATOR_WITH_FULL_CONTROL: 8,
};

// @note this function was added and is used to deploy a mock super token
// and the associated cfa NFT contracts and attach them to the
// super token. This was done because the tests which use this
// are not using the super token from test environment and are not
// reverting to snapshot and are therefore reliant on deploying a
// new super token each time.
export const deploySuperTokenAndNFTContractsAndInitialize = async (
    t: TestEnvironment
) => {
    const {poolAdminNFTProxy, poolMemberNFTProxy} =
        await t.deployNFTContracts();
    const superToken = await t.deployContract<SuperTokenMock>(
        "SuperTokenMock",
        t.contracts.superfluid.address,
        "69",
        t.constants.ZERO_ADDRESS,
        t.constants.ZERO_ADDRESS,
        poolAdminNFTProxy.address,
        poolMemberNFTProxy.address
    );

    return superToken;
};

// @note at this point, this file is mostly just for coverage
// we utilize the SuperTokenV1 Library throughout our tests
// and the code is simply a mapping of the functions
describe("SuperTokenV1 Library CFA testing", function () {
    this.timeout(300e3);
    const t = TestEnvironment.getSingleton();

    let superToken: SuperTokenMock,
        host: SuperfluidMock,
        cfa: ConstantFlowAgreementV1;
    let alice: string, bob: string;
    let aliceSigner: SignerWithAddress;
    let superTokenLibCFAMock: SuperTokenLibraryCFAMock;
    let superTokenLibCFASuperAppMock: SuperTokenLibraryCFASuperAppMock;

    // the calldata used for a lot of the tests are
    // repeated, it makes sense to collapse them here
    let createFlowCalldata: string;
    let authorizeFullControlCalldata: string;

    before(async () => {
        await t.beforeTestSuite({
            isTruffle: true,
            nAccounts: 3,
        });

        cfa = t.contracts.cfa;
        host = t.contracts.superfluid;

        ({alice, bob} = t.aliases);
        aliceSigner = await ethers.getSigner(alice);
    });

    beforeEach(async function () {
        superToken = await deploySuperTokenAndNFTContractsAndInitialize(t);

        await superToken.mintInternal(alice, mintAmount, "0x", "0x");
        await superToken.mintInternal(bob, mintAmount, "0x", "0x");

        const superTokenLibCFASuperAppMockFactory =
            await ethers.getContractFactory("SuperTokenLibraryCFASuperAppMock");
        superTokenLibCFASuperAppMock =
            await superTokenLibCFASuperAppMockFactory.deploy(
                host.address,
                alice, // sender
                bob, // receiver
                alice // operator
            );
        // deploy a contract we'll use for testing the library
        const superTokenLibCFAMockFactory = await ethers.getContractFactory(
            "SuperTokenLibraryCFAMock"
        );
        superTokenLibCFAMock = await superTokenLibCFAMockFactory.deploy();

        await superToken.mintInternal(alice, mintAmount, "0x", "0x");
        await superToken
            .connect(aliceSigner)
            .transfer(superTokenLibCFAMock.address, mintAmount);

        await superToken.mintInternal(alice, mintAmount, "0x", "0x");
        await superToken
            .connect(aliceSigner)
            .transfer(superTokenLibCFASuperAppMock.address, mintAmount);

        createFlowCalldata = t.agreementHelper.cfaInterface.encodeFunctionData(
            "createFlow",
            [
                superToken.address,
                superTokenLibCFASuperAppMock.address,
                flowRate,
                "0x",
            ]
        );
        authorizeFullControlCalldata =
            t.agreementHelper.cfaInterface.encodeFunctionData(
                "authorizeFlowOperatorWithFullControl",
                [superToken.address, superTokenLibCFAMock.address, "0x"]
            );

        t.beforeEachTestCaseBenchmark(this);
    });

    afterEach(() => {
        t.afterEachTestCaseBenchmark();
    });

    describe("1 - Flow Ops", async function () {
        it("1.1 - Create Flow", async () => {
            await superTokenLibCFAMock.createFlowTest(
                superToken.address,
                bob,
                flowRate
            );

            assert.equal(
                (
                    await cfa.getFlow(
                        superToken.address,
                        superTokenLibCFAMock.address,
                        bob
                    )
                ).flowRate.toString(),
                flowRate
            );
            //testing read functions
            const flowInfo = await superTokenLibCFAMock.getFlowInfoTest(
                superToken.address,
                superTokenLibCFAMock.address,
                bob
            );

            const flowRateTestResponse =
                await superTokenLibCFAMock.getFlowRateTest(
                    superToken.address,
                    superTokenLibCFAMock.address,
                    bob
                );
            assert.equal(flowInfo[1].toString(), flowRate);
            assert.equal(flowRateTestResponse.toString(), flowRate);
            const netFlowRateResponse =
                await superTokenLibCFAMock.getNetFlowRateTest(
                    superToken.address,
                    superTokenLibCFAMock.address
                );
            const cfaNetFlowRateResponse = await cfa.getNetFlow(
                superToken.address,
                superTokenLibCFAMock.address
            );
            assert.equal(
                netFlowRateResponse.toString(),
                cfaNetFlowRateResponse.toString()
            );
            const netFlowInfoResponse =
                await superTokenLibCFAMock.getNetFlowInfoTest(
                    superToken.address,
                    superTokenLibCFAMock.address
                );
            assert.equal(
                netFlowInfoResponse[1].toString(),
                cfaNetFlowRateResponse.toString()
            );

            const cfaDepositCalculation = (
                await cfa.getFlow(
                    superToken.address,
                    superTokenLibCFAMock.address,
                    bob
                )
            ).deposit;
            const libDepositCalculation =
                await superTokenLibCFAMock.getBufferAmountByFlowRateTest(
                    superToken.address,
                    flowRate
                );

            assert.equal(
                cfaDepositCalculation.toString(),
                libDepositCalculation.toString()
            );
        });

        it("1.2 - Create Flow w/ userData", async () => {
            await expect(
                superTokenLibCFAMock.createFlowWithUserDataTest(
                    superToken.address,
                    bob,
                    flowRate,
                    defaultUserData
                )
            )
                .to.emit(t.contracts.cfa, "FlowUpdated")
                .withArgs(
                    superToken.address,
                    superTokenLibCFAMock.address,
                    bob,
                    flowRate,
                    toBN(flowRate).mul(toBN(-1)),
                    flowRate,
                    defaultUserData
                );
        });

        it("1.3 - Update Flow", async () => {
            await superTokenLibCFAMock.createFlowTest(
                superToken.address,
                bob,
                flowRate
            );

            await superTokenLibCFAMock.updateFlowTest(
                superToken.address,
                bob,
                updatedFlowRate
            );

            assert.equal(
                (
                    await cfa.getFlow(
                        superToken.address,
                        superTokenLibCFAMock.address,
                        bob
                    )
                ).flowRate.toString(),
                updatedFlowRate
            );
        });

        it("1.4 - Update Flow w/ userData", async () => {
            await superTokenLibCFAMock.createFlowTest(
                superToken.address,
                bob,
                flowRate
            );

            await expect(
                superTokenLibCFAMock.updateFlowWithUserDataTest(
                    superToken.address,
                    bob,
                    updatedFlowRate,
                    defaultUserData
                )
            )
                .to.emit(t.contracts.cfa, "FlowUpdated")
                .withArgs(
                    superToken.address,
                    superTokenLibCFAMock.address,
                    bob,
                    updatedFlowRate,
                    toBN(updatedFlowRate).mul(toBN(-1)),
                    updatedFlowRate,
                    defaultUserData
                );

            await superTokenLibCFAMock.updateFlowTest(
                superToken.address,
                bob,
                updatedFlowRate
            );

            assert.equal(
                (
                    await cfa.getFlow(
                        superToken.address,
                        superTokenLibCFAMock.address,
                        bob
                    )
                ).flowRate.toString(),
                updatedFlowRate
            );
        });

        it("1.5 - Delete Flow", async () => {
            await superTokenLibCFAMock.createFlowTest(
                superToken.address,
                bob,
                flowRate
            );

            await superTokenLibCFAMock.deleteFlowTest(
                superToken.address,
                superTokenLibCFAMock.address,
                bob
            );

            assert.equal(
                (
                    await cfa.getFlow(
                        superToken.address,
                        superTokenLibCFAMock.address,
                        bob
                    )
                ).flowRate.toString(),
                "0"
            );
        });

        it("1.6 - Delete Flow w/ userData", async () => {
            await superTokenLibCFAMock.createFlowTest(
                superToken.address,
                bob,
                flowRate
            );

            await expect(
                superTokenLibCFAMock.deleteFlowWithUserDataTest(
                    superToken.address,
                    superTokenLibCFAMock.address,
                    bob,
                    defaultUserData
                )
            )
                .to.emit(t.contracts.cfa, "FlowUpdated")
                .withArgs(
                    superToken.address,
                    superTokenLibCFAMock.address,
                    bob,
                    "0",
                    "0",
                    "0",
                    defaultUserData
                );

            assert.equal(
                (
                    await cfa.getFlow(
                        superToken.address,
                        superTokenLibCFAMock.address,
                        bob
                    )
                ).flowRate.toString(),
                "0"
            );
        });

        it("1.7 - Create Flow in Callback", async () => {
            await host
                .connect(aliceSigner)
                .callAgreement(
                    cfa.address,
                    t.agreementHelper.cfaInterface.encodeFunctionData(
                        "createFlow",
                        [
                            superToken.address,
                            superTokenLibCFASuperAppMock.address,
                            flowRate,
                            "0x",
                        ]
                    ),
                    web3.eth.abi.encodeParameter(
                        "uint8",
                        callbackFunctionIndex.CREATE_FLOW
                    )
                );

            assert.equal(
                (
                    await cfa.getFlow(
                        superToken.address,
                        superTokenLibCFASuperAppMock.address,
                        bob
                    )
                ).flowRate.toString(),
                flowRate
            );
        });

        it("1.8 - Update Flow in Callback", async () => {
            await superTokenLibCFASuperAppMock.createFlow(superToken.address);

            await host
                .connect(aliceSigner)
                .callAgreement(
                    cfa.address,
                    createFlowCalldata,
                    web3.eth.abi.encodeParameter(
                        "uint8",
                        callbackFunctionIndex.UPDATE_FLOW
                    )
                );

            assert.equal(
                (
                    await cfa.getFlow(
                        superToken.address,
                        superTokenLibCFASuperAppMock.address,
                        bob
                    )
                ).flowRate.toString(),
                updatedFlowRate
            );
        });

        it("1.9 - Delete Flow in Callback", async () => {
            await superTokenLibCFASuperAppMock.createFlow(superToken.address);

            await host
                .connect(aliceSigner)
                .callAgreement(
                    cfa.address,
                    createFlowCalldata,
                    web3.eth.abi.encodeParameter(
                        "uint8",
                        callbackFunctionIndex.DELETE_FLOW
                    )
                );

            assert.equal(
                (
                    await cfa.getFlow(
                        superToken.address,
                        superTokenLibCFASuperAppMock.address,
                        bob
                    )
                ).flowRate.toString(),
                "0"
            );
        });

        it("1.10 - _getHostAndCFA empty cache test", async () => {
            const flowRateTestResponse =
                await superTokenLibCFAMock.getFlowRateTest(
                    superToken.address,
                    superTokenLibCFAMock.address,
                    bob
                );
            expect(flowRateTestResponse).to.equal("0");
        });
    });

    describe("2 - Flow Operator Ops", async () => {
        // testing permissions first before testing operator functions
        it("2.1 - Can Update Flow Operator Permissions", async () => {
            await superTokenLibCFAMock.setFlowPermissionsTest(
                superToken.address,
                alice,
                true,
                true,
                true,
                "1"
            );
            //testing getter function
            const flowPermissionsCheck =
                await superTokenLibCFAMock.getFlowPermissionsTest(
                    superToken.address,
                    superTokenLibCFAMock.address,
                    alice
                );
            assert.equal(
                flowPermissionsCheck.allowCreate,
                flowPermissionsCheck.allowUpdate
            );
            assert.equal(
                flowPermissionsCheck.allowUpdate,
                flowPermissionsCheck.allowDelete
            );
            assert.equal(flowPermissionsCheck.allowDelete, true);

            assert.equal(
                flowPermissionsCheck.flowRateAllowance.toString(),
                "1"
            );

            assert.equal(
                (
                    await cfa.getFlowOperatorData(
                        superToken.address,
                        superTokenLibCFAMock.address,
                        alice
                    )
                ).permissions.toString(),
                "7"
            );
        });

        it("2.2 - Can Authorize Flow Operator With full Control", async () => {
            await superTokenLibCFAMock.setMaxFlowPermissionsTest(
                alice,
                superToken.address
            );

            assert.equal(
                (
                    await cfa.getFlowOperatorData(
                        superToken.address,
                        superTokenLibCFAMock.address,
                        alice
                    )
                ).permissions.toString(),
                "7"
            );
        });

        it("2.3 - Can Revoke Flow Operator With Full Control", async () => {
            await superTokenLibCFAMock.setMaxFlowPermissionsTest(
                alice,
                superToken.address
            );

            await superTokenLibCFAMock.revokeFlowPermissionsTest(
                alice,
                superToken.address
            );

            assert.equal(
                (
                    await cfa.getFlowOperatorData(
                        superToken.address,
                        superTokenLibCFAMock.address,
                        alice
                    )
                ).permissions.toString(),
                "0"
            );
        });

        it("2.4 - Can Create Flow By Operator", async () => {
            await host
                .connect(aliceSigner)
                .callAgreement(cfa.address, authorizeFullControlCalldata, "0x");

            await superTokenLibCFAMock.createFlowFromTest(
                superToken.address,
                alice,
                bob,
                flowRate
            );

            assert.equal(
                (
                    await cfa.getFlow(superToken.address, alice, bob)
                ).flowRate.toString(),
                flowRate
            );
        });

        it("2.5 - Can Create Flow By Operator w/ userData", async () => {
            await host
                .connect(aliceSigner)
                .callAgreement(cfa.address, authorizeFullControlCalldata, "0x");

            await expect(
                superTokenLibCFAMock.createFlowFromWithUserDataTest(
                    superToken.address,
                    alice,
                    bob,
                    flowRate,
                    defaultUserData
                )
            )
                .to.emit(t.contracts.cfa, "FlowUpdated")
                .withArgs(
                    superToken.address,
                    alice,
                    bob,
                    flowRate,
                    toBN(flowRate).mul(toBN(-1)),
                    flowRate,
                    defaultUserData
                );

            assert.equal(
                (
                    await cfa.getFlow(superToken.address, alice, bob)
                ).flowRate.toString(),
                flowRate
            );
        });

        it("2.6 - Can Update Flow By Operator", async () => {
            await host
                .connect(aliceSigner)
                .callAgreement(
                    cfa.address,
                    t.agreementHelper.cfaInterface.encodeFunctionData(
                        "authorizeFlowOperatorWithFullControl",
                        [superToken.address, superTokenLibCFAMock.address, "0x"]
                    ),
                    "0x"
                );

            await host
                .connect(aliceSigner)
                .callAgreement(
                    cfa.address,
                    t.agreementHelper.cfaInterface.encodeFunctionData(
                        "createFlow",
                        [superToken.address, bob, flowRate, "0x"]
                    ),
                    "0x"
                );

            await superTokenLibCFAMock.updateFlowFromTest(
                superToken.address,
                alice,
                bob,
                updatedFlowRate
            );

            assert.equal(
                (
                    await cfa.getFlow(superToken.address, alice, bob)
                ).flowRate.toString(),
                updatedFlowRate
            );
        });

        it("2.7 - Can Update Flow By Operator w/ userData", async () => {
            await host
                .connect(aliceSigner)
                .callAgreement(
                    cfa.address,
                    t.agreementHelper.cfaInterface.encodeFunctionData(
                        "authorizeFlowOperatorWithFullControl",
                        [superToken.address, superTokenLibCFAMock.address, "0x"]
                    ),
                    "0x"
                );

            await host
                .connect(aliceSigner)
                .callAgreement(
                    cfa.address,
                    t.agreementHelper.cfaInterface.encodeFunctionData(
                        "createFlow",
                        [superToken.address, bob, flowRate, "0x"]
                    ),
                    "0x"
                );

            await expect(
                superTokenLibCFAMock.updateFlowFromWithUserDataTest(
                    superToken.address,
                    alice,
                    bob,
                    updatedFlowRate,
                    defaultUserData
                )
            )
                .to.emit(t.contracts.cfa, "FlowUpdated")
                .withArgs(
                    superToken.address,
                    alice,
                    bob,
                    updatedFlowRate,
                    toBN(updatedFlowRate).mul(toBN(-1)),
                    updatedFlowRate,
                    defaultUserData
                );

            assert.equal(
                (
                    await cfa.getFlow(superToken.address, alice, bob)
                ).flowRate.toString(),
                updatedFlowRate
            );
        });

        it("2.8 - Can Delete Flow By Operator", async () => {
            await host
                .connect(aliceSigner)
                .callAgreement(cfa.address, authorizeFullControlCalldata, "0x");

            await host
                .connect(aliceSigner)
                .callAgreement(
                    cfa.address,
                    t.agreementHelper.cfaInterface.encodeFunctionData(
                        "createFlow",
                        [superToken.address, bob, flowRate, "0x"]
                    ),
                    "0x"
                );

            await superTokenLibCFAMock.deleteFlowFromTest(
                superToken.address,
                alice,
                bob
            );

            assert.equal(
                (
                    await cfa.getFlow(superToken.address, alice, bob)
                ).flowRate.toString(),
                "0"
            );
        });

        it("2.9 - Can Delete Flow By Operator w/ userData", async () => {
            await host
                .connect(aliceSigner)
                .callAgreement(cfa.address, authorizeFullControlCalldata, "0x");

            await host
                .connect(aliceSigner)
                .callAgreement(
                    cfa.address,
                    t.agreementHelper.cfaInterface.encodeFunctionData(
                        "createFlow",
                        [superToken.address, bob, flowRate, "0x"]
                    ),
                    "0x"
                );

            await expect(
                superTokenLibCFAMock.deleteFlowFromWithUserDataTest(
                    superToken.address,
                    alice,
                    bob,
                    defaultUserData
                )
            )
                .to.emit(t.contracts.cfa, "FlowUpdated")
                .withArgs(
                    superToken.address,
                    alice,
                    bob,
                    "0",
                    "0",
                    "0",
                    defaultUserData
                );

            assert.equal(
                (
                    await cfa.getFlow(superToken.address, alice, bob)
                ).flowRate.toString(),
                "0"
            );
        });

        it("2.10 - Can Create Flow By Operator in Callback", async () => {
            // alice approves super app as operator, alice creates a flow to super app which creates
            // a flow from alice to bob on alice's behalf.
            authorizeFullControlCalldata =
                t.agreementHelper.cfaInterface.encodeFunctionData(
                    "authorizeFlowOperatorWithFullControl",
                    [
                        superToken.address,
                        superTokenLibCFASuperAppMock.address,
                        "0x",
                    ]
                );
            await host
                .connect(aliceSigner)
                .callAgreement(cfa.address, authorizeFullControlCalldata, "0x");

            await host
                .connect(aliceSigner)
                .callAgreement(
                    cfa.address,
                    createFlowCalldata,
                    web3.eth.abi.encodeParameter(
                        "uint8",
                        callbackFunctionIndex.CREATE_FLOW_BY_OPERATOR
                    )
                );

            assert.equal(
                (
                    await cfa.getFlow(superToken.address, alice, bob)
                ).flowRate.toString(),
                flowRate
            );
        });

        it("2.11 - Can Update Flow By Operator in Callback", async () => {
            // alice approves super app as operator, alice creates a flow to bob, alice creates a
            // flow to super app which updates the flow from alice to bob on alice's behalf.
            authorizeFullControlCalldata =
                t.agreementHelper.cfaInterface.encodeFunctionData(
                    "authorizeFlowOperatorWithFullControl",
                    [
                        superToken.address,
                        superTokenLibCFASuperAppMock.address,
                        "0x",
                    ]
                );
            await host
                .connect(aliceSigner)
                .callAgreement(cfa.address, authorizeFullControlCalldata, "0x");

            await host
                .connect(aliceSigner)
                .callAgreement(
                    cfa.address,
                    t.agreementHelper.cfaInterface.encodeFunctionData(
                        "createFlow",
                        [superToken.address, bob, flowRate, "0x"]
                    ),
                    "0x"
                );

            await host
                .connect(aliceSigner)
                .callAgreement(
                    cfa.address,
                    createFlowCalldata,
                    web3.eth.abi.encodeParameter(
                        "uint8",
                        callbackFunctionIndex.UPDATE_FLOW_BY_OPERATOR
                    )
                );

            assert.equal(
                (
                    await cfa.getFlow(superToken.address, alice, bob)
                ).flowRate.toString(),
                updatedFlowRate
            );
        });

        it("2.12 - Can Delete Flow By Operator in Callback", async () => {
            // alice approves super app as operator, alice creates a flow to bob, alice creates a
            // flow to super app which deletes the flow from alice to bob on alice's behalf.
            authorizeFullControlCalldata =
                t.agreementHelper.cfaInterface.encodeFunctionData(
                    "authorizeFlowOperatorWithFullControl",
                    [
                        superToken.address,
                        superTokenLibCFASuperAppMock.address,
                        "0x",
                    ]
                );
            await host
                .connect(aliceSigner)
                .callAgreement(cfa.address, authorizeFullControlCalldata, "0x");

            await host
                .connect(aliceSigner)
                .callAgreement(
                    cfa.address,
                    t.agreementHelper.cfaInterface.encodeFunctionData(
                        "createFlow",
                        [superToken.address, bob, flowRate, "0x"]
                    ),
                    "0x"
                );

            await host
                .connect(aliceSigner)
                .callAgreement(
                    cfa.address,
                    createFlowCalldata,
                    web3.eth.abi.encodeParameter(
                        "uint8",
                        callbackFunctionIndex.DELETE_FLOW_BY_OPERATOR
                    )
                );

            assert.equal(
                (
                    await cfa.getFlow(superToken.address, alice, bob)
                ).flowRate.toString(),
                "0"
            );
        });

        it("2.13 - Can Update Flow Operator Permissions in Callback", async () => {
            // alice creates a flow to the super app which sets alice as the operator for it
            await host
                .connect(aliceSigner)
                .callAgreement(
                    cfa.address,
                    createFlowCalldata,
                    web3.eth.abi.encodeParameter(
                        "uint8",
                        callbackFunctionIndex.UPDATE_FLOW_OPERATOR_PERMISSIONS
                    )
                );

            assert.equal(
                (
                    await cfa.getFlowOperatorData(
                        superToken.address,
                        superTokenLibCFASuperAppMock.address,
                        alice
                    )
                ).permissions.toString(),
                "7"
            );
        });

        it("2.14 - Can Authorize Flow Operator With Full Control in Callback", async () => {
            // alice creates a flow to the super app which sets alice as the operator for it
            await host
                .connect(aliceSigner)
                .callAgreement(
                    cfa.address,
                    createFlowCalldata,
                    web3.eth.abi.encodeParameter(
                        "uint8",
                        callbackFunctionIndex.AUTHORIZE_FLOW_OPERATOR_WITH_FULL_CONTROL
                    )
                );

            assert.equal(
                (
                    await cfa.getFlowOperatorData(
                        superToken.address,
                        superTokenLibCFASuperAppMock.address,
                        alice
                    )
                ).permissions.toString(),
                "7"
            );
        });

        it("2.15 - Can Revoke Flow Operator With Full Control in Callback", async () => {
            // alice sets theirself as the operator for the super app, alice creates a flow to
            // the super app which revokes alice's operator permissions
            await superTokenLibCFASuperAppMock
                .connect(aliceSigner)
                .authorizeFlowOperatorWithFullControl(superToken.address);

            await host
                .connect(aliceSigner)
                .callAgreement(
                    cfa.address,
                    createFlowCalldata,
                    web3.eth.abi.encodeParameter(
                        "uint8",
                        callbackFunctionIndex.REVOKE_FLOW_OPERATOR_WITH_FULL_CONTROL
                    )
                );

            assert.equal(
                (
                    await cfa.getFlowOperatorData(
                        superToken.address,
                        superTokenLibCFASuperAppMock.address,
                        alice
                    )
                ).permissions.toString(),
                "0"
            );
        });

        it("2.16 - Can increase flow rate allowance", async () => {
            await superTokenLibCFAMock
                .connect(aliceSigner)
                .increaseFlowRateAllowanceTest(
                    superToken.address,
                    bob,
                    flowRate
                );

            const flowPermissionsCheck =
                await superTokenLibCFAMock.getFlowPermissionsTest(
                    superToken.address,
                    superTokenLibCFAMock.address,
                    bob
                );
            assert.equal(
                flowPermissionsCheck.flowRateAllowance.toString(),
                flowRate
            );
        });

        it("2.17 - Can increase flow rate allowance with user data", async () => {
            await superTokenLibCFAMock
                .connect(aliceSigner)
                .increaseFlowRateAllowanceWithUserDataTest(
                    superToken.address,
                    bob,
                    flowRate,
                    "0x1234"
                );

            const flowPermissionsCheck =
                await superTokenLibCFAMock.getFlowPermissionsTest(
                    superToken.address,
                    superTokenLibCFAMock.address,
                    bob
                );
            assert.equal(
                flowPermissionsCheck.flowRateAllowance.toString(),
                flowRate
            );
        });

        it("2.18 - Can decrease flow rate allowance", async () => {
            await superTokenLibCFAMock
                .connect(aliceSigner)
                .increaseFlowRateAllowanceTest(
                    superToken.address,
                    bob,
                    flowRate
                );

            await superTokenLibCFAMock
                .connect(aliceSigner)
                .decreaseFlowRateAllowanceTest(
                    superToken.address,
                    bob,
                    flowRate
                );

            const flowPermissionsCheck =
                await superTokenLibCFAMock.getFlowPermissionsTest(
                    superToken.address,
                    superTokenLibCFAMock.address,
                    alice
                );
            assert.equal(
                flowPermissionsCheck.flowRateAllowance.toString(),
                "0"
            );
        });

        it("2.19 - Can decrease flow rate allowance with user data", async () => {
            await superTokenLibCFAMock
                .connect(aliceSigner)
                .increaseFlowRateAllowanceTest(
                    superToken.address,
                    bob,
                    flowRate
                );

            await superTokenLibCFAMock
                .connect(aliceSigner)
                .decreaseFlowRateAllowanceWithUserDataTest(
                    superToken.address,
                    bob,
                    flowRate,
                    "0x1234"
                );

            const flowPermissionsCheck =
                await superTokenLibCFAMock.getFlowPermissionsTest(
                    superToken.address,
                    superTokenLibCFAMock.address,
                    alice
                );
            assert.equal(
                flowPermissionsCheck.flowRateAllowance.toString(),
                "0"
            );
        });

        it("2.20 - Can increase flow allowance with permissions", async () => {
            await superTokenLibCFAMock
                .connect(aliceSigner)
                .increaseFlowRateAllowanceWithPermissionsTest(
                    superToken.address,
                    alice,
                    callbackFunctionIndex.AUTHORIZE_FLOW_OPERATOR_WITH_FULL_CONTROL,
                    flowRate
                );

            const flowPermissionsCheck =
                await superTokenLibCFAMock.getFlowPermissionsTest(
                    superToken.address,
                    superTokenLibCFAMock.address,
                    alice
                );
            assert.equal(
                flowPermissionsCheck.flowRateAllowance.toString(),
                flowRate
            );
            assert.equal(flowPermissionsCheck.allowCreate, true);
            assert.equal(flowPermissionsCheck.allowUpdate, true);
            assert.equal(flowPermissionsCheck.allowDelete, true);
        });

        it("2.21 - Can increase flow allowance with permissions with user data", async () => {
            await superTokenLibCFAMock
                .connect(aliceSigner)
                .increaseFlowRateAllowanceWithPermissionsWithUserDataTest(
                    superToken.address,
                    alice,
                    callbackFunctionIndex.AUTHORIZE_FLOW_OPERATOR_WITH_FULL_CONTROL,
                    flowRate,
                    "0x"
                );

            const flowPermissionsCheck =
                await superTokenLibCFAMock.getFlowPermissionsTest(
                    superToken.address,
                    superTokenLibCFAMock.address,
                    alice
                );
            assert.equal(
                flowPermissionsCheck.flowRateAllowance.toString(),
                flowRate
            );
            assert.equal(flowPermissionsCheck.allowCreate, true);
            assert.equal(flowPermissionsCheck.allowUpdate, true);
            assert.equal(flowPermissionsCheck.allowDelete, true);
        });

        it("2.22 - Can decrease flow allowance with permissions", async () => {
            await superTokenLibCFAMock
                .connect(aliceSigner)
                .increaseFlowRateAllowanceTest(
                    superToken.address,
                    alice,
                    flowRate
                );

            await superTokenLibCFAMock
                .connect(aliceSigner)
                .decreaseFlowRateAllowanceWithPermissionsTest(
                    superToken.address,
                    alice,
                    callbackFunctionIndex.AUTHORIZE_FLOW_OPERATOR_WITH_FULL_CONTROL,
                    flowRate
                );

            const flowPermissionsCheck =
                await superTokenLibCFAMock.getFlowPermissionsTest(
                    superToken.address,
                    superTokenLibCFAMock.address,
                    alice
                );
            assert.equal(
                flowPermissionsCheck.flowRateAllowance.toString(),
                "0"
            );
            assert.equal(flowPermissionsCheck.allowCreate, false);
            assert.equal(flowPermissionsCheck.allowUpdate, false);
            assert.equal(flowPermissionsCheck.allowDelete, false);
        });

        it("2.23 - Can decrease flow allowance with permissions with user data", async () => {
            await superTokenLibCFAMock
                .connect(aliceSigner)
                .increaseFlowRateAllowanceTest(
                    superToken.address,
                    alice,
                    flowRate
                );

            await superTokenLibCFAMock
                .connect(aliceSigner)
                .decreaseFlowRateAllowanceWithPermissionsWithUserDataTest(
                    superToken.address,
                    alice,
                    callbackFunctionIndex.AUTHORIZE_FLOW_OPERATOR_WITH_FULL_CONTROL,
                    flowRate,
                    "0x"
                );

            const flowPermissionsCheck =
                await superTokenLibCFAMock.getFlowPermissionsTest(
                    superToken.address,
                    superTokenLibCFAMock.address,
                    alice
                );
            assert.equal(
                flowPermissionsCheck.flowRateAllowance.toString(),
                "0"
            );
            assert.equal(flowPermissionsCheck.allowCreate, false);
            assert.equal(flowPermissionsCheck.allowUpdate, false);
            assert.equal(flowPermissionsCheck.allowDelete, false);
        });
    });
});
