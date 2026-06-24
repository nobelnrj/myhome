---
phase: 15-analytics-screen
plan: "02"
subsystem: analytics-ui
tags: [analytics, SwiftUI, Charts, AreaMark, neumorphic, navigation-push]
dependency_graph:
  requires: [SpendSummary, AnalyticsAggregator.summarize, SpendBucket, CategorySpendItem]
  provides: [AnalyticsView, AnalyticsTrendChart, AnalyticsCategoryBars, Overview-Analytics-push]
  affects: [15-03-delta-chips, phase-16-ai-card]
tech_stack:
  added: []
  patterns: [summarize-at-top-of-body, pre-aggregated-chart-data, track-backed-bars, navigationDestination-push]
key_files:
  created:
    - MyHomeApp/Features/Analytics/AnalyticsView.swift
    - MyHomeApp/Features/Analytics/AnalyticsTrendChart.swift
    - MyHomeApp/Features/Analytics/AnalyticsCategoryBars.swift
  modified:
    - MyHomeApp/Features/Overview/OverviewView.swift
    - MyHome.xcodeproj/project.pbxproj
decisions:
  - "summarize computed at the very top of AnalyticsView.body (outside any nested LazyVStack/Group) so SwiftUI dependency tracking re-computes on selectedRange change — no stale data (ANL-02 no-stale-data rule)"
  - "Hero numeral: .system(size: 34, weight: .bold, design: .default) — solid, not thin ultraLight-rounded (v1.2 hero-font preference)"
  - "AnalyticsCategoryBars shows ALL categories (no top-N truncation) to satisfy ANL-04 success criterion 4"
  - "Analytics push entry point: 'See analytics' CTA added to existing 'Over Time' sectionHeader — minimal-risk, reuses sectionHeader(_:action:) already used for Net Worth and Budgets"
  - "allGlobalExpenses (2-year-wide unfiltered query) passed to AnalyticsView so the aggregator can compute prior-period deltas (Pitfall 2)"
metrics:
  duration: ~25min
  completed: "2026-06-24"
  tasks: 3
  files: 5
---

# Phase 15 Plan 02: Analytics Screen UI Summary

AnalyticsView with Week/Month/Year range control, AreaMark trend chart, and track-backed category bars pushed from Overview via `.navigationDestination` (ANL-01/02/03/04).

## What Was Built

### Task 1 — AnalyticsView + AnalyticsTrendChart, registered in new G_ANL group (ANL-01/02/03)
**Commit:** `4df9dc6`

Created `MyHomeApp/Features/Analytics/AnalyticsView.swift` (86 lines):

- `struct AnalyticsView: View` accepting `expenses: [Expense]` and `categories: [Category]` from caller.
- `@State private var selectedRange: SpendRange = .month` with a `Picker("Range", selection: $selectedRange)` using `.pickerStyle(.segmented)` over `SpendRange.allCases` (ANL-02).
- `let summary = AnalyticsAggregator.summarize(...)` computed at the VERY TOP of `body` (no-stale-data rule — 15-RESEARCH line 459 / ANL-02).
- Headline card with `summary.totalSpend.formattedINRWords()` in `.system(size: 34, weight: .bold, design: .default)` + `.monospacedDigit()` inside `.neuSurface(.floating)`. NOT thin ultraLight-rounded (v1.2 hero-font rule).
- `AnalyticsTrendChart(buckets: summary.trendBuckets)` inside `.neuSurface(.raised)` — pre-aggregated buckets only (Pitfall A / T-15-05).

Created `MyHomeApp/Features/Analytics/AnalyticsTrendChart.swift` (94 lines):

- `struct AnalyticsTrendChart: View` accepting `let buckets: [SpendBucket]`.
- `AreaMark` + `LinearGradient` fill (accent.opacity(0.35) → accent.opacity(0.0)) + `LineMark` in `DesignTokens.accent`, `StrokeStyle(lineWidth: 2)`, `.interpolationMethod(.catmullRom)` (ANL-03).
- Y-axis labels via `Decimal(d).formattedINRCompact()` (axis-label-only Double→Decimal, Pitfall B acceptable).
- Empty/all-zero guard: calm "No spend data for this period." text instead of crash.
- Fixed `.frame(height: 200)` + `.neonGlow(DesignTokens.accent, ...)`.

pbxproj: created `G_ANL /* Analytics */` group with `path = Analytics` in G120 Features children; `FANL02`/`FANL03` PBXFileReference entries; `AANL02`/`AANL03` PBXBuildFile entries; both added to P001 app target Sources phase.

Build: `xcodebuild build` → **BUILD SUCCEEDED**, zero AnalyticsView/AnalyticsTrendChart errors.

### Task 2 — AnalyticsCategoryBars + mount into AnalyticsView (ANL-04)
**Commit:** `61d82f0`

Created `MyHomeApp/Features/Analytics/AnalyticsCategoryBars.swift` (97 lines):

- `struct AnalyticsCategoryBars: View` accepting `let items: [CategorySpendItem]` (already sorted descending by aggregator).
- Track-backed bar rows mirroring `SpendByCategoryChart`: category name, `item.spentDecimal.formattedINRWhole()` amount (Decimal — Pitfall B guard), `DesignTokens.fillRecessed2` track, per-category fill capsule with `neonGlow`.
- Shows ALL categories — no `prefix` or truncation (ANL-04 success criterion 4).
- Empty state: "No spend this range." for zero items.
- Does NOT redefine `CategorySpendItem` — reuses the type from `SpendByCategoryChart.swift`.

Mounted at insertion point in `AnalyticsView`: `AnalyticsCategoryBars(items: summary.categoryBreakdown).neuSurface(.raised)`.

pbxproj: `FANL04` ref, `AANL04` build file, `G_ANL` group child entry, P001 Sources entry.

Build: `xcodebuild build` → **BUILD SUCCEEDED**.

### Task 3 — Wire push navigation from Overview to Analytics (ANL-01)
**Commit:** `9be9a4d`

Modified `MyHomeApp/Features/Overview/OverviewView.swift`:

- Added `@State private var navigateToAnalytics = false` alongside `navigateToAssets` in `OverviewMonthContent`.
- Extended "Over Time" section header: `sectionHeader("Over Time", action: ("See analytics", { navigateToAnalytics = true }))`.
- Added `.navigationDestination(isPresented: $navigateToAnalytics) { AnalyticsView(expenses: allGlobalExpenses, categories: categories) }` alongside the `navigateToAssets` destination.
- Passes `allGlobalExpenses` (the existing 2-year-wide unfiltered `@Query`) so the aggregator can compute prior-period deltas (Pitfall 2).
- No new tab; tab bar unchanged (ANL-01).

Build: `xcodebuild build` → **BUILD SUCCEEDED**.

## Deviations from Plan

None — plan executed exactly as written.

## Known Stubs

None. `AnalyticsView` is fully wired to `AnalyticsAggregator.summarize` with real expense data from the caller. `AnalyticsTrendChart` renders real `SpendBucket` values. `AnalyticsCategoryBars` renders real `CategorySpendItem` values. The delta chip insertion point comment in Task 1 is explicitly a Phase 15-03 placeholder (noted in the plan itself, not a hidden stub).

## Threat Surface Scan

No new network endpoints, auth paths, file access, or schema changes. The Analytics push reuses the existing in-process `.navigationDestination` mechanism. `AnalyticsView` receives already-fetched SwiftData arrays — no new query surface.

T-15-04 mitigated: headline and category bars derive from `SpendSummary` (self-transfer-excluded in 15-01 aggregator).
T-15-05 mitigated: `AnalyticsTrendChart` and `AnalyticsCategoryBars` receive only pre-aggregated value types; no raw expenses enter Chart DSL.
T-15-06 mitigated: build gate confirmed G_ANL group (path=Analytics), all 4 per-file edits for each of the 3 new files — registration verified, not assumed.

## Self-Check: PASSED

| Item | Status |
|------|--------|
| `MyHomeApp/Features/Analytics/AnalyticsView.swift` | FOUND |
| `MyHomeApp/Features/Analytics/AnalyticsTrendChart.swift` | FOUND |
| `MyHomeApp/Features/Analytics/AnalyticsCategoryBars.swift` | FOUND |
| commit `4df9dc6` (Task 1 — AnalyticsView + AnalyticsTrendChart + G_ANL pbxproj) | FOUND |
| commit `61d82f0` (Task 2 — AnalyticsCategoryBars + mount + pbxproj) | FOUND |
| commit `9be9a4d` (Task 3 — Overview push navigation) | FOUND |
