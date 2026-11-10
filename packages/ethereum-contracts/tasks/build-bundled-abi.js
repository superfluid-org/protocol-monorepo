const fs = require("fs");
const path = require("path");

const contractNames = require("./bundled-abi-contracts-list.json");
const readHardhatAbis = require("./read-hardhat-abis");

// Resolve every artifact before replacing any generated files.
const abis = readHardhatAbis([...contractNames].sort());
const outputDir = path.resolve(__dirname, "../build");
const javascript = [
    "if (typeof module === 'undefined') module = {};",
    "// eslint-disable-next-line no-unused-vars",
    "let Superfluid_ABI;",
    `Superfluid_ABI = module.exports = ${JSON.stringify(abis, null, 4)};`,
    "",
].join("\n");

fs.mkdirSync(outputDir, {recursive: true});
fs.writeFileSync(path.join(outputDir, "bundled-abi.js"), javascript);
fs.writeFileSync(
    path.join(outputDir, "bundled-abi.json"),
    JSON.stringify(abis) + "\n"
);
fs.copyFileSync(
    path.join(__dirname, "bundled-abi-contracts-list.json"),
    path.join(outputDir, "bundled-abi-contracts-list.json")
);
