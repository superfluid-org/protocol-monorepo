/**
 * Ethers-backed `artifacts.require` with Truffle-shaped `.new()` / `.at()`.
 */
const {ethers} = require("hardhat");

const _linkedLibraries = new Map();
const _abiCache = new Map();

function normalizeEtherValue(value) {
    if (value === undefined || value === null) {
        return value;
    }
    if (typeof value === "string") {
        return ethers.BigNumber.from(value);
    }
    return ethers.utils.hexValue(value);
}

function normalizeTxResponse(result) {
    if (result && result.hash && !result.transactionHash) {
        result.transactionHash = result.hash;
    }
    return result;
}

function decodeReceiptLogs(receipt, contract) {
    if (!receipt?.logs || !contract?.interface) {
        return [];
    }
    return receipt.logs
        .map((log) => {
            try {
                const parsed = contract.interface.parseLog(log);
                const args = {};
                for (const input of parsed.eventFragment.inputs) {
                    if (input.name) {
                        args[input.name] = parsed.args[input.name];
                    }
                }
                return {event: parsed.name, args};
            } catch {
                return null;
            }
        })
        .filter(Boolean);
}

async function toTruffleTxResponse(result, contract) {
    normalizeTxResponse(result);
    if (result && typeof result.wait === "function") {
        const receipt = await result.wait();
        const tx = await ethers.provider.getTransaction(
            receipt.transactionHash
        );
        const txCost = receipt.gasUsed.mul(
            tx?.gasPrice || ethers.constants.Zero
        );
        return {
            ...result,
            receipt,
            logs: decodeReceiptLogs(receipt, contract),
            tx: receipt.transactionHash,
            txCost,
            gasPrice: tx?.gasPrice,
        };
    }
    return result;
}

function extractTxOptions(args) {
    if (
        args.length === 0 ||
        typeof args[args.length - 1] !== "object" ||
        args[args.length - 1] === null ||
        Array.isArray(args[args.length - 1])
    ) {
        return {args, opts: undefined};
    }
    const last = args[args.length - 1];
    if ("from" in last || "value" in last || "gas" in last) {
        return {args: args.slice(0, -1), opts: last};
    }
    return {args, opts: undefined};
}

function withFromSupport(contract) {
    const names = new Set(
        contract.interface.fragments
            .filter((f) => f.type === "function")
            .map((f) => f.name)
    );
    for (const name of names) {
        if (typeof contract[name] !== "function") {
            continue;
        }
        contract[name] = (...rawArgs) => {
            const {args, opts} = extractTxOptions(rawArgs);
            const run = async () => {
                const contractName = contract.contractName;
                if (!contractName) {
                    throw new Error(
                        `Missing contractName on ${contract.address} calling ${name}`
                    );
                }
                const base = await ethers.getContractAt(
                    contractName,
                    contract.address
                );
                let target = base;
                const txOverrides = {};
                if (opts?.from) {
                    const signer = await ethers.getSigner(opts.from);
                    target = base.connect(signer);
                }
                if (opts?.value !== undefined) {
                    txOverrides.value = normalizeEtherValue(opts.value);
                }
                if (opts?.gas !== undefined) {
                    txOverrides.gasLimit = opts.gas;
                }
                const result =
                    Object.keys(txOverrides).length > 0
                        ? await target[name](...args, txOverrides)
                        : await target[name](...args);
                return toTruffleTxResponse(result, base);
            };
            return run();
        };
    }
    const originalConnect = contract.connect.bind(contract);
    contract.connect = (signer) => {
        const connected = originalConnect(signer);
        connected.contractName = contract.contractName;
        return withFromSupport(connected);
    };
    return contract;
}

function wrapAt(contractName, address, {withFrom = false} = {}) {
    return ethers.getContractAt(contractName, address).then((contract) => {
        const wrapped = withFrom ? withFromSupport(contract) : contract;
        wrapped.contractName = contractName;
        return wrapped;
    });
}

async function loadArtifactAbi(contractName) {
    if (_abiCache.has(contractName)) {
        return _abiCache.get(contractName);
    }
    const factory = await ethers.getContractFactory(contractName);
    const abi = JSON.parse(
        factory.interface.format(ethers.utils.FormatTypes.json)
    );
    _abiCache.set(contractName, abi);
    return abi;
}

function makeArtifactWrapper(contractName) {
    const wrapped = {
        contractName,
        get abi() {
            return _abiCache.get(contractName);
        },
        at: (address) => wrapAt(contractName, address),
        link: (libOrName, address) => {
            const libs = _linkedLibraries.get(contractName) || {};
            if (typeof libOrName === "object" && libOrName.address) {
                const name = libOrName.contractName;
                if (!name) {
                    throw new Error(
                        `Cannot link library to ${contractName}: missing contractName on deployed library`
                    );
                }
                libs[name] = libOrName.address;
            } else {
                libs[libOrName] = address;
            }
            _linkedLibraries.set(contractName, libs);
        },
    };
    wrapped.new = async (...args) => {
        const lib = _linkedLibraries.get(contractName);
        const deployFactory = lib
            ? await ethers.getContractFactory(contractName, {
                  libraries: lib,
              })
            : await ethers.getContractFactory(contractName);
        wrapped.bytecode = deployFactory.bytecode;
        wrapped.binary = deployFactory.bytecode;
        _abiCache.set(
            contractName,
            JSON.parse(
                deployFactory.interface.format(ethers.utils.FormatTypes.json)
            )
        );
        const contract = await deployFactory.deploy(...args);
        await contract.deployed();
        contract.contractName = contractName;
        return contract;
    };
    return wrapped;
}

/** Truffle-shaped `artifacts.require(name)` for legacy tests. */
function artifactsRequire(contractName) {
    const wrapped = makeArtifactWrapper(contractName);
    void loadArtifactAbi(contractName);
    const originalNew = wrapped.new;
    wrapped.new = (...args) =>
        originalNew(...args).then((contract) => withFromSupport(contract));
    wrapped.at = (address) => wrapAt(contractName, address, {withFrom: true});
    return wrapped;
}

module.exports = {
    artifactsRequire,
    toTruffleTxResponse,
};
