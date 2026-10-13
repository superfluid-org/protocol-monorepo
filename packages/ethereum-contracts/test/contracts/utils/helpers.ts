import {BigNumber, BigNumberish} from "ethers";
import {ethers} from "hardhat";

export const toBN = (x: any) => ethers.BigNumber.from(x);

export const toWad = (x: any) => ethers.utils.parseUnits(x.toString(), 18);

export const wad4human = (x: ethers.BigNumberish, decimals = 18) =>
    ethers.utils.formatUnits(x, decimals);

export const toDecimals = (x: string | number, decimals: number) =>
    ethers.utils.parseUnits(x.toString(), decimals);

export const max = (a: BigNumber, b: BigNumber) => (a.gt(b) ? a : b);
export const min = (a: BigNumber, b: BigNumber) => (a.gt(b) ? b : a);

export const keccak256 = (x: string) =>
    ethers.utils.keccak256(ethers.utils.toUtf8Bytes(x));

/** web3.utils.sha3 equivalent (keccak256 of utf8 string). */
export const sha3 = (input: string) => ethers.utils.id(input);

export const soliditySha3 = (...args: unknown[]) => {
    if (args.length === 1 && typeof args[0] === "string") {
        return ethers.utils.id(args[0]);
    }
    const types = args.filter((_, i) => i % 2 === 0) as string[];
    const values = args.filter((_, i) => i % 2 === 1);
    return ethers.utils.solidityKeccak256(types, values);
};

export const encodeAbiParameter = (type: string, value: unknown) =>
    ethers.utils.defaultAbiCoder.encode([type], [value]);

export const encodeAbiParameters = (types: string[], values: unknown[]) =>
    ethers.utils.defaultAbiCoder.encode(types, values);
