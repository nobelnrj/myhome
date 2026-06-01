---
phase: "04-overview-charts"
plan: "05"
subsystem: "feature/overview"
tags: [dashboard, overview, tab-reorder, deep-link, quick-add, ovr-01, ovr-02, ovr-03, ovr-04, exp-10, exp-11]
dependency_graph:
  requires:
    - MyHomeApp/Features/Overview/SpendBudgetCard.swift
    - MyHomeApp/Features/Overview/TopCategoriesCard.swift
    - MyHomeApp/Features/Overview/PinnedNoteCard.swift
    - MyHomeApp/Features/Overview/SpendByCategoryChart.swift
    - MyHomeApp/Features/Overview/SpendOverTimeChart.swift
    - MyHomeApp/Support/OverviewAggregation.swift
    - MyHomeApp/Support/BudgetCalculator.swift
    - MyHomeApp/Features/Expenses/AddExpenseView.swift
    - MyHomeApp/RootView.swift
  provides:
    - MyHomeApp/Features/Overview/OverviewView.swift
    - MyHomeApp/RootView.swift (tab reorder + deep-link re-tag)
  affects:
    - MyHome.xcodeproj/project.pbxproj
tech_stack:
  added: []
  patterns:
    - BudgetsView/BudgetsMonthView child-re-init pattern for month-scoped @Query
    - Pre-aggregation in body before LazyVStack card pass-down (Pitfall A guard)
    - Integer selectedTab binding for cross-tab navigation (no URL parsing)
    - kOpenNoteNotification deep-link re-tagged from 2 → 3 (Pitfall D)
key_files:
  created:
    - MyHomeApp/Features/Overview/OverviewView.swift
  modified:
    - MyHomeApp/RootView.swift
    - MyHome.xcodeproj/project.pbxproj
decisions:
  - "OverviewView uses inner OverviewMonthContent child to own @Query (mirrors BudgetsMonthView pattern, RESEARCH OQ3)"
  - "Three @Query sources in child: monthExpenses (date-bounded), categories (sortOrder), allNotes (modifiedAt desc)"
  - "totalSpend includes BudgetCalculator.uncategorizedSpend per Open Question #1 answer"
  - "RootView tabs reordered Home(0)→Expenses(1)→Budgets(2)→Notes(3); @State selectedTab=0 value unchanged — meaning changes"
  - "Deep-link constant selectedTab=2 → selectedTab=3 (only reference site, Pitfall D T-04-09)"
  - "SpendByCategoryChart.swift and SpendOverTimeChart.swift added to pbxproj (were missing — Rule 3 fix during Task 2)"
metrics:
  duration: 35
  completed_date: "2026-06-01"
---

# Phase 4 Plan 5: Overview Dashboard Wiring + Tab Reorder Summary

OverviewView composes the five dashboard cards (SpendBudgetCard, TopCategoriesCard, PinnedNoteCard, SpendByCategoryChart, SpendOverTimeChart) in D4-03 order with quick-add sheet and pre-aggregated data; RootView reordered to Home(0)→Expenses(1)→Budgets(2)→Notes(3) with Notes deep-link re-tagged to 3; full 76-test suite green.

## What Was Built

### Task 1: OverviewView dashboard composition

**File:** `MyHomeApp/Features/Overview/OverviewView.swift` (new)

**Architecture:** Two-struct pattern mirrors BudgetsView/BudgetsMonthView.

`OverviewView` (public) holds:
- `@Binding var selectedTab: Int` and `@Binding var deepLinkNoteID: UUID?` (from RootView)
- `@State private var showAddExpense = false`
- Computes current-month `DateComponents` + `BudgetCalculator.monthBoundaries(for:)`
- Presents `OverviewMonthContent` child, NavigationStack with `.navigationTitle("Home")` `.inline`, toolbar `+` button, and `AddExpenseView` sheet

`OverviewMonthContent` (private) holds:
- `@Query(sort: \Category.sortOrder) private var categories: [Category]`
- `@Query private var monthExpenses: [Expense]` (date-bounded `#Predicate`, sort `.date` reverse — verbatim from BudgetsMonthView init)
- `@Query private var allNotes: [Note]` (sort `\Note.modifiedAt` reverse)

Pre-aggregation in `body` (before any card or chart receives data):
```swift
let spendByCategory = BudgetCalculator.monthlySpend(for: monthExpenses, categories: categories)
let totalBudget = categories.compactMap(\.monthlyBudget).reduce(.zero, +)
let totalSpend = spendByCategory.values.reduce(.zero, +)
    + BudgetCalculator.uncategorizedSpend(for: monthExpenses)   // incl. uncategorized (OQ#1)
let top3 = OverviewAggregation.topCategories(spendByCategory:categories:)
let pinnedNote = OverviewAggregation.pinnedOrChecklistNote(from: allNotes)
let categoryItems: [CategorySpendItem]  // Double, sorted desc
```

Layout: `ScrollView(.vertical)` → `LazyVStack(alignment: .leading, spacing: 16)` with `.padding(.horizontal, 16)` `.padding(.top, 8)` → five cards in D4-03 order.

### Task 2: RootView tab reorder + deep-link re-tag

**File:** `MyHomeApp/RootView.swift` (modified)

New 4-tab structure:
```swift
OverviewView(selectedTab: $selectedTab, deepLinkNoteID: $deepLinkNoteID)
    .tabItem { Label("Home", systemImage: "house") }
    .tag(0)

ExpenseListView()
    .tabItem { Label("Expenses", systemImage: "list.bullet") }
    .tag(1)

BudgetsView()
    .tabItem { Label("Budgets", systemImage: "chart.bar") }
    .tag(2)

NotesHomeView(deepLinkNoteID: $deepLinkNoteID, deepLinkBlockID: $deepLinkBlockID)
    .tabItem { Label("Notes", systemImage: "note.text") }
    .tag(3)
```

Deep-link re-tag (Pitfall D, T-04-09):
```swift
selectedTab = 3   // was 2; Notes is now tag 3
```

`@State private var selectedTab: Int = 0` unchanged — still 0, now means Overview.

---

## Build + Test Results

- Build: `xcodebuild build -scheme MyHome -destination 'platform=iOS Simulator,name=iPhone 17'` → BUILD SUCCEEDED
- Test suite: `xcodebuild test -scheme MyHome -destination 'platform=iOS Simulator,name=iPhone 17'` → 76 tests PASSED, 0 FAILED

### Manual Smoke (Task 3 — checkpoint:human-verify)

**Status: Awaiting human verification.**

The automated tasks are complete. The following items require manual verification on the iPhone 17 simulator:

1. App LANDS on "Home" tab (leftmost, `house` icon) — not Expenses
2. Tab order left→right: Home, Expenses, Budgets, Notes
3. Five cards top→bottom: This Month, Top Categories, Pinned Note, Spend by Category, Spend Over Time
4. Toolbar `+` → full Add Expense sheet appears; add expense → Overview updates
5. Spend Over Time: Week/Month/Year Picker recomputes line
6. Empty states render (no blank/broken charts)
7. Notes deep-link lands on Notes tab (tag 3), not Budgets

---

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] SpendByCategoryChart.swift and SpendOverTimeChart.swift missing from pbxproj**
- **Found during:** Task 2 (first build attempt after RootView edit failed with "cannot find 'OverviewView' in scope")
- **Issue:** `OverviewView.swift`, `SpendByCategoryChart.swift`, and `SpendOverTimeChart.swift` were all absent from `MyHome.xcodeproj/project.pbxproj` (PBXBuildFile, PBXFileReference, G124 group, and PBXSourcesBuildPhase). The Task 1 build had succeeded via build-cache artifacts; once RootView explicitly referenced `OverviewView`, the missing entry caused a "cannot find 'OverviewView' in scope" compile error.
- **Fix:** Added all three files to pbxproj (F409/F410/F411 file references, A409/A410/A411 build file entries, G124 group children, P001 sources build phase).
- **Files modified:** `MyHome.xcodeproj/project.pbxproj`
- **Commit:** 726abb7

---

## Known Stubs

None. OverviewView is fully wired to live @Query data via the OverviewMonthContent child. All five cards receive pre-computed value-type data. No placeholder text, hardcoded empty arrays, or wiring gaps.

---

## Threat Flags

None. No new network endpoints, auth paths, file access patterns, or schema changes. The single new write path (quick-add `+` → AddExpenseView sheet, OVR-04) reuses the existing already-validated Phase-1 entry UI verbatim — T-04-08 accepted. The Notes deep-link re-tag is a single integer constant change at one verified reference site — T-04-09 mitigated by manual-smoke step 8.

---

## Self-Check: PASSED

| Check | Result |
|-------|--------|
| `MyHomeApp/Features/Overview/OverviewView.swift` exists | FOUND |
| `grep -c "struct OverviewView"` = 1 | PASSED |
| All five card types referenced | PASSED |
| `grep -c "AddExpenseView()"` >= 1 | PASSED (1) |
| `grep -c ".sheet(isPresented:"` >= 1 | PASSED (1) |
| `grep -c 'navigationTitle("Home")'` = 1 | PASSED |
| `grep -c "uncategorizedSpend"` >= 1 | PASSED (1) |
| No `Chart(monthExpenses|categories|allNotes)` | PASSED (0) |
| `grep -c "import Charts"` = 0 | PASSED |
| `grep -c "selectedTab = 2" RootView.swift` = 0 | PASSED |
| `grep -c "selectedTab = 3" RootView.swift` = 1 | PASSED |
| `grep -c "OverviewView(" RootView.swift` = 1 | PASSED |
| commit 1ba77a9 exists (Task 1) | FOUND |
| commit 726abb7 exists (Task 2) | FOUND |
| Full test suite: 76 passed, 0 failed | CONFIRMED |
