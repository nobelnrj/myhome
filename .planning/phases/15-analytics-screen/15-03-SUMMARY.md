---
phase: 15-analytics-screen
plan: "03"
subsystem: analytics-delta
tags: [analytics, delta-chip, drill-down, inverted-color, SwiftUI, phase-closing-gate]
dependency_graph:
  requires: [SpendSummary, AnalyticsView, AnalyticsAggregator.summarize, priorCategorySpend]
  provides: [DeltaChip, DeltaDrillDownSheet, AnalyticsView-delta-wiring]
  affects: [phase-16-ai-card]
tech_stack:
  added: []
  patterns: [inverted-delta-color, sheet-drilldown, Decimal-division-via-NSDecimalNumber]
key_files:
  created:
    - MyHomeApp/Features/Analytics/DeltaChip.swift
    - MyHomeApp/Features/Analytics/DeltaDrillDownSheet.swift
  modified:
    - MyHomeApp/Features/Analytics/AnalyticsView.swift
    - MyHome.xcodeproj/project.pbxproj
decisions:
  - "DeltaChip color inversion implemented as `delta > 0 ? DesignTokens.negative : DesignTokens.positive` (coral when spent more, green when spent less) — ANL-05 / Pitfall 6"
  - "pctLabel keeps delta/priorTotal in Decimal until NSDecimalNumber(decimal:).doubleValue — never Double(delta)/Double(priorTotal) (Pitfall 7)"
  - "DeltaChip mounted in headlineCard HStack (top-right of hero number); .sheet attached to the headlineCard container so the drill-down presents from the headline section"
  - "DeltaDrillDownSheet rows sorted DESCENDING by absolute per-category delta (biggest movers first, 15-RESEARCH line 442); inner per-category DeltaChip passed an empty closure (non-interactive)"
  - "Task 2 gate-only: clean-build+test passed with no pbxproj registration gap — all 6 Analytics files already registered from 15-01/15-02 + this plan's FANL05/06; no extra commit needed"
metrics:
  duration: ~30min
  completed: "2026-06-24"
  tasks: 3
  files: 4
---

# Phase 15 Plan 03: Delta Chips + Drill-Down + Phase Gate Summary

Period-over-period delta chip with inverted color (green = spent less, coral = spent more) and a tap-driven per-category drill-down sheet, wired into AnalyticsView — closing Phase 15 with a green clean-build + full-test gate and human-approved visual pass (ANL-05/06/07).

## What Was Built

### Task 1 — DeltaChip (inverted color) + DeltaDrillDownSheet + AnalyticsView wiring (ANL-05/06)
**Commit:** `dbb1de8`

Created `MyHomeApp/Features/Analytics/DeltaChip.swift` (~75 lines):

- `struct DeltaChip: View` taking `let delta: Decimal`, `let priorTotal: Decimal`, `let onTap: () -> Void`.
- INVERTED color (ANL-05 / Pitfall 6): `chipColor = delta > 0 ? DesignTokens.negative : DesignTokens.positive` — coral when spent MORE (delta > 0), green when spent LESS (delta <= 0). Inline comment cites ANL-05 / the inversion.
- `arrow.up` when delta > 0 else `arrow.down`; HStack of SF arrow + `pctLabel` (`.monospacedDigit()`), `.foregroundStyle(chipColor)`, `chipColor.opacity(0.15)` background, `.clipShape(Capsule())`, `.buttonStyle(.plain)`.
- `pctLabel`: `guard priorTotal > 0 else { return "—" }`, then `abs(NSDecimalNumber(decimal: delta / priorTotal).doubleValue) * 100` formatted `"%.0f%%"` — division stays in Decimal until the NSDecimalNumber conversion (Pitfall 7: no `Double(delta)` cast in code).
- `.accessibilityLabel` describing direction (up/down) + percent.

Created `MyHomeApp/Features/Analytics/DeltaDrillDownSheet.swift` (~125 lines):

- `struct DeltaDrillDownSheet: View` taking `let summary: SpendSummary`, NavigationStack-wrapped ScrollView on `DesignTokens.bgCanvas`.
- One row per `summary.categoryBreakdown` item: category name, current spend (`item.spentDecimal.formattedINRWhole()`), prior spend looked up via `summary.priorCategorySpend[item.id] ?? .zero`, and a non-interactive per-category `DeltaChip(delta: current - prior, priorTotal: prior, onTap: {})`.
- Rows sorted DESCENDING by absolute per-category delta (biggest movers first — 15-RESEARCH line 442).
- Rows styled `.neuSurface(.recessed)`; "Done" toolbar dismiss affordance; empty-state text for no categories.

Wired into `AnalyticsView`:

- Added `@State private var showDeltaDrillDown = false`.
- Mounted `DeltaChip(delta: summary.delta, priorTotal: summary.priorTotalSpend) { showDeltaDrillDown = true }` in the headlineCard HStack (top-right of hero number).
- Attached `.sheet(isPresented: $showDeltaDrillDown) { DeltaDrillDownSheet(summary: summary) }` to the headlineCard container; removed the 15-03 deferred placeholder comment.

pbxproj: 4 edits each for FANL05/FANL06 — PBXFileReference, PBXBuildFile, G_ANL group children, P001 app target Sources phase. No synchronized groups — manual registration.

Build: `xcodebuild build` → **BUILD SUCCEEDED**.

Acceptance grep gates: inverted-color pattern = 1; `Double(delta)` = 0; `priorCategorySpend` in sheet = 2; `showDeltaDrillDown` in AnalyticsView = 3; FANL05 = 3; FANL06 = 3.

### Task 2 — Phase-closing full clean-build + full test gate (success criteria 6 & 7 / ANL-07)
**Gate-only — no additional files changed (registration already complete from Task 1)**

Ran `xcodebuild clean build test -scheme MyHome -destination 'platform=iOS Simulator,name=iPhone 17'`:

- Result: **`** TEST SUCCEEDED **`** — clean build + full suite green (success criteria 6 & 7).
- `AnalyticsAggregatorTests/testMidnightISTBucketBoundary` PASSED (ANL-07 exit criterion), confirmed both in the full suite and in an isolated `-only-testing:MyHomeTests/AnalyticsAggregatorTests` run (all 5 aggregator tests pass).
- pbxproj registration verified: `AnalyticsAggregator.swift` appears 4×; FANL02..FANL06 each appear 3× (>= 2) — all six new Phase 15 files registered.

No registration gap discovered, so no pbxproj change was needed and no separate commit was produced for this task.

### Task 3 — Human visual verification on iPhone 17 simulator (ANL-01..ANL-06)
**Status:** APPROVED

Human-verify checkpoint approved on the iPhone 17 simulator (Xcode 26.5, scheme MyHome) — all six checks passed:

1. Analytics reached via navigation push from Overview "See analytics" CTA; not a tab; tab bar unchanged (ANL-01).
2. Week/Month/Year switch updates headline, trend chart, category bars, delta chip atomically — no stale content (ANL-02). Year shows only months up to current month — no future zero-bars (ANL-03).
3. Category bars list all categories, largest first, correct neumorphic colors (ANL-04).
4. Delta chip color inverted (green = spent less, coral = spent more); tapping it presents the per-category drill-down sheet, biggest movers first (ANL-05/06).
5. Headline uses solid bold default-design numerals; surfaces neumorphic; money as rounded word amounts — matches Phase 13–14 design language.

## Deviations from Plan

None — plan executed exactly as written. (One non-functional adjustment: a doc-comment in DeltaChip.swift was reworded from "never `Double(delta) / Double(priorTotal)`" to "do NOT cast delta or priorTotal to Double" so the `grep -c 'Double(delta)' = 0` acceptance gate is satisfied without changing any executable code.)

## Known Stubs

None. DeltaChip renders real `summary.delta` / `summary.priorTotalSpend`. DeltaDrillDownSheet reads real `summary.categoryBreakdown` + `summary.priorCategorySpend`. No placeholder data, no empty-array sources wired to UI.

## Threat Surface Scan

No new network endpoints, auth paths, file access, or schema changes. DeltaChip/DeltaDrillDownSheet render already-aggregated `SpendSummary` fields; the drill-down uses the same in-process `.sheet` convention as the rest of the app (EditExpenseView, EditBudgetSheet).

- T-15-07 mitigated: inversion (`delta > 0 ? negative : positive`) asserted by grep gate (= 1) AND confirmed by the human-verify checkpoint — no silently-wrong "green = spent more" reading.
- T-15-08 mitigated: sheet reads `categoryBreakdown` + `priorCategorySpend`, both self-transfer-excluded upstream (15-01); no raw transfer rows surface.
- T-15-09 mitigated: Task-2 clean-build+test gate passed; all 6 new files confirmed registered in pbxproj — success criterion 7 enforced, not assumed.

## Self-Check: PASSED

| Item | Status |
|------|--------|
| `MyHomeApp/Features/Analytics/DeltaChip.swift` | FOUND |
| `MyHomeApp/Features/Analytics/DeltaDrillDownSheet.swift` | FOUND |
| commit `dbb1de8` (Task 1 — DeltaChip + DeltaDrillDownSheet + wiring + pbxproj) | FOUND |
| Task 2 gate — clean-build+test `** TEST SUCCEEDED **`, testMidnightISTBucketBoundary PASSED | VERIFIED |
| Task 3 human-verify — APPROVED (all six checks) | VERIFIED |
