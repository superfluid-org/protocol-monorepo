const {artifactsRequire} = require("./ethers-contract-loader");

/** Ethers replacement for hardhat-truffle5 `artifacts.require()`. */
module.exports = {require: artifactsRequire};
