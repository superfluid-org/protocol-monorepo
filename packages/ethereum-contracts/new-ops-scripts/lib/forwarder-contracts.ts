import type { Address } from "viem";

export const FORWARDER_CONTRACTS = new Set([
  "ClearMacroForwarderV1",
  "ClearMacroForwarderV1WithPermit2",
  "BlindMacroForwarder",
  "CFAv1Forwarder",
  "GDAv1Forwarder",
]);

/** Vanity addresses at deployer nonce 0 (npx vanityeth -i … --contract). */
export const CANONICAL_FORWARDER_ADDRESSES: Record<string, Address> = {
  ClearMacroForwarderV1: "0x712Fc5863F53AFBa980207006cfd74F6c25fE055",
  ClearMacroForwarderV1WithPermit2: "0xC1EaB73855155D4e021f7EB4f866996Bac2fe25e",
  BlindMacroForwarder: "0xFD0268E33111565dE546af2675351A4b1587F89F",
  CFAv1Forwarder: "0xcfA132E353cB4E398080B9700609bb008eceB125",
  GDAv1Forwarder: "0x6DA13Bde224A05a288748d857b9e7DDEffd1dE08",
};
