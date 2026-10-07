import {assert} from "chai";
import {ethers} from "hardhat";
import TestEnvironment from "../../TestEnvironment";
import {expectRevertedWith} from "../../utils/expectRevert";

const DEFAULT_ADMIN_ROLE =
    "0x0000000000000000000000000000000000000000000000000000000000000000";

describe("Resolver", function () {
    const t = TestEnvironment.getSingleton();

    let admin: string, alice: string;

    before(async () => {
        await t.beforeTestSuite({
            nAccounts: 5,
        });
        ({admin, alice} = t.aliases);
    });

    it("Resolver.set should only be called by admin", async () => {
        const adminSigner = await ethers.getSigner(admin);
        const aliceSigner = await ethers.getSigner(alice);
        const resolverFactory = await ethers.getContractFactory("Resolver");
        const resolver = await resolverFactory.connect(adminSigner).deploy();
        await expectRevertedWith(
            resolver.connect(aliceSigner).set("alice", alice),
            "Caller is not an admin"
        );
        await resolver.grantRole(DEFAULT_ADMIN_ROLE, alice);
        await resolver.connect(aliceSigner).set("alice", alice);
        assert.equal(await resolver.get("alice"), alice);
    });
});
