import {assert} from "chai";
import {ethers, web3} from "hardhat";
import {expectCustomError, expectRevertedWith} from "../../utils/expectRevert";
import TestEnvironment from "../../TestEnvironment";
import {toWad} from "./helpers";

const {web3tx} = require("@decentral.ee/web3-helpers");

import {
    SuperToken,
    SuperUpgrader__factory,
    TestToken,
} from "../../../typechain-types";

const DEFAULT_ADMIN_ROLE =
    "0x0000000000000000000000000000000000000000000000000000000000000000";
const BACKEND_ROLE = web3.utils.soliditySha3("BACKEND_ROLE")!;

describe("Superfluid Super Upgrader Contract", function () {
    this.timeout(300e3);
    const t = TestEnvironment.getSingleton();

    const {ZERO_ADDRESS} = t.constants;

    let SuperUpgraderFactory: SuperUpgrader__factory;

    let admin: string,
        alice: string,
        bob: string,
        carol: string,
        dan: string,
        eve: string;
    let backend: Array<string>;
    let superToken: SuperToken;
    let testToken: TestToken;

    before(async () => {
        await t.beforeTestSuite({
            isTruffle: true,
            nAccounts: 6,
        });
        SuperUpgraderFactory = await ethers.getContractFactory("SuperUpgrader");
        ({admin, alice, bob, carol, dan, eve} = t.aliases);
        backend = new Array(bob, carol, dan);
        testToken = t.tokens.TestToken;
        superToken = t.tokens.SuperToken;
    });

    beforeEach(async function () {
        await t.beforeEachTestCase();
        t.beforeEachTestCaseBenchmark(this);
    });

    afterEach(async () => {
        t.afterEachTestCaseBenchmark();
    });

    describe("#1 SuperUpgrader Deployment", async () => {
        it("#1.1 Should deploy adminRole address", async () => {
            const upgrader = await SuperUpgraderFactory.deploy(admin, backend);
            const isAdminRole = await upgrader.hasRole(
                DEFAULT_ADMIN_ROLE,
                admin
            );
            const isBackend = await upgrader.hasRole(BACKEND_ROLE, backend[0]);
            assert.isOk(
                isAdminRole,
                "SuperUpgrader contract should have address as admin"
            );
            assert.isOk(
                isBackend,
                "SuperUpgrader contract should have server as backend"
            );
        });

        it("#1.2 Should revert without owner address", async () => {
            const backendWithZero = [...backend];
            backendWithZero.push(ZERO_ADDRESS);
            const superUpgraderFactory = await ethers.getContractFactory(
                "SuperUpgrader"
            );
            await expectRevertedWith(
                superUpgraderFactory.deploy(ZERO_ADDRESS, new Array()),
                "adminRole is empty"
            );

            await expectRevertedWith(
                superUpgraderFactory.deploy(admin, backendWithZero),
                "backend can't be zero"
            );
        });

        it("#1.3 Should add new Backend addresses", async () => {
            const upgrader = await SuperUpgraderFactory.deploy(
                admin,
                new Array()
            );
            await upgrader.grantRole(BACKEND_ROLE, bob);
            const isBackend = await upgrader.hasRole(BACKEND_ROLE, bob);
            assert.isOk(
                isBackend,
                "SuperUpgrader contract should have server as backend"
            );
        });
    });

    describe("#2 Upgrades to SuperToken", async () => {
        it("#2.1 Should revert if not in role", async () => {
            const upgrader = await SuperUpgraderFactory.deploy(admin, backend);
            const aliceSigner = await ethers.getSigner(alice);
            console.log("testToken.approve - from alice to admin");
            await testToken
                .connect(aliceSigner)
                .approve(upgrader.address, toWad("3"));
            const eveSigner = await ethers.getSigner(eve);
            await expectRevertedWith(
                upgrader
                    .connect(eveSigner)
                    .upgrade(superToken.address, alice, toWad("3")),
                "operation not allowed"
            );
        });

        it("#2.2 Should upgrade amount and give it back to user", async () => {
            const upgrader = await SuperUpgraderFactory.deploy(admin, backend);
            const aliceSigner = await ethers.getSigner(alice);
            console.log("testToken.approve - from alice to admin");
            await testToken
                .connect(aliceSigner)
                .approve(upgrader.address, toWad("3"));
            const signer = await ethers.getSigner(backend[0]);
            await upgrader
                .connect(signer)
                .upgrade(superToken.address, alice, toWad("3"));
            const aliceSuperTokenBalance = await superToken.balanceOf(alice);
            assert.equal(
                aliceSuperTokenBalance.toString(),
                toWad("3").toString(),
                "Alice should receive the correct amount"
            );
        });

        it("#2.3 Should upgrade small amount", async () => {
            const upgrader = await SuperUpgraderFactory.deploy(admin, backend);
            const aliceSigner = await ethers.getSigner(alice);
            console.log("testToken.approve - from alice to backend");
            await testToken
                .connect(aliceSigner)
                .approve(upgrader.address, toWad("3"));

            const signer = await ethers.getSigner(backend[1]);
            await web3tx(upgrader.connect(signer).upgrade, "upgrader.upgrade")(
                superToken.address,
                alice,
                1
            );

            const aliceSuperTokenBalance = await superToken.balanceOf(alice);
            assert.equal(
                aliceSuperTokenBalance.toString(),
                "1",
                "Alice should receive the correct amount"
            );
        });

        it("#2.4 Should upgrade large amount", async () => {
            const upgrader = await SuperUpgraderFactory.deploy(admin, backend);
            const adminSigner = await ethers.getSigner(admin);
            const aliceSigner = await ethers.getSigner(alice);
            await testToken
                .connect(adminSigner)
                .mint(alice, toWad("100000000000"));

            console.log("testToken.approve - from alice to backend");
            await testToken
                .connect(aliceSigner)
                .approve(upgrader.address, toWad("100000000000"));
            const signer = await ethers.getSigner(backend[2]);
            await web3tx(upgrader.connect(signer).upgrade, "upgrader.upgrade")(
                superToken.address,
                alice,
                toWad("100000000000")
            );

            const aliceSuperTokenBalance = await superToken.balanceOf(alice);
            assert.equal(
                aliceSuperTokenBalance.toString(),
                toWad("100000000000").toString(),
                "Alice should receive the correct amount"
            );
        });

        it("#2.5 Should revert without approval", async () => {
            const upgrader = await SuperUpgraderFactory.deploy(admin, backend);
            const backendSigner = await ethers.getSigner(backend[0]);

            console.log("upgrader.upgrade");
            await expectCustomError(
                upgrader
                    .connect(backendSigner)
                    .upgrade(superToken.address, alice, 1),
                testToken,
                "ERC20InsufficientAllowance",
                [upgrader.address, 0, 1]
            );
        });

        it("#2.6 Should revert approval is less than need it", async () => {
            const upgrader = await SuperUpgraderFactory.deploy(admin, backend);
            const backendSigner = await ethers.getSigner(backend[0]);
            const aliceSigner = await ethers.getSigner(alice);
            console.log("testToken.approve - from alice to backend");
            await testToken
                .connect(aliceSigner)
                .approve(upgrader.address, toWad("1"));

            await expectCustomError(
                upgrader
                    .connect(backendSigner)
                    .upgrade(superToken.address, alice, "1000000000000000001"),
                testToken,
                "ERC20InsufficientAllowance",
                [upgrader.address, toWad("1"), "1000000000000000001"]
            );
        });

        it("#2.7 Owner of tokens can use SuperUpgrader directly", async () => {
            const upgrader = await SuperUpgraderFactory.deploy(admin, backend);
            const aliceSigner = await ethers.getSigner(alice);
            console.log("testToken.approve - from alice to admin");
            await testToken
                .connect(aliceSigner)
                .approve(upgrader.address, toWad("1000000"));
            console.log("upgrader.upgrade");
            await upgrader
                .connect(aliceSigner)
                .upgrade(superToken.address, alice, toWad("3"));
            const aliceSuperTokenBalance = await superToken.balanceOf(alice);
            assert.equal(
                aliceSuperTokenBalance.toString(),
                toWad("3").toString(),
                "Alice should receive the correct amount"
            );
        });

        it("#2.8 Owner should define optout/optin blocking backend upgrade", async () => {
            const upgrader = await SuperUpgraderFactory.deploy(admin, backend);
            const backendSigner = await ethers.getSigner(backend[0]);
            const aliceSigner = await ethers.getSigner(alice);
            console.log("testToken.approve - from alice to backend");
            await testToken
                .connect(aliceSigner)
                .approve(upgrader.address, toWad("1000000"));
            console.log("Alice opt-out");

            await upgrader.connect(aliceSigner).optoutAutoUpgrades();

            await expectRevertedWith(
                upgrader
                    .connect(backendSigner)
                    .upgrade(superToken.address, alice, toWad("3")),
                "operation not allowed"
            );

            console.log("Alice opt-in");
            await upgrader.connect(aliceSigner).optinAutoUpgrades();

            console.log("Backend upgrade alice tokens");
            await upgrader
                .connect(backendSigner)
                .upgrade(superToken.address, alice, toWad("100"));
            const aliceSuperTokenBalance = await superToken.balanceOf(alice);
            assert.equal(
                aliceSuperTokenBalance.toString(),
                toWad("100").toString(),
                "Alice should receive the correct amount"
            );
        });
    });

    describe("#3 Control list of roles", async () => {
        it("#3.1 Admin should add/remove backend accounts", async () => {
            const upgrader = await SuperUpgraderFactory.deploy(admin, backend);
            const adminSigner = await ethers.getSigner(admin);
            const eveSigner = await ethers.getSigner(eve);

            for (let i = 0; i < backend.length; i++) {
                assert.isOk(
                    await upgrader.isBackendAgent(backend[i]),
                    "address should be in backend role"
                );
            }

            console.log("admin revoke backend account");
            await upgrader.connect(adminSigner).revokeBackendAgent(backend[0]);

            assert.isOk(
                !(await upgrader.isBackendAgent(backend[0])),
                "address should not be in backend role"
            );

            console.log("admin grant backend account");
            await upgrader.connect(adminSigner).grantBackendAgent(backend[0]);

            assert.isOk(
                await upgrader.isBackendAgent(backend[0]),
                "address should be in backend role"
            );

            await expectRevertedWith(
                upgrader.connect(adminSigner).grantBackendAgent(ZERO_ADDRESS),
                "operation not allowed"
            );

            await expectCustomError(
                upgrader.connect(eveSigner).grantBackendAgent(eve),
                upgrader,
                "AccessControlUnauthorizedAccount",
                [eve, DEFAULT_ADMIN_ROLE]
            );

            await expectCustomError(
                upgrader.connect(eveSigner).revokeBackendAgent(backend[1]),
                upgrader,
                "AccessControlUnauthorizedAccount",
                [eve, DEFAULT_ADMIN_ROLE]
            );
        });

        it("#3.2 Admin should add/remove admin accounts", async () => {
            const upgrader = await SuperUpgraderFactory.deploy(admin, backend);
            const adminSigner = await ethers.getSigner(admin);
            await web3tx(
                upgrader.connect(adminSigner).grantRole,
                "admin add bob to admin"
            )(DEFAULT_ADMIN_ROLE, bob);
            assert.isOk(
                await upgrader.hasRole(DEFAULT_ADMIN_ROLE, bob),
                "bob should be in admin role"
            );
        });

        it("#3.3 List all Backend accounts", async () => {
            const upgrader = await SuperUpgraderFactory.deploy(admin, backend);
            const registerBackend = await upgrader.getBackendAgents();
            for (let i = 0; i < backend.length; i++) {
                assert.equal(
                    registerBackend[i],
                    backend[i],
                    "not register backend"
                );
            }
        });
    });
});
