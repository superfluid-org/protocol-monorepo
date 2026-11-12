import {ethers} from "hardhat";

const deployMFA = async () => {
    const provider = new ethers.providers.JsonRpcProvider(
        "http://127.0.0.1:8545/"
    );
    const signer = provider.getSigner(
        "0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266"
    );
    const MFAContractFactory = await ethers.getContractFactory(
        "MultiFlowTesterApp"
    );
    const mfa = await MFAContractFactory.connect(signer).deploy(
        "0x9bd03768a7DCc129555dE410FF8E85528A4F88b5",
        "0xa513E6E4b8f2a923D98304ec87F64353C4D5C853"
    );
    console.log("MFA deployed at:", mfa.address);
};

deployMFA()
    .then(() => {
        process.exit(0);
    })
    .catch((err) => {
        console.error(err);
        process.exit(1);
    });
