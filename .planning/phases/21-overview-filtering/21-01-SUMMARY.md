---
phase: 21-overview-filtering
plan: 01
subsystem: overview-filter-engine
tags: [filter, overview, pure-helper, cash-flow, tdd]
requires:
  - BudgetCalculator.isTransferForCashFlow (transfer exclusion)
  - BudgetCalculator.grossSpend / grossIncome (cash-flow totals)
  - SchemaV9.Expense.accountID / isTransfer / transferPairID
  - SchemaV9.Account.id
provides:
  - OverviewFilter (value type: accountIDs, includeUnassigned, dateRange, accountFilterActive, isActive)
  - OverviewFilterEngine (matchesAccount, apply, rangeBoundaries)
affects:
  - 21-02 (threads OverviewFilter into OverviewView @Query + suppresses Budgets under active filter)
  - 21-03 (OverviewScopePill UI — consumes isActive + summary state)
tech-stack:
  added: []
  patterns:
    - pure-helper enum (no SwiftUI / no @Query), mirroring OverviewAggregation / BudgetCalculator
    - injectable Calendar for timezone-deterministic day-edge math (IST) — AnalyticsAggregator pattern
    - value-type filter state so `OverviewFilter()` default == one-tap clear
key-files:
  created:
    - MyHomeApp/Support/OverviewFilter.swift
    - MyHomeTests/OverviewFilterTests.swift
  modified:
    - MyHome.xcodeproj/project.pbxproj
decisions:
  - "apply(_:to:) owns the ACCOUNT dimension only; date scoping stays in the view @Query predicate fed by rangeBoundaries — documented division of labour"
  - "includeUnassigned is a first-class flag (not implicit) so filtered money can never silently vanish; irrelevant while accountIDs is empty"
  - "Transfer exclusion is NOT re-implemented in the engine; callers compose apply() with BudgetCalculator.grossSpend/grossIncome (T-21-02) — enforced by test, not just doc-comment"
  - "rangeBoundaries swaps from>to defensively and derives edges via Calendar (no epoch math); calendar injectable for IST day-edge tests (T-21-01)"
metrics:
  duration: ~6 min
  completed: 2026-07-22
  tasks: 2
  files: 3
---

# Phase 21 Plan 01: Overview Filter Engine Summary

Pure `OverviewFilter` state model + `OverviewFilterEngine` (account-membership filtering
and inclusive day-granular range boundaries), proven with 8 unit tests that account-subset
× custom-date-range aggregation is correct AND that the load-bearing confirmed/pending
self-transfer exclusion survives filtering unchanged.

## What Was Built

- **`OverviewFilter`** — `Equatable` value type OverviewView will hold in `@State`:
  `accountIDs: Set<UUID>` (empty = all accounts, OVF-01 default), `includeUnassigned: Bool`,
  `dateRange: ClosedRange<Date>?` (nil = current-month, OVF-02), plus derived
  `accountFilterActive` and `isActive` (drives the OVF-03 pill in Plan 03). Default `init()`
  produces the neutral all-accounts/current-month scope, so `filter = OverviewFilter()` IS the
  one-tap clear.
- **`OverviewFilterEngine`** — pure static helpers:
  - `matchesAccount(_:filter:)` — all-accounts passthrough when the account filter is inactive
    (including nil-accountID rows); otherwise membership in `accountIDs` OR unassigned-and-`includeUnassigned`.
  - `apply(_:to:)` — account-membership filter only; documents that date scoping and transfer
    exclusion are the caller's job.
  - `rangeBoundaries(from:to:calendar:)` — inclusive `[startOfDay(from) … endOfDay(to)]` mirroring
    `BudgetCalculator.monthBoundaries`, with a defensive `from>to` swap and an injectable calendar.
- **pbxproj registration** — both new files added with all 4 manual edits each
  (F21F0/A21F0 for OverviewFilter.swift → Support group + app Sources; F21FT/A21FT for the test
  → MyHomeTests group + test Sources). Project has no synchronized groups.

## Verification

- `xcodebuild build -scheme MyHome -destination 'iPhone 17'` → exit 0 (both new files compiled).
- `-only-testing:MyHomeTests/OverviewFilterTests` → 8/8 GREEN.
- `-only-testing:MyHomeTests/BudgetCalculatorTests` → GREEN (contract consumed, not modified).
- Acceptance greps: `Decimal(` count 26 (≥4, no bare-arithmetic money comparisons), `grossSpend`
  count 6 (transfer test routes through BudgetCalculator), BudgetCalculator.swift unmodified.

## Deviations from Plan

None — plan executed as written.

## TDD Gate Compliance

The plan's Task 1 (`type="auto"`) intentionally lands the full `OverviewFilterEngine`
implementation as the *contract* commit, and Task 2 (`tdd="true"`) test-drives it. Because the
engine was already fully implemented in Task 1, the Task 2 suite was GREEN on first run rather
than progressing through a discrete RED→GREEN transition. This is by plan design (contracts first
so Plans 02/03 can code against them), not a skipped RED gate: the tests genuinely exercise the
engine (8 passing assertions against real filtering/boundary math), and no production code needed
adjustment to reach GREEN. Commits: `feat(21-01)` (contract + impl) → `test(21-01)` (behaviors).
Note: plan-level `tdd_mode` is disabled in config, and no MVP+TDD runtime gate was active.

## Self-Check: PASSED

- FOUND: MyHomeApp/Support/OverviewFilter.swift
- FOUND: MyHomeTests/OverviewFilterTests.swift
- FOUND commit 7bf065a (feat(21-01) contract)
- FOUND commit f559ace (test(21-01) behaviors)
