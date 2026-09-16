# SuperApp liquidation production gate

Status: implementation specification. The validator fuzz tests and callback-budget NOOP regressions exist; the production gas gate described below is still to be implemented.

## Objective and scope

A supported CFA flow into a SuperApp must remain liquidatable within a valid transaction gas limit. With sufficient gas, a callback rule violation must result in flow closure and the appropriate jail event, rather than rolling back liquidation. Honest callbacks within their allowance must not be jailed.

Gate the combined returndata and shared-callback-budget changes. Existing work is split between `callback_returndata_fix` (validator fuzzing: `359b9fad`) and `feature/shared-callback-gas` (budget lifetime fix: `9e35463b`); the release candidate must include both.

Keep this focused on callback-induced failure. Use supported SuperTokens and the normal liquidation entry points, with empty liquidation userData. Do not claim coverage of arbitrary custom token code, unlimited batches, or every possible protocol state. A single-flow fallback must work even when a larger batch cannot fit.

## Keep the implementation small

Extend the existing Foundry fixtures and callback test apps. Add one production-budget test file under `test/foundry/agreements/`, plus one small transaction smoke-test script using the existing development-node tooling. Avoid a new test framework, a general state-machine handler, or a separate configuration service.

Use a small callback behavior enum and bounded parameters for gas consumption and return size. Keep dishonest raw RETURN/REVERT assembly in the test app. Do not add production methods to make tests easier. Configure the fixture Host with the desired immutable callback limit through deployment; an etched standalone Host is useful for exploration but cannot establish proxy-path coverage.

## 1. Preserve cheap, exhaustive-in-shape checks

Run the existing `CallUtilsAnvil`, `CallbackUtilsTest`, `CallbackReturnSizeGriefTest`, `OversizedCallbackReturndataTest`, `CallbackCbdataRoundtripTest`, and `SharedCallbackGasBudgetTest` suites.

Validator properties already added:

- Arbitrary bytes must produce the correct boolean without a panic or revert.
- Also force ABI offset 32 and fuzz the full uint256 claimed length; otherwise random bytes almost always exit at the offset check.
- Compare with an independent layout oracle that does not call `padLength32`.
- When accepted, zero-copy unwrap must agree with ABI decoding. Dirty padding remains accepted, matching current behavior.

Retain deterministic malformed-head cases. Add missing boundary cases where useful: total lengths 0, 31, 32, 63, 64, and 65; offsets 0, 31, 32, and 64; claimed lengths around actual payload size and uint256.max. Do not restrict hostile claimed lengths to values that already fit.

For raw returndata, exercise cap minus one, cap, and cap plus one for CALL and STATICCALL, successful returns and reverts. The cap applies to the complete ABI returndata, including its 64-byte header. Keep coverage where calldata exceeds 128 KiB, including an honest large-context echo.

## 2. Test budget ownership through short operation sequences

Keep the three same-transaction regressions for before-only create, update, and termination followed by an independent after-only operation. They must continue to fail on the old shared-budget implementation.

Add a bounded sequence fuzz test only if it stays simple: choose from a few valid two-to-four-operation templates, vary the NOOP mask and gas workload, and exercise the same app and two different apps. Set up valid flows directly rather than filtering arbitrary illegal operation sequences with many `vm.assume` calls.

Assert that an after-only operation gets a fresh budget, a matching before/after pair shares its allowance, and a later pair starts fresh. Test a zero remainder explicitly: it must not be mistaken for an absent budget. Do not require exact gas equality; call/copy overhead is charged too. Keep honest workloads comfortably inside their allowance, with separate tests for exhaustion.

## 3. Add a bounded liquidation integration test

Reuse `FoundrySuperfluidTester` setup, but actually make the sender critical. Do not substitute sender-authorized or operator-authorized deletion for liquidation. Use a third-party liquidator and assert the account is critical before the attempt.

Run fixture creation, funding, and time advancement outside the measured liquidation call. Pass a deliberate execution gas budget to the real liquidator entry point with `.call{gas: executionBudget}(...)`. Give the outer test enough gas to supply that budget and finish assertions. Do not use the gas reported for the whole Foundry test as transaction feasibility evidence.

Use these focused cases:

| Callback behavior | Required funded outcome |
| --- | --- |
| Honest cheap pair and honest pair near the allowance | Flow closes; no jail |
| Before consumes most of allowance; after exceeds remainder | Flow closes; jail for callback failure |
| Before or after exhausts its allowance | Flow closes; jail for callback failure |
| Maximum accepted well-formed cbdata plus expensive callbacks | Flow closes; jail only if the callback actually violates a rule |
| Oversized successful before/after return | Flow closes; malformed-context jail |
| Oversized reverted return | Flow closes; termination-callback-failure jail |
| Small return with hostile claimed length | Flow closes; malformed-context jail |

Fuzz the split of work between before and after, the returned payload size, and gas supplied around relevant boundaries. Use a few explicit boundary choices as well as random values; a full Cartesian product is unnecessary. Preserve the known gasleft-dependent return-bomb cases, but use fixed-work honest controls so reducing supplied gas does not silently change the intended workload.

For an honest callback that demonstrably fits its full allowance, a gas-starved attempt must not persist a false jail. Reverting without changing the flow or jail state is acceptable. Do not require every low-gas attempt to revert: cheap operations can succeed. Do not require a particular revert selector when outer frames can themselves run out of gas.

After every funded attempt assert flow rate zero, expected jail state/reason, and the relevant liquidation event. Check token/account consistency using existing fixture helpers. Cover ordinary liquidation and insolvency/bailout once with deterministic cases; do not multiply every fuzz case by every payout mode.

Test the production `BatchLiquidator.deleteFlow` path and a one-item `deleteFlows` call. The batch method tolerates failed individual liquidations, so outer-call success alone is never sufficient. Include proxy overhead and one deterministic case with the supported agreements active on the account.

## 4. Confirm feasibility with real transactions

Foundry's bounded internal call is a fast regression test, not an exact transaction simulation. Setup may warm accesses, and the extra call frame changes EIP-150 behavior.

Before release, run a small deterministic smoke suite on a local node fork pinned by block number. Install the candidate implementation through the normal upgrade path on the fork, preserve deployed proxy/token/liquidator topology, and verify the candidate code and `CALLBACK_GAS_LIMIT()` are actually active. Never send these setup or upgrade transactions to a live chain.

Create/fund the test app and flow in earlier transactions, then send liquidation as a separate transaction with an explicit gasLimit and no access list. This gives the liquidation its own cold-access and transient-storage lifecycle. Use the target chain's EVM rules. Verify the node enforces the transaction cap; increasing the block limit or merely forking state does not configure chain-specific gas rules.

For Ethereum, EIP-7825 caps transaction gasLimit at 16,777,216, independently of the block gas limit: https://eips.ethereum.org/EIPS/eip-7825. Verify other chains' current rules separately.

Keep a small fixture table near the smoke test containing chain ID, pinned block, deployed addresses, callback limit, effective transaction cap, and approved liquidation gasLimit. Read addresses from existing metadata and verify them against the fork. Cross-check callback limits with deployment configuration and the candidate Host. Fail on unexpected differences instead of silently changing the fixture.

Start with the 15M callback configuration and the tightest transaction headroom. The repository also configures 3M, 7.5M, and 8.5M limits; use deployed/candidate values as authority. Run cheap local parameterized tests for each distinct configuration. Before deploying to a chain, require its deterministic smoke check; group configurations only when bytecode, call topology, and relevant gas rules are equivalent.

Choose an approved gasLimit below the chain cap and record the remaining headroom. Reserve intrinsic/calldata gas and any chain-specific costs when deriving the Foundry execution budget. Set the margin from measurements and review it explicitly; do not silently raise the budget until a regression passes. Report submitted gasLimit and receipt gasUsed separately: refunds and EIP-150 mean gasUsed alone does not establish how much gas must be supplied.

Use a modest gas-limit grid for diagnostics. Do not assume success is monotonic for an adversarial callback that branches on gasleft(). A failure at the approved budget blocks release; missing RPC access or unsupported node rules is an incomplete gate, not a pass.

## 5. Wire the gate into existing CI

Use `.github/workflows/call.test-ethereum-contracts.yml` and existing Nix tooling. Set `FOUNDRY_PROFILE=ci` directly in the test step's environment; writing it to GITHUB_ENV affects subsequent steps, not commands already running in that step. Artifact cache hits must not bypass a newly required gate.

Use the current 1,000-case CI fuzz setting for cheap validator/returndata properties. Start expensive liquidation fuzzing at 64 cases per property, with deterministic boundaries always included. Increase only if runtime remains reasonable. Run 10,000 cheap validator cases and a larger bounded liquidation campaign for release candidates; this does not require a new fuzzing service.

For example, the already-implemented cheap validator checks can be run from `packages/ethereum-contracts`:

```sh
nix develop --offline --no-write-lock-file -c forge test --match-contract CallUtilsAnvil --fuzz-runs 10000
```

Keep a stable CI seed for reproduction, record seeds for additional release campaigns, and turn every discovered counterexample into a named deterministic regression. Save the candidate commit, toolchain versions, fixture table, test results, and smoke transaction receipts as existing CI artifacts. Full traces are needed on failure, not for every passing fuzz case.

## Completion criteria

The gate is ready when the combined candidate passes the existing regressions, bounded liquidation tests, and target-chain transaction checks; NOOP and underfunding controls cannot falsely jail honest apps; actual flow closure is asserted; and a deliberate regression in the return cap, length guard, or budget cleanup makes the relevant test fail.

Implement in that order. Defer long randomized state machines, broad cross-chain fuzzing, and gas dashboards unless a concrete uncovered failure warrants them.
