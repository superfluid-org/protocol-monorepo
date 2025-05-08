import fs from "fs";

import {createObjectCsvWriter as createCsvWriter} from "csv-writer";
import {BigNumber} from "ethers";
import {artifacts, assert, ethers, expect, network, web3} from "hardhat";
import _ from "lodash";
import Web3 from "web3";

import {
    ISuperToken,
    ISuperToken__factory,
    PoolAdminNFT__factory,
    PoolMemberNFT__factory,
    SuperTokenMock,
    TestToken,
} from "../typechain-types";

import {VerifyOptions} from "./contracts/agreements/Agreement.types";
import AgreementHelper from "./contracts/agreements/AgreementHelper";
import CFADataModel from "./contracts/agreements/ConstantFlowAgreementV1.data";
import {max, min, toBN, toWad} from "./contracts/utils/helpers";
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

const {web3tx, wad4human} = require("@decentral.ee/web3-helpers");
const SuperfluidSDK = require("@superfluid-finance/js-sdk");
const traveler = require("ganache-time-traveler");

const deployFramework = require("../ops-scripts/deploy-framework");
const deploySuperToken = require("../ops-scripts/deploy-super-token");
const deployTestToken = require("../ops-scripts/deploy-test-token");

const SuperTokenMock = artifacts.require("SuperTokenMock");
const TestToken = artifacts.require("TestToken");

let _singleton: TestEnvironment;
const TOKEN_SYMBOL = "TEST";

const DEFAULT_TEST_TRAVEL_TIME = toBN(3600 * 24); // 24 hours

/**
 * @dev Test environment for test cases
 */
export default class TestEnvironment {
    agreementHelper: AgreementHelper;
    benchmarkingTemp: {
        startTime: number;
        testName: string;
    };
    benchmarkingData: BenchmarkingData[];
    data: TestEnvironmentData;
    plotData: TestEnvironmentPlotData;
    _evmSnapshots: {id: string; resolverAddress?: string}[];
    customErrorCode: CustomErrorCodeType;
    configs: TestEnvironmentConfigs;
    constants: TestEnvironmentConstants;
    gasReportType: string | undefined;
    contracts: TestEnvironmentContracts;
    aliases: {[alias: string]: string};
    accounts: string[];
    tokens: {TestToken: TestToken; SuperToken: SuperTokenMock};
    sf: any;

    constructor() {
        this.benchmarkingTemp = {
            startTime: 0,
            testName: "",
        };
        this.benchmarkingData = [];
        this.data = {
            moreAliases: {},
            tokens: {},
        };
        this.plotData = {
            enabled: false,
            observedAccounts: [],
            tokens: {},
        };
        this.aliases = {};
        this.accounts = [];
        this._evmSnapshots = [];
        this.tokens = {} as any;

        this.agreementHelper = new AgreementHelper(this);
        this.customErrorCode = CUSTOM_ERROR_CODES;

        this.contracts = {} as any;
        this.configs = {
            INIT_BALANCE: toWad(100),
            AUM_DUST_AMOUNT: toBN(0),
            LIQUIDATION_PERIOD: toBN(3600),
            PATRICIAN_PERIOD: toBN(900),
            FLOW_RATE1: toWad(1).div(toBN(3600)), // 1 per hour
            MINIMUM_DEPOSIT: CFADataModel.clipDepositNumber(toWad(0.25), false),
        };

        this.constants = {
            ZERO_ADDRESS: "0x0000000000000000000000000000000000000000",
            ZERO_BYTES32:
                "0x0000000000000000000000000000000000000000000000000000000000000000",
            MAX_UINT256: toBN("2").pow(toBN("256")).sub(toBN("1")),
            MAX_INT256: toBN("2").pow(toBN("255")).sub(toBN("1")),
            MIN_INT256: toBN("2").pow(toBN("255")).mul(toBN("-1")),
            MAXIMUM_FLOW_RATE: toBN(2).pow(toBN(95)).sub(toBN(1)),
            APP_LEVEL_FINAL: 1 << 0,
            APP_LEVEL_SECOND: 1 << 1,
        };

        this.gasReportType = process.env.ENABLE_GAS_REPORT_TYPE;
    }

    createErrorHandler() {
        return (err: any) => {
            if (err) throw err;
        };
    }

    static getSingleton() {
        if (!_singleton) {
            _singleton = new TestEnvironment();
        }
        return _singleton as TestEnvironment;
    }

    /**************************************************************************
     * EVM utilities
     **************************************************************************/

    async _takeEvmSnapshot() {
        return await network.provider.send("evm_snapshot");
    }

    async _revertToEvmSnapShot(evmSnapshotId: string) {
        // NOTE: the evm snapshot is actually deleted
        return await network.provider.send("evm_revert", [evmSnapshotId]);
    }

    async pushEvmSnapshot() {
        const evmSnapshotId = await this._takeEvmSnapshot();
        this._evmSnapshots.push({
            id: evmSnapshotId,
            resolverAddress: process.env.RESOLVER_ADDRESS,
        });
        console.debug(
            "pushEvmSnapshot",
            evmSnapshotId,
            JSON.stringify(this._evmSnapshots)
        );
    }

    async popEvmSnapshot() {
        this._evmSnapshots.pop();
        console.debug("popEvmSnapshot", JSON.stringify(this._evmSnapshots));
    }

    async useLastEvmSnapshot() {
        let oldEvmSnapshotId = "";
        const popped = this._evmSnapshots.pop();
        if (popped) {
            ({
                id: oldEvmSnapshotId,
                resolverAddress: process.env.RESOLVER_ADDRESS,
            } = popped);
        }
        await this._revertToEvmSnapShot(oldEvmSnapshotId);
        // move the time to now
        await traveler.advanceBlockAndSetTime(
            parseInt((Date.now() / 1000).toString())
        );
        const newEvmSnapshotId = await this._takeEvmSnapshot();
        this._evmSnapshots.push({
            id: newEvmSnapshotId,
            resolverAddress: process.env.RESOLVER_ADDRESS,
        });
        console.debug(
            "useLastEvmSnapshot",
            oldEvmSnapshotId,
            JSON.stringify(this._evmSnapshots)
        );
    }

    async timeTravelOnce(time = DEFAULT_TEST_TRAVEL_TIME) {
        const jsNumTime = time.toNumber();
        const block1 = await ethers.provider.getBlock("latest");
        console.log("current block time", block1.timestamp);
        console.log(`time traveler going to the future +${jsNumTime}...`);
        await traveler.advanceTimeAndBlock(jsNumTime);
        const block2 = await ethers.provider.getBlock("latest");
        console.log("new block time", block2.timestamp);
    }

    /**************************************************************************
     * Test suite and test case setup functions
     **************************************************************************/

    /**
     * @dev Run before the test suite
     * @param isTruffle Is test environment initialized in a truffle environment
     * @param nAccounts Number of test accounts to be loaded from web3
     * @param tokens Tokens to be loaded
     */
    async beforeTestSuite({
        isTruffle,
        nAccounts,
        tokens,
        web3,
    }: {
        isTruffle: boolean;
        nAccounts: number;
        tokens?: string[];
        web3?: Web3;
    }) {
        const MAX_TEST_ACCOUNTS = 10;
        nAccounts = nAccounts || 0;
        assert(nAccounts <= MAX_TEST_ACCOUNTS);
        tokens = typeof tokens === "undefined" ? ["TEST"] : tokens;
        const allAccounts = await (
            web3 || (global as any).web3
        ).eth.getAccounts();
        const testAccounts = allAccounts.slice(0, nAccounts);
        this.setupDefaultAliases(testAccounts);

        // deploy default test environment if needed
        if (this._evmSnapshots.length === 0) {
            // Can we load from externally saved snapshots?
            if (!process.env.TESTENV_SNAPSHOT_VARS) {
                console.log("Creating a new evm snapshot");
                await this.deployFramework({isTruffle, web3, useMocks: true});
                this.contracts.resolver = await ethers.getContractAt(
                    "Resolver",
                    process.env.RESOLVER_ADDRESS || ""
                );
                await this.deployNewToken("TEST", {
                    isTruffle,
                    web3,
                    accounts: allAccounts.slice(0, MAX_TEST_ACCOUNTS),
                });
                await this.pushEvmSnapshot();
            } else {
                console.log("Loading from externally saved snapshot");
                require("dotenv").config({
                    path: process.env.TESTENV_SNAPSHOT_VARS,
                });
                this._evmSnapshots.push({
                    id: process.env.TESTENV_EVM_SNAPSHOT_ID || "",
                    resolverAddress: process.env.RESOLVER_ADDRESS,
                });
                await this.useLastEvmSnapshot();
                await this.mintTestTokensAndApprove(
                    "TEST",
                    allAccounts.slice(0, nAccounts)
                );
                await this.pushEvmSnapshot();
            }
        } else {
            console.debug(
                "Current evm snapshots",
                JSON.stringify(this._evmSnapshots)
            );
            await this.useLastEvmSnapshot();
        }

        // load the SDK
        this.sf = new SuperfluidSDK.Framework({
            gasReportType: this.gasReportType,
            isTruffle: isTruffle,
            web3,
            version: process.env.RELEASE_VERSION || "test",
            tokens,
        });
        await this.sf.initialize();

        const signer = await ethers.getSigner(this.accounts[0]);

        // load contracts with testing/mocking interfaces
        await Promise.all([
            // load singletons
            (this.contracts.erc1820 = await ethers.getContractAt(
                "IERC1820Registry",
                "0x1820a4B7618BdE71Dce8cdc73aAB6C95905faD24"
            )),
            // load host contract
            (this.contracts.superfluid = await ethers.getContractAt(
                "SuperfluidMock",
                this.sf.host.address
            )),
            // load agreement contracts
            (this.contracts.cfa = await ethers.getContractAt(
                "ConstantFlowAgreementV1",
                this.sf.agreements.cfa.address
            )),
            (this.contracts.ida = await ethers.getContractAt(
                "InstantDistributionAgreementV1",
                this.sf.agreements.ida.address
            )),
            (this.contracts.gda = await ethers.getContractAt(
                "GeneralDistributionAgreementV1",
                await this.contracts.superfluid.getAgreementClass(
                    ethers.utils.solidityKeccak256(
                        ["string"],
                        [
                            "org.superfluid-finance.agreements.GeneralDistributionAgreement.v1",
                        ]
                    )
                )
            )),
            // load governance contract
            (this.contracts.governance = await ethers.getContractAt(
                "TestGovernance",
                await this.sf.host.getGovernance()
            )),
            (this.contracts.ISuperToken = new ethers.Contract(
                "ISuperToken",
                ISuperToken__factory.abi,
                signer
            ) as ISuperToken),
            (this.contracts.resolver = await ethers.getContractAt(
                "Resolver",
                this.sf.resolver.address
            )),
        ]);
        this.agreementHelper = new AgreementHelper(this);
    }

    /*
     * @dev Run before each test case
     */
    async beforeEachTestCase() {
        // return to the parent snapshot and save the same snapshot again
        await this.useLastEvmSnapshot();

        // test data can be persisted over a test case here
        this.data = {
            moreAliases: {},
            tokens: {},
        };

        // plot data can be persisted over a test case here
        this.plotData = {
            enabled: false,
            observedAccounts: [],
            tokens: {},
        };

        // reset governance parameters
        await Promise.all([
            await web3tx(
                this.contracts.governance.setPPPConfig,
                "reset 3Ps config"
            )(
                this.contracts.superfluid.address,
                this.constants.ZERO_ADDRESS,
                this.configs.LIQUIDATION_PERIOD,
                this.configs.PATRICIAN_PERIOD
            ),
            await web3tx(
                this.contracts.governance.setRewardAddress,
                "reset reward address to admin"
            )(
                this.contracts.superfluid.address,
                this.constants.ZERO_ADDRESS,
                this.aliases.admin
            ),
            await web3tx(
                this.contracts.governance.setSuperTokenMinimumDeposit,
                `set superToken minimum deposit@${this.configs.MINIMUM_DEPOSIT.toString()}`
            )(
                this.contracts.superfluid.address,
                this.constants.ZERO_ADDRESS,
                this.configs.MINIMUM_DEPOSIT.toString()
            ),
        ]);
    }
    beforeEachTestCaseBenchmark(mocha: Mocha.Context) {
        this.benchmarkingTemp.testName =
            mocha.currentTest?.parent?.title +
                " | " +
                mocha.currentTest?.title || "n/a";
        this.benchmarkingTemp.startTime = performance.now();
    }

    afterEachTestCaseBenchmark() {
        const benchmarkingData: BenchmarkingData = {
            totalTime: performance.now() - this.benchmarkingTemp.startTime,
            testName: this.benchmarkingTemp.testName,
        };
        this.benchmarkingData = [...this.benchmarkingData, benchmarkingData];
    }

    /// deploy framework
    async deployFramework(deployOpts: any) {
        // deploy framework
        await deployFramework(this.createErrorHandler(), {
            newTestResolver: true,
            isTruffle: deployOpts.isTruffle,
            web3: deployOpts.web3,
            useMocks: deployOpts.useMocks,
            ...deployOpts,
        });
    }

    getAndSetTestTokenAndSuperTokenMock = async (tokenSymbol: string) => {
        const testTokenAddress = await this.contracts.resolver.get(
            "tokens." + tokenSymbol
        );
        const testToken = await ethers.getContractAt(
            "TestToken",
            testTokenAddress
        );
        const superTokenKey = "supertokens.test." + tokenSymbol + "x";
        const superTokenAddress =
            await this.contracts.resolver.get(superTokenKey);

        const superToken = await ethers.getContractAt(
            "SuperTokenMock",
            superTokenAddress
        );

        if (!this.tokens.TestToken) {
            this.tokens.TestToken = testToken;
        }

        if (!this.tokens.SuperToken) {
            this.tokens.SuperToken = superToken;
        }

        return {testToken, superToken};
    };

    /// create a new test token (ERC20) and its super token
    async deployNewToken(
        tokenSymbol: string,
        {
            isTruffle,
            web3,
            accounts,
            doUpgrade,
        }: {
            isTruffle: boolean;
            web3?: Web3;
            accounts?: string[];
            doUpgrade?: boolean;
        }
    ) {
        accounts = accounts || this.accounts;

        await deployTestToken(this.createErrorHandler(), [":", tokenSymbol], {
            isTruffle: isTruffle,
            web3,
        });
        await deploySuperToken(this.createErrorHandler(), [":", tokenSymbol], {
            isTruffle: isTruffle,
            web3,
        });

        const {testToken, superToken} =
            await this.getAndSetTestTokenAndSuperTokenMock(tokenSymbol);

        await this.mintTestTokensAndApprove(tokenSymbol, accounts, doUpgrade);

        return {
            testToken,
            superToken,
        };
    }

    async mintTestTokensAndApprove(
        tokenSymbol: string,
        accounts: string[],
        doUpgrade?: boolean
    ) {
        const {testToken, superToken} =
            await this.getAndSetTestTokenAndSuperTokenMock(tokenSymbol);

        // mint test tokens to test accounts
        for (let i = 0; i < accounts.length; ++i) {
            const userAddress = accounts[i];

            console.log(`TestToken.approve by account[${i}] to SuperToken`);
            const signer = await ethers.getSigner(userAddress);
            console.log(superToken.address);
            await testToken
                .connect(signer)
                .approve(superToken.address, this.constants.MAX_UINT256);

            console.log(`Mint token for account[${i}]`);
            await testToken
                .connect(signer)
                .mint(userAddress, this.configs.INIT_BALANCE);

            if (doUpgrade) {
                console.log(`Upgrade token for account[${i}]`);
                await superToken
                    .connect(signer)
                    .upgrade(this.configs.INIT_BALANCE);
            }
        }
    }

    /**************************************************************************
     * Alias functions
     *************************************************************************/

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
        // delete undefined accounts
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

    /**************************************************************************
     * Agreement Util functions
     *************************************************************************/

    getFlowOperatorId(sender: string, flowOperator: string) {
        return web3.utils.keccak256(
            web3.eth.abi.encodeParameters(
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
        const poolMemberNFTProxyAddress =
            await superTokenLogic.POOL_MEMBER_NFT();

        const poolAdminNFT = PoolAdminNFT__factory.connect(
            poolAdminNFTProxyAddress,
            await ethers.getSigner(this.aliases.admin)
        );
        const poolMemberNFT = PoolMemberNFT__factory.connect(
            poolMemberNFTProxyAddress,
            await ethers.getSigner(this.aliases.admin)
        );
        const paNFTLogicAddress = await poolAdminNFT.getCodeAddress();
        const pmNFTLogicAddress = await poolMemberNFT.getCodeAddress();

        return {
            poolAdminNFTProxy: poolAdminNFT,
            poolMemberNFTProxy: poolMemberNFT,
            paNFTLogicAddress,
            pmNFTLogicAddress,
        };
    };

    deployContract = async <T>(contractName: string, ...args: any) => {
        const contractFactory = await ethers.getContractFactory(contractName);
        const contract = await contractFactory.deploy(...args);

        return contract as T;
    };

    /**************************************************************************
     * Test data functions
     *************************************************************************/

    async upgradeBalance(
        alias: string,
        amount: BigNumber,
        tokenSymbol = TOKEN_SYMBOL
    ) {
        const {testToken, superToken} =
            await this.getAndSetTestTokenAndSuperTokenMock(tokenSymbol);
        const account = this.getAddress(alias);
        const signer = await ethers.getSigner(account);

        console.log(`Mint token for ${alias}`);
        await testToken
            .connect(signer)
            .mint(account, this.configs.INIT_BALANCE);

        console.log(`Upgrade ${amount.toString()} for account ${alias}`);
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
        assert.isDefined(balanceSnapshot.timestamp.toString());
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
        assert.isDefined(account);
        assert.isDefined(expectedBalanceDelta.toString());
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
                        [account]: {
                            expectedBalanceDelta: "0",
                        },
                    },
                },
            },
        });
        return toBN(
            this.data.tokens[superToken].accounts[account].expectedBalanceDelta
        );
    }

    /**************************************************************************
     * Test Plot Data Functions
     **************************************************************************/

    formatRawBalanceSnapshot(
        rawBalanceSnapshot: RealtimeBalance,
        description: string
    ) {
        return {
            availableBalance: rawBalanceSnapshot.availableBalance,
            deposit: rawBalanceSnapshot.deposit,
            owedDeposit: rawBalanceSnapshot.owedDeposit,
            timestamp: rawBalanceSnapshot.timestamp,
            description: description,
        };
    }

    /**
     * @dev Sets the plotData object-call this in a more "local" before hook or at the start or end of a test case
     * @param enabled whether we want to record plot data
     * @param observedAccounts the accounts (addresses) we want to observe
     */
    initializePlotData(enabled = false, observedAccounts = []) {
        this.plotData = {
            ...this.plotData,
            enabled,
            observedAccounts,
        };
    }

    /**
     * @dev Takes a balance snapshot for the plotData object if account is observed or observedAccounts is empty
     * @param account the account we are adding an entry for
     * @param rawBalanceSnapshot the rawBalanceSnapshot to be formatted and added as an entry (row)
     * @param description the description to be used to showcase data points in charts
     */
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

        // initializes default data for an account if it doesn't exist
        _.defaultsDeep(this.plotData, {
            tokens: {
                [superToken]: {
                    accountBalanceSnapshots: {
                        [account]: [],
                    },
                },
            },
        });
        const existingAccountBalanceSnapshots =
            this.plotData.tokens[superToken].accountBalanceSnapshots[account];
        // we only want to add new entries if the timestamp has changed
        const accountBalanceSnapshotsToMerge =
            existingAccountBalanceSnapshots.length === 0 ||
            existingAccountBalanceSnapshots[
                existingAccountBalanceSnapshots.length - 1
            ].timestamp !== rawBalanceSnapshot.timestamp
                ? [
                      ...existingAccountBalanceSnapshots,
                      this.formatRawBalanceSnapshot(
                          rawBalanceSnapshot,
                          description
                      ),
                  ]
                : [...existingAccountBalanceSnapshots];

        // add a new entry to accountBalanceSnapshots
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

    /**
     * @dev Formats the accountBalanceSnapshots object into a processable format.
     * @param superToken
     * @returns an easily processable format (for csv)
     */
    formatPlotDataIntoProcessableFormat(superToken: string) {
        if (!this.plotData.tokens) {
            return [];
        }
        const accountBalanceSnapshots =
            this.plotData.tokens[superToken]?.accountBalanceSnapshots || {};
        return (
            Object.entries(accountBalanceSnapshots)
                // TODO: filter out unchanged account balance (for now)
                // maybe we want to monitor deposit, owedDeposit, etc,
                .filter(
                    (x) =>
                        !_.every(x[1], (y) =>
                            y.availableBalance.eq(x[1][0].availableBalance)
                        )
                )
                // map into new easily processable data
                .map((x) =>
                    x[1].map((y) => ({
                        alias: this.toAlias(x[0]),
                        address: x[0],
                        availableBalance: wad4human(
                            y.availableBalance.toString()
                        ),
                        deposit: wad4human(y.deposit.toString()),
                        owedDeposit: wad4human(y.owedDeposit.toString()),
                        timestamp: y.timestamp,
                        description: y.description,
                    }))
                )
                .flat()
        );
    }

    /**
     * @dev Writes the entirety of the data of a test into a csv file.
     * @param path the location the file is to be saved
     * @param superToken
     */
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
            csvWriter
                .writeRecords(csvFormatPlotData)
                .then(() => console.log("CSV file created"));
        }
    }

    /**************************************************************************
     * Logging utilities
     *************************************************************************/

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
            `${wad4human(
                balance.availableBalance
            )} (${balance.availableBalance.toString()})`,
            `${wad4human(balance.deposit)} (${balance.deposit.toString()})`,
            `${wad4human(
                balance.owedDeposit
            )} (${balance.owedDeposit.toString()})`,
            balance.timestamp.toString()
        );
    }

    /**************************************************************************
     * Invariance tests
     *************************************************************************/

    async validateExpectedBalances(
        syncExpectedBalancesFn: () => void,
        tokenSymbol = TOKEN_SYMBOL
    ) {
        const {superToken} =
            await this.getAndSetTestTokenAndSuperTokenMock(tokenSymbol);

        const txBlock = await ethers.provider.getBlock("latest");
        const balances2: {[address: string]: RealtimeBalance} = {};

        // update balance snapshot
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
                this.printSingleBalance(
                    `${alias} actual real-time balance delta`,
                    realtimeBalanceDelta
                );

                const expectedBalanceDelta =
                    this.getAccountExpectedBalanceDelta(
                        superToken.address,
                        address
                    );
                this.printSingleBalance(
                    `${alias} expected real-time balance delta`,
                    expectedBalanceDelta
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
        console.log("======== validateSystemInvariance begins ========");

        const currentBlock = await ethers.provider.getBlock("latest");

        let rtBalanceSum = toBN(0);
        await Promise.all(
            this.listAliases().map(async (alias) => {
                const userAddress = this.getAddress(alias);
                const tokenBalance = await testToken.balanceOf(
                    userAddress
                    /* TODO query old block currentBlock.timestamp*/
                );
                // @note TODO: create a convenience function which
                // only takes the necessary variables
                const superTokenBalance = {
                    ...(await superToken.realtimeBalanceOf(
                        userAddress,
                        currentBlock.timestamp.toString()
                    )),
                    timestamp: toBN(currentBlock.timestamp),
                };
                // Available Balance = Realtime Balance - Deposit + Min(Deposit, Owed Deposit)
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

                this.printSingleBalance(
                    `${alias} underlying token balance`,
                    tokenBalance
                );
                console.log(
                    `${alias} super token balance`,
                    wad4human(realtimeBalance)
                );
                this.printRealtimeBalance(
                    `${alias} super token balance (tuple)`,
                    superTokenBalance
                );

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

        this.printSingleBalance(
            "Total real-time balances of super tokens",
            rtBalanceSum
        );

        const aum = toBN(
            (await testToken.balanceOf(superToken.address)).toString()
        );
        this.printSingleBalance("AUM of super tokens", aum);

        const totalSupply = await superToken.totalSupply();
        this.printSingleBalance("Total supply of super tokens", totalSupply);

        assert.isTrue(
            aum.gte(rtBalanceSum),
            "AUM should be equal or more than real-time balance"
        );
        assert.isTrue(
            aum.sub(rtBalanceSum).lte(this.configs.AUM_DUST_AMOUNT),
            "AUM minus the real-time balance sum should only be a dust amount"
        );
        assert.equal(
            wad4human(aum, 8),
            wad4human(rtBalanceSum, 8),
            "AUM should match the real-time balance sum to at least 8 decimals during testing"
        );
        assert.equal(
            aum.toString(),
            totalSupply.toString(),
            "Total supply should be equal to the AUM"
        );

        console.log("======== validateSystemInvariance ends ========");
    }
}
