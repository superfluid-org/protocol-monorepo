/**
 * Deploy funding estimate:
 * - Scroll: L1GasPriceOracle at 0x5300…0002
 * - OP Stack: GasPriceOracle at 0x4200…000F (getL1Fee + L2 execution fee)
 * - Otherwise: gasLimit × maxFeePerGas (L1-style chains, e.g. BSC, Ethereum, Polygon)
 */
import type { Address, Hex, PublicClient } from "viem";
import { serializeTransaction } from "viem";

const FUNDING_BUFFER_BPS = 1000n;
const SCROLL_CHAIN_IDS = new Set([534351, 534352]); // scroll-sepolia, scroll-mainnet
/** OP Stack predeploy; viem uses this when chain.contracts.gasPriceOracle is unset. */
const OP_GAS_PRICE_ORACLE = "0x420000000000000000000000000000000000000F" as Address;
const SCROLL_L1_GAS_ORACLE = "0x5300000000000000000000000000000000000002" as Address;

const GAS_PRICE_ORACLE_PROBE_ABI = [
  {
    type: "function",
    name: "version",
    stateMutability: "view",
    inputs: [],
    outputs: [{ type: "string" }],
  },
] as const;

const L1_FEE_ORACLE_ABI = [
  {
    type: "function",
    name: "getL1Fee",
    stateMutability: "view",
    inputs: [{ name: "data", type: "bytes" }],
    outputs: [{ name: "", type: "uint256" }],
  },
] as const;

type DeployTxParams = {
  chainId: number;
  deployData: Hex;
  gasLimit: bigint;
  maxFeePerGas: bigint;
  nonce: number;
};

function withBuffer(amount: bigint): bigint {
  return (amount * (10000n + FUNDING_BUFFER_BPS)) / 10000n;
}

function executionFee(gasLimit: bigint, maxFeePerGas: bigint): bigint {
  return gasLimit * maxFeePerGas;
}

/** True when chain metadata includes viem's OP Stack gasPriceOracle contract. */
function chainDeclaresOpStack(chain: PublicClient["chain"]): boolean {
  const contracts = chain?.contracts as Record<string, { address?: Address }> | undefined;
  return Boolean(contracts?.gasPriceOracle?.address);
}

/** Probe the standard OP Stack GasPriceOracle predeploy (works when defineChain omits contracts). */
async function hasOpGasPriceOracle(client: PublicClient): Promise<boolean> {
  if (chainDeclaresOpStack(client.chain)) return true;
  try {
    await client.readContract({
      address: OP_GAS_PRICE_ORACLE,
      abi: GAS_PRICE_ORACLE_PROBE_ABI,
      functionName: "version",
    });
    return true;
  } catch {
    return false;
  }
}

async function l1DataFee(
  client: PublicClient,
  oracle: Address,
  params: DeployTxParams
): Promise<bigint> {
  const serialized = serializeTransaction({
    chainId: params.chainId,
    data: params.deployData,
    gas: params.gasLimit,
    maxFeePerGas: params.maxFeePerGas,
    maxPriorityFeePerGas: params.maxFeePerGas,
    nonce: params.nonce,
    type: "eip1559",
  });

  return client.readContract({
    address: oracle,
    abi: L1_FEE_ORACLE_ABI,
    functionName: "getL1Fee",
    args: [serialized],
  });
}

async function l1PlusL2Funding(
  client: PublicClient,
  oracle: Address,
  label: string,
  networkName: string,
  chainId: number,
  txParams: DeployTxParams
): Promise<bigint> {
  const l2Fee = executionFee(txParams.gasLimit, txParams.maxFeePerGas);
  let l1Fee: bigint;
  try {
    l1Fee = await l1DataFee(client, oracle, txParams);
    console.log(`${label} L1 data fee:`, l1Fee.toString());
  } catch (e) {
    const detail = e instanceof Error ? e.message : String(e);
    throw new Error(
      `Cannot estimate ${label} L1 data fee on ${networkName} (chain ${chainId}). Set EST_TX_COST. ${detail}`
    );
  }
  const total = l1Fee + l2Fee;
  console.log(`${label} L2 fee:`, l2Fee.toString(), "→ funding (+10%):", withBuffer(total).toString());
  return withBuffer(total);
}

/** Total wei to fund deployer (+10% buffer). Throws if estimation fails (set EST_TX_COST). */
export async function estimateDeployFunding(params: {
  client: PublicClient;
  chainId: number;
  networkName: string;
  deployData: Hex;
  gasLimit: bigint;
  maxFeePerGas: bigint;
  nonce: number;
}): Promise<bigint> {
  const { client, chainId, networkName, deployData, gasLimit, maxFeePerGas, nonce } = params;
  const txParams: DeployTxParams = { chainId, deployData, gasLimit, maxFeePerGas, nonce };

  if (SCROLL_CHAIN_IDS.has(chainId)) {
    return l1PlusL2Funding(client, SCROLL_L1_GAS_ORACLE, "scroll", networkName, chainId, txParams);
  }

  if (await hasOpGasPriceOracle(client)) {
    return l1PlusL2Funding(client, OP_GAS_PRICE_ORACLE, "OP Stack", networkName, chainId, txParams);
  }

  const total = executionFee(gasLimit, maxFeePerGas);
  console.log(
    "execution fee (gas × maxFeePerGas):",
    total.toString(),
    "→ funding (+10%):",
    withBuffer(total).toString()
  );
  return withBuffer(total);
}
