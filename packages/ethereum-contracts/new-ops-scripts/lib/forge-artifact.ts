import fs from "fs";
import path from "path";

import type { Abi } from "viem";

import { getOpsPackageRoot } from "./ops-env";

export type ForgeArtifact = {
  abi: Abi;
  bytecode: { object: HexString };
};

type HexString = `0x${string}`;

export function getForgeArtifactPath(contractName: string): string {
  return path.join(
    getOpsPackageRoot(),
    "build/foundry/default",
    `${contractName}.sol`,
    `${contractName}.json`
  );
}

export function loadForgeArtifact(contractName: string): ForgeArtifact {
  const p = getForgeArtifactPath(contractName);
  if (!fs.existsSync(p)) {
    throw new Error(
      `Artifact not found: ${p}\nRun: cd packages/ethereum-contracts && forge build`
    );
  }
  const raw = JSON.parse(fs.readFileSync(p, "utf8")) as ForgeArtifact;
  if (!raw.bytecode?.object || raw.bytecode.object === "0x") {
    throw new Error(`Empty bytecode in ${p}; run forge build`);
  }
  return raw;
}
