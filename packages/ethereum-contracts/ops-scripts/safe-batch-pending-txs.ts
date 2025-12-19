#!/usr/bin/env node

/*
This fetches pending transactions from a Safe and replaces them with a batch tx.

Example usage:
SAFE_ADDRESS=0x... PRIVATE_KEY=$SAFE_PROPOSER_PK RPC_URL=https://mainnet.base.org ts-node ops-scripts/safe-batch-pending-txs.ts

It does NOT reject the pending transactions the batch tx is replacing.
That's because the Safe SDK doesn't provide a method for that API endpoint.

The API endpoint for off-chain-rejecting (by the proposer) would be:
DELETE /tx-service/eth/api/v2/multisig-transactions/{safe_tx_hash}/
Invoking that directly (without SDK) may be tedious because it requires a signed message.

Thus the user currently needs to manually reject replaced pending transactions.
*/

import Safe from '@safe-global/protocol-kit';
import SafeApiKit from '@safe-global/api-kit';
import type { MetaTransactionData } from '@safe-global/types-kit';
import { Wallet, providers } from 'ethers';

async function batchAndClearQueue() {
    const { 
        SAFE_ADDRESS: safeAddress, 
        PRIVATE_KEY: privateKey, 
        RPC_URL: rpcUrl, 
        DRY_RUN: dryRun,
        SAFE_API_KEY: apiKey
    } = process.env;

    if (!safeAddress || !privateKey || !rpcUrl) {
        throw new Error('Missing SAFE_ADDRESS, PRIVATE_KEY, or RPC_URL');
    }

    const isDryRun = dryRun === 'true';
    
    // Get chainId from RPC
    const ethersProvider = new providers.JsonRpcProvider(rpcUrl);
    const network = await ethersProvider.getNetwork();
    const chainId = network.chainId;
    
    const safeSdk = await Safe.init({
        provider: rpcUrl,
        signer: privateKey,
        safeAddress
    });
    
    const apiConfig: any = { chainId: BigInt(chainId) };
    if (apiKey) {
        apiConfig.apiKey = apiKey;
    }
    const apiKit = new SafeApiKit(apiConfig);

    console.log(`Fetching pending transactions for ${safeAddress}...`);
    const pendingTxs = await apiKit.getPendingTransactions(safeAddress);
    
    if (pendingTxs.results.length < 1) {
        console.log('No pending transactions found.');
        return;
    }

    // Reverse chronological order for batch execution
    const transactions: MetaTransactionData[] = pendingTxs.results
        .reverse()
        .map(tx => ({
            to: tx.to,
            value: tx.value,
            data: tx.data || '0x',
            operation: 0
        }));

    console.log(`--- PLAN ---`);
    console.log(`Action: Batch ${transactions.length} transactions`);
    console.log(`Dry Run: ${isDryRun}`);
    console.log(`------------`);

    if (isDryRun) {
        console.log('DRY_RUN is enabled. No transactions were proposed or rejected.');
        return;
    }

    // Create the batch tx (nonce will be handled automatically by the SDK)
    const safeTransaction = await safeSdk.createTransaction({ 
        transactions
    });
    
    const safeTxHash = await safeSdk.getTransactionHash(safeTransaction);
    const signature = await safeSdk.signHash(safeTxHash);

    // Derive the sender address from the private key
    const wallet = new Wallet(privateKey);
    const senderAddress = wallet.address;

    await apiKit.proposeTransaction({
        safeAddress,
        safeTransactionData: safeTransaction.data,
        safeTxHash,
        senderAddress,
        senderSignature: signature.data,
        origin: 'retroactive-batcher-v2'
    });

    console.log(`✅ Success! Batch proposed with hash: ${safeTxHash}`);
    console.log('!!! Please manually reject the pending transactions that were replaced by this batch !!!');
}

batchAndClearQueue().catch(err => {
    console.error(`❌ ${err.message}`);
    process.exit(1);
});