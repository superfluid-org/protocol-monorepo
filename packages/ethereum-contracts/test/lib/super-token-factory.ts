import {BigNumberish, Signer} from "ethers";
import {ethers} from "hardhat";

import {
    IERC20Metadata,
    ISuperTokenFactory,
    SuperfluidMock,
    SuperTokenMock,
} from "../../typechain-types";

export type CreateERC20WrapperOptions = {
    superTokenName?: string;
    superTokenSymbol?: string;
    from?: string;
    /** 0 non-upgradable, 1 semi, 2 full (default 1) */
    upgradability?: BigNumberish;
};

/** Ethers replacement for js-sdk Framework.createERC20Wrapper. */
export async function createERC20Wrapper(
    superfluid: SuperfluidMock,
    token: IERC20Metadata,
    {
        superTokenName,
        superTokenSymbol,
        from,
        upgradability = 1,
    }: CreateERC20WrapperOptions = {}
) {
    const tokenName = await token.name();
    const tokenSymbol = await token.symbol();
    superTokenName = superTokenName ?? `Super ${tokenName}`;
    superTokenSymbol = superTokenSymbol ?? `${tokenSymbol}x`;

    const factoryAddress = await superfluid.getSuperTokenFactory();
    const factory = (await ethers.getContractAt(
        "ISuperTokenFactory",
        factoryAddress
    )) as ISuperTokenFactory;

    const signer = from
        ? await ethers.getSigner(from)
        : (await ethers.getSigners())[0];

    const connected = factory.connect(signer as Signer);
    const callData = connected.interface.encodeFunctionData(
        "createERC20Wrapper(address,uint8,string,string)",
        [token.address, upgradability, superTokenName, superTokenSymbol]
    );
    const staticResult = await (signer as Signer).call({
        to: factoryAddress,
        data: callData,
    });
    const wrapperAddress = connected.interface.decodeFunctionResult(
        "createERC20Wrapper(address,uint8,string,string)",
        staticResult
    )[0] as string;
    const txResponse = await connected[
        "createERC20Wrapper(address,uint8,string,string)"
    ](token.address, upgradability, superTokenName, superTokenSymbol);
    const receipt = await txResponse.wait();

    console.log(`super token ${superTokenSymbol} created at ${wrapperAddress}`);

    const superToken = (await ethers.getContractAt(
        "SuperTokenMock",
        wrapperAddress
    )) as SuperTokenMock;

    return Object.assign(superToken, {
        tx: {
            receipt,
            transactionHash: receipt.transactionHash,
        },
    });
}
