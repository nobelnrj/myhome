---
phase: 02-categories-tags-budgets
reviewed: 2026-05-30T06:06:00Z
depth: standard
files_reviewed: 18
files_reviewed_list:
  - MyHomeApp/Persistence/Schema/SchemaV2.swift
  - MyHomeApp/Persistence/Schema/MigrationPlan.swift
  - MyHomeApp/Persistence/Models/Category.swift
  - MyHomeApp/Persistence/Models/Expense.swift
  - MyHomeApp/Persistence/ModelContainer+App.swift
  - MyHomeApp/Support/BudgetCalculator.swift
  - MyHomeApp/Support/Date+Display.swift
  - MyHomeApp/Features/Expenses/CategoryPickerView.swift
  - MyHomeApp/Features/Expenses/AddExpenseView.swift
  - MyHomeApp/Features/Expenses/EditExpenseView.swift
  - MyHomeApp/Features/Budgets/BudgetProgressView.swift
  - MyHomeApp/Features/Budgets/BudgetCategoryCard.swift
  - MyHomeApp/Features/Budgets/EditBudgetSheet.swift
  - MyHomeApp/Features/Budgets/BudgetsView.swift
  - MyHomeApp/Features/Budgets/FilteredExpenseListView.swift
  - MyHomeApp/Features/Budgets/ManageCategoriesView.swift
  - MyHomeApp/RootView.swift
  - MyHomeTests/BudgetCalculatorTests.swift
findings:
  critical: 1
  warning: 4
  info: 4
  total: 9
status: resolved
resolution: "CR-01 + WR-01..04 fixed in 3c31ca2 (full suite green). WR-02 ManageCategoriesView half was a false positive (no dismiss on delete). Info items IN-01..04 left as advisory."
---

# Phase 02: Code Review Report

**Reviewed:** 2026-05-30T06:06:00Z
**Depth:** standard
**Files Reviewed:** 18
**Status:** issues_found

## Summary

Phase 2 is a well-structured implementation. The schema migration is additive and correct — SchemaV1 is untouched, SchemaV2 copies the Expense model faithfully and adds the Category @Model with a properly declared bidirectional relationship, CloudKit readiness rules are uniformly applied, and the migration plan correctly uses the custom-nil stage workaround for the iOS 17 SchemaMigrationPlan bug. The seeding pattern, dynamic @Query child-view strategy, in-memory aggregation approach, and persistentModelID predicate workaround are all executed in line with the research findings.

One blocker requires a fix before ship: a double ₹ symbol in BudgetProgressView produces garbled money strings in the progress bar. Four warnings address force-unwrap risk, silent error handling, locale-hardcoded date formatting, and a fragile sortOrder assignment. Four info items cover test coverage gaps and minor defensive improvements.

---

## Critical Issues

### CR-01: Double ₹ symbol in BudgetProgressView — "₹₹500.00 remaining"

**File:** `MyHomeApp/Features/Budgets/BudgetProgressView.swift:62` and `:66`

**Issue:** `remaining.formattedINR()` already returns a string that includes the ₹ symbol (documented in `Decimal+INR.swift`: `Decimal(500).formattedINR()` → `"₹500.00"`). Both label strings prepend an additional literal `₹` in the interpolation, so the rendered output is `"₹₹500.00 remaining"` and `"₹₹200.00 over budget"`. This is a visible, wrong UI output on every budget card that has a budget set and non-zero spend.

```swift
// BudgetProgressView.swift lines 62 and 66 — WRONG
Text("₹\(remaining.formattedINR()) remaining")   // "₹₹500.00 remaining"
Text("₹\((-remaining).formattedINR()) over budget") // "₹₹200.00 over budget"

// CORRECT — drop the literal ₹ prefix; formattedINR() supplies it
Text("\(remaining.formattedINR()) remaining")
Text("\((-remaining).formattedINR()) over budget")
```

---

## Warnings

### WR-01: Force-unwrap on `FileManager.urls(for:in:).first!` in ModelContainer+App

**File:** `MyHomeApp/Persistence/ModelContainer+App.swift:29`

**Issue:** `FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!` force-unwraps the result. Apple's documentation does not guarantee a non-empty array for all mask/directory combinations; the method returns an empty array when no match exists. While `.applicationSupportDirectory` + `.userDomainMask` reliably returns at least one URL in current iOS sandboxed apps, a process running in a restricted context (e.g., App Extension) could receive an empty array, crashing at the store-URL resolution step before the container is even created.

**Fix:** Use optional chaining and convert the failure to a thrown error, consistent with the function's `throws` signature:

```swift
guard let supportURL = FileManager.default
    .urls(for: .applicationSupportDirectory, in: .userDomainMask)
    .first
else {
    throw NSError(
        domain: "com.reojacob.myhome",
        code: 1,
        userInfo: [NSLocalizedDescriptionKey: "Application Support directory unavailable"]
    )
}
storeURL = supportURL.appendingPathComponent("MyHome.store")
```

---

### WR-02: Error handling in confirmation-dialog destructive actions is silent to the user

**File:** `MyHomeApp/Features/Budgets/ManageCategoriesView.swift:99–103` and `MyHomeApp/Features/Budgets/EditBudgetSheet.swift:97–104`

**Issue:** In both the "Delete Category" and "Remove Budget" `confirmationDialog` destructive buttons, a `context.save()` failure is handled with `assertionFailure` + `print`, and then `dismiss()` is called unconditionally. `assertionFailure` is stripped in release builds. The user sees the sheet dismiss and believes the operation succeeded, even if the persistent write failed silently in a release build.

This pattern is already established in Phase 1 for expense saves (where `shakeAmount()` gives feedback). The budget/category destructive paths have no equivalent UI feedback on save failure.

**Fix:** Avoid calling `dismiss()` on save failure in the confirmation action. Since confirmation dialogs don't support inline error display, the minimal fix is to at minimum not dismiss on failure, and log the error through a proper error-reporting path:

```swift
// ManageCategoriesView — deleteCategory (ManageCategoriesView.swift:240-247)
private func deleteCategory(_ category: Category) {
    context.delete(category)
    do {
        try context.save()
        // dismiss happens via onDelete / list update — no explicit dismiss needed here
    } catch {
        // do NOT dismiss; show an alert or log to crash reporter
        print("[Error] Failed to delete category: \(error)")
    }
}

// EditBudgetSheet — Remove Budget confirmation (EditBudgetSheet.swift:94-104)
Button("Remove Budget", role: .destructive) {
    category.monthlyBudget = nil
    do {
        try context.save()
        dismiss()  // only dismiss on success
    } catch {
        print("[Error] Failed to remove budget: \(error)")
        // do NOT dismiss
    }
}
```

---

### WR-03: `formattedAsMonthYear()` uses a hardcoded `dateFormat` string, not a locale-adapted template

**File:** `MyHomeApp/Support/Date+Display.swift:43–48`

**Issue:** `formatter.dateFormat = "MMMM yyyy"` hardcodes the field order. In locales where the year precedes the month (e.g., Chinese, Japanese, Korean), this produces a wrong word order. The established `Date+Display.swift` helpers for expense-list and date-picker rows both use `dateStyle`/`timeStyle` which adapt correctly. Only `formattedAsMonthYear()` uses a hardcoded format string.

**Fix:** Use `setLocalizedDateFormatFromTemplate(_:)` which derives the correct format for the current locale:

```swift
func formattedAsMonthYear() -> String {
    let formatter = DateFormatter()
    formatter.locale = .current
    formatter.timeZone = .current
    formatter.setLocalizedDateFormatFromTemplate("MMMMyyyy")
    return formatter.string(from: self)
}
```

---

### WR-04: `sortOrder` for new custom categories uses `categories.count`, producing collisions on rapid adds

**File:** `MyHomeApp/Features/Budgets/ManageCategoriesView.swift:191`

**Issue:** New custom categories are assigned `sortOrder: 1000 + categories.count`. The `categories` property is the `@Query`-bound array, which reflects the last committed state. Because saves are explicit (`context.save()`) and @Query updates synchronously on the MainActor after each save, a single-user rapid sequence of "add → observe update → add" is safe in practice. However, if `context.save()` is called but the @Query result has not yet refreshed (e.g., during an `addCategory` call before the view re-renders), a second add could read the pre-refresh count and produce a duplicate `sortOrder`.

More concretely: the current value `1000 + categories.count` also fails to account for categories already deleted. If 14 predefined categories exist (count=14) and the user adds a custom one, it gets `sortOrder = 1014`. If the user then deletes 5 predefined categories (count drops to 9) and adds another custom category, it gets `sortOrder = 1009`, which is less than `1014` — breaking the expected append ordering.

**Fix:** Base sortOrder on the maximum existing sortOrder, not the count:

```swift
let maxOrder = categories.map(\.sortOrder).max() ?? 999
let category = Category(name: trimmed, symbolName: "tag", sortOrder: maxOrder + 1)
```

---

## Info

### IN-01: `BudgetCalculatorTests` has no test for negative-spend (refund-heavy) fractionUsed

**File:** `MyHomeTests/BudgetCalculatorTests.swift`

**Issue:** `BudgetProgressData.fractionUsed` can return a negative `Double` when `spent < 0` (e.g., a month with only refunds totaling -₹200 against a ₹1000 budget). The progress bar caps negative fractions at zero via `min(CGFloat(fraction), 1.0) * geo.size.width` in `BudgetProgressView` — but `min(negative, 1.0)` is the negative value, not zero. The bar fill width would be negative (effectively zero, since SwiftUI won't render a negative-width frame), so the visual is correct. However, `colorThreshold` with a negative fraction returns `.normal` (correct), and `remaining` would be `1000 - (-200) = 1200` (also correct). The absence of a test for this path leaves the edge case unvalidated.

**Fix:** Add a test case in `BudgetCalculatorTests`:

```swift
@Test("negativeSpend: net refunds give negative fraction → bar 0%, .normal color, remaining > budget")
func negativeSpend() throws {
    // spent = -200 (net refunds), budget = 1000
    let data = BudgetProgressData(category: cat, spent: Decimal(-200), budget: Decimal(1000))
    if let f = data.fractionUsed {
        #expect(f < 0, "fractionUsed must be negative for net refunds")
    }
    #expect(data.colorThreshold == .normal)
    #expect(data.remaining == Decimal(1200))
}
```

---

### IN-02: `EditBudgetSheet` and `EditExpenseView` use `String(describing:)` on `Decimal` for keypad initialization

**File:** `MyHomeApp/Features/Budgets/EditBudgetSheet.swift:155` and `MyHomeApp/Features/Expenses/EditExpenseView.swift:260`

**Issue:** Both `initializeFields()` methods initialize the `amountString` display value via `String(describing: amount)`. For `Decimal`, `String(describing:)` delegates to `Decimal`'s `CustomStringConvertible` conformance, which typically produces a clean decimal string (e.g. `"15000"`). However, for values constructed via `Decimal(floatLiteral:)` or via indirect `NSDecimalNumber` paths, the output can include exponent notation (e.g. `"1.5E+4"`) which `DecimalKeypadView` would display as-is, and `Decimal(string: "1.5E+4")` would fail to parse back. In practice, since all budgets and amounts are entered through `DecimalKeypadView` (which only produces digit strings), the risk is low — but the assumption is implicit and not enforced.

**Fix (low priority):** Use `NSDecimalNumber(decimal: amount).stringValue` which is guaranteed to produce a plain decimal string without scientific notation, or add a guard that falls back to `""` if the string contains non-digit characters:

```swift
amountString = NSDecimalNumber(decimal: existing).stringValue
```

---

### IN-03: `BudgetsView` renders an empty screen silently when `monthBoundaries` returns nil

**File:** `MyHomeApp/Features/Budgets/BudgetsView.swift:37–39`

**Issue:** The content area uses `if let (start, end) = BudgetCalculator.monthBoundaries(for: viewedMonth)`. If `monthBoundaries` returns `nil` (which cannot happen with a valid `DateComponents(year:month:)` but could occur if `viewedMonth` lacks year or month components due to a future refactor), the entire content area silently shows nothing — no error message, no empty state, just a blank screen below the month pager.

**Fix:** Add a defensive else branch:

```swift
if let (start, end) = BudgetCalculator.monthBoundaries(for: viewedMonth) {
    BudgetsMonthView(start: start, end: end)
} else {
    ContentUnavailableView("Unable to compute month", systemImage: "calendar.badge.exclamationmark")
}
```

---

### IN-04: `ManageCategoriesView.onDelete` silently ignores all but the first index in a multi-element `IndexSet`

**File:** `MyHomeApp/Features/Budgets/ManageCategoriesView.swift:36–40`

**Issue:** The `onDelete` handler uses `offsets.first` and ignores any additional indices. For the current swipe-to-delete affordance on iOS this is safe (SwiftUI delivers a single-element `IndexSet` for swipe-delete). However, if `EditMode` is ever added (or if an assistive technology triggers a multi-delete), the handler would silently queue only the first item for the confirmation dialog and discard the rest with no feedback.

**Fix:** If multiple-delete is not intended, document the single-index assumption explicitly. If it becomes relevant, iterate over offsets:

```swift
.onDelete { offsets in
    // Currently only handles the first index (swipe-to-delete delivers one at a time)
    if let index = offsets.first {
        categoryToDelete = categories[index]
        showDeleteConfirmation = true
    }
}
```

---

_Reviewed: 2026-05-30T06:06:00Z_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
