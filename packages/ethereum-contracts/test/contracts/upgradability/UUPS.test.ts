import {assert, expect} from "chai";
import {ethers} from "hardhat";

import {
    UUPSProxiableMock__factory,
    UUPSProxy__factory,
} from "../../../typechain-types";
import TestEnvironment from "../../TestEnvironment";
import {expectRevertedWith} from "../../utils/expectRevert";
import {sha3} from "../utils/helpers";

describe("Miscellaneous for test coverages", () => {
    const t = TestEnvironment.getSingleton();

    const {ZERO_ADDRESS} = t.constants;

    before(async () => {
        await t.beforeTestSuite({
            nAccounts: 5,
        });
    });

    beforeEach(async function () {
        t.beforeEachTestCaseBenchmark(this);
    });

    afterEach(() => {
        t.afterEachTestCaseBenchmark();
    });

    describe("UUPS", () => {
        let UUPSProxyFactory: UUPSProxy__factory;
        let UUPSProxiableMock: UUPSProxiableMock__factory;
        before(async () => {
            UUPSProxyFactory = await ethers.getContractFactory("UUPSProxy");
            UUPSProxiableMock =
                await ethers.getContractFactory("UUPSProxiableMock");
        });

        it("UUPSProxy", async () => {
            const proxy = await UUPSProxyFactory.deploy();
            const proxiable = await ethers.getContractAt(
                "UUPSProxiableMock",
                proxy.address
            );
            const uuid1 = sha3("UUPSProxiableMock1")!;
            const mock = await UUPSProxiableMock.deploy(uuid1, 1);
            await expectRevertedWith(
                proxy.initializeProxy(ZERO_ADDRESS),
                "UUPSProxy: zero address"
            );
            await proxy.initializeProxy(mock.address);
            await expectRevertedWith(
                proxy.initializeProxy(mock.address),
                "UUPSProxy: already initialized"
            );
            assert.equal(await proxiable.proxiableUUID(), uuid1);
        });

        it("UUPSProxiable", async () => {
            const proxy = await UUPSProxyFactory.deploy();
            const proxiable = await ethers.getContractAt(
                "UUPSProxiableMock",
                proxy.address
            );
            const uuid1 = sha3("UUPSProxiableMock1")!;
            const uuid2 = sha3("UUPSProxiableMock2")!;
            const UUPSProxiableMockFactory =
                await ethers.getContractFactory("UUPSProxiableMock");
            const mock1a = await UUPSProxiableMockFactory.deploy(uuid1, 1);
            const mock1b = await UUPSProxiableMockFactory.deploy(uuid1, 2);
            const mock2 = await UUPSProxiableMockFactory.deploy(uuid2, 1);

            assert.equal(await mock1a.getCodeAddress(), ZERO_ADDRESS);
            await expectRevertedWith(
                mock1a.updateCode(mock1a.address),
                "UUPSProxiable: not upgradable"
            );
            await proxiable.updateCode(mock1a.address);

            await proxy.initializeProxy(mock1a.address);
            assert.equal(await proxiable.proxiableUUID(), uuid1);
            expect(await proxiable.waterMark()).to.equal(1);

            await proxiable.updateCode(mock1b.address);
            assert.equal(await proxiable.proxiableUUID(), uuid1);
            expect(await proxiable.waterMark()).to.equal(2);

            await expectRevertedWith(
                proxiable.updateCode(mock2.address),
                "UUPSProxiable: not compatible logic"
            );

            await expectRevertedWith(
                proxiable.updateCode(proxiable.address),
                "UUPSProxiable: proxy loop"
            );
        });

        it("Can't initialize castrated UUPSProxiable", async () => {
            const uuid1 = sha3("UUPSProxiableMock1")!;
            const mock1 = await UUPSProxiableMock.deploy(uuid1, 1);

            const uuid2 = sha3("UUPSProxiableMock2")!;
            const mock2 = await UUPSProxiableMock.deploy(uuid2, 1);

            // can initialize if not castrated
            await mock1.initialize();

            // cannot initialize if castrated
            await mock2.castrate();
            await expectRevertedWith(
                mock2.initialize(),
                "Initializable: contract is already initialized"
            );
        });
    });
});
