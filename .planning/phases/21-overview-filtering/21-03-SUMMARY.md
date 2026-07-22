---
phase: 21-overview-filtering
plan: 03
subsystem: overview-filter-ui
tags: [filter, overview, ovf-01, ovf-03, neumorphic, ui]
requires:
  - OverviewFilter (value type) — 21-01
  - OverviewFilterEngine.apply / rangeBoundaries — 21-01
  - OverviewView threads @State OverviewFilter (visibleExpenses, suppression) — 21-02
  - BudgetCalculator.grossSpend / grossIncome (transfer-excluding per-account glance numbers)
  - DesignTokens + NeuSurface (neumorphic surfaces, adaptive light/dark) — Phase 13/17
  - IconTile, Color(hex:), AccountsListView (Manage accounts destination)
provides:
  - OverviewFilterSheet (account multi-select + This Month/custom range, live @Binding edits)
  - OverviewScopePill (always-present header entry point AND active-state display, one-tap clear)
  - OverviewView header wiring (filter now a @Binding through OverviewMonthContent)
  - DEBUG screenshot hooks (-filterFirstAccount / -filterRangeDays / -openFilterSheet)
affects: []
tech-stack:
  added: []
  patterns:
    - single always-present header pill = entry point + active display (UI-REFERENCE Decision 3, replaces the planned separate chip bar)
    - sheet edits the parent @State via @Binding, so figures recompute live behind the sheet
    - per-account glance numbers routed through BudgetCalculator.grossSpend/grossIncome (same transfer-excluding path as the hero) so sheet totals reconcile with the readout
    - custom-range from<=to clamped in the sheet AND swapped in the engine (defence in depth, T-21-06)
key-files:
  created:
    - MyHomeApp/Features/Overview/OverviewFilterSheet.swift
    - MyHomeApp/Features/Overview/OverviewScopePill.swift
  modified:
    - MyHomeApp/Features/Overview/OverviewView.swift
    - MyHomeApp/MyHomeApp.swift
    - MyHome.xcodeproj/project.pbxproj
decisions:
  - "Single always-present header pill (not a filter button + separate chip): it is the entry point when inactive ('All accounts' + chevron) and names the active scope + shows the xmark clear when active — UI-REFERENCE Decision 3 overrides the plan prose's separate button/chip"
  - "Sheet subtitle shipped as 'Applies to your Overview' (not the mocked 'Applies across Home, Expenses & Budgets') — 21-02 suppresses Budgets under an active filter, so an app-wide claim would be false (UI-REFERENCE Decision 1)"
  - "OverviewMonthContent.filter changed from `let` to `@Binding` so the pill/sheet mutate the parent OverviewView @State; the OQ3 child-re-init-on-date-change mechanism is unaffected because the @State lives in the parent"
  - "Per-account row numbers use periodExpenses (the parent's date-scoped, account-UNfiltered monthExpenses) filtered by accountID and summed via BudgetCalculator.grossSpend/grossIncome — no second date-window fetch, and the sub-totals reconcile with the hero (HDFC 22,330 + ICICI 15,210 = 37,540)"
  - "Added DEBUG-only launch hooks (-filterFirstAccount/-filterRangeDays/-openFilterSheet) mirroring the existing -openAnalytics/-scrollTo pattern so filtered/range/sheet states are screenshot-verifiable without a tap-automation tool (Rule 3 — enabled required verification)"
metrics:
  duration: ~20 min
  completed: 2026-07-22
  tasks: 2
  files: 5
---

# Phase 21 Plan 03: Overview Filter UI Summary

Built the visible half of the phase: the `OverviewFilterSheet` (account multi-select +
This Month/custom date range) and the `OverviewScopePill` — a single always-present header
control that is both the filter entry point and the unmissable active-state display with a
one-tap clear. The account math and section-suppression from Plans 01/02 are now reachable and
their state is impossible to miss (OVF-01 selection UI, OVF-03 visibility + clear), styled
entirely with the existing neumorphic token system in both light and dark with zero DesignSystem
edits.

## What Was Built

- **`OverviewFilterSheet`** (`@Binding var filter`) — "Show data from" sheet, subtitle
  "Applies to your Overview". Owns a `@Query(!isArchived, sort: sortOrder)` for accounts and
  renders: a pinned accent-outlined **All accounts** row (checked when `!accountFilterActive`;
  tapping empties `accountIDs` + clears `includeUnassigned`), one **per-account** row (multi-select
  toggle of `id` in `accountIDs`, colored `IconTile` + name + "Credit ··42" + income when non-zero),
  and a last **Unassigned** row toggling `includeUnassigned`. A **Period** block switches
  This Month (`dateRange = nil`) vs Custom range (from/to day `DatePicker`s, `from<=to` clamped
  before assign). Edits apply **live** through the binding; **Reset** restores `OverviewFilter()`,
  **Done** dismisses; a "Manage accounts" `NavigationLink` reaches `AccountsListView`.
  `.presentationDetents([.medium, .large])`. Each row's amount comes from
  `BudgetCalculator.grossSpend/grossIncome` over the date-scoped `periodExpenses` — the same
  transfer-excluding path the hero uses, so the sub-totals reconcile with the readout.
- **`OverviewScopePill`** — a compact neu capsule trailing the "Overview" title, **always present**
  (UI-REFERENCE Decision 3, replacing the planned separate `OverviewFilterBar`). Inactive: neutral
  dot + "All accounts" + chevron, whole capsule opens the sheet. Active: accent dot + a summary
  label ("SAMPLE HDFC", "SAMPLE HDFC +1", "10 Jul – 12 Jul", or account · range) so filtered
  figures can never read as all-account totals (T-21-05), and a trailing `xmark.circle.fill`
  (44pt target, `accessibilityLabel("Clear filters")`) that clears in ONE tap without opening the
  sheet (OVF-03).
- **`OverviewView` wiring** — `OverviewMonthContent.filter` promoted from `let` to `@Binding`
  (parent passes `$filter`). The header VStack became an HStack with the pill; `onTap` opens the
  sheet, `onClear` sets `OverviewFilter()`. `selectedAccountNames` resolves the pill's label via
  the existing `allAccounts` @Query (no second fetch). The sheet is presented with
  `monthExpenses` as `periodExpenses`.
- **DEBUG seeder extension** (`MyHomeApp.swift`) — two SAMPLE accounts ("SAMPLE HDFC" #2563EB /
  "SAMPLE ICICI Credit" #C2410C, explicit sortOrder), seeded expenses attributed alternately, the
  income row left unassigned — so account filtering (and the Unassigned row) is visually
  verifiable. Idempotence guard retained.
- **DEBUG screenshot hooks** — `-filterFirstAccount`, `-filterRangeDays N`, `-openFilterSheet`
  added to the existing `-openAnalytics`/`-scrollTo` onAppear block so the filtered/range/sheet
  states render for self-verification without a tap-automation tool.

## Verification

- `xcodebuild build -scheme MyHome -destination 'iPhone 17'` → exit 0 (both new files compiled;
  pbxproj registered with all 4 edits each).
- `xcodebuild test -only-testing:MyHomeTests` → exit 0, 0 failures. Key suites executed:
  `OverviewFilterTests` (9), `DesignTokensTests` (5), `DarkBitIdentityTests` (72 — dark
  bit-identity intact).
- `git diff` across both task commits touches **no** `DesignSystem/` file (dark tokens untouched).
- Seeded-simulator screenshots (iPhone 17), dark AND light:
  - **Default** — pill reads "All accounts" (neutral dot), hero 73% / ₹14,000 in / ₹37,540 spent,
    Net Worth + Budgets present.
  - **Account-filtered (SAMPLE HDFC)** — pill shows accent dot + "SAMPLE HDFC" + xmark, hero 100% /
    ₹0 in / ₹22,330 spent, budget strip → no-budget state, Net Worth gone.
  - **Filter sheet** — "Show data from" / "Applies to your Overview"; All accounts accent-outlined
    + checked (₹37,540); HDFC (blue, Credit ··42, ₹22,330); ICICI (orange, Credit ··18, ₹15,210);
    Unassigned (₹0). Sub-totals reconcile: 22,330 + 15,210 = 37,540. Matches 21-REF-filter-sheet.png.
  - **Custom range (last 12 days)** — eyebrow AND pill both read "10 Jul – 22 Jul" (no stale month
    name), hero 70% / ₹14,000 in / ₹33,040 spent, Net Worth + Budgets + Over Time suppressed.
- OVF-03 clear: `onClear` sets `filter = OverviewFilter()`, which is exactly the default state in
  the "Default" screenshot — the post-clear Overview returns to the unfiltered figures with no
  leftover pill state.

## Deviations from Plan

### Auto-fixed / adopted decisions

**1. [Rule 3 - Blocking] Added DEBUG screenshot hooks to enable required verification**
- **Found during:** Task 2 (screenshot self-verification step).
- **Issue:** The plan requires seeded-simulator screenshots of the filtered / range-filtered /
  sheet states, but those require user taps and the environment has no tap-automation tool.
- **Fix:** Added `-filterFirstAccount`, `-filterRangeDays N`, `-openFilterSheet` to the existing
  DEBUG onAppear hook block (same pattern as `-openAnalytics`/`-scrollTo`). DEBUG-only; no release
  impact.
- **Files modified:** MyHomeApp/Features/Overview/OverviewView.swift
- **Commit:** 553a338

**2. [Adopted — UI-REFERENCE binding] Single always-present pill instead of button + separate chip**
- The plan prose (Task 2) described a separate `line.3.horizontal.decrease.circle` filter button
  plus an `OverviewScopePill` rendered only when active. UI-REFERENCE Decision 3 (BINDING,
  overrides plan prose) mandates a **single always-present** header pill that is both entry point
  and active display. Implemented per the reference; the pill still satisfies the plan's truths
  (names the selection when active, one-tap clear). Not a defect — the plan's `<read_first>`
  explicitly routes conflicts to the UI-REFERENCE Decisions section.

## Known Stubs

None — the sheet, pill, and per-account glance numbers are all wired to real data
(`@Query` accounts, `periodExpenses`, `BudgetCalculator`). No placeholder values.

## Self-Check: PASSED

- FOUND: MyHomeApp/Features/Overview/OverviewFilterSheet.swift
- FOUND: MyHomeApp/Features/Overview/OverviewScopePill.swift
- FOUND: MyHomeApp/Features/Overview/OverviewView.swift (modified)
- FOUND commit bf8beb9 (feat(21-03) OverviewFilterSheet + seeder)
- FOUND commit 553a338 (feat(21-03) OverviewScopePill + wiring)
