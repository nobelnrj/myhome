---
phase: 01-foundation-manual-expense-spine
plan: 03
subsystem: expense-ui-screens
tags: [swiftui, swiftdata, custom-keypad, expense-list, add-edit-screens, en-IN]
dependency_graph:
  requires:
    - swiftdata-schema (01-02)
    - xcode-project (01-01)
  provides:
    - expense-list-screen (ExpenseListView @Query reverse-chron, swipe-delete, add/edit sheets)
    - add-expense-screen (AddExpenseView <=3-tap flow, custom keypad, sign toggle)
    - edit-expense-screen (EditExpenseView @Bindable + destructive delete with confirmation)
    - decimal-keypad (DecimalKeypadView always-visible 3-col grid, no system keyboard)
    - expense-row (ExpenseRow en-IN amount + note + date)
  affects:
    - 01-04 (migration tests can now use the live app to create v1 seed store)
tech_stack:
  added:
    - SwiftUI .sheet(item:) for tap-to-edit pattern
    - SwiftUI ContentUnavailableView for empty state
    - SwiftUI .confirmationDialog for destructive action sheet
    - LazyVGrid 3-column custom keypad (no system keyboard)
    - @Bindable for live two-way model binding in edit sheet
  patterns:
    - "@Query sort by Expense.date order .reverse — reads via @Query, writes via modelContext (RESEARCH Pattern 4)"
    - "DecimalKeypadView always visible in layout — no keyboard animation/avoidance (Pitfall 6)"
    - "Local @State mirrors expense fields for isDirty tracking; Cancel discards without mutating model"
    - "dismiss() after save/delete in same action closure — no same-tick navigation race (Pitfall 19)"
    - "abs(amount) < 1_000_000_000 guard before insert (T-01-03 ASVS V5)"
key_files:
  created:
    - MyHomeApp/Features/Expenses/DecimalKeypadView.swift
    - MyHomeApp/Features/Expenses/AddExpenseView.swift
    - MyHomeApp/Features/Expenses/ExpenseListView.swift
    - MyHomeApp/Features/Expenses/ExpenseRow.swift
    - MyHomeApp/Features/Expenses/EditExpenseView.swift
  modified:
    - MyHomeApp/RootView.swift (wired to ExpenseListView, replaced placeholder)
    - MyHome.xcodeproj/project.pbxproj (file refs + build phases for all 5 new files)
decisions:
  - "EditExpenseView uses local @State mirror of expense fields for isDirty detection; Cancel dismisses without mutating the model — avoids unexpected @Bindable mutations when user decides to discard"
  - "RootView reduced to a single-line pass-through to ExpenseListView; ExpenseListView owns its own NavigationStack per UI-SPEC"
  - "All 5 Features/Expenses/ files added to pbxproj in a single edit (required for BUILD SUCCEEDED — the build system validates file existence at parse time)"
  - "amountString initialized from expense.amount in EditExpenseView.onAppear with trailing-zero cleanup for UX (500.00 displays as 500)"
metrics:
  duration: 18 min
  completed_date: "2026-05-29"
  tasks_completed: 2
  tasks_total: 2
  files_created: 5
  files_modified: 2
---

# Phase 01 Plan 03: Expense UI Screens Summary

Custom always-visible decimal keypad + Add/Edit/List screens wired to the SwiftData container — full manual-expense vertical slice satisfying EXP-01/02/03 with en-IN amounts, sign toggle, empty state, and both delete paths.

## What Was Built

**Task 1 — DecimalKeypadView + AddExpenseView (<=3-tap add flow)** (commit eb20b67)

Created the input layer:

- `DecimalKeypadView.swift`: `LazyVGrid` 3-column keypad (7-8-9 / 4-5-6 / 1-2-3 / .-0-backspace). 64pt minimum key height per UI-SPEC. `handleKey()` enforces: single decimal point, <=2 decimal places (D-04 paise-optional), backspace removes last char. Backspace uses `Image(systemName: "delete.backward")`. Accessibility labels: "0"-"9", "Decimal point", "Delete". No `keyboardType` anywhere (Pitfall 6).

- `AddExpenseView.swift`: Sheet with `NavigationStack` inside, title "New Expense" inline. Toolbar: "Cancel" (dismiss) + "Save Expense" (accent, disabled until non-zero). Section 1: sign-toggle button (`plus.slash.minus`, accessibilityLabel "Toggle sign"), large `.largeTitle.bold` amount display with live `formattedINR()`, always-visible `DecimalKeypadView`. Section 2 (off <=3-tap path): collapsible date picker row (defaults to `Date()` per D-01, shows `formattedForDatePickerRow()`), Note `TextField` "Merchant or memo". On save: `abs(amount) < 1_000_000_000` guard (T-01-03), shake+systemRed for zero/invalid, `context.insert(expense)`, then `dismiss()` (T-01-07/Pitfall 19).

**Task 2 — ExpenseListView + ExpenseRow + EditExpenseView + RootView wiring** (commit a6daf61)

Created the list and edit layer:

- `ExpenseRow.swift`: Leading 100pt column for `amount.formattedINR()` (`.headline`, `.systemGreen` for negatives — color + leading minus, never color alone). Trailing VStack: note (`.body`, 1 line, truncated) over `date.formattedForExpenseList()` (`.subheadline`, secondary). `accessibilityElement(children: .combine)`.

- `ExpenseListView.swift`: `NavigationStack` + `@Query(sort: \Expense.date, order: .reverse)`. `List .insetGrouped` with `ForEach(expenses)` → `ExpenseRow` + `.onTapGesture` → `editingExpense`. `.onDelete` swipe-delete via `context.delete`. Toolbar `+` (accent, accessibilityLabel "Add Expense"). `.sheet(isPresented: $showingAddSheet)` → `AddExpenseView`. `.sheet(item: $editingExpense)` → `EditExpenseView`. `ContentUnavailableView("No Expenses Yet", ...)` when empty.

- `EditExpenseView.swift`: `@Bindable var expense: Expense`. Local `@State` mirrors (amountString, isNegative, date, note) initialized in `.onAppear`. Toolbar: "Cancel" (dismiss, no confirmation) + "Save Expense" (enabled when `isDirty`). Same form layout as Add (DecimalKeypadView always visible). Full-width `.destructive` "Delete Expense" button (`.tint(.systemRed)`) → `.confirmationDialog("Delete Expense?")` with "Delete Expense" (destructive) + "Cancel". Save writes fields back + `expense.updatedAt = Date()`, then `dismiss()`. Delete calls `context.delete(expense)`, then `dismiss()`.

- `RootView.swift`: Replaced placeholder with `ExpenseListView()`.

## Verification Evidence

```
xcodebuild build -scheme MyHome -destination 'platform=iOS Simulator,name=iPhone 17'
→ BUILD SUCCEEDED

xcodebuild test -scheme MyHome -only-testing:MyHomeTests/ExpenseModelTests -destination 'platform=iOS Simulator,name=iPhone 17'
→ TEST SUCCEEDED
  ExpenseModelTests/expenseCRUD() PASSED
  ExpenseModelTests/expenseUpdate() PASSED
  ExpenseModelTests/currencyFormatting() PASSED
  ExpenseModelTests/expensePropertiesAreCloudKitReady() PASSED

grep -Rn ".keyboardType(.decimalPad)" MyHomeApp/Features/ → ZERO actual usage (only doc comment) ✓
grep -rn "@StateObject|@ObservedObject|@Published" MyHomeApp/ → ZERO (correct, Pitfall 5) ✓
grep -q "DecimalKeypadView" MyHomeApp/Features/Expenses/AddExpenseView.swift → found ✓
grep -q "@Query" MyHomeApp/Features/Expenses/ExpenseListView.swift → found ✓
grep -q "Delete Expense" MyHomeApp/Features/Expenses/EditExpenseView.swift → found ✓
grep -q "@Bindable" MyHomeApp/Features/Expenses/EditExpenseView.swift → found ✓
grep -q "Save Expense" MyHomeApp/Features/Expenses/AddExpenseView.swift → found ✓
grep -q "Save Expense" MyHomeApp/Features/Expenses/EditExpenseView.swift → found ✓
```

## Deviations from Plan

None — plan executed exactly as written.

## Threat Surface Scan

No new threat surface beyond the plan's declared threat model:
- T-01-03: mitigated — `abs(amount) < Decimal(1_000_000_000)` guard in both AddExpenseView and EditExpenseView before any model mutation.
- T-01-06: mitigated — note rendered via `Text(note)` (plain SwiftUI Text, no `AttributedString(markdown:)`).
- T-01-07: mitigated — `dismiss()` called after save/delete in action closure; no same-tick state mutation (Pitfall 19).
- T-01-SC: not applicable — zero third-party packages this phase.

## Known Stubs

| Stub | File | Reason |
|------|------|--------|
| `v1StoreMigratesCleanly` | `MyHomeTests/MigrationTests.swift` | Seed store creation requires running app once and exporting the SQLite store — plan 04 task |

## Self-Check: PASSED

Files exist:
- MyHomeApp/Features/Expenses/DecimalKeypadView.swift ✓
- MyHomeApp/Features/Expenses/AddExpenseView.swift ✓
- MyHomeApp/Features/Expenses/ExpenseListView.swift ✓
- MyHomeApp/Features/Expenses/ExpenseRow.swift ✓
- MyHomeApp/Features/Expenses/EditExpenseView.swift ✓
- MyHomeApp/RootView.swift (modified) ✓

Commits exist:
- eb20b67 feat(01-03): DecimalKeypadView + AddExpenseView (<=3-tap add flow) ✓
- a6daf61 feat(01-03): ExpenseListView + ExpenseRow + EditExpenseView (list, edit, delete) ✓
