---
phase: 10-self-transfer-detection
reviewed: 2026-06-10T00:00:00Z
depth: standard
files_reviewed: 15
files_reviewed_list:
  - MyHomeApp/Features/Gmail/TransferDetectionScorer.swift
  - MyHomeApp/Features/Gmail/TransferScanService.swift
  - MyHomeApp/Features/Gmail/GmailSyncController.swift
  - MyHomeApp/Features/Expenses/TransferPairRow.swift
  - MyHomeApp/Features/Expenses/ExpenseListView.swift
  - MyHomeApp/Features/Expenses/EditExpenseView.swift
  - MyHomeApp/Features/Settings/SettingsView.swift
  - MyHomeApp/Support/AccountBalance.swift
  - MyHomeApp/Support/BudgetCalculator.swift
  - MyHomeApp/Support/SpendOverTimeAggregator.swift
  - MyHomeTests/TransferDetectionScorerTests.swift
  - MyHomeTests/TransferScanServiceTests.swift
  - MyHomeTests/AccountBalanceTransferTests.swift
  - MyHomeTests/AccountBalanceTests.swift
  - MyHomeTests/EditExpenseTransferTests.swift
findings:
  critical: 2
  warning: 2
  info: 1
  total: 5
status: resolved
resolution: All 5 findings (CR-01, CR-02, WR-01, WR-02, IN-01) fixed in commit ccd5518; full test suite green.
---

# Phase 10: Code Review Report

> **Resolution (2026-06-10):** All five findings fixed in commit `ccd5518`.
> CR-01 (mark releases pending partner + goes solo), CR-02 (legacy sync scan hook),
> WR-01 (clear stale pending links before re-pair), WR-02 (double-negation simplified),
> IN-01 (confirmedLegSkipped test now exercises the confirmed leg). Full suite green on iPhone 17.


**Reviewed:** 2026-06-10
**Depth:** standard
**Files Reviewed:** 15
**Status:** issues_found

## Summary

Phase 10 is well-structured. The scorer is pure and deterministic; STAB-02 value-type discipline is
consistently applied; AccountBalance sign fix is correct and regression-tested; BudgetCalculator and
SpendOverTimeAggregator D-15 exclusion filters are correctly placed. Two BLOCKER issues were found,
both in the interaction between manual marking (EditExpenseView) and the scanner/inbox state machine:
one produces an orphaned pending pair that can never be dismissed, and the legacy Gmail sync path
silently skips the post-sync transfer scan. Two warnings cover scanner re-pairing of already-pending
legs and a confusing double-negation in setContext.

---

## Critical Issues

### CR-01: Manual mark on a pending expense orphans the partner in the inbox

**File:** `MyHomeApp/Features/Expenses/EditExpenseView.swift:401–418`

**Issue:**
`applyTransferMark(true, expense:context:)` sets `isTransfer = true` and intentionally leaves
`transferPairID` intact ("solo flag allowed — D-14"). This is correct when marking a fully
unevaluated expense (`isTransfer == nil && transferPairID == nil`). However, when the expense is
already in a **pending pair** (`isTransfer == nil && transferPairID != nil`) the mark creates an
asymmetric pair state:

- The marked leg: `isTransfer = true`, `transferPairID = <partnerID>` (confirmed solo).
- The partner leg: `isTransfer = nil`, `transferPairID = <markedLegID>` (still pending).

`ExpenseListView.pendingPairs` then shows the partner as a debit with `debit.isTransfer == nil` —
correct — but the credit-leg guard `credit.isTransfer == nil` fails because the manually-marked leg
now has `isTransfer == true`. The pair is filtered out of `pendingPairs`, so the partner debit
appears in `pendingDebitLegs` but never in the rendered "Possible Transfers" section. The user sees
a ghost badge count with no dismissible row. The partner cannot be confirmed, rejected, or
auto-cleared via the inbox; it must be resolved by hand in EditExpenseView for both legs.

**Fix:**
Before marking, check whether the expense is currently pending (has a partner in the pending-pair
state). If so, either: (a) clear `transferPairID` on the partner first (orphan prevention), or (b)
treat the mark as a full pair-confirm and set `isTransfer = true` on both legs like `confirmPair()`
does. The simplest correct fix aligns with the existing cascade-unlink pattern — check and clear the
partner before proceeding:

```swift
static func applyTransferMark(_ mark: Bool, expense: Expense, context: ModelContext) {
    if mark {
        // If the expense is currently pending-paired, clear the partner's
        // back-pointer so it doesn't orphan in the inbox (CR-01 fix).
        if expense.isTransfer == nil, let pairID = expense.transferPairID,
           let all = try? context.fetch(FetchDescriptor<Expense>()),
           let partner = all.first(where: { $0.id == pairID && $0.isTransfer == nil }) {
            partner.transferPairID = nil
        }
        expense.isTransfer = true
        // Leave transferPairID on the marked leg as-is (D-14 solo flag).
    } else if expense.isTransfer == true {
        // Unmark — cascade-unlink any paired counterpart first (T-10-12)
        if let pairID = expense.transferPairID,
           let all = try? context.fetch(FetchDescriptor<Expense>()),
           let partner = all.first(where: { $0.id == pairID }) {
            partner.isTransfer = nil
            partner.transferPairID = nil
        }
        expense.isTransfer = nil
        expense.transferPairID = nil
    }
}
```

A new test should assert: "marking a pending-paired debit sets the partner's transferPairID to nil."

---

### CR-02: Legacy Gmail sync path never triggers transfer scan

**File:** `MyHomeApp/Features/Gmail/GmailSyncController.swift:711–731` (legacySingleAccountSync)

**Issue:**
`syncAccount(email:accessToken:)` calls `transferScanService?.scan()` after its final `ctx.save()`
(line 570, D-08 comment). The legacy code path `legacySingleAccountSync()` has its own save at
lines 712–714 followed by metadata updates but **never calls `transferScanService?.scan()`**. Any
device still going through the legacy path (no accounts in the store, `accessToken` set directly,
or first-launch-before-migration) will complete a sync without triggering transfer detection. No
error is raised; the feature silently does not run.

**Fix:**
Add the scan call to the success path of `legacySingleAccountSync`, mirroring `syncAccount`:

```swift
// (after line 714: `if let ctx = modelContext { try ctx.save() }`)
// D-08: run transfer scorer after legacy sync (mirrors syncAccount path)
transferScanService?.scan()
```

Place it after the save and before the `lastSyncedAt` / `syncStatus = .done` lines, identical to
where it sits in `syncAccount`.

---

## Warnings

### WR-01: Scanner re-paints stale transferPairID on already-pending credit legs

**File:** `MyHomeApp/Features/Gmail/TransferScanService.swift:61`

**Issue:**
`candidates = all.filter { $0.isTransfer == nil }` intentionally includes pending expenses
(`transferPairID != nil, isTransfer == nil`). On repeated scans after new expenses are added, the
scorer may produce a *different* best match for an already-pending debit. The scan loop overwrites
`debit.transferPairID` and `newCredit.transferPairID` with the new pair, but the **old credit's
`transferPairID`** is not cleared — it continues pointing at the debit even though the debit no
longer points back. This leaves a stale `transferPairID` on the old credit with no inbox path to
clear it. On the next scan the old credit re-enters candidates and may re-pair or remain dangling
indefinitely.

**Fix:**
Before writing a new pair, clear the old partner's back-pointer:

```swift
for pair in pairs {
    guard let debit  = expenseByID[pair.debitID],
          let credit = expenseByID[pair.creditID] else { continue }

    // Clear stale back-pointers on any previously-pending partners (WR-01)
    if let oldCreditID = debit.transferPairID, oldCreditID != credit.id,
       let oldCredit = expenseByID[oldCreditID], oldCredit.isTransfer == nil {
        oldCredit.transferPairID = nil
    }
    if let oldDebitID = credit.transferPairID, oldDebitID != debit.id,
       let oldDebit = expenseByID[oldDebitID], oldDebit.isTransfer == nil {
        oldDebit.transferPairID = nil
    }

    debit.transferPairID  = credit.id
    credit.transferPairID = debit.id
}
```

---

### WR-02: Double-negation in setContext condition is always-true and misleads future editors

**File:** `MyHomeApp/Features/Gmail/GmailSyncController.swift:216`

**Issue:**
```swift
if let firstAccount = store.accounts.first,
   !defaults.bool(forKey: GmailAccountStore.migrationDoneKey) == false {
```
Swift operator precedence parses this as `(!defaults.bool(...)) == false`, which reduces to
`defaults.bool(...) == true`. The guard therefore fires when the migration key **is** set — which
matches the comment "Migration already ran". Functionally correct by accident, but any future
editor reading `!key == false` as "key is false" will invert the condition, reintroducing a bug
where the backfill runs before migration or is skipped entirely.

**Fix:**
```swift
if let firstAccount = store.accounts.first,
   defaults.bool(forKey: GmailAccountStore.migrationDoneKey) {
    store.backfillSourceAccount(email: firstAccount.email, modelContext: context)
}
```

---

## Info

### IN-01: TransferDetectionScorerTests.confirmedLegSkipped has misleading test body

**File:** `MyHomeTests/TransferDetectionScorerTests.swift:164–191`

**Issue:**
The test constructs a `_confirmedCredit` but never passes it to the scorer — the call site
passes only `[debit].filter { ... }`. The test name says "confirmedLegSkipped" and the assertion
checks `pairs.count == 0`, but since the confirmed credit was never in the input, the 0-pair
result proves only that a debit with no counterpart produces no pairs — not that the scorer skips
confirmed legs. The comment acknowledges this but the test is essentially a dead-code verifier
rather than the behavior it claims to cover.

**Fix:**
Either (a) rewrite the test to pass `[debit, _confirmedCredit]` directly and assert the scorer
produces 0 pairs (verifying the scorer does *not* pair on `isTransfer == true` legs — or
document that the scorer intentionally does not filter, relying solely on the service-layer
pre-filter), or (b) rename the test to `"loneDebitProducesNoPairs"` and add a separate test for
the service-layer filtering behavior (already covered in TransferScanServiceTests.confirmedLegSkipped).

---

_Reviewed: 2026-06-10_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
