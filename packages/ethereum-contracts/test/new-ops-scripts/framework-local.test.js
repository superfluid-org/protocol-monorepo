const {test} = require("node:test");
const assert = require("node:assert/strict");
const {spawn, spawnSync} = require("node:child_process");
const fs = require("node:fs");
const path = require("node:path");
const {ethers} = require("ethers");
const root = path.resolve(__dirname, "../..");
const port = process.env.FRAMEWORK_LOCAL_PORT || "19600";
const rpc = `http://127.0.0.1:${port}`;
const key =
    "0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80";
const owner = new ethers.Wallet(key).address;
const pause = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

test(
    "operator defaults, chain binding, recovery, discovery and real admin routes",
    {timeout: 300000},
    async () => {
        fs.mkdirSync(path.join(root, ".tmp"), {recursive: true});
        const artifacts = fs.mkdtempSync(
            path.join(root, ".tmp/framework-local-")
        );
        const metadata = path.join(artifacts, "networks.json");
        const row = {
            name: "local-anvil",
            chainId: 31337,
            isTestnet: true,
            publicRPCs: [rpc],
            contractsV1: {},
        };
        const saveMetadata = () =>
            fs.writeFileSync(metadata, JSON.stringify([row]));
        saveMetadata();
        const env = {
            ...process.env,
            RPC_URL: rpc,
            PRIVATE_KEY: key,
            METADATA_JSON: metadata,
            FOUNDRY_BROADCAST: artifacts,
            FOUNDRY_CACHE_PATH: path.join(artifacts, "cache"),
        };
        delete env.RESOLVER_ADDRESS;
        delete env.HOST_ADDRESS;
        delete env.DEPLOYER;
        const invoke = (script, args, extra = {}) =>
            spawnSync(script, args, {
                cwd: root,
                env: {...env, ...extra},
                encoding: "utf8",
                timeout: 240000,
                maxBuffer: 20000000,
            });
        const run = (script, args, extra) => {
            const result = invoke(script, args, extra);
            assert.equal(
                result.status,
                0,
                `${script} ${args.join(" ")}\n${result.stdout}\n${result.stderr}`
            );
            return result.stdout;
        };
        const framework = "new-ops-scripts/framework.sh";
        const anvil = spawn(
            "anvil",
            ["--port", port, "--gas-limit", "100000000", "--silent"],
            {stdio: "ignore"}
        );
        const provider = new ethers.providers.JsonRpcProvider(rpc);
        const signer = new ethers.Wallet(key, provider);
        const deploy = async (name) => {
            const artifact = require(
                path.join(
                    root,
                    "build/foundry/default",
                    `${name}.sol`,
                    `${name}.json`
                )
            );
            const contract = await new ethers.ContractFactory(
                artifact.abi,
                artifact.bytecode.object,
                signer
            ).deploy();
            return contract.deployed();
        };
        let deployment;
        try {
            for (let i = 0; ; ++i) {
                try {
                    await provider.getBlockNumber();
                    break;
                } catch {
                    assert.ok(i < 60, "anvil startup");
                    await pause(100);
                }
            }
            const unknown = invoke(framework, ["brand-new-chain", "fresh"]);
            assert.notEqual(unknown.status, 0);
            assert.match(
                unknown.stderr,
                /Unknown network.*add its name, chainId/
            );
            run("new-ops-scripts/deploy-erc1820.sh", [row.name, "--broadcast"]);
            const nonce = await provider.getTransactionCount(owner);
            const freshPlan = run(framework, [row.name, "fresh"]);
            assert.equal(
                await provider.getTransactionCount(owner),
                nonce,
                "default simulation sent transactions"
            );
            const host = freshPlan.match(/HOST_ADDRESS (0x[0-9a-fA-F]{40})/)[1];
            const resolver = freshPlan.match(
                /RESOLVER_ADDRESS (0x[0-9a-fA-F]{40})/
            )[1];
            assert.equal(await provider.getCode(host), "0x");

            // Mine exactly five transactions, then stop. No wall-clock race against a deployment.
            await provider.send("evm_setAutomine", [false]);
            deployment = spawn(framework, [row.name, "fresh", "--broadcast"], {
                cwd: root,
                env,
                detached: true,
                stdio: ["ignore", "pipe", "pipe"],
            });
            let output = "";
            deployment.stdout.on("data", (chunk) => {
                output += chunk;
            });
            deployment.stderr.on("data", (chunk) => {
                output += chunk;
            });
            // The wrapper can exit before Forge flushes its interrupted broadcast.
            // Inherited pipes close only after Forge has finished saving its artifacts.
            const stopped = new Promise((resolve) =>
                deployment.once("close", resolve)
            );
            for (let mined = 0; mined < 5; ++mined) {
                for (let i = 0; ; ++i) {
                    assert.equal(deployment.exitCode, null, output);
                    if (
                        (await provider.getTransactionCount(owner, "pending")) >
                        nonce + mined
                    )
                        break;
                    assert.ok(i < 1200, output);
                    await pause(50);
                }
                await provider.send("evm_mine", []);
            }
            process.kill(-deployment.pid, "SIGINT");
            await provider.send("evm_setAutomine", [true]);
            await provider.send("evm_mine", []);
            await stopped;
            const partialNonce = await provider.getTransactionCount(owner);
            assert.ok(
                partialNonce >= nonce + 5,
                "did not exercise an interrupted deployment"
            );
            run(framework, [row.name, "fresh", "--broadcast", "--resume"]);
            assert.notEqual(await provider.getCode(host), "0x");
            const finalNonce = await provider.getTransactionCount(owner);
            assert.ok(
                finalNonce > partialNonce,
                "no remaining transactions resumed"
            );
            run(framework, [row.name, "fresh", "--broadcast", "--resume"]);
            assert.equal(
                await provider.getTransactionCount(owner),
                finalNonce,
                "completed resume deployed duplicates"
            );
            const duplicate = invoke(framework, [
                row.name,
                "fresh",
                "--broadcast",
            ]);
            assert.notEqual(duplicate.status, 0);
            assert.match(
                duplicate.stderr,
                /Fresh broadcast artifacts already exist/
            );

            row.contractsV1 = {host, resolver};
            saveMetadata();
            for (const hostOverride of ["", ethers.constants.AddressZero]) {
                const occupied = invoke(framework, [row.name, "fresh"], {
                    HOST_ADDRESS: hostOverride,
                });
                assert.notEqual(occupied.status, 0);
                assert.match(
                    occupied.stderr,
                    /Metadata already contains a host/
                );
            }
            const validation = JSON.parse(
                run("new-ops-scripts/info-print-contract-addresses.sh", [
                    row.name,
                    "--validate",
                    "--skip-tokens",
                ])
            );
            assert.deepEqual(validation.errors, []);
            assert.equal(validation.addresses.SUPERFLUID_HOST_PROXY, host);
            // Verification targets must originate in real discovery, not a synthetic forwarding fixture.
            const plan = JSON.parse(
                run("new-ops-scripts/verify-framework.sh", [
                    row.name,
                    "--plan",
                    "--skip-tokens",
                ])
            );
            assert.deepEqual(plan.errors, []);
            const gda = new ethers.Contract(
                plan.addresses.GDA_LOGIC,
                [
                    "function SLOTS_BITMAP_LIBRARY_ADDRESS() view returns(address)",
                    "function SUPERFLUID_POOL_DEPLOYER_ADDRESS() view returns(address)",
                ],
                provider
            );
            const bitmap = await gda.SLOTS_BITMAP_LIBRARY_ADDRESS();
            const poolDeployer = await gda.SUPERFLUID_POOL_DEPLOYER_ADDRESS();
            assert.notEqual(
                bitmap,
                poolDeployer,
                "fixture needs independent library addresses"
            );
            const command = plan.commands.find(
                (entry) => entry.label === "GDA logic"
            );
            const libraries = command.args.flatMap((arg, index) =>
                arg === "--libraries" ? [command.args[index + 1]] : []
            );
            assert.deepEqual(
                libraries.sort(),
                [
                    `contracts/libs/SlotsBitmapLibrary.sol:SlotsBitmapLibrary:${bitmap}`,
                    "contracts/agreements/gdav1/SuperfluidPoolDeployerLibrary.sol:" +
                        `SuperfluidPoolDeployerLibrary:${poolDeployer}`,
                ].sort(),
                "discovery lost linked libraries"
            );
            const argsFor = (label) =>
                plan.contracts.find((entry) => entry.label === label)
                    .constructorArgs;
            assert.equal(
                argsFor("GDA logic"),
                ethers.utils.defaultAbiCoder.encode(
                    ["address", "address"],
                    [host, plan.addresses.SUPERFLUID_POOL_BEACON]
                )
            );
            assert.equal(
                argsFor("IDA logic"),
                ethers.utils.defaultAbiCoder.encode(
                    ["address", "bool", "uint32"],
                    [host, true, 256]
                )
            );
            assert.equal(
                argsFor("host logic"),
                ethers.utils.defaultAbiCoder.encode(
                    ["bool", "bool", "uint64", "address", "address", "address"],
                    [
                        false,
                        false,
                        12000000,
                        plan.addresses.SIMPLE_FORWARDER,
                        plan.addresses.ERC2771_FORWARDER,
                        plan.addresses.SIMPLE_ACL,
                    ]
                )
            );

            const forwarder = await new ethers.Contract(
                resolver,
                ["function get(string) view returns(address)"],
                provider
            ).get("CFAv1Forwarder");
            const overrideResolver = await deploy("Resolver");
            run(
                "new-ops-scripts/register-forwarder.sh",
                [row.name, "CFAv1Forwarder", forwarder, "--broadcast"],
                {RESOLVER_ADDRESS: overrideResolver.address}
            );
            assert.equal(
                await overrideResolver.get("CFAv1Forwarder"),
                forwarder,
                "resolver override was ignored"
            );
            const overrideProxy = await deploy("UUPSProxy");
            await (
                await overrideProxy.initializeProxy(
                    plan.addresses.SUPERFLUID_HOST_LOGIC
                )
            ).wait();
            const overrideHost = new ethers.Contract(
                overrideProxy.address,
                [
                    "function initialize(address)",
                    "function isTrustedForwarder(address) view returns(bool)",
                ],
                signer
            );
            await (
                await overrideHost.initialize(
                    plan.addresses.SUPERFLUID_GOVERNANCE
                )
            ).wait();
            assert.equal(
                await overrideHost.isTrustedForwarder(forwarder),
                false
            );
            const blocked = invoke(
                "new-ops-scripts/register-forwarder.sh",
                [row.name, "CFAv1Forwarder", forwarder, "--broadcast"],
                {
                    HOST_ADDRESS: overrideHost.address,
                    RESOLVER_ADDRESS: overrideResolver.address,
                }
            );
            assert.notEqual(
                blocked.status,
                0,
                "metadata host bypassed the untrusted explicit host"
            );
            assert.match(blocked.stderr, /not trusted/);

            const multiOutput = run(
                "new-ops-scripts/deploy-legacy-multisig.sh",
                [row.name, "1", owner, "--broadcast"]
            );
            const multisig = multiOutput.match(
                /MultiSigWallet: (0x[0-9a-fA-F]{40})/
            )[1];
            const multiResolver = await deploy("Resolver");
            await (
                await multiResolver.grantRole(
                    ethers.constants.HashZero,
                    multisig
                )
            ).wait();
            await (
                await multiResolver.revokeRole(ethers.constants.HashZero, owner)
            ).wait();
            const multiArgs = [row.name, "tokens.LEGACY", owner];
            run("new-ops-scripts/resolver-set-key.sh", multiArgs, {
                RESOLVER_ADDRESS: multiResolver.address,
            });
            assert.equal(
                await multiResolver.get("tokens.LEGACY"),
                ethers.constants.AddressZero,
                "multisig simulation changed state"
            );
            run(
                "new-ops-scripts/resolver-set-key.sh",
                [...multiArgs, "--broadcast"],
                {RESOLVER_ADDRESS: multiResolver.address}
            );
            assert.equal(
                await multiResolver.get("tokens.LEGACY"),
                owner,
                "real legacy multisig did not execute resolver update"
            );
            const registry = new ethers.Contract(
                resolver,
                ["function get(string) view returns(address)"],
                provider
            );
            const governance = new ethers.Contract(
                validation.addresses.SUPERFLUID_GOVERNANCE,
                [
                    "function getSuperTokenMinimumDeposit(address,address) view returns(uint256)",
                ],
                provider
            );
            const zero = ethers.constants.AddressZero;
            for (const [script, args] of [
                [
                    "new-ops-scripts/gov-action.sh",
                    [row.name, "setTokenMinimumDeposit", zero, "424242"],
                ],
                [
                    "new-ops-scripts/resolver-set-key.sh",
                    [row.name, "tokens.MIG", owner],
                ],
                [
                    "new-ops-scripts/deploy-custom-super-token.sh",
                    [row.name, "pure", "Migration", "MIG", "123"],
                ],
            ]) {
                const before = await provider.getTransactionCount(owner);
                run(script, args);
                assert.equal(
                    await provider.getTransactionCount(owner),
                    before,
                    `${script} simulated with side effects`
                );
                row.chainId = 1;
                saveMetadata();
                const mismatch = invoke(script, [...args, "--broadcast"]);
                assert.notEqual(mismatch.status, 0);
                assert.match(
                    mismatch.stderr,
                    /RPC chain 31337 differs from NETWORK/
                );
                assert.equal(
                    await provider.getTransactionCount(owner),
                    before,
                    "wrong-chain operation broadcast"
                );
                row.chainId = 31337;
                saveMetadata();
                const typo = invoke(script, [...args, "--brodcast"]);
                assert.notEqual(typo.status, 0);
                assert.match(typo.stderr, /Unknown option/);
                assert.equal(
                    await provider.getTransactionCount(owner),
                    before,
                    "unknown option broadcast"
                );
                run(script, [...args, "--broadcast"]);
                assert.ok(
                    (await provider.getTransactionCount(owner)) > before,
                    `${script} ignored --broadcast`
                );
            }
            assert.equal(
                (
                    await governance.getSuperTokenMinimumDeposit(host, zero)
                ).toString(),
                "424242"
            );
            run("new-ops-scripts/gov-action.sh", [
                row.name,
                "setTokenMinimumDeposit",
                owner,
                "7",
                "--broadcast",
            ]);
            assert.equal(
                (
                    await governance.getSuperTokenMinimumDeposit(host, owner)
                ).toString(),
                "7"
            );
            assert.equal(
                (
                    await governance.getSuperTokenMinimumDeposit(host, zero)
                ).toString(),
                "424242",
                "token scope overwrote default"
            );
            const strangerKey = ethers.utils.hexZeroPad("0x02", 32);
            const stranger = new ethers.Wallet(strangerKey).address;
            await provider.send("anvil_setBalance", [
                stranger,
                "0x3635c9adc5dea00000",
            ]);
            const unauthorized = invoke(
                "new-ops-scripts/gov-action.sh",
                [row.name, "setTokenMinimumDeposit", zero, "1", "--broadcast"],
                {PRIVATE_KEY: strangerKey}
            );
            assert.notEqual(unauthorized.status, 0);
            assert.equal(
                (
                    await governance.getSuperTokenMinimumDeposit(host, zero)
                ).toString(),
                "424242",
                "non-owner changed policy"
            );
            assert.equal(await registry.get("tokens.MIG"), owner);
            const denied = invoke("new-ops-scripts/resolver-set-key.sh", [
                row.name,
                "tokens.MIG",
                zero,
                "--broadcast",
            ]);
            assert.notEqual(denied.status, 0);
            assert.equal(
                await registry.get("tokens.MIG"),
                owner,
                "occupied resolver key overwritten"
            );
            run(
                "new-ops-scripts/resolver-set-key.sh",
                [row.name, "tokens.MIG", zero, "--broadcast"],
                {ALLOW_UPDATE: "1"}
            );
            assert.equal(await registry.get("tokens.MIG"), zero);
            // Exercise the wrapper's EOA upgrade route; the Solidity/fork tests cover policy preservation.
            const oldLogic = validation.addresses.SUPERFLUID_HOST_LOGIC;
            run(framework, [row.name, "upgrade", "--broadcast"]);
            const upgraded = JSON.parse(
                run("new-ops-scripts/info-print-contract-addresses.sh", [
                    row.name,
                    "--validate",
                    "--skip-tokens",
                ])
            );
            assert.deepEqual(upgraded.errors, []);
            assert.notEqual(upgraded.addresses.SUPERFLUID_HOST_LOGIC, oldLogic);
            const faucetArgs = [
                row.name,
                "provision-test-token",
                "Fake USDC",
                "fUSDC",
                "6",
                "1000000000000",
                "--broadcast",
            ];
            run(framework, faucetArgs);
            const faucetAddress = await registry.get("tokens.fUSDC");
            const faucet = new ethers.Contract(
                faucetAddress,
                ["function decimals() view returns(uint8)"],
                provider
            );
            assert.equal(await faucet.decimals(), 6);
            const wrapper = new ethers.Contract(
                await registry.get("supertokens.v1.fUSDCx"),
                [
                    "function getUnderlyingToken() view returns(address)",
                    "function getHost() view returns(address)",
                ],
                provider
            );
            assert.equal(await wrapper.getUnderlyingToken(), faucetAddress);
            assert.equal(await wrapper.getHost(), host);
            const faucetNonce = await provider.getTransactionCount(owner);
            assert.notEqual(
                invoke(framework, faucetArgs).status,
                0,
                "occupied faucet keys were overwritten"
            );
            assert.equal(
                await provider.getTransactionCount(owner),
                faucetNonce
            );

            const listingKey = "supertokens.reviewed.MIG_LIST";
            const listArgs = [row.name, "list", wrapper.address, "MIG_LIST"];
            run("new-ops-scripts/resolver-token.sh", listArgs, {
                RELEASE_VERSION: "reviewed",
            });
            assert.equal(
                await registry.get(listingKey),
                zero,
                "listing simulation changed resolver state"
            );
            run(
                "new-ops-scripts/resolver-token.sh",
                [...listArgs, "--broadcast"],
                {RELEASE_VERSION: "reviewed"}
            );
            assert.equal(await registry.get(listingKey), wrapper.address);
            assert.equal(
                await registry.get("supertokens.v1.MIG_LIST"),
                zero,
                "listing ignored the explicit release"
            );
            run(
                "new-ops-scripts/resolver-token.sh",
                [row.name, "unlist", "MIG_LIST", "--broadcast"],
                {RELEASE_VERSION: "reviewed"}
            );
            assert.equal(await registry.get(listingKey), zero);
            assert.equal(
                await registry.get("supertokens.v1.fUSDCx"),
                wrapper.address,
                "unlisting changed an unrelated key"
            );

            run("new-ops-scripts/acl-grant-role.sh", [
                row.name,
                "ACL_SUPERAPP_REGISTRATION_ROLE_ADMIN",
                owner,
                "--broadcast",
            ]);
            run("new-ops-scripts/transfer-simple-acl-admin.sh", [
                row.name,
                stranger,
                "--broadcast",
            ]);
            const acl = new ethers.Contract(
                upgraded.addresses.SIMPLE_ACL,
                ["function hasRole(bytes32,address) view returns(bool)"],
                provider
            );
            for (const role of [
                ethers.constants.HashZero,
                ethers.utils.id("ACL_SUPERAPP_REGISTRATION_ROLE_ADMIN"),
            ]) {
                assert.equal(
                    await acl.hasRole(role, owner),
                    false,
                    "deployer retained ACL authority"
                );
                assert.equal(
                    await acl.hasRole(role, stranger),
                    true,
                    "successor missing ACL authority"
                );
            }
            const retainedAuthority = invoke(
                "new-ops-scripts/acl-grant-role.sh",
                [row.name, "macros.superfluid.eth", owner, "--broadcast"]
            );
            assert.notEqual(
                retainedAuthority.status,
                0,
                "old deployer can still grant ACL roles"
            );
            console.log(
                JSON.stringify({host, resolver, partialNonce, finalNonce})
            );
        } finally {
            try {
                if (
                    deployment &&
                    deployment.exitCode === null &&
                    deployment.signalCode === null
                )
                    process.kill(-deployment.pid, "SIGTERM");
            } finally {
                provider.polling = false;
                anvil.kill();
                fs.rmSync(artifacts, {recursive: true, force: true});
            }
        }
    }
);
