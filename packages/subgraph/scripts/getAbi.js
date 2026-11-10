const fs = require("fs");
const path = require("path");

const readHardhatAbis = require("../../ethereum-contracts/tasks/read-hardhat-abis");

const contracts = [
    "ERC20",
    "IConstantFlowAgreementV1",
    "ISuperTokenFactory",
    "ISuperToken",
    "ISuperfluid",
    "Resolver",
    "IInstantDistributionAgreementV1",
    "IGeneralDistributionAgreementV1",
    "ISuperfluidPool",
    "SuperfluidGovernanceBase",
    "TestToken",
    "TOGA",
];

// Fail before writing if any required contract is missing or ambiguous.
const abis = readHardhatAbis(contracts);
const outputDir = path.resolve(__dirname, "../abis");
fs.mkdirSync(outputDir, { recursive: true });
console.log("Fetched ABIs for the following contracts:");
for (const [name, abi] of Object.entries(abis)) {
    fs.writeFileSync(path.join(outputDir, `${name}.json`), JSON.stringify(abi));
    console.log(`- ${name}`);
}
