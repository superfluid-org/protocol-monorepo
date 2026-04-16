import fs from "fs";

import Safe from "@safe-global/protocol-kit";
import SafeApiKit from "@safe-global/api-kit";
import type { MetaTransactionData } from "@safe-global/types-kit";
import { Wallet, providers } from "ethers";

type Log = Pick<Console, "info" | "warn" | "error">;

type SafePayload = {
  safeAddress: string;
  to: string;
  data: string;
  value?: string | number;
  operation?: string | number;
  actionType?: string;
};

type CliOptions = {
  rpcUrl: string;
  payloadFile: string;
  mode: "single" | "batch";
  requireSingleSafe: boolean;
  origin?: string;
  dryRun: boolean;
};

export async function proposeSafeTx({
  rpcUrl,
  chainId,
  safeAddress,
  proposerPrivateKey,
  transactions,
  replaceLatest = false,
  explicitNonce,
  apiKey,
  txServiceUrl,
  origin,
  logger
}: {
  rpcUrl: string;
  chainId: bigint;
  safeAddress: string;
  proposerPrivateKey: string;
  transactions: MetaTransactionData[];
  replaceLatest?: boolean;
  explicitNonce?: number;
  apiKey?: string;
  txServiceUrl?: string;
  origin?: string;
  logger?: Log;
}) {
  const log = logger ?? console;

  const protocolKit = await Safe.init({
    provider: rpcUrl,
    signer: proposerPrivateKey,
    safeAddress
  });
  log.info({ safeAddress }, "protocol: init");

  const apiConfig: any = { chainId };
  if (apiKey) {
    apiConfig.apiKey = apiKey;
  }
  if (txServiceUrl) {
    apiConfig.txServiceUrl = txServiceUrl;
    log.warn(`Using CUSTOM txServiceUrl: ${txServiceUrl}`);
    log.warn("This may override the default service for this chain!");
  }

  const api = new SafeApiKit(apiConfig);
  log.info(
    { chainId: chainId.toString(), service: txServiceUrl ?? "auto-detected from chainId" },
    "api: init"
  );

  const proposerAddress = new Wallet(proposerPrivateKey).address;
  try {
    const safeInfo = await api.getSafeInfo(safeAddress);
    log.info("✓ Safe info:", JSON.stringify(safeInfo, null, 2));
  } catch (e: any) {
    log.warn("✗ Failed to get Safe info from API");
    log.warn(`Error: ${e.message}`);
  }

  let nonce: number;
  if (typeof explicitNonce === "number") {
    nonce = explicitNonce;
  } else if (replaceLatest) {
    const pending = await api.getPendingTransactions(safeAddress, {
      ordering: "created",
      limit: 1
    });
    const pendingNonce =
      pending.results.length > 0
        ? pending.results[0].nonce
        : await api.getNextNonce(safeAddress);
    nonce = typeof pendingNonce === "string" ? parseInt(pendingNonce, 10) : pendingNonce;
  } else {
    const nextNonce = await api.getNextNonce(safeAddress);
    nonce = typeof nextNonce === "string" ? parseInt(nextNonce, 10) : nextNonce;
  }
  log.info({ nonce }, "nonce: selected");

  const safeTx = await protocolKit.createTransaction({
    transactions,
    options: { nonce }
  });
  const safeTxData = safeTx.data;
  log.info({ count: transactions.length }, "tx: created");

  const safeTxHash = await protocolKit.getTransactionHash(safeTx);
  const sig = await protocolKit.signHash(safeTxHash);

  const owners = await protocolKit.getOwners();
  const isOwner = owners.includes(proposerAddress);
  log.info({ safeTxHash, senderAddress: proposerAddress, isOwner }, "tx: hashed & signed");

  if (!isOwner) {
    log.warn("WARNING: Proposer is not an owner of this Safe!");
    log.warn(`Proposer: ${proposerAddress}`);
    log.warn(`Safe owners: ${owners.join(", ")}`);
  }

  await api.proposeTransaction({
    safeAddress,
    safeTxHash,
    safeTransactionData: safeTxData,
    senderAddress: proposerAddress,
    senderSignature: sig.data,
    ...(origin ? { origin } : {})
  });
  log.info({ safeTxHash, nonce }, "tx: proposed");

  return { safeTxHash, nonce };
}

function usage(): string {
  return [
    "Usage:",
    "  npx ts-node safe-ops.ts propose-file --rpc-url <url> --payload-file <path> --mode <single|batch> [--require-single-safe] [--origin <label>] [--dry-run]",
    "",
    "Secrets are read from env:",
    "  SAFE_PROPOSER_PK, SAFE_API_KEY, SAFE_TX_SERVICE_URL"
  ].join("\n");
}

function parseCliArgs(argv: string[]): CliOptions {
  if (argv[2] !== "propose-file") {
    throw new Error(usage());
  }

  const options: Partial<CliOptions> = {
    requireSingleSafe: false,
    dryRun: false
  };

  for (let i = 3; i < argv.length; i++) {
    const arg = argv[i];
    switch (arg) {
      case "--rpc-url":
        options.rpcUrl = argv[++i];
        break;
      case "--payload-file":
        options.payloadFile = argv[++i];
        break;
      case "--mode": {
        const mode = argv[++i];
        if (mode !== "single" && mode !== "batch") {
          throw new Error(`Unsupported mode: ${mode}`);
        }
        options.mode = mode;
        break;
      }
      case "--require-single-safe":
        options.requireSingleSafe = true;
        break;
      case "--origin":
        options.origin = argv[++i];
        break;
      case "--dry-run":
        options.dryRun = true;
        break;
      default:
        throw new Error(`Unknown argument: ${arg}`);
    }
  }

  if (!options.rpcUrl || !options.payloadFile || !options.mode) {
    throw new Error(usage());
  }

  return options as CliOptions;
}

function normalizeTransaction(payload: SafePayload): MetaTransactionData {
  const operation =
    typeof payload.operation === "number"
      ? payload.operation
      : typeof payload.operation === "string"
        ? parseInt(payload.operation, 10)
        : 0;

  return {
    to: payload.to,
    data: payload.data,
    value: payload.value != null ? String(payload.value) : "0",
    operation: Number.isFinite(operation) ? operation : 0
  };
}

function readSafePayloads(payloadFile: string): SafePayload[] {
  const lines = fs
    .readFileSync(payloadFile, "utf8")
    .split(/\r?\n/)
    .map((line) => line.trim())
    .filter((line) => line.length > 0);

  return lines.map((line) => {
    const payload = JSON.parse(line) as SafePayload;
    if (!payload.safeAddress || !payload.to || !payload.data) {
      throw new Error(`Invalid Safe payload: ${line}`);
    }
    return payload;
  });
}

function groupPayloadsBySafe(payloads: SafePayload[]): Array<{
  safeAddress: string;
  payloads: SafePayload[];
}> {
  const groups = new Map<string, SafePayload[]>();

  for (const payload of payloads) {
    const group = groups.get(payload.safeAddress);
    if (group) {
      group.push(payload);
    } else {
      groups.set(payload.safeAddress, [payload]);
    }
  }

  return Array.from(groups.entries()).map(([safeAddress, groupPayloads]) => ({
    safeAddress,
    payloads: groupPayloads
  }));
}

async function detectChainId(rpcUrl: string): Promise<bigint> {
  const provider = new providers.JsonRpcProvider(rpcUrl);
  const network = await provider.getNetwork();
  return BigInt(network.chainId);
}

function printSinglePayloads(payloads: SafePayload[]): void {
  console.log("");
  console.log("Captured Safe transaction payloads:");
  for (const payload of payloads) {
    console.log(`  Action Type: ${payload.actionType ?? "unknown"}`);
    console.log(`    Safe: ${payload.safeAddress}`);
    console.log(`    To: ${payload.to}`);
    if (payload.value != null) {
      console.log(`    Value: ${payload.value}`);
    }
    console.log(`    Data: ${payload.data}`);
  }
}

function printBatch(group: { safeAddress: string; payloads: SafePayload[] }): void {
  console.log("");
  console.log("Captured Safe transaction payloads:");
  console.log(`  Safe: ${group.safeAddress}`);
  console.log(`  Batched calls: ${group.payloads.length}`);
  group.payloads.forEach((payload, index) => {
    const tx = normalizeTransaction(payload);
    console.log(`    [${index}] to=${tx.to} op=${tx.operation ?? 0}`);
    console.log(`         data=${tx.data}`);
  });
}

async function proposeSinglePayloads(payloads: SafePayload[], options: CliOptions): Promise<void> {
  printSinglePayloads(payloads);
  if (options.dryRun) {
    return;
  }

  const proposerPrivateKey = process.env.SAFE_PROPOSER_PK;
  if (!proposerPrivateKey) {
    throw new Error("SAFE_PROPOSER_PK environment variable is required");
  }

  const chainId = await detectChainId(options.rpcUrl);
  console.log(`Auto-detected Chain ID: ${chainId}`);

  for (const payload of payloads) {
    const transactions = [normalizeTransaction(payload)];
    const origin = options.origin ?? payload.actionType;

    console.log("");
    console.log("======== Safe Transaction Proposal ========");
    console.log(`Safe Address: ${payload.safeAddress}`);
    console.log(`Chain ID: ${chainId}`);
    console.log("Calls: 1");
    console.log(`  [0] to=${transactions[0].to} op=${transactions[0].operation ?? 0}`);
    console.log("");

    const result = await proposeSafeTx({
      rpcUrl: options.rpcUrl,
      chainId,
      safeAddress: payload.safeAddress,
      proposerPrivateKey,
      transactions,
      apiKey: process.env.SAFE_API_KEY,
      txServiceUrl: process.env.SAFE_TX_SERVICE_URL,
      origin,
      logger: console
    });

    console.log("");
    console.log("✓ Success!");
    console.log(`Safe Tx Hash: ${result.safeTxHash}`);
    console.log(`Nonce: ${result.nonce}`);
    console.log("");
    console.log("The transaction has been proposed to the Safe Transaction Service.");
    console.log("Other Safe owners can now review and sign it.");
  }
}

async function proposeBatches(payloads: SafePayload[], options: CliOptions): Promise<void> {
  const groups = groupPayloadsBySafe(payloads);
  if (options.requireSingleSafe && groups.length !== 1) {
    throw new Error(
      `Expected exactly 1 Safe in batch mode, found ${groups.length}: ${groups
        .map((group) => group.safeAddress)
        .join(", ")}`
    );
  }

  for (const group of groups) {
    printBatch(group);
  }
  if (options.dryRun) {
    return;
  }

  const proposerPrivateKey = process.env.SAFE_PROPOSER_PK;
  if (!proposerPrivateKey) {
    throw new Error("SAFE_PROPOSER_PK environment variable is required");
  }

  const chainId = await detectChainId(options.rpcUrl);
  console.log(`Auto-detected Chain ID: ${chainId}`);

  for (const group of groups) {
    const transactions = group.payloads.map(normalizeTransaction);

    console.log("");
    console.log("======== Safe Transaction Proposal ========");
    console.log(`Safe Address: ${group.safeAddress}`);
    console.log(`Chain ID: ${chainId}`);
    console.log(`Calls: ${transactions.length}`);
    transactions.forEach((tx, index) => {
      console.log(`  [${index}] to=${tx.to} op=${tx.operation ?? 0}`);
    });
    console.log("");

    const result = await proposeSafeTx({
      rpcUrl: options.rpcUrl,
      chainId,
      safeAddress: group.safeAddress,
      proposerPrivateKey,
      transactions,
      apiKey: process.env.SAFE_API_KEY,
      txServiceUrl: process.env.SAFE_TX_SERVICE_URL,
      origin: options.origin,
      logger: console
    });

    console.log("");
    console.log("✓ Success!");
    console.log(`Safe Tx Hash: ${result.safeTxHash}`);
    console.log(`Nonce: ${result.nonce}`);
    console.log("");
    console.log("The transaction has been proposed to the Safe Transaction Service.");
    console.log("Other Safe owners can now review and sign it.");
  }
}

async function main() {
  const options = parseCliArgs(process.argv);
  const payloads = readSafePayloads(options.payloadFile);

  if (payloads.length === 0) {
    console.log("No Safe transaction payloads found in payload file.");
    return;
  }

  if (options.mode === "single") {
    await proposeSinglePayloads(payloads, options);
  } else {
    await proposeBatches(payloads, options);
  }
}

if (require.main === module) {
  main().catch((error) => {
    console.error("");
    console.error("✗ Safe operation failed");
    console.error(`Error: ${error.message}`);
    if (error.stack) {
      console.error("");
      console.error(error.stack);
    }
    process.exit(1);
  });
}
