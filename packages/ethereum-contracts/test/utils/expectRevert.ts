import {Contract} from "ethers";
import {expect} from "hardhat";

export const expectRevertedWith = async (
    func: Promise<any>,
    errMsg: string
) => {
    await expect(func).to.be.revertedWith(errMsg);
};
export const expectReverted = async (func: Promise<any>) =>
    expect(func).to.be.reverted;

export const expectCustomError = async (
    func: Promise<any>,
    contract: Contract,
    customErrorString: string,
    args?: any
) => {
    const expectation = expect(func).to.be.revertedWithCustomError(contract, customErrorString);
    args ? await expectation.withArgs(...(Array.isArray(args) ? args : [args])) : await expectation;
};
