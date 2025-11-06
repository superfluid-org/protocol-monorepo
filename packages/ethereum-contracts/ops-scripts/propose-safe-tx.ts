// propose-safe-tx.ts
import Safe from "@safe-global/protocol-kit";
import SafeApiKit from "@safe-global/api-kit";
import type { MetaTransactionData } from "@safe-global/types-kit";
import { Wallet } from "ethers";

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

  // 2.5) DEBUG: Check if Safe exists in the service
  const proposerAddress = new Wallet(proposerPrivateKey).address;
  
  try {
    log.info('=== DEBUG: Querying Safe from API ===');
    const safeInfo = await api.getSafeInfo(safeAddress);
    log.info('✓ Safe Info from API:', JSON.stringify(safeInfo, null, 2));
  } catch (e: any) {
    log.warn('✗ Failed to get Safe info from API');
    log.warn(`Error: ${e.message}`);
    log.warn('This Safe is NOT indexed by the Transaction Service');
    
    // Try to get all safes for this proposer address
    try {
      log.info(`\nTrying to get Safes owned by ${proposerAddress}...`);
      const ownedSafes = await api.getSafesByOwner(proposerAddress);
      log.info('Safes owned by proposer:', JSON.stringify(ownedSafes, null, 2));
      
      if (ownedSafes.safes && ownedSafes.safes.length > 0) {
        log.info(`\nFound ${ownedSafes.safes.length} indexed Safe(s)`);
        log.info('If you want to test with an indexed Safe, use one of these addresses');
      } else {
        log.warn('No Safes found for this owner in the Transaction Service');
      }
    } catch (e2: any) {
      log.warn(`Could not query owned safes: ${e2.message}`);
    }
    
    // Still continue with the transaction creation (we'll fail at proposal but that's ok for debugging)
    log.info('\nContinuing anyway to test transaction creation and signing...\n');
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
    log.warn('WARNING: Signer is not an owner of this Safe!');
    log.warn(`Signer: ${senderAddress}`);
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
  log.info({ safeTxHash, nonce }, "tx: proposed"); // proposeTransaction. :contentReference[oaicite:4]{index=4}

  return { safeTxHash, nonce };
}

// CLI wrapper for testing
async function main() {
  // Required environment variables
  const safeAddress = process.env.SAFE_ADDRESS;
  const proposerPrivateKey = process.env.SAFE_PROPOSER_PK;
  const rpcUrl = process.env.RPC_URL;
  const chainId = process.env.CHAIN_ID;
  
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
  if (!chainId) {
    console.error('Error: CHAIN_ID environment variable is required');
    process.exit(1);
  }

  console.log('======== Safe Transaction Proposal Test ========');
  console.log(`Safe Address: ${safeAddress}`);
  console.log(`Chain ID: ${chainId}`);
  console.log(`RPC URL: ${rpcUrl}`);
  console.log('');

  // Dummy transaction data (sending 0 ETH to the Safe itself - harmless)
  const dummyTransactions: MetaTransactionData[] = [
    {
      to: safeAddress,
      value: '0',
      data: '0x', // empty data
    }
  ];

  try {
    const result = await proposeSafeTx({
      rpcUrl,
      chainId: BigInt(chainId),
      safeAddress,
      proposerPrivateKey,
      transactions: dummyTransactions,
      explicitNonce: process.env.SAFE_NONCE ? parseInt(process.env.SAFE_NONCE) : undefined, // Optional: use explicit nonce
      apiKey: process.env.SAFE_API_KEY, // Optional
      txServiceUrl: process.env.SAFE_TX_SERVICE_URL, // Optional
      origin: 'propose-safe-tx-test',
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
