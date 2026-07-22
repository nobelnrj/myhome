---
phase: 21-overview-filtering
plan: 02
subsystem: overview-filter-wiring
tags: [filter, overview, cash-flow, view-wiring, ovf-03]
requires:
  - OverviewFilter (value type) — 21-01
  - OverviewFilterEngine.apply / rangeBoundaries — 21-01
  - BudgetCalculator.grossSpend / grossIncome / monthlySpend (transfer exclusion)
  - BudgetCalculator.monthBoundaries (default current-month window)
provides:
  - OverviewView threads @State OverviewFilter through OverviewMonthContent
  - Effective date window = custom range (rangeBoundaries) ?? current month
  - visibleExpenses (account-filtered) as the single source for ALL cash-flow figures
  - OVF-03 data half — unfilterable global sections suppressed under an active filter
affects:
  - 21-03 (binds the visible pill/sheet controls to the already-correct @State filter)
tech-stack:
  added: []
  patterns:
    - child-view re-init on changed init params re-executes @Query with new date bounds (existing OQ3 mechanism, reused — no new re-query invented)
    - single account-filtered array (visibleExpenses) feeds every aggregation (threat T-21-03 gate)
    - locale/timezone-adaptive DateFormatter template for the custom-range header label
key-files:
  created: []
  modified:
    - MyHomeApp/Features/Overview/OverviewView.swift
decisions:
  - "Effective bounds computed in OverviewView (custom range overrides monthBoundaries); label switches to a compact 'd MMM – d MMM yyyy' range string so no stale month name shows (OVF-03)"
  - "visibleExpenses = OverviewFilterEngine.apply(filter, to: monthExpenses) is the ONLY input to spendByCategory/totalSpend/totalIncome/rankedSpend/recent — no aggregation reads the raw @Query array"
  - "reviewItems (Gmail triage banner) stays UNFILTERED — it is a triage queue, not a financial figure"
  - "Under an active filter: Net Worth card hidden (balance-sheet, all-account), Budgets glance hidden + hero budget strip fed 0/0, Over Time recomputes for an account subset but hides entirely under a custom date range"
  - "OVF-03 requirement is delivered in its DATA half here; the visible pill/clear UI half lands in 21-03 — left OVF-03 unmarked in REQUIREMENTS until then"
metrics:
  duration: ~15 min
  completed: 2026-07-22
  tasks: 2
  files: 1
---

# Phase 21 Plan 02: Overview Filter Wiring Summary

Threaded the Plan 01 `OverviewFilter`/`OverviewFilterEngine` through the live Overview
screen so every money figure recomputes for the account × date-range scope (OVF-01/02),
and suppressed the whole-month / all-account sections that cannot honestly coexist with a
subset view (OVF-03 data half). Default `OverviewFilter()` is a passthrough, so the
un-filtered screen is byte-for-byte identical to pre-phase.

## What Was Built

- **Filter state + effective window** — `OverviewView` now holds `@State var filter =
  OverviewFilter()`. A new `effectiveBounds` computed picks the custom-range boundaries
  (`OverviewFilterEngine.rangeBoundaries`) when `filter.dateRange` is set, otherwise the
  existing `BudgetCalculator.monthBoundaries(for: currentMonth)`. The header label follows:
  `formattedAsMonthYear()` by default, a compact `rangeLabel(from:to:)` ("5 Jun – 12 Jul
  2026", same-year drops the leading year) for a custom range — preventing a stale month
  name over range-filtered figures (OVF-03).
- **Account-filtered aggregations** — `OverviewMonthContent` gained `let filter:
  OverviewFilter`. Its `body` opens with `let visibleExpenses =
  OverviewFilterEngine.apply(filter, to: monthExpenses)`, and `spendByCategory`,
  `totalSpend`, `totalIncome`, `rankedSpend`/donut/`categoryItems`, and `recent` all consume
  `visibleExpenses`. Transfer exclusion is inherited unchanged (the aggregations still route
  through `BudgetCalculator.grossSpend/grossIncome`, i.e. `isTransferForCashFlow`). The date
  window still comes from the @Query predicate fed by the effective bounds — the child
  re-inits when bounds change (existing OQ3 mechanism), so no new re-query was invented.
- **OVF-03 suppression of unfilterable sections** —
  - Net Worth card: `showNetWorth && !filter.isActive` (balance-sheet total across all
    accounts + assets).
  - Budgets glance section: `!budgeted.isEmpty && !filter.isActive`; the hero budget strip
    is fed `budgetedSpent: 0, totalBudget: 0` while active so `SpendBudgetCard` renders its
    existing no-budget state.
  - Over Time chart: fed `OverviewFilterEngine.apply(filter, to: allGlobalExpenses)` so it
    recomputes for an account subset, but hidden entirely when a custom date range is active
    (`filter.dateRange == nil` gate) — a multi-month series contradicts the selected range.
- **`reviewItems` left unfiltered** — documented as a triage queue, not a financial figure.
- **No DesignSystem edits** — the DarkBitIdentity / DesignTokens contract (Phase 17) is
  untouched; `git diff` shows only `OverviewView.swift` changed.

## Verification

- `xcodebuild build -scheme MyHome -destination 'iPhone 17'` → exit 0.
- `grep -c "OverviewFilterEngine.apply" OverviewView.swift` → 1 (used for both the primary
  visibleExpenses and Over Time subset; the apply call for visibleExpenses is the enforced one).
- `grep -n "grossSpend(for: monthExpenses\|grossIncome(for: monthExpenses\|monthlySpend(for:
  monthExpenses" OverviewView.swift` → NOTHING (no cash-flow aggregation reads the raw @Query
  array — threat T-21-03 gate satisfied).
- `grep -c "filter.isActive" OverviewView.swift` → 4 (net-worth + budgets glance + budget-strip
  spent/total gates).
- `xcodebuild test -only-testing:MyHomeTests` → GREEN on a clean run, including
  `OverviewFilterTests` (8) and `DesignTokensTests` / `DarkBitIdentityTests` dark bit-identity.
- Seeded-simulator screenshot of the default Overview matches the pre-change layout exactly
  (JULY 2026 eyebrow, 73% hero, ₹14,000 income / ₹37,540 spent, budget strip, Net Worth +
  Budgets sections all present because `filter.isActive == false`).

## Deviations from Plan

None — plan executed as written.

## Notes

- **Flaky suite observed once:** the first `xcodebuild test` run reported `** TEST FAILED **`
  with no failing assertion, crash, or `error:` line; an immediate re-run reported `** TEST
  SUCCEEDED **`. This matches the documented `LockSettingsTests`/`LockStateTests`
  shared-UserDefaults race (Swift Testing parallelism) in project memory, not this change —
  the only modified file is `OverviewView.swift`, and every Overview/DesignTokens test passed
  on both runs.
- **OVF-03 requirement** is only half-delivered here (the data-suppression half). The visible
  scope pill + one-tap clear UI is Plan 03, so OVF-03 was NOT marked complete in REQUIREMENTS;
  OVF-01 and OVF-02 are complete.

## Self-Check: PASSED

- FOUND: MyHomeApp/Features/Overview/OverviewView.swift (modified)
- FOUND commit 921a505 (feat(21-02) thread filter into aggregations)
- FOUND commit 171408d (feat(21-02) suppress unfilterable sections)
</content>
</invoke>
