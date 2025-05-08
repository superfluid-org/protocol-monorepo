import { expect } from "chai";
import {
    AUTHORIZE_FULL_CONTROL,
    Operation,
    TestToken,
    TestToken__factory,
    getPerSecondFlowRateByMonth,
    toBN,
} from "../src";
import { BigNumber, Contract, ethers } from "ethers";
import { createCallAppActionOperation } from "./2_operation.test";
import { TestEnvironment, makeSuite } from "./TestEnvironment";

makeSuite("Batch Call Tests", (testEnv: TestEnvironment) => {
    it("Should throw an error when empty", async () => {
        try {
            const unsupportedOperation = new Operation(
                {} as any,
                "UNSUPPORTED"
            );
            await testEnv.sdkFramework
                .batchCall([unsupportedOperation])
                .exec(testEnv.bob);
        } catch (err: any) {
            expect(err.type).to.equal("UNSUPPORTED_OPERATION");
            expect(err.message).to.contain(
                "The operation at index 0 is unsupported"
            );
        }
    });

    it("Should throw an error when data not provided", async () => {
        const noTxnDataOperation = new Operation({} as any, "ERC20_APPROVE");
        try {
            await testEnv.sdkFramework
                .batchCall([noTxnDataOperation])
                .exec(testEnv.bob);
        } catch (err: any) {
            expect(err.type).to.equal("MISSING_TRANSACTION_PROPERTIES");
            expect(err.message).to.contain(
                "The transaction is missing the to or data property."
            );
        }
    });

    it("Should throw an error when type not provided", async () => {
        const transferOp = testEnv.wrapperSuperToken.transfer({
            receiver: testEnv.bob.address,
            amount: ethers.utils.parseUnits("1000").toString(),
        });
        const noTypeOperation = new Operation(
            transferOp.populateTransactionPromise,
            null!
        );
        try {
            await testEnv.sdkFramework
                .batchCall([noTypeOperation])
                .exec(testEnv.bob);
        } catch (err: any) {
            expect(err.type).to.equal("UNSUPPORTED_OPERATION");
            expect(err.message).to.contain(
                "The operation at index 0 is unsupported"
            );
        }
    });

    it("Should throw an error on unsupported operations", async () => {
        const transferOp = testEnv.wrapperSuperToken.transfer({
            receiver: testEnv.bob.address,
            amount: ethers.utils.parseUnits("1000").toString(),
        });
        const batchCall = testEnv.sdkFramework.batchCall([transferOp]);

        try {
            const promises = batchCall.getOperationStructArrayPromises;
            await Promise.all(promises);
        } catch (err: any) {
            expect(err.message).to.not.be.undefined;
            expect(err.cause).to.be.undefined;
        }
    });

    it("Should throw an error when amount not provided ERC20 approve", async () => {
        const approveOp = testEnv.wrapperSuperToken.approve({
            receiver: testEnv.bob.address,
        } as any);
        try {
            await testEnv.sdkFramework.batchCall([approveOp]).exec(testEnv.bob);
        } catch (err: any) {
            expect(err.message).to.not.be.undefined;
        }
    });

    it("Should throw an error when sender not provided ERC20 transferFrom", async () => {
        const amount = ethers.utils.parseUnits("1000").toString();
        const transferFromOp = testEnv.wrapperSuperToken.transferFrom({
            receiver: testEnv.bob.address,
            amount,
        } as any);
        try {
            await testEnv.sdkFramework
                .batchCall([transferFromOp])
                .exec(testEnv.bob);
        } catch (err: any) {
            expect(err.message).to.not.be.undefined;
        }
    });

    it("Should throw an error if batch call fails", async () => {
        const createFlowOp = testEnv.wrapperSuperToken.createFlow({
            sender: testEnv.bob.address,
            receiver: testEnv.alice.address,
            flowRate: getPerSecondFlowRateByMonth("10000"),
        });
        try {
            await testEnv.sdkFramework
                .batchCall([createFlowOp])
                .exec(testEnv.alice);
        } catch (err: any) {
            expect(err.message).to.not.be.undefined;
        }
    });

    it("Should throw an error if amount not provided for upgrade", async () => {
        const upgradeOp = testEnv.wrapperSuperToken.upgrade({} as any);
        try {
            await testEnv.sdkFramework
                .batchCall([upgradeOp])
                .exec(testEnv.alice);
        } catch (err: any) {
            expect(err.message).to.not.be.undefined;
        }
    });

    it("Should throw an error if attempting to batch no operations", async () => {
        try {
            await testEnv.sdkFramework.batchCall([]).exec(testEnv.alice);
        } catch (err: any) {
            expect(err.message).to.not.be.undefined;
        }
    });

    it("Should be able to create and execute a batch call (approve + transferFrom)", async () => {
        const amount = ethers.utils.parseUnits("1000").toString();
        const approveOp = testEnv.wrapperSuperToken.approve({
            receiver: testEnv.bob.address,
            amount,
        });
        const transferFromOp = testEnv.wrapperSuperToken.transferFrom({
            sender: testEnv.alice.address,
            receiver: testEnv.bob.address,
            amount,
        });
        const batchCall = testEnv.sdkFramework.batchCall([
            approveOp,
            transferFromOp,
        ]);
        await expect(batchCall.exec(testEnv.alice))
            .to.emit(
                testEnv.wrapperSuperToken.contract.connect(testEnv.alice),
                "Transfer"
            )
            .withArgs(testEnv.alice.address, testEnv.bob.address, amount);
    });

    it("Should be able to batch erc777 send wrapper super token", async () => {
        const amount = ethers.utils.parseUnits("1000").toString();
        const sendOp = testEnv.pureSuperToken.send({
            recipient: testEnv.bob.address,
            amount,
        });
        const batchCall = testEnv.sdkFramework.batchCall([sendOp]);

        await expect(batchCall.exec(testEnv.alice))
            .to.emit(
                testEnv.pureSuperToken.contract.connect(testEnv.alice),
                "Transfer"
            )
            .withArgs(testEnv.alice.address, testEnv.bob.address, amount);
    });

    it("Should be able to batch erc777 send pure super token", async () => {
        const amount = ethers.utils.parseUnits("1000").toString();
        const sendOp = testEnv.pureSuperToken.send({
            recipient: testEnv.bob.address,
            amount,
        });
        const batchCall = testEnv.sdkFramework.batchCall([sendOp]);

        await expect(batchCall.exec(testEnv.alice))
            .to.emit(
                testEnv.pureSuperToken.contract.connect(testEnv.alice),
                "Transfer"
            )
            .withArgs(testEnv.alice.address, testEnv.bob.address, amount);
    });

    it("Should be able to batch erc777 send native asset super token", async () => {
        const amount = ethers.utils.parseUnits("10").toString();
        const sendOp = testEnv.nativeAssetSuperToken.send({
            recipient: testEnv.bob.address,
            amount,
        });
        const batchCall = testEnv.sdkFramework.batchCall([sendOp]);
        await expect(batchCall.exec(testEnv.alice))
            .to.emit(
                testEnv.nativeAssetSuperToken.contract.connect(testEnv.alice),
                "Transfer"
            )
            .withArgs(testEnv.alice.address, testEnv.bob.address, amount);
    });

    it("Should be able to batch create flows and batch update flows and batch delete flows", async () => {
        let flowRate = getPerSecondFlowRateByMonth("10000");
        const createFlow1 = testEnv.wrapperSuperToken.createFlow({
            sender: testEnv.charlie.address,
            receiver: testEnv.bob.address,
            flowRate,
        });
        const createFlow2 = testEnv.wrapperSuperToken.createFlow({
            sender: testEnv.charlie.address,
            receiver: testEnv.alice.address,
            flowRate,
        });
        await testEnv.sdkFramework
            .batchCall([createFlow1, createFlow2])
            .exec(testEnv.charlie);

        flowRate = getPerSecondFlowRateByMonth("12500");

        const updateFlow1 = testEnv.wrapperSuperToken.updateFlow({
            sender: testEnv.charlie.address,
            receiver: testEnv.bob.address,
            flowRate,
        });
        const updateFlow2 = testEnv.wrapperSuperToken.updateFlow({
            sender: testEnv.charlie.address,
            receiver: testEnv.alice.address,
            flowRate,
        });
        await testEnv.sdkFramework
            .batchCall([updateFlow1, updateFlow2])
            .exec(testEnv.charlie);
        const deleteFlow1 = testEnv.wrapperSuperToken.deleteFlow({
            sender: testEnv.charlie.address,
            receiver: testEnv.bob.address,
        });
        const deleteFlow2 = testEnv.wrapperSuperToken.deleteFlow({
            sender: testEnv.charlie.address,
            receiver: testEnv.alice.address,
        });
        await testEnv.sdkFramework
            .batchCall([deleteFlow1, deleteFlow2])
            .exec(testEnv.charlie);
    });

    it("Should be able to create a call app action operation and execute from batch call", async () => {
        const NEW_VAL = 69;
        const { superAppTester, operation } =
            await createCallAppActionOperation(
                testEnv.alice,
                testEnv.sdkFramework,
                NEW_VAL
            );
        await testEnv.sdkFramework.batchCall([operation]).exec(testEnv.alice);
        expect(await superAppTester.val()).to.equal("69");
    });

    it("Should be able to create a increaseAllowance", async () => {
        const amount = ethers.utils.parseUnits("1000").toString();
        const increaseAllowanceOp = testEnv.wrapperSuperToken.increaseAllowance(
            {
                spender: testEnv.bob.address,
                amount,
            }
        );
        const batchCall = testEnv.sdkFramework.batchCall([increaseAllowanceOp]);
        await expect(batchCall.exec(testEnv.alice))
            .to.emit(
                testEnv.wrapperSuperToken.contract.connect(testEnv.alice),
                "Approval"
            )
            .withArgs(testEnv.alice.address, testEnv.bob.address, amount);

        const allowance = await testEnv.wrapperSuperToken.allowance({
            owner: testEnv.alice.address,
            spender: testEnv.bob.address,
            providerOrSigner: testEnv.alice,
        });
        expect(allowance).to.equal(amount);
    });

    it("Should be able to create a decreaseAllowance", async () => {
        const increaseAmount = ethers.utils.parseUnits("100").toString();
        const finalAllowance = ethers.utils.parseUnits("69").toString();
        await testEnv.wrapperSuperToken
            .increaseAllowance({
                spender: testEnv.bob.address,
                amount: increaseAmount,
            })
            .exec(testEnv.alice);
        const decreaseAmount = ethers.utils.parseUnits("31").toString();
        const decreaseAllowanceOp = testEnv.wrapperSuperToken.decreaseAllowance(
            {
                spender: testEnv.bob.address,
                amount: decreaseAmount,
            }
        );
        const batchCall = testEnv.sdkFramework.batchCall([decreaseAllowanceOp]);
        await expect(batchCall.exec(testEnv.alice))
            .to.emit(
                testEnv.wrapperSuperToken.contract.connect(testEnv.alice),
                "Approval"
            )
            .withArgs(
                testEnv.alice.address,
                testEnv.bob.address,
                finalAllowance
            );

        const allowance = await testEnv.wrapperSuperToken.allowance({
            owner: testEnv.alice.address,
            spender: testEnv.bob.address,
            providerOrSigner: testEnv.alice,
        });

        expect(allowance).to.equal(finalAllowance);
    });

    it("Should be able to create a batch call with both increaseAllowance and decreaseAllowance", async () => {
        const increaseAmount = ethers.utils.parseUnits("100").toString();
        const finalAllowance = ethers.utils.parseUnits("169").toString();
        await testEnv.wrapperSuperToken
            .increaseAllowance({
                spender: testEnv.bob.address,
                amount: increaseAmount,
            })
            .exec(testEnv.alice);
        const decreaseAmount = ethers.utils.parseUnits("31").toString();
        const decreaseAllowanceOp = testEnv.wrapperSuperToken.decreaseAllowance(
            {
                spender: testEnv.bob.address,
                amount: decreaseAmount,
            }
        );
        const increaseAllowanceOp = testEnv.wrapperSuperToken.increaseAllowance(
            {
                spender: testEnv.bob.address,
                amount: increaseAmount,
            }
        );
        await testEnv.sdkFramework
            .batchCall([decreaseAllowanceOp, increaseAllowanceOp])
            .exec(testEnv.alice);

        const allowance = await testEnv.wrapperSuperToken.allowance({
            owner: testEnv.alice.address,
            spender: testEnv.bob.address,
            providerOrSigner: testEnv.alice,
        });

        expect(allowance).to.equal(finalAllowance);
    });

    it("Should be able to batch multiple increase/decrease flow rate allowance operations", async () => {
        const flowRateAllowanceDelta = getPerSecondFlowRateByMonth("100");
        const permissions = AUTHORIZE_FULL_CONTROL;
        const sender = testEnv.alice;
        const flowOperator = testEnv.bob;

        const flowOperatorDataBefore =
            await testEnv.wrapperSuperToken.getFlowOperatorData({
                sender: sender.address,
                flowOperator: flowOperator.address,
                providerOrSigner: sender,
            });
        const increaseAllowanceOp =
            testEnv.wrapperSuperToken.increaseFlowRateAllowanceWithPermissions({
                flowRateAllowanceDelta,
                flowOperator: flowOperator.address,
                permissionsDelta: permissions,
            });
        const decreaseFlowRateAllowanceDelta =
            getPerSecondFlowRateByMonth("31");
        const decreaseAllowanceOp =
            testEnv.wrapperSuperToken.decreaseFlowRateAllowanceWithPermissions({
                flowRateAllowanceDelta: decreaseFlowRateAllowanceDelta,
                flowOperator: flowOperator.address,
                permissionsDelta: permissions,
            });
        await testEnv.sdkFramework
            .batchCall([increaseAllowanceOp, decreaseAllowanceOp])
            .exec(sender);

        const flowOperatorDataAfter =
            await testEnv.wrapperSuperToken.getFlowOperatorData({
                sender: sender.address,
                flowOperator: flowOperator.address,
                providerOrSigner: sender,
            });
        expect(flowOperatorDataAfter.flowRateAllowance).to.equal(
            toBN(flowOperatorDataBefore.flowRateAllowance)
                .add(toBN(flowRateAllowanceDelta))
                .sub(toBN(decreaseFlowRateAllowanceDelta))
                .toString()
        );

        // we remove all permissions after
        expect(flowOperatorDataAfter.permissions).to.equal(
            "0"
        );
    });


    it("Should be able to execute SimpleForwarder batch call", async () => {
        const contract = (new Contract(
            testEnv.wrapperSuperToken.underlyingToken.address,
            TestToken__factory.abi
        ) as TestToken).connect(testEnv.alice);

        const beforeBalance = await contract.balanceOf(testEnv.alice.address);

        const txn1 = contract
            .populateTransaction.mint(
                testEnv.alice.address,
                "100"
            );
        const txn2 = contract
            .populateTransaction.mint(
                testEnv.alice.address,
                "200"
            );

        const operation1 = testEnv.sdkFramework.operation(
            txn1,
            "SIMPLE_FORWARD_CALL"
        );
        const operation2 = testEnv.sdkFramework.operation(
            txn2,
            "SIMPLE_FORWARD_CALL"
        );

        const batchCall = testEnv.sdkFramework.batchCall(
            [
                operation1,
                operation2
            ]
        );

        const txResponse = await batchCall.exec(testEnv.alice);
        const txReceipt = await txResponse.wait();
        expect(txReceipt.status).to.equal(1);

        const afterBalance = await contract.balanceOf(testEnv.alice.address);

        expect(beforeBalance.lt(afterBalance)).to.be.true;
        expect(afterBalance.sub(BigNumber.from(300)).eq(beforeBalance)).to.be.true;
    });

    it("Should be able to move ETH value", async () => {
        const value = BigNumber.from(Number(0.1e18).toString());

        const beforeBalanceAlice = await testEnv.alice.getBalance();
        const beforeBalanceBob = await testEnv.bob.getBalance();

        expect(beforeBalanceAlice.gt(value)).to.be.true;

        const operation = testEnv.sdkFramework.operation(
            testEnv.alice.populateTransaction({
                to: testEnv.bob.address,
                value,
                data: "0x"
            }) as Promise<ethers.PopulatedTransaction>,
            "SIMPLE_FORWARD_CALL"
        );

        const batchCall = testEnv.sdkFramework.batchCall(
            [
                operation
            ]
        );

        const txn = await batchCall.exec(testEnv.alice, 2);

        const txReceipt = await txn.wait();
        expect(txReceipt.status).to.equal(1);

        const afterBalanceAlice = await testEnv.alice.getBalance();
        const afterBalanceBob = await testEnv.bob.getBalance();

        expect(afterBalanceBob.sub(beforeBalanceBob)).to.equal(value);
        expect(beforeBalanceAlice.sub(afterBalanceAlice).gte(value)).to.be.true;
    });

    it("Should throw an error when multiple Operations with ETH value", async () => {
        const operation1 = testEnv.sdkFramework.operation(
            testEnv.alice.populateTransaction({
                to: testEnv.bob.address,
                value: BigNumber.from(Number(0.1e18).toString()),
                data: "0x"
            }) as Promise<ethers.PopulatedTransaction>,
            "SIMPLE_FORWARD_CALL"
        );

        const operation2 = testEnv.sdkFramework.operation(
            testEnv.alice.populateTransaction({
                to: testEnv.bob.address,
                value: BigNumber.from(Number(0.2e18).toString()),
                data: "0x"
            }) as Promise<ethers.PopulatedTransaction>,
            "SIMPLE_FORWARD_CALL"
        );

        const batchCall = testEnv.sdkFramework.batchCall(
            [
                operation1,
                operation2
            ]
        );
        
        await expect(batchCall.exec(testEnv.alice, 2))
            .to.be.rejectedWith("multiple values in the batch call");
    });
});
