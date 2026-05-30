---
phase: 02-categories-tags-budgets
plan: "05"
subsystem: features/budgets
tags: [budgets-view, tab-view, manage-categories, filtered-expense-list, swiftui, swiftdata]
dependency_graph:
  requires: [02-02, 02-03, 02-04]
  provides: [BudgetsView, ManageCategoriesView, FilteredExpenseListView, UncategorizedExpenseListView, RootView-TabView]
  affects: [RootView, BudgetsView, ManageCategoriesView, FilteredExpenseListView]
tech_stack:
  added: [BudgetsView (month pager + BudgetsMonthView child re-init pattern), ManageCategoriesView (CRUD + uniqueness), FilteredExpenseListView (date-only query + in-memory category filter), UncategorizedExpenseListView, RootView TabView shell]
  patterns: [child view re-init for dynamic @Query (RESEARCH OQ3), date-only @Query + in-memory category filter (RESEARCH OQ1/A3), lookup-before-insert uniqueness (T-02-12), CR-01 explicit save, confirmationDialog for destructive actions]
key_files:
  created:
    - MyHomeApp/Features/Budgets/ManageCategoriesView.swift
    - MyHomeApp/Features/Budgets/FilteredExpenseListView.swift
    - MyHomeApp/Features/Budgets/BudgetsView.swift
  modified:
    - MyHomeApp/RootView.swift
    - MyHome.xcodeproj/project.pbxproj
decisions:
  - "FilteredExpenseListView uses date-only @Query + in-memory category filter (RESEARCH OQ1/A3) to avoid relationship-contains predicate fragility in early SwiftData versions"
  - "UncategorizedExpenseListView is a separate struct (not a nil category case) since FilteredExpenseListView requires a non-optional Category instance"
  - "BudgetsMonthView child view re-initializes on start/end change to re-run @Query (RESEARCH OQ3 resolution)"
  - "ManageCategoriesView rename logic: tapping a row enters rename mode with inline TextField; saving checks case-insensitive uniqueness excluding self"
  - "ManageCategoriesView addCategory: fetches all categories and compares lowercased in-memory (#Predicate does not support .lowercased() — T-02-12 mitigation)"
metrics:
  duration: "<1 session"
  completed: "2026-05-30"
  tasks: 2
  files: 5
---

# Phase 02 Plan 05: Budgets Surface Assembly & TabView Shell Summary

**One-liner:** Complete Budgets surface wired as the second TabView tab — month pager with per-category budget cards (via BudgetsMonthView child re-init), tap-through filtered lists, inline category management (ManageCategoriesView), and the RootView TabView shell with Expenses + Budgets tabs.

## What Was Built

### Task 1: ManageCategoriesView + FilteredExpenseListView

- **`ManageCategoriesView`** — Category add/rename/delete sheet presented from BudgetsView toolbar.
  - Inline rename mode: tapping a row replaces it with a pre-filled TextField; "Done" or submit saves.
  - Add mode: tapping `+` reveals a new-row TextField at the bottom of the list.
  - Uniqueness enforcement: fetches all Categories in-memory and compares `.lowercased()` (since `#Predicate` does not support `String.lowercased()` — safe fallback per T-02-12).
  - Delete: `.onDelete` swipe → sets `categoryToDelete` → `confirmationDialog("Delete Category?")` before `context.delete()` + explicit `try context.save()` (CR-01, T-02-13).
  - `nameError` rendered inline (`.caption`, `.systemRed`) on both add and rename paths; view does not dismiss on error.

- **`FilteredExpenseListView`** — Read-only month+category expense tap-through.
  - Date-only `@Query` (start/end boundary) + in-memory `.filter { $0.categories.contains(where: { $0.persistentModelID == catID }) }` (RESEARCH OQ1/A3 — avoids relationship-contains predicate fragility).
  - Empty state: `ContentUnavailableView` with contextual copy.
  - No add/edit/delete — system back button only.

- **`UncategorizedExpenseListView`** — Companion view for the "Uncategorized" row tap-through (separate struct; same date-only query + in-memory filter for empty `.categories`).

- **`project.pbxproj`** — F130/A130 (`ManageCategoriesView`), F131/A131 (`FilteredExpenseListView`), F132/A132 (`BudgetsView`) registered in G122 Budgets group and P001 Sources build phase.

### Task 2: BudgetsView + RootView TabView

- **`BudgetsView`** — NavigationStack wrapping month pager + BudgetsMonthView child.
  - Month pager `HStack`: `<` (always enabled), month label (`.title2`, semibold), `>` (disabled + `.opacity(0.3)` at current month per D2-07/UI-SPEC).
  - `BudgetsMonthView` child re-initializes when `start`/`end` change, re-running its `@Query` (RESEARCH OQ3 resolution).
  - Toolbar "Manage Categories" button → `.sheet(isPresented:) { ManageCategoriesView() }`.

- **`BudgetsMonthView`** — Private child view owning month-scoped `@Query<Expense>` + `@Query<Category>`.
  - Per-category `BudgetCategoryCard` wrapped in `NavigationLink` → `FilteredExpenseListView(category:start:end:)`.
  - "Uncategorized" row at bottom when `uncategorizedTotal != 0` (D2-08) → `NavigationLink` → `UncategorizedExpenseListView(start:end:)`.
  - `BudgetCalculator.monthlySpend` + `uncategorizedSpend` compute in-memory aggregation.

- **`RootView`** — Replaced single-view pass-through with `TabView`:
  - Tab 1: `ExpenseListView()` + `Label("Expenses", systemImage: "list.bullet")`
  - Tab 2: `BudgetsView()` + `Label("Budgets", systemImage: "chart.bar")`
  - Each tab owns its own `NavigationStack` independently (D2-10).

## Verification

- Task 1: `xcodebuild test ... -only-testing MyHomeTests/CategoryCRUDTests` → **TEST SUCCEEDED** (all 4 tests pass).
- Task 2: `xcodebuild test -scheme MyHome -destination 'platform=iOS Simulator,name=iPhone 17'` → **TEST SUCCEEDED** (all 20+ tests pass).
- Task 3 (human checkpoint): **APPROVED** (2026-05-30) — visual verification on iPhone 17 simulator confirmed tab bar, month pager, Manage Categories CRUD + name uniqueness + delete dialog, color thresholds shifting at 80%/100% (always paired with text), category tap-through, and the Uncategorized row.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] FilteredExpenseListView: relationship-contains predicate avoided**
- **Found during:** Task 1 implementation
- **Issue:** RESEARCH OQ1 documents relationship-contains predicates as fragile in early SwiftData; plan says to use it with a documented fallback.
- **Fix:** Used date-only `@Query` + in-memory `.filter { ... .persistentModelID == catID }` from the start (the RESEARCH-recommended A3 fallback) rather than attempting the fragile predicate first.
- **Files modified:** `FilteredExpenseListView.swift`
- **Commit:** eaebd25

**2. [Rule 2 - Missing functionality] UncategorizedExpenseListView added as separate struct**
- **Found during:** Task 2 — BudgetsView needed a tap-through for uncategorized expenses, but `FilteredExpenseListView` requires a non-optional `Category` instance.
- **Fix:** Added `UncategorizedExpenseListView` as a separate struct in `FilteredExpenseListView.swift` with same date-only query + `categories.isEmpty` filter.
- **Files modified:** `FilteredExpenseListView.swift`
- **Commit:** eaebd25

**3. [Rule 1 - Bug] ManageCategoriesView uniqueness check: in-memory lowercased comparison**
- **Found during:** Task 1
- **Issue:** `#Predicate<Category>(predicate: #Predicate { ($0.name ?? "").lowercased() == lower })` would fail at runtime — `#Predicate` does not support calling `.lowercased()`.
- **Fix:** Fetched all categories with `FetchDescriptor<Category>()` and compared case-insensitively in-memory (noted in CategoryCRUDTests as the established uniqueness-check pattern per Pitfall P2-06).
- **Files modified:** `ManageCategoriesView.swift`
- **Commit:** eaebd25

## Threat Mitigations

- **T-02-12** (duplicate insert): Lookup-before-insert with in-memory case-insensitive comparison — no `@Attribute(.unique)`.
- **T-02-13** (accidental delete): `confirmationDialog("Delete Category?")` before delete; explicit `try context.save()` (CR-01).
- **T-02-14** (relationship predicate runtime failure): Used date-only `@Query` + in-memory filter for all filtered list views.
- **T-02-15** (category name display): Plain `Text()` everywhere — never `AttributedString(markdown:)`.

## Known Stubs

None — all components render live SwiftData-backed data.

## Threat Flags

None — no new network endpoints, auth paths, file access patterns, or schema changes introduced in this plan.

## Self-Check: PASSED

- `/Users/reo/My Projects/my-home/MyHomeApp/Features/Budgets/ManageCategoriesView.swift` — exists
- `/Users/reo/My Projects/my-home/MyHomeApp/Features/Budgets/FilteredExpenseListView.swift` — exists
- `/Users/reo/My Projects/my-home/MyHomeApp/Features/Budgets/BudgetsView.swift` — exists
- `/Users/reo/My Projects/my-home/MyHomeApp/RootView.swift` — contains `TabView`
- Commits: `eaebd25` (Task 1), `8c88c02` (Task 2) — both verified in git log
- Full test suite: TEST SUCCEEDED
