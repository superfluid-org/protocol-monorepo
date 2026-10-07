/** CommonJS ethers helpers replacing legacy web3-shim for deploy scripts. */
const {ethers} = require("hardhat");

const sha3 = (input) => ethers.utils.id(input);

const soliditySha3 = (...args) => {
    if (args.length === 1 && typeof args[0] === "string") {
        return ethers.utils.id(args[0]);
    }
    const types = args.filter((_, i) => i % 2 === 0);
    const values = args.filter((_, i) => i % 2 === 1);
    return ethers.utils.solidityKeccak256(types, values);
};

const encodeAbiParameter = (type, value) =>
    ethers.utils.defaultAbiCoder.encode([type], [value]);

const encodeAbiParameters = (types, values) =>
    ethers.utils.defaultAbiCoder.encode(types, values);

module.exports = {
    sha3,
    soliditySha3,
    encodeAbiParameter,
    encodeAbiParameters,
    getBalance: (address) => ethers.provider.getBalance(address),
    getCode: (address) => ethers.provider.getCode(address),
    getAccounts: async () =>
        (await ethers.getSigners()).map((signer) => signer.address),
    getChainId: async () => (await ethers.provider.getNetwork()).chainId,
    getNetworkId: async () => (await ethers.provider.getNetwork()).chainId,
    getNetworkType: async () => "private",
};
