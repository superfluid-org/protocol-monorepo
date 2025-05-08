const loadContracts = require("./loadContracts");
const getConfig = require("./getConfig");
const GasMeter = require("./utils/gasMetering/gasMetering");
const {getErrorResponse} = require("./utils/error");
const {isAddress, validateAddress} = require("./utils/general");
const {batchCall} = require("./batchCall");
const ConstantFlowAgreementV1Helper = require("./ConstantFlowAgreementV1Helper");
const InstantDistributionAgreementV1Helper = require("./InstantDistributionAgreementV1Helper");
const fetch = require("node-fetch");
// yes, this is dirty. truffle is deprecated, so this won't stick forever.
const truffleConfig = require("../../ethereum-contracts/truffle-config");

const User = require("./User");

const ZERO_ADDRESS = "0x0000000000000000000000000000000000000000";

/**
 * @dev Superfluid Framework class
 */
module.exports = class Framework {
    /**
     * @dev Create new Superfluid framework object
     * @param {string} options.version (Default: v1) protocol release version.
     * @param {boolean} options.isTruffle (Default: false) if the framework is used within truffle environment.
     * @param {Web3} options.web3  Injected web3 instance (version has to be 1.x)
     *
     * @param {Array} options.additionalContracts (Optional) additional contracts to be loaded
     * @param {string[]} options.tokens (Optional) Tokens to be loaded with a list of (in order of preference):
     *    - super chain-native token symbol (see getConfig.js),
     *    - underlying token resolver key (tokens.{KEY}),
     *    - super token key  (supertokens.{protocol_release_version}.{KEY})
     * @param {bool} options.loadSuperNativeToken Load super native token (e.g. ETHx) if possible
     * @param {Function} options.contractLoader (Optional) alternative contract loader function
     *
     * @param {string} options.resolverAddress force resolver address
     * @param {string} options.gasReportType output type for gas reporting. Currently HTML only
     * @return {Framework} The Framework object
     *
     * NOTE: You should call async function Framework.initialize to initialize the object.
     */
    constructor(options) {
        this._options = options;
        this.version = options.version || "v1";

        if (options.isTruffle && options.web3)
            throw Error(
                "@superfluid-finance/js-sdk: Flag 'isTruffle' cannot be 'true' when using a web3 instance."
            );
        if (!options.isTruffle && !options.web3)
            throw Error(
                "@superfluid-finance/js-sdk: You must provide a web3 instance."
            );

        this.web3 = options.isTruffle ? global.web3 : options.web3;

        if (options.gasReportType) {
            if (
                options.gasReportType !== "HTML" &&
                options.gasReportType !== "JSON"
            ) {
                throw new Error(
                    "Unsupported gas report type: " + options.gasReportType
                );
            }
            console.debug("Enabling gas report type:", options.gasReportType);
            this._gasReportType = options.gasReportType;
        }
    }

    /**
     * @dev Initialize the framework object
     * @return {Promise}
     */
    async initialize() {
        console.log("Initializing Superfluid Framework...");
        // NOTE: querying network type first,
        // Somehow web3.eth.net.getId may send bogus number if this was not done first
        // It could be a red-herring issue, but it makes it more stable.
        this.networkType = await this.web3.eth.net.getNetworkType();
        this.networkId = await this.web3.eth.net.getId();
        this.chainId = await this.web3.eth.getChainId();

        console.log("version", this.version);
        console.log("networkType", this.networkType);
        console.log("networkId", this.networkId);
        console.log("chainId", this.chainId);

        this.config = getConfig(this.chainId, this.version);

        this.contracts = await loadContracts({
            isTruffle: this._options.isTruffle,
            web3: this._options.web3,
            from: this._options.from,
            additionalContracts: this._options.additionalContracts,
            contractLoader: this._options.contractLoader,
            networkId: this.networkId,
            // copy of ethereum-contracts/ops-scripts/libs/common.js:getGasConfig()
            gasConfig: ((networkId) => {
                let gasConfig = {};

                const networkConfig = Object.values(truffleConfig.networks)
                    .filter((e) => e !== undefined)
                    .find((e) => e.network_id === networkId);

                if (networkConfig !== undefined) {
                    // gas limit
                    if (networkConfig.gas !== undefined) {
                        gasConfig.gas = networkConfig.gas;
                    }
                    // legacy gas price
                    if (networkConfig.gasPrice !== undefined) {
                        gasConfig.gasPrice = networkConfig.gasPrice;
                    }

                    // EIP-1559 gas price
                    if (networkConfig.maxPriorityFeePerGas !== undefined) {
                        gasConfig.maxPriorityFeePerGas =
                            networkConfig.maxPriorityFeePerGas;
                    }
                    if (networkConfig.maxFeePerGas !== undefined) {
                        gasConfig.maxFeePerGas = networkConfig.maxFeePerGas;
                    }
                }

                return gasConfig;
            })(this.networkId),
        });

        const resolverAddress =
            this._options.resolverAddress || this.config.resolverAddress;
        console.debug("Resolver at", resolverAddress);
        this.resolver = await this.contracts.IResolver.at(resolverAddress);

        // get framework loader and load
        this.loader = await this.contracts.SuperfluidLoader.at(
            await this.resolver.get("SuperfluidLoader-v1")
        );
        console.debug("Superfluid Loader v1", this.loader.address);
        console.debug("Loading framework with release version", this.version);
        const loaderResult = await this.loader.loadFramework(this.version);

        console.debug(
            "Superfluid host contract: TruffleContract .host",
            loaderResult.superfluid
        );
        console.debug(
            "SuperTokenFactory address:",
            loaderResult.superTokenFactory
        );
        console.debug(
            "ConstantFlowAgreementV1: TruffleContract .agreements.cfa | Helper .cfa",
            loaderResult.agreementCFAv1
        );
        console.debug(
            "InstantDistributionAgreementV1: TruffleContract .agreements.ida | Helper .ida",
            loaderResult.agreementIDAv1
        );

        this.agreements = {};
        this.tokens = {};
        this.superTokens = {};

        // load agreement classes
        [this.host, this.agreements.cfa, this.agreements.ida] =
            await Promise.all([
                // load host
                this.contracts.ISuperfluid.at(loaderResult.superfluid),
                // load agreements
                this.contracts.IConstantFlowAgreementV1.at(
                    loaderResult.agreementCFAv1
                ),
                this.contracts.IInstantDistributionAgreementV1.at(
                    loaderResult.agreementIDAv1
                ),
                // load tokens
                ...[
                    ...(this._options.tokens ? this._options.tokens : []),
                    ...(this._options.loadSuperNativeToken &&
                    this.config.nativeTokenSymbol
                        ? [this.config.nativeTokenSymbol]
                        : []),
                ].map(this.loadToken.bind(this)),
            ]);

        // load agreement helpers
        this.cfa = new ConstantFlowAgreementV1Helper(this);
        this.ida = new InstantDistributionAgreementV1Helper(this);

        this.utils = new (require("./Utils"))(this);
        if (this._gasReportType) {
            const defaultGasPrice = await this.web3.eth.getGasPrice();
            this._gasMetering = new GasMeter(
                this.web3,
                this._gasReportType,
                defaultGasPrice
            );
        }
        console.log("Superfluid Framework initialized.");
    }

    /**
     * @dev Load additional token using resolver
     * @param {String} superTokenKey super token key used to query resolver
     */
    async isSuperTokenListed(superTokenKey) {
        if (!isAddress(superTokenKey)) {
            const superTokenAddress = await this.resolver.get(
                `supertokens.${this.version}.${superTokenKey}`
            );
            return superTokenAddress !== ZERO_ADDRESS;
        } else {
            try {
                const superToken =
                    await this.contracts.ISuperToken.at(superTokenKey);
                const symbol = await superToken.symbol();
                const superTokenAddress = await this.resolver.get(
                    `supertokens.${this.version}.${symbol}`
                );
                return (
                    superToken.address.toLowerCase() ==
                    superTokenAddress.toLowerCase()
                );
            } catch (error) {
                console.warn("Invalid super token address", superTokenKey);
                return false;
            }
        }
    }

    /**
     * @dev Load additional token using resolver
     * @param {String} tokenKey token key used to query resolver (in order of preference):
     *    - super chain-native token symbol (see getConfig.js),
     *    - underlying token resolver key (tokens.{KEY}),
     *    - super token key (supertokens.{protocol_release_version}.{KEY})
     *    - super token address
     * @param options.skipTokens skips .tokens object, to save some network calls
     *
     * As a result:
     * - sf.tokens[tokenKey] and sf.superTokens[tokenKey] is the loaded SuperToken Object.
     * - Additionally, superTokenObject.underlyingToken is the underlying token object.
     * - If tokenKey is a super token address, it is normalized to lower case.
     */
    async loadToken(tokenKey, {skipTokens} = {}) {
        let underlyingToken;
        let superTokenKey;
        let superTokenContractType;
        let superTokenAddress;
        let superToken;
        let superTokenCustomType = "";
        // validate if the underlying token matches its corresponding
        // listed super token underlying token
        let doValidateUnderlyingToken = false;
        let isLoadingByAddress = false;

        if (!isAddress(tokenKey)) {
            if (
                tokenKey === this.config.nativeTokenSymbol ||
                tokenKey === this.config.nativeTokenSymbol + "x"
            ) {
                // it is the same as native token symbol (or plus "x"), we assume it is a SETH
                superTokenKey = this.config.nativeTokenSymbol + "x";
                superTokenContractType = this.contracts.ISETH;
                superTokenCustomType = "SETH";
            } else {
                // first check if tokenKey is symbol of a listed non-super token
                const tokenAddress = await this.resolver.get(
                    `tokens.${tokenKey}`
                );
                if (tokenAddress !== ZERO_ADDRESS) {
                    // if it is, we assume its ERC20 super token wrapper is postfixed with "x"
                    underlyingToken =
                        await this.contracts.IERC20Metadata.at(tokenAddress);
                    if (!skipTokens) this.tokens[tokenKey] = underlyingToken;
                    console.debug(
                        `${tokenKey}: IERC20Metadata .tokens["${tokenKey}"]`,
                        tokenAddress
                    );
                    superTokenKey = tokenKey + "x";
                    doValidateUnderlyingToken = true;
                } else {
                    // if it is not, then we assume it is a listed super token
                    superTokenKey = tokenKey;
                }
                superTokenContractType = this.contracts.ISuperToken;
            }

            // load super token
            superTokenAddress = await this.resolver.get(
                `supertokens.${this.version}.${superTokenKey}`
            );
            if (superTokenAddress === ZERO_ADDRESS) {
                throw new Error(`Super Token for ${tokenKey} cannot be found`);
            }
        } else {
            superTokenAddress = superTokenKey = tokenKey.toLowerCase();
            superTokenContractType = this.contracts.ISuperToken;
            isLoadingByAddress = true;
        }

        superToken = await superTokenContractType.at(superTokenAddress);
        superToken.superTokenCustomType = superTokenCustomType;
        if (!skipTokens) this.tokens[superTokenKey] = superToken;
        this.superTokens[superTokenKey] = superToken;
        let underlyingTokenAddress = await superToken.getUnderlyingToken.call();
        if (doValidateUnderlyingToken) {
            if (underlyingTokenAddress !== ZERO_ADDRESS) {
                // if underlying token is not undefined and not equal to getUnderlyingToken() returned address
                if (
                    underlyingTokenAddress.toLowerCase() !==
                    underlyingToken.address.toLowerCase()
                ) {
                    throw new Error(
                        `Underlying token addresses are different for ${tokenKey}`
                    );
                }
            } else {
                throw new Error(`Unexpected underlying token for ${tokenKey}`);
            }
        }

        // if underlying token is still null or undefined, load it
        if (!underlyingToken) {
            if (underlyingTokenAddress !== ZERO_ADDRESS) {
                underlyingToken = await this.contracts.IERC20Metadata.at(
                    underlyingTokenAddress
                );
                if (!isLoadingByAddress && !skipTokens) {
                    // do not pollute the tokens namespace if loading a potentially
                    // unlisted token
                    const symbol = await underlyingToken.symbol();
                    this.tokens[symbol] = underlyingToken;
                }
            }
        }
        superToken.underlyingToken = underlyingToken;

        console.debug(
            `${superTokenKey}: ISuperToken .tokens["${superTokenKey}"] ${superTokenCustomType}`,
            superToken.address
        );
    }

    /**
     * @dev Create the ERC20 wrapper from underlying token
     * @param {Any} iERC20Metadata the IERC20Metadata contract object to the underlying token
     * @param {string} superTokenName (optional) overriding superTokenName
     * @param {string} superTokenSymbol (optional) overriding superTokenSymbol
     * @param {address} from (optional) send transaction from
     * @param {address} upgradability (optional) send transaction from
     * @return {Promise<Transaction>} web3 transaction object
     */
    async createERC20Wrapper(
        iERC20Metadata,
        {superTokenSymbol, superTokenName, from, upgradability} = {}
    ) {
        const tokenName = await iERC20Metadata.name.call();
        const tokenSymbol = await iERC20Metadata.symbol.call();
        superTokenName = superTokenName || `Super ${tokenName}`;
        superTokenSymbol = superTokenSymbol || `${tokenSymbol}x`;
        const factory = await this.contracts.ISuperTokenFactory.at(
            await this.host.getSuperTokenFactory()
        );
        upgradability =
            typeof upgradability === "undefined" ? 1 : upgradability;
        const tx = await factory.createERC20Wrapper(
            iERC20Metadata.address,
            upgradability,
            superTokenName,
            superTokenSymbol,
            ...((from && [{from}]) || []) // don't mind this silly js stuff, thanks to web3.js
        );
        this._pushTxForGasReport(tx, "createERC20Wrapper");
        const wrapperAddress = tx.logs[0].args.token;
        const u = ["Non upgradable", "Semi upgrdable", "Full upgradable"][
            upgradability
        ];
        console.log(
            `${u} super token ${superTokenSymbol} created at ${wrapperAddress}`
        );
        const superToken = await this.contracts.ISuperToken.at(wrapperAddress);
        superToken.tx = tx;
        return superToken;
    }

    /**
     * @dev Create an user object
     * @param {address} address Account address Address of the user
     * @param {token} token Default token for the user
     * @param {options} options Additional options for the user.
     *
     * NOTE:
     * - See User class for more details about the options
     */
    user({address, token, options}) {
        try {
            if (!address) throw "Please provide an address";
            if (!token) throw "Please provide a token";
            validateAddress(address);
            // TODO: validate token
            return new User({sf: this, address, token, options});
        } catch (e) {
            throw getErrorResponse(e, "Framework", "user");
        }
    }

    /**
     * @dev Create a batch call
     * @param {object[]} calls Array of batch call descriptions.
     *
     * NOTE:
     * The batch call description is defined in batchCall.js, for lack of better
     * documentation, please read the source code of it.
     */
    batchCall(calls) {
        return this.host.batchCall(batchCall(calls));
    }

    /**
     * @dev Make a subgraph query
     * @param {string} query The subgraph query body
     * @return {Promise<object[]>}
     */
    async subgraphQuery(query) {
        const response = await fetch(this.config.subgraphQueryEndpoint, {
            method: "POST",
            body: JSON.stringify({query}),
            headers: {"Content-Type": "application/json"},
        });
        if (response.ok) {
            const result = JSON.parse(await response.text());
            if (!result.errors) {
                return result.data;
            } else {
                throw new Error(
                    "subgraphQuery errors: " + JSON.stringify(result.errors)
                );
            }
        } else throw new Error("subgraphQuery failed: " + response.text());
    }

    /**
     * @dev Get past events thourhg either web3 or subgraph
     * @param {Contract} contract The contract object where the event is emitted
     * @param {string} eventName The event name
     * @param {object} filter Event filtering
     * @return {Promise<object[]>}
     */
    async getPastEvents(contract, eventName, filter = {}, {forceWeb3} = {}) {
        function lcfirst(str) {
            return str.replace(/[A-Z]+/, (i) => i.toLowerCase());
        }

        const eventABI = contract.abi.filter((i) => i.name === eventName)[0];
        if (!eventABI) throw new Error("Event not found");

        if (this.config.subgraphQueryEndpoint && !forceWeb3) {
            const entityName = lcfirst(`${eventName}Events`);
            const fields = eventABI.inputs.map((i) => i.name);
            const where = eventABI.inputs
                .filter((i) => i.indexed)
                .map((i) => {
                    if (i.name in filter) {
                        if (filter[i.name] !== null) {
                            return `${i.name} : "${filter[i.name]}"`;
                        } else {
                            return null;
                        }
                    } else return null;
                })
                .filter((i) => i !== null)
                .join(",");
            const events = await this.subgraphQuery(`{
                ${entityName} (first: 1000, where: { ${where} }) {
                    transactionHash
                    blockNumber
                    ${fields.join("\n")}
                }
            }`);
            return events[entityName];
        } else if (contract.getPastEvents) {
            const result = await contract.getPastEvents(eventName, {
                fromBlock: 0,
                toBlock: "latest",
                filter,
            });
            return result.map((i) => ({
                transactionHash: i.transactionHash,
                blockNumber: i.blockNumber,
                ...i.args,
            }));
        } else if (contract.queryFilter) {
            const filterArgs = eventABI.inputs
                .filter((i) => i.indexed)
                .map((i) => (i.name in filter ? filter[i.name] : null));
            console.log("filterArgs", filterArgs);
            const result = await contract.queryFilter(
                contract.filters[eventName](...filterArgs),
                0,
                "latest"
            );
            return result.map((i) => ({
                transactionHash: i.transactionHash,
                blockNumber: i.blockNumber,
                ...i.args,
            }));
        } else throw new Error("No backend found for getPastEvents");
    }

    /**
     * @dev call to add a tx in the gas report. Does nothing if gas report type is not set.
     * @param {tx oject} tx as returned by truffleContract action
     * @param {str} actionName action title for row in report
     */
    _pushTxForGasReport(tx, actionName) {
        this._gasMetering ? this._gasMetering.pushTx(tx, actionName) : null;
    }

    /**
     * @dev generate gas report with transactions pushed until this call
     * @param {str} name file name for gas report
     * @throws if gas report type was not indicated in constructor
     */
    generateGasReport(name) {
        if (!this._gasMetering) {
            throw new Error("No gas metering configured");
        }
        this._gasMetering.generateReport(name);
    }
};
