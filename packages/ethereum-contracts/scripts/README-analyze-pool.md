# Pool Flow Rate Calculation Analysis Script

This script queries a GDA pool contract and replicates the exact calculation logic used in the contracts to identify precision loss issues.

## Usage

### Standalone Script (Recommended - No Hardhat Required)

**Using Node.js (JavaScript):**
```bash
cd packages/ethereum-contracts
RPC_URL=https://polygon-rpc.com POOL_ADDRESS=0xc406eb08a815bb8543f1ade3f865398bcdab4b09 node scripts/analyze-pool-calculation-standalone.js
```

**Using TypeScript:**
```bash
cd packages/ethereum-contracts
RPC_URL=https://polygon-rpc.com POOL_ADDRESS=0xc406eb08a815bb8543f1ade3f865398bcdab4b09 npx ts-node scripts/analyze-pool-calculation-standalone.ts
```

### With Hardhat (Alternative)

```bash
cd packages/ethereum-contracts
POOL_ADDRESS=0xc406eb08a815bb8543f1ade3f865398bcdab4b09 npx hardhat run scripts/analyze-pool-calculation.ts --network <network>
```

### Example RPC URLs

- Ethereum Mainnet: `https://eth.llamarpc.com` or `https://rpc.ankr.com/eth`
- Polygon Mainnet: `https://polygon-rpc.com` or `https://rpc.ankr.com/polygon`
- Arbitrum One: `https://arb1.arbitrum.io/rpc` or `https://rpc.ankr.com/arbitrum`
- Optimism Mainnet: `https://mainnet.optimism.io` or `https://rpc.ankr.com/optimism`
- Gnosis Chain: `https://rpc.gnosischain.com`

**Note:** You can use any public RPC endpoint or your own node. For production, consider using a reliable RPC provider like Infura, Alchemy, or QuickNode.

## What the Script Does

1. **Queries Pool Contract Values**:
   - `poolOperatorGetIndex()` - Gets the internal pool index data including `wrappedFlowRate`
   - `getTotalUnits()` - Total units in the pool
   - `getTotalConnectedUnits()` - Connected units
   - `getTotalFlowRate()` - Total flow rate
   - `getTotalConnectedFlowRate()` - Flow rate to connected members
   - `getTotalDisconnectedFlowRate()` - Flow rate to disconnected members

2. **Replicates Contract Calculations**:
   - Calculates `_getTotalFlowRate()`: `wrappedFlowRate * totalUnits`
   - Calculates effective flow rate: `perUnitFlowRate * totalUnits`
   - Calculates adjustment flow rate: `totalFlowRate - effectiveFlowRate`

3. **Analyzes Precision Loss**:
   - Compares expected vs actual per-unit flow rate
   - Identifies integer division remainder
   - Shows how precision loss affects distribution

4. **Provides Summary**:
   - Shows percentage of flow going to adjustment
   - Warns if all flow goes to adjustment (critical issue)

## Output Example

```
================================================================================
GDA Pool Flow Rate Calculation Analysis
================================================================================
Pool Address: 0xc406eb08a815bb8543f1ade3f865398bcdab4b09

1. Querying Pool Contract Values...
--------------------------------------------------------------------------------
Pool Index Data (from poolOperatorGetIndex):
  totalUnits: 254889074354287
  wrappedSettledAt: 12345678
  wrappedFlowRate (int96): 864
  wrappedSettledValue (int256): ...

2. Replicating Contract Calculations...
--------------------------------------------------------------------------------
Calculation: _getTotalFlowRate()
  wrappedFlowRate: 864
  totalUnits: 254889074354287
  wrappedFlowRate * totalUnits (before int96 cast): 220223560241103168
  After int96 cast: 220223560241103168
  Contract's getTotalFlowRate(): 220277889022382414
  Match: ✓

3. Precision Loss Analysis...
--------------------------------------------------------------------------------
Expected vs Actual Per-Unit Flow Rate:
  Expected (totalFlowRate / totalUnits): 864
  Remainder from division: 54328781279246
  Actual (wrappedFlowRate): 864
  Difference: 0

4. Integer Division Analysis...
--------------------------------------------------------------------------------
Integer Division in flow1 function:
  r (total flow rate): 220277889022382414
  totalUnits: 254889074354287
  quotient = r / totalUnits: 864
  r1 = quotient * totalUnits: 220223560241103168
  remainder lost: 54328781279246
  This remainder goes to adjustment flow rate

5. Summary
================================================================================
Total Flow Rate: 220277889022382414
Total Units: 254889074354287
Per-Unit Flow Rate (wrappedFlowRate): 864
Effective Flow Rate: 220223560241103168
Adjustment Flow Rate: 54328781279246
Percentage to Adjustment: 0.0247%
```

## Understanding the Results

### If All Flow Goes to Adjustment

If you see:
```
🚨 CRITICAL: ALL FLOW RATE GOES TO ADJUSTMENT!
```

This means:
- `perUnitFlowRate` is 0 or very small
- `effectiveFlowRate = 0 * totalUnits = 0`
- All flow goes to adjustment instead of members

**Possible causes**:
1. Precision loss from `int128` → `int96` conversion
2. Integer division rounding down to 0
3. Flow rate is smaller than total units (per-unit < 1)

### If High Percentage Goes to Adjustment

If adjustment flow rate is > 10%:
```
⚠️  WARNING: More than 10% of flow rate goes to adjustment
```

This suggests:
- Significant precision loss
- Integer division remainder is large
- May need to investigate the `flow1` function logic

## Troubleshooting

### Script Fails to Connect

Make sure you have:
1. **RPC_URL environment variable set** - This is required for the standalone script
2. **Valid RPC endpoint** - The URL should be accessible and point to the correct network
3. **Correct network** - Make sure the RPC URL matches the network where your pool contract is deployed

### Contract Not Found

The script uses a minimal ABI. If the pool contract doesn't match the expected interface, you may need to:
1. Verify the pool address is correct
2. Check that the contract implements `ISuperfluidPool` interface
3. Ensure you're on the correct network

## Next Steps

After running the script:

1. **If precision loss is detected**: Review the `wrappedFlowRate` value and compare with expected per-unit flow rate
2. **If all flow goes to adjustment**: Check if `wrappedFlowRate` is 0 or if there's a calculation error
3. **If remainder is large**: Consider if the integer division in `flow1` is causing the issue

Share the output with the team to diagnose the root cause!

