import { ethers } from "hardhat";

/**
 * Script to analyze GDA pool flow rate calculations
 * 
 * This script queries the pool contract and replicates the exact calculation
 * logic used in the contracts to identify precision loss issues.
 * 
 * Usage:
 *   npx hardhat run scripts/analyze-pool-calculation.ts --network <network>
 * 
 * Or with custom pool address:
 *   POOL_ADDRESS=0x... npx hardhat run scripts/analyze-pool-calculation.ts --network <network>
 */

const POOL_ADDRESS = process.env.POOL_ADDRESS || "0xc406eb08a815bb8543f1ade3f865398bcdab4b09";

interface PoolIndexData {
  totalUnits: bigint;
  wrappedSettledAt: number;
  wrappedFlowRate: bigint; // int96
  wrappedSettledValue: bigint; // int256
}

async function main() {
  console.log("=".repeat(80));
  console.log("GDA Pool Flow Rate Calculation Analysis");
  console.log("=".repeat(80));
  console.log(`Pool Address: ${POOL_ADDRESS}\n`);

  // Get the pool contract
  // Note: We use the ABI from the interface to query the pool
  const poolABI = [
    "function poolOperatorGetIndex() external view returns (tuple(uint128 totalUnits, uint32 wrappedSettledAt, int96 wrappedFlowRate, int256 wrappedSettledValue))",
    "function getTotalUnits() external view returns (uint128)",
    "function getTotalConnectedUnits() external view returns (uint128)",
    "function getTotalDisconnectedUnits() external view returns (uint128)",
    "function getTotalFlowRate() external view returns (int96)",
    "function getTotalConnectedFlowRate() external view returns (int96)",
    "function getTotalDisconnectedFlowRate() external view returns (int96)",
  ];
  
  const pool = new ethers.Contract(POOL_ADDRESS, poolABI, ethers.provider);

  // Query all relevant values
  console.log("1. Querying Pool Contract Values...");
  console.log("-".repeat(80));

  const [
    totalUnitsBN,
    totalConnectedUnitsBN,
    totalDisconnectedUnitsBN,
    totalFlowRateBN,
    totalConnectedFlowRateBN,
    totalDisconnectedFlowRateBN,
    poolIndexData,
  ] = await Promise.all([
    pool.getTotalUnits(),
    pool.getTotalConnectedUnits(),
    pool.getTotalDisconnectedUnits(),
    pool.getTotalFlowRate(),
    pool.getTotalConnectedFlowRate(),
    pool.getTotalDisconnectedFlowRate(),
    pool.poolOperatorGetIndex(),
  ]);

  // Convert BigNumber to bigint for calculations
  const totalUnits = BigInt(totalUnitsBN.toString());
  const totalConnectedUnits = BigInt(totalConnectedUnitsBN.toString());
  const totalDisconnectedUnits = BigInt(totalDisconnectedUnitsBN.toString());
  const totalFlowRate = BigInt(totalFlowRateBN.toString());
  const totalConnectedFlowRate = BigInt(totalConnectedFlowRateBN.toString());
  const totalDisconnectedFlowRate = BigInt(totalDisconnectedFlowRateBN.toString());

  // Extract pool index data (ethers returns BigNumber, convert to bigint)
  const indexData: PoolIndexData = {
    totalUnits: BigInt(poolIndexData.totalUnits.toString()),
    wrappedSettledAt: poolIndexData.wrappedSettledAt,
    wrappedFlowRate: BigInt(poolIndexData.wrappedFlowRate.toString()),
    wrappedSettledValue: BigInt(poolIndexData.wrappedSettledValue.toString()),
  };

  console.log("Pool Index Data (from poolOperatorGetIndex):");
  console.log(`  totalUnits: ${indexData.totalUnits.toString()}`);
  console.log(`  wrappedSettledAt: ${indexData.wrappedSettledAt}`);
  console.log(`  wrappedFlowRate (int96): ${indexData.wrappedFlowRate.toString()}`);
  console.log(`  wrappedSettledValue (int256): ${indexData.wrappedSettledValue.toString()}`);
  console.log();

  console.log("Pool State (from view functions):");
  console.log(`  totalUnits: ${totalUnits.toString()}`);
  console.log(`  totalConnectedUnits: ${totalConnectedUnits.toString()}`);
  console.log(`  totalDisconnectedUnits: ${totalDisconnectedUnits.toString()}`);
  console.log(`  totalFlowRate (int96): ${totalFlowRate.toString()}`);
  console.log(`  totalConnectedFlowRate (int96): ${totalConnectedFlowRate.toString()}`);
  console.log(`  totalDisconnectedFlowRate (int96): ${totalDisconnectedFlowRate.toString()}`);
  console.log();

  // Replicate contract calculations
  console.log("2. Replicating Contract Calculations...");
  console.log("-".repeat(80));

  // Calculation from _getTotalFlowRate() in SuperfluidPool.sol line 256:
  // return (_index.wrappedFlowRate * uint256(_index.totalUnits).toInt256()).toInt96();
  const calculatedTotalFlowRate = BigInt(indexData.wrappedFlowRate) * BigInt(indexData.totalUnits);
  const calculatedTotalFlowRateInt96 = signedInt96(calculatedTotalFlowRate);

  console.log("Calculation: _getTotalFlowRate()");
  console.log(`  wrappedFlowRate: ${indexData.wrappedFlowRate.toString()}`);
  console.log(`  totalUnits: ${indexData.totalUnits.toString()}`);
  console.log(`  wrappedFlowRate * totalUnits (before int96 cast): ${calculatedTotalFlowRate.toString()}`);
  console.log(`  After int96 cast: ${calculatedTotalFlowRateInt96.toString()}`);
  console.log(`  Contract's getTotalFlowRate(): ${totalFlowRate.toString()}`);
  console.log(`  Match: ${calculatedTotalFlowRateInt96 === totalFlowRate ? "✓" : "✗ MISMATCH!"}`);
  console.log();

  // Calculate per-unit flow rate
  // This is what flow_rate_per_unit() would return in SemanticMoney
  // flow_rate_per_unit = wrappedFlowRate (already per-unit)
  const perUnitFlowRate = indexData.wrappedFlowRate;
  
  console.log("Per-Unit Flow Rate Calculation:");
  console.log(`  wrappedFlowRate (stored per-unit): ${perUnitFlowRate.toString()}`);
  console.log(`  This is the per-unit flow rate stored as int96`);
  console.log();

  // Calculate what the effective flow rate should be
  // effectiveFlowRate = perUnitFlowRate * totalUnits
  const effectiveFlowRate = BigInt(perUnitFlowRate) * BigInt(indexData.totalUnits);
  const effectiveFlowRateInt96 = signedInt96(effectiveFlowRate);

  console.log("Effective Flow Rate Calculation:");
  console.log(`  perUnitFlowRate: ${perUnitFlowRate.toString()}`);
  console.log(`  totalUnits: ${indexData.totalUnits.toString()}`);
  console.log(`  effectiveFlowRate = perUnitFlowRate * totalUnits: ${effectiveFlowRateInt96.toString()}`);
  console.log();

  // Calculate adjustment flow rate
  // adjustmentFlowRate = totalFlowRate - effectiveFlowRate
  const adjustmentFlowRate = totalFlowRate - effectiveFlowRateInt96;

  console.log("Adjustment Flow Rate Calculation:");
  console.log(`  totalFlowRate: ${totalFlowRate.toString()}`);
  console.log(`  effectiveFlowRate: ${effectiveFlowRateInt96.toString()}`);
  console.log(`  adjustmentFlowRate = totalFlowRate - effectiveFlowRate: ${adjustmentFlowRate.toString()}`);
  console.log();

  // Check precision loss
  console.log("3. Precision Loss Analysis...");
  console.log("-".repeat(80));

  // Calculate what the per-unit flow rate SHOULD be (without precision loss)
  // This is: totalFlowRate / totalUnits
  const expectedPerUnitFlowRate = totalFlowRate / indexData.totalUnits;
  const expectedPerUnitFlowRateRemainder = totalFlowRate % indexData.totalUnits;

  console.log("Expected vs Actual Per-Unit Flow Rate:");
  console.log(`  Expected (totalFlowRate / totalUnits): ${expectedPerUnitFlowRate.toString()}`);
  console.log(`  Remainder from division: ${expectedPerUnitFlowRateRemainder.toString()}`);
  console.log(`  Actual (wrappedFlowRate): ${perUnitFlowRate.toString()}`);
  console.log(`  Difference: ${expectedPerUnitFlowRate - perUnitFlowRate}`);
  console.log();

  // Check if precision loss occurred
  const precisionLoss = expectedPerUnitFlowRate - perUnitFlowRate;
  if (precisionLoss !== 0n) {
    console.log("⚠️  PRECISION LOSS DETECTED!");
    console.log(`  Lost precision: ${precisionLoss.toString()}`);
    console.log(`  This precision loss causes: ${(precisionLoss * indexData.totalUnits).toString()} flow rate to go to adjustment`);
  } else {
    console.log("✓ No precision loss in per-unit flow rate");
  }
  console.log();

  // Calculate what happens with integer division in flow1 function
  console.log("4. Integer Division Analysis (SemanticMoney.flow1)...");
  console.log("-".repeat(80));

  // This replicates: r1 = r.div(a.total_units).mul(a.total_units);
  // from SemanticMoney.sol line 363
  const r = totalFlowRate; // total flow rate
  const totalUnitsBig = indexData.totalUnits;
  
  // Integer division: r / totalUnits
  const quotient = r / totalUnitsBig;
  // Multiply back: quotient * totalUnits
  const r1 = quotient * totalUnitsBig;
  // Remainder lost
  const remainder = r - r1;

  console.log("Integer Division in flow1 function:");
  console.log(`  r (total flow rate): ${r.toString()}`);
  console.log(`  totalUnits: ${totalUnitsBig.toString()}`);
  console.log(`  quotient = r / totalUnits: ${quotient.toString()}`);
  console.log(`  r1 = quotient * totalUnits: ${r1.toString()}`);
  console.log(`  remainder lost: ${remainder.toString()}`);
  console.log(`  This remainder goes to adjustment flow rate`);
  console.log();

  // Summary
  console.log("5. Summary");
  console.log("=".repeat(80));
  console.log(`Total Flow Rate: ${totalFlowRate.toString()}`);
  console.log(`Total Units: ${indexData.totalUnits.toString()}`);
  console.log(`Total Connected Units: ${totalConnectedUnits.toString()}`);
  console.log(`Per-Unit Flow Rate (wrappedFlowRate): ${perUnitFlowRate.toString()}`);
  console.log(`Effective Flow Rate: ${effectiveFlowRateInt96.toString()}`);
  console.log(`Adjustment Flow Rate: ${adjustmentFlowRate.toString()}`);
  console.log(`Percentage to Adjustment: ${((Number(adjustmentFlowRate) / Number(totalFlowRate)) * 100).toFixed(4)}%`);
  console.log();

  if (adjustmentFlowRate === totalFlowRate) {
    console.log("🚨 CRITICAL: ALL FLOW RATE GOES TO ADJUSTMENT!");
    console.log("   This means perUnitFlowRate is 0 or effectiveFlowRate calculation failed.");
  } else if (Number(adjustmentFlowRate) > Number(totalFlowRate) * 0.1) {
    console.log("⚠️  WARNING: More than 10% of flow rate goes to adjustment");
    console.log("   This suggests significant precision loss.");
  } else {
    console.log("✓ Flow rate distribution appears normal");
  }
}

/**
 * Convert a bigint to int96 (signed 96-bit integer)
 * int96 range: -2^95 to 2^95 - 1
 */
function signedInt96(value: bigint): bigint {
  const maxInt96 = (1n << 95n) - 1n;
  const minInt96 = -(1n << 95n);
  
  if (value > maxInt96) {
    // Overflow: wrap around
    return value - (1n << 96n);
  } else if (value < minInt96) {
    // Underflow: wrap around
    return value + (1n << 96n);
  }
  return value;
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });

