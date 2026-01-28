# GDA Pool Distribution Issue Analysis

## Problem Summary
Pool `0xc406eb08a815bb8543f1ade3f865398bcdab4b09` has:
- Flow rate to pool: `220277889022382414`
- Connected units: `254889074354287`
- Issue: All distribution goes to adjustment flow rate instead of members

## Root Cause: Integer Division and Precision Loss

### The Issue

There are **two related problems**:

1. **Integer Division in `flow1` function** (SemanticMoney.sol line 363):
   ```solidity
   r1 = r.div(a.total_units).mul(a.total_units);
   ```
   This performs integer division which **always loses the remainder**. The remainder should go to adjustment flow, but if the per-unit flow rate rounds to 0, everything goes to adjustment.

2. **Type Mismatch and Precision Loss**:
   - `FlowRate` type in SemanticMoney is `int128` (128 bits)
   - `wrappedFlowRate` in `PoolIndexData` is stored as `int96` (96 bits)
   - In `SuperfluidPool.sol` line 329:
     ```solidity
     wrappedFlowRate: int256(FlowRate.unwrap(pdPoolIndex.flow_rate_per_unit())).toInt96(),
     ```
     This converts `int128` → `int256` → `int96`, potentially losing precision.

3. **Calculation Chain**:
   - Per-unit flow rate = `220277889022382414 / 254889074354287 ≈ 864.2...`
   - When stored as `int96`, this value may lose precision
   - When calculating total flow rate (line 256):
     ```solidity
     return (_index.wrappedFlowRate * uint256(_index.totalUnits).toInt256()).toInt96();
     ```
   - The imprecise per-unit flow rate × total units < actual total flow rate
   - Difference goes to adjustment flow rate

### Why Everything Goes to Adjustment Flow

The effective flow rate calculation:
```
effectiveFlowRate = perUnitFlowRate (imprecise) × totalUnits
adjustmentFlowRate = totalFlowRate - effectiveFlowRate
```

**Critical Issue**: In `SemanticMoney.sol` line 363, the `flow1` function does:
```solidity
r1 = r.div(a.total_units).mul(a.total_units);
```

This means:
- If `r = 220277889022382414` and `total_units = 254889074354287`
- `r1 = (220277889022382414 / 254889074354287) * 254889074354287`
- Due to integer division: `r1 = 864 * 254889074354287 = 220223560241103168`
- **Remainder lost**: `220277889022382414 - 220223560241103168 = 54328781279246`

However, if the per-unit flow rate (`r / total_units`) is less than 1 or rounds to 0 due to precision loss when stored as `int96`, then:
- `perUnitFlowRate = 0`
- `effectiveFlowRate = 0 * totalUnits = 0`
- `adjustmentFlowRate = totalFlowRate - 0 = totalFlowRate` (everything!)

This explains why **everything goes to adjustment flow**.

### The Numbers

- Total flow rate: `220277889022382414`
- Connected units: `254889074354287`
- Expected per-unit: `220277889022382414 / 254889074354287 ≈ 864.2...`

If the per-unit flow rate is stored imprecisely as `int96`, then:
- Stored per-unit might be: `864` (losing decimal precision)
- Effective flow rate: `864 × 254889074354287 = 220223560241103168`
- Adjustment flow rate: `220277889022382414 - 220223560241103168 = 54328781279246`

This explains why distribution goes to adjustment flow instead of members.

## Potential Solutions

1. **Change storage type**: Store `wrappedFlowRate` as `int128` instead of `int96`
   - Requires storage layout change (breaking change)
   - May need migration

2. **Use higher precision calculation**: Calculate flow rates using `int256` internally, only downcast when necessary

3. **Fix the calculation**: Ensure the per-unit flow rate calculation preserves precision throughout

## Files to Review

- `packages/ethereum-contracts/contracts/agreements/gdav1/SuperfluidPool.sol`
  - Line 72: `int96 wrappedFlowRate;` (storage)
  - Line 329: Conversion from `int128` to `int96`
  - Line 256: Total flow rate calculation

- `packages/solidity-semantic-money/src/SemanticMoney.sol`
  - Line 116: `FlowRate` is `int128`
  - Line 344-345: `flow_rate_per_unit()` returns `FlowRate`

## Note on 1e3/1e4 Scalar

The user suspected a 1e3 or 1e4 scalar issue. This is likely not a scalar multiplication, but rather the precision loss from the int128→int96 conversion that creates a similar effect where small values are lost, making it appear as if there's a scaling factor.

## Additional Investigation Needed

To fully diagnose this issue, we need to check:

1. **Actual stored values**: What is the actual `wrappedFlowRate` value stored in the pool?
2. **Calculation verification**: Verify the calculation chain:
   - `flow_rate_per_unit()` from SemanticMoney (int128)
   - Conversion to `wrappedFlowRate` (int96) 
   - Multiplication by `totalUnits` to get total flow rate
   - Comparison with actual total flow rate

3. **Integer division issue**: The subgraph calculates:
   ```typescript
   pool.perUnitFlowRate = divideOrZero(pool.flowRate, pool.totalUnits);
   ```
   This integer division will always produce a remainder that goes to adjustment flow. If the per-unit flow rate is very small (< 1), it could round to 0, causing everything to go to adjustment.

4. **Check if perUnitFlowRate is 0**: If `perUnitFlowRate` is 0 or very small due to precision loss, then `effectiveFlowRate = 0 * totalUnits = 0`, and all flow goes to adjustment.

## Recommended Next Steps

1. **Run the Analysis Script** (Standalone - No Hardhat Required): 
   ```bash
   cd packages/ethereum-contracts
   RPC_URL=https://polygon-rpc.com POOL_ADDRESS=0xc406eb08a815bb8543f1ade3f865398bcdab4b09 node scripts/analyze-pool-calculation-standalone.js
   ```
   
   Or with TypeScript:
   ```bash
   RPC_URL=https://polygon-rpc.com POOL_ADDRESS=0xc406eb08a815bb8543f1ade3f865398bcdab4b09 npx ts-node scripts/analyze-pool-calculation-standalone.ts
   ```
   This script will:
   - Query the pool's `wrappedFlowRate` value directly from the contract
   - Calculate `wrappedFlowRate * totalUnits` and compare with actual `flowRate`
   - Show the exact calculation chain as the contracts perform it
   - Identify precision loss and integer division remainders
   - See `packages/ethereum-contracts/scripts/README-analyze-pool.md` for detailed usage

2. Check if there's a scenario where `wrappedFlowRate` becomes 0 or very small
3. Verify the `flow1` function in SemanticMoney.sol (line 358-366) to see how it handles the division
4. Compare the script output with the expected values to pinpoint the exact issue

