// propose-safe-tx.ts
import Safe from "@safe-global/protocol-kit";
import SafeApiKit from "@safe-global/api-kit";
import type { MetaTransactionData } from "@safe-global/types-kit";
import { Wallet, providers } from "ethers";

type Log = Pick<Console, "info" | "warn" | "error">;

export async function proposeSafeTx({
  rpcUrl,
  chainId,            // bigint, e.g. 1n
  safeAddress,
  proposerPrivateKey, // "0x..." – used only to sign the proposal hash
  transactions,       // MetaTransactionData[] (single/batch)
  replaceLatest = false,
  explicitNonce,
  apiKey,             // for Safe-hosted service (preferred)
  txServiceUrl,       // OR custom Transaction Service URL
  origin,             // optional: label in service
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

  // 1) Protocol Kit (no adapters/libs needed)
  const protocolKit = await Safe.init({
    provider: rpcUrl,
    signer: proposerPrivateKey,
    safeAddress
  });
  log.info({ safeAddress }, "protocol: init"); // Safe.init docs. :contentReference[oaicite:0]{index=0}

  // 2) API Kit (chain-aware; default service uses apiKey, or pass txServiceUrl)
  // NOTE: When chainId is provided, the SDK knows the correct service URL automatically
  // Only use txServiceUrl for custom/self-hosted services
  const apiConfig: any = { chainId };
  if (apiKey) {
    apiConfig.apiKey = apiKey;
  }
  if (txServiceUrl) {
    apiConfig.txServiceUrl = txServiceUrl;
    log.warn(`Using CUSTOM txServiceUrl: ${txServiceUrl}`);
    log.warn('This may override the default service for this chain!');
  }
  
  const api = new SafeApiKit(apiConfig);
  log.info(
    { chainId: chainId.toString(), service: txServiceUrl ?? "auto-detected from chainId" },
    "api: init"
  );

  // 2.5) Check if Safe exists in the service
  const proposerAddress = new Wallet(proposerPrivateKey).address;
  try {
    log.info('=== DEBUG: Querying Safe from API ===');
    const safeInfo = await api.getSafeInfo(safeAddress);
    log.info('✓ Safe Info from API:', JSON.stringify(safeInfo, null, 2));
  } catch (e: any) {
    log.warn('✗ Failed to get Safe info from API');
    log.warn(`Error: ${e.message}`);
    log.warn('This Safe is NOT indexed by the Transaction Service');
    
  }

  // 3) Choose nonce
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
    nonce = typeof pendingNonce === 'string' ? parseInt(pendingNonce, 10) : pendingNonce;
  } else {
    const nextNonce = await api.getNextNonce(safeAddress);
    nonce = typeof nextNonce === 'string' ? parseInt(nextNonce, 10) : nextNonce;
  }
  log.info({ nonce }, "nonce: selected"); // getPendingTransactions/getNextNonce. :contentReference[oaicite:2]{index=2}

  // 4) Build Safe tx (array form is required) with chosen nonce
  const safeTx = await protocolKit.createTransaction({
    transactions,
    options: { nonce }
  });
  const safeTxData = safeTx.data; // Note: .data is a property, not a method
  log.info({ count: transactions.length }, "tx: created"); // createTransaction (array + options.nonce). :contentReference[oaicite:3]{index=3}

  // 5) Hash + single proposer signature (for the Service)
  const safeTxHash = await protocolKit.getTransactionHash(safeTx);
  const sig = await protocolKit.signHash(safeTxHash);
  
  // Use the proposer address we already derived earlier
  const senderAddress = proposerAddress;
  
  // Check if senderAddress is an owner of the Safe
  const owners = await protocolKit.getOwners();
  const isOwner = owners.includes(senderAddress);
  
  log.info({ safeTxHash, senderAddress, isOwner, owners }, "tx: hashed & signed");
  
  if (!isOwner) {
    log.warn('WARNING: Proposer is not an owner of this Safe!');
    log.warn(`Proposer: ${senderAddress}`);
    log.warn(`Safe owners: ${owners.join(', ')}`);
  }

  // 6) Propose (idempotent for same hash)
  const proposalData = {
    safeAddress,
    safeTxHash,
    safeTransactionData: safeTxData,
    senderAddress,
    senderSignature: sig.data,
    ...(origin ? { origin } : {})
  };
  
  log.info('=== DEBUG: Proposal Data ===');
  log.info({ safeAddress, safeTxHash, senderAddress, origin });
  log.info('safeTransactionData:', JSON.stringify(safeTxData, null, 2));
  log.info('senderSignature:', sig.data);
  log.info('===========================');
  
  await api.proposeTransaction(proposalData);
  log.info({ safeTxHash, nonce }, "tx: proposed");

  return { safeTxHash, nonce };
}

// CLI wrapper for testing
async function main() {
  // Required environment variables
  const safeAddress = process.env.SAFE_ADDRESS;
  const proposerPrivateKey = process.env.SAFE_PROPOSER_PK;
  const rpcUrl = process.env.RPC_URL;
  const safeTxPayload = process.env.SAFE_TX_PAYLOAD;
  
  // Validation
  if (!safeAddress) {
    console.error('Error: SAFE_ADDRESS environment variable is required');
    process.exit(1);
  }
  if (!proposerPrivateKey) {
    console.error('Error: SAFE_PROPOSER_PK environment variable is required');
    process.exit(1);
  }
  if (!rpcUrl) {
    console.error('Error: RPC_URL environment variable is required');
    process.exit(1);
  }
  if (!safeTxPayload) {
    console.error('Error: SAFE_TX_PAYLOAD environment variable is required');
    process.exit(1);
  }
  
  // Parse JSON payload
  let payload: any;
  try {
    payload = JSON.parse(safeTxPayload);
  } catch (error: any) {
    console.error('Error: Failed to parse SAFE_TX_PAYLOAD JSON');
    console.error(error.message);
    process.exit(1);
  }
  
  const txTo = payload.to;
  const txData = payload.data;
  
  if (!txTo) {
    console.error('Error: SAFE_TX_PAYLOAD.to is required');
    process.exit(1);
  }
  if (!txData) {
    console.error('Error: SAFE_TX_PAYLOAD.data is required');
    process.exit(1);
  }

  // Auto-detect chainId from RPC
  let chainId: bigint;
  try {
    const provider = new providers.JsonRpcProvider(rpcUrl);
    const network = await provider.getNetwork();
    chainId = BigInt(network.chainId);
    console.log(`Auto-detected Chain ID: ${chainId}`);
  } catch (error: any) {
    console.error('Error: Failed to detect chainId from RPC');
    console.error(error.message);
    process.exit(1);
  }

  // Build transaction
  const transactions: MetaTransactionData[] = [{
    to: txTo,
    value: "0",
    data: txData,
    operation: 0 // CALL
  }];

  console.log('======== Safe Transaction Proposal ========');
  console.log(`Safe Address: ${safeAddress}`);
  console.log(`Chain ID: ${chainId}`);
  console.log(`RPC URL: ${rpcUrl}`);
  console.log(`To: ${txTo}`);
  console.log(`Data: ${txData}`);
  console.log('');

  try {
    const result = await proposeSafeTx({
      rpcUrl,
      chainId,
      safeAddress,
      proposerPrivateKey,
      transactions,
      apiKey: process.env.SAFE_API_KEY, // Optional
      txServiceUrl: process.env.SAFE_TX_SERVICE_URL, // Optional
      origin: process.env.SAFE_ORIGIN, // Optional
      logger: console,
    });

    console.log('');
    console.log('✓ Success!');
    console.log(`Safe Tx Hash: ${result.safeTxHash}`);
    console.log(`Nonce: ${result.nonce}`);
    console.log('');
    console.log('The transaction has been proposed to the Safe Transaction Service.');
    console.log('Other Safe owners can now review and sign it.');
  } catch (error: any) {
    console.error('');
    console.error('✗ Failed to propose Safe transaction');
    console.error(`Error: ${error.message}`);
    if (error.stack) {
      console.error('');
      console.error('Stack trace:');
      console.error(error.stack);
    }
    process.exit(1);
  }
}

// Run if called directly
if (require.main === module) {
  main().catch((error) => {
    console.error('Unexpected error:', error);
    process.exit(1);
  });
}
