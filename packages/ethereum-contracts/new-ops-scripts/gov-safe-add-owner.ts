/**
 * proposes addOwnerWithThreshold on the governance Safe per chain.
 * Env matches the shell script (GOV_SAFE, NEW_SAFE_OWNER,
 * GOV_SAFE_OPS_NETWORKS, SIMULATE=1, METADATA_JSON, PROVIDER_URL_OVERRIDE / PROVIDER_URL_TEMPLATE,
 * SAFE_PROPOSER_PK, SAFE_API_KEY, SAFE_TX_SERVICE_URL, SAFE_ORIGIN).
 *
 * Loads `.env` from `packages/ethereum-contracts` then `packages/`.
 * Shell-exported vars still win (`dotenv` does not override existing `process.env`).
 *
 * Run from packages/ethereum-contracts: npx ts-node new-ops-scripts/gov-safe-add-owner.ts
 */
import { ethers } from "ethers";

import {
  loadOpsEnv,
  readMetadataNetworks,
  resolveMetadataRpcUrl,
  type MetadataNetworkRow
} from "./lib/ops-env";
import { proposeSafeTx } from "./safe-ops";

const HOST_ABI = ["function getGovernance() view returns (address)"];
const OWNABLE_ABI = ["function owner() view returns (address)"];
const SAFE_ABI = [
  "function VERSION() view returns (string)",
  "function isOwner(address) view returns (bool)",
  "function getThreshold() view returns (uint256)"
];
const safeIface = new ethers.utils.Interface([
  ...SAFE_ABI,
  "function addOwnerWithThreshold(address owner, uint256 _threshold)"
]);

const DEFAULT_GOV_SAFE = "0x06a858185b3b2abb246128bb9415d57e5c09aeb6";
const DEFAULT_NEW_OWNER = "0x4289a2b29be2555b0973422167321bF42CC39A3B";

function networkFilter(): Set<string> | null {
  const raw = process.env.GOV_SAFE_OPS_NETWORKS?.trim();
  if (!raw) return null;
  return new Set(raw.split(",").map((s) => s.replace(/\s+/g, "")).filter(Boolean));
}

async function processNetwork(
  row: MetadataNetworkRow,
  govSafe: string,
  newOwner: string,
  dryRun: boolean
): Promise<"proposed" | "skipped" | "error"> {
  const { name } = row;
  const hostAddr = row.contractsV1?.host;
  if (!hostAddr || !ethers.utils.isAddress(hostAddr)) {
    console.log(`[${name}] skip: invalid host in metadata`);
    return "skipped";
  }

  const rpc = resolveMetadataRpcUrl(name, row);
  if (!rpc) {
    console.log(`[${name}] skip: no RPC`);
    return "skipped";
  }

  const provider = new ethers.providers.JsonRpcProvider(rpc);
  const host = new ethers.Contract(hostAddr, HOST_ABI, provider);

  let govAddr: string;
  try {
    govAddr = await host.getGovernance();
  } catch {
    console.log(`[${name}] skip: getGovernance failed`);
    return "skipped";
  }

  let adminAddr: string;
  try {
    adminAddr = await new ethers.Contract(govAddr, OWNABLE_ABI, provider).owner();
  } catch {
    console.log(`[${name}] skip: governance owner() failed`);
    return "skipped";
  }

  if (adminAddr.toLowerCase() !== govSafe.toLowerCase()) {
    console.log(
      `[${name}] skip: governance admin ${adminAddr} is not GOV_SAFE (not Safe-owned by expected multisig)`
    );
    return "skipped";
  }

  const safeRO = new ethers.Contract(adminAddr, SAFE_ABI, provider);
  try {
    await safeRO.VERSION();
  } catch {
    console.log(`[${name}] skip: admin does not respond like a Safe (VERSION)`);
    return "skipped";
  }

  let already: boolean;
  try {
    already = await safeRO.isOwner(newOwner);
  } catch {
    console.error(`[${name}] error: isOwner check failed`);
    return "error";
  }
  if (already) {
    console.log(`[${name}] skip: ${newOwner} is already an owner`);
    return "skipped";
  }

  let threshold: ethers.BigNumber;
  try {
    threshold = await safeRO.getThreshold();
  } catch {
    console.error(`[${name}] error: getThreshold failed`);
    return "error";
  }

  const data = safeIface.encodeFunctionData("addOwnerWithThreshold", [newOwner, threshold]);

  console.log(`======== ${name} ========`);
  console.log(`  RPC: ${rpc}`);
  console.log(`  Governance: ${govAddr}`);
  console.log(`  Safe admin: ${adminAddr}`);
  console.log(`  Preserving threshold: ${threshold.toString()}`);
  console.log(`  addOwnerWithThreshold calldata: ${data}`);

  const transactions = [{ to: govSafe, data, value: "0", operation: 0 }];

  if (dryRun) {
    console.log("");
    console.log("Captured Safe transaction payloads:");
    console.log(`  Action Type: gov-safe-add-owner`);
    console.log(`    Safe: ${govSafe}`);
    console.log(`    To: ${govSafe}`);
    console.log(`    Data: ${data}`);
    console.log("");
    return "proposed";
  }

  const pk = process.env.SAFE_PROPOSER_PK;
  if (!pk) throw new Error("SAFE_PROPOSER_PK environment variable is required (unless SIMULATE=1)");

  const { chainId } = await provider.getNetwork();
  console.log("");
  console.log("======== Safe Transaction Proposal ========");
  console.log(`Safe Address: ${govSafe}`);
  console.log(`Chain ID: ${chainId}`);
  console.log("Calls: 1");
  console.log("");

  const result = await proposeSafeTx({
    rpcUrl: rpc,
    chainId: BigInt(chainId),
    safeAddress: govSafe,
    proposerPrivateKey: pk,
    transactions,
    apiKey: process.env.SAFE_API_KEY,
    txServiceUrl: process.env.SAFE_TX_SERVICE_URL,
    origin: process.env.SAFE_ORIGIN ?? "gov-safe-add-owner",
    logger: console
  });

  console.log("");
  if (result.skipped) {
    console.log("→ skip: identical Safe tx already pending");
    console.log(`  Safe Tx Hash: ${result.safeTxHash}`);
    console.log(`  Nonce: ${result.nonce}`);
  } else {
    console.log("✓ Success!");
    console.log(`Safe Tx Hash: ${result.safeTxHash}`);
    console.log(`Nonce: ${result.nonce}`);
    console.log("");
  }
  return result.skipped ? "skipped" : "proposed";
}

async function main(): Promise<void> {
  loadOpsEnv();

  const govSafe = ethers.utils.getAddress(process.env.GOV_SAFE ?? DEFAULT_GOV_SAFE);
  const newOwner = ethers.utils.getAddress(process.env.NEW_SAFE_OWNER ?? DEFAULT_NEW_OWNER);
  const filter = networkFilter();
  const dryRun = process.env.SIMULATE === "1";

  console.log(`Expected governance Safe: ${govSafe}`);
  console.log(`New owner to add:         ${newOwner}`);
  console.log(
    filter
      ? `Network filter (GOV_SAFE_OPS_NETWORKS): ${process.env.GOV_SAFE_OPS_NETWORKS}`
      : "Network filter: (none — all networks in metadata)"
  );
  console.log("");

  const rows = readMetadataNetworks();

  let proposed = 0;
  let skipped = 0;
  let errors = 0;

  for (const row of rows) {
    if (filter && !filter.has(row.name)) continue;
    try {
      const r = await processNetwork(row, govSafe, newOwner, dryRun);
      if (r === "proposed") proposed++;
      else if (r === "skipped") skipped++;
      else errors++;
    } catch (e: any) {
      console.error(`[${row.name}] error:`, e.message ?? e);
      errors++;
    }
    console.log("");
  }

  console.log(`Done. Proposed (or dry-run printed): ${proposed}, skipped: ${skipped}, errors: ${errors}`);
  if (errors > 0) process.exit(1);
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
