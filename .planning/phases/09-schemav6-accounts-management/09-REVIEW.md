---
phase: 09-schemav6-accounts-management
reviewed: 2026-06-10T00:00:00Z
depth: standard
files_reviewed: 31
files_reviewed_list:
  - MyHomeApp/Features/Expenses/AccountPickerView.swift
  - MyHomeApp/Features/Expenses/AddExpenseView.swift
  - MyHomeApp/Features/Expenses/EditExpenseView.swift
  - MyHomeApp/Features/Expenses/ExpenseListView.swift
  - MyHomeApp/Features/Gmail/GmailSyncController.swift
  - MyHomeApp/Features/Notes/RoutineResetService.swift
  - MyHomeApp/Features/Settings/AccountDetailView.swift
  - MyHomeApp/Features/Settings/AccountsListView.swift
  - MyHomeApp/Features/Settings/EditAccountView.swift
  - MyHomeApp/Features/Settings/MigrationReviewSheet.swift
  - MyHomeApp/Features/Settings/SettingsView.swift
  - MyHomeApp/Persistence/ModelContainer+App.swift
  - MyHomeApp/Persistence/Models/Account.swift
  - MyHomeApp/Persistence/Models/Asset.swift
  - MyHomeApp/Persistence/Models/Category.swift
  - MyHomeApp/Persistence/Models/Expense.swift
  - MyHomeApp/Persistence/Models/Note.swift
  - MyHomeApp/Persistence/Models/NoteBlock.swift
  - MyHomeApp/Persistence/Schema/MigrationPlan.swift
  - MyHomeApp/Persistence/Schema/SchemaV6.swift
  - MyHomeApp/RootView.swift
  - MyHomeApp/Support/AccountBalance.swift
  - MyHomeApp/Support/Color+Hex.swift
  - MyHomeTests/AccountBalanceTests.swift
  - MyHomeTests/AccountCRUDTests.swift
  - MyHomeTests/AccountTypeInferenceTests.swift
  - MyHomeTests/GmailAccountAttributionTests.swift
  - MyHomeTests/MigrationTests.swift
  - MyHomeTests/NoteModelTests.swift
  - MyHomeTests/RoutineResetServiceTests.swift
  - MyHomeTests/SchemaV6MigrationTests.swift
findings:
  critical: 1
  warning: 7
  info: 5
  total: 13
status: issues_found
---

# Phase 9: Code Review Report

**Reviewed:** 2026-06-10
**Depth:** standard
**Files Reviewed:** 31
**Status:** issues_found

## Summary

Reviewed SchemaV6 (Account + Asset models, Note routine fields), the V5→V6 migration
with account backfill, accounts-management UI, expense→account attribution, and the
daily routine-reset service. The schema additions and typealias flips are consistent and
well-documented, and migration idempotency is genuinely exercised by tests. The migration
backfill, balance formula, and routine-reset core logic are correct.

The most serious issue is a **type-inference correctness bug** in `inferAccountType`: the
substring `"cc"` matches inside the common token `"account"`, so a label like `"ICICI Account"`
mis-infers as `credit_card`. Beyond that, the findings are robustness/quality concerns:
the routine-reset service relies on a `#Predicate` over a Bool that has a SwiftData-known
fragility, several save-failure paths are swallowed with `try?`, the migration-review
`Done` button has dead `do {}`/`try?` structure, and the Gmail `setContext` deferred-backfill
guard is written as an unreadable double-negative that runs backfill on every launch.

## Critical Issues

### CR-01: `inferAccountType` substring match misclassifies labels containing "account"

**File:** `MyHomeApp/Support/AccountBalance.swift:45-51`
**Issue:** The keyword match uses `lower.contains("cc")`. The substring `"cc"` appears inside
the very common word **"account"** (a-cc-ount). Any bank label such as `"ICICI Account"`,
`"Savings Account"`, or `"HDFC Account"` will be inferred as `"credit_card"` instead of
`"savings"`. This function drives the V5→V6 migration backfill (`MigrationPlan.swift:87`) and
the EditAccountView auto-type, so real auto-created accounts will be silently mistyped — which
in turn changes the balance color logic (`AccountDetailView.balanceColor` / `AccountsListView.balanceColor`
force red for `credit_card`) and the "Amount Owed" vs "Opening Balance" label. The existing
test only checks `"HDFC CC"`/`"ICICI Savings"`/`"Salary"` and never exercises the "account"
collision, so it passes while the bug ships.
**Fix:** Match on word boundaries / discrete tokens rather than a raw substring, e.g.:
```swift
func inferAccountType(from label: String) -> String {
    let tokens = Set(label.lowercased().split { !$0.isLetter }.map(String.init))
    if tokens.contains("cc") || label.lowercased().contains("credit") || tokens.contains("card") {
        return "credit_card"
    }
    return "savings"
}
```
Add a regression test for `"ICICI Account"` → `"savings"`.

## Warnings

### WR-01: RoutineResetService relies on a `#Predicate` over a `Bool` property (SwiftData fragility)

**File:** `MyHomeApp/Features/Notes/RoutineResetService.swift:33-35`
**Issue:** `FetchDescriptor<Note>(predicate: #Predicate { $0.isDailyRoutine == true })` filters
on a stored `Bool`. SwiftData predicates over plain Bools have historically mistranslated to
SQL in several iOS releases (the project's own `NoteModelTests` comment notes predicate
type-check fragility, and STAB-08 was a schema-mismatch crash). If this predicate ever fails
to compile to the expected SQL, the fetch returns the wrong set and either (a) silently never
resets routines, or (b) throws and the reset is skipped (caught at line 54). There is no test
that runs the reset through this `#Predicate` path against the production versioned schema —
all four `RoutineResetServiceTests` insert routine notes and rely on the predicate, but use a
bare `ModelContainer(for: Note.self, ...)` rather than `Schema(versionedSchema: SchemaV6.self)`,
so a production-schema predicate mismatch would not be caught.
**Fix:** Either fetch all notes and filter `isDailyRoutine` in-memory (the set is tiny), or add
a test that exercises `resetIfNeeded()` against `Schema(versionedSchema: SchemaV6.self)` to pin
the predicate behavior under the real store.

### WR-02: GmailSyncController.setContext deferred-backfill guard is an unreadable double-negative that re-runs every launch

**File:** `MyHomeApp/Features/Gmail/GmailSyncController.swift:211-215`
**Issue:** The guard reads
`!defaults.bool(forKey: GmailAccountStore.migrationDoneKey) == false`. By Swift precedence this
is `(!migrationDone) == false`, i.e. simply `migrationDone == true`. So whenever migration is
already done and at least one account exists, `store.backfillSourceAccount(...)` runs on **every**
`setContext` call — which is every app launch (RootView.onAppear injects the context each launch).
The inline comment ("If already migrated but backfill wasn't run") does not match the actual
condition, which fires unconditionally post-migration. The backfill is documented as idempotent,
so this is not data corruption, but it is wasted work on the launch-critical path and a
maintenance landmine.
**Fix:** Replace with an explicit, readable guard, e.g. gate on a separate
`backfillDoneKey` flag set after the first successful backfill:
```swift
if defaults.bool(forKey: GmailAccountStore.migrationDoneKey),
   !defaults.bool(forKey: backfillDoneKey),
   let firstAccount = store.accounts.first {
    store.backfillSourceAccount(email: firstAccount.email, modelContext: context)
    defaults.set(true, forKey: backfillDoneKey)
}
```

### WR-03: MigrationReviewSheet "Done" uses `do { try? ... }` — dead structure that silently drops save errors

**File:** `MyHomeApp/Features/Settings/MigrationReviewSheet.swift:45-50`
**Issue:** The block is:
```swift
do {
    try? context.save()  // CR-01: persist any pending edits
}
UserDefaults.standard.set(false, forKey: "accountReviewPending")
dismiss()
```
The `do { }` is pointless (no `catch`, no `try` inside — only `try?`). More importantly, a failed
save is swallowed by `try?`, yet the code unconditionally clears `accountReviewPending` and
dismisses, so the user is told their account edits are "finalized" even if persistence failed.
Other save sites in this phase (EditAccountView, EditExpenseView) correctly `do/catch` and
`assertionFailure`. This one diverges.
**Fix:** Drop the empty `do`, use `do { try context.save() } catch { assertionFailure(...) ; return }`
before clearing the flag and dismissing, mirroring `saveRename`.

### WR-04: Type-change Picker writes to the store inside a SwiftUI Binding setter with `try?`

**File:** `MyHomeApp/Features/Settings/MigrationReviewSheet.swift:114-120`
**Issue:** The segmented type picker's `Binding.set` mutates `account.typeRaw` and calls
`try? context.save()` directly inside the setter. A save failure is silently swallowed (the UI
shows the new selection while the store may not have persisted), and performing a persistence
write inside a binding setter on each segment tap is an anti-pattern that diverges from the
explicit-save discipline used elsewhere this phase. Same swallow-on-failure issue applies to the
swipe `Archive`/`Unarchive` saves in `AccountsListView.swift:97` and `:120`.
**Fix:** Surface save failures (at minimum `assertionFailure` in DEBUG, ideally a user-visible
error) rather than `try?`. Consider batching the change and saving on "Done" instead of per-tap.

### WR-05: EditExpenseView reconstructs the amount string with `String(describing:)` on a Decimal

**File:** `MyHomeApp/Features/Expenses/EditExpenseView.swift:300-315`
**Issue:** `initializeFields()` builds the editable `amountString` via
`String(describing: amount)` / `String(describing: -amount)`. `String(describing:)` on `Decimal`
is not a contract-stable, locale-independent numeric formatter; for some scales/magnitudes it can
emit forms the subsequent `Decimal(string:)` parse (line 41) does not round-trip cleanly, leaving
the field blank or mis-seeded and silently disabling Save (isDirty/isSaveEnabled both depend on
`parsedAmount`). The trailing-zero cleanup that follows assumes a plain decimal string and would
also misbehave on an unexpected representation.
**Fix:** Format via an explicit, locale-fixed path (e.g. `NSDecimalNumber(decimal: amount).stringValue`
or a `NumberFormatter` with `usesGroupingSeparator = false` and a fixed locale) so the value
round-trips through `Decimal(string:)`.

### WR-06: V5→V6 migration dedups Accounts only by `sourceLabel`, ignoring user-created accounts with matching names

**File:** `MyHomeApp/Persistence/Schema/MigrationPlan.swift:76-93`
**Issue:** The idempotency/dedup map (`accountByLabel`) is built only from accounts whose
`sourceLabel != nil` (line 79). If the migration ever runs on a store that already contains a
user-created account whose `name` equals a transaction `sourceLabel` but whose `sourceLabel` is
`nil` (e.g. a future re-run path, or a manually added account before a deferred backfill), step 3
will insert a **second** Account row with the same name, producing a visible duplicate in the
accounts list (uniqueness is only enforced in `EditAccountView`/`AccountsListView`, never in the
migration). This is latent given the current single-shot V5→V6 path, but the dedup key is
narrower than the app's own case-insensitive name-uniqueness contract.
**Fix:** When deciding whether to create an account for a label, also check for an existing
account whose `name` case-insensitively equals the label, not just one whose `sourceLabel` matches.

### WR-07: `Color.hexString` uses `Int(component * 255)` (truncation) for round-trip encoding

**File:** `MyHomeApp/Support/Color+Hex.swift:32-35`
**Issue:** Encoding uses `Int(r * 255)` etc., which truncates rather than rounds. A component of
e.g. `0.999` → `254` instead of `255`, so a color decoded then re-encoded can drift by one step
and a chosen swatch may not re-match its source hex on `colorHex.uppercased() == item.hex.uppercased()`
comparisons (EditAccountView:184), leaving the selected-checkmark off the swatch the user picked.
Low blast radius (cosmetic), but it is an avoidable correctness gap in a round-trip codec.
**Fix:** Use `Int((component * 255).rounded())`.

## Info

### IN-01: `String(format: "₹1,00,00,00,000")` user-facing copy hardcodes a magic threshold

**File:** `MyHomeApp/Features/Settings/EditAccountView.swift:38,235,237`
**Issue:** The `1_000_000_000` limit is duplicated in `isValid`, `saveAccount`, and the error
string. If the cap changes, three sites must change in lockstep.
**Fix:** Extract a single `private static let maxBalance: Decimal = 1_000_000_000` constant and
reference it (including in the message).

### IN-02: `last4` accepted without digit/length validation

**File:** `MyHomeApp/Features/Settings/EditAccountView.swift:108,269`
**Issue:** The "Last 4 digits" field uses `.numberPad` but is stored verbatim
(`last4 = last4.isEmpty ? nil : last4`) with no check that it is ≤4 characters or all digits
(numberPad can still paste arbitrary text). Not a security issue (display-only), but the field
name implies a constraint that is not enforced.
**Fix:** Trim to digits and clamp to 4 characters before storing.

### IN-03: `print(...)` debug artifacts on save-failure paths

**File:** `MyHomeApp/Features/Expenses/AddExpenseView.swift:294`, `EditExpenseView.swift:357,373`,
`ExpenseListView.swift:285`, `RoutineResetService.swift:56`
**Issue:** Several catch blocks log via `print(...)`. These reach the device console in release
builds and are inconsistent with the `assertionFailure` discipline used alongside them.
**Fix:** Route through a unified logger (`os.Logger`) or gate behind `#if DEBUG`.

### IN-04: `displayType`/`typeLabel` duplicated across two views

**File:** `MyHomeApp/Features/Settings/AccountsListView.swift:215-222` and
`MyHomeApp/Features/Settings/AccountDetailView.swift:59-66`
**Issue:** The `typeRaw` → display-string switch (and the `balanceColor` logic) is duplicated
verbatim in both views, so a new account type must be added in two places.
**Fix:** Hoist a shared helper (e.g. on `Account` or a small free function) for both the label
and the balance color.

### IN-05: `Decimal(1_000_000_000)` vs `1_000_000_000` literal inconsistency

**File:** `MyHomeApp/Features/Expenses/AddExpenseView.swift:271`, `EditExpenseView.swift:332`,
`EditAccountView.swift:38,235`
**Issue:** The same threshold is written three different ways (`Decimal(1_000_000_000)`,
`1_000_000_000` against a `Decimal`, and as a formatted string). Harmless today but invites
drift.
**Fix:** Centralize a single typed constant for the expense/balance cap.

---

_Reviewed: 2026-06-10_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
