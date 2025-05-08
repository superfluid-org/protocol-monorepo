const https = require("https");
const ethers = require("ethers");

const workflowPath =
    "https://api.github.com/repos/superfluid-finance/protocol-monorepo/actions/runs?per_page=100";
const pullRequestPath =
    "https://api.github.com/repos/superfluid-finance/protocol-monorepo/pulls?state=open";
const allPullRequests =
    "https://github.com/superfluid-finance/protocol-monorepo/pulls";
const warningIcon =
    "https://api.slack.com/img/blocks/bkb_template_images/notificationsWarningIcon.png";
const greenCheckMark =
    "https://emojipedia-us.s3.amazonaws.com/source/skype/289/check-mark-button_2705.png";
const redWarningIcon =
    "https://cdn-icons-png.flaticon.com/512/4201/4201973.png";
const sadPepeKidImage =
    "https://www.pngmart.com/files/11/Sad-Pepe-The-Frog-PNG-Transparent-Picture.png";
const topSectionMessage =
    "Looks like there are some lonely pull requests open in your area";
const workflowFileName = ".github/workflows/ci.canary.yml";
const metadataLink =
    "https://raw.githubusercontent.com/superfluid-finance/protocol-monorepo/dev/packages/metadata/networks.json";
const redImage =
    "https://upload.wikimedia.org/wikipedia/commons/thumb/6/62/Solid_red.svg/512px-Solid_red.svg.png?20150316143248";
const orangeImage =
    "https://5.imimg.com/data5/TK/YH/MY-451313/yellowish-orange-dye-500x500.jpg";
const greenImage =
    "https://upload.wikimedia.org/wikipedia/commons/thumb/3/32/Auto_Racing_Green.svg/1280px-Auto_Racing_Green.svg.png";

//Using graph to get the token list, so please use non-checksum addresses for ignoring tokens
const whiteListedAddresses = [
    "0xb63e38d21b31719e6df314d3d2c351df0d4a9162", // Polygon Mainnet IDLEx
    "0x00a27a8cf40d419fe581643f5c7d671e158ca4c3", // Old 2021 contract
    "0x42c3f8648bb518ae5fd74a79b4df6406171095ae", // Old 2021 contract
    "0xeb5748f9798b11af79f892f344f585e3a88aa784", // Old 2021 contract
];

const networkSpecificData = {
    "avalanche-fuji": {
        url: "https://api-testnet.snowtrace.io/api",
        key: process.env.SNOWTRACE_API_KEY,
    },
    "eth-sepolia": {
        url: "https://api-sepolia.etherscan.io/api",
        key: process.env.ETHERSCAN_API_KEY,
    },
    // mainnets
    "xdai-mainnet": {
        url: "https://api.gnosisscan.io/api",
        key: process.env.GNOSISSCAN_API_KEY,
    },
    "polygon-mainnet": {
        url: "https://api.polygonscan.com/api",
        key: process.env.POLYGONSCAN_API_KEY,
    },
    "optimism-mainnet": {
        url: "https://api-optimistic.etherscan.io/api",
        key: process.env.OPTIMISTIC_API_KEY,
    },
    "arbitrum-one": {
        url: "https://api.arbiscan.io/api",
        key: process.env.ARBISCAN_API_KEY,
    },
    "avalanche-c": {
        url: "https://api.snowtrace.io/api",
        key: process.env.SNOWTRACE_API_KEY,
    },
    "bsc-mainnet": {
        url: "https://api.bscscan.com/api",
        key: process.env.BSCSCAN_API_KEY,
    },
    "eth-mainnet": {
        url: "https://api.etherscan.io/api",
        key: process.env.ETHERSCAN_API_KEY,
    },
    "celo-mainnet": {
        url: "https://api.celoscan.io/api",
        key: process.env.CELOSCAN_API_KEY,
    },
    "scroll-mainnet": {
        url: "https://api.scrollscan.com/api",
        key: process.env.SCROLLSCAN_API_KEY,
    },
    "scroll-sepolia": {
        url: "https://api-sepolia.scrollscan.com/api",
        key: process.env.SCROLLSCAN_API_KEY,
    },
    "base-mainnet": {
        url: "https://api.basescan.org/api",
        key: process.env.BASESCAN_API_KEY,
    },
};

const superTokenFactoryABI = [
    {
        inputs: [
            {
                internalType: "contract ISuperfluid",
                name: "host",
                type: "address",
            },
            {
                internalType: "contract ISuperToken",
                name: "superTokenLogic",
                type: "address",
            },
            {
                internalType: "contract IConstantOutflowNFT",
                name: "constantOutflowNFTLogic",
                type: "address",
            },
            {
                internalType: "contract IConstantInflowNFT",
                name: "constantInflowNFTLogic",
                type: "address",
            },
            {
                internalType: "contract IPoolAdminNFT",
                name: "poolAdminNFT",
                type: "address",
            },
            {
                internalType: "contract IPoolMemberNFT",
                name: "poolMemberNFT",
                type: "address",
            },
        ],
        stateMutability: "nonpayable",
        type: "constructor",
    },
    { inputs: [], name: "SUPER_TOKEN_FACTORY_ALREADY_EXISTS", type: "error" },
    { inputs: [], name: "SUPER_TOKEN_FACTORY_DOES_NOT_EXIST", type: "error" },
    {
        inputs: [],
        name: "SUPER_TOKEN_FACTORY_NON_UPGRADEABLE_IS_DEPRECATED",
        type: "error",
    },
    {
        inputs: [],
        name: "SUPER_TOKEN_FACTORY_ONLY_GOVERNANCE_OWNER",
        type: "error",
    },
    { inputs: [], name: "SUPER_TOKEN_FACTORY_ONLY_HOST", type: "error" },
    { inputs: [], name: "SUPER_TOKEN_FACTORY_UNINITIALIZED", type: "error" },
    { inputs: [], name: "SUPER_TOKEN_FACTORY_ZERO_ADDRESS", type: "error" },
    {
        anonymous: false,
        inputs: [
            {
                indexed: false,
                internalType: "bytes32",
                name: "uuid",
                type: "bytes32",
            },
            {
                indexed: false,
                internalType: "address",
                name: "codeAddress",
                type: "address",
            },
        ],
        name: "CodeUpdated",
        type: "event",
    },
    {
        anonymous: false,
        inputs: [
            {
                indexed: true,
                internalType: "contract ISuperToken",
                name: "token",
                type: "address",
            },
        ],
        name: "CustomSuperTokenCreated",
        type: "event",
    },
    {
        anonymous: false,
        inputs: [
            {
                indexed: false,
                internalType: "uint8",
                name: "version",
                type: "uint8",
            },
        ],
        name: "Initialized",
        type: "event",
    },
    {
        anonymous: false,
        inputs: [
            {
                indexed: true,
                internalType: "contract ISuperToken",
                name: "token",
                type: "address",
            },
        ],
        name: "SuperTokenCreated",
        type: "event",
    },
    {
        anonymous: false,
        inputs: [
            {
                indexed: true,
                internalType: "contract ISuperToken",
                name: "tokenLogic",
                type: "address",
            },
        ],
        name: "SuperTokenLogicCreated",
        type: "event",
    },
    {
        inputs: [],
        name: "CONSTANT_INFLOW_NFT_LOGIC",
        outputs: [
            {
                internalType: "contract IConstantInflowNFT",
                name: "",
                type: "address",
            },
        ],
        stateMutability: "view",
        type: "function",
    },
    {
        inputs: [],
        name: "CONSTANT_OUTFLOW_NFT_LOGIC",
        outputs: [
            {
                internalType: "contract IConstantOutflowNFT",
                name: "",
                type: "address",
            },
        ],
        stateMutability: "view",
        type: "function",
    },
    {
        inputs: [],
        name: "POOL_ADMIN_NFT_LOGIC",
        outputs: [
            {
                internalType: "contract IPoolAdminNFT",
                name: "",
                type: "address",
            },
        ],
        stateMutability: "view",
        type: "function",
    },
    {
        inputs: [],
        name: "POOL_MEMBER_NFT_LOGIC",
        outputs: [
            {
                internalType: "contract IPoolMemberNFT",
                name: "",
                type: "address",
            },
        ],
        stateMutability: "view",
        type: "function",
    },
    {
        inputs: [],
        name: "_SUPER_TOKEN_LOGIC",
        outputs: [
            { internalType: "contract ISuperToken", name: "", type: "address" },
        ],
        stateMutability: "view",
        type: "function",
    },
    {
        inputs: [],
        name: "castrate",
        outputs: [],
        stateMutability: "nonpayable",
        type: "function",
    },
    {
        inputs: [
            {
                internalType: "address",
                name: "_underlyingToken",
                type: "address",
            },
        ],
        name: "computeCanonicalERC20WrapperAddress",
        outputs: [
            {
                internalType: "address",
                name: "superTokenAddress",
                type: "address",
            },
            { internalType: "bool", name: "isDeployed", type: "bool" },
        ],
        stateMutability: "view",
        type: "function",
    },
    {
        inputs: [
            {
                internalType: "contract ERC20WithTokenInfo",
                name: "_underlyingToken",
                type: "address",
            },
        ],
        name: "createCanonicalERC20Wrapper",
        outputs: [
            { internalType: "contract ISuperToken", name: "", type: "address" },
        ],
        stateMutability: "nonpayable",
        type: "function",
    },
    {
        inputs: [
            {
                internalType: "contract ERC20WithTokenInfo",
                name: "underlyingToken",
                type: "address",
            },
            {
                internalType: "enum ISuperTokenFactory.Upgradability",
                name: "upgradability",
                type: "uint8",
            },
            { internalType: "string", name: "name", type: "string" },
            { internalType: "string", name: "symbol", type: "string" },
        ],
        name: "createERC20Wrapper",
        outputs: [
            {
                internalType: "contract ISuperToken",
                name: "superToken",
                type: "address",
            },
        ],
        stateMutability: "nonpayable",
        type: "function",
    },
    {
        inputs: [
            {
                internalType: "contract IERC20",
                name: "underlyingToken",
                type: "address",
            },
            {
                internalType: "uint8",
                name: "underlyingDecimals",
                type: "uint8",
            },
            {
                internalType: "enum ISuperTokenFactory.Upgradability",
                name: "upgradability",
                type: "uint8",
            },
            { internalType: "string", name: "name", type: "string" },
            { internalType: "string", name: "symbol", type: "string" },
        ],
        name: "createERC20Wrapper",
        outputs: [
            {
                internalType: "contract ISuperToken",
                name: "superToken",
                type: "address",
            },
        ],
        stateMutability: "nonpayable",
        type: "function",
    },
    {
        inputs: [
            {
                internalType: "address",
                name: "_underlyingTokenAddress",
                type: "address",
            },
        ],
        name: "getCanonicalERC20Wrapper",
        outputs: [
            {
                internalType: "address",
                name: "superTokenAddress",
                type: "address",
            },
        ],
        stateMutability: "view",
        type: "function",
    },
    {
        inputs: [],
        name: "getCodeAddress",
        outputs: [
            { internalType: "address", name: "codeAddress", type: "address" },
        ],
        stateMutability: "view",
        type: "function",
    },
    {
        inputs: [],
        name: "getHost",
        outputs: [{ internalType: "address", name: "host", type: "address" }],
        stateMutability: "view",
        type: "function",
    },
    {
        inputs: [],
        name: "getSuperTokenLogic",
        outputs: [
            { internalType: "contract ISuperToken", name: "", type: "address" },
        ],
        stateMutability: "view",
        type: "function",
    },
    {
        inputs: [],
        name: "initialize",
        outputs: [],
        stateMutability: "nonpayable",
        type: "function",
    },
    {
        inputs: [
            {
                components: [
                    {
                        internalType: "address",
                        name: "underlyingToken",
                        type: "address",
                    },
                    {
                        internalType: "address",
                        name: "superToken",
                        type: "address",
                    },
                ],
                internalType: "struct SuperTokenFactoryBase.InitializeData[]",
                name: "_data",
                type: "tuple[]",
            },
        ],
        name: "initializeCanonicalWrapperSuperTokens",
        outputs: [],
        stateMutability: "nonpayable",
        type: "function",
    },
    {
        inputs: [
            {
                internalType: "address",
                name: "customSuperTokenProxy",
                type: "address",
            },
        ],
        name: "initializeCustomSuperToken",
        outputs: [],
        stateMutability: "nonpayable",
        type: "function",
    },
    {
        inputs: [],
        name: "proxiableUUID",
        outputs: [{ internalType: "bytes32", name: "", type: "bytes32" }],
        stateMutability: "pure",
        type: "function",
    },
    {
        inputs: [
            { internalType: "address", name: "newAddress", type: "address" },
        ],
        name: "updateCode",
        outputs: [],
        stateMutability: "nonpayable",
        type: "function",
    },
];
const hostABI = [
    {
        inputs: [
            { internalType: "bool", name: "nonUpgradable", type: "bool" },
            {
                internalType: "bool",
                name: "appWhiteListingEnabled",
                type: "bool",
            },
        ],
        stateMutability: "nonpayable",
        type: "constructor",
    },
    {
        inputs: [{ internalType: "uint256", name: "_code", type: "uint256" }],
        name: "APP_RULE",
        type: "error",
    },
    { inputs: [], name: "HOST_AGREEMENT_ALREADY_REGISTERED", type: "error" },
    {
        inputs: [],
        name: "HOST_AGREEMENT_CALLBACK_IS_NOT_ACTION",
        type: "error",
    },
    { inputs: [], name: "HOST_AGREEMENT_IS_NOT_REGISTERED", type: "error" },
    {
        inputs: [],
        name: "HOST_CALL_AGREEMENT_WITH_CTX_FROM_WRONG_ADDRESS",
        type: "error",
    },
    {
        inputs: [],
        name: "HOST_CALL_APP_ACTION_WITH_CTX_FROM_WRONG_ADDRESS",
        type: "error",
    },
    {
        inputs: [],
        name: "HOST_CANNOT_DOWNGRADE_TO_NON_UPGRADEABLE",
        type: "error",
    },
    { inputs: [], name: "HOST_INVALID_CONFIG_WORD", type: "error" },
    {
        inputs: [],
        name: "HOST_INVALID_OR_EXPIRED_SUPER_APP_REGISTRATION_KEY",
        type: "error",
    },
    { inputs: [], name: "HOST_MAX_256_AGREEMENTS", type: "error" },
    { inputs: [], name: "HOST_MUST_BE_CONTRACT", type: "error" },
    { inputs: [], name: "HOST_NEED_MORE_GAS", type: "error" },
    { inputs: [], name: "HOST_NON_UPGRADEABLE", type: "error" },
    { inputs: [], name: "HOST_NON_ZERO_LENGTH_PLACEHOLDER_CTX", type: "error" },
    { inputs: [], name: "HOST_NOT_A_SUPER_APP", type: "error" },
    { inputs: [], name: "HOST_NO_APP_REGISTRATION_PERMISSIONS", type: "error" },
    { inputs: [], name: "HOST_ONLY_GOVERNANCE", type: "error" },
    { inputs: [], name: "HOST_ONLY_LISTED_AGREEMENT", type: "error" },
    { inputs: [], name: "HOST_RECEIVER_IS_NOT_SUPER_APP", type: "error" },
    { inputs: [], name: "HOST_SENDER_IS_NOT_SUPER_APP", type: "error" },
    {
        inputs: [],
        name: "HOST_SOURCE_APP_NEEDS_HIGHER_APP_LEVEL",
        type: "error",
    },
    { inputs: [], name: "HOST_SUPER_APP_ALREADY_REGISTERED", type: "error" },
    { inputs: [], name: "HOST_SUPER_APP_IS_JAILED", type: "error" },
    { inputs: [], name: "HOST_UNAUTHORIZED_SUPER_APP_FACTORY", type: "error" },
    {
        inputs: [],
        name: "HOST_UNKNOWN_BATCH_CALL_OPERATION_TYPE",
        type: "error",
    },
    {
        anonymous: false,
        inputs: [
            {
                indexed: false,
                internalType: "bytes32",
                name: "agreementType",
                type: "bytes32",
            },
            {
                indexed: false,
                internalType: "address",
                name: "code",
                type: "address",
            },
        ],
        name: "AgreementClassRegistered",
        type: "event",
    },
    {
        anonymous: false,
        inputs: [
            {
                indexed: false,
                internalType: "bytes32",
                name: "agreementType",
                type: "bytes32",
            },
            {
                indexed: false,
                internalType: "address",
                name: "code",
                type: "address",
            },
        ],
        name: "AgreementClassUpdated",
        type: "event",
    },
    {
        anonymous: false,
        inputs: [
            {
                indexed: true,
                internalType: "contract ISuperApp",
                name: "app",
                type: "address",
            },
        ],
        name: "AppRegistered",
        type: "event",
    },
    {
        anonymous: false,
        inputs: [
            {
                indexed: false,
                internalType: "bytes32",
                name: "uuid",
                type: "bytes32",
            },
            {
                indexed: false,
                internalType: "address",
                name: "codeAddress",
                type: "address",
            },
        ],
        name: "CodeUpdated",
        type: "event",
    },
    {
        anonymous: false,
        inputs: [
            {
                indexed: false,
                internalType: "contract ISuperfluidGovernance",
                name: "oldGov",
                type: "address",
            },
            {
                indexed: false,
                internalType: "contract ISuperfluidGovernance",
                name: "newGov",
                type: "address",
            },
        ],
        name: "GovernanceReplaced",
        type: "event",
    },
    {
        anonymous: false,
        inputs: [
            {
                indexed: false,
                internalType: "uint8",
                name: "version",
                type: "uint8",
            },
        ],
        name: "Initialized",
        type: "event",
    },
    {
        anonymous: false,
        inputs: [
            {
                indexed: true,
                internalType: "contract ISuperApp",
                name: "app",
                type: "address",
            },
            {
                indexed: false,
                internalType: "uint256",
                name: "reason",
                type: "uint256",
            },
        ],
        name: "Jail",
        type: "event",
    },
    {
        anonymous: false,
        inputs: [
            {
                indexed: false,
                internalType: "contract ISuperTokenFactory",
                name: "newFactory",
                type: "address",
            },
        ],
        name: "SuperTokenFactoryUpdated",
        type: "event",
    },
    {
        anonymous: false,
        inputs: [
            {
                indexed: true,
                internalType: "contract ISuperToken",
                name: "token",
                type: "address",
            },
            {
                indexed: false,
                internalType: "address",
                name: "code",
                type: "address",
            },
        ],
        name: "SuperTokenLogicUpdated",
        type: "event",
    },
    {
        inputs: [],
        name: "APP_WHITE_LISTING_ENABLED",
        outputs: [{ internalType: "bool", name: "", type: "bool" }],
        stateMutability: "view",
        type: "function",
    },
    {
        inputs: [],
        name: "CALLBACK_GAS_LIMIT",
        outputs: [{ internalType: "uint64", name: "", type: "uint64" }],
        stateMutability: "view",
        type: "function",
    },
    {
        inputs: [],
        name: "MAX_APP_CALLBACK_LEVEL",
        outputs: [{ internalType: "uint256", name: "", type: "uint256" }],
        stateMutability: "view",
        type: "function",
    },
    {
        inputs: [],
        name: "MAX_NUM_AGREEMENTS",
        outputs: [{ internalType: "uint32", name: "", type: "uint32" }],
        stateMutability: "view",
        type: "function",
    },
    {
        inputs: [],
        name: "NON_UPGRADABLE_DEPLOYMENT",
        outputs: [{ internalType: "bool", name: "", type: "bool" }],
        stateMutability: "view",
        type: "function",
    },
    {
        inputs: [
            { internalType: "uint256", name: "bitmap", type: "uint256" },
            { internalType: "bytes32", name: "agreementType", type: "bytes32" },
        ],
        name: "addToAgreementClassesBitmap",
        outputs: [
            { internalType: "uint256", name: "newBitmap", type: "uint256" },
        ],
        stateMutability: "view",
        type: "function",
    },
    {
        inputs: [
            {
                internalType: "contract ISuperApp",
                name: "targetApp",
                type: "address",
            },
        ],
        name: "allowCompositeApp",
        outputs: [],
        stateMutability: "nonpayable",
        type: "function",
    },
    {
        inputs: [
            { internalType: "bytes", name: "ctx", type: "bytes" },
            {
                internalType: "int256",
                name: "appCreditUsedDelta",
                type: "int256",
            },
        ],
        name: "appCallbackPop",
        outputs: [{ internalType: "bytes", name: "newCtx", type: "bytes" }],
        stateMutability: "nonpayable",
        type: "function",
    },
    {
        inputs: [
            { internalType: "bytes", name: "ctx", type: "bytes" },
            {
                internalType: "contract ISuperApp",
                name: "app",
                type: "address",
            },
            {
                internalType: "uint256",
                name: "appCreditGranted",
                type: "uint256",
            },
            { internalType: "int256", name: "appCreditUsed", type: "int256" },
            {
                internalType: "contract ISuperfluidToken",
                name: "appCreditToken",
                type: "address",
            },
        ],
        name: "appCallbackPush",
        outputs: [{ internalType: "bytes", name: "appCtx", type: "bytes" }],
        stateMutability: "nonpayable",
        type: "function",
    },
    {
        inputs: [
            {
                components: [
                    {
                        internalType: "uint32",
                        name: "operationType",
                        type: "uint32",
                    },
                    {
                        internalType: "address",
                        name: "target",
                        type: "address",
                    },
                    { internalType: "bytes", name: "data", type: "bytes" },
                ],
                internalType: "struct ISuperfluid.Operation[]",
                name: "operations",
                type: "tuple[]",
            },
        ],
        name: "batchCall",
        outputs: [],
        stateMutability: "nonpayable",
        type: "function",
    },
    {
        inputs: [
            {
                internalType: "contract ISuperAgreement",
                name: "agreementClass",
                type: "address",
            },
            { internalType: "bytes", name: "callData", type: "bytes" },
            { internalType: "bytes", name: "userData", type: "bytes" },
        ],
        name: "callAgreement",
        outputs: [
            { internalType: "bytes", name: "returnedData", type: "bytes" },
        ],
        stateMutability: "nonpayable",
        type: "function",
    },
    {
        inputs: [
            {
                internalType: "contract ISuperAgreement",
                name: "agreementClass",
                type: "address",
            },
            { internalType: "bytes", name: "callData", type: "bytes" },
            { internalType: "bytes", name: "userData", type: "bytes" },
            { internalType: "bytes", name: "ctx", type: "bytes" },
        ],
        name: "callAgreementWithContext",
        outputs: [
            { internalType: "bytes", name: "newCtx", type: "bytes" },
            { internalType: "bytes", name: "returnedData", type: "bytes" },
        ],
        stateMutability: "nonpayable",
        type: "function",
    },
    {
        inputs: [
            {
                internalType: "contract ISuperApp",
                name: "app",
                type: "address",
            },
            { internalType: "bytes", name: "callData", type: "bytes" },
        ],
        name: "callAppAction",
        outputs: [
            { internalType: "bytes", name: "returnedData", type: "bytes" },
        ],
        stateMutability: "nonpayable",
        type: "function",
    },
    {
        inputs: [
            {
                internalType: "contract ISuperApp",
                name: "app",
                type: "address",
            },
            { internalType: "bytes", name: "callData", type: "bytes" },
            { internalType: "bytes", name: "ctx", type: "bytes" },
        ],
        name: "callAppActionWithContext",
        outputs: [{ internalType: "bytes", name: "newCtx", type: "bytes" }],
        stateMutability: "nonpayable",
        type: "function",
    },
    {
        inputs: [
            {
                internalType: "contract ISuperApp",
                name: "app",
                type: "address",
            },
            { internalType: "bytes", name: "callData", type: "bytes" },
            { internalType: "bool", name: "isTermination", type: "bool" },
            { internalType: "bytes", name: "ctx", type: "bytes" },
        ],
        name: "callAppAfterCallback",
        outputs: [{ internalType: "bytes", name: "newCtx", type: "bytes" }],
        stateMutability: "nonpayable",
        type: "function",
    },
    {
        inputs: [
            {
                internalType: "contract ISuperApp",
                name: "app",
                type: "address",
            },
            { internalType: "bytes", name: "callData", type: "bytes" },
            { internalType: "bool", name: "isTermination", type: "bool" },
            { internalType: "bytes", name: "ctx", type: "bytes" },
        ],
        name: "callAppBeforeCallback",
        outputs: [{ internalType: "bytes", name: "cbdata", type: "bytes" }],
        stateMutability: "nonpayable",
        type: "function",
    },
    {
        inputs: [],
        name: "castrate",
        outputs: [],
        stateMutability: "nonpayable",
        type: "function",
    },
    {
        inputs: [
            { internalType: "bytes", name: "ctx", type: "bytes" },
            {
                internalType: "int256",
                name: "appCreditUsedMore",
                type: "int256",
            },
        ],
        name: "ctxUseCredit",
        outputs: [{ internalType: "bytes", name: "newCtx", type: "bytes" }],
        stateMutability: "nonpayable",
        type: "function",
    },
    {
        inputs: [{ internalType: "bytes", name: "ctx", type: "bytes" }],
        name: "decodeCtx",
        outputs: [
            {
                components: [
                    {
                        internalType: "uint8",
                        name: "appCallbackLevel",
                        type: "uint8",
                    },
                    { internalType: "uint8", name: "callType", type: "uint8" },
                    {
                        internalType: "uint256",
                        name: "timestamp",
                        type: "uint256",
                    },
                    {
                        internalType: "address",
                        name: "msgSender",
                        type: "address",
                    },
                    {
                        internalType: "bytes4",
                        name: "agreementSelector",
                        type: "bytes4",
                    },
                    { internalType: "bytes", name: "userData", type: "bytes" },
                    {
                        internalType: "uint256",
                        name: "appCreditGranted",
                        type: "uint256",
                    },
                    {
                        internalType: "uint256",
                        name: "appCreditWantedDeprecated",
                        type: "uint256",
                    },
                    {
                        internalType: "int256",
                        name: "appCreditUsed",
                        type: "int256",
                    },
                    {
                        internalType: "address",
                        name: "appAddress",
                        type: "address",
                    },
                    {
                        internalType: "contract ISuperfluidToken",
                        name: "appCreditToken",
                        type: "address",
                    },
                ],
                internalType: "struct ISuperfluid.Context",
                name: "context",
                type: "tuple",
            },
        ],
        stateMutability: "pure",
        type: "function",
    },
    {
        inputs: [
            {
                components: [
                    {
                        internalType: "uint32",
                        name: "operationType",
                        type: "uint32",
                    },
                    {
                        internalType: "address",
                        name: "target",
                        type: "address",
                    },
                    { internalType: "bytes", name: "data", type: "bytes" },
                ],
                internalType: "struct ISuperfluid.Operation[]",
                name: "operations",
                type: "tuple[]",
            },
        ],
        name: "forwardBatchCall",
        outputs: [],
        stateMutability: "nonpayable",
        type: "function",
    },
    {
        inputs: [
            { internalType: "bytes32", name: "agreementType", type: "bytes32" },
        ],
        name: "getAgreementClass",
        outputs: [
            {
                internalType: "contract ISuperAgreement",
                name: "agreementClass",
                type: "address",
            },
        ],
        stateMutability: "view",
        type: "function",
    },
    {
        inputs: [
            {
                internalType: "contract ISuperApp",
                name: "appAddr",
                type: "address",
            },
        ],
        name: "getAppCallbackLevel",
        outputs: [{ internalType: "uint8", name: "", type: "uint8" }],
        stateMutability: "view",
        type: "function",
    },
    {
        inputs: [
            {
                internalType: "contract ISuperApp",
                name: "app",
                type: "address",
            },
        ],
        name: "getAppManifest",
        outputs: [
            { internalType: "bool", name: "isSuperApp", type: "bool" },
            { internalType: "bool", name: "isJailed", type: "bool" },
            { internalType: "uint256", name: "noopMask", type: "uint256" },
        ],
        stateMutability: "view",
        type: "function",
    },
    {
        inputs: [],
        name: "getCodeAddress",
        outputs: [
            { internalType: "address", name: "codeAddress", type: "address" },
        ],
        stateMutability: "view",
        type: "function",
    },
    {
        inputs: [],
        name: "getGovernance",
        outputs: [
            {
                internalType: "contract ISuperfluidGovernance",
                name: "",
                type: "address",
            },
        ],
        stateMutability: "view",
        type: "function",
    },
    {
        inputs: [],
        name: "getNow",
        outputs: [{ internalType: "uint256", name: "", type: "uint256" }],
        stateMutability: "view",
        type: "function",
    },
    {
        inputs: [],
        name: "getSuperTokenFactory",
        outputs: [
            {
                internalType: "contract ISuperTokenFactory",
                name: "factory",
                type: "address",
            },
        ],
        stateMutability: "view",
        type: "function",
    },
    {
        inputs: [],
        name: "getSuperTokenFactoryLogic",
        outputs: [{ internalType: "address", name: "logic", type: "address" }],
        stateMutability: "view",
        type: "function",
    },
    {
        inputs: [
            {
                internalType: "contract ISuperfluidGovernance",
                name: "gov",
                type: "address",
            },
        ],
        name: "initialize",
        outputs: [],
        stateMutability: "nonpayable",
        type: "function",
    },
    {
        inputs: [
            {
                internalType: "contract ISuperAgreement",
                name: "agreementClass",
                type: "address",
            },
        ],
        name: "isAgreementClassListed",
        outputs: [{ internalType: "bool", name: "yes", type: "bool" }],
        stateMutability: "view",
        type: "function",
    },
    {
        inputs: [
            { internalType: "bytes32", name: "agreementType", type: "bytes32" },
        ],
        name: "isAgreementTypeListed",
        outputs: [{ internalType: "bool", name: "yes", type: "bool" }],
        stateMutability: "view",
        type: "function",
    },
    {
        inputs: [
            {
                internalType: "contract ISuperApp",
                name: "app",
                type: "address",
            },
        ],
        name: "isApp",
        outputs: [{ internalType: "bool", name: "", type: "bool" }],
        stateMutability: "view",
        type: "function",
    },
    {
        inputs: [
            {
                internalType: "contract ISuperApp",
                name: "app",
                type: "address",
            },
        ],
        name: "isAppJailed",
        outputs: [{ internalType: "bool", name: "", type: "bool" }],
        stateMutability: "view",
        type: "function",
    },
    {
        inputs: [
            {
                internalType: "contract ISuperApp",
                name: "app",
                type: "address",
            },
            {
                internalType: "contract ISuperApp",
                name: "targetApp",
                type: "address",
            },
        ],
        name: "isCompositeAppAllowed",
        outputs: [{ internalType: "bool", name: "", type: "bool" }],
        stateMutability: "view",
        type: "function",
    },
    {
        inputs: [{ internalType: "bytes", name: "ctx", type: "bytes" }],
        name: "isCtxValid",
        outputs: [{ internalType: "bool", name: "", type: "bool" }],
        stateMutability: "view",
        type: "function",
    },
    {
        inputs: [
            { internalType: "address", name: "forwarder", type: "address" },
        ],
        name: "isTrustedForwarder",
        outputs: [{ internalType: "bool", name: "", type: "bool" }],
        stateMutability: "view",
        type: "function",
    },
    {
        inputs: [
            { internalType: "bytes", name: "ctx", type: "bytes" },
            {
                internalType: "contract ISuperApp",
                name: "app",
                type: "address",
            },
            { internalType: "uint256", name: "reason", type: "uint256" },
        ],
        name: "jailApp",
        outputs: [{ internalType: "bytes", name: "newCtx", type: "bytes" }],
        stateMutability: "nonpayable",
        type: "function",
    },
    {
        inputs: [{ internalType: "uint256", name: "bitmap", type: "uint256" }],
        name: "mapAgreementClasses",
        outputs: [
            {
                internalType: "contract ISuperAgreement[]",
                name: "agreementClasses",
                type: "address[]",
            },
        ],
        stateMutability: "view",
        type: "function",
    },
    {
        inputs: [],
        name: "proxiableUUID",
        outputs: [{ internalType: "bytes32", name: "", type: "bytes32" }],
        stateMutability: "pure",
        type: "function",
    },
    {
        inputs: [
            {
                internalType: "contract ISuperAgreement",
                name: "agreementClassLogic",
                type: "address",
            },
        ],
        name: "registerAgreementClass",
        outputs: [],
        stateMutability: "nonpayable",
        type: "function",
    },
    {
        inputs: [
            { internalType: "uint256", name: "configWord", type: "uint256" },
        ],
        name: "registerApp",
        outputs: [],
        stateMutability: "nonpayable",
        type: "function",
    },
    {
        inputs: [
            {
                internalType: "contract ISuperApp",
                name: "app",
                type: "address",
            },
            { internalType: "uint256", name: "configWord", type: "uint256" },
        ],
        name: "registerAppByFactory",
        outputs: [],
        stateMutability: "nonpayable",
        type: "function",
    },
    {
        inputs: [
            { internalType: "uint256", name: "configWord", type: "uint256" },
            { internalType: "string", name: "registrationKey", type: "string" },
        ],
        name: "registerAppWithKey",
        outputs: [],
        stateMutability: "nonpayable",
        type: "function",
    },
    {
        inputs: [
            { internalType: "uint256", name: "bitmap", type: "uint256" },
            { internalType: "bytes32", name: "agreementType", type: "bytes32" },
        ],
        name: "removeFromAgreementClassesBitmap",
        outputs: [
            { internalType: "uint256", name: "newBitmap", type: "uint256" },
        ],
        stateMutability: "view",
        type: "function",
    },
    {
        inputs: [
            {
                internalType: "contract ISuperfluidGovernance",
                name: "newGov",
                type: "address",
            },
        ],
        name: "replaceGovernance",
        outputs: [],
        stateMutability: "nonpayable",
        type: "function",
    },
    {
        inputs: [
            {
                internalType: "contract ISuperAgreement",
                name: "agreementClassLogic",
                type: "address",
            },
        ],
        name: "updateAgreementClass",
        outputs: [],
        stateMutability: "nonpayable",
        type: "function",
    },
    {
        inputs: [
            { internalType: "address", name: "newAddress", type: "address" },
        ],
        name: "updateCode",
        outputs: [],
        stateMutability: "nonpayable",
        type: "function",
    },
    {
        inputs: [
            {
                internalType: "contract ISuperTokenFactory",
                name: "newFactory",
                type: "address",
            },
        ],
        name: "updateSuperTokenFactory",
        outputs: [],
        stateMutability: "nonpayable",
        type: "function",
    },
    {
        inputs: [
            {
                internalType: "contract ISuperToken",
                name: "token",
                type: "address",
            },
        ],
        name: "updateSuperTokenLogic",
        outputs: [],
        stateMutability: "nonpayable",
        type: "function",
    },
    {
        inputs: [],
        name: "versionRecipient",
        outputs: [{ internalType: "string", name: "", type: "string" }],
        stateMutability: "pure",
        type: "function",
    },
];

async function getDataAsJson(url) {
    let options = {
        headers: {
            "Content-Type": "application/json",
            "User-Agent": "Elvi.js slack bot",
        },
        method: "GET",
    };

    return new Promise((resolve) => {
        const req = https.request(url, options, (res) => {
            let body = "";
            res.on("data", function (chunk) {
                body += chunk;
            });
            res.on("error", (err) => {
                console.log(err);
            });
            res.on("end", function () {
                resolve(JSON.parse(body));
            });
        });

        req.on("error", (err) => {
            console.log(err);
        });
        req.end();
    });
}

async function sendMessageToSlack(data) {
    const slackHostName = "hooks.slack.com";
    let topSecret = process.env.CI_SLACK_WEBHOOK.split(slackHostName)[1];
    let options = {
        headers: {
            "Content-Type": "application/json",
            "User-Agent": "Elvi.js slack bot",
        },
        hostname: slackHostName,
        path: topSecret,
        method: "POST",
    };

    const req = https
        .request(options, (res) => {
            console.log("Status Code:", res.statusCode);

            res.on("data", (chunk) => {
                data += chunk;
            });
        })
        .on("error", (err) => {
            console.log("Error: ", err.message);
        });

    req.write(data);
    req.end();
}

async function getSuperTokenLogicAddress(network) {
    const rpcUrl = "https://rpc-endpoints.superfluid.dev/" + network.name;
    const provider = new ethers.JsonRpcProvider(rpcUrl);
    const contract = new ethers.Contract(
        network.contractsV1.superTokenFactory,
        superTokenFactoryABI,
        provider,
    );
    try {
        return await contract.getSuperTokenLogic();
    } catch (e) {
        console.log(e);
    }
}

async function getGovernanceAddress(network) {
    const rpcUrl = "https://rpc-endpoints.superfluid.dev/" + network.name;
    const provider = new ethers.JsonRpcProvider(rpcUrl);
    const contract = new ethers.Contract(
        network.contractsV1.host,
        hostABI,
        provider,
    );
    try {
        return await contract.getGovernance();
    } catch (e) {
        console.log(e);
    }
}

async function checkNetworkContractVerification(network) {
    if (networkSpecificData[network.name] === undefined) {
        return "";
    }
    let contractsToCheck = network.contractsV1;
    contractsToCheck.nativeTokenWrapper = network.nativeTokenWrapper;
    contractsToCheck.superTokenLogic = await getSuperTokenLogicAddress(network);
    contractsToCheck.governance = await getGovernanceAddress(network);
    if (network.contractsV1.autowrap) {
        contractsToCheck.autoWrapManager = network.contractsV1.autowrap.manager;
        contractsToCheck.autoWrapStrategy =
            network.contractsV1.autowrap.wrapStrategy;
        delete network.contractsV1.autowrap;
    }
    const networkTokenAddressList = await getNetworkTokenAddressList(network);
    contractsToCheck = {
        ...contractsToCheck,
        ...networkTokenAddressList,
    };

    for (const [contractName, address] of Object.entries(contractsToCheck)) {
        if (whiteListedAddresses.includes(address)) {
            delete contractsToCheck[contractName];
        }
    }

    let networkMessage = "";
    for (const [contractName, address] of Object.entries(contractsToCheck)) {
        networkMessage += await checkIndividualContractVerification(
            network,
            contractName,
            address,
        );
    }

    if (networkMessage === "") {
        return "";
    } else {
        return `*❌ ${network.humanReadableName}*\n${networkMessage}\n`;
    }
}

async function getNetworkTokenAddressList(network) {
    return new Promise((resolve, reject) => {
        let response = "";
        const hostName = `${network.name}.subgraph.x.superfluid.dev`;
        let options = {
            headers: {
                "Content-Type": "application/json",
                "User-Agent": "Elvi.js slack bot",
            },
            hostname: hostName,
            path: "/",
            method: "POST",
        };

        const req = https
            .request(options, (res) => {
                console.log("Status Code:", res.statusCode);

                res.on("data", (chunk) => {
                    response += chunk.toString();
                });

                res.on("end", () => {
                    try {
                        const parsedResponse = JSON.parse(response);
                        const newObject = {};
                        parsedResponse.data.tokens.forEach((token) => {
                            newObject[token.symbol] = token.id;
                        });
                        resolve(newObject);
                    } catch (error) {
                        reject(error);
                    }
                });
            })
            .on("error", (err) => {
                console.log("Error: ", err.message);
                reject(err);
            });

        req.write(
            JSON.stringify({
                query: "query {  tokens(where: {isListed: true}) {    symbol    id  }}",
            }),
        );
        req.end();
    });
}

async function checkIndividualContractVerification(
    network,
    contractName,
    contractAddress,
) {
    let endpoint = networkSpecificData[network.name];
    const url = `${endpoint.url}/?apikey=${endpoint.key}&module=contract&action=getabi&address=${contractAddress}`;
    if (!endpoint.key) {
        throw new Error(`Please specify the API key for ${network.name}`);
    }
    const result = await getDataAsJson(url);
    if (result.status === undefined) {
        throw new Error(`Failed checking ${contractName}: ${contractAddress}`);
    }
    if (result.result === "Invalid API Key") {
        throw new Error(`Invalid API key for ${network.name}}`);
    }
    if (
        result.status === "0" &&
        result.result === "Contract source code not verified"
    ) {
        return `*<${network.explorer}/address/${contractAddress}|${contractName}>*\n`;
    } else {
        return "";
    }
}

(async () => {
    const allNetworkMetadata = await getDataAsJson(metadataLink);
    const prJson = await getDataAsJson(pullRequestPath);
    const workflowJson = await getDataAsJson(workflowPath);
    const openPRs = prJson.filter((x) => x.draft === false);
    const draftPRs = prJson.filter((x) => x.draft === true);
    let amountOfDraftPRs = draftPRs.length;
    const amountOfPRsOpen = openPRs.length;
    const oldestOpenPR = openPRs[openPRs.length - 1];
    const oldestDraftPR = draftPRs[draftPRs.length - 1];
    let oldestOpenPRTitle = oldestOpenPR ? oldestOpenPR.title : "";
    const oldestDraftPRTitle = oldestDraftPR ? oldestDraftPR.title : "";
    const oldestPRAuthorName = oldestOpenPR ? oldestOpenPR.user.login : "";
    const oldestPRAuthorPicture = oldestOpenPR
        ? oldestOpenPR.user.avatar_url
        : "";
    const oldestPRCreatedByUrl = oldestOpenPR ? oldestOpenPR.user.url : "";
    const oldestPRUrl = oldestOpenPR ? oldestOpenPR.html_url : "";
    const oldestDraftPRUrl = oldestDraftPR ? oldestDraftPR.html_url : "";
    const lastWorkflow = workflowJson.workflow_runs.filter(
        (x) => x.path === workflowFileName,
    )[0];
    const lastWorkflowId = lastWorkflow.id;
    const lastWorkflowUsage = await getDataAsJson(
        "https://api.github.com/repos/superfluid-finance/protocol-monorepo/actions/runs/" +
            lastWorkflowId +
            "/timing",
    );

    const workflowStatus = lastWorkflow.status;
    const workflowConclusion = lastWorkflow.conclusion;
    const workflowRanAt = new Date(lastWorkflow.run_started_at).toUTCString();
    const workflowUrl = lastWorkflow.html_url;
    const workflowNumber = lastWorkflow.run_number;
    const workflowName = lastWorkflow.name;

    const workflowTriggeringCommitMessage =
        lastWorkflow.head_commit.message.split("\n")[0];
    const workflowCommitLink =
        "https://github.com/superfluid-finance/protocol-monorepo/commit/" +
        lastWorkflow.head_commit.id;

    let webhookPayload = { blocks: [] };

    async function getPrOldestCommit(prJson) {
        let allCommits = await getDataAsJson(
            "https://api.github.com/repos/superfluid-finance/protocol-monorepo/pulls/" +
                prJson.number +
                "/commits",
        );
        return allCommits[allCommits.length - 1];
    }

    let olderstPrOldestCommit = oldestOpenPR
        ? await getPrOldestCommit(oldestOpenPR)
        : "";
    let oldestDraftPrOldestCommit = oldestDraftPR
        ? await getPrOldestCommit(oldestDraftPR)
        : "";

    const oldestPRLastUpdate = oldestOpenPR
        ? new Date(olderstPrOldestCommit.commit.author.date)
        : "";

    const oldestDraftPRLastUpdate = oldestDraftPR
        ? new Date(oldestDraftPrOldestCommit.commit.author.date)
        : "";

    const oldestPRMessage = oldestOpenPR
        ? olderstPrOldestCommit.commit.message
        : "";

    const msInADay = 1000 * 60 * 60 * 24;
    const lastUpdatedBeforeDays = (
        (Date.now() - oldestPRLastUpdate) /
        msInADay
    ).toFixed(0);

    let lastDraftPrUpdateBeforeDays = (
        (Date.now() - oldestDraftPRLastUpdate) /
        msInADay
    ).toFixed(0);

    async function addContractVerificationSections(metadata) {
        let allContractsVerified = true;
        for (const [key, value] of Object.entries(metadata)) {
            let networkResult = await checkNetworkContractVerification(value);
            if (networkResult !== "") {
                allContractsVerified = false;
                addMarkdownText(webhookPayload, networkResult);
                addDivider(webhookPayload);
            }
        }
        if (allContractsVerified) {
            addMarkdownText(
                webhookPayload,
                "All contracts are verified ✅✅✅",
            );
        }
    }

    function convertMS(ms) {
        let d, h, m, s;
        s = Math.floor(ms / 1000);
        m = Math.floor(s / 60);
        s = s % 60;
        h = Math.floor(m / 60);
        m = m % 60;
        d = Math.floor(h / 24);
        h = h % 24;
        h += d * 24;
        return h + ":" + m + ":" + s;
    }

    function addHeader(payload, text) {
        let header = {
            type: "header",
            text: {
                type: "plain_text",
                text: text,
                emoji: true,
            },
        };
        payload.blocks.push(header);
    }

    function addPlainText(payload, text) {
        let header = {
            type: "section",
            text: {
                type: "plain_text",
                text: text,
                emoji: true,
            },
        };
        payload.blocks.push(header);
    }

    function addMarkdownText(payload, text) {
        let header = {
            type: "section",
            text: {
                type: "mrkdwn",
                text: text,
            },
        };
        payload.blocks.push(header);
    }

    function addSectionWithImage(payload, text, image, imageText) {
        let section = {
            type: "section",
            text: {
                type: "mrkdwn",
                text: text,
            },
            accessory: {
                type: "image",
                image_url: image,
                alt_text: imageText,
            },
        };
        payload.blocks.push(section);
    }

    function addContextWithImage(payload, text, image, imageText) {
        let context = {
            type: "context",
            elements: [
                {
                    type: "image",
                    image_url: image,
                    alt_text: imageText,
                },
                {
                    type: "mrkdwn",
                    text: text,
                },
            ],
        };
        payload.blocks.push(context);
    }

    function addDivider(payload) {
        let divider = {
            type: "divider",
        };
        payload.blocks.push(divider);
    }

    function getAssigneeString() {
        let finalString = "Assigned to: ";
        oldestOpenPR.assignees.forEach((asignee) => {
            finalString += "*<" + asignee.url + "|" + asignee.login + ">*,";
        });
        if (oldestOpenPR.assignees.length > 0) {
            return finalString.slice(0, -1) + " please have a look\n";
        } else {
            return "Nobody is assigned to this PR, we need to find someone to shame ASAP\n";
        }
    }

    function getLastPRString() {
        return "*<" + oldestPRUrl + "|" + oldestOpenPRTitle + ">*" + "\n";
    }

    function getPRCreatedByString() {
        return (
            "Created by: *<" +
            oldestPRCreatedByUrl +
            "|" +
            oldestPRAuthorName +
            ">*\n"
        );
    }

    function getPRAmountString() {
        let prCountString;
        prCountString = "There are " + amountOfPRsOpen + " PRs open";
        if (amountOfDraftPRs > 0) {
            prCountString =
                prCountString + " and " + amountOfDraftPRs + " are in draft";
        }
        if (amountOfPRsOpen === 0 && amountOfDraftPRs === 0) {
            prCountString =
                "Click here to see a magnificent view of no open PRs in the monorepo";
        }
        return "*<" + allPullRequests + "|" + prCountString + ">*";
    }

    function addDraftPRSection() {
        if (amountOfDraftPRs > 0 && lastDraftPrUpdateBeforeDays >= 90) {
            let americaTrips = (lastDraftPrUpdateBeforeDays / 36).toFixed(0);
            addHeader(
                webhookPayload,
                "Unlike fine wine , draft pull requests don't get better with time",
            );
            addSectionWithImage(
                webhookPayload,
                "Please have a look at: *<" +
                    oldestDraftPRUrl +
                    "|" +
                    oldestDraftPRTitle +
                    ">*\nColumbus would have went to America " +
                    americaTrips +
                    " times already by this time ,do something with this as this has been open for *" +
                    lastDraftPrUpdateBeforeDays +
                    "* days",
                redWarningIcon,
                "It took them 36 days",
            );
            addDivider(webhookPayload);
        }
    }

    function addPRSection() {
        if (amountOfPRsOpen > 0) {
            let PRString =
                getLastPRString() +
                getAssigneeString() +
                getPRCreatedByString() +
                getPRAmountString();
            addSectionWithImage(
                webhookPayload,
                PRString,
                oldestPRAuthorPicture,
                oldestPRAuthorName,
            );
            addPRContext();
        } else {
            let draftMessage = oldestDraftPR
                ? "There are no open PRs????? *<" +
                  allPullRequests +
                  "|" +
                  amountOfDraftPRs +
                  " pull requests are in draft , you might want to look into those>*"
                : "There are no open and draft PRs? What is this, why u no work, you might want to read this:\n*<https://docs.github.com/en/pull-requests/collaborating-with-pull-requests/proposing-changes-to-your-work-with-pull-requests/creating-a-pull-request|How to create a pull request>*";
            addSectionWithImage(
                webhookPayload,
                draftMessage,
                sadPepeKidImage,
                "The pepe kid is sad, open a PR to make him happy",
            );
        }
    }

    function addPRContext() {
        if (amountOfPRsOpen > 0) {
            let imageToAddToContext;
            let imageText;
            if (lastUpdatedBeforeDays >= 30) {
                imageToAddToContext = redWarningIcon;
                imageText =
                    "C'mon guys it has been a month already , lets move this along";
            } else {
                imageToAddToContext =
                    lastUpdatedBeforeDays < 14 ? greenCheckMark : warningIcon;

                imageText =
                    lastUpdatedBeforeDays < 14
                        ? "Please, publicly shame Elvijs if this value is wrong ,otherwise the PR is nice and fresh"
                        : "Amigo, the PR is hanging there for more than 2 weeks already, maybe have a look?";
            }
            addContextWithImage(
                webhookPayload,
                "*The PR has been last updated before " +
                    lastUpdatedBeforeDays +
                    " days*\nLast commit: " +
                    oldestPRMessage,
                imageToAddToContext,
                imageText,
            );
            addDivider(webhookPayload);
        }
    }

    function getOverallWorkflowString() {
        if (workflowStatus === "in_progress") {
            return "In progress";
        } else {
            return workflowConclusion === "success" ? "Success" : "Failed";
        }
    }

    function getWorkflowTimeString() {
        if (workflowStatus === "in_progress") {
            return workflowName + " is still running , please wait";
        } else {
            return (
                workflowName +
                " ran for: " +
                convertMS(lastWorkflowUsage.run_duration_ms)
            );
        }
    }

    function getWorkflowString() {
        return (
            workflowName +
            " *<" +
            workflowUrl +
            "|#" +
            workflowNumber +
            ">*: " +
            getOverallWorkflowString() +
            "\nLast commit: *<" +
            workflowCommitLink +
            "|" +
            workflowTriggeringCommitMessage +
            ">*\nWorkflow ran at: " +
            workflowRanAt +
            "\n" +
            getWorkflowTimeString()
        );
    }

    function getWorkflowPicture() {
        if (workflowStatus === "in_progress") {
            return orangeImage;
        } else {
            return workflowConclusion === "success" ? greenImage : redImage;
        }
    }

    function addWorkflowSection() {
        addSectionWithImage(
            webhookPayload,
            getWorkflowString(),
            getWorkflowPicture(),
            "Sorry if you are color blind",
        );
    }

    addHeader(webhookPayload, "Elvi.js protocol monorepo public shamer");
    addPlainText(webhookPayload, topSectionMessage);
    addDivider(webhookPayload);
    addPRSection();
    addDraftPRSection();
    addHeader(
        webhookPayload,
        workflowName + " latest status: " + getOverallWorkflowString(),
    );
    addWorkflowSection();
    addDivider(webhookPayload);
    addHeader(webhookPayload, "Contract verification checker ✔️");
    await addContractVerificationSections(allNetworkMetadata);
    await sendMessageToSlack(JSON.stringify(webhookPayload));
})();
