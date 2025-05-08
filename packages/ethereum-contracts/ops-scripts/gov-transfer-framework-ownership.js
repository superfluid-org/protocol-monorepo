const SuperfluidSDK = require("@superfluid-finance/js-sdk");
const {web3tx} = require("@decentral.ee/web3-helpers");
const {
    getScriptRunnerFactory: S,
    extractWeb3Options,
    hasCode,
    sendGovernanceAction,
    builtTruffleContractLoader,
} = require("./libs/common");

/**
 * @dev Inspect accounts and their agreements
 * @param {Array} argv Overriding command line arguments
 * @param {boolean} options.isTruffle Whether the script is used within native truffle framework
 * @param {Web3} options.web3  Injected web3 instance
 * @param {Address} options.from Address to deploy contracts from
 *
 * Usage: npx truffle exec ops-scripts/gov-transfer-framework-ownership.js : {NEW_GOV_OWNER} [ {NEW_RESOLVER_ADMIN} ]
 *        if NEW_RESOLVER_ADMIN is not set, only governance ownership is changed
 *        set NEW_GOV_OWNER to the current owner in order to only set a new resolver admin
 */
module.exports = eval(`(${S.toString()})()`)(async function (
    args,
    options = {}
) {
    let {protocolReleaseVersion} = options;

    if (args.length !== 1 && args.length !== 2) {
        throw new Error("Wrong number of arguments");
    }

    let newResolverAdmin;
    if (args.length === 2) {
        newResolverAdmin = args.pop();
    }
    const newGovOwner = args.pop();

    const myAccount = (await web3.eth.getAccounts())[0];
    console.log("My account", myAccount);
    console.log("Transferring ownership of the framework to", newGovOwner);
    if (newResolverAdmin !== undefined) {
        console.log(
            "Transferring admin role of the resolver to",
            newResolverAdmin
        );
    }

    const sf = new SuperfluidSDK.Framework({
        ...extractWeb3Options(options),
        version: protocolReleaseVersion,
        additionalContracts: [
            "AccessControl",
            "Ownable",
            "IMultiSigWallet",
            "ISafe"
        ],
        contractLoader: builtTruffleContractLoader,
    });
    await sf.initialize();

    const govAddress = await sf.host.getGovernance.call();
    console.log("Governance address", govAddress);
    const ownable = await sf.contracts.Ownable.at(govAddress);
    const govOwner = await ownable.owner();
    console.log("Current owner of the governance", govOwner);
    if (newGovOwner.toLowerCase() !== govOwner.toLowerCase()) {
        // if owner is an EOA, it must match the caller account
        if (await hasCode(web3, govOwner) || (govOwner).toLowerCase() === myAccount.toLowerCase()) {
            await sendGovernanceAction(sf, (govMethods) =>
                govMethods.transferOwnership(newGovOwner)
            );
        } else {
            console.log("ERR: I am not owner of the governance.");
        }
    } else { // new owner == old owner
        console.log("I remain the owner of the governance.");
    }

    if (
        newResolverAdmin !== undefined &&
        newResolverAdmin.toLowerCase() !== myAccount.toLowerCase()
    ) {
        console.log("Resolver address", sf.resolver.address);
        const ADMIN_ROLE = "0x" + "0".repeat(64);
        const ac = await sf.contracts.AccessControl.at(sf.resolver.address);
        if (await ac.hasRole(ADMIN_ROLE, myAccount)) {
            await web3tx(
                ac.grantRole,
                "Grant admin rights of the resolver to new admin"
            )(ADMIN_ROLE, newResolverAdmin);
            await web3tx(
                ac.revokeRole,
                "Revoke my admin rights to the resolver"
            )(ADMIN_ROLE, myAccount);
        } else {
            console.log("ERR: I am not admin of the resolver.");
        }
    } else {
        console.log("I remain the admin of the resolver.");
    }
});
