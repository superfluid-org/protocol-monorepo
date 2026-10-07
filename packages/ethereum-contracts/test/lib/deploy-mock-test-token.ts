import {ethers} from "hardhat";

import {
    Resolver,
    SuperfluidMock,
    SuperTokenMock,
    TestToken,
} from "../../typechain-types";

import {loggedTx} from "./logged-tx";
import {createERC20Wrapper} from "./super-token-factory";

/** Deploy TEST underlying + SuperTokenMock wrapper and register in resolver. */
export async function deployMockTestToken(
    resolver: Resolver,
    superfluid: SuperfluidMock,
    tokenSymbol: string,
    admin: string,
    decimals = 18
) {
    const mintLimit = ethers.BigNumber.from(2).pow(100);
    const testToken = (await (
        await ethers.getContractFactory("TestToken")
    ).deploy(
        `${tokenSymbol} Fake Token`,
        tokenSymbol,
        decimals,
        mintLimit
    )) as TestToken;
    await testToken.deployed();

    await loggedTx(`resolver.set tokens.${tokenSymbol}`, () =>
        resolver.set(`tokens.${tokenSymbol}`, testToken.address)
    );

    const releaseVersion = process.env.RELEASE_VERSION || "test";
    const superTokenKey = `supertokens.${releaseVersion}.${tokenSymbol}x`;

    const superToken = (await createERC20Wrapper(superfluid, testToken, {
        superTokenName: `Super ${tokenSymbol} Fake Token`,
        superTokenSymbol: `${tokenSymbol}x`,
        from: admin,
    })) as unknown as SuperTokenMock;

    await loggedTx(`resolver.set ${superTokenKey}`, () =>
        resolver.set(superTokenKey, superToken.address)
    );

    return {testToken, superToken};
}
