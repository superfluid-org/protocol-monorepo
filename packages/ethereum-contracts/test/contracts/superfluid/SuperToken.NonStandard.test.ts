import {SignerWithAddress} from "@nomiclabs/hardhat-ethers/signers";
import {BigNumberish} from "ethers";
import {artifacts, assert, ethers, expect, web3} from "hardhat";

import {
    CustomSuperTokenMock,
    MockSmartWallet,
    SuperfluidMock,
    SuperToken,
    SuperToken__factory,
    SuperTokenMock,
    SuperTokenStorageLayoutTester,
    TestToken,
} from "../../../typechain-types";
import TestEnvironment from "../../TestEnvironment";
import {expectCustomError, expectRevertedWith} from "../../utils/expectRevert";
import {toBN, toWad} from "../utils/helpers";

const {web3tx, toDecimals} = require("@decentral.ee/web3-helpers");

const TestToken = artifacts.require("TestToken");

describe("SuperToken's Non Standard Functions", function () {
    this.timeout(300e3);
    const t = TestEnvironment.getSingleton();

    const {MAX_UINT256, ZERO_ADDRESS} = t.constants;

    let admin: string, alice: string, bob: string;
    let aliceSigner: SignerWithAddress, bobSigner: SignerWithAddress;
    let superfluid: SuperfluidMock;
    let testToken: TestToken;
    let superToken: SuperTokenMock;
    let mockWallet: MockSmartWallet;
    let superTokenContract: SuperToken;

    before(async () => {
        await t.beforeTestSuite({
            isTruffle: true,
            nAccounts: 4,
        });

        testToken = t.tokens.TestToken;
        superToken = t.tokens.SuperToken;
        ({admin, alice, bob} = t.aliases);
        ({superfluid} = t.contracts);
        aliceSigner = await ethers.getSigner(alice);
        bobSigner = await ethers.getSigner(bob);
        superTokenContract = new ethers.Contract(
            "SuperToken",
            SuperToken__factory.abi,
            aliceSigner
        ) as SuperToken;
    });

    beforeEach(async function () {
        await t.beforeEachTestCase();
        t.beforeEachTestCaseBenchmark(this);
        const mockWalletFactory =
            await ethers.getContractFactory("MockSmartWallet");
        mockWallet = await mockWalletFactory.deploy();
    });

    afterEach(async () => {
        t.afterEachTestCaseBenchmark();
    });

    describe("#1 upgradability", () => {
        it("#1.1 storage layout", async () => {
            const {poolAdminNFTProxy, poolMemberNFTProxy} =
                await t.deployNFTContracts();
            const superTokenLogic =
                await t.deployContract<SuperTokenStorageLayoutTester>(
                    "SuperTokenStorageLayoutTester",
                    superfluid.address,
                    t.constants.ZERO_ADDRESS,
                    t.constants.ZERO_ADDRESS,
                    poolAdminNFTProxy.address,
                    poolMemberNFTProxy.address
                );
            await superTokenLogic.validateStorageLayout();
        });

        it("#1.2 proxiable info", async () => {
            assert.equal(
                await superToken.proxiableUUID(),
                web3.utils.sha3(
                    "org.superfluid-finance.contracts.SuperToken.implementation"
                )
            );
        });

        it("#1.3 only host can update the code", async () => {
            await expectCustomError(
                superToken.updateCode(ZERO_ADDRESS),
                superToken,
                "SUPER_TOKEN_ONLY_ADMIN"
            );
        });

        it("#1.4 only can initialize once", async () => {
            await expectRevertedWith(
                superToken.initialize(ZERO_ADDRESS, 18, "name", "symbol"),
                "Initializable: contract is already initialized"
            );
        });
    });

    describe("#2 SuperToken.upgrade/downgrade", () => {
        it("#2.1 - should upgrade if enough balance", async () => {
            const initialBalance = await testToken.balanceOf(alice);

            console.log("SuperToken.upgrade 2.0 tokens from alice");
            await expect(superToken.connect(aliceSigner).upgrade(toWad(2)))
                .to.emit(superToken, "TokenUpgraded")
                .withArgs(alice, toWad(2).toString());
            const {timestamp} = await ethers.provider.getBlock("latest");

            const finalBalance = await testToken.balanceOf(alice);
            const finalSuperTokenBalance = await superToken.balanceOf(alice);
            const finalRealBalance = await superToken.realtimeBalanceOf(
                alice,
                timestamp
            );

            assert.equal(
                finalSuperTokenBalance.toString(),
                toWad(2).toString(),
                "SuperToken.balanceOf is wrong"
            );
            assert.equal(
                initialBalance.sub(finalBalance).toString(),
                toWad(2).toString(),
                "SuperToken.upgrade should manage underlying tokens"
            );
            assert.equal(
                finalRealBalance.availableBalance.toString(),
                finalSuperTokenBalance.toString(),
                "balanceOf should equal realtimeBalanceOf"
            );

            await t.validateSystemInvariance();
        });

        it("#2.2 - should not upgrade without enough underlying balance", async () => {
            const initialBalance = await testToken.balanceOf(alice);
            console.log("SuperToken.upgrade - bad balance");
            await expectRevertedWith(
                superToken
                    .connect(aliceSigner)
                    .upgrade(initialBalance.add(toBN(1))),
                "ERC20: transfer amount exceeds balance"
            );
            await t.validateSystemInvariance();
        });

        it("#2.3 - should downgrade by single account", async () => {
            const initialBalance = await testToken.balanceOf(alice);

            console.log("SuperToken.upgrade 2 from alice");
            await superToken.connect(aliceSigner).upgrade(toWad(2));

            console.log("SuperToken.downgrade 1 from alice");
            await superToken.connect(aliceSigner).downgrade(toWad(1));

            const finalBalance = await testToken.balanceOf(alice);
            const finalSuperTokenBalance = await superToken.balanceOf(alice);

            assert.isOk(
                initialBalance.sub(finalBalance).toString(),
                toWad(1).toString()
            );
            assert.equal(
                finalSuperTokenBalance.toString(),
                toWad("1").toString(),
                "SuperToken.balanceOf is wrong"
            );

            await t.validateSystemInvariance();
        });

        it("#2.4 - should downgrade by multiple accounts", async () => {
            const initialBalanceAlice = await testToken.balanceOf(alice);
            const initialSuperBalanceAlice = await superToken.balanceOf(alice);

            console.log("SuperToken.upgrade 2 from alice");
            await superToken.connect(aliceSigner).upgrade(toWad(2));

            console.log("SuperToken.upgrade 1 from bob");
            await superToken.connect(bobSigner).upgrade(toWad(1));

            const initialSuperBalanceBob = await superToken.balanceOf(bob);

            console.log("SuperToken.downgrade 2 from alice");
            await superToken.connect(aliceSigner).downgrade(toWad(2));

            const finalBalanceAlice = await testToken.balanceOf(alice);
            const finalSuperBalanceAlice = await superToken.balanceOf(alice);
            const finalSuperBalanceBob = await superToken.balanceOf(bob);

            assert.equal(
                initialBalanceAlice.toString(),
                finalBalanceAlice.toString(),
                "TestToken.balanceOf - not correct for alice"
            );
            assert.equal(
                initialSuperBalanceAlice.toString(),
                finalSuperBalanceAlice.toString(),
                "SuperToken.balanceOf - not correct for user 1"
            );
            assert.equal(
                initialSuperBalanceBob.toString(),
                finalSuperBalanceBob.toString(),
                "SuperToken.balanceOf - not correct for user 2"
            );

            await t.validateSystemInvariance();
        });

        it("#2.5 - should not downgrade if there is no balance", async () => {
            console.log("SuperToken.downgrade - bad balance");
            await expectCustomError(
                superToken.connect(aliceSigner).downgrade(toBN(1)),
                superToken,
                "SF_TOKEN_BURN_INSUFFICIENT_BALANCE"
            );
        });

        it("#2.6 should not be able to downgradeTo self if there is no balance", async () => {
            console.log("SuperToken.downgradeTo self - bad balance");
            await expectCustomError(
                superToken
                    .connect(aliceSigner)
                    .downgradeTo(aliceSigner.address, toBN(1)),
                superToken,
                "SF_TOKEN_BURN_INSUFFICIENT_BALANCE"
            );
        });

        it("#2.7 should not be able to downgradeTo others if there is no balance", async () => {
            console.log("SuperToken.downgradeTo alice -> bob - bad balance");
            await expectCustomError(
                superToken
                    .connect(aliceSigner)
                    .downgradeTo(bobSigner.address, toBN(1)),
                superToken,
                "SF_TOKEN_BURN_INSUFFICIENT_BALANCE"
            );
        });

        it("#2.8 should be able to downgradeTo self", async () => {
            console.log("SuperToken.upgrade 2 from alice");
            await superToken.connect(aliceSigner).upgrade(toWad(2));
            const downgradeAmount = toBN(1);
            console.log("SuperToken.downgradeTo self");
            await assertDowngradeToBalances({
                superToken,
                testToken,
                sender: aliceSigner.address,
                receiver: aliceSigner.address,
                downgradeAmount,
            });

            await t.validateSystemInvariance();
        });

        it("#2.9 should be able to downgradeTo other EOA", async () => {
            console.log("SuperToken.upgrade 2 from alice");
            await superToken.connect(aliceSigner).upgrade(toWad(2));
            const downgradeAmount = toBN(1);
            console.log("SuperToken.downgradeTo alice -> bob");
            await assertDowngradeToBalances({
                superToken,
                testToken,
                sender: aliceSigner.address,
                receiver: bobSigner.address,
                downgradeAmount,
            });

            await t.validateSystemInvariance();
        });

        it("#2.10 should be able to downgradeTo contract (doesn't make a difference)", async () => {
            const mockFactory = await ethers.getContractFactory(
                "ERC777SenderRecipientMock"
            );
            const mock = await mockFactory.deploy();

            console.log("SuperToken.upgrade 2 from alice");
            await superToken.connect(aliceSigner).upgrade(toWad(2));
            const downgradeAmount = toBN(1);
            console.log("SuperToken.downgradeTo alice -> bob");
            await assertDowngradeToBalances({
                superToken,
                testToken,
                sender: aliceSigner.address,
                receiver: mock.address,
                downgradeAmount,
            });

            await t.validateSystemInvariance();
        });

        it("#2.6 - should convert from smaller underlying decimals", async () => {
            const token6D = await web3tx(TestToken.new, "TestToken.new")(
                "Test Token 6 Decimals",
                "TEST6D",
                6,
                ethers.utils.parseUnits((1e12).toString()),
                {
                    from: bob,
                }
            );
            await web3tx(token6D.mint, "Mint testToken for bob")(
                bob,
                toDecimals("100", 6),
                {
                    from: bob,
                }
            );
            assert.equal(
                (await token6D.balanceOf(bob)).toString(),
                toDecimals("100", 6)
            );

            const superToken6D = await t.sf.createERC20Wrapper(token6D);
            assert.equal((await superToken6D.balanceOf(bob)).toString(), "0");

            await web3tx(
                token6D.approve,
                "TestToken.approve - from bob to SuperToken"
            )(superToken6D.address, MAX_UINT256, {
                from: bob,
            });

            await web3tx(superToken6D.upgrade, "upgrade 1 from bob")(toWad(1), {
                from: bob,
            });
            assert.equal(
                (await superToken6D.balanceOf(bob)).toString(),
                toWad(1).toString()
            );
            assert.equal(
                (await token6D.balanceOf(bob)).toString(),
                toDecimals("99", 6)
            );

            await web3tx(superToken6D.upgrade, "upgrade 0.1234567 from bob")(
                toWad("0.1234567"),
                {
                    from: bob,
                }
            );
            assert.equal(
                (await token6D.balanceOf(bob)).toString(),
                toDecimals("98.876544", 6)
            );
            assert.equal(
                (await superToken6D.balanceOf(bob)).toString(),
                toWad("1.123456").toString()
            );

            await web3tx(superToken6D.downgrade, "downgrade from bob")(
                toWad(1),
                {
                    from: bob,
                }
            );
            assert.equal(
                (await token6D.balanceOf(bob)).toString(),
                toDecimals("99.876544", 6)
            );
            assert.equal(
                (await superToken6D.balanceOf(bob)).toString(),
                toWad("0.123456").toString()
            );

            // extra decimals should be discarded due to precision issue
            await web3tx(
                superToken6D.downgrade,
                "downgrade extra decimals from bob"
            )(toWad("0.10000012345"), {
                from: bob,
            });
            assert.equal(
                (await token6D.balanceOf(bob)).toString(),
                toDecimals("99.976544", 6)
            );
            assert.equal(
                (await superToken6D.balanceOf(bob)).toString(),
                toWad("0.023456").toString()
            );

            // downgrade the rest
            await web3tx(superToken6D.downgrade, "downgrade the rest from bob")(
                toWad("0.023456"),
                {
                    from: bob,
                }
            );
            assert.equal(
                (await token6D.balanceOf(bob)).toString(),
                toDecimals("100", 6)
            );
            assert.equal(
                (await superToken6D.balanceOf(bob)).toString(),
                toWad("0").toString()
            );
        });

        it("#2.7 - should convert from larger underlying decimals", async () => {
            const token20D = await web3tx(TestToken.new, "TestToken.new")(
                "Test Token 20 Decimals",
                "TEST20D",
                20,
                ethers.utils.parseUnits((1e12).toString()),
                {
                    from: bob,
                }
            );
            await web3tx(token20D.mint, "Mint testToken for bob")(
                bob,
                toDecimals("100", 20),
                {
                    from: bob,
                }
            );
            assert.equal(
                (await token20D.balanceOf(bob)).toString(),
                toDecimals("100", 20)
            );

            const superToken6D = await t.sf.createERC20Wrapper(token20D);
            assert.equal((await superToken6D.balanceOf(bob)).toString(), "0");

            await web3tx(
                token20D.approve,
                "TestToken.approve - from bob to SuperToken"
            )(superToken6D.address, MAX_UINT256, {
                from: bob,
            });

            await web3tx(superToken6D.upgrade, "upgrade 1 from bob")(toWad(1), {
                from: bob,
            });
            assert.equal(
                (await superToken6D.balanceOf(bob)).toString(),
                toWad(1).toString()
            );
            assert.equal(
                (await token20D.balanceOf(bob)).toString(),
                toDecimals("99", 20)
            );

            await web3tx(superToken6D.downgrade, "downgrade 1 from bob")(
                toWad(1),
                {
                    from: bob,
                }
            );
            assert.equal(
                (await token20D.balanceOf(bob)).toString(),
                toDecimals("100", 20)
            );
            assert.equal(
                (await superToken6D.balanceOf(bob)).toString(),
                toWad("0").toString()
            );
        });

        it("#2.8 - should upgradeTo if enough balance", async () => {
            const initialBalanceAlice = await testToken.balanceOf(alice);
            const initialBalanceBob = await testToken.balanceOf(bob);

            console.log("SuperToken.upgrade 2.0 tokens from alice to bob");
            await expect(
                superToken.connect(aliceSigner).upgradeTo(bob, toWad(2), "0x")
            )
                .to.emit(superToken, "TokenUpgraded")
                .withArgs(bob, toWad(2).toString());
            const {timestamp} = await ethers.provider.getBlock("latest");

            const finalBalanceAlice = await testToken.balanceOf(alice);
            const finalSuperTokenBalanceAlice =
                await superToken.balanceOf(alice);
            const finalRealBalanceAlice = await superToken.realtimeBalanceOf(
                alice,
                timestamp
            );

            const finalBalanceBob = await testToken.balanceOf(bob);
            const finalSuperTokenBalanceBob = await superToken.balanceOf(bob);
            const finalRealBalanceBob = await superToken.realtimeBalanceOf(
                bob,
                timestamp
            );

            assert.equal(
                initialBalanceAlice.sub(finalBalanceAlice).toString(),
                toWad(2).toString(),
                "(alice) SuperToken.upgradeTo should manage underlying tokens"
            );
            assert.equal(
                finalSuperTokenBalanceAlice.toString(),
                "0",
                "(alice) SuperToken.balanceOf is wrong"
            );
            assert.equal(
                finalRealBalanceAlice.availableBalance.toString(),
                finalSuperTokenBalanceAlice.toString(),
                "(alice) balanceOf should equal realtimeBalanceOf"
            );

            assert.equal(
                initialBalanceBob.sub(finalBalanceBob).toString(),
                "0",
                "(bob) SuperToken.upgradeTo should not affect recipient"
            );
            assert.equal(
                finalSuperTokenBalanceBob.toString(),
                toWad(2).toString(),
                "(bob) SuperToken.balanceOf is wrong"
            );
            assert.equal(
                finalRealBalanceBob.availableBalance.toString(),
                finalSuperTokenBalanceBob.toString(),
                "(bob) balanceOf should equal realtimeBalanceOf"
            );

            await t.validateSystemInvariance();
        });

        it("#2.9 - upgradeTo should not revert for unregistered contract if no user data is passed to tokensReceived", async () => {
            const mockFactory = await ethers.getContractFactory(
                "ERC777SenderRecipientMock"
            );
            const mock = await mockFactory.deploy();
            console.log(
                "SuperToken.upgrade 2.0 tokens from alice to unregistered mock w/ empty userData"
            );
            await superToken
                .connect(aliceSigner)
                .upgradeTo(mock.address, toWad(2), "0x");
        });

        it("#2.10 - upgradeTo should revert for unregistered contract if user data is passed to tokensReceived", async () => {
            const mockFactory = await ethers.getContractFactory(
                "ERC777SenderRecipientMock"
            );
            const mock = await mockFactory.deploy();
            console.log(
                "SuperToken.upgrade 2.0 tokens from alice to unregistered mock w/ non-empty userData"
            );
            await expectCustomError(
                superToken
                    .connect(aliceSigner)
                    .upgradeTo(mock.address, toWad(2), "0x4206"),
                superToken,
                "SUPER_TOKEN_NOT_ERC777_TOKENS_RECIPIENT"
            );
        });

        it("#2.11 - upgradeTo should not revert for registered contract if no userData is passed to tokensReceived", async () => {
            const mockFactory = await ethers.getContractFactory(
                "ERC777SenderRecipientMock"
            );
            const mock = await mockFactory.deploy();

            console.log("registerRecipient");
            await mock.registerRecipient(mock.address);
            console.log(
                "SuperToken.upgrade 2.0 tokens from alice to registered mock w/ empty userData"
            );
            await superToken
                .connect(aliceSigner)
                .upgradeTo(mock.address, toWad(2), "0x");
        });

        it("#2.12 - upgradeTo should not revert for registered contract if userData is passed to tokensReceived", async () => {
            const mockFactory = await ethers.getContractFactory(
                "ERC777SenderRecipientMock"
            );
            const mock = await mockFactory.deploy();

            console.log("registerRecipient");
            await mock.registerRecipient(mock.address);
            console.log(
                "SuperToken.upgrade 2.0 tokens from alice to registered mock w/ non-empty userData"
            );
            await superToken
                .connect(aliceSigner)
                .upgradeTo(mock.address, toWad(2), "0x4206");
        });

        it("#2.13 - upgradeTo should not revert for EOA if userData is passed to tokensReceived", async () => {
            console.log(
                "SuperToken.upgrade 2.0 tokens from alice to bob w/ non-empty userData"
            );
            await superToken
                .connect(aliceSigner)
                .upgradeTo(bobSigner.address, toWad(2), "0x4206");
        });

        it("#2.14 - upgradeTo should not revert for EOA if empty userData is passed to tokensReceived", async () => {
            console.log(
                "SuperToken.upgrade 2.0 tokens from alice to bob w/ empty userData"
            );
            await superToken
                .connect(aliceSigner)
                .upgradeTo(bobSigner.address, toWad(2), "0x");
        });

        it("#2.15 upgrade and self-upgradeTo should not trigger tokenReceived", async () => {
            const mockFactory = await ethers.getContractFactory(
                "ERC777SenderRecipientMock"
            );
            const mock = await mockFactory.deploy();

            console.log("send token from alice to mock");
            await testToken
                .connect(aliceSigner)
                .transfer(mock.address, toWad(2));

            console.log("mock.upgradeAll");
            await mock.upgradeAll(superToken.address);
            assert.equal(
                (await superToken.balanceOf(mock.address)).toString(),
                toWad(2).toString()
            );

            console.log("send token from alice to mock");
            await testToken
                .connect(aliceSigner)
                .transfer(mock.address, toWad(2));

            console.log("mock.upgradeAllToSelf");
            await mock.upgradeAllToSelf(superToken.address);
            assert.equal(
                (await superToken.balanceOf(mock.address)).toString(),
                toWad(4).toString()
            );
        });

        it("#2.16 upgrade and self-upgradeTo should not trigger tokenReceived if self is contract", async () => {
            console.log("send token from alice to wallet");
            await testToken
                .connect(aliceSigner)
                .transfer(mockWallet.address, toWad(2));

            console.log("mockWallet.approve - from Wallet to SuperToken");
            await mockWallet
                .connect(aliceSigner)
                .approveTest(
                    testToken.address,
                    superToken.address,
                    MAX_UINT256
                );

            console.log("mockWallet.upgradeToTest");
            await mockWallet
                .connect(aliceSigner)
                .upgradeToTest(
                    superToken.address,
                    mockWallet.address,
                    toWad(2),
                    "0x"
                );
            assert.equal(
                (await superToken.balanceOf(mockWallet.address)).toString(),
                toWad(2).toString(),
                "0x"
            );
        });

        it("#2.17 Revert upgrade and self-upgradeTo if trigger tokenReceived on unregistered wallet with userData", async () => {
            console.log("TestToken.approve - from alice to mockWallet");
            await expectCustomError(
                superToken
                    .connect(aliceSigner)
                    .upgradeTo(mockWallet.address, toWad(2), "0x4206"),
                superToken,
                "SUPER_TOKEN_NOT_ERC777_TOKENS_RECIPIENT"
            );
        });
    });

    describe("#3 SuperToken custom token support", () => {
        let customToken: CustomSuperTokenMock;

        beforeEach(async () => {
            const customSuperTokenProxyMockFactory =
                await ethers.getContractFactory("CustomSuperTokenProxyMock");
            const customSuperTokenProxyMock =
                await customSuperTokenProxyMockFactory.deploy();
            customToken = await ethers.getContractAt(
                "CustomSuperTokenMock",
                customSuperTokenProxyMock.address
            );
            const factory = await ethers.getContractAt(
                "ISuperTokenFactory",
                await superfluid.getSuperTokenFactory()
            );

            console.log("initializeCustomSuperToken");
            await factory.initializeCustomSuperToken(customToken.address);
        });

        it("#3.1 Custom token storage should not overlap with super token", async () => {
            const {poolAdminNFTProxy, poolMemberNFTProxy} =
                await t.deployNFTContracts();
            const superTokenLogic =
                await t.deployContract<SuperTokenStorageLayoutTester>(
                    "SuperTokenStorageLayoutTester",
                    superfluid.address,
                    t.constants.ZERO_ADDRESS,
                    t.constants.ZERO_ADDRESS,
                    poolAdminNFTProxy.address,
                    poolMemberNFTProxy.address
                );
            const a = await superTokenLogic.getLastSuperTokenStorageSlot();
            const b = await customToken.getFirstCustomTokenStorageSlot();
            console.log("lastSuperTokenStorageSlot", a.toString());
            console.log("firstCustomTokenStorageSlot", b.toString());
            assert.equal(Number(a.toString()) + 1, Number(b.toString()));
        });

        it("#3.2 Custom token functions can only be called by self", async () => {
            const reason = "SUPER_TOKEN_ONLY_SELF";
            await expectCustomError(
                superToken.selfMint(alice, 100, "0x"),
                superToken,
                reason
            );
            await expectCustomError(
                superToken.selfBurn(alice, 100, "0x"),
                superToken,
                reason
            );
        });

        it("#3.3 Custom token that mints/burn and disabling upgrade/downgrade", async () => {
            const reason = "SUPER_TOKEN_NO_UNDERLYING_TOKEN";
            await expectCustomError(
                customToken.upgrade(100),
                customToken,
                reason
            );
            await expectCustomError(
                customToken.downgrade(100),
                customToken,
                reason
            );
            await web3tx(customToken.initialize, "customToken.initialize")(
                ZERO_ADDRESS,
                0,
                "Custom SuperTestToken",
                "CSTT"
            );

            await web3tx(customToken.selfMint, "customToken.selfMint")(
                alice,
                100,
                "0x"
            );
            assert.equal(
                (await customToken.balanceOf(alice)).toString(),
                "100"
            );
            assert.equal((await customToken.totalSupply()).toString(), "100");

            await expectCustomError(
                customToken.callSelfBurn(alice, 101, "0x"),
                superTokenContract,
                "SF_TOKEN_BURN_INSUFFICIENT_BALANCE"
            );

            await web3tx(customToken.callSelfBurn, "customToken.callSelfBurn")(
                alice,
                100,
                "0x"
            );
            assert.equal((await customToken.balanceOf(alice)).toString(), "0");
            assert.equal((await customToken.totalSupply()).toString(), "0");
        });

        it("#3.4 Custom token can use selfTransferFrom", async () => {
            console.log("customToken.initialize");
            await customToken.initialize(
                ZERO_ADDRESS,
                0,
                "Custom SuperTestToken",
                "CSTT"
            );

            console.log("customToken.selfMint");
            await customToken.selfMint(alice, 100, "0x");
            assert.equal(
                (await customToken.balanceOf(alice)).toString(),
                "100"
            );

            // specified spender is different than holder without allowance reverts
            await expect(
                customToken.callSelfTransferFrom(alice, bob, bob, 100)
            ).to.be.revertedWith(
                "SuperToken: transfer amount exceeds allowance"
            );

            // holder must have enough balance
            await expectCustomError(
                customToken.callSelfTransferFrom(bob, alice, alice, 100),
                superTokenContract,
                "SF_TOKEN_MOVE_INSUFFICIENT_BALANCE"
            );

            // holder cannot be zero address
            await expectCustomError(
                customToken.callSelfTransferFrom(
                    ZERO_ADDRESS,
                    ZERO_ADDRESS,
                    bob,
                    100
                ),
                superTokenContract,
                "SUPER_TOKEN_TRANSFER_FROM_ZERO_ADDRESS"
            );

            // recipient cannot be zero address
            await expectCustomError(
                customToken.callSelfTransferFrom(alice, bob, ZERO_ADDRESS, 100),
                superTokenContract,
                "SUPER_TOKEN_TRANSFER_TO_ZERO_ADDRESS"
            );

            // alice approves bob to spend her tokens
            console.log(
                "customToken.approve Alice approves (100) -> customToken.address"
            );
            await customToken.connect(aliceSigner).approve(bob, 100);
            // selfTransferFrom is called from alice => bob, where bob is the spender
            // (spender and holder are different so approval is required)
            console.log("customToken.callSelfTransferFrom Alice -> Bob");
            await customToken
                .connect(bobSigner)
                .callSelfTransferFrom(alice, bob, bob, 100);
            assert.equal((await customToken.balanceOf(bob)).toString(), "100");
            assert.equal((await customToken.balanceOf(alice)).toString(), "0");

            // should be able to send tokens without approval
            // as long as spender and holder are the same
            console.log("customToken.callSelfTransferFrom Bob -> Alice");
            await customToken
                .connect(aliceSigner)
                .callSelfTransferFrom(bob, bob, alice, 100);
            assert.equal((await customToken.balanceOf(bob)).toString(), "0");
            assert.equal(
                (await customToken.balanceOf(alice)).toString(),
                "100"
            );

            // should be able to send tokens to yourself without approval
            console.log("customToken.callSelfTransferFrom Alice -> Alice");
            await customToken.callSelfTransferFrom(alice, alice, alice, 100);
        });

        it("#3.5 Custom token can use selfApproveFor", async () => {
            await web3tx(customToken.initialize, "customToken.initialize")(
                ZERO_ADDRESS,
                0,
                "Custom SuperTestToken",
                "CSTT"
            );

            await web3tx(customToken.selfMint, "customToken.selfMint")(
                alice,
                100,
                "0x"
            );
            assert.equal(
                (await customToken.balanceOf(alice)).toString(),
                "100"
            );

            // account cannot be zero address
            await expectCustomError(
                customToken.callSelfApproveFor(ZERO_ADDRESS, bob, 100),
                superTokenContract,
                "SUPER_TOKEN_APPROVE_FROM_ZERO_ADDRESS"
            );

            // spender cannot be zero address
            await expectCustomError(
                customToken.callSelfApproveFor(alice, ZERO_ADDRESS, 100),
                superTokenContract,
                "SUPER_TOKEN_APPROVE_TO_ZERO_ADDRESS"
            );

            // should be able to call selfApprove at will + make a selfTransferFrom
            console.log(
                "customToken.callSelfApproveFor Alice approves (100) -> Bob"
            );
            await customToken
                .connect(bobSigner)
                .callSelfApproveFor(alice, bob, 100);
            console.log(
                "customToken.callSelfTransferFrom Alice transfers (100) -> Bob"
            );
            await customToken.callSelfTransferFrom(alice, bob, bob, 100);

            // should be able to call selfApprove and make a regular transferFrom
            console.log(
                "customToken.callSelfApproveFor Bob approves (100) -> Alice"
            );
            await customToken
                .connect(aliceSigner)
                .callSelfApproveFor(bob, alice, 100);
            console.log(
                "customToken.transferFrom Bob transfers (100) -> Alice"
            );
            await customToken
                .connect(aliceSigner)
                .transferFrom(bob, alice, 100);
        });
    });

    describe("#10 misc", () => {
        it("#10.1 should return underlying token", async () => {
            assert.equal(
                await superToken.getUnderlyingToken(),
                testToken.address
            );
        });

        it("#10.2 transferAll", async () => {
            await t.upgradeBalance("alice", toWad(2));
            assert.equal(
                (await superToken.balanceOf(alice)).toString(),
                toWad(2).toString()
            );
            console.log("superToken.transferAll alice -> bob");
            await superToken.connect(aliceSigner).transferAll(bob);
            assert.equal((await superToken.balanceOf(alice)).toString(), "0");
            assert.equal(
                (await superToken.balanceOf(bob)).toString(),
                toWad(2).toString()
            );
        });

        it("#10.3 batchCall should only be called by host", async function () {
            await expectCustomError(
                superToken.operationApprove(alice, bob, "0"),
                superToken,
                "SF_TOKEN_ONLY_HOST"
            );
            await expectCustomError(
                superToken.operationTransferFrom(alice, bob, admin, "0"),
                superToken,
                "SF_TOKEN_ONLY_HOST"
            );
            await expectCustomError(
                superToken.operationSend(alice, bob, "0", "0x"),
                superToken,
                "SF_TOKEN_ONLY_HOST"
            );
            await expectCustomError(
                superToken.operationUpgrade(alice, "0"),
                superToken,
                "SF_TOKEN_ONLY_HOST"
            );
            await expectCustomError(
                superToken.operationDowngrade(alice, "0"),
                superToken,
                "SF_TOKEN_ONLY_HOST"
            );
        });
    });
});

const assertDowngradeToBalances = async ({
    superToken,
    testToken,
    sender,
    receiver,
    downgradeAmount,
}: {
    superToken: SuperToken;
    testToken: TestToken;
    sender: string;
    receiver: string;
    downgradeAmount: BigNumberish;
}) => {
    const senderSigner = await ethers.getSigner(sender);
    const receiverSigner = await ethers.getSigner(receiver);
    const senderSuperTokenBalanceBefore = await superToken
        .connect(senderSigner)
        .balanceOf(sender);
    const senderERC20BalanceBefore = await testToken
        .connect(senderSigner)
        .balanceOf(sender);
    const receiverSuperTokenBalanceBefore = await superToken
        .connect(receiverSigner)
        .balanceOf(receiver);
    const receiverERC20TokenBalanceBefore = await testToken
        .connect(receiverSigner)
        .balanceOf(receiver);

    await superToken
        .connect(senderSigner)
        .downgradeTo(receiver, downgradeAmount);

    const senderSuperTokenBalanceAfter = await superToken
        .connect(senderSigner)
        .balanceOf(sender);
    const senderERC20TokenBalanceAfter = await testToken
        .connect(senderSigner)
        .balanceOf(sender);
    const receiverSuperTokenBalanceAfter = await superToken
        .connect(receiverSigner)
        .balanceOf(receiver);
    const receiverERC20TokenBalanceAfter = await testToken
        .connect(receiverSigner)
        .balanceOf(receiver);

    // sender super token balance after downgrade = sender super token balance before - downgrade amount
    expect(senderSuperTokenBalanceBefore.sub(downgradeAmount)).to.equal(
        senderSuperTokenBalanceAfter
    );

    // receiver underlying token balance before downgrade = receiver underlying token balance before + downgrade amount
    expect(receiverERC20TokenBalanceBefore.add(downgradeAmount)).to.equal(
        receiverERC20TokenBalanceAfter
    );

    // unless they are downgrading to their self, then balances will change for both
    if (sender !== receiver) {
        // sender underlying token balance after downgrade = sender underlying token balance after downgrade
        expect(senderERC20BalanceBefore).to.equal(senderERC20TokenBalanceAfter);
        // receiver super token balance after downgrade = receiver super token balance after downgrade
        expect(receiverSuperTokenBalanceBefore).to.equal(
            receiverSuperTokenBalanceAfter
        );
    }
};
