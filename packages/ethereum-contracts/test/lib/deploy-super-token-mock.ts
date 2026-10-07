import {ethers} from "hardhat";

import {SuperTokenMock, TestToken} from "../../typechain-types";
import TestEnvironment from "../TestEnvironment";

import {createERC20Wrapper} from "./super-token-factory";

const mintAmount = ethers.utils.parseUnits("1000000000", 18);

/**
 * Deploy an isolated SuperToken wrapper (via factory) for per-test CFA / forwarder use.
 * Optionally upgrades balances for the given accounts.
 */
export const deploySuperTokenAndNFTContractsAndInitialize = async (
    t: TestEnvironment,
    fundAccounts: string[] = []
) => {
    const admin = t.aliases.admin || (await ethers.getSigners())[0].address;
    const suffix = Math.floor(Math.random() * 1e6).toString(36);
    const symbol = `T${suffix}`.slice(0, 5).toUpperCase();

    const testToken = (await (
        await ethers.getContractFactory("TestToken")
    ).deploy(`Temp ${symbol}`, symbol, 18, mintAmount)) as TestToken;
    await testToken.deployed();

    const superToken = (await createERC20Wrapper(
        t.contracts.superfluid,
        testToken,
        {
            superTokenName: `Super ${symbol}`,
            superTokenSymbol: `${symbol}x`,
            from: admin,
        }
    )) as unknown as SuperTokenMock;

    const accountsToFund = fundAccounts.length > 0 ? fundAccounts : [];
    for (const account of accountsToFund) {
        const signer = await ethers.getSigner(account);
        await testToken.connect(signer).mint(account, mintAmount);
        await testToken
            .connect(signer)
            .approve(superToken.address, ethers.constants.MaxUint256);
        await superToken.connect(signer).upgrade(mintAmount);
    }

    return superToken;
};

/** Raw SuperTokenMock for library tests that rely on mintInternal. */
export const deployRawSuperTokenMock = async (t: TestEnvironment) => {
    const {poolAdminNFTProxy} = await t.deployNFTContracts();
    return t.deployContract<SuperTokenMock>(
        "SuperTokenMock",
        t.contracts.superfluid.address,
        "69",
        poolAdminNFTProxy.address
    );
};
