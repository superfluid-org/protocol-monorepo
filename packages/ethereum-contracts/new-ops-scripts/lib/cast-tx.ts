/**
 * All cast invocations that use a Foundry keystore account live here.
 * Read-only cast calls (cast call, cast code, etc.) stay in the calling scripts — no keystore needed.
 */
import { spawnSync } from "child_process";

import type { Address, Hash, Hex } from "viem";

import { keystoreSpawnEnv } from "./ops-env";

export type CastPublishResult = {
  hash: Hash;
  contractAddress?: Address;
};

function parseTxHash(output: string): Hash {
  const jsonMatch = output.match(/"transactionHash"\s*:\s*"(0x[a-fA-F0-9]{64})"/i);
  if (jsonMatch) {
    return jsonMatch[1] as Hash;
  }

  const lineMatch = output.match(/transactionHash\s+(0x[a-fA-F0-9]{64})/i);
  if (lineMatch) {
    return lineMatch[1] as Hash;
  }

  throw new Error(`could not parse transactionHash from cast output: ${output.trim().slice(0, 200) || "(empty)"}`);
}

function parsePublishResult(output: string): CastPublishResult {
  const trimmed = output.trim();
  if (trimmed.startsWith("{")) {
    try {
      const json = JSON.parse(trimmed) as {
        transactionHash?: string;
        contractAddress?: string | null;
      };
      if (json.transactionHash) {
        return {
          hash: json.transactionHash as Hash,
          contractAddress:
            json.contractAddress && json.contractAddress !== "null"
              ? (json.contractAddress as Address)
              : undefined,
        };
      }
    } catch {
      // fall through to line parser
    }
  }
  return { hash: parseTxHash(output) };
}

function runCast(args: string[], useKeystore = false): string {
  const r = spawnSync("cast", args, { encoding: "utf-8", env: keystoreSpawnEnv(useKeystore) });
  const combined = `${r.stdout ?? ""}${r.stderr ?? ""}`.trim();
  if (r.status !== 0) {
    throw new Error(combined || `cast failed (exit ${r.status ?? 1})`);
  }
  if (combined) {
    console.log(combined);
  }
  return combined;
}

/** Fund an address from a Foundry keystore account. */
export function castFund(
  rpcUrl: string,
  walletName: string,
  to: Address,
  wei: bigint
): Hash {
  console.log(`cast send (fund) → ${to}, value ${wei}`);
  return parseTxHash(
    runCast([
      "send",
      to,
      "--value",
      wei.toString(),
      "--rpc-url",
      rpcUrl,
      "--account",
      walletName,
    ], true)
  );
}

/** Broadcast a signed EIP-1559 transaction (CREATE deploy). Waits for inclusion. */
export function castPublish(rpcUrl: string, signedTx: Hex): CastPublishResult {
  console.log("cast publish (deploy)");
  return parsePublishResult(
    runCast(["publish", signedTx, "--rpc-url", rpcUrl, "--json"])
  );
}
