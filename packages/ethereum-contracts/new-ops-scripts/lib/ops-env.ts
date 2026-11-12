import path from "path";

/** Environment is prepared once by the bash entry point. */

export function keystoreSpawnEnv(useKeystore: boolean): NodeJS.ProcessEnv {
  const env = { ...process.env };
  if (useKeystore && env.SF_KEYSTORE_PASSWORD_FILE) env.ETH_PASSWORD = env.SF_KEYSTORE_PASSWORD_FILE;
  else delete env.ETH_PASSWORD;
  return env;
}

export function getOpsPackageRoot(): string {
  return path.join(__dirname, "..", "..");
}
