/**
 * Shared bootstrap for new-ops-scripts: dotenv, metadata path, RPC resolution, networks.json.
 * Matches shell helpers in new-ops-scripts/lib/network-config.sh.
 */
import fs from "fs";
import os from "os";
import path from "path";

import { config as dotenvConfig } from "dotenv";

export type MetadataNetworkRow = {
  name: string;
  chainId?: number;
  isTestnet?: boolean;
  contractsV1?: { host?: string; resolver?: string };
  publicRPCs?: string[];
};

let envLoaded = false;
let keystorePasswordFile: string | undefined;

/** Password file path for Foundry signing; not exported as ETH_PASSWORD (breaks `cast call`). */
export function getKeystorePasswordFile(): string | undefined {
  return keystorePasswordFile;
}

/** Env for `spawnSync` when invoking signing commands (`cast send`, `cast wallet`, etc.). */
export function keystoreSpawnEnv(useKeystore: boolean): NodeJS.ProcessEnv {
  const env = { ...process.env };
  if (useKeystore) {
    const file = getKeystorePasswordFile();
    if (file) env.ETH_PASSWORD = file;
  }
  return env;
}

/**
 * Prepare a password file for Foundry `--account` unlock.
 * KEYSTORE_PASSWORD empty string is valid; unset means not configured.
 * Password is kept in keystorePasswordFile (not exported as ETH_PASSWORD — breaks cast call).
 */
export function applyKeystorePasswordEnv(): void {
  if (keystorePasswordFile) return;

  if (process.env.ETH_PASSWORD) {
    keystorePasswordFile = process.env.ETH_PASSWORD;
    delete process.env.ETH_PASSWORD;
    return;
  }

  const file = process.env.KEYSTORE_PASSWORD_FILE?.trim();
  if (file) {
    if (!fs.existsSync(file)) {
      throw new Error(`KEYSTORE_PASSWORD_FILE not found: ${file}`);
    }
    keystorePasswordFile = file;
    return;
  }

  if (!("KEYSTORE_PASSWORD" in process.env)) return;

  const pwd = process.env.KEYSTORE_PASSWORD ?? "";

  keystorePasswordFile = path.join(os.tmpdir(), `sf-ops-keystore-${process.pid}-${Date.now()}`);
  fs.writeFileSync(keystorePasswordFile, pwd, { mode: 0o600 });

  const cleanupPath = keystorePasswordFile;
  const cleanup = (): void => {
    try {
      fs.unlinkSync(cleanupPath);
    } catch {
      // ignore
    }
    if (keystorePasswordFile === cleanupPath) keystorePasswordFile = undefined;
  };
  process.once("exit", cleanup);
  process.once("SIGINT", () => {
    cleanup();
    process.exit(130);
  });
  process.once("SIGTERM", () => {
    cleanup();
    process.exit(143);
  });
}

/** `packages/ethereum-contracts` — parent of `new-ops-scripts/`. */
export function getOpsPackageRoot(): string {
  return path.join(__dirname, "..", "..");
}

/**
 * Load `.env` from ethereum-contracts then `packages/` (parent overrides package), once per process.
 * Shell-exported vars win over both dotenv files.
 */
export function loadOpsEnv(): void {
  if (envLoaded) return;
  const root = getOpsPackageRoot();
  const shellEnv = { ...process.env };
  dotenvConfig({ path: path.join(root, ".env") });
  dotenvConfig({ path: path.join(root, "..", ".env"), override: true });
  for (const [key, value] of Object.entries(shellEnv)) {
    if (value !== undefined) process.env[key] = value;
  }
  applyKeystorePasswordEnv();
  envLoaded = true;
}

export function getMetadataJsonPath(): string {
  return process.env.METADATA_JSON ?? path.join(getOpsPackageRoot(), "../metadata/networks.json");
}

/** RPC priority: RPC_URL | PROVIDER_URL_OVERRIDE | PROVIDER_URL_TEMPLATE | metadata publicRPCs[0] */
export function resolveMetadataRpcUrl(networkName: string, row: MetadataNetworkRow): string | null {
  if (process.env.RPC_URL) return process.env.RPC_URL;
  if (process.env.PROVIDER_URL_OVERRIDE) return process.env.PROVIDER_URL_OVERRIDE;
  const tpl = process.env.PROVIDER_URL_TEMPLATE;
  if (tpl?.includes("{{NETWORK}}")) return tpl.replace(/\{\{NETWORK\}\}/g, networkName);
  const u = row.publicRPCs?.[0];
  return u && u !== "null" ? u : null;
}

export function readMetadataNetworks(): MetadataNetworkRow[] {
  const p = getMetadataJsonPath();
  return JSON.parse(fs.readFileSync(p, "utf8")) as MetadataNetworkRow[];
}

export function findMetadataNetwork(
  networkName: string,
  rows: MetadataNetworkRow[] = readMetadataNetworks()
): MetadataNetworkRow | undefined {
  return rows.find((r) => r.name === networkName);
}
