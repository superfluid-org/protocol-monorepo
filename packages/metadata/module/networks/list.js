/* eslint-disable */
export default
[
    {
        "name": "avalanche-fuji",
        "isTestnet": true,
        "networkId": 43113,
        "chainId": 43113,
        "sfId": 105,
        "shortName": "fuji",
        "uppercaseName": "AVALANCHE_FUJI",
        "humanReadableName": "Avalanche Fuji",
        "nativeTokenSymbol": "AVAX",
        "nativeTokenWrapper": "0xfFD0f6d73ee52c68BF1b01C8AfA2529C97ca17F3",
        "contractsV1": {
            "resolver": "0xf0ec6A8842Ca72Aec8A4D4573E731242389e18A8",
            "host": "0x85Fe79b998509B77BF10A8BD4001D58475D29386",
            "cfaV1": "0x16843ac25Ccc58Aa7960ba05f61cBB17b36b130A",
            "cfaV1Forwarder": "0x2CDd45c5182602a36d391F7F16DD9f8386C3bD8D",
            "idaV1": "0xA44dEC7A0Dde1a56AeDe4143C1ef89cf5d956782",
            "gdaV1": "0x51f571D934C59185f13d17301a36c07A2268B814",
            "gdaV1Forwarder": "0x6DA13Bde224A05a288748d857b9e7DDEffd1dE08",
            "superTokenFactory": "0x1C92042426B6bAAe497bEf461B6d8342D03aEc92",
            "superfluidLoader": "0x36446Ec9C7909608065dEB7f491701d815B880e5",
            "batchLiquidator": "0x85AfCf531aF1a853AC65F6bfa4de99C742B8e432",
            "autowrap": {
                "manager": "0x30aE282CF477E2eF28B14d0125aCEAd57Fe1d7a1",
                "wrapStrategy": "0x1D65c6d3AD39d454Ea8F682c49aE7744706eA96d"
            },
            "existentialNFTCloneFactory": "0xF76529ddEE7AA7890323eCa40C212758DD93B888",
            "macroForwarder": "0xFD0268E33111565dE546af2675351A4b1587F89F"
        },
        "startBlockV1": 3220000,
        "logsQueryRange": 50000,
        "explorer": "https://testnet.snowtrace.io",
        "subgraphV1": {
            "cliName": "fuji",
            "name": "protocol-v1-avalanche-fuji",
            "hostedEndpoint": "https://subgraph-endpoints.superfluid.dev/avalanche-fuji/protocol-v1"
        },
        "publicRPCs": [
            "https://api.avax-test.network/ext/bc/C/rpc",
            "https://avalanche-fuji-c-chain.publicnode.com"
        ],
        "trustedForwarders": [
            "0x6271Ca63D30507f2Dcbf99B52787032506D75BBF",
            "0xb539068872230f20456CF38EC52EF2f91AF4AE49",
            "0xd8253782c45a12053594b9deB72d8e8aB2Fca54c"
        ]
    },
    {
        "name": "eth-sepolia",
        "isTestnet": true,
        "networkId": 11155111,
        "chainId": 11155111,
        "sfId": 106,
        "shortName": "sepolia",
        "uppercaseName": "ETH_SEPOLIA",
        "humanReadableName": "Sepolia",
        "nativeTokenSymbol": "ETH",
        "nativeTokenWrapper": "0x30a6933Ca9230361972E413a15dC8114c952414e",
        "contractsV1": {
            "resolver": "0x6813edE4E78ecb830d380d0F7F684c12aAc95F02",
            "host": "0x109412E3C84f0539b43d39dB691B08c90f58dC7c",
            "cfaV1": "0x6836F23d6171D74Ef62FcF776655aBcD2bcd62Ef",
            "cfaV1Forwarder": "0xcfA132E353cB4E398080B9700609bb008eceB125",
            "idaV1": "0x9358C7dCCc6B8CA6F526311e8ac266F8C861B7ea",
            "gdaV1": "0x9823364056BcA85Dc3c4a3b96801314D082C8Eb9",
            "gdaV1Forwarder": "0x6DA13Bde224A05a288748d857b9e7DDEffd1dE08",
            "superTokenFactory": "0x254C2e152E8602839D288A7bccdf3d0974597193",
            "superfluidLoader": "0x862F59081FC7907F940bE4227b9f485d700E6cdD",
            "batchLiquidator": "0x79aE8BF8EE9238d8E848F7dbBF74Ddb3365f6c11",
            "existentialNFTCloneFactory": "0x0D1F0d4629B722b4dFabd195c14F12f2095418d9",
            "macroForwarder": "0xFD0268E33111565dE546af2675351A4b1587F89F"
        },
        "startBlockV1": 3322400,
        "logsQueryRange": 10000,
        "explorer": "https://sepolia.etherscan.io",
        "subgraphV1": {
            "cliName": "sepolia",
            "name": "protocol-v1-eth-sepolia",
            "hostedEndpoint": "https://subgraph-endpoints.superfluid.dev/eth-sepolia/protocol-v1"
        },
        "publicRPCs": [
            "https://rpc.sepolia.org",
            "https://ethereum-sepolia.blockpi.network/v1/rpc/public"
        ]
    },
    {
        "name": "optimism-sepolia",
        "isTestnet": true,
        "networkId": 11155420,
        "chainId": 11155420,
        "sfId": 109,
        "shortName": "opsepolia",
        "uppercaseName": "OPTIMISM_SEPOLIA",
        "humanReadableName": "Optimism Sepolia",
        "nativeTokenSymbol": "ETH",
        "nativeTokenWrapper": "0x0043d7c85C8b96a49A72A92C0B48CdC4720437d7",
        "contractsV1": {
            "resolver": "0x554c06487bEc8c890A0345eb05a5292C1b1017Bd",
            "host": "0xd399e2Fb5f4cf3722a11F65b88FAB6B2B8621005",
            "cfaV1": "0x8a3170AdbC67233196371226141736E4151e7C26",
            "cfaV1Forwarder": "0xcfA132E353cB4E398080B9700609bb008eceB125",
            "idaV1": "0x51BDA2C5F627d456E282257710F4A4b6Eb094A52",
            "gdaV1": "0xd453d38A001B47271488886532f1CCeAbf0c7eF3",
            "gdaV1Forwarder": "0x6DA13Bde224A05a288748d857b9e7DDEffd1dE08",
            "superTokenFactory": "0xfcF0489488397332579f35b0F711BE570Da0E8f5",
            "flowScheduler": "0x73B1Ce21d03ad389C2A291B1d1dc4DAFE7B5Dc68",
            "vestingScheduler": "0x27444c0235a4D921F3106475faeba0B5e7ABDD7a",
            "vestingSchedulerV2": "0x3aa62b96f44D0f8892BeBBC819DE8e02E9DE69A8",
            "autowrap": {
                "manager": "0xe567b32C10B0dB72d9490eB1B9A409C5ADed192C",
                "wrapStrategy": "0xf232f1fd34CE12e24F4391865c2D6E374D2C34d9"
            },
            "superfluidLoader": "0x109412E3C84f0539b43d39dB691B08c90f58dC7c",
            "batchLiquidator": "0x9539B21cC67844417E80aE168bc28c831E7Ed271",
            "macroForwarder": "0xFD0268E33111565dE546af2675351A4b1587F89F"
        },
        "startBlockV1": 6886559,
        "logsQueryRange": 50000,
        "explorer": "https://sepolia-optimism.etherscan.io",
        "subgraphV1": {
            "cliName": "optimism-sepolia",
            "name": "protocol-v1-optimism-sepolia",
            "hostedEndpoint": "https://subgraph-endpoints.superfluid.dev/optimism-sepolia/protocol-v1"
        },
        "subgraphVesting": {
            "name": "vesting-v1-optimism-sepolia",
            "hostedEndpoint": "https://subgraph-endpoints.superfluid.dev/optimism-sepolia/vesting-scheduler"
        },
        "subgraphFlowScheduler": {
            "name": "scheduling-v1-optimism-sepolia",
            "hostedEndpoint": "https://subgraph-endpoints.superfluid.dev/optimism-sepolia/flow-scheduler"
        },
        "subgraphAutoWrap": {
            "name": "auto-wrap-v1-optimism-sepolia",
            "hostedEndpoint": "https://subgraph-endpoints.superfluid.dev/optimism-sepolia/auto-wrap"
        },
        "publicRPCs": [
            "https://sepolia.optimism.io"
        ],
        "trustedForwarders": []
    },
    {
        "name": "scroll-sepolia",
        "isTestnet": true,
        "networkId": 534351,
        "chainId": 534351,
        "sfId": 110,
        "shortName": "scrsepolia",
        "uppercaseName": "SCROLL_SEPOLIA",
        "humanReadableName": "Scroll Sepolia",
        "nativeTokenSymbol": "ETH",
        "nativeTokenWrapper": "0x58f0A7c6c143074f5D824c2f27a85f6dA311A6FB",
        "contractsV1": {
            "resolver": "0xB62446a3006d86f6e9eAa36da773c311E7B8AF91",
            "host": "0x42b05a6016B9eED232E13fd56a8F0725693DBF8e",
            "cfaV1": "0xbc46B4Aa41c055578306820013d4B65fff42711E",
            "cfaV1Forwarder": "0xcfA132E353cB4E398080B9700609bb008eceB125",
            "idaV1": "0x296556422F44F19E5d216CBf98348A03BDc445E7",
            "gdaV1": "0x93fA9B627eE016990Fe5e654F923aaE8a480a75b",
            "gdaV1Forwarder": "0x6DA13Bde224A05a288748d857b9e7DDEffd1dE08",
            "superfluidLoader": "0xe25603df330027d91A0BAcc3e80a7f9e84930FC6",
            "batchLiquidator": "0x70bbB7a057A13070dF11d533e8f299357D778637",
            "superTokenFactory": "0x87560833d59Be057aFc63cFFa3fc531589Ba428F",
            "macroForwarder": "0xFD0268E33111565dE546af2675351A4b1587F89F"
        },
        "startBlockV1": 2823800,
        "logsQueryRange": 50000,
        "explorer": "https://sepolia.scrollscan.com/",
        "subgraphV1": {
            "cliName": "scroll-sepolia",
            "name": "protocol-v1-scroll-sepolia",
            "hostedEndpoint": "https://subgraph-endpoints.superfluid.dev/scroll-sepolia/protocol-v1"
        },
        "publicRPCs": ["https://sepolia-rpc.scroll.io"]
    },
    {
        "name": "base-sepolia",
        "isTestnet": true,
        "networkId": 84532,
        "chainId": 84532,
        "sfId": 111,
        "shortName": "bsepolia",
        "uppercaseName": "BASE_SEPOLIA",
        "humanReadableName": "Base Sepolia",
        "nativeTokenSymbol": "ETH",
        "nativeTokenWrapper": "0x143ea239159155B408e71CDbE836e8CFD6766732",
        "contractsV1": {
            "resolver": "0x21d4E9fbB9DB742E6ef4f29d189a7C18B0b59136",
            "host": "0x109412E3C84f0539b43d39dB691B08c90f58dC7c",
            "cfaV1": "0x6836F23d6171D74Ef62FcF776655aBcD2bcd62Ef",
            "cfaV1Forwarder": "0xcfA132E353cB4E398080B9700609bb008eceB125",
            "idaV1": "0x9358C7dCCc6B8CA6F526311e8ac266F8C861B7ea",
            "gdaV1": "0x53F4f44C813Dc380182d0b2b67fe5832A12B97f8",
            "gdaV1Forwarder": "0x6DA13Bde224A05a288748d857b9e7DDEffd1dE08",
            "superTokenFactory": "0x7447E94Dfe3d804a9f46Bf12838d467c912C8F6C",
            "superfluidLoader": "0x777Be25F9fdcA87e8a0E06Ad4be93d65429FCb9f",
            "batchLiquidator": "0x95043eC349476B413eF5c369c4d2454a1a65eaB9",
            "macroForwarder": "0xFD0268E33111565dE546af2675351A4b1587F89F"
        },
        "startBlockV1": 10604500,
        "logsQueryRange": 50000,
        "explorer": "https://sepolia.basescan.org",
        "subgraphV1": {
            "cliName": "base-sepolia"
        },
        "publicRPCs": [
            "https://sepolia.base.org"
        ]
    },
    {
        "name": "xdai-mainnet",
        "isTestnet": false,
        "networkId": 100,
        "chainId": 100,
        "sfId": 1,
        "shortName": "xdai",
        "uppercaseName": "XDAI_MAINNET",
        "humanReadableName": "Gnosis Chain",
        "nativeTokenSymbol": "xDAI",
        "nativeTokenWrapper": "0x59988e47A3503AaFaA0368b9deF095c818Fdca01",
        "duneName": "gnosis",
        "contractsV1": {
            "resolver": "0x9634Fa35188C59DD3B0ADa0Dd9adD7e4ECefc0a9",
            "host": "0x2dFe937cD98Ab92e59cF3139138f18c823a4efE7",
            "governance": "0xaCc7380323681fdb8a0B9F2FE7d69dDFf0664478",
            "cfaV1": "0xEbdA4ceF883A7B12c4E669Ebc58927FBa8447C7D",
            "cfaV1Forwarder": "0xcfA132E353cB4E398080B9700609bb008eceB125",
            "idaV1": "0x7888ac96F987Eb10E291F34851ae0266eF912081",
            "gdaV1": "0xd7992D358A20478c82dDEd98B3D8A9da46e99b82",
            "gdaV1Forwarder": "0x6DA13Bde224A05a288748d857b9e7DDEffd1dE08",
            "superTokenFactory": "0x23410e2659380784498509698ed70E414D384880",
            "superfluidLoader": "0xb688e4Da3100Bcec4b5B3140C8Fb482ad15D2013",
            "toga": "0xb7DE52F4281a7a276E18C40F94cd93159C4A2d22",
            "batchLiquidator": "0x96C3C2d23d143301cF363a02cB7fe3596d2834d7",
            "flowScheduler": "0x9cC7fc484fF588926149577e9330fA5b2cA74336",
            "vestingScheduler": "0x0170FFCC75d178d426EBad5b1a31451d00Ddbd0D",
            "wrapManager": "0x7a2899D179a8F205C8EDAd2e52954cA5f6d48D1A",
            "autowrap": {
                "manager": "0x8082e58681350876aFe8f52d3Bf8672034A03Db0",
                "wrapStrategy": "0x51FBAbD31A615E14b1bC12E9d887f60997264a4E"
            },
            "existentialNFTCloneFactory": "0xCd67c5bC1dfA3FF7d86b5ABc62A65C912Cbd2DA7",
            "macroForwarder": "0xFD0268E33111565dE546af2675351A4b1587F89F"
        },
        "startBlockV1": 14820000,
        "logsQueryRange": 20000,
        "explorer": "https://gnosisscan.io",
        "subgraphV1": {
            "cliName": "gnosis",
            "name": "protocol-v1-xdai",
            "hostedEndpoint": "https://subgraph-endpoints.superfluid.dev/xdai-mainnet/protocol-v1"
        },
        "subgraphVesting": {
            "name": "vesting-v1-xdai-mainnet",
            "hostedEndpoint": "https://subgraph-endpoints.superfluid.dev/xdai-mainnet/vesting-scheduler"
        },
        "subgraphFlowScheduler": {
            "name": "scheduling-v1-xdai-mainnet",
            "hostedEndpoint": "https://subgraph-endpoints.superfluid.dev/xdai-mainnet/flow-scheduler"
        },
        "subgraphAutoWrap": {
            "name": "auto-wrap-v1-xdai-mainnet",
            "hostedEndpoint": "https://subgraph-endpoints.superfluid.dev/xdai-mainnet/auto-wrap"
        },
        "publicRPCs": [
            "https://rpc.gnosischain.com",
            "https://gnosischain-rpc.gateway.pokt.network"
        ],
        "coinGeckoId": "xdai"
    },
    {
        "name": "polygon-mainnet",
        "isTestnet": false,
        "networkId": 137,
        "chainId": 137,
        "sfId": 2,
        "shortName": "matic",
        "uppercaseName": "POLYGON_MAINNET",
        "humanReadableName": "Polygon",
        "nativeTokenSymbol": "MATIC",
        "nativeTokenWrapper": "0x3aD736904E9e65189c3000c7DD2c8AC8bB7cD4e3",
        "duneName": "polygon",
        "contractsV1": {
            "resolver": "0x8bDCb5613153f41B2856F71Bd7A7e0432F6dbe58",
            "host": "0x3E14dC1b13c488a8d5D310918780c983bD5982E7",
            "governance": "0x3AD3f7A0965Ce6f9358AD5CCE86Bc2b05F1EE087",
            "cfaV1": "0x6EeE6060f715257b970700bc2656De21dEdF074C",
            "cfaV1Forwarder": "0xcfA132E353cB4E398080B9700609bb008eceB125",
            "idaV1": "0xB0aABBA4B2783A72C52956CDEF62d438ecA2d7a1",
            "gdaV1": "0x961dd5A052741B49B6CBf6759591f9D8576fCFb0",
            "gdaV1Forwarder": "0x6DA13Bde224A05a288748d857b9e7DDEffd1dE08",
            "superTokenFactory": "0x2C90719f25B10Fc5646c82DA3240C76Fa5BcCF34",
            "superfluidLoader": "0x444A48dA32649Ed03eeC9B9cD416748262c320E6",
            "toga": "0x6AEAeE5Fd4D05A741723D752D30EE4D72690A8f7",
            "batchLiquidator": "0xA7afDc46999076C295cfC6812dd73d103cF64e19",
            "flowScheduler": "0x55F7758dd99d5e185f4CC08d4Ad95B71f598264D",
            "vestingScheduler": "0xcFE6382B33F2AdaFbE46e6A26A88E0182ae32b0c",
            "autowrap": {
                "manager": "0x2581c27E7f6D6AF452E63fCe884EDE3EDd716b32",
                "wrapStrategy": "0xb4afa36BAd8c76976Dc77a21c9Ad711EF720eE4b"
            },
            "existentialNFTCloneFactory": "0x497aa106Da00BFa8f8BC266EF0793131930Fa630",
            "macroForwarder": "0xFD0268E33111565dE546af2675351A4b1587F89F"
        },
        "startBlockV1": 11650500,
        "logsQueryRange": 10000,
        "explorer": "https://polygonscan.com",
        "subgraphV1": {
            "cliName": "matic",
            "name": "protocol-v1-matic",
            "hostedEndpoint": "https://subgraph-endpoints.superfluid.dev/polygon-mainnet/protocol-v1"
        },
        "subgraphVesting": {
            "name": "vesting-v1-polygon-mainnet",
            "hostedEndpoint": "https://subgraph-endpoints.superfluid.dev/polygon-mainnet/vesting-scheduler"
        },
        "subgraphFlowScheduler": {
            "name": "scheduling-v1-polygon-mainnet",
            "hostedEndpoint": "https://subgraph-endpoints.superfluid.dev/polygon-mainnet/flow-scheduler"
        },
        "subgraphAutoWrap": {
            "name": "auto-wrap-v1-polygon-mainnet",
            "hostedEndpoint": "https://subgraph-endpoints.superfluid.dev/polygon-mainnet/auto-wrap"
        },
        "publicRPCs": [
            "https://polygon-rpc.com",
            "https://poly-rpc.gateway.pokt.network"
        ],
        "coinGeckoId": "polygon-pos"
    },
    {
        "name": "optimism-mainnet",
        "isTestnet": false,
        "networkId": 10,
        "chainId": 10,
        "sfId": 3,
        "shortName": "optimism",
        "uppercaseName": "OPTIMISM_MAINNET",
        "humanReadableName": "Optimism",
        "nativeTokenSymbol": "ETH",
        "nativeTokenWrapper": "0x4ac8bD1bDaE47beeF2D1c6Aa62229509b962Aa0d",
        "duneName": "optimism",
        "contractsV1": {
            "resolver": "0x743B5f46BC86caF41bE4956d9275721E0531B186",
            "host": "0x567c4B141ED61923967cA25Ef4906C8781069a10",
            "governance": "0x0170FFCC75d178d426EBad5b1a31451d00Ddbd0D",
            "cfaV1": "0x204C6f131bb7F258b2Ea1593f5309911d8E458eD",
            "cfaV1Forwarder": "0xcfA132E353cB4E398080B9700609bb008eceB125",
            "idaV1": "0xc4ce5118C3B20950ee288f086cb7FC166d222D4c",
            "gdaV1": "0x68Ae17fa7a31b86F306c383277552fd4813b0d35",
            "gdaV1Forwarder": "0x6DA13Bde224A05a288748d857b9e7DDEffd1dE08",
            "superTokenFactory": "0x8276469A443D5C6B7146BED45e2abCaD3B6adad9",
            "superfluidLoader": "0xe8B40071df98bBEe23833905AFcF7b28fC7Ca3cb",
            "toga": "0xA3c8502187fD7a7118eAD59dc811281448946C8f",
            "batchLiquidator": "0x84956C84c33c38AcE22C9324F1f92028AF2215ce",
            "flowScheduler": "0x55c8fc400833eEa791087cF343Ff2409A39DeBcC",
            "vestingScheduler": "0x65377d4dfE9c01639A41952B5083D58964782892",
            "vestingSchedulerV2": "0xe567b32C10B0dB72d9490eB1B9A409C5ADed192C",
            "autowrap": {
                "manager": "0x1fA76f2Cd0C3fe6c399A80111408d9C42C0CAC23",
                "wrapStrategy": "0x0Cf060a501c0040e9CCC708eFE94079F501c6Bb4"
            },
            "existentialNFTCloneFactory": "0xCb0Ff4D0cA186f0Fc0301258066Fe3fA258417a6",
            "macroForwarder": "0xFD0268E33111565dE546af2675351A4b1587F89F"
        },
        "startBlockV1": 4300000,
        "logsQueryRange": 50000,
        "explorer": "https://optimistic.etherscan.io",
        "subgraphV1": {
            "cliName": "optimism",
            "name": "protocol-v1-optimism-mainnet",
            "hostedEndpoint": "https://subgraph-endpoints.superfluid.dev/optimism-mainnet/protocol-v1"
        },
        "subgraphVesting": {
            "name": "vesting-v1-optimism-mainnet",
            "hostedEndpoint": "https://subgraph-endpoints.superfluid.dev/optimism-mainnet/vesting-scheduler"
        },
        "subgraphFlowScheduler": {
            "name": "scheduling-v1-optimism-mainnet",
            "hostedEndpoint": "https://subgraph-endpoints.superfluid.dev/optimism-mainnet/flow-scheduler"
        },
        "subgraphAutoWrap": {
            "name": "auto-wrap-v1-optimism-mainnet",
            "hostedEndpoint": "https://subgraph-endpoints.superfluid.dev/optimism-mainnet/auto-wrap"
        },
        "publicRPCs": [
            "https://mainnet.optimism.io",
            "https://rpc.ankr.com/optimism"
        ],
        "coinGeckoId": "optimistic-ethereum"
    },
    {
        "name": "arbitrum-one",
        "isTestnet": false,
        "networkId": 42161,
        "chainId": 42161,
        "sfId": 4,
        "shortName": "arbone",
        "uppercaseName": "ARBITRUM_ONE",
        "humanReadableName": "Arbitrum One",
        "nativeTokenSymbol": "ETH",
        "nativeTokenWrapper": "0xe6C8d111337D0052b9D88BF5d7D55B7f8385ACd3",
        "duneName": "arbitrum",
        "contractsV1": {
            "resolver": "0x609b9d9d6Ee9C3200745A79B9d3398DBd63d509F",
            "host": "0xCf8Acb4eF033efF16E8080aed4c7D5B9285D2192",
            "governance": "0x0170FFCC75d178d426EBad5b1a31451d00Ddbd0D",
            "cfaV1": "0x731FdBB12944973B500518aea61942381d7e240D",
            "cfaV1Forwarder": "0xcfA132E353cB4E398080B9700609bb008eceB125",
            "idaV1": "0x2319C7e07EB063340D2a0E36709B0D65fda75986",
            "gdaV1": "0x1e299701792a2aF01408B122419d65Fd2dF0Ba02",
            "gdaV1Forwarder": "0x6DA13Bde224A05a288748d857b9e7DDEffd1dE08",
            "superTokenFactory": "0x1C21Ead77fd45C84a4c916Db7A6635D0C6FF09D6",
            "superfluidLoader": "0xe8B40071df98bBEe23833905AFcF7b28fC7Ca3cb",
            "toga": "0xFC63B7C762B10670Eda15cF3ca3970bCDB28C9eF",
            "batchLiquidator": "0x9224413b9177E6c1D5721B4a4D1D00eC84B07Ce7",
            "flowScheduler": "0x3fA8B653F9abf91428800C0ba0F8D145a71F97A1",
            "vestingScheduler": "0x55c8fc400833eEa791087cF343Ff2409A39DeBcC",
            "autowrap": {
                "manager": "0xf01825eAFAe5CD1Dab5593EFAF218efC8968D272",
                "wrapStrategy": "0x342076aA957B0ec8bC1d3893af719b288eA31e61"
            },
            "existentialNFTCloneFactory": "0xF353978890204756fc5fa6dfbD16a91eac9E6f4d",
            "macroForwarder": "0xFD0268E33111565dE546af2675351A4b1587F89F"
        },
        "startBlockV1": 7600000,
        "logsQueryRange": 50000,
        "explorer": "https://arbiscan.io",
        "subgraphV1": {
            "cliName": "arbitrum-one",
            "name": "protocol-v1-arbitrum-one",
            "hostedEndpoint": "https://subgraph-endpoints.superfluid.dev/arbitrum-one/protocol-v1"
        },
        "subgraphVesting": {
            "name": "vesting-v1-arbitrum-one",
            "hostedEndpoint": "https://subgraph-endpoints.superfluid.dev/arbitrum-one/vesting-scheduler"
        },
        "subgraphFlowScheduler": {
            "name": "scheduling-v1-arbitrum-one",
            "hostedEndpoint": "https://subgraph-endpoints.superfluid.dev/arbitrum-one/flow-scheduler"
        },
        "subgraphAutoWrap": {
            "name": "auto-wrap-v1-arbitrum-one",
            "hostedEndpoint": "https://subgraph-endpoints.superfluid.dev/arbitrum-one/auto-wrap"
        },
        "publicRPCs": [
            "https://arb1.arbitrum.io/rpc",
            "https://arbitrum.blockpi.network/v1/rpc/public"
        ],
        "coinGeckoId": "arbitrum-one"
    },
    {
        "name": "avalanche-c",
        "isTestnet": false,
        "networkId": 43114,
        "chainId": 43114,
        "sfId": 5,
        "shortName": "avalanche",
        "uppercaseName": "AVALANCHE_C",
        "humanReadableName": "Avalanche C",
        "nativeTokenSymbol": "AVAX",
        "nativeTokenWrapper": "0xBE916845D8678b5d2F7aD79525A62D7c08ABba7e",
        "duneName": "avalanche_c",
        "contractsV1": {
            "resolver": "0x24a3F04F70B7f07B9673EadD3e146391BcfEa5c1",
            "host": "0x60377C7016E4cdB03C87EF474896C11cB560752C",
            "governance": "0xF74390BabA510ec2fE196c2e02B037380d7a6F12",
            "cfaV1": "0x6946c5B38Ffea373b0a2340b4AEf0De8F6782e58",
            "cfaV1Forwarder": "0xcfA132E353cB4E398080B9700609bb008eceB125",
            "idaV1": "0x1fA9fFe8Db73F701454B195151Db4Abb18423cf2",
            "gdaV1": "0xA7b197cD5b0cEF6d62c4A0a851E3581f5E62e4D2",
            "gdaV1Forwarder": "0x6DA13Bde224A05a288748d857b9e7DDEffd1dE08",
            "superTokenFactory": "0x464AADdBB2B80f3Cb666522EB7381bE610F638b4",
            "superfluidLoader": "0x42B709822F18595443c308c1BE5E63CbFEf06481",
            "toga": "0x3D9A67D5ec1E72CEcA8157e028855056786b6159",
            "batchLiquidator": "0x3b387638a5d33aE8772715642A21345f23Af824c",
            "flowScheduler": "0xF7AfF590E9DE493D7ACb421Fca7f1E35C1ad4Ce5",
            "vestingScheduler": "0x3fA8B653F9abf91428800C0ba0F8D145a71F97A1",
            "autowrap": {
                "manager": "0x8082e58681350876aFe8f52d3Bf8672034A03Db0",
                "wrapStrategy": "0x51FBAbD31A615E14b1bC12E9d887f60997264a4E"
            },
            "existentialNFTCloneFactory": "0x94aE5f52E401A5766b0877d2f030cFb9C3792BD7",
            "macroForwarder": "0xFD0268E33111565dE546af2675351A4b1587F89F"
        },
        "startBlockV1": 14700000,
        "logsQueryRange": 50000,
        "explorer": "https://snowtrace.io",
        "subgraphV1": {
            "cliName": "avalanche",
            "name": "protocol-v1-avalanche-c",
            "hostedEndpoint": "https://subgraph-endpoints.superfluid.dev/avalanche-c/protocol-v1"
        },
        "subgraphVesting": {
            "name": "vesting-v1-avalanche-c",
            "hostedEndpoint": "https://subgraph-endpoints.superfluid.dev/avalanche-c/vesting-scheduler"
        },
        "subgraphFlowScheduler": {
            "name": "scheduling-v1-avalanche-c",
            "hostedEndpoint": "https://subgraph-endpoints.superfluid.dev/avalanche-c/flow-scheduler"
        },
        "subgraphAutoWrap": {
            "name": "auto-wrap-v1-avalanche-c",
            "hostedEndpoint": "https://subgraph-endpoints.superfluid.dev/avalanche-c/auto-wrap"
        },
        "publicRPCs": [
            "https://api.avax.network/ext/bc/C/rpc",
            "https://rpc.ankr.com/avalanche"
        ],
        "coinGeckoId": "avalanche"
    },
    {
        "name": "bsc-mainnet",
        "isTestnet": false,
        "networkId": 56,
        "chainId": 56,
        "sfId": 5,
        "shortName": "bsc",
        "uppercaseName": "BSC_MAINNET",
        "humanReadableName": "BNB Smart Chain",
        "nativeTokenSymbol": "BNB",
        "nativeTokenWrapper": "0x529A4116F160c833c61311569D6B33dFF41fD657",
        "duneName": "bnb",
        "contractsV1": {
            "resolver": "0x69604aA4e9e8BF44A73C680997205Edb03A92E41",
            "host": "0xd1e2cFb6441680002Eb7A44223160aB9B67d7E6E",
            "governance": "0xee07D9fce4Cf2a891BC979E9d365929506C2982f",
            "cfaV1": "0x49c38108870e74Cb9420C0991a85D3edd6363F75",
            "cfaV1Forwarder": "0xcfA132E353cB4E398080B9700609bb008eceB125",
            "idaV1": "0x594ed9Cd773584B645aC1F5B11020d3b32cDF07d",
            "gdaV1": "0x3bbFA4C406719424C7f66CD97A8Fe27Af383d3e2",
            "gdaV1Forwarder": "0x6DA13Bde224A05a288748d857b9e7DDEffd1dE08",
            "superTokenFactory": "0x8bde47397301F0Cd31b9000032fD517a39c946Eb",
            "superfluidLoader": "0xF353978890204756fc5fa6dfbD16a91eac9E6f4d",
            "toga": "0xFCD84210f5d51Cd40a30443d44d6A5500d5D10dF",
            "batchLiquidator": "0x27636F8E129cdd4ccA0F30E2b4C116DDaC773bE5",
            "flowScheduler": "0x2f9e2A2A59405682d4F86779275CF5525AD7eC2B",
            "vestingScheduler": "0x9B91c27f78376383003C6A12Ad12B341d016C5b9",
            "autowrap": {
                "manager": "0x2AcdD61ac1EFFe1535109449c31889bdE8d7f325",
                "wrapStrategy": "0x9e308cb079ae130790F604b1030cDf386670f199"
            },
            "existentialNFTCloneFactory": "0xe9F27eb8cdAaA0B01a4034e109496C3026b01bd9",
            "macroForwarder": "0xFD0268E33111565dE546af2675351A4b1587F89F"
        },
        "startBlockV1": 18800000,
        "logsQueryRange": 5000,
        "explorer": "https://bscscan.com",
        "subgraphV1": {
            "cliName": "bsc",
            "name": "protocol-v1-bsc-mainnet",
            "hostedEndpoint": "https://subgraph-endpoints.superfluid.dev/bsc-mainnet/protocol-v1"
        },
        "subgraphVesting": {
            "name": "vesting-v1-bsc-mainnet",
            "hostedEndpoint": "https://subgraph-endpoints.superfluid.dev/bsc-mainnet/vesting-scheduler"
        },
        "subgraphFlowScheduler": {
            "name": "scheduling-v1-bsc-mainnet",
            "hostedEndpoint": "https://subgraph-endpoints.superfluid.dev/bsc-mainnet/flow-scheduler"
        },
        "subgraphAutoWrap": {
            "name": "auto-wrap-v1-bsc-mainnet",
            "hostedEndpoint": "https://subgraph-endpoints.superfluid.dev/bsc-mainnet/auto-wrap"
        },
        "publicRPCs": [
            "https://bscrpc.com",
            "https://bsc-dataseed.binance.org"
        ],
        "coinGeckoId": "binance-smart-chain"
    },
    {
        "name": "eth-mainnet",
        "isTestnet": false,
        "networkId": 1,
        "chainId": 1,
        "sfId": 6,
        "shortName": "mainnet",
        "uppercaseName": "ETH_MAINNET",
        "humanReadableName": "Ethereum",
        "nativeTokenSymbol": "ETH",
        "nativeTokenWrapper": "0xC22BeA0Be9872d8B7B3933CEc70Ece4D53A900da",
        "duneName": "ethereum",
        "contractsV1": {
            "resolver": "0xeE4cD028f5fdaAdeA99f8fc38e8bA8A57c90Be53",
            "host": "0x4E583d9390082B65Bef884b629DFA426114CED6d",
            "governance": "0xe2E14e2C4518cB06c32Cd0818B4C01f53E1Ba653",
            "cfaV1": "0x2844c1BBdA121E9E43105630b9C8310e5c72744b",
            "cfaV1Forwarder": "0xcfA132E353cB4E398080B9700609bb008eceB125",
            "idaV1": "0xbCF9cfA8Da20B591790dF27DE65C1254Bf91563d",
            "gdaV1": "0xAAdBB3Eee3Bd080f5353d86DdF1916aCA3fAC842",
            "gdaV1Forwarder": "0x6DA13Bde224A05a288748d857b9e7DDEffd1dE08",
            "superTokenFactory": "0x0422689cc4087b6B7280e0a7e7F655200ec86Ae1",
            "superfluidLoader": "0xcb05535bd212eCFC4B7b9db81d6C2C768b726776",
            "toga": "0x8B5a2CF69a56d7F8Fa027edcA23594cdDF544dDc",
            "batchLiquidator": "0x42B709822F18595443c308c1BE5E63CbFEf06481",
            "flowScheduler": "0xAA0cD305eD020137E302CeCede7b18c0A05aCCDA",
            "vestingScheduler": "0x39D5cBBa9adEBc25085a3918d36D5325546C001B",
            "autowrap": {
                "manager": "0x30aE282CF477E2eF28B14d0125aCEAd57Fe1d7a1",
                "wrapStrategy": "0x1D65c6d3AD39d454Ea8F682c49aE7744706eA96d"
            },
            "macroForwarder": "0xFD0268E33111565dE546af2675351A4b1587F89F"
        },
        "startBlockV1": 15870000,
        "logsQueryRange": 10000,
        "explorer": "https://etherscan.io",
        "subgraphV1": {
            "cliName": "mainnet",
            "name": "protocol-v1-eth-mainnet",
            "hostedEndpoint": "https://subgraph-endpoints.superfluid.dev/eth-mainnet/protocol-v1"
        },
        "subgraphVesting": {
            "name": "vesting-v1-eth-mainnet",
            "hostedEndpoint": "https://subgraph-endpoints.superfluid.dev/eth-mainnet/vesting-scheduler"
        },
        "subgraphFlowScheduler": {
            "name": "scheduling-v1-eth-mainnet",
            "hostedEndpoint": "https://subgraph-endpoints.superfluid.dev/eth-mainnet/flow-scheduler"
        },
        "subgraphAutoWrap": {
            "name": "auto-wrap-v1-eth-mainnet",
            "hostedEndpoint": "https://subgraph-endpoints.superfluid.dev/eth-mainnet/auto-wrap"
        },
        "publicRPCs": [
            "https://cloudflare-eth.com",
            "https://eth-rpc.gateway.pokt.network"
        ],
        "coinGeckoId": "ethereum"
    },
    {
        "name": "celo-mainnet",
        "isTestnet": false,
        "networkId": 42220,
        "chainId": 42220,
        "sfId": 7,
        "shortName": "celo",
        "uppercaseName": "CELO_MAINNET",
        "humanReadableName": "Celo",
        "nativeTokenSymbol": "CELO",
        "nativeTokenWrapper": "0x671425Ae1f272Bc6F79beC3ed5C4b00e9c628240",
        "duneName": "celo",
        "contractsV1": {
            "resolver": "0x05eE721BD4D803d6d477Aa7607395452B65373FF",
            "host": "0xA4Ff07cF81C02CFD356184879D953970cA957585",
            "governance": "0x0170FFCC75d178d426EBad5b1a31451d00Ddbd0D",
            "cfaV1": "0x9d369e78e1a682cE0F8d9aD849BeA4FE1c3bD3Ad",
            "cfaV1Forwarder": "0xcfA132E353cB4E398080B9700609bb008eceB125",
            "idaV1": "0x26747Fe93fAC8bF28E1e24A558a2bC7E4d9846cA",
            "gdaV1": "0x308b7405272d11494716e30C6E972DbF6fb89555",
            "gdaV1Forwarder": "0x6DA13Bde224A05a288748d857b9e7DDEffd1dE08",
            "superTokenFactory": "0x36be86dEe6BC726Ed0Cbd170ccD2F21760BC73D9",
            "superfluidLoader": "0xF0d7d1D47109bA426B9D8A3Cde1941327af1eea3",
            "toga": "0x9bCa3a623e7b2e248510d88B2894F54898d88F91",
            "batchLiquidator": "0xCb0Ff4D0cA186f0Fc0301258066Fe3fA258417a6",
            "existentialNFTCloneFactory": "0x051e766e2d8dc65ae2bFCF084A50AD0447634227",
            "macroForwarder": "0xFD0268E33111565dE546af2675351A4b1587F89F"
        },
        "startBlockV1": 16393000,
        "logsQueryRange": 20000,
        "explorer": "https://celoscan.io",
        "subgraphV1": {
            "cliName": "celo",
            "name": "protocol-v1-celo-mainnet",
            "hostedEndpoint": "https://subgraph-endpoints.superfluid.dev/celo-mainnet/protocol-v1"
        },
        "publicRPCs": ["https://forno.celo.org", "https://rpc.ankr.com/celo"],
        "coinGeckoId": "celo"
    },
    {
        "name": "base-mainnet",
        "isTestnet": false,
        "networkId": 8453,
        "chainId": 8453,
        "sfId": 8,
        "shortName": "base",
        "uppercaseName": "BASE_MAINNET",
        "humanReadableName": "Base",
        "nativeTokenSymbol": "ETH",
        "nativeTokenWrapper": "0x46fd5cfB4c12D87acD3a13e92BAa53240C661D93",
        "duneName": "base",
        "contractsV1": {
            "resolver": "0x6a214c324553F96F04eFBDd66908685525Da0E0d",
            "host": "0x4C073B3baB6d8826b8C5b229f3cfdC1eC6E47E74",
            "governance": "0x55F7758dd99d5e185f4CC08d4Ad95B71f598264D",
            "cfaV1": "0x19ba78B9cDB05A877718841c574325fdB53601bb",
            "cfaV1Forwarder": "0xcfA132E353cB4E398080B9700609bb008eceB125",
            "idaV1": "0x66DF3f8e14CF870361378d8F61356D15d9F425C4",
            "gdaV1": "0xfE6c87BE05feDB2059d2EC41bA0A09826C9FD7aa",
            "gdaV1Forwarder": "0x6DA13Bde224A05a288748d857b9e7DDEffd1dE08",
            "superTokenFactory": "0xe20B9a38E0c96F61d1bA6b42a61512D56Fea1Eb3",
            "superfluidLoader": "0x9F9EEd9Bbc38E9e0514fD9dFcc0Bca9869A9c534",
            "toga": "0xA87F76e99f6C8Ff8996d14f550ceF47f193D9A09",
            "batchLiquidator": "0x6b008BAc0e5846cB5d9Ca02ca0e801fCbF88B6f9",
            "flowScheduler": "0xC72CEd15204d02183c83fEbb918b183E400811Ee",
            "vestingScheduler": "0xDF92D0E6Bcb9385FDe99aD21Ff5e47Fb47E3c6b2",
            "vestingSchedulerV2": "0x7b77A34b8B76B66E97a5Ae01aD052205d5cbe257",
            "autowrap": {
                "manager": "0x5D0acD0864Ad07ba4E1E0474AE69Da87482e14A9",
                "wrapStrategy": "0xB29005319B0caB24cF6D4d24e8420E54BB29Cb0d"
            },
            "existentialNFTCloneFactory": "0x642332562BC60a4Bd9681E7bb1588f7456A497aC",
            "macroForwarder": "0xFD0268E33111565dE546af2675351A4b1587F89F"
        },
        "startBlockV1": 1000000,
        "logsQueryRange": 20000,
        "explorer": "https://basescan.org",
        "subgraphV1": {
            "cliName": "base",
            "name": "protocol-v1-base-mainnet",
            "hostedEndpoint": "https://subgraph-endpoints.superfluid.dev/base-mainnet/protocol-v1"
        },
        "subgraphVesting": {
            "name": "vesting-v1-base-mainnet",
            "hostedEndpoint": "https://subgraph-endpoints.superfluid.dev/base-mainnet/vesting-scheduler"
        },
        "subgraphFlowScheduler": {
            "name": "scheduling-v1-base-mainnet",
            "hostedEndpoint": "https://subgraph-endpoints.superfluid.dev/base-mainnet/flow-scheduler"
        },
        "subgraphAutoWrap": {
            "name": "auto-wrap-v1-base-mainnet",
            "hostedEndpoint": "https://subgraph-endpoints.superfluid.dev/base-mainnet/auto-wrap"
        },
        "publicRPCs": ["https://developer-access-mainnet.base.org"],
        "coinGeckoId": "base"
    },
    {
        "name": "scroll-mainnet",
        "isTestnet": false,
        "networkId": 534352,
        "chainId": 534352,
        "sfId": 9,
        "shortName": "scroll",
        "uppercaseName": "SCROLL_MAINNET",
        "humanReadableName": "Scroll",
        "nativeTokenSymbol": "ETH",
        "nativeTokenWrapper": "0x483C1716b6133cdA01237ebBF19c5a92898204B7",
        "duneName": "scroll",
        "contractsV1": {
            "resolver": "0xb25a19c0e7d10c8D37E5b63Ed3213b67f7ebfF80",
            "host": "0x0F86a21F6216c061B222c224e315d9FC34520bb7",
            "governance": "0xC2C9a709A6744816b3712D520BD314fe610AEa33",
            "cfaV1": "0xB3bcD6da1eeB6c97258B3806A853A6dcD3B6C00c",
            "cfaV1Forwarder": "0xcfA132E353cB4E398080B9700609bb008eceB125",
            "idaV1": "0x4112557F0F228A18654d3C39599421DE9F61144d",
            "gdaV1": "0x97a9f293d7eD13f3fbD499cE684Ed4F103295a28",
            "gdaV1Forwarder": "0x6DA13Bde224A05a288748d857b9e7DDEffd1dE08",
            "superfluidLoader": "0x7613030429E95cDFC76FE70f9573037068B51815",
            "toga": "0x1bF9D75d50fD828a93f69ECB06f2B85767792CEB",
            "batchLiquidator": "0x2eaa49BeB4Aa4fcC709DC14c0FA0fF1B292077b5",
            "superTokenFactory": "0xacFBED2bC9344C158DD3dC229b84Bd7220e7c673",
            "macroForwarder": "0xFD0268E33111565dE546af2675351A4b1587F89F"
        },
        "startBlockV1": 2575000,
        "logsQueryRange": 50000,
        "explorer": "https://scrollscan.com/",
        "subgraphV1": {
            "cliName": "scroll",
            "name": "protocol-v1-scroll-mainnet",
            "hostedEndpoint": "https://subgraph-endpoints.superfluid.dev/scroll-mainnet/protocol-v1"
        },
        "publicRPCs": ["https://rpc.scroll.io"]
    },
    {
        "name": "degenchain",
        "isTestnet": false,
        "networkId": 666666666,
        "chainId": 666666666,
        "sfId": 10,
        "shortName": "degen",
        "uppercaseName": "DEGENCHAIN",
        "humanReadableName": "Degen Chain",
        "nativeTokenSymbol": "DEGEN",
        "nativeTokenWrapper": "0xda58FA9bfc3D3960df33ddD8D4d762Cf8Fa6F7ad",
        "contractsV1": {
            "resolver": "0x649FB24ed0B983f88500F3C37682714aB96D73c2",
            "host": "0xc1314EdcD7e478C831a7a24169F7dEADB2646eD2",
            "governance": "0x4D420e94328bF1AEA1b525FDE9e498ADBe60f9B1",
            "cfaV1": "0x82cc052d1b17aC554a22A88D5876B56c6b51e95c",
            "cfaV1Forwarder": "0xcfA132E353cB4E398080B9700609bb008eceB125",
            "idaV1": "0xb19CE3e7DA9FbAf9De2526BD662A82f26421A53E",
            "gdaV1": "0x210a01ad187003603B2287F78579ec103Eb70D9B",
            "gdaV1Forwarder": "0x6DA13Bde224A05a288748d857b9e7DDEffd1dE08",
            "superfluidLoader": "0x5fb676d66eAb8E0c22Ae24C5c10eD7E4A6397c1C",
            "toga": "0x38ed5512Ac11926bB697F4CF4eE0DD04358E2E7e",
            "batchLiquidator": "0x7BCE8e8401dc98E3Da26F1D701c3C2168b8e466c",
            "superTokenFactory": "0x184D999ea60e9b16fE4cCC1f756422114E9B663f",
            "macroForwarder": "0xFD0268E33111565dE546af2675351A4b1587F89F"
        },
        "startBlockV1": 6500000,
        "logsQueryRange": 50000,
        "explorer": "https://explorer.degen.tips/",
        "subgraphV1": {
            "cliName": "degen",
            "name": "protocol-v1-degenchain",
            "hostedEndpoint": "https://subgraph-endpoints.superfluid.dev/degenchain/protocol-v1"
	    },
        "publicRPCs": ["https://rpc.degen.tips"]
    }
]
