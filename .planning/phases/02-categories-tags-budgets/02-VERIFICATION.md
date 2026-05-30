---
phase: 02-categories-tags-budgets
verified: 2026-05-30T06:20:00Z
status: human_needed
score: 6/6 requirements verified
overrides_applied: 0
human_verification:
  - test: "Confirm color-threshold visual rendering"
    expected: "Progress bar shifts from accent to orange at ≥80% spend, to red at ≥100%; ₹-remaining text co-signals each state (color never the sole signal)"
    why_human: "BudgetProgressView color logic is correct in code and tests cover threshold math, but pixel-accurate color rendering against device-calibrated display can only be confirmed in the simulator"
  - test: "Confirm month-pager feel and '>' disabled state"
    expected: "Tapping '<' pages back; '>' is visually dimmed and unresponsive at current month"
    why_human: "UI interaction and visual disabled-state feedback cannot be asserted by grep or unit tests"
  - test: "Confirm tap-through to filtered list"
    expected: "Tapping a BudgetCategoryCard pushes FilteredExpenseListView showing only that category's expenses for the viewed month; system back button returns to Budgets"
    why_human: "NavigationLink push behavior requires runtime rendering"
  - test: "Confirm Uncategorized row appears only when present"
    expected: "Adding an expense with no category causes an 'Uncategorized' row to appear at the bottom of the Budgets list; it taps through to UncategorizedExpenseListView"
    why_human: "Conditional row appearance and tap-through require live data"
---

# Phase 2: Categories, Tags & Budgets — Verification Report

**Phase Goal:** A user can categorize and tag expenses, set per-category monthly budgets, and watch budget progress — making the manual tracker usable end-to-end with no backend.
**Verified:** 2026-05-30T06:20:00Z
**Status:** human_needed
**Re-verification:** No — initial verification
**Test suite:** 27/27 tests PASS (full `xcodebuild test` run — confirmed)

---

## Goal Achievement

### Observable Truths (Success Criteria)

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | App ships with India-tuned predefined category list; user can add, rename, delete custom categories | VERIFIED | `ModelContainer+App.swift:71–95` seeds exactly 14 categories (Groceries … Misc) on first launch; `ManageCategoriesView.swift` implements add/rename/delete with duplicate-check and confirmationDialog. `CategorySeedTests` (2 tests), `CategoryCRUDTests` (4 tests) — all green. |
| 2 | User can attach one tag (category) to an expense; schema supports multiple for future UI | VERIFIED | `SchemaV2.Expense.categories: [SchemaV2.Category]` (to-many); `AddExpenseView` + `EditExpenseView` wire single-select via `CategoryPickerView`; `expense.categories = selectedCategory.map { [$0] } ?? []`. `ExpenseCategoryTests` (2 tests) — green. |
| 3 | User can set a monthly budget per category and see ₹-remaining + % progress bar with color shift at 80% and 100% | VERIFIED (automated math) / HUMAN (visual rendering) | `Category.monthlyBudget: Decimal?` in `SchemaV2`. `BudgetProgressData.colorThreshold` shifts at f≥0.8 → .warning, f≥1.0 → .overBudget. `BudgetProgressView` renders correct text ("X remaining" / "X over budget") with no double-₹ (CR-01 fixed). `BudgetCalculatorTests` covers: normal/warning/overBudget/exactly80/exactly100/noBudget/zeroBudgetGuard. `BudgetModelTests` (2 tests) — green. |
| 4 | User can view the current month's expenses grouped by category and tap through to the transaction list | VERIFIED (structural) / HUMAN (interaction) | `BudgetsView.swift` + `BudgetsMonthView` renders per-category `BudgetCategoryCard` rows sorted by `sortOrder`, each wrapped in a `NavigationLink` to `FilteredExpenseListView`. Uncategorized row appears when `uncategorizedTotal != 0`. |

**Score:** 6/6 requirements verified (all automation-testable paths green; 4 human checks remain for visual/interaction behavior)

---

## Requirement-by-Requirement Verdict

### EXP-04 — India-tuned predefined category list seeds on first launch

**PASS**

Evidence:
- `ModelContainer+App.swift:71–95` — `seedCategoriesIfNeeded` inserts exactly 14 categories with correct names, SF Symbol names, and `sortOrder` 0–13. Guard is `fetchLimit = 1` empty-check → idempotent.
- `CategorySeedTests/seedsOnEmptyStore` — expects `count == 14`. GREEN.
- `CategorySeedTests/seedIsIdempotent` — calls seed twice, expects `count == 14`. GREEN.
- `SchemaV2.swift` — no `@Attribute(.unique)` anywhere; uniqueness enforced by lookup-before-insert.

### EXP-05 — User can add, rename, and delete custom categories

**PASS**

Evidence:
- `ManageCategoriesView.swift`:
  - **Add**: `addCategory(name:)` trims, rejects empty, fetches all categories in-memory for case-insensitive duplicate check, inserts with `sortOrder = max + 1` (WR-04 fixed), then `try context.save()`.
  - **Rename**: `saveRename(for:)` runs same uniqueness check excluding self, mutates `category.name`, saves.
  - **Delete**: `deleteCategory(_:)` calls `context.delete(category)` + `try context.save()`. `.nullify` delete rule clears `expense.categories` links.
  - Inline error display in `.systemRed` for empty name and duplicate.
- `CategoryCRUDTests/addCategory`, `renameCategory`, `deleteNullifiesExpenseLink`, `uniquenessByFetch` — all GREEN.

### EXP-06 — User can attach one tag to an expense; schema supports multiple for future UI

**PASS**

Note: The REQUIREMENTS.md uses the word "tag" for what is implemented as a "category" relationship. This is consistent with the roadmap intent — the phase is explicitly named "Categories, Tags & Budgets" and the PLAN frontmatter maps EXP-06 to the category picker. The schema is multi-tag-ready (`categories: [Category]`); the v1 UI is single-select.

Evidence:
- `SchemaV2.Expense.categories: [SchemaV2.Category] = []` — to-many, default empty.
- `CategoryPickerView.swift` — `@Binding var selectedCategory: Category?`; "None" row + optional "Clear" toolbar button.
- `AddExpenseView.swift:230` — `expense.categories = selectedCategory.map { [$0] } ?? []` on save.
- `EditExpenseView.swift:274` — `selectedCategory = expense.categories.first` on appear; `expense.categories = selectedCategory.map { [$0] } ?? []` on save. `isDirty` includes category change.
- `ExpenseCategoryTests/assignCategory`, `clearCategory` — GREEN.
- Uncategorized add flow remains valid — leaving category as "None" produces `categories = []`, no taps added to the ≤4-tap path (EXP-01 preserved).

### EXP-07 — User can set a monthly budget per category

**PASS**

Evidence:
- `SchemaV2.Category.monthlyBudget: Decimal? = nil` — stored as Decimal (not Double), CloudKit-ready.
- `EditBudgetSheet.swift` — `@Bindable var category: Category`; keypad entry; `saveBudget()` guards `amount > 0` and `abs(amount) < 1e9`; sets `category.monthlyBudget = amount`; `try context.save()`. Remove path: `confirmationDialog` + `category.monthlyBudget = nil` + `try context.save()` + `dismiss()`.
- `BudgetCategoryCard` presents `EditBudgetSheet` via pencil button on each card.
- `BudgetModelTests/budgetStoreAndRetrieve` — Decimal(15000) round-trips as Decimal. GREEN.
- `BudgetModelTests/nilBudgetRoundTrip` — nil round-trips as nil. GREEN.

### EXP-08 — Per-category budget progress: ₹-remaining + % bar, color shift at 80% and 100%

**PASS (automated math) / HUMAN NEEDED (visual)**

Evidence:
- `BudgetCalculator.swift`:
  - `BudgetProgressData.remaining = budget - spent` (nil when no budget).
  - `BudgetProgressData.fractionUsed = spent / budget` as Double via NSDecimalNumber (zero-guard).
  - `BudgetProgressData.colorThreshold`: `f >= 1.0 → .overBudget`, `f >= 0.8 → .warning`, else `.normal`.
- `BudgetProgressView.swift`:
  - Progress bar: `min(CGFloat(fraction), 1.0) * geo.size.width` — capped at 100%.
  - Labels: `"\(remaining.formattedINR()) remaining"` / `"\((-remaining).formattedINR()) over budget"` — no double ₹ (CR-01 fixed in 3c31ca2).
  - `100%+` label at ≥1.0; `"\(Int(fraction * 100))% used"` otherwise.
  - Color follows `fillColor` mapped from `BudgetColor`.
- `BudgetCalculatorTests`: normal/warning/overBudget/exactly80/exactly100/noBudget/zeroBudgetGuard — all GREEN.

Human check required: pixel-accurate color rendering at 80% and 100% boundaries in the simulator (approved by human in plan 02-05 checkpoint — recorded in phase facts).

### EXP-09 — Month view shows expenses grouped by category with tap-through

**PASS (structural) / HUMAN NEEDED (interaction)**

Evidence:
- `BudgetsView.swift` — month pager with `<` / `>` buttons; `>` disabled when `isAtCurrentMonth`.
- `BudgetsMonthView` — child struct re-initialized on month boundary change (OQ3 pattern); owns `@Query<Expense>` filtered by `[start, end]`; computes `spendByCategory` and `uncategorizedTotal` via `BudgetCalculator`.
- `ForEach(categories) { category in NavigationLink { FilteredExpenseListView(...) } label: { BudgetCategoryCard(...) } }` — sorted by `sortOrder`.
- Uncategorized row: `if uncategorizedTotal != 0 { NavigationLink { UncategorizedExpenseListView(...) } }`.
- `FilteredExpenseListView.swift` — date-range `@Query` + in-memory filter by `persistentModelID`; empty state via `ContentUnavailableView`; read-only.
- `UncategorizedExpenseListView.swift` — analogous for uncategorized expenses.
- Tap-through and month-paging interaction approved by human in plan 02-05 checkpoint — recorded in phase facts.

---

## Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `MyHomeApp/Persistence/Schema/SchemaV2.swift` | SchemaV2 + Category @Model + Expense with categories relationship | VERIFIED | 94 lines; `enum SchemaV2: VersionedSchema`; `@Model Category` with `monthlyBudget: Decimal?`; `@Model Expense` with `@Relationship(deleteRule: .nullify, inverse: \SchemaV2.Category.expenses) var categories` |
| `MyHomeApp/Persistence/Models/Category.swift` | typealias Category = SchemaV2.Category | VERIFIED | Present in codebase |
| `MyHomeApp/Persistence/ModelContainer+App.swift` | SchemaV2 schema + seedCategoriesIfNeeded | VERIFIED | `Schema(versionedSchema: SchemaV2.self)`; `try seedCategoriesIfNeeded(context: container.mainContext)` before return; WR-01 force-unwrap fixed (guard + CocoaError) |
| `MyHomeApp/Support/BudgetCalculator.swift` | BudgetProgressData + BudgetColor + BudgetCalculator | VERIFIED | 116 lines; all three types fully implemented |
| `MyHomeApp/Features/Expenses/CategoryPickerView.swift` | Reusable category picker sheet | VERIFIED | 99 lines; None row + checkmark + optional Clear; `@Query(sort: \Category.sortOrder)` |
| `MyHomeApp/Features/Expenses/AddExpenseView.swift` | Category row in Section 2 + wiring on save | VERIFIED | `selectedCategory: Category?` state; `expense.categories = selectedCategory.map { [$0] } ?? []` |
| `MyHomeApp/Features/Expenses/EditExpenseView.swift` | Pre-filled category + isDirty + save wiring | VERIFIED | `selectedCategory = expense.categories.first` on appear; category in `isDirty` |
| `MyHomeApp/Features/Budgets/BudgetProgressView.swift` | Progress bar + ₹-remaining + % text + color | VERIFIED | CR-01 fixed: no double ₹; correct threshold text |
| `MyHomeApp/Features/Budgets/BudgetCategoryCard.swift` | Card composing icon + name + spend + EditBudgetSheet | VERIFIED | Pencil button presents `EditBudgetSheet` |
| `MyHomeApp/Features/Budgets/EditBudgetSheet.swift` | Budget set/remove sheet | VERIFIED | `saveBudget()` + `removeBudget` confirmationDialog both have explicit `try context.save()` |
| `MyHomeApp/Features/Budgets/BudgetsView.swift` | Month pager + BudgetsMonthView child | VERIFIED | Month pager with disabled > at current month; child re-init pattern |
| `MyHomeApp/Features/Budgets/FilteredExpenseListView.swift` | Filtered tap-through list | VERIFIED | In-memory fallback (OQ1/A3); `UncategorizedExpenseListView` also present |
| `MyHomeApp/Features/Budgets/ManageCategoriesView.swift` | Category CRUD sheet | VERIFIED | Add/rename/delete; inline errors; WR-04 sortOrder fixed (`max + 1`) |
| `MyHomeApp/RootView.swift` | TabView with Expenses + Budgets tabs | VERIFIED | `TabView { ExpenseListView() ... BudgetsView() ... }` |

---

## Key Link Verification

| From | To | Via | Status | Details |
|------|----|-----|--------|---------|
| `Expense.swift` | `SchemaV2.Expense` | typealias | WIRED | `typealias Expense = SchemaV2.Expense` |
| `Category.swift` | `SchemaV2.Category` | typealias | WIRED | `typealias Category = SchemaV2.Category` |
| `MigrationPlan.swift` | SchemaV2 | `MigrationStage.custom` V1→V2 | WIRED | `schemas = [SchemaV1.self, SchemaV2.self]`; `stages = [v1ToV2]` with nil closures |
| `ModelContainer+App.swift` | `seedCategoriesIfNeeded` | post-container call | WIRED | `try seedCategoriesIfNeeded(context: container.mainContext)` before return |
| `AddExpenseView.saveExpense` | `expense.categories` | selectedCategory wiring | WIRED | `expense.categories = selectedCategory.map { [$0] } ?? []` |
| `CategoryPickerView` | `@Query(sort: \Category.sortOrder)` | SwiftData query | WIRED | `@Query(sort: \Category.sortOrder) private var categories` |
| `RootView` | `BudgetsView()` | TabView tabItem | WIRED | `BudgetsView().tabItem { Label("Budgets", ...) }` |
| `BudgetsView` | `BudgetCalculator.monthlySpend / monthBoundaries` | month-scoped aggregation | WIRED | `BudgetsMonthView` calls both |
| `BudgetsView card tap` | `FilteredExpenseListView` | `NavigationLink` | WIRED | `NavigationLink { FilteredExpenseListView(category:start:end:) }` |
| `ManageCategoriesView.addCategory` | `FetchDescriptor<Category>` lookup | case-insensitive in-memory check | WIRED | `context.fetch(FetchDescriptor<Category>())` then `.lowercased()` compare |

---

## Data-Flow Trace (Level 4)

| Artifact | Data Variable | Source | Produces Real Data | Status |
|----------|---------------|--------|--------------------|--------|
| `BudgetsMonthView` | `monthExpenses` | `@Query` filter by date range | Yes — live SwiftData query | FLOWING |
| `BudgetsMonthView` | `categories` | `@Query(sort: \Category.sortOrder)` | Yes — seeded + user-added categories | FLOWING |
| `BudgetsMonthView` | `spendByCategory` | `BudgetCalculator.monthlySpend(for:categories:)` | Yes — in-memory reduce over real query results | FLOWING |
| `BudgetsMonthView` | `uncategorizedTotal` | `BudgetCalculator.uncategorizedSpend(for:)` | Yes — filters `categories.isEmpty` from real query | FLOWING |
| `FilteredExpenseListView` | `expenses` | `@Query` + in-memory `persistentModelID` filter | Yes — real query + filter | FLOWING |
| `BudgetProgressView` | `data.remaining`, `data.fractionUsed` | `BudgetProgressData` computed from `spent` + `category.monthlyBudget` | Yes — real Decimal values from SwiftData model | FLOWING |

---

## Behavioral Spot-Checks

| Behavior | Check | Result | Status |
|----------|-------|--------|--------|
| Full test suite | `xcodebuild test -scheme MyHome -destination 'platform=iOS Simulator,name=iPhone 17'` | 27/27 PASS, exit 0 | PASS |
| 14 categories seed | `CategorySeedTests/seedsOnEmptyStore` | count == 14 | PASS |
| Seed is idempotent | `CategorySeedTests/seedIsIdempotent` | count == 14 after 2 calls | PASS |
| Color at 80% is .warning | `BudgetCalculatorTests/exactly80` | .warning | PASS |
| Color at 100% is .overBudget | `BudgetCalculatorTests/exactly100` | .overBudget | PASS |
| Zero-budget guard (no divide-by-zero) | `BudgetCalculatorTests/zeroBudgetGuard` | fractionUsed == nil | PASS |
| Uncategorized bucket | `BudgetCalculatorTests/uncategorizedBucket` | uncategorizedTotal == 150, excluded from category totals | PASS |
| Delete category nullifies expense link | `CategoryCRUDTests/deleteNullifiesExpenseLink` | `expense.categories.isEmpty == true` | PASS |
| V1 store migrates cleanly | `MigrationTests/v1StoreMigratesCleanly` | seed expense readable post-migration | PASS |
| No double ₹ symbol | `grep "₹\\\(.*formattedINR" BudgetProgressView.swift` | 0 matches (CR-01 fixed) | PASS |

---

## Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|-------------|------------|-------------|--------|----------|
| EXP-04 | 02-01 | India-tuned predefined category list | SATISFIED | 14 categories seeded; CategorySeedTests green |
| EXP-05 | 02-01, 02-05 | Add, rename, delete custom categories | SATISFIED | ManageCategoriesView + CategoryCRUDTests |
| EXP-06 | 02-03 | Attach one category to expense (multi ready) | SATISFIED | CategoryPickerView + wiring in Add/Edit + ExpenseCategoryTests |
| EXP-07 | 02-01, 02-04 | Set monthly budget per category | SATISFIED | EditBudgetSheet + BudgetModelTests |
| EXP-08 | 02-02, 02-04 | ₹-remaining + % bar + color shift at 80% / 100% | SATISFIED (math) / HUMAN (visual) | BudgetProgressData + BudgetProgressView + BudgetCalculatorTests |
| EXP-09 | 02-02, 02-05 | Month view grouped by category + tap-through | SATISFIED (structural) / HUMAN (interaction) | BudgetsView + FilteredExpenseListView + human checkpoint approved |

---

## Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
|------|------|---------|----------|--------|
| `EditBudgetSheet.swift:155` | — | `String(describing: existing)` for Decimal keypad init | INFO (IN-02 from REVIEW) | Low risk — budget values entered via DecimalKeypadView produce clean strings. Not a blocker. |
| `BudgetsView.swift:38` | — | No `else` branch when `monthBoundaries` returns nil | INFO (IN-03 from REVIEW) | Blank screen on malformed `viewedMonth` — cannot happen with current code; no user-visible risk. |
| `ManageCategoriesView.swift:36` | — | `onDelete` uses `offsets.first` only | INFO (IN-04 from REVIEW) | Safe for swipe-to-delete; no multi-delete affordance exists. |
| `BudgetCalculatorTests.swift` | — | No test for negative-spend (refund-heavy month) | INFO (IN-01 from REVIEW) | Visual bar floor at 0 is correct; no crash; test gap only. |

No TBD, FIXME, or XXX markers found in any Phase 2 files.

All 4 WARNING-level findings from code review (WR-01..04) were resolved in commit 3c31ca2:
- WR-01: force-unwrap on `FileManager.urls` replaced with `guard let` + `CocoaError`.
- WR-02: `deleteCategory` no longer calls `dismiss()` on error; `EditBudgetSheet` `removeBudget` only dismisses on success.
- WR-03: `formattedAsMonthYear()` uses `setLocalizedDateFormatFromTemplate("MMMMyyyy")`.
- WR-04: `addCategory` uses `max(sortOrder) + 1` instead of `categories.count`.

---

## Human Verification Required

Human checkpoints for plans 02-03 and 02-05 were both **approved** by the developer in the simulator (phase facts). The items below are re-stated for the record as formally verified.

### 1. Progress Bar Color Thresholds

**Test:** Run app on iPhone 17 simulator; set a ₹1,000 budget on Groceries; add expenses to reach ~79%, ~85%, ~105%.
**Expected:** Bar is accent color below 80%; shifts to orange at ≥80%; shifts to red at ≥100%. ₹-remaining text co-signals each state.
**Why human:** Pixel-accurate SwiftUI color rendering against device display requires runtime.
**Prior approval:** Plan 02-05 checkpoint — APPROVED.

### 2. Month Pager Navigation

**Test:** Open Budgets tab; confirm month header shows current month; tap `<`; tap `>` to return; confirm `>` is dimmed/unresponsive at current month.
**Expected:** Month label updates; `>` visually disabled at current month with `.opacity(0.3)`.
**Why human:** SwiftUI button disabled-state visual appearance requires runtime.
**Prior approval:** Plan 02-05 checkpoint — APPROVED.

### 3. Tap-Through to Filtered Expense List

**Test:** Tap a BudgetCategoryCard; confirm filtered list title matches category name; confirm only that month's expenses for that category are shown; back out.
**Expected:** Correct title, correct filtering, read-only (no add/edit affordances).
**Why human:** NavigationLink push and back-button behavior require runtime.
**Prior approval:** Plan 02-05 checkpoint — APPROVED.

### 4. Uncategorized Row Appearance and Tap-Through

**Test:** Add an expense with no category in the viewed month; confirm "Uncategorized" row appears at the bottom; tap through to `UncategorizedExpenseListView`.
**Expected:** Row appears when any uncategorized expense exists; correct total shown; tap shows uncategorized expenses only.
**Why human:** Conditional row and tap-through require live data and runtime rendering.
**Prior approval:** Plan 02-05 checkpoint — APPROVED.

---

## Gaps Summary

No automated-test gaps blocking the goal. All 6 requirements are satisfied at the code level. The 4 human verification items above were all approved by the developer during plan execution checkpoints. The phase goal — "A user can categorize and tag expenses, set per-category monthly budgets, and watch budget progress" — is fully achieved in the codebase.

The `status: human_needed` reflects the mandatory classification for any phase with remaining human verification items, even when all items carry prior approval. The developer may treat this as **effectively PASSED** given the approvals recorded in the phase facts.

---

_Verified: 2026-05-30T06:20:00Z_
_Verifier: Claude (gsd-verifier)_
