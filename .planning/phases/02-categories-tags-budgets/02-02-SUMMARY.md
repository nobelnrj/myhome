---
phase: 02-categories-tags-budgets
plan: "02"
subsystem: support
tags: [budget-math, pure-value-types, decimal, timezone, tdd]
dependency_graph:
  requires: [02-01]
  provides: [BudgetColor, BudgetProgressData, BudgetCalculator, monthlySpend, uncategorizedSpend, monthBoundaries]
  affects: [BudgetProgressView, BudgetCategoryCard, BudgetsView]
tech_stack:
  added: [BudgetCalculator static helpers, BudgetProgressData value type, BudgetColor enum]
  patterns: [pure value types, in-memory reduce over fetched arrays, Decimal money math with Double only for bar fraction, timezone-aware Calendar month boundaries]
key_files:
  created:
    - MyHomeApp/Support/BudgetCalculator.swift
    - MyHomeTests/BudgetCalculatorTests.swift
  modified:
    - MyHome.xcodeproj/project.pbxproj
decisions:
  - "fractionUsed guards budget > 0 (T-02-05) returning nil for nil/zero/negative budgets — no divide-by-zero, colorThreshold falls back to .normal"
  - "Money math stays Decimal end-to-end (T-02-04); Double used only for the progress-bar fraction via Double(truncating: NSDecimalNumber)"
  - "colorThreshold boundaries are inclusive: >= 1.0 overBudget, >= 0.8 warning, else normal"
  - "monthBoundaries uses Calendar.current with TimeZone.current (T-02-06) for correct local month edges; end = start + 1 month - 1 second"
  - "monthlySpend keys by PersistentIdentifier using expense.categories.first (v1 UI single-select; schema supports multiple); empty-category expenses flow to uncategorizedSpend"
  - "Refunds (negative amount) reduce category totals via additive reduce"
metrics:
  duration: "~2 sessions (interrupted by session limit; closed out by orchestrator)"
  completed: "2026-05-30"
  tasks: 2
  files: 3
---

# Phase 02 Plan 02: Budget-Math Layer Summary

**One-liner:** Pure value types `BudgetColor`, `BudgetProgressData`, and `BudgetCalculator` static helpers — per-category monthly spend aggregation, uncategorized bucket, and timezone-correct month boundaries — fully unit-tested without a ModelContainer.

## What Was Built

- **`BudgetColor`** — `Equatable` enum (`normal` / `warning` / `overBudget`) mapping budget consumption to a visual threshold (D2-09, EXP-08). Color is never the sole signal — always paired with ₹-remaining / % text downstream.
- **`BudgetProgressData`** — pure value type wrapping `category`, `spent`, and optional `budget`:
  - `remaining` = `budget - spent` (nil when no budget set).
  - `fractionUsed` = `spent / budget` as `Double` for bar rendering; nil-guarded on `budget > 0` (T-02-05).
  - `colorThreshold` — inclusive thresholds (≥1.0 overBudget, ≥0.8 warning, else normal).
- **`BudgetCalculator`** — static aggregation helpers operating on already-fetched arrays (no direct SwiftData fetching, decoupled from `@Query`):
  - `monthlySpend(for:categories:)` → `[PersistentIdentifier: Decimal]` per-category totals (EXP-09, D2-08).
  - `uncategorizedSpend(for:)` → `Decimal` sum of expenses with no category (D2-08).
  - `monthBoundaries(for:)` → inclusive `(start, end)` for a calendar month in the user's local timezone (P2-05, T-02-06).

## Verification

- `xcodebuild test -scheme MyHome -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing MyHomeTests/BudgetCalculatorTests` → **TEST SUCCEEDED**, all 10 tests pass (color thresholds incl. 80%/100% boundaries, nil/zero budget guards, month boundaries, per-category aggregation, uncategorized bucket).

## Execution Note

This plan was interrupted by a provider session limit after the RED commit (`7cb49e9`) while the GREEN implementation sat uncommitted in the working tree. The orchestrator closed it out via the safe-resume "close out manually" path: re-ran the acceptance test (green), committed the GREEN implementation (`745b868`), and wrote this SUMMARY. No work was redone or lost.

## Threat Mitigations

- **T-02-04** (precision loss): money math stays `Decimal`; `Double` only for the bar fraction.
- **T-02-05** (divide-by-zero): `fractionUsed` guards `budget > 0`.
- **T-02-06** (timezone month edges): `monthBoundaries` uses `Calendar.current` + `TimeZone.current`.

## Self-Check: PASSED
