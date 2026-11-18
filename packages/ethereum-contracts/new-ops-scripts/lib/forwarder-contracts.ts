import type { Address } from "viem";
import forwarders from "./forwarders.json";

export const FORWARDER_CONTRACTS: Record<string, { address: string; deployerEnv: string; provider: boolean }> = forwarders;
export const CANONICAL_FORWARDER_ADDRESSES: Record<string, Address> = Object.fromEntries(
  Object.entries(forwarders).map(([name, config]) => [name, config.address as Address])
);
