import {BigNumber, BigNumberish} from "ethers";
import {ethers} from "hardhat";

export const toBN = (x: any) => ethers.BigNumber.from(x);

export const toWad = (x: any) => ethers.utils.parseUnits(x.toString(), 18);

/** Format a wad rounded to `decimals` fractional digits. */
export const wad4human = (wad: BigNumberish, decimals = 5) =>
    Number(ethers.utils.formatUnits(wad, 18)).toFixed(decimals);

export const toDecimals = (x: string | number, decimals: number) =>
    ethers.utils.parseUnits(x.toString(), decimals).toString();

export const max = (a: BigNumber, b: BigNumber) => (a.gt(b) ? a : b);
export const min = (a: BigNumber, b: BigNumber) => (a.gt(b) ? b : a);

export const keccak256 = (x: string) =>
    ethers.utils.keccak256(ethers.utils.toUtf8Bytes(x));
