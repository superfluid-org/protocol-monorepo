const path = require("path");
const {Artifacts} = require("hardhat/internal/artifacts");

/** Read artifacts without loading the Hardhat config or its plugins. */
module.exports = function readHardhatAbis(contractNames) {
    const artifacts = new Artifacts(
        path.resolve(__dirname, "../build/hardhat")
    );
    // Hardhat rejects missing artifacts and ambiguous contract names.
    return Object.fromEntries(
        contractNames.map((name) => [
            name,
            artifacts.readArtifactSync(name).abi,
        ])
    );
};
