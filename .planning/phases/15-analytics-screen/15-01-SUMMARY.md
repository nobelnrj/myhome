---
phase: 15-analytics-screen
plan: "01"
subsystem: analytics-aggregator
tags: [analytics, aggregator, IST, bucketing, TDD, pure-swift]
dependency_graph:
  requires: []
  provides: [SpendSummary, AnalyticsAggregator.summarize]
  affects: [15-02-analytics-ui, 15-03-delta-chips, phase-16-ai-card]
tech_stack:
  added: []
  patterns: [injectable-calendar-timezone, delegate-bucketing-to-existing-aggregator, Decimal-at-boundary]
key_files:
  created:
    - MyHomeApp/Support/AnalyticsAggregator.swift
    - MyHomeTests/AnalyticsAggregatorTests.swift
  modified:
    - MyHomeApp/Support/SpendOverTimeAggregator.swift
    - MyHome.xcodeproj/project.pbxproj
decisions:
  - "Use dynamic dates relative to today (not fixed 2025 dates) in testMidnightISTBucketBoundary so the .week period window includes the test expenses on any execution date"
  - "AnalyticsAggregator imports SwiftUI for Color (CategorySpendItem.color field) — only import strictly needed; zero View code added"
  - "BudgetCalculator.monthlySpend already excludes self-transfers; AnalyticsAggregator pre-filters before calling it to avoid double-filtering while keeping the explicit isTransfer check visible in the aggregator"
metrics:
  duration: ~35min
  completed: "2026-06-23"
  tasks: 3
  files: 4
---

# Phase 15 Plan 01: AnalyticsAggregator + SpendSummary + Tests Summary

Pure data layer for Analytics: `AnalyticsAggregator.summarize` returning `SpendSummary` with IST-injectable calendar, Decimal-correct delta, and delegation to `SpendOverTimeAggregator` for all bucketing (ANL-03/ANL-07).

## What Was Built

### Task 1 — SpendOverTimeAggregator timezone injection fix (ANL-03 prereq)
**Commit:** `02f9a57`

Removed `cal.timeZone = TimeZone.current` overrides from all five private helpers (`startOfDay`, `startOfMonth`, `weekBuckets`, `monthBuckets`, `yearBuckets`). The helpers now use the caller's `calendar` parameter timezone unchanged. The public `bucket(expenses:range:calendar:)` signature and its `calendar: Calendar = .current` default are unchanged, so all existing call sites are behaviorally identical. Updated doc comment to document the injectable-timezone contract.

Verified: `grep -c 'cal.timeZone = TimeZone.current'` = 0; existing `SpendOverTimeAggregatorTests` (9 tests) all pass.

### Task 2 — AnalyticsAggregator + SpendSummary, pbxproj G140 (ANL-07, ANL-03)
**Commit:** `c7308b0`

Created `MyHomeApp/Support/AnalyticsAggregator.swift` (~250 lines):

- `struct SpendSummary`: `range`, `totalSpend`, `priorTotalSpend` (Decimal), computed `delta`/`deltaFraction` (Pitfall 7: NSDecimalNumber conversion only), `trendBuckets [SpendBucket]`, `categoryBreakdown [CategorySpendItem]` (sorted descending), `priorCategorySpend [PersistentIdentifier: Decimal]`.
- `enum AnalyticsAggregator`: `static func summarize(expenses:categories:range:calendar: Calendar = .current) -> SpendSummary`.
  - Delegates bucketing to `SpendOverTimeAggregator.bucket(...)` — no re-implemented date logic (ANL-03).
  - Year range: filters `trendBuckets` to `month <= currentMonth` (no future zero-bars).
  - Per-category breakdown via `BudgetCalculator.monthlySpend`, colors via `CategoryStyle.color(for:)`.
  - `currentPeriodBounds` / `priorPeriodBounds` private helpers compute period windows only.
- Registered: `FANL01` in PBXFileReference, `AANL01` in PBXBuildFile, `FANL01` in G140 Support group children, `AANL01` in P001 app target Sources.
- Also pre-registered `FANL07`/`AANL07` for the test file (Task 3).

Build: `xcodebuild build` → **BUILD SUCCEEDED**, zero `AnalyticsAggregator`/`SpendSummary` errors.

### Task 3 — AnalyticsAggregatorTests + pbxproj G200 (ANL-07 exit criterion)
**Commit:** `2cfb777`

Created `MyHomeTests/AnalyticsAggregatorTests.swift` (5 tests):

| Test | Result |
|------|--------|
| `testMidnightISTBucketBoundary` | PASS — two expenses 2 min apart straddling IST midnight (18:29Z / 18:31Z UTC, dynamically dated 2 days ago) → 2 non-zero IST day buckets |
| `testYearNoFutureBuckets` | PASS — `.year` `trendBuckets.count` <= current month |
| `testSelfTransferExclusion` | PASS — `isTransfer==true` excluded from `totalSpend` and all buckets |
| `testDelta` | PASS — current > prior → `delta > 0`, `deltaFraction ≈ 1.0` |
| `testDeltaZeroGuard` | PASS — `priorTotalSpend == 0` → `deltaFraction == 0` |

Registered: `FANL07` in G200 MyHomeTests group children, `AANL07` in P003 test target Sources.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Dynamic dates in testMidnightISTBucketBoundary instead of fixed 2025 dates**
- **Found during:** Task 3 first test run
- **Issue:** Research doc used fixed `"2025-03-15T18:29:00Z"` dates. The `.week` range window is `today-6..today` (June 2026), so March 2025 expenses were outside the window → zero non-zero buckets → test failed.
- **Fix:** Replaced fixed dates with dynamic dates computed as "2 days ago at 18:29 UTC" and "2 days ago at 18:31 UTC", which always fall within the 7-day window regardless of execution date. IST boundary semantics are identical (UTC 18:29/18:31 straddle IST midnight at UTC 18:30).
- **Files modified:** `MyHomeTests/AnalyticsAggregatorTests.swift`
- **Commit:** `2cfb777`

**2. [Rule 1 - Bug] Swift Testing Comment type: string interpolation not allowed**
- **Found during:** Task 3 first compile attempt
- **Issue:** `#expect(condition, "...\(variable)")` — Swift Testing `Comment` type requires a string literal, not an interpolated string expression.
- **Fix:** Replaced all `#expect` message arguments containing string interpolation with static string literals.
- **Files modified:** `MyHomeTests/AnalyticsAggregatorTests.swift`
- **Commit:** `2cfb777`

## Known Stubs

None. `AnalyticsAggregator.summarize` is fully wired — it computes real period bounds, filters real expenses, delegates real bucketing, and returns real `SpendSummary` values. No placeholder data.

## Threat Surface Scan

No new network endpoints, auth paths, file access, or schema changes. `AnalyticsAggregator` is a pure value-type helper over already-persisted `Expense`/`Category` data.

T-15-01 mitigated: self-transfer-excluded via `isTransfer != true` in period filter + `BudgetCalculator.monthlySpend` (which also excludes transfers).
T-15-02 mitigated: existing `SpendOverTimeAggregatorTests` (9 tests) verified green after timezone injection change.
T-15-03 mitigated: build gate and test gate both passed; pbxproj registration confirmed.

## Self-Check: PASSED

| Item | Status |
|------|--------|
| `MyHomeApp/Support/AnalyticsAggregator.swift` | FOUND |
| `MyHomeTests/AnalyticsAggregatorTests.swift` | FOUND |
| commit `02f9a57` (Task 1 — SpendOverTimeAggregator fix) | FOUND |
| commit `c7308b0` (Task 2 — AnalyticsAggregator + pbxproj) | FOUND |
| commit `2cfb777` (Task 3 — AnalyticsAggregatorTests + pbxproj) | FOUND |
