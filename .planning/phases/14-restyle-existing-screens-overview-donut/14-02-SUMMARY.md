---
phase: 14-restyle-existing-screens-overview-donut
plan: "02"
subsystem: overview-ui
tags: [restyle, neumorphic, donut-chart, net-cash-flow, ovr-05, ovr-06, skin-01, d-04, d-05]
dependency_graph:
  requires:
    - SpendDonutAggregation (plan 14-01 — OVR-05 math)
    - CategoryStyle rewrite (plan 14-01 — DesignTokens.cat* palette)
    - NeuSurface.swift (plan 13 — .neuSurface modifier)
    - DesignTokens.swift (plan 13 — bgCanvas, label*, positive, negative, accent, etc.)
  provides:
    - SpendDonutCard (OVR-05/06 — donut with tappable legend)
    - activityCategoryFilter binding (OVR-06 — tab-switch-to-filter navigation)
    - NET CASH FLOW hero (D-04 — income/spent split with RollingMoneyText)
    - Fully neumorphic Overview screen (SKIN-01 — zero stock system colors)
  affects:
    - Overview screen appearance (all cards now .neuSurface)
    - ExpenseListView (new deepLinkCategoryFilter binding for pre-filter)
    - SpendByCategoryChart + SpendOverTimeChart (restyled, now rendered on Overview per D-05)
tech_stack:
  added: []
  patterns:
    - DonutChart composition with center closure (21pt stat Text, not RollingMoneyText)
    - Tappable legend rows (Button with .accessibilityLabel)
    - OVR-06 deep-link via Binding<UUID?> threading (mirrors deepLinkNoteID pattern)
    - NET CASH FLOW income/spent split tiles (nested .neuSurface .recessed)
    - RollingMoneyText 46pt hero with positive/negative color
key_files:
  created:
    - MyHomeApp/Features/Overview/SpendDonutCard.swift
    - MyHomeTests/SpendDonutCardTests.swift
  modified:
    - MyHomeApp/Features/Overview/OverviewView.swift
    - MyHomeApp/Features/Overview/SpendBudgetCard.swift
    - MyHomeApp/Features/Overview/PinnedNoteCard.swift
    - MyHomeApp/Features/Overview/SpendByCategoryChart.swift
    - MyHomeApp/Features/Overview/SpendOverTimeChart.swift
    - MyHomeApp/Features/Overview/TopCategoriesCard.swift
    - MyHomeApp/RootView.swift
    - MyHomeApp/Features/Expenses/ExpenseListView.swift
    - MyHome.xcodeproj/project.pbxproj
decisions:
  - deepLinkCategoryFilter naming avoids collision with internal @State private var activeCategoryFilter (CategoryFilter enum)
  - Charts (SpendByCategoryChart + SpendOverTimeChart) added back to OverviewView per D-05 (they were removed in Phase 4/8 but the design contract requires them)
  - Income computed as sum of abs(expense.amount) where amount < 0 and isTransfer != true (existing convention)
  - SpendDonutCardTests test closure contract (not UIKit rendering) — no ViewInspector needed
metrics:
  duration_minutes: ~55
  completed_date: "2026-06-22"
  tasks_completed: 2
  files_changed: 9
---

# Phase 14 Plan 02: Overview Restyle + SpendDonutCard + NET CASH FLOW Summary

**One-liner:** Neumorphic Overview restyle with SpendDonutCard donut (OVR-05/06), NET CASH FLOW income/spent hero (D-04), retained+restyled legacy charts (D-05), and 5-test OVR-06 tap-callback suite.

## Tasks Completed

| Task | Name | Commit | Key Files |
|------|------|--------|-----------|
| 1 | SpendDonutCard + pbxproj + OVR-06 wiring | f830cfe | SpendDonutCard.swift, project.pbxproj, RootView.swift, ExpenseListView.swift |
| 2 | Overview restyle + NET CASH FLOW hero + SpendDonutCardTests | c96d747 | OverviewView.swift, SpendBudgetCard.swift, PinnedNoteCard.swift, SpendByCategoryChart.swift, SpendOverTimeChart.swift, TopCategoriesCard.swift, SpendDonutCardTests.swift |

## Verification Results

- `xcodebuild build -scheme MyHome -destination 'platform=iOS Simulator,name=iPhone 17 Pro'`: **BUILD SUCCEEDED**
- `xcodebuild test -only-testing:MyHomeTests/SpendDonutCardTests`: **5/5 PASSED**
- `grep -c 'SpendDonutCard.swift' project.pbxproj`: **4** (>= 2 required — PBXFileReference + PBXBuildFile + group + sources)
- `grep -c 'struct SpendDonutCard' SpendDonutCard.swift`: **1**
- `grep -c 'activityCategoryFilter' RootView.swift`: **3** (>= 2 required)
- `grep -c 'RollingMoneyText' SpendDonutCard.swift`: **0** (no 46pt hero in donut center)
- `grep -c '.clipped()' SpendDonutCard.swift`: **0** (shadow preserved)
- Stock system colors in Features/Overview/: **0**
- `.cardStyle(` in Features/Overview/: **0**
- `grep -c 'RollingMoneyText' SpendBudgetCard.swift`: **4** (>= 1 required)
- `grep -c 'WhereItsGoingCard' OverviewView.swift`: **0** (removed)
- `SpendByCategoryChart|SpendOverTimeChart` in OverviewView.swift: **present** (D-05 retained)

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 2 - Missing Functionality] deepLinkCategoryFilter renamed to avoid @State naming collision**
- **Found during:** Task 1
- **Issue:** ExpenseListView has `@State private var categoryFilter: CategoryFilter = .all` (enum type) and the plan's binding param is also named `categoryFilter` (UUID? type) — Swift naming collision.
- **Fix:** Renamed the binding parameter to `deepLinkCategoryFilter` (UUID?) and the internal state to `activeCategoryFilter` (CategoryFilter enum). Callers use `deepLinkCategoryFilter:` label.
- **Files modified:** ExpenseListView.swift, RootView.swift
- **Commit:** f830cfe

**2. [Rule 2 - Missing Functionality] SpendByCategoryChart + SpendOverTimeChart added to OverviewView**
- **Found during:** Task 2 acceptance criteria check
- **Issue:** D-05 acceptance criterion requires these charts in OverviewView.swift, but they were removed in Phase 4/8 ("the user chose to match the design exactly"). The plan says "KEEP" them on Overview.
- **Fix:** Added both charts to OverviewMonthContent body with section headers ("By Category", "Over Time"), using existing `rankedSpend`/`allGlobalExpenses` data already in scope.
- **Files modified:** OverviewView.swift
- **Commit:** c96d747

**3. [Rule 2 - Missing Critical] Income computation added to OverviewMonthContent**
- **Found during:** Task 2 SpendBudgetCard rewrite
- **Issue:** NET CASH FLOW hero requires `income: Decimal` but OverviewView only computed `totalSpend`. No income aggregation existed.
- **Fix:** Added `totalIncome` computed as sum of `abs(amount)` for negative-amount, non-transfer expenses in `monthExpenses`.
- **Files modified:** OverviewView.swift
- **Commit:** c96d747

## Known Stubs

None. All deliverables are fully wired:
- SpendDonutCard renders real data from SpendDonutAggregation (via OverviewView rankedSpend)
- NET CASH FLOW hero reads real income/spent from monthExpenses
- OVR-06 binding chain: SpendDonutCard.onCategoryTap → activityCategoryFilter → ExpenseListView.activeCategoryFilter

## Threat Flags

None. This plan introduced no new network endpoints, auth paths, file access patterns, or schema changes.

T-14-03 (donut center total): mitigated — totalSpend is from BudgetCalculator.monthlySpend (self-transfer-excluded).
T-14-04 (OVR-06 binding): mitigated — activityCategoryFilter is @State only (not URL/notification driven); deepLinkCategoryFilter cleared after consumption.
T-14-05 (pbxproj registration): mitigated — clean build succeeds, proving registration is complete.

## Self-Check: PASSED

- [x] MyHomeApp/Features/Overview/SpendDonutCard.swift — exists (created, 145 lines)
- [x] MyHomeTests/SpendDonutCardTests.swift — exists (created, 5 tests green)
- [x] MyHomeApp/Features/Overview/OverviewView.swift — modified (activityCategoryFilter threaded, SpendDonutCard call, charts added)
- [x] MyHomeApp/Features/Overview/SpendBudgetCard.swift — modified (NET CASH FLOW layout, .neuSurface(.floating))
- [x] MyHomeApp/Features/Overview/PinnedNoteCard.swift — modified (.neuSurface(.raised, isInteractive: true))
- [x] MyHomeApp/Features/Overview/SpendByCategoryChart.swift — modified (.neuSurface(.raised), token colors)
- [x] MyHomeApp/Features/Overview/SpendOverTimeChart.swift — modified (.neuSurface(.raised), token colors)
- [x] MyHomeApp/Features/Overview/TopCategoriesCard.swift — modified (.neuSurface(.raised), label tokens)
- [x] MyHomeApp/RootView.swift — modified (activityCategoryFilter @State, OverviewView + ExpenseListView calls)
- [x] MyHomeApp/Features/Expenses/ExpenseListView.swift — modified (deepLinkCategoryFilter binding, activeCategoryFilter @State)
- [x] MyHome.xcodeproj/project.pbxproj — modified (6 edits for SpendDonutCard + SpendDonutCardTests)
- [x] Commits f830cfe, c96d747 — confirmed in git log
