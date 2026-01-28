/**
 * Standalone script to analyze GDA pool flow rate calculations
 * 
 * This script queries the pool contract and replicates the exact calculation
 * logic used in the contracts to identify precision loss issues.
 * 
 * Usage:
 *   node scripts/analyze-pool-calculation-standalone.js
 * 
 * Or with environment variables:
 *   POOL_ADDRESS=0x... RPC_URL=https://... node scripts/analyze-pool-calculation-standalone.js
 */

const { ethers } = require("ethers");

const POOL_ADDRESS = process.env.POOL_ADDRESS || "0xc406eb08a815bb8543f1ade3f865398bcdab4b09";
const RPC_URL = process.env.RPC_URL || process.env.PROVIDER_URL || "";

if (!RPC_URL) {
  console.error("Error: RPC_URL or PROVIDER_URL environment variable is required");
  console.error("Example: RPC_URL=https://polygon-rpc.com node scripts/analyze-pool-calculation-standalone.js");
  process.exit(1);
}

async function main() {
  console.log("=".repeat(80));
  console.log("GDA Pool Flow Rate Calculation Analysis");
  console.log("=".repeat(80));
  console.log(`Pool Address: ${POOL_ADDRESS}`);
  console.log(`RPC URL: ${RPC_URL}\n`);

  // Connect to provider
  const provider = new ethers.providers.JsonRpcProvider(RPC_URL);

  // Pool contract ABI (minimal, just what we need)
  const poolABI = [
    "function poolOperatorGetIndex() external view returns (tuple(uint128 totalUnits, uint32 wrappedSettledAt, int96 wrappedFlowRate, int256 wrappedSettledValue))",
    "function getTotalUnits() external view returns (uint128)",
    "function getTotalConnectedUnits() external view returns (uint128)",
    "function getTotalDisconnectedUnits() external view returns (uint128)",
    "function getTotalFlowRate() external view returns (int96)",
    "function getTotalConnectedFlowRate() external view returns (int96)",
    "function getTotalDisconnectedFlowRate() external view returns (int96)",
  ];
  
  const pool = new ethers.Contract(POOL_ADDRESS, poolABI, provider);

  // Query all relevant values
  console.log("1. Querying Pool Contract Values...");
  console.log("-".repeat(80));

  try {
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

    // Convert BigNumber to BigInt for calculations
    const totalUnits = BigInt(totalUnitsBN.toString());
    const totalConnectedUnits = BigInt(totalConnectedUnitsBN.toString());
    const totalDisconnectedUnits = BigInt(totalDisconnectedUnitsBN.toString());
    const totalFlowRate = BigInt(totalFlowRateBN.toString());
    const totalConnectedFlowRate = BigInt(totalConnectedFlowRateBN.toString());
    const totalDisconnectedFlowRate = BigInt(totalDisconnectedFlowRateBN.toString());

    // Extract pool index data
    const indexData = {
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
    const calculatedTotalFlowRate = indexData.wrappedFlowRate * indexData.totalUnits;
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
    const perUnitFlowRate = indexData.wrappedFlowRate;
    
    console.log("Per-Unit Flow Rate Calculation:");
    console.log(`  wrappedFlowRate (stored per-unit): ${perUnitFlowRate.toString()}`);
    console.log(`  This is the per-unit flow rate stored as int96`);
    console.log();

    // Calculate what the effective flow rate should be
    const effectiveFlowRate = perUnitFlowRate * indexData.totalUnits;
    const effectiveFlowRateInt96 = signedInt96(effectiveFlowRate);

    console.log("Effective Flow Rate Calculation:");
    console.log(`  perUnitFlowRate: ${perUnitFlowRate.toString()}`);
    console.log(`  totalUnits: ${indexData.totalUnits.toString()}`);
    console.log(`  effectiveFlowRate = perUnitFlowRate * totalUnits: ${effectiveFlowRateInt96.toString()}`);
    console.log();

    // Calculate adjustment flow rate
    const adjustmentFlowRate = totalFlowRate - effectiveFlowRateInt96;

    console.log("Adjustment Flow Rate Calculation:");
    console.log(`  totalFlowRate: ${totalFlowRate.toString()}`);
    console.log(`  effectiveFlowRate: ${effectiveFlowRateInt96.toString()}`);
    console.log(`  adjustmentFlowRate = totalFlowRate - effectiveFlowRate: ${adjustmentFlowRate.toString()}`);
    console.log();

    // Check precision loss
    console.log("3. Precision Loss Analysis...");
    console.log("-".repeat(80));

    const expectedPerUnitFlowRate = totalFlowRate / indexData.totalUnits;
    const expectedPerUnitFlowRateRemainder = totalFlowRate % indexData.totalUnits;

    console.log("Expected vs Actual Per-Unit Flow Rate:");
    console.log(`  Expected (totalFlowRate / totalUnits): ${expectedPerUnitFlowRate.toString()}`);
    console.log(`  Remainder from division: ${expectedPerUnitFlowRateRemainder.toString()}`);
    console.log(`  Actual (wrappedFlowRate): ${perUnitFlowRate.toString()}`);
    console.log(`  Difference: ${expectedPerUnitFlowRate - perUnitFlowRate}`);
    console.log();

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

    const r = totalFlowRate;
    const totalUnitsBig = indexData.totalUnits;
    
    const quotient = r / totalUnitsBig;
    const r1 = quotient * totalUnitsBig;
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
    
    const adjustmentPercentage = Number(adjustmentFlowRate) / Number(totalFlowRate) * 100;
    console.log(`Percentage to Adjustment: ${adjustmentPercentage.toFixed(4)}%`);
    console.log();

    if (adjustmentFlowRate === totalFlowRate) {
      console.log("🚨 CRITICAL: ALL FLOW RATE GOES TO ADJUSTMENT!");
      console.log("   This means perUnitFlowRate is 0 or effectiveFlowRate calculation failed.");
    } else if (adjustmentPercentage > 10) {
      console.log("⚠️  WARNING: More than 10% of flow rate goes to adjustment");
      console.log("   This suggests significant precision loss.");
    } else {
      console.log("✓ Flow rate distribution appears normal");
    }

  } catch (error) {
    console.error("Error querying pool contract:");
    console.error(error.message);
    if (error.code === "NETWORK_ERROR" || error.code === "SERVER_ERROR") {
      console.error("\nMake sure RPC_URL is correct and the network is accessible.");
    } else if (error.code === "CALL_EXCEPTION") {
      console.error("\nMake sure POOL_ADDRESS is correct and the contract exists on this network.");
    }
    process.exit(1);
  }
}

/**
 * Convert a BigInt to int96 (signed 96-bit integer)
 * int96 range: -2^95 to 2^95 - 1
 */
function signedInt96(value) {
  const maxInt96 = (1n << 95n) - 1n;
  const minInt96 = -(1n << 95n);
  
  if (value > maxInt96) {
    return value - (1n << 96n);
  } else if (value < minInt96) {
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

