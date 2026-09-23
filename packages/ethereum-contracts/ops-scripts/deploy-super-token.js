const SuperfluidSDK = require("@superfluid-finance/js-sdk");

const {
    getScriptRunnerFactory: S,
    ZERO_ADDRESS,
    extractWeb3Options,
    builtTruffleContractLoader,
    sendGovernanceAction,
} = require("./libs/common");

/**
 * @dev Deploy a listed super token (wrapper for ERC20 or native token) to the network.
 * @param {Array} argv Overriding command line arguments
 * @param {boolean} options.isTruffle Whether the script is used within native truffle framework
 * @param {Web3} options.web3  Injected web3 instance
 * @param {Address} options.from Address to deploy contracts from
 * @param {string} options.protocolReleaseVersion Specify the protocol release version to be used
 *
 * Usage: npx truffle exec ops-scripts/deploy-super-token.js : {UNDERLYING_TOKEN_SYMBOL_OR_ADDRESS}
 *
 * NOTE:
 * - If the `UNDERLYING_TOKEN_SYMBOL_OR_ADDRESS` is the ZERO_ADDRESS or the (known) native token symbol
 *   of the network, then the SETH contract will be deployed.
 *   If the name of the network's native token isn't known by the framework, it can be provided
 *   via ENV var NATIVE_TOKEN_SYMBOL.
 * - Otherwise an ERC20 super token wrapper will be created for the underlying ERC20 token specified in
 *   UNDERLYING_TOKEN_SYMBOL_OR_ADDRESS. A symbol must already be registered in the resolver as
 *   `tokens.${UNDERLYING_TOKEN_SYMBOL}`. An address is used directly and does not need a resolver entry.
 * - A resolver entry `supertokens.${protocolReleaseVersion}.${UNDERLYING_TOKEN_SYMBOL}x` will be created
 *   for the super token address.
 * - The caller needs to have permission to set resolver entries.
 */
module.exports = eval(`(${S.toString()})()`)(async function (
    args,
    options = {}
) {
    console.log("======== Deploying super token ========");
    let {resetToken, protocolReleaseVersion} = options;

    if (args.length !== 1) {
        throw new Error("Wrong number of arguments");
    }
    const tokenSymbolOrAddress = args.pop();

    resetToken = resetToken || !!process.env.RESET_TOKEN;
    console.log("reset token: ", resetToken);
    console.log("protocol release version:", protocolReleaseVersion);

    const sf = new SuperfluidSDK.Framework({
        ...extractWeb3Options(options),
        version: protocolReleaseVersion,
        additionalContracts: [
            "Ownable",
            "IMultiSigWallet",
            "ISafe",
            "SuperfluidGovernanceBase",
            "Resolver",
            "UUPSProxiable",
            "SETHProxy",
            "IERC20Metadata",
        ],
        contractLoader: builtTruffleContractLoader,
    });
    await sf.initialize();

    const {
        Resolver,
        UUPSProxiable,
        IERC20Metadata,
        ISuperToken,
        ISETH,
        SETHProxy,
    } = sf.contracts;

    const superTokenFactory = await sf.contracts.ISuperTokenFactory.at(
        await sf.host.getSuperTokenFactory.call()
    );

    let tokenSymbol;
    let tokenAddress;
    let superTokenKey;
    let deploymentFn;
    if (
        tokenSymbolOrAddress === ZERO_ADDRESS ||
        tokenSymbolOrAddress === sf.config.nativeTokenSymbol
    ) {
        // deploy wrapper for the native token
        tokenSymbol =
            sf.config.nativeTokenSymbol || process.env.NATIVE_TOKEN_SYMBOL;
        if (tokenSymbol === undefined) {
            throw new Error(
                "Native token symbol unknown. You can set it with ENV var NATIVE_TOKEN_SYMBOL"
            );
        }

        superTokenKey = `supertokens.${protocolReleaseVersion}.${tokenSymbol}x`;
        deploymentFn = async () => {
            console.log("Creating SETH Proxy...");
            const sethProxy = await SETHProxy.new();
            const seth = await ISETH.at(sethProxy.address);
            console.log("Intialize SETH as a custom super token...");
            await superTokenFactory.initializeCustomSuperToken(seth.address);
            console.log("Intialize SETH token info...");
            await seth.initialize(
                ZERO_ADDRESS,
                18,
                `Super ${tokenSymbol}`,
                `${tokenSymbol}x`
            );
            return seth;
        };
    } else {
        // deploy wrapper for an ERC20 token
        const givenByAddress = web3.utils.isAddress(tokenSymbolOrAddress);
        if (givenByAddress) {
            tokenAddress = tokenSymbolOrAddress;
            tokenSymbol = await (
                await IERC20Metadata.at(tokenAddress)
            ).symbol.call();
        } else {
            tokenSymbol = tokenSymbolOrAddress;
            tokenAddress = await sf.resolver.get(`tokens.${tokenSymbol}`);
        }

        console.log("Underlying token symbol", tokenSymbol);
        console.log("Underlying token address", tokenAddress);

        superTokenKey = `supertokens.${protocolReleaseVersion}.${tokenSymbol}`;
        if ((await sf.resolver.get(superTokenKey)) === ZERO_ADDRESS) {
            if (!givenByAddress) {
                tokenAddress = await sf.resolver.get(`tokens.${tokenSymbol}`);
                if (tokenAddress === ZERO_ADDRESS) {
                    throw new Error("Underlying ERC20 Token not found");
                }
            }
            const iERC20Metadata =
                await sf.contracts.IERC20Metadata.at(tokenAddress);
            const name = await iERC20Metadata.name.call();
            const symbol = await iERC20Metadata.symbol.call();
            const decimals = await iERC20Metadata.decimals.call();
            console.log("Underlying token address", tokenAddress);
            console.log("Underlying token info name()", name);
            console.log("Underlying token info symbol()", symbol);
            console.log(
                "Underlying token info decimals()",
                decimals.toString()
            );
            superTokenKey = `supertokens.${protocolReleaseVersion}.${tokenSymbol}x`;
            deploymentFn = async () => {
                return await sf.createERC20Wrapper(iERC20Metadata);
            };
        }
    }

    const superTokenAddress = await sf.resolver.get(superTokenKey);
    console.log("SuperToken key at the resolver: ", superTokenKey);

    console.log("SuperToken address: ", superTokenAddress);
    let doDeploy = false;
    if (resetToken || superTokenAddress === ZERO_ADDRESS) {
        doDeploy = true;
    } else {
        console.log("The superToken already registered.");
        const superToken = await ISuperToken.at(superTokenAddress);
        if ((await superToken.getHost()) !== sf.host.address) {
            console.log(
                "But the superToken uses a different host, redeploying is required."
            );
            doDeploy = true;
        } else {
            const superTokenLogic1 =
                await superTokenFactory.getSuperTokenLogic();
            console.log("Latest SuperToken logic address", superTokenLogic1);
            const superTokenLogic2 = await (
                await UUPSProxiable.at(superTokenAddress)
            ).getCodeAddress();
            console.log("Current SuperToken logic address", superTokenLogic2);
            if (superTokenLogic1 !== superTokenLogic2) {
                console.log("SuperToken logic needs to be updated.");
                await sendGovernanceAction(sf, (gov) =>
                    gov.batchUpdateSuperTokenLogic(sf.host.address, [
                        superTokenAddress,
                    ])
                );
                if (!process.env.GOVERNANCE_ADMIN_TYPE) {
                    // validate the token logic update for default governance type updates
                    const superTokenLogic3 = await (
                        await UUPSProxiable.at(superTokenAddress)
                    ).getCodeAddress();
                    console.log(
                        "Updated SuperToken logic address",
                        superTokenLogic3
                    );
                    if (superTokenLogic3 !== superTokenLogic1)
                        throw new Error("SuperToken logic not updated");
                    console.log("SuperToken's logic has been updated.");
                }
            }
        }
    }
    if (doDeploy) {
        console.log("Creating the wrapper...");
        const superToken = await deploymentFn();
        console.log("Wrapper created at", superToken.address);
        console.log("Resolver setting new address...");
        const resolver = await Resolver.at(sf.resolver.address);
        await resolver.set(superTokenKey, superToken.address);
        console.log("Resolver set done.");
        return superToken.address;
    }

    console.log("======== Super token deployed ========");
});
