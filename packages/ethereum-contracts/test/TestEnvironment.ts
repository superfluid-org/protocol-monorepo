import fs from "fs";

import {assert, expect} from "chai";
import {createObjectCsvWriter as createCsvWriter} from "csv-writer";
import {BigNumber} from "ethers";
import {ethers, network} from "hardhat";
import _ from "lodash";

import {
    ISuperToken__factory,
    PoolAdminNFT__factory,
    SuperTokenMock,
    TestToken,
} from "../typechain-types";

import {VerifyOptions} from "./contracts/agreements/Agreement.types";
import AgreementHelper from "./contracts/agreements/AgreementHelper";
import CFADataModel from "./contracts/agreements/ConstantFlowAgreementV1.data";
import {max, min, toBN, toWad, wad4human} from "./contracts/utils/helpers";
import {deployMockTestToken} from "./lib/deploy-mock-test-token";
import {createEthersFramework} from "./lib/ethers-framework";
import {loggedTx} from "./lib/logged-tx";
import {
    BenchmarkingData,
    CUSTOM_ERROR_CODES,
    CustomErrorCodeType,
    RealtimeBalance,
    TestEnvironmentConfigs,
    TestEnvironmentConstants,
    TestEnvironmentContracts,
    TestEnvironmentData,
    TestEnvironmentPlotData,
} from "./types";

const deployVariantFramework = require("./lib/deploy-variant-framework");

let _singleton: TestEnvironment;
let baselineSnapshotId: string | null = null;
let baselineResolverAddress: string | undefined;
const TOKEN_SYMBOL = "TEST";
/** Hardhat deploys a fresh framework; ignore repo .env RELEASE_VERSION (often v1). */
const HARDHAT_TEST_RELEASE_VERSION = "test";
const DEFAULT_TEST_TRAVEL_TIME = toBN(3600 * 24);

export type DeployFrameworkOptions = {
    useMocks?: boolean;
    nonUpgradable?: boolean;
    appWhiteListing?: boolean;
};

export type BeforeTestSuiteOptions = {
    nAccounts: number;
    tokens?: string[];
    /** Revert global deploy baseline (default) or the current file/describe snapshot. */
    fromSnapshot?: "baseline" | "file";
};

/** Hardhat test environment (ethers + typechain only). */
export default class TestEnvironment {
    agreementHelper: AgreementHelper;
    benchmarkingTemp: {startTime: number; testName: string};
    benchmarkingData: BenchmarkingData[];
    data: TestEnvironmentData;
    plotData: TestEnvironmentPlotData;
    /** Snapshot to revert to in beforeEach (file setup or nested describe). */
    _fileSnapshotId: string | null;
    /** Previous _fileSnapshotId values from pushEvmSnapshot (nested describes). */
    _describeSnapshotStack: string[];
    customErrorCode: CustomErrorCodeType;
    configs: TestEnvironmentConfigs;
    constants: TestEnvironmentConstants;
    gasReportType: string | undefined;
    contracts: TestEnvironmentContracts;
    aliases: {[alias: string]: string};
    accounts: string[];
    tokens: {TestToken: TestToken; SuperToken: SuperTokenMock};
    /** Legacy agreement behaviour tests. */
    sf: Awaited<ReturnType<typeof createEthersFramework>>;

    constructor() {
        this.benchmarkingTemp = {startTime: 0, testName: ""};
        this.benchmarkingData = [];
        this.data = {moreAliases: {}, tokens: {}};
        this.plotData = {enabled: false, observedAccounts: [], tokens: {}};
        this.aliases = {};
        this.accounts = [];
        this._fileSnapshotId = null;
        this._describeSnapshotStack = [];
        this.tokens = {} as any;
        this.sf = {} as any;

        this.agreementHelper = new AgreementHelper(this);
        this.customErrorCode = CUSTOM_ERROR_CODES;
        this.contracts = {} as any;
        this.configs = {
            INIT_BALANCE: toWad(100),
            AUM_DUST_AMOUNT: toBN(0),
            LIQUIDATION_PERIOD: toBN(3600),
            PATRICIAN_PERIOD: toBN(900),
            FLOW_RATE1: toWad(1).div(toBN(3600)),
            MINIMUM_DEPOSIT: CFADataModel.clipDepositNumber(toWad(0.25), false),
        };
        this.constants = {
            ZERO_ADDRESS: "0x0000000000000000000000000000000000000000",
            ZERO_BYTES32:
                "0x0000000000000000000000000000000000000000000000000000000000000000",
            MAX_UINT256: toBN("2").pow(toBN("256")).sub(toBN(1)),
            MAX_INT256: toBN("2").pow(toBN("255")).sub(toBN(1)),
            MIN_INT256: toBN("2").pow(toBN("255")).mul(toBN("-1")),
            MAXIMUM_FLOW_RATE: toBN(2).pow(toBN(95)).sub(toBN(1)),
            APP_LEVEL_FINAL: 1 << 0,
            APP_LEVEL_SECOND: 1 << 1,
        };
        this.gasReportType = process.env.ENABLE_GAS_REPORT_TYPE;
    }

    static getSingleton() {
        if (!_singleton) {
            _singleton = new TestEnvironment();
        }
        return _singleton as TestEnvironment;
    }

    async _takeEvmSnapshot() {
        return await network.provider.send("evm_snapshot");
    }

    async _revertToEvmSnapShot(evmSnapshotId: string) {
        return await network.provider.send("evm_revert", [evmSnapshotId]);
    }

    async pushEvmSnapshot() {
        const evmSnapshotId = await this._takeEvmSnapshot();
        if (this._fileSnapshotId) {
            this._describeSnapshotStack.push(this._fileSnapshotId);
        }
        this._fileSnapshotId = evmSnapshotId;
    }

    async popEvmSnapshot() {
        const previous = this._describeSnapshotStack.pop();
        if (previous !== undefined) {
            this._fileSnapshotId = previous;
        }
    }

    async _revertToFileSnapshot() {
        if (!this._fileSnapshotId) {
            throw new Error("No file snapshot to revert to");
        }
        await this._revertToEvmSnapShot(this._fileSnapshotId);
        this._fileSnapshotId = await this._takeEvmSnapshot();
    }

    async _revertToBaselineOnly() {
        if (!baselineSnapshotId) {
            throw new Error("Baseline snapshot not initialized");
        }
        if (baselineResolverAddress) {
            process.env.RESOLVER_ADDRESS = baselineResolverAddress;
        }
        await this._revertToEvmSnapShot(baselineSnapshotId);
        this._describeSnapshotStack = [];
        this._fileSnapshotId = null;
        this.tokens = {} as any;
    }

    /** @deprecated Prefer _revertToBaselineOnly + _captureBaselineSnapshot after harness repair. */
    async _revertToBaseline() {
        await this._revertToBaselineOnly();
        await this._captureBaselineSnapshot();
    }

    async _captureBaselineSnapshot() {
        baselineSnapshotId = await this._takeEvmSnapshot();
        baselineResolverAddress = process.env.RESOLVER_ADDRESS;
    }

    async _captureFileSnapshot() {
        this._fileSnapshotId = await this._takeEvmSnapshot();
    }

    async _advanceTimeAndBlock(seconds: number) {
        await network.provider.send("evm_increaseTime", [seconds]);
        await network.provider.send("evm_mine", []);
    }

    /** @deprecated Use beforeEachTestCase snapshot reset instead. */
    async useLastEvmSnapshot() {
        await this._revertToFileSnapshot();
    }

    async timeTravelOnce(time = DEFAULT_TEST_TRAVEL_TIME) {
        const jsNumTime = time.toNumber();
        const block1 = await ethers.provider.getBlock("latest");
        console.log("current block time", block1.timestamp);
        console.log(`time traveler going to the future +${jsNumTime}...`);
        await this._advanceTimeAndBlock(jsNumTime);
        const block2 = await ethers.provider.getBlock("latest");
        console.log("new block time", block2.timestamp);
    }

    async beforeTestSuite({
        nAccounts,
        fromSnapshot = "baseline",
    }: BeforeTestSuiteOptions) {
        const MAX_TEST_ACCOUNTS = 10;
        nAccounts = nAccounts || 0;
        assert(nAccounts <= MAX_TEST_ACCOUNTS);

        const signers = await ethers.getSigners();
        const allAccounts = signers.map((s) => s.address);
        const testAccounts = allAccounts.slice(0, nAccounts);
        this.setupDefaultAliases(testAccounts);

        let needsBaselineCapture = false;

        if (baselineSnapshotId === null) {
            needsBaselineCapture = true;
            if (!process.env.TESTENV_SNAPSHOT_VARS) {
                console.log("Creating a new evm snapshot");
                await this.deployFramework();
                await this.deployNewToken("TEST", {
                    accounts: allAccounts.slice(0, MAX_TEST_ACCOUNTS),
                });
            } else {
                console.log("Loading from externally saved snapshot");
                require("dotenv").config({
                    path: process.env.TESTENV_SNAPSHOT_VARS,
                });
                baselineSnapshotId = process.env.TESTENV_EVM_SNAPSHOT_ID || "";
                baselineResolverAddress = process.env.RESOLVER_ADDRESS;
                await this._revertToEvmSnapShot(baselineSnapshotId);
                needsBaselineCapture = true;
                await this.mintTestTokensAndApprove(
                    "TEST",
                    allAccounts.slice(0, nAccounts)
                );
            }
        } else if (fromSnapshot === "baseline") {
            needsBaselineCapture = true;
            await this._revertToBaselineOnly();
        } else {
            await this._revertToFileSnapshot();
        }

        await this.loadContractsFromFramework();
        await this.ensureGovernanceOwner();
        await this.getAndSetTestTokenAndSuperTokenMock(TOKEN_SYMBOL);

        if (needsBaselineCapture) {
            await this._captureBaselineSnapshot();
        }
        await this._captureFileSnapshot();
    }

    async ensureGovernanceOwner() {
        const sf = this.contracts.superfluid;
        let gov = this.contracts.governance;
        const govFromHost = await sf.getGovernance();
        if (govFromHost.toLowerCase() !== gov.address.toLowerCase()) {
            gov = await ethers.getContractAt("TestGovernance", govFromHost);
            this.contracts.governance = gov;
        }

        const hostSlot = await ethers.provider.getStorageAt(gov.address, 2);
        if (BigNumber.from(hostSlot).isZero()) {
            const admin =
                this.aliases.admin || (await ethers.getSigners())[0].address;
            await loggedTx("initialize TestGovernance", async () => {
                const owner = await gov.owner();
                return gov
                    .connect(await ethers.getSigner(owner))
                    .initialize(
                        sf.address,
                        admin,
                        this.configs.LIQUIDATION_PERIOD,
                        this.configs.PATRICIAN_PERIOD,
                        []
                    );
            });
        }

        const owner = await gov.owner();
        const admin =
            this.aliases.admin || (await ethers.getSigners())[0].address;
        if (owner.toLowerCase() !== admin.toLowerCase()) {
            await gov
                .connect(await ethers.getSigner(owner))
                .transferOwnership(admin);
        }
    }

    async loadContractsFromFramework() {
        const resolverAddress =
            process.env.RESOLVER_ADDRESS ||
            this.contracts.resolver?.address ||
            "";
        if (!resolverAddress) {
            throw new Error("Resolver address not set");
        }

        const resolver = await ethers.getContractAt(
            "Resolver",
            resolverAddress
        );
        const loader = await ethers.getContractAt(
            "SuperfluidLoader",
            await resolver.get("SuperfluidLoader-v1")
        );
        const loaded = await loader.loadFramework(HARDHAT_TEST_RELEASE_VERSION);

        const signer = await ethers.getSigner(
            this.accounts[0] || (await ethers.getSigners())[0].address
        );

        this.contracts.resolver = resolver;
        this.contracts.superfluid = await ethers.getContractAt(
            "SuperfluidMock",
            loaded.superfluid
        );
        this.contracts.cfa = await ethers.getContractAt(
            "ConstantFlowAgreementV1",
            loaded.agreementCFAv1
        );
        this.contracts.ida = await ethers.getContractAt(
            "InstantDistributionAgreementV1",
            loaded.agreementIDAv1
        );
        this.contracts.gda = await ethers.getContractAt(
            "GeneralDistributionAgreementV1",
            loaded.agreementGDAv1
        );

        await Promise.all([
            (this.contracts.erc1820 = await ethers.getContractAt(
                "IERC1820Registry",
                "0x1820a4B7618BdE71Dce8cdc73aAB6C95905faD24"
            )),
            (this.contracts.governance = await ethers.getContractAt(
                "TestGovernance",
                await this.contracts.superfluid.getGovernance()
            )),
            (this.contracts.ISuperToken = new ethers.Contract(
                "ISuperToken",
                ISuperToken__factory.abi,
                signer
            ) as TestEnvironmentContracts["ISuperToken"]),
        ]);

        this.sf = await createEthersFramework(
            this.contracts.superfluid,
            this.contracts.cfa,
            this.contracts.ida
        );
        this.agreementHelper = new AgreementHelper(this);
    }

    async beforeEachTestCase() {
        await this._revertToFileSnapshot();
        this.data = {moreAliases: {}, tokens: {}};
        this.plotData = {
            enabled: false,
            observedAccounts: [],
            tokens: {},
        };

        const gov = this.contracts.governance;
        const sf = this.contracts.superfluid;
        const govOwner = await gov.owner();
        const adminSigner = await ethers.getSigner(govOwner);
        const govAdmin = gov.connect(adminSigner);
        await loggedTx("reset 3Ps config", () =>
            govAdmin.setPPPConfig(
                sf.address,
                this.constants.ZERO_ADDRESS,
                this.configs.LIQUIDATION_PERIOD,
                this.configs.PATRICIAN_PERIOD
            )
        );
        await loggedTx("reset reward address to admin", () =>
            govAdmin.setRewardAddress(
                sf.address,
                this.constants.ZERO_ADDRESS,
                govOwner
            )
        );
        await loggedTx(
            `set superToken minimum deposit@${this.configs.MINIMUM_DEPOSIT.toString()}`,
            () =>
                govAdmin.setSuperTokenMinimumDeposit(
                    sf.address,
                    this.constants.ZERO_ADDRESS,
                    this.configs.MINIMUM_DEPOSIT
                )
        );
    }

    beforeEachTestCaseBenchmark(mocha: Mocha.Context) {
        this.benchmarkingTemp.testName =
            mocha.currentTest?.parent?.title +
                " | " +
                mocha.currentTest?.title || "n/a";
        this.benchmarkingTemp.startTime = performance.now();
    }

    afterEachTestCaseBenchmark() {
        this.benchmarkingData = [
            ...this.benchmarkingData,
            {
                totalTime: performance.now() - this.benchmarkingTemp.startTime,
                testName: this.benchmarkingTemp.testName,
            },
        ];
    }

    async deployFramework(deployOpts: DeployFrameworkOptions = {}) {
        process.env.IS_HARDHAT = "true";
        process.env.RELEASE_VERSION = HARDHAT_TEST_RELEASE_VERSION;
        await deployVariantFramework({
            newTestResolver: true,
            protocolReleaseVersion: HARDHAT_TEST_RELEASE_VERSION,
            useMocks: true,
            ...deployOpts,
        });
        const resolver = await ethers.getContractAt(
            "Resolver",
            process.env.RESOLVER_ADDRESS || ""
        );
        const loader = await ethers.getContractAt(
            "SuperfluidLoader",
            await resolver.get("SuperfluidLoader-v1")
        );
        const loaded = await loader.loadFramework(HARDHAT_TEST_RELEASE_VERSION);
        this.contracts.resolver = resolver;
        this.contracts.superfluid = await ethers.getContractAt(
            "SuperfluidMock",
            loaded.superfluid
        );
        this.contracts.cfa = await ethers.getContractAt(
            "ConstantFlowAgreementV1",
            loaded.agreementCFAv1
        );
        this.contracts.ida = await ethers.getContractAt(
            "InstantDistributionAgreementV1",
            loaded.agreementIDAv1
        );
        this.contracts.gda = await ethers.getContractAt(
            "GeneralDistributionAgreementV1",
            loaded.agreementGDAv1
        );

        const admin =
            this.aliases.admin || (await ethers.getSigners())[0].address;
        const govAddress = await this.contracts.superfluid.getGovernance();
        const gov = await ethers.getContractAt("TestGovernance", govAddress);
        const owner = await gov.owner();
        if (owner.toLowerCase() !== admin.toLowerCase()) {
            const ownerSigner = await ethers.getSigner(owner);
            await gov.connect(ownerSigner).transferOwnership(admin);
        }
    }

    getAndSetTestTokenAndSuperTokenMock = async (tokenSymbol: string) => {
        const testTokenAddress = await this.contracts.resolver.get(
            "tokens." + tokenSymbol
        );
        const testToken = await ethers.getContractAt(
            "TestToken",
            testTokenAddress
        );
        const releaseVersion = HARDHAT_TEST_RELEASE_VERSION;
        const superTokenKey = `supertokens.${releaseVersion}.${tokenSymbol}x`;
        const superTokenAddress =
            await this.contracts.resolver.get(superTokenKey);

        const superToken = (await ethers.getContractAt(
            "SuperTokenMock",
            superTokenAddress
        )) as unknown as SuperTokenMock;

        if (!this.tokens.TestToken) {
            this.tokens.TestToken = testToken;
        }
        if (!this.tokens.SuperToken) {
            this.tokens.SuperToken = superToken;
        }
        return {testToken, superToken};
    };

    async deployNewToken(
        tokenSymbol: string,
        {
            accounts,
            doUpgrade,
        }: {
            accounts?: string[];
            doUpgrade?: boolean;
        } = {}
    ) {
        accounts = accounts || this.accounts;
        const admin = accounts[0];

        const {testToken, superToken} = await deployMockTestToken(
            this.contracts.resolver,
            this.contracts.superfluid,
            tokenSymbol,
            admin
        );
        if (!this.tokens.TestToken) {
            this.tokens.TestToken = testToken;
        }
        if (!this.tokens.SuperToken) {
            this.tokens.SuperToken = superToken as unknown as SuperTokenMock;
        }
        await this.mintTestTokensAndApprove(tokenSymbol, accounts, doUpgrade);
        return {testToken, superToken};
    }

    async mintTestTokensAndApprove(
        tokenSymbol: string,
        accounts: string[],
        doUpgrade?: boolean
    ) {
        const {testToken, superToken} =
            await this.getAndSetTestTokenAndSuperTokenMock(tokenSymbol);

        for (let i = 0; i < accounts.length; ++i) {
            const userAddress = accounts[i];
            const signer = await ethers.getSigner(userAddress);
            await testToken
                .connect(signer)
                .approve(superToken.address, this.constants.MAX_UINT256);
            await testToken
                .connect(signer)
                .mint(userAddress, this.configs.INIT_BALANCE);
            if (doUpgrade) {
                await superToken
                    .connect(signer)
                    .upgrade(this.configs.INIT_BALANCE);
            }
        }
    }

    setupDefaultAliases(accounts: string[]) {
        this.accounts = accounts;
        this.aliases = {
            admin: accounts[0],
            alice: accounts[1],
            bob: accounts[2],
            carol: accounts[3],
            dan: accounts[4],
            eve: accounts[5],
            frank: accounts[6],
            grace: accounts[7],
            heidi: accounts[8],
            ivan: accounts[9],
        };
        Object.keys(this.aliases).forEach((alias) => {
            if (!this.aliases[alias]) delete this.aliases[alias];
        });
        console.log("Aliases", this.aliases);
    }

    listAliases() {
        return Object.keys(this.aliases).concat(
            Object.keys(this.data.moreAliases)
        );
    }

    listAddresses() {
        return Object.values(this.aliases).concat(
            Object.values(this.data.moreAliases)
        );
    }

    addAlias(alias: string, address: string) {
        this.data.moreAliases = _.merge(this.data.moreAliases, {
            [alias]: address,
        });
    }

    toAlias(address: string) {
        return (
            this.listAliases().find(
                (i) =>
                    this.getAddress(i).toLowerCase() === address.toLowerCase()
            ) || ""
        );
    }

    getAddress(alias?: string) {
        if (!alias) return "";
        return this.aliases[alias] || this.data.moreAliases[alias];
    }

    getFlowOperatorId(sender: string, flowOperator: string) {
        return ethers.utils.keccak256(
            ethers.utils.defaultAbiCoder.encode(
                ["string", "address", "address"],
                ["flowOperator", sender, flowOperator]
            )
        );
    }

    deployNFTContracts = async () => {
        const superTokenFactoryLogicAddress =
            await this.contracts.superfluid.getSuperTokenFactoryLogic();
        const superTokenFactory = await ethers.getContractAt(
            "SuperTokenFactory",
            superTokenFactoryLogicAddress
        );
        const superTokenLogicAddress =
            await superTokenFactory.getSuperTokenLogic();
        const superTokenLogic = await ethers.getContractAt(
            "SuperToken",
            superTokenLogicAddress
        );
        const poolAdminNFTProxyAddress = await superTokenLogic.POOL_ADMIN_NFT();
        const poolAdminNFT = PoolAdminNFT__factory.connect(
            poolAdminNFTProxyAddress,
            await ethers.getSigner(this.aliases.admin)
        );
        const paNFTLogicAddress = await poolAdminNFT.getCodeAddress();
        return {poolAdminNFTProxy: poolAdminNFT, paNFTLogicAddress};
    };

    deployContract = async <T>(contractName: string, ...args: any) => {
        const contractFactory = await ethers.getContractFactory(contractName);
        return (await contractFactory.deploy(...args)) as T;
    };

    async upgradeBalance(
        alias: string,
        amount: BigNumber,
        tokenSymbol = TOKEN_SYMBOL
    ) {
        const {testToken, superToken} =
            await this.getAndSetTestTokenAndSuperTokenMock(tokenSymbol);
        const account = this.getAddress(alias);
        const signer = await ethers.getSigner(account);
        await testToken
            .connect(signer)
            .mint(account, this.configs.INIT_BALANCE);
        await superToken.connect(signer).upgrade(amount);
        this.updateAccountBalanceSnapshot(
            superToken.address,
            account,
            await superToken.realtimeBalanceOfNow(account)
        );
    }

    async transferBalance(
        from: string,
        to: string,
        amount: BigNumber,
        tokenSymbol = TOKEN_SYMBOL
    ) {
        const {superToken} =
            await this.getAndSetTestTokenAndSuperTokenMock(tokenSymbol);
        const fromAccount = this.getAddress(from);
        const toAccount = this.getAddress(to);
        await superToken
            .connect(await ethers.getSigner(fromAccount))
            .transfer(toAccount, amount);
        this.updateAccountBalanceSnapshot(
            superToken.address,
            toAccount,
            await superToken.realtimeBalanceOfNow(toAccount)
        );
        this.updateAccountBalanceSnapshot(
            superToken.address,
            fromAccount,
            await superToken.realtimeBalanceOfNow(fromAccount)
        );
    }

    updateAccountBalanceSnapshot(
        superToken: string,
        account: string,
        balanceSnapshot: RealtimeBalance
    ) {
        assert.isDefined(account);
        assert.isDefined(balanceSnapshot);
        _.merge(this.data, {
            tokens: {
                [superToken]: {
                    accounts: {
                        [account]: {
                            balanceSnapshot: {
                                availableBalance:
                                    balanceSnapshot.availableBalance,
                                deposit: balanceSnapshot.deposit,
                                owedDeposit: balanceSnapshot.owedDeposit,
                                timestamp: balanceSnapshot.timestamp,
                            },
                        },
                    },
                },
            },
        });
    }

    getAccountBalanceSnapshot(superToken: string, account: string) {
        _.defaultsDeep(this.data, {
            tokens: {
                [superToken]: {
                    accounts: {
                        [account]: {
                            balanceSnapshot: {
                                availableBalance: 0,
                                deposit: 0,
                                owedDeposit: 0,
                                timestamp: 0,
                                description: "",
                            },
                        },
                    },
                },
            },
        });
        return _.clone(
            this.data.tokens[superToken].accounts[account].balanceSnapshot
        );
    }

    updateAccountExpectedBalanceDelta(
        superToken: string,
        account: string,
        expectedBalanceDelta: BigNumber
    ) {
        _.merge(this.data, {
            tokens: {
                [superToken]: {
                    accounts: {
                        [account]: {
                            expectedBalanceDelta:
                                expectedBalanceDelta.toString(),
                        },
                    },
                },
            },
        });
    }

    getAccountExpectedBalanceDelta(superToken: string, account: string) {
        _.defaultsDeep(this.data, {
            tokens: {
                [superToken]: {
                    accounts: {
                        [account]: {expectedBalanceDelta: "0"},
                    },
                },
            },
        });
        return toBN(
            this.data.tokens[superToken].accounts[account].expectedBalanceDelta
        );
    }

    formatRawBalanceSnapshot(
        rawBalanceSnapshot: RealtimeBalance,
        description: string
    ) {
        return {
            availableBalance: rawBalanceSnapshot.availableBalance,
            deposit: rawBalanceSnapshot.deposit,
            owedDeposit: rawBalanceSnapshot.owedDeposit,
            timestamp: rawBalanceSnapshot.timestamp,
            description,
        };
    }

    initializePlotData(enabled = false, observedAccounts: string[] = []) {
        this.plotData = {...this.plotData, enabled, observedAccounts};
    }

    updatePlotDataAccountBalanceSnapshot(
        superToken: string,
        account: string,
        rawBalanceSnapshot: RealtimeBalance,
        description: string
    ) {
        const observedAccounts = this.plotData.observedAccounts;
        if (
            observedAccounts.length > 0 &&
            !observedAccounts.includes(account)
        ) {
            return;
        }
        _.defaultsDeep(this.plotData, {
            tokens: {[superToken]: {accountBalanceSnapshots: {[account]: []}}},
        });
        const existing =
            this.plotData.tokens[superToken].accountBalanceSnapshots[account];
        const accountBalanceSnapshotsToMerge =
            existing.length === 0 ||
            existing[existing.length - 1].timestamp !==
                rawBalanceSnapshot.timestamp
                ? [
                      ...existing,
                      this.formatRawBalanceSnapshot(
                          rawBalanceSnapshot,
                          description
                      ),
                  ]
                : [...existing];
        _.merge(this.plotData, {
            tokens: {
                [superToken]: {
                    accountBalanceSnapshots: {
                        [account]: accountBalanceSnapshotsToMerge,
                    },
                },
            },
        });
    }

    formatPlotDataIntoProcessableFormat(superToken: string) {
        if (!this.plotData.tokens) return [];
        const accountBalanceSnapshots =
            this.plotData.tokens[superToken]?.accountBalanceSnapshots || {};
        return Object.entries(accountBalanceSnapshots)
            .filter(
                (x) =>
                    !_.every(x[1], (y) =>
                        y.availableBalance.eq(x[1][0].availableBalance)
                    )
            )
            .map((x) =>
                x[1].map((y) => ({
                    alias: this.toAlias(x[0]),
                    address: x[0],
                    availableBalance: wad4human(y.availableBalance.toString()),
                    deposit: wad4human(y.deposit.toString()),
                    owedDeposit: wad4human(y.owedDeposit.toString()),
                    timestamp: y.timestamp,
                    description: y.description,
                }))
            )
            .flat();
    }

    writePlotDataIntoCSVFile(path: string, superToken: string) {
        const outputDir = "./build/test_output";
        fs.mkdirSync(outputDir, {recursive: true});
        const csvFormatPlotData =
            this.formatPlotDataIntoProcessableFormat(superToken);
        const csvWriter = createCsvWriter({
            path: outputDir + "/" + path + ".csv",
            header: [
                {id: "alias", title: "alias"},
                {id: "timestamp", title: "timestamp"},
                {id: "availableBalance", title: "availableBalance"},
                {id: "deposit", title: "deposit"},
                {id: "owedDeposit", title: "owedDeposit"},
                {id: "address", title: "address"},
                {id: "description", title: "description"},
            ],
        });
        if (csvFormatPlotData.length > 0) {
            csvWriter.writeRecords(csvFormatPlotData).then(() => {
                console.log("CSV file created");
            });
        }
    }

    realtimeBalance(balance: RealtimeBalance) {
        return toBN(balance.availableBalance.toString()).add(
            max(
                toBN(0),
                toBN(balance.deposit.toString()).sub(
                    toBN(balance.owedDeposit.toString())
                )
            )
        );
    }

    printSingleBalance(title: string, balance: BigNumber) {
        console.log(
            `${title}:`,
            `${wad4human(balance)} (${balance.toString()})`
        );
    }

    printRealtimeBalance(title: string, balance: RealtimeBalance) {
        console.log(
            `${title}: `,
            `${wad4human(balance.availableBalance)} (${balance.availableBalance.toString()})`,
            `${wad4human(balance.deposit)} (${balance.deposit.toString()})`,
            `${wad4human(balance.owedDeposit)} (${balance.owedDeposit.toString()})`,
            balance.timestamp.toString()
        );
    }

    async validateExpectedBalances(
        syncExpectedBalancesFn: () => void,
        tokenSymbol = TOKEN_SYMBOL
    ) {
        const {superToken} =
            await this.getAndSetTestTokenAndSuperTokenMock(tokenSymbol);
        const txBlock = await ethers.provider.getBlock("latest");
        const balances2: {[address: string]: RealtimeBalance} = {};
        await Promise.all(
            this.listAddresses().map(async (address) => {
                balances2[address] = {
                    ...(await superToken.realtimeBalanceOf(
                        address,
                        txBlock.timestamp
                    )),
                    timestamp: toBN(txBlock.timestamp),
                };
            })
        );
        syncExpectedBalancesFn();
        await Promise.all(
            this.listAddresses().map(async (address) => {
                const alias = this.toAlias(address);
                const balanceSnapshot1 = this.getAccountBalanceSnapshot(
                    superToken.address,
                    address
                );
                const realtimeBalanceDelta = this.realtimeBalance(
                    balances2[address]
                ).sub(this.realtimeBalance(balanceSnapshot1));
                const expectedBalanceDelta =
                    this.getAccountExpectedBalanceDelta(
                        superToken.address,
                        address
                    );
                expect(
                    realtimeBalanceDelta.toString(),
                    `wrong real-time balance changes of ${alias}`
                ).to.equal(expectedBalanceDelta.toString());
                this.updateAccountBalanceSnapshot(
                    superToken.address,
                    address,
                    balances2[address]
                );
                this.updateAccountExpectedBalanceDelta(
                    superToken.address,
                    address,
                    toBN(0)
                );
            })
        );
    }

    async validateSystemInvariance(data?: VerifyOptions) {
        const {testToken, superToken} =
            await this.getAndSetTestTokenAndSuperTokenMock(
                data?.tokenSymbol || TOKEN_SYMBOL
            );
        const currentBlock = await ethers.provider.getBlock("latest");
        let rtBalanceSum = toBN(0);
        await Promise.all(
            this.listAliases().map(async (alias) => {
                const userAddress = this.getAddress(alias);
                const superTokenBalance = {
                    ...(await superToken.realtimeBalanceOf(
                        userAddress,
                        currentBlock.timestamp.toString()
                    )),
                    timestamp: toBN(currentBlock.timestamp),
                };
                const realtimeBalance = superTokenBalance.availableBalance
                    .add(superTokenBalance.deposit)
                    .sub(
                        min(
                            superTokenBalance.owedDeposit,
                            superTokenBalance.deposit
                        )
                    );
                if (this.plotData.enabled) {
                    this.updatePlotDataAccountBalanceSnapshot(
                        superToken.address,
                        userAddress,
                        superTokenBalance,
                        data?.description || ""
                    );
                }
                if (!data?.allowCriticalAccount) {
                    assert.isTrue(
                        superTokenBalance.availableBalance.gte(toBN(0)),
                        `${alias} account is critical`
                    );
                }
                rtBalanceSum = rtBalanceSum.add(
                    toBN(realtimeBalance.toString())
                );
            })
        );
        const aum = toBN(
            (await testToken.balanceOf(superToken.address)).toString()
        );
        const totalSupply = await superToken.totalSupply();
        assert.isTrue(aum.gte(rtBalanceSum));
        assert.isTrue(aum.sub(rtBalanceSum).lte(this.configs.AUM_DUST_AMOUNT));
        assert.equal(wad4human(aum, 8), wad4human(rtBalanceSum, 8));
        assert.equal(aum.toString(), totalSupply.toString());
    }
}
