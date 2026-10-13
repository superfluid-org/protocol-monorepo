import {ethers} from "hardhat";

import {CallUtilsMock, CallUtilsTester} from "../../../typechain-types";
import TestEnvironment from "../../TestEnvironment";
import {expectRevertedWith} from "../../utils/expectRevert";

describe("CallUtils", function () {
    const t = TestEnvironment.getSingleton();

    let callUtilsMock: CallUtilsMock;
    let callUtilsTester: CallUtilsTester;

    before(async () => {
        await t.beforeTestSuite({
            nAccounts: 5,
        });
        const CallUtilsMockFactory =
            await ethers.getContractFactory("CallUtilsMock");
        callUtilsMock = await CallUtilsMockFactory.deploy();

        const CallUtilsTesterFactory =
            await ethers.getContractFactory("CallUtilsTester");
        callUtilsTester = await CallUtilsTesterFactory.deploy();
    });

    beforeEach(async function () {
        t.beforeEachTestCaseBenchmark(this);
    });

    afterEach(() => {
        t.afterEachTestCaseBenchmark();
    });

    it("CallUtils.revertFromReturnedData", async () => {
        await expectRevertedWith(
            callUtilsMock.revertTest("revertEmpty()"),
            "CallUtils: target revert()"
        );

        await expectRevertedWith(
            callUtilsMock.revertTest("revertAssert()"),
            "CallUtils: target panicked: 0x01"
        );

        await expectRevertedWith(
            callUtilsMock.revertTest("revertOverflow()"),
            "CallUtils: target panicked: 0x11"
        );

        await expectRevertedWith(
            callUtilsMock.revertTest("revertDivByZero()"),
            "CallUtils: target panicked: 0x12"
        );

        await expectRevertedWith(
            callUtilsMock.revertTest("revertEnum()"),
            "CallUtils: target panicked: 0x21"
        );

        await expectRevertedWith(
            callUtilsMock.revertTest("revertPop()"),
            "CallUtils: target panicked: 0x31"
        );

        await expectRevertedWith(
            callUtilsMock.revertTest("revertArrayAccess()"),
            "CallUtils: target panicked: 0x32"
        );

        await expectRevertedWith(
            callUtilsMock.revertTest("revertBigArray()"),
            "CallUtils: target panicked: 0x41"
        );

        await expectRevertedWith(
            callUtilsMock.revertTest("revertZeroInitializedFunctionPointer()"),
            "CallUtils: target panicked: 0x51"
        );

        await expectRevertedWith(
            callUtilsMock.revertTest("revertString()"),
            "gm"
        );
    });

    it("CallUtils.isValidAbiEncodedBytes", async () => {
        await callUtilsTester.testIsValidAbiEncodedBytes();
    });
});
