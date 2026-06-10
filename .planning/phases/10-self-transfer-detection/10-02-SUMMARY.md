---
phase: 10-self-transfer-detection
plan: "02"
subsystem: budgeting
tags: [swift, swiftdata, budget, aggregation, transfer-exclusion, tdd]

requires:
  - phase: 10-self-transfer-detection/10-01
    provides: isTransfer Bool? field on Expense (SchemaV6), TransferDetectionScorer, TransferScanService

provides:
  - BudgetCalculator.monthlySpend excludes isTransfer == true expenses (D-15)
  - BudgetCalculator.uncategorizedSpend excludes isTransfer == true expenses (D-15)
  - SpendOverTimeAggregator.bucket excludes isTransfer == true before dispatching to week/month/year helpers
  - OverviewAggregation verified to consume BudgetCalculator-filtered output only (no raw-array bypass)
  - TDD tests for all four D-15 exclusion behaviors

affects:
  - 10-self-transfer-detection/10-03
  - 10-self-transfer-detection/10-04
  - any phase that reads monthlySpend, uncategorizedSpend, or chart buckets

tech-stack:
  added: []
  patterns:
    - "D-15 transfer exclusion: .filter { $0.isTransfer != true } at every aggregator input boundary"
    - "!= true predicate: excludes only isTransfer == true; nil and false both counted as spend"
    - "Single insertion point per aggregator: filter applied once before dispatch, not inside each helper"

key-files:
  created: []
  modified:
    - MyHomeApp/Support/BudgetCalculator.swift
    - MyHomeApp/Support/SpendOverTimeAggregator.swift
    - MyHomeTests/BudgetCalculatorTests.swift
    - MyHomeTests/SpendOverTimeAggregatorTests.swift

key-decisions:
  - "OverviewAggregation.topCategories and aggregateThreshold consume BudgetCalculator-derived maps/totals only; no raw [Expense] path exists — no direct filter needed"
  - "SpendOverTimeChart receives raw [Expense] from parent @Query but filter applied inside bucket() — single gate, no caller changes required"
  - "!= true predicate (not == false) used throughout: handles both nil (unevaluated) and false (rejected) as spend-eligible"

patterns-established:
  - "Transfer exclusion pattern: filter at aggregator input boundary before any switch/reduce — one guard per public API entry point"

requirements-completed: [XFER-04]

duration: 25min
completed: 2026-06-10
---

# Phase 10 Plan 02: Transfer Spend Exclusion Summary

**Confirmed self-transfers excluded from all spend aggregators via `.filter { $0.isTransfer != true }` at each public API boundary (D-15/XFER-04), with TDD-verified nil/false still counted.**

## Performance

- **Duration:** 25 min
- **Started:** 2026-06-10T14:10:00Z
- **Completed:** 2026-06-10T14:35:00Z
- **Tasks:** 2
- **Files modified:** 4

## Accomplishments

- BudgetCalculator.monthlySpend: `.filter { $0.isTransfer != true }` applied as first line, shadowing parameter
- BudgetCalculator.uncategorizedSpend: existing `.filter { $0.categories.isEmpty }` extended to also exclude `isTransfer == true`
- SpendOverTimeAggregator.bucket: `let spendable = expenses.filter { $0.isTransfer != true }` before the `switch range`; all three helpers (weekBuckets/monthBuckets/yearBuckets) receive `spendable` — single insertion point
- OverviewAggregation verified: `topCategories` and `aggregateThreshold` receive BudgetCalculator-derived maps/Decimal totals, not raw `[Expense]` — no direct filter needed
- 4 TDD tests for BudgetCalculator + 2 TDD tests for SpendOverTimeAggregator; all green

## Task Commits

1. **Task 1 RED: BudgetCalculator transfer-exclusion tests** - `2dc8592` (test)
2. **Task 1 GREEN: BudgetCalculator filter implementation** - `585d875` (feat)
3. **Task 2 RED: SpendOverTimeAggregator transfer-exclusion tests** - `fc053d3` (test)
4. **Task 2 GREEN: SpendOverTimeAggregator filter + OverviewAggregation verification** - `e7a9809` (feat)

## Files Created/Modified

- `MyHomeApp/Support/BudgetCalculator.swift` - monthlySpend and uncategorizedSpend now filter `isTransfer != true`
- `MyHomeApp/Support/SpendOverTimeAggregator.swift` - bucket() filters to `spendable` before dispatch
- `MyHomeTests/BudgetCalculatorTests.swift` - 4 new D-15 transfer-exclusion tests
- `MyHomeTests/SpendOverTimeAggregatorTests.swift` - 2 new D-15 chart-exclusion tests

## Decisions Made

- **OverviewAggregation path confirmed clean:** `topCategories(spendByCategory:categories:)` and `aggregateThreshold(totalSpend:totalBudget:)` both consume caller-computed Decimal values derived from BudgetCalculator — they inherit the exclusion without needing a direct filter. SUMMARY records: OverviewAggregation inherited exclusion from BudgetCalculator; no direct filter applied.
- **SpendOverTimeChart receives raw @Query array:** The chart component receives `expenses: [Expense]` from the parent's `@Query`. The D-15 filter is applied inside `bucket()` rather than at the call site, keeping caller code unchanged and ensuring any future call site also gets the exclusion for free.
- **!= true predicate used throughout:** Handles `nil` (unevaluated expenses) and `false` (rejected transfers) as spend-eligible — only confirmed (`true`) transfers are excluded.

## Deviations from Plan

None — plan executed exactly as written.

## Issues Encountered

None.

## Known Stubs

None.

## Threat Flags

None — all three STRIDE mitigations from the plan's threat register (T-10-05, T-10-06, T-10-07) are implemented and verified by the TDD suite.

## Next Phase Readiness

- Spend exclusion foundation complete; Plans 10-03 and 10-04 can build on confirmed transfer state
- OverviewAggregation chain verified — no bypass path exists
- Full test suite green at plan completion

---
*Phase: 10-self-transfer-detection*
*Completed: 2026-06-10*
