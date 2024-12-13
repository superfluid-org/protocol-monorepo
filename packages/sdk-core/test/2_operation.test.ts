import { expect } from "chai";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { Framework } from "../src/index";
import { getPerSecondFlowRateByMonth } from "../src";
import { IConstantFlowAgreementV1__factory } from "../src/typechain-types";
import Operation from "../src/Operation";
import hre from "hardhat";
import { SuperAppTester } from "../typechain-types";
import { SuperAppTester__factory } from "../typechain-types";
const cfaInterface = IConstantFlowAgreementV1__factory.createInterface();
import { TestEnvironment, makeSuite } from "./TestEnvironment";
import { BigNumber, ethers } from "ethers";
import multiplyGasLimit from "../src/multiplyGasLimit";

/**
 * Create a simple call app action (setVal) operation with the SuperAppTester contract.
 * @param deployer
 * @param framework
 * @returns Operation
 */
export const createCallAppActionOperation = async (
    deployer: SignerWithAddress,
    framework: Framework,
    val: number,
    overrides?: ethers.Overrides
) => {
    const SuperAppTesterFactory = await hre.ethers.getContractFactory(
        "SuperAppTester",
        deployer
    );
    let superAppTester = (await SuperAppTesterFactory.deploy(
        framework.contracts.host.address
    )) as SuperAppTester;

    const superAppTesterInterface = SuperAppTester__factory.createInterface();
    superAppTester = (await superAppTester.deployed()).connect(deployer);

    // initial val will be 0 when contract is initialized
    expect(await superAppTester.val()).to.equal("0");

    const callData = superAppTesterInterface.encodeFunctionData("setVal", [
        val,
        "0x",
    ]);
    return {
        operation: framework.host.callAppAction(
            superAppTester.address,
            callData,
            overrides
        ),
        superAppTester,
    };
};

makeSuite("Operation Tests", (testEnv: TestEnvironment) => {
    describe("Revert cases", () => {
        it("Should fail if gas limit used is far below estimation.", async () => {
            const NEW_VAL = 69;
            const { operation } = await createCallAppActionOperation(
                testEnv.alice,
                testEnv.sdkFramework,
                NEW_VAL
            );
            try {
                await operation.exec(testEnv.alice, 0.25);
            } catch (err) {
                expect(err.message).to.not.be.undefined;
            }
        });
    });

    describe("Happy Path Tests", () => {
        it("Should be able to get transaction hash and it should be equal to transaction hash once executed", async () => {
            const revokeControlOp =
                testEnv.sdkFramework.cfaV1.revokeFlowOperatorWithFullControl({
                    superToken: testEnv.wrapperSuperToken.address,
                    flowOperator: testEnv.bob.address,
                });
            const signer = testEnv.sdkFramework.createSigner({
                privateKey: testEnv.constants.HARDHAT_PRIVATE_KEY,
                provider: testEnv.alice.provider,
            });
            const opTxnHash = await revokeControlOp.getTransactionHash(signer);
            const executedTxn = await revokeControlOp.exec(signer);
            const receipt = await executedTxn.wait();
            expect(opTxnHash).to.equal(receipt.transactionHash);
        });

        it("Should be able to create an operation from framework.", async () => {
            const callData = cfaInterface.encodeFunctionData("createFlow", [
                testEnv.wrapperSuperToken.address,
                testEnv.bob.address,
                getPerSecondFlowRateByMonth("100"),
                "0x",
            ]);
            const txn =
                testEnv.sdkFramework.host.contract.populateTransaction.callAgreement(
                    testEnv.cfaV1.address,
                    callData,
                    "0x"
                );
            const operation = testEnv.sdkFramework.operation(
                txn,
                "SUPERFLUID_CALL_AGREEMENT"
            );
            await operation.exec(testEnv.alice);
        });

        it("Should be able to create an operation from framework and execute from batch call.", async () => {
            const callData = cfaInterface.encodeFunctionData("createFlow", [
                testEnv.wrapperSuperToken.address,
                testEnv.bob.address,
                getPerSecondFlowRateByMonth("100"),
                "0x",
            ]);
            const txn =
                testEnv.sdkFramework.host.contract.populateTransaction.callAgreement(
                    testEnv.cfaV1.address,
                    callData,
                    "0x"
                );
            const operation = testEnv.sdkFramework.operation(
                txn,
                "SUPERFLUID_CALL_AGREEMENT"
            );
            await testEnv.sdkFramework
                .batchCall([operation])
                .exec(testEnv.alice);
        });

        it("Should be able to create a call app action operation", async () => {
            const NEW_VAL = 69;
            const { superAppTester, operation } =
                await createCallAppActionOperation(
                    testEnv.alice,
                    testEnv.sdkFramework,
                    NEW_VAL
                );
            await operation.exec(testEnv.alice, 1);
            expect(await superAppTester.val()).to.equal(NEW_VAL.toString());
        });

        it("Should be able to use arbitrary gas estimation limit", async () => {
            const GAS_MULTIPLIER = 2;

            const { operation } = await createCallAppActionOperation(
                testEnv.alice,
                testEnv.sdkFramework,
                420
            );

            const populatedTxn = await operation.populateTransactionPromise;
            const estimatedGas = await testEnv.alice.estimateGas(populatedTxn);

            const callAppActionTxn = await operation.exec(
                testEnv.alice,
                GAS_MULTIPLIER
            );

            expect(callAppActionTxn.gasLimit).to.equal(
                multiplyGasLimit(estimatedGas, GAS_MULTIPLIER)
            );
        });

        it("Should not apply multiplier to Overrides gas limit", async () => {
            const NEW_VAL = 69;
            const { operation } = await createCallAppActionOperation(
                testEnv.alice,
                testEnv.sdkFramework,
                NEW_VAL,
                { gasLimit: 500000 }
            );
            const txn = await operation.exec(testEnv.alice, 2);
            expect(txn.gasLimit).to.equal("500000");
        });

        it("Should move ETH value passed from the Overrides", async () => {
            const value = BigNumber.from(Number(0.1e18).toString());

            const beforeBalanceAlice = await testEnv.alice.getBalance();
            const beforeBalanceBob = await testEnv.bob.getBalance();

            expect(beforeBalanceAlice.gt(value)).to.be.true;

            const operation = testEnv.sdkFramework.operation(
                testEnv.alice.populateTransaction({
                    to: testEnv.bob.address,
                    value
                }) as Promise<ethers.PopulatedTransaction>,
                "SIMPLE_FORWARD_CALL"
            );

            const txn = await operation.exec(testEnv.alice, 2);
            const txReceipt = await txn.wait();
            expect(txReceipt.status).to.equal(1);

            const afterBalanceAlice = await testEnv.alice.getBalance();
            const afterBalanceBob = await testEnv.bob.getBalance();

            expect(afterBalanceBob.sub(beforeBalanceBob)).to.equal(value);
            expect(beforeBalanceAlice.sub(afterBalanceAlice).gte(value)).to.be.true;
        });

        it("Should throw an error when trying to execute a transaction with faulty callData", async () => {
            const callData = cfaInterface.encodeFunctionData("createFlow", [
                testEnv.wrapperSuperToken.address,
                testEnv.alice.address,
                getPerSecondFlowRateByMonth("-100"),
                "0x",
            ]);
            const txn =
                testEnv.sdkFramework.host.contract.populateTransaction.callAgreement(
                    testEnv.cfaV1.address,
                    callData,
                    "0x"
                );
            const operation = new Operation(txn, "SUPERFLUID_CALL_AGREEMENT");
            try {
                await operation.exec(testEnv.alice);
            } catch (err: any) {
                expect(err.message).to.contain("cannot estimate gas");
            }
        });

        it("Should throw error when trying to sign a transaction", async () => {
            const operation = testEnv.sdkFramework.cfaV1.createFlow({
                flowRate: getPerSecondFlowRateByMonth("100"),
                receiver: testEnv.charlie.address,
                superToken: testEnv.wrapperSuperToken.address,
                sender: testEnv.alice.address,
            });
            try {
                await operation.getSignedTransaction(testEnv.bob);
            } catch (err: any) {
                expect(err.message).to.not.be.null;
            }
        });

        context(
            "Should be able to get and execute a signed transaction",
            async () => {
                async function shouldExecuteSignedTransaction(
                    shouldUseCallAgreement: boolean
                ) {
                    const flowRate = getPerSecondFlowRateByMonth("100");
                    // NOTE: the hardhat signer does not support signing transactions, therefore, we must create
                    // our own signer with a custom private key
                    const signer = testEnv.sdkFramework.createSigner({
                        privateKey: testEnv.constants.HARDHAT_PRIVATE_KEY,
                        provider: testEnv.alice.provider,
                    });
                    const createFlowOp = testEnv.wrapperSuperToken.createFlow({
                        sender: testEnv.alice.address,
                        receiver: testEnv.bob.address,
                        flowRate,
                        shouldUseCallAgreement,
                    });
                    const signedTxn = await createFlowOp.getSignedTransaction(
                        signer
                    );
                    await expect(
                        testEnv.alice.provider!.sendTransaction(signedTxn)
                    )
                        .to.emit(testEnv.cfaV1, "FlowUpdated")
                        .withArgs(
                            testEnv.wrapperSuperToken.address,
                            testEnv.alice.address,
                            testEnv.bob.address,
                            Number(flowRate),
                            Number(flowRate) * -1,
                            Number(flowRate),
                            "0x"
                        );
                }

                it("With Call Agreement", async () => {
                    await shouldExecuteSignedTransaction(true);
                });

                it("With Forwarder", async () => {
                    await shouldExecuteSignedTransaction(false);
                });
            }
        );
    });
});
