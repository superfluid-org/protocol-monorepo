const assert = require("node:assert/strict");
const {spawnSync} = require("node:child_process");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const {test} = require("node:test");
const vm = require("node:vm");

const bundledNames = require("../bundled-abi-contracts-list.json");
const subgraphNames = [
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

function fixture(t) {
    const root = fs.mkdtempSync(path.join(os.tmpdir(), "abi-generation-"));
    t.after(() => fs.rmSync(root, {recursive: true, force: true}));
    const contracts = path.join(root, "packages/ethereum-contracts");
    const subgraph = path.join(root, "packages/subgraph");
    fs.mkdirSync(path.join(contracts, "tasks"), {recursive: true});
    fs.mkdirSync(path.join(subgraph, "scripts"), {recursive: true});
    for (const name of [
        "build-bundled-abi.sh",
        "build-bundled-abi.js",
        "read-hardhat-abis.js",
        "bundled-abi-contracts-list.json",
    ]) {
        fs.copyFileSync(
            path.resolve(__dirname, "..", name),
            path.join(contracts, "tasks", name)
        );
    }
    fs.copyFileSync(
        path.resolve(__dirname, "../../../subgraph/scripts/getAbi.js"),
        path.join(subgraph, "scripts/getAbi.js")
    );
    fs.mkdirSync(path.join(root, "node_modules"));
    fs.symlinkSync(
        path.dirname(require.resolve("hardhat/package.json")),
        path.join(root, "node_modules/hardhat"),
        "dir"
    );

    const abis = {};
    for (const name of new Set([...bundledNames, ...subgraphNames])) {
        abis[name] =
            name === "Ownable"
                ? []
                : [{type: "event", name, inputs: [], anonymous: false}];
        const dir = path.join(
            contracts,
            "build/hardhat/contracts",
            `${name}.sol`
        );
        fs.mkdirSync(dir, {recursive: true});
        fs.writeFileSync(
            path.join(dir, `${name}.json`),
            JSON.stringify({contractName: name, abi: abis[name]})
        );
    }
    // Unrelated compiler metadata must not be parsed as contract artifacts.
    const buildInfo = path.join(contracts, "build/hardhat/build-info");
    fs.mkdirSync(buildInfo);
    fs.writeFileSync(path.join(buildInfo, "ISuperToken.json"), "invalid JSON");
    return {root, contracts, subgraph, abis};
}

function run(f, generator) {
    const command = generator === "bundle" ? "bash" : process.execPath;
    const script =
        generator === "bundle"
            ? path.join(f.contracts, "tasks/build-bundled-abi.sh")
            : path.join(f.subgraph, "scripts/getAbi.js");
    // Neither generator should depend on the caller's working directory.
    return spawnSync(command, [script], {cwd: f.root, encoding: "utf8"});
}

test("generates compatible bundles and subgraph ABIs without Truffle artifacts", (t) => {
    const f = fixture(t);
    for (const generator of ["bundle", "subgraph"]) {
        const result = run(f, generator);
        assert.equal(result.status, 0, result.stderr);
    }
    const expected = Object.fromEntries(
        bundledNames.map((name) => [name, f.abis[name]])
    );
    const bundle = path.join(f.contracts, "build/bundled-abi.js");
    const javascript = fs.readFileSync(bundle, "utf8");
    assert.deepEqual(require(bundle), expected);
    assert.deepEqual(
        JSON.parse(
            fs.readFileSync(path.join(f.contracts, "build/bundled-abi.json"))
        ),
        expected
    );
    assert.deepEqual(
        JSON.parse(
            vm.runInNewContext(javascript + "\nJSON.stringify(Superfluid_ABI);")
        ),
        expected
    );
    assert.deepEqual(
        JSON.parse(
            fs.readFileSync(
                path.join(f.contracts, "build/bundled-abi-contracts-list.json")
            )
        ),
        bundledNames
    );
    for (const name of subgraphNames) {
        assert.deepEqual(
            JSON.parse(
                fs.readFileSync(path.join(f.subgraph, "abis", `${name}.json`))
            ),
            f.abis[name]
        );
    }
    assert.equal(
        fs.readdirSync(path.join(f.subgraph, "abis")).length,
        subgraphNames.length
    );
    assert.equal(run(f, "bundle").status, 0);
    assert.equal(fs.readFileSync(bundle, "utf8"), javascript);
});

for (const generator of ["bundle", "subgraph"]) {
    for (const failure of ["missing", "ambiguous"]) {
        test(`${generator} rejects ${failure} artifacts without overwriting outputs`, (t) => {
            const f = fixture(t);
            const artifactDir = path.join(
                f.contracts,
                "build/hardhat/contracts"
            );
            const artifact = path.join(
                artifactDir,
                "ISuperToken.sol/ISuperToken.json"
            );
            if (failure === "missing") {
                fs.unlinkSync(artifact);
            } else {
                const duplicate = path.join(artifactDir, "Duplicate.sol");
                fs.mkdirSync(duplicate);
                fs.copyFileSync(
                    artifact,
                    path.join(duplicate, "ISuperToken.json")
                );
            }
            const output =
                generator === "bundle"
                    ? path.join(f.contracts, "build/bundled-abi.js")
                    : path.join(f.subgraph, "abis/ISuperToken.json");
            fs.mkdirSync(path.dirname(output), {recursive: true});
            fs.writeFileSync(output, "previous output");
            const previousFiles = fs.readdirSync(path.dirname(output));
            const result = run(f, generator);
            assert.notEqual(result.status, 0);
            assert.match(
                result.stderr,
                failure === "missing" ? /HH700/ : /HH701/
            );
            assert.equal(fs.readFileSync(output, "utf8"), "previous output");
            assert.deepEqual(
                fs.readdirSync(path.dirname(output)),
                previousFiles
            );
        });
    }
}
