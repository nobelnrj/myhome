---
phase: 09-schemav6-accounts-management
plan: 03
subsystem: features/expenses/accounts
tags: [swiftui, swiftdata, accounts, expense-attribution, gmail-sync, tdd]
dependency_graph:
  requires:
    - phase: 09-01
      provides: SchemaV6 (Account model with sourceLabel, Expense.accountID field)
    - phase: 09-02
      provides: AccountBalance helper, AccountsListView/EditAccountView/AccountDetailView
  provides:
    - AccountPickerView (optional account picker, active accounts only, last-used default)
    - Account picker rows in AddExpenseView and EditExpenseView
    - AccountFilter enum + filteredExpenses account-filter in ExpenseListView
    - GmailAccountAttributionHelper (pure function: sourceLabel → UUID map)
    - GmailSyncController wired to set expense.accountID from pre-loop UUID map
    - GmailAccountAttributionTests (RED commit + GREEN passing)
  affects: [09-04, phase-10 self-transfer, phase-11 asset-tracker]
tech-stack:
  added: []
  patterns:
    - AccountPickerView mirrors CategoryPickerView exactly (Binding selection, None row, ForEach active-only, Cancel/Clear toolbar)
    - last-used account default via UserDefaults lastUsedAccountID (mirrors category last-used pattern)
    - AccountFilter enum chains after CategoryFilter in filteredExpenses computed property (no re-architecture)
    - Pre-loop UUID capture for Gmail attribution (mirrors categoryIDsByName STAB-02 pattern; no @Model refs across await)
    - Pure attribution helper function (testable without Gmail network path)
key-files:
  created:
    - MyHomeApp/Features/Expenses/AccountPickerView.swift
    - MyHomeTests/GmailAccountAttributionTests.swift
  modified:
    - MyHomeApp/Features/Expenses/AddExpenseView.swift
    - MyHomeApp/Features/Expenses/EditExpenseView.swift
    - MyHomeApp/Features/Expenses/ExpenseListView.swift
    - MyHomeApp/Features/Gmail/GmailSyncController.swift
key-decisions:
  - "Account balance excludes expenses dated before the account's as-of date (defaults to today); confirmed working as designed per D-09/D-10 contract — user chose to keep this behavior as-is"
  - "Migration auto-creates accounts and backfills accountID for expenses with a bank sourceLabel; manual (no-label) expenses require hand attribution by nature — user confirmed acceptable"
  - "Archived accounts excluded from both picker (@Query filter !$0.isArchived) and attribution helper; if a selected account becomes archived before save, accountID is nullified (T-09-09)"
  - "Attribution helper is a pure function (accountIDsByLabel build + resolver); GmailSyncController captures UUIDs before the per-message loop and never holds @Model refs across await (T-09-10 / STAB-02)"
  - "sourceAccount field (Gmail dedup key) is never touched by attribution code — only accountID is written (T-09-11 / ACCT-08)"
requirements-completed: [ACCT-06]
duration: ~
completed: "2026-06-10"
---

# Phase 9 Plan 03: Expense Attribution Surface Summary

**AccountPickerView + ExpenseListView account filter + Gmail sourceLabel→accountID auto-attribution helper, with GmailAccountAttributionTests passing (TDD RED/GREEN)**

## Performance

- **Duration:** multi-session
- **Completed:** 2026-06-10
- **Tasks:** 3 auto + 1 human-verify checkpoint
- **Files modified:** 6

## Accomplishments

- Optional account picker in Add/Edit expense defaulting to last-used active account (D-04/D-08); archived accounts excluded from picker and nullified on save (T-09-09)
- AccountFilter (all/unassigned/account-UUID) chained after CategoryFilter in ExpenseListView.filteredExpenses; filter icon shows filled variant when active (ACCT-06/D-07)
- Gmail auto-attribution: GmailSyncController captures `accountIDsByLabel: [String: UUID]` before the per-message loop and writes `expense.accountID` without holding @Model refs across await (D-05/STAB-02/T-09-10)
- GmailAccountAttributionTests: `attributesBySourceLabel` and `archivedAccountNotMatched` both pass (TDD)

## Task Commits

1. **Task 1: AccountPickerView + Add/Edit account picker rows (D-04)** — `70e8645` (feat)
2. **Task 2: ExpenseListView account filter (ACCT-06/D-07)** — `6a9ca1e` (feat)
3. **Task 3 RED: failing GmailAccountAttributionTests** — `39c8ce4` (test)
4. **Task 3 GREEN: GmailAccountAttributionHelper + GmailSyncController wiring (D-05)** — `91566cf` (feat)
5. **Task 4: human-verify checkpoint** — APPROVED (no code commit)

## Files Created/Modified

- `MyHomeApp/Features/Expenses/AccountPickerView.swift` — new; optional account picker mirroring CategoryPickerView; `@Query(filter: #Predicate<Account> { !$0.isArchived })` for active accounts; None/Unassigned top row; Cancel/Clear toolbar
- `MyHomeApp/Features/Expenses/AddExpenseView.swift` — account picker row + sheet; last-used account seed from UserDefaults `lastUsedAccountID`; `saveExpense()` writes `expense.accountID` and nullifies if archived
- `MyHomeApp/Features/Expenses/EditExpenseView.swift` — account picker row + sheet seeded from `expense.accountID`; isDirty/local @State mirror pattern respected; Save writes back `expense.accountID`
- `MyHomeApp/Features/Expenses/ExpenseListView.swift` — `AccountFilter` enum (all/unassigned/account(UUID)); `@State accountFilter`; filter chained in `filteredExpenses`; toolbar Menu with active-account rows; filled icon when filter active
- `MyHomeApp/Features/Gmail/GmailSyncController.swift` — pre-loop `accountIDsByLabel: [String: UUID]` map (non-archived, indexed by sourceLabel + lowercased name); per-message `expense.accountID` assignment; no new `ctx.save()` inside loop; `sourceAccount` untouched
- `MyHomeTests/GmailAccountAttributionTests.swift` — new; `attributesBySourceLabel` (active account matched) + `archivedAccountNotMatched` (archived excluded); uses pure attribution helper

## Decisions Made

- Account balance excluding expenses before the as-of date (defaulting to today) is intentional per the D-09/D-10 contract; verified at the human checkpoint and accepted by the user — no change requested.
- Migration backfill covers all bank-sourced expenses; manual (no-label) expenses require user hand-attribution by design — user confirmed acceptable at the human checkpoint.
- Pure attribution helper extracted from GmailSyncController to make the `sourceLabel → UUID` resolution independently testable without the full Gmail sync network path.

## Deviations from Plan

None — plan executed exactly as written. All design decisions and behaviors confirmed by the user at the human-verify checkpoint.

### Human Checkpoint Notes (confirmed at verification)

**1. Balance excludes pre-as-of expenses — confirmed intended**
- **Reported at:** Task 4 human-verify
- **Observation:** Account balance shows 0 for auto-created accounts because no manual opening balance is set and the as-of date defaults to today; expenses dated before today are excluded.
- **Resolution:** User confirmed this is working as designed (D-09/D-10 contract). No change requested.

**2. Manual expenses remain Unassigned after migration — confirmed acceptable**
- **Reported at:** Task 4 human-verify
- **Observation:** Only expenses with a `sourceLabel` matching an auto-created account are backfilled with `accountID`. Manual expenses (no bank label) remain Unassigned after migration.
- **Resolution:** User confirmed this is acceptable. Manual attribution via the new account picker is the intended path for these expenses.

## Verification

### Automated (TDD)

- `xcodebuild test -scheme MyHome -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:MyHomeTests/GmailAccountAttributionTests` — **TEST SUCCEEDED**
  - `GmailAccountAttributionTests/attributesBySourceLabel` — PASSED
  - `GmailAccountAttributionTests/archivedAccountNotMatched` — PASSED

### Human Verified

- Account picker in Add expense: only active accounts shown; picked account persists as last-used default on next add.
- Account picker in Edit expense: seeds from existing `expense.accountID`; change persists and reflects in account detail balance (Plan 02).
- ExpenseListView account filter: All / Unassigned / per-account filtering; filter icon shows filled variant when active; returns to All correctly.
- Balance semantics (as-of date behavior) confirmed acceptable as designed.
- Migration backfill behavior confirmed acceptable.

## Threat Surface Scan

No new unplanned threat surface. All three threat register items from the plan were implemented:
- T-09-09: Archived accounts excluded from picker; accountID nullified if account archived before save — implemented.
- T-09-10: Pre-loop UUID capture, no @Model refs across await, no per-message save — implemented and tested.
- T-09-11: `sourceAccount` (Gmail dedup key) untouched by attribution code — verified via grep and test.

## Known Stubs

None. All attribution surfaces are fully wired to SwiftData.

## Self-Check: PASSED

Created files exist:
- MyHomeApp/Features/Expenses/AccountPickerView.swift: FOUND (commit 70e8645)
- MyHomeTests/GmailAccountAttributionTests.swift: FOUND (commit 39c8ce4)

Commits exist:
- 70e8645: FOUND (feat(09-03) AccountPickerView + Add/Edit)
- 6a9ca1e: FOUND (feat(09-03) ExpenseListView account filter)
- 39c8ce4: FOUND (test(09-03) failing GmailAccountAttributionTests)
- 91566cf: FOUND (feat(09-03) Gmail attribution helper GREEN)

---
*Phase: 09-schemav6-accounts-management*
*Completed: 2026-06-10*
