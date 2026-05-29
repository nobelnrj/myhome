---
phase: 01-foundation-manual-expense-spine
reviewed: 2026-05-29T00:00:00Z
depth: standard
files_reviewed: 15
files_reviewed_list:
  - MyHomeApp/MyHomeApp.swift
  - MyHomeApp/RootView.swift
  - MyHomeApp/Persistence/Models/Expense.swift
  - MyHomeApp/Persistence/Schema/SchemaV1.swift
  - MyHomeApp/Persistence/Schema/MigrationPlan.swift
  - MyHomeApp/Persistence/ModelContainer+App.swift
  - MyHomeApp/Support/Decimal+INR.swift
  - MyHomeApp/Support/Date+Display.swift
  - MyHomeApp/Features/Expenses/DecimalKeypadView.swift
  - MyHomeApp/Features/Expenses/ExpenseListView.swift
  - MyHomeApp/Features/Expenses/ExpenseRow.swift
  - MyHomeApp/Features/Expenses/AddExpenseView.swift
  - MyHomeApp/Features/Expenses/EditExpenseView.swift
  - MyHomeTests/ExpenseModelTests.swift
  - MyHomeTests/MigrationTests.swift
findings:
  critical: 2
  critical_resolved: 2
  warning: 7
  info: 5
  total: 14
status: issues_found
critical_status: resolved
---

# Phase 1: Code Review Report

**Reviewed:** 2026-05-29
**Depth:** standard
**Files Reviewed:** 15
**Status:** issues_found

## Summary

Phase 1 lays the irreversible foundation: `Expense` @Model, VersionedSchema scaffolding, App Group ModelContainer, en-IN formatting, custom keypad, and the three CRUD screens. The CloudKit-readiness discipline on the @Model is sound (all defaulted/optional, no `@Attribute(.unique)`, Decimal money, UTC dates), the immutable identifiers match the locked decisions, strict concurrency is set to `complete`, and the privacy manifest is wired. The forbidden property wrappers do not appear anywhere.

However, adversarial review surfaces two **blockers** that defeat stated requirements: (1) the custom keypad never persists writes — `AddExpenseView`/`EditExpenseView` call `context.insert`/mutate but **never `try context.save()`**, while the production container has no explicit autosave guarantee, risking data loss on the very flow EXP-01/02 promise; and (2) the CloudKit-readiness reflection test is a **tautology that can never fail**, so FND-03's mechanical guard provides false confidence. Several warnings concern Decimal round-tripping through `String(describing:)`, locale assumptions in parsing, the silent App Group fallback, and a non-cancelled shake timer mutating view state after dismissal.

## Critical Issues

### CR-01: Writes are never persisted — `context.save()` is missing on insert, edit, and delete [RESOLVED 2026-05-29]

**File:** `MyHomeApp/Features/Expenses/AddExpenseView.swift:188-191`, `MyHomeApp/Features/Expenses/EditExpenseView.swift:246-260`, `MyHomeApp/Features/Expenses/ExpenseListView.swift:69-73`
**Issue:** `AddExpenseView.saveExpense()` calls `context.insert(expense)` then immediately `dismiss()` with no `try context.save()`. `EditExpenseView.saveExpense()`/`deleteExpense()` and `ExpenseListView.deleteExpenses(at:)` likewise mutate/delete with no explicit save. SwiftData's implicit autosave is tied to the `mainContext`'s `autosaveEnabled` and runs on run-loop checkpoints — it is **not** guaranteed to have flushed before the app is backgrounded or killed, and the production container in `ModelContainer+App.swift` does not set `autosaveEnabled` explicitly. The research's own Pattern 4 comment ("ModelContext auto-saves or explicit try? context.save()") flagged this as a choice that was never resolved. On the canonical EXP-01 fast-path (add → dismiss → background app), the new expense can be lost. The migration/CRUD tests pass only because they call `try context.save()` manually — production code does not, so tests do not cover the real write path.
**Fix:** Persist explicitly after every mutation, surfacing failures rather than swallowing them:
```swift
private func saveExpense() {
    // ... validation ...
    let expense = Expense(amount: amount, date: date, note: trimmedNote)
    context.insert(expense)
    do {
        try context.save()
    } catch {
        // surface to user / log; do not dismiss on failure
        shakeAmount()
        return
    }
    dismiss()
}
```
Apply the same `try context.save()` to `EditExpenseView.saveExpense()`, `EditExpenseView.deleteExpense()`, and `ExpenseListView.deleteExpenses(at:)`. If relying on autosave is intended, set `container.mainContext.autosaveEnabled = true` deliberately and document that choice — but explicit save on a financial write is the safer contract.

**Resolution (commit `36c1e7b`):** Added `do { try context.save() } catch { ... }` after `context.insert` in `AddExpenseView.saveExpense()`, after the property edits in `EditExpenseView.saveExpense()`, after `context.delete` in `EditExpenseView.deleteExpense()`, and after the delete loop in `ExpenseListView.deleteExpenses(at:)`. On failure the code logs via `assertionFailure`/`print` and does NOT dismiss (re-shakes the amount on the save paths), so a failed write is never treated as success. Build green and all 5 tests pass on iPhone 17.

### CR-02: CloudKit-readiness reflection test is a tautology — it can never fail [RESOLVED 2026-05-29]

**File:** `MyHomeTests/ExpenseModelTests.swift:84-94`
**Issue:** The optionality assertion computes `let hasNonNilValue = !isOptional` and then `let passesRule = isOptional || hasNonNilValue`, which expands to `isOptional || !isOptional` — always `true`. The `#expect(passesRule, ...)` therefore can never fail regardless of the model shape. This is the mechanical guard FND-03 and PITFALLS Pitfall 1 rely on to stop a future developer adding a non-optional, default-less property that breaks CloudKit mirroring. As written it provides zero protection. (The `uniquenessConstraints` half of the test is genuine and useful; only the optionality loop is broken.) A reflection-based optionality check also cannot in principle detect a "non-optional with a default" vs "non-optional without a default" at runtime, because by the time you have an instance every stored property already holds a value — so the test is doubly ineffective and gives false confidence.
**Fix:** Replace the runtime-reflection optionality check with a compile-time/source-level guard that actually catches the regression — either (a) a build-phase or test that greps the `@Model` source for non-optional, non-defaulted stored properties, or (b) at minimum assert against the `Schema` entity's `attributesByName` to verify each attribute `isOptional == true || defaultValue != nil`:
```swift
let entity = container.schema.entities.first { $0.name == "Expense" }!
for attribute in entity.attributes {
    let ok = attribute.isOptional /* || attribute has a default — verify the SwiftData API surface */
    #expect(ok, "Attribute '\(attribute.name)' must be optional or defaulted for CloudKit")
}
```
Verify the exact `Schema.Entity` attribute API in Xcode (Assumption A2 in research was never confirmed) before relying on it.

**Resolution (commit `d1cc0a2`):** Replaced the `isOptional || !isOptional` tautology (and removed the now-unused `OptionalProtocol` reflection helper) with assertions against the SwiftData `Schema.Entity` metadata: for every `entity.attributes`, assert `isOptional || defaultValue != nil`; assert `entity.uniquenessConstraints.isEmpty`; and assert a default-initialized `Expense(amount:)` succeeds with `amount` of type `Decimal` and expected defaults (`currencyCode == "INR"`, `note == nil`). The `Schema.Entity` attribute API (`isOptional`, `defaultValue`) was confirmed working by a green test run, resolving research Assumption A2. The test retains its name `expensePropertiesAreCloudKitReady` and remains a Swift Testing `@Test`. It now genuinely fails if a required/default-less property, a unique constraint, or a non-Decimal money type is introduced.

## Warnings

### WR-01: `Decimal(string:)` and `String(describing: Decimal)` are locale-fragile for amount round-tripping

**File:** `MyHomeApp/Features/Expenses/AddExpenseView.swift:33`, `MyHomeApp/Features/Expenses/EditExpenseView.swift:33`, `MyHomeApp/Features/Expenses/EditExpenseView.swift:220-223`
**Issue:** `Decimal(string: amountString)` parses with a fixed POSIX/`.` decimal separator. That happens to match the keypad (which always emits `.`), so the add path is currently safe — but it is an undocumented coupling: if the keypad is ever localized to emit `,` (common in many locales), parsing silently returns `nil` or wrong values. More concretely, `EditExpenseView.initializeFields()` reconstructs the editable string via `String(describing: amount)`. `String(describing:)` on `Decimal` is not a locale-stable, round-trip-guaranteed serialization contract; for values with trailing fractional precision or values originating from migration/import it can yield strings the keypad's 2-decimal guard never sanitized (e.g. `"500.333"`), which then flows straight back into `Decimal(string:)` on save. Money should not depend on `description` formatting.
**Fix:** Parse and render through an explicit, fixed locale. For parsing, construct from a known-locale `Decimal.FormatStyle` or `NumberFormatter` pinned to `Locale(identifier: "en_US_POSIX")`. For the edit seed string, format the stored `Decimal` deterministically (e.g. `NSDecimalNumber` with a fixed-scale `NSDecimalNumberHandler`, or `Decimal.formatted` with a plain number style and `.` separator) rather than `String(describing:)`.

### WR-02: Shake timer mutates view state after the sheet is dismissed

**File:** `MyHomeApp/Features/Expenses/AddExpenseView.swift:194-203`, `MyHomeApp/Features/Expenses/EditExpenseView.swift:262-271`
**Issue:** `shakeAmount()` schedules `DispatchQueue.main.asyncAfter(deadline: .now() + 0.3)` to reset `amountShakeOffset`/`amountIsError`. The closure captures `self` and runs 0.3s later unconditionally. On the over-limit guard path in `saveExpense()` the view stays up so it is benign there, but the pattern is fragile: any code path that triggers `shakeAmount()` and then dismisses (or a rapid re-entry) leaves a pending closure that mutates `@State` on a view that may no longer be presented, and the timer is never cancelled. This is also a non-structured-concurrency escape hatch in a Swift 6 `complete` project.
**Fix:** Use a cancellable structured task tied to view lifetime instead of a free `asyncAfter`:
```swift
@State private var shakeTask: Task<Void, Never>?
private func shakeAmount() {
    amountIsError = true
    withAnimation(.easeInOut(duration: 0.05).repeatCount(5, autoreverses: true)) { amountShakeOffset = 8 }
    shakeTask?.cancel()
    shakeTask = Task { @MainActor in
        try? await Task.sleep(for: .seconds(0.3))
        guard !Task.isCancelled else { return }
        amountShakeOffset = 0; amountIsError = false
    }
}
```

### WR-03: Silent App Group fallback can fork the store location and orphan data

**File:** `MyHomeApp/Persistence/ModelContainer+App.swift:21-30`
**Issue:** When `containerURL(forSecurityApplicationGroupIdentifier:)` returns `nil` (App Group not provisioned — common on the free account per Pitfall 5/13), the code silently falls back to `.applicationSupportDirectory` with no log, no flag, and no user-visible signal. If the entitlement later starts provisioning (e.g. after the paid-account upgrade or an OS quirk), the app silently switches back to the App Group path and the user's existing Application-Support store is orphaned — exactly the catastrophic outcome Pitfall 13 warns about. The fallback also force-unwraps `.first!` on the Application Support URL lookup (see WR-04). The two paths are not "the same relative path" across containers as the comment claims; they are different absolute roots and SwiftData keys the store to the absolute URL.
**Fix:** Log loudly when the fallback is taken, and persist a one-time flag recording which store location was chosen so the app never silently switches roots later:
```swift
if let groupURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.com.reojacob.myhome") {
    storeURL = groupURL.appendingPathComponent("MyHome.store")
} else {
    Logger(...).warning("App Group unavailable — using Application Support store. Migration required when App Group provisions.")
    // record the chosen location so a future launch does not silently switch roots
    ...
}
```
At minimum the silent fallback must not be allowed to flip back without an explicit migration step.

### WR-04: Force-unwrap on `.applicationSupportDirectory` URL lookup

**File:** `MyHomeApp/Persistence/ModelContainer+App.swift:27-29`
**Issue:** `FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!` force-unwraps. This array is effectively always non-empty on iOS, so a crash is unlikely, but combined with the `fatalError` in `MyHomeApp.swift:13` it means any failure here takes down the whole app at launch with no recovery. For a financial app the store-open path should fail gracefully, not crash.
**Fix:** Use `try` with a thrown error instead of `!`:
```swift
guard let supportURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
    throw CocoaError(.fileNoSuchFile)
}
```

### WR-05: `isDirty` date comparison can produce false negatives/positives via DatePicker rounding

**File:** `MyHomeApp/Features/Expenses/EditExpenseView.swift:37-42`
**Issue:** `isDirty` compares `date != expense.date` with full `Date` equality (sub-millisecond). `expense.date` is a full UTC timestamp including seconds, but the `DatePicker` is configured with `displayedComponents: [.date, .hourAndMinute]` (no seconds). If the user opens the date picker and re-selects, the bound `date` is truncated to the minute, so `date != expense.date` becomes true even when the user intended no change — marking the form dirty and, on save, silently zeroing the original seconds of `expense.date`. Conversely if `initializeFields` copies the exact timestamp, an untouched picker stays equal, so the bug only bites when the picker is interacted with. For UTC-stored intra-day ordering (D-02 rationale) this seconds loss is a real correctness regression.
**Fix:** Either store/compare at minute granularity deliberately, or only overwrite `expense.date` when the user actually changed the date (track a `dateWasEdited` flag set in the DatePicker's binding), so an untouched timestamp keeps its original seconds.

### WR-06: Keypad allows malformed numeric strings (leading zeros, lone/leading dot edge cases)

**File:** `MyHomeApp/Features/Expenses/DecimalKeypadView.swift:53-78`
**Issue:** `handleKey` permits arbitrary leading zeros (`"0007"`, `"00"`) and does not cap the integer-part length, so a user can build very long strings that the `< 1_000_000_000` guard only rejects at save time (with a shake and no explanation). `Decimal(string: "0007")` parses to `7` so it is not a crash, but the display shows the raw string is not used (display uses `parsedAmount.formattedINR()`), masking the malformed entry. There is no guard preventing the integer part from exceeding the 1-billion limit during entry, so the keypad lets the user type past the valid range before silently failing on Save.
**Fix:** Normalize on input: strip a leading `0` when a non-zero digit follows (`"0" + "5"` → `"5"`), keep a single `"0"` before a decimal point, and optionally reject digits once the parsed value would exceed the documented max so the validation is visible at entry time rather than only on Save.

### WR-07: `EditExpenseView` decimal-trim only handles all-zero fractions

**File:** `MyHomeApp/Features/Expenses/EditExpenseView.swift:225-231`
**Issue:** The trailing-zero cleanup only collapses `"500.00"` → `"500"` when *every* fractional digit is `0`. A stored amount like `Decimal(500.5)` rendered by `String(describing:)` may appear as `"500.5"` (fine) but a value such as `"500.50"` keeps the trailing zero, and any value with >2 fractional digits (possible from future import/migration) is left intact and then re-clipped inconsistently by the keypad's 2-place guard only on further typing. The result is an editable amount string whose precision does not match what the keypad would ever allow a user to enter, so re-saving can persist a value the input rules forbid.
**Fix:** After seeding `amountString`, normalize it through the same rules the keypad enforces (max 2 fractional places, no redundant trailing zeros) so the edit buffer is always in the keypad's valid domain. Tie this to the deterministic formatting fix in WR-01.

## Info

### IN-01: `fatalError` on container-open failure is intentional but undocumented as data-loss-on-corruption

**File:** `MyHomeApp/MyHomeApp.swift:9-15`
**Issue:** Crashing on an unopenable store is a defensible choice (better than silently creating a fresh empty store and losing history, per Pitfall 7). The doc comment says "crashes with a diagnostic message" but does not state the recovery expectation. Consider noting that a corrupt store currently has no in-app recovery path; this is acceptable for v1 but should be revisited before TestFlight.
**Fix:** Add a brief note and a TODO for a future "store reset / export" recovery affordance.

### IN-02: `ExpenseRow` color-only differentiation comment vs. implementation

**File:** `MyHomeApp/Features/Expenses/ExpenseRow.swift:17-22`
**Issue:** The comment states "color never sole differentiator" and relies on the leading minus from `formattedINR()`. This is correct for negatives, but positive vs negative is then distinguished by green vs label color plus the sign — fine. No action required; flagging only to confirm the accessibility intent is met (the minus sign carries the meaning, color is supplementary).
**Fix:** None required; consider an explicit accessibility value like "refund" for negatives.

### IN-03: Migration test silently passes when the seed store is absent

**File:** `MyHomeTests/MigrationTests.swift:21-26`
**Issue:** When `MyHomeV1Seed.store` is not bundled, the test calls `Issue.record(...)` then `return`. `Issue.record` does register a test issue (so it is not a true silent skip), but the early `return` means the assertions that prove FND-05 never run. Confirm the seed store is actually present in the test target's Copy Bundle Resources; otherwise FND-05 is effectively untested while appearing wired.
**Fix:** Verify `MyHomeV1Seed.store` is committed and in the test bundle; consider failing hard (not `return`) if the gate must be enforced in CI.

### IN-04: `expenseUpdate` test comment claims a delay that does not exist

**File:** `MyHomeTests/ExpenseModelTests.swift:46-58`
**Issue:** Comment says "Small delay to ensure updatedAt timestamp differs" but there is no delay; `before` is captured and the assertion is `>= before`, which can be equal if the two `Date()` calls land in the same instant. The test is not flaky (uses `>=`) but the comment is misleading and the test does not actually prove `updatedAt` advanced.
**Fix:** Either remove the misleading comment or assert `fetched[0].updatedAt > createdUpdatedAt` after a real `Task.sleep` if proving advancement matters.

### IN-05: `currencyCode` stored but display hardcodes "INR"

**File:** `MyHomeApp/Support/Decimal+INR.swift:12-17`
**Issue:** `formattedINR()` hardcodes `.currency(code: "INR")` and ignores the `Expense.currencyCode` field that the schema deliberately carries for multi-currency-readiness. This is correct for v1 (INR-only) but means the schema-forward field is unused; a future reviewer might assume formatting already respects `currencyCode`.
**Fix:** None for v1. When multi-currency lands, format with `expense.currencyCode` rather than the hardcoded literal; consider an overload `Decimal.formatted(currencyCode:)`.

---

_Reviewed: 2026-05-29_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
