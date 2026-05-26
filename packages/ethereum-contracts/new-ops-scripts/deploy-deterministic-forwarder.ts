/**
 * Step 1 — Deploy only: deterministic CREATE at vanity address (nonce 0 deployer).
 *
 * viem: reads + fee estimates. cast: fund (keystore) + publish (deployer PK).
 *
 * Usage (from packages/ethereum-contracts):
 *   npx ts-node new-ops-scripts/deploy-deterministic-forwarder.ts <network> <contractName>
 *     [--rpc-url <url>] [--host <address>] [--chain-id <id>]
 *
 * Prerequisite: forge build
 *
 * Env:
 *   DETERMINISTIC_DEPLOYER_PK — vanity deployer private key
 *   WALLET_NAME               — Foundry account that funds deployer (default: sf-ops)
 *   KEYSTORE_PASSWORD         — password in .env (→ SF_KEYSTORE_PASSWORD_FILE for signing)
 *   KEYSTORE_PASSWORD_FILE    — path to password file (alternative to KEYSTORE_PASSWORD)
 *   EXPECTED_ADDRESS, SKIP_ADDRESS_CHECK=1
 *   GAS_LIMIT, MAX_FEE_PER_GAS, MAX_PRIORITY_FEE_PER_GAS, EST_TX_COST
 *     (manual override if auto-estimate unsupported)
 *   SIMULATE=1                — checks only, no fund/deploy
 *
 * Follow-up: verify-forwarder.sh, register-forwarder.sh, activate-forwarder.sh
 *            (or deploy-clearmacro-forwarder.sh for the full rollout).
 */
import type { Address, Hex } from "viem";
import {
  createPublicClient,
  defineChain,
  encodeDeployData,
  getContractAddress,
  http,
  isAddress,
} from "viem";
import { privateKeyToAccount } from "viem/accounts";

import { castFund, castPublish } from "./lib/cast-tx";
import { estimateDeployFunding } from "./lib/estimate-deploy-funding";
import { loadForgeArtifact } from "./lib/forge-artifact";
import {
  CANONICAL_FORWARDER_ADDRESSES,
  FORWARDER_CONTRACTS,
} from "./lib/forwarder-contracts";
import {
  findMetadataNetwork,
  getMetadataJsonPath,
  loadOpsEnv,
  resolveMetadataRpcUrl,
} from "./lib/ops-env";

function usage(): never {
  console.error(
    "Usage: npx ts-node new-ops-scripts/deploy-deterministic-forwarder.ts <network> <contractName> " +
      "[--rpc-url <url>] [--host <address>] [--chain-id <id>]\n" +
      `Contracts: ${[...FORWARDER_CONTRACTS].join(", ")}`
  );
  process.exit(1);
}

type CliArgs = {
  networkName: string;
  contractName: string;
  rpcUrl?: string;
  host?: Address;
  chainId?: number;
};

function parseArgs(argv: string[]): CliArgs {
  const positionals: string[] = [];
  const args: Partial<CliArgs> = {};

  for (let i = 2; i < argv.length; i++) {
    const arg = argv[i];
    if (arg === "--rpc-url") {
      args.rpcUrl = argv[++i];
    } else if (arg === "--host") {
      args.host = argv[++i] as Address;
    } else if (arg === "--chain-id") {
      args.chainId = Number(argv[++i]);
    } else if (arg.startsWith("--")) {
      usage();
    } else {
      positionals.push(arg);
    }
  }

  const [networkName, contractName] = positionals;
  if (!networkName || !contractName || positionals.length !== 2) usage();
  return { networkName, contractName, ...args };
}

function parsePrivateKey(raw: string): Hex {
  const hex = (raw.trim().startsWith("0x") ? raw.trim() : `0x${raw.trim()}`) as Hex;
  if (hex.length !== 66) {
    throw new Error("DETERMINISTIC_DEPLOYER_PK must be 32 bytes");
  }
  return hex;
}

async function main(): Promise<void> {
  loadOpsEnv();

  const cli = parseArgs(process.argv);
  const { networkName, contractName } = cli;
  if (!FORWARDER_CONTRACTS.has(contractName)) {
    console.error(`Unknown contract: ${contractName}`);
    usage();
  }

  const deployerPk = process.env.DETERMINISTIC_DEPLOYER_PK?.trim();
  if (!deployerPk) {
    console.error("DETERMINISTIC_DEPLOYER_PK is required");
    process.exit(1);
  }

  const row = findMetadataNetwork(networkName);
  const rpc = cli.rpcUrl ?? (row ? resolveMetadataRpcUrl(networkName, row) : null);
  const host = cli.host ?? (row?.contractsV1?.host as Address | undefined);
  const chainId = cli.chainId ?? row?.chainId;

  if (!host || !isAddress(host) || typeof chainId !== "number" || !Number.isInteger(chainId)) {
    console.error(`network/host/chainId missing in metadata (${getMetadataJsonPath()})`);
    process.exit(1);
  }
  if (!rpc) {
    console.error("no RPC (RPC_URL, PROVIDER_URL_OVERRIDE, or metadata publicRPCs)");
    process.exit(1);
  }

  const nonce = process.env.NONCE ? parseInt(process.env.NONCE, 10) : 0;
  const simulate = process.env.SIMULATE === "1";
  const funder = process.env.WALLET_NAME ?? "sf-ops";
  const expected =
    (process.env.EXPECTED_ADDRESS?.trim() as Address | undefined) ??
    CANONICAL_FORWARDER_ADDRESSES[contractName];

  console.log("Network:", networkName);
  console.log("Contract:", contractName);
  console.log("Host:", host);

  const artifact = loadForgeArtifact(contractName);
  const deployData = encodeDeployData({
    abi: artifact.abi,
    bytecode: artifact.bytecode.object as Hex,
    args: [host],
  });

  const account = privateKeyToAccount(parsePrivateKey(deployerPk));
  const chain = defineChain({
    id: chainId,
    name: networkName,
    nativeCurrency: { name: "Ether", symbol: "ETH", decimals: 18 },
    rpcUrls: { default: { http: [rpc] } },
  });
  const client = createPublicClient({ chain, transport: http(rpc) });

  const onChainNonce = await client.getTransactionCount({ address: account.address });
  if (onChainNonce !== nonce) {
    throw new Error(`Deployer nonce is ${onChainNonce}, expected ${nonce}`);
  }

  const predicted = getContractAddress({
    from: account.address,
    nonce: BigInt(nonce),
    bytecode: deployData,
  });

  if (expected) {
    if (predicted.toLowerCase() !== expected.toLowerCase()) {
      const msg = `Predicted ${predicted} != expected ${expected}`;
      if (process.env.SKIP_ADDRESS_CHECK !== "1") throw new Error(msg);
      console.warn(`WARNING: ${msg}`);
    }
  }
  console.log("Predicted address:", predicted);

  const gasLimit = process.env.GAS_LIMIT?.trim()
    ? BigInt(process.env.GAS_LIMIT.trim())
    : await client.estimateGas({ account: account.address, data: deployData });
  console.log("gas limit:", gasLimit.toString());

  const fees = await client.estimateFeesPerGas();
  const maxFeePerGas = process.env.MAX_FEE_PER_GAS?.trim()
    ? BigInt(process.env.MAX_FEE_PER_GAS.trim())
    : (fees.maxFeePerGas ?? fees.gasPrice ?? (await client.getGasPrice()));
  const maxPriorityFeePerGas = process.env.MAX_PRIORITY_FEE_PER_GAS?.trim()
    ? BigInt(process.env.MAX_PRIORITY_FEE_PER_GAS.trim())
    : (fees.maxPriorityFeePerGas ?? maxFeePerGas);
  console.log("max fee per gas:", maxFeePerGas.toString());
  console.log("max priority fee per gas:", maxPriorityFeePerGas.toString());

  let fundingTarget: bigint;
  const estOverride = process.env.EST_TX_COST?.trim();
  if (estOverride) {
    fundingTarget = BigInt(estOverride);
    console.log("EST_TX_COST override:", fundingTarget.toString());
  } else {
    fundingTarget = await estimateDeployFunding({
      client,
      chainId,
      networkName,
      deployData,
      gasLimit,
      maxFeePerGas,
      nonce,
    });
  }

  if (simulate) {
    console.log("SIMULATE=1: done");
    console.log(predicted);
    return;
  }

  const balance = await client.getBalance({ address: account.address });
  if (balance < fundingTarget) {
    castFund(rpc, funder, account.address, fundingTarget - balance);
  }

  const signed = await account.signTransaction({
    chainId,
    data: deployData,
    gas: gasLimit,
    maxFeePerGas,
    maxPriorityFeePerGas,
    nonce,
    type: "eip1559",
  });

  const { hash, contractAddress: deployedFromCast } = castPublish(rpc, signed);
  console.log("deploy tx:", hash);

  const deployed =
    deployedFromCast ??
    (await client.waitForTransactionReceipt({ hash })).contractAddress;
  if (!deployed || deployed.toLowerCase() !== predicted.toLowerCase()) {
    throw new Error(`Deploy mismatch: got ${deployed}, expected ${predicted}`);
  }

  console.log("contract deployed at:");
  console.log(deployed);
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
