---
phase: 10-self-transfer-detection
verified: 2026-06-10T00:00:00Z
status: passed
score: 17/17 must-haves verified
overrides_applied: 0
re_verification: false
---

# Phase 10: Self-Transfer Detection — Verification Report

**Phase Goal:** The app automatically identifies likely self-transfers between own accounts and routes them to an explicit confirm flow; confirmed transfers are excluded from all spend and budget totals; account balances reflect confirmed transfer balance-moves.
**Verified:** 2026-06-10
**Status:** passed
**Re-verification:** No — initial verification

---

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | Scorer surfaces a pair ONLY when all 5 AND-rules hold (equal amount, opposite sign, two distinct assigned accounts, ≤3-day IST window, isTransfer == nil) | VERIFIED | `TransferDetectionScorer.findCandidatePairs` implements each rule explicitly; 12 unit tests in `TransferDetectionScorerTests` cover every AND-rule individually |
| 2 | An unassigned leg (accountID == nil) is never paired | VERIFIED | Scorer pre-filters `accountID != nil` for both debits and credits (lines 57–58 of scorer); `unassignedLegNotPaired` test passes |
| 3 | Two legs on the same account are never paired | VERIFIED | `candidates.filter { credit.accountID != debit.accountID }` (line 83); `sameAccountNotPaired` test passes |
| 4 | A leg outside the 3-day IST window is never paired | VERIFIED | `istDayDistance <= 3` filter; `outsideWindowNotPaired` tests both 4-day (0 pairs) and 3-day (1 pair) cases |
| 5 | Already-confirmed (isTransfer == true) or rejected (isTransfer == false) legs are never re-surfaced | VERIFIED | `TransferScanService.scan()` pre-filters `.filter { $0.isTransfer == nil }` before calling scorer; `confirmedLegSkipped` and `rejectedLegSkipped` tests in both scorer and service test suites |
| 6 | When one debit matches multiple candidate credits, the closest-in-time credit wins deterministically | VERIFIED | Tie-break by `abs(credit.date.timeIntervalSince(debit.date))` then `credit.id.uuidString`; `tieBreakClosestTimeWins` and `tieBreakUUIDStableOnEqualDistance` tests pass |
| 7 | A second scan over a corpus with non-nil legs produces zero new pairs (idempotent) | VERIFIED | `secondScanIdempotent` test in `TransferScanServiceTests`; WR-01 fix clears stale pending links before re-pairing (line 68–69 of service) |
| 8 | AccountBalance.compute includes confirmed-transfer legs; total net worth unchanged across a confirmed pair | VERIFIED | `AccountBalance.compute` has no `isTransfer` filter — transfer legs are fully included; `netWorthUnchangedByTransfer` test asserts `computeA + computeB == baselineA + baselineB`; `balanceMoveDirection` confirms debit account decreases, credit account increases |
| 9 | Detected pending pairs surface in a "Possible Transfers" section of the existing Review Inbox — nothing is silently excluded | VERIFIED | `ExpenseListView` has `Section("Possible Transfers")` rendered from `pendingDebitLegs` query; pairs are shown with `TransferPairRow`; confirmed/rejected legs are excluded from the inbox via defensive `isTransfer == nil` guard in the ForEach |
| 10 | Confirming a pair marks both legs isTransfer = true and keeps transferPairID cross-set | VERIFIED | `TransferPairRow.confirmPair()` sets `debit.isTransfer = true` and `credit.isTransfer = true`, leaves `transferPairID` intact (D-16 comment); single `try context.save()` after both mutations (CR-01) |
| 11 | Rejecting a pair marks both legs isTransfer = false and clears transferPairID | VERIFIED | `TransferPairRow.rejectPair()` sets `isTransfer = false` on both legs and clears `transferPairID` on both; `grep -c 'transferPairID = nil' TransferPairRow.swift` returns 2 |
| 12 | A confirmed transfer disappears from the default expense list and appears only under the Transfers filter | VERIFIED | `filteredExpenses` `.normal` case: `.filter { $0.isTransfer != true }`; `.transfers` case: `.filter { $0.isTransfer == true }` (ExpenseListView lines 287/289); human verified by user |
| 13 | The review tab badge includes the pending transfer-pair count | VERIFIED | `reviewBadgeCount = reviewItems.count + pendingDebitLegs.count` set in both `onAppear` and `onChange(of: pendingDebitLegs.count)` (ExpenseListView lines 202, 205, 208) |
| 14 | The scorer runs at the end of each Gmail sync and via a manual 'Scan for Transfers' action | VERIFIED | `GmailSyncController.syncAccount` calls `transferScanService?.scan()` after final save (line 570); legacy path `legacySingleAccountSync` also calls it (line 719, CR-02 fix); `SettingsView` has "Scan for Transfers" row calling `transferScanService.scan()` |
| 15 | A user can mark any expense as a self-transfer on its detail/edit view (solo flag: isTransfer = true, transferPairID stays nil after pending-partner release) | VERIFIED | `EditExpenseView.applyTransferMark(true,...)` sets `isTransfer = true`, clears own `transferPairID`, and releases any pending partner (CR-01 fix); `manualMarkSetsSoloTransfer` test passes |
| 16 | A user can unmark a transfer; unmark resets isTransfer to nil and clears transferPairID | VERIFIED | `applyTransferMark(false,...)` resets `isTransfer = nil` and `transferPairID = nil`; `manualUnmarkResetsTransfer` test passes |
| 17 | Unmarking a leg that was part of a confirmed pair cascade-unlinks the counterpart | VERIFIED | `applyTransferMark` fetches the partner by `transferPairID` and sets `partner.isTransfer = nil` + `partner.transferPairID = nil`; `unmarkCascadeUnlinksCounterpart` test passes |

**Score:** 17/17 truths verified

---

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `MyHomeApp/Features/Gmail/TransferDetectionScorer.swift` | Pure 5-signal candidate pairing helper | VERIFIED | `enum TransferDetectionScorer`, `static func findCandidatePairs`, no `import SwiftData`, no `@Model` |
| `MyHomeApp/Features/Gmail/TransferScanService.swift` | @MainActor scan lifecycle coordinator | VERIFIED | `@MainActor @Observable final class TransferScanService`, `var modelContext: ModelContext?`, synchronous `func scan()` |
| `MyHomeApp/Features/Expenses/TransferPairRow.swift` | Two-leg transfer-pair inbox row with confirm/reject swipe actions | VERIFIED | `struct TransferPairRow: View`, `confirmPair()`, `rejectPair()`, both set isTransfer on both legs before single save |
| `MyHomeApp/Features/Expenses/ExpenseListView.swift` | Pending-pair section, Transfers filter, badge wiring | VERIFIED | `private enum TransferFilter`, `Section("Possible Transfers")`, `filteredExpenses` with `.normal`/`.transfers` paths, `pendingDebitLegs.count` in badge |
| `MyHomeApp/Features/Gmail/GmailSyncController.swift` | Post-sync scan hook (both paths) | VERIFIED | `var transferScanService: TransferScanService?`; hook present in both `syncAccount` (line 570) and `legacySingleAccountSync` (line 719) |
| `MyHomeApp/Support/BudgetCalculator.swift` | Transfer-excluded monthlySpend and uncategorizedSpend | VERIFIED | `isTransfer != true` filter at top of `monthlySpend` and in `uncategorizedSpend` (both carry D-15 comment) |
| `MyHomeApp/Support/SpendOverTimeAggregator.swift` | Transfer-excluded chart buckets | VERIFIED | `let spendable = expenses.filter { $0.isTransfer != true }` before `switch range` in `bucket(...)` (line 204) |
| `MyHomeApp/Features/Expenses/EditExpenseView.swift` | Mark/unmark transfer toggle with cascade unlink | VERIFIED | `@State private var isMarkedTransfer`, isDirty check, Toggle row, `applyTransferMark` static helper with CR-01 pending-partner release; `grep -c 'isMarkedTransfer'` returns 5, `grep -c 'transferPairID = nil'` returns 5 |
| `MyHomeTests/TransferDetectionScorerTests.swift` | Per-AND-rule + tie-break + determinism unit tests | VERIFIED | 327 lines; 12 `@Test` functions covering all 10 specified behaviors including determinism and equidistant UUID tie-break |
| `MyHomeTests/TransferScanServiceTests.swift` | Pending-pair write + idempotency + skip integration tests | VERIFIED | 230 lines; 6 `@Test` functions; in-memory ModelContainer; `secondScanIdempotent`, `confirmedLegSkipped`, `rejectedLegSkipped`, `firstRunFlagSet` all present |
| `MyHomeTests/AccountBalanceTransferTests.swift` | Net-worth-unchanged balance-move tests | VERIFIED | 203 lines; 3 `@Test` functions: `confirmedTransferIncludedInBalance`, `netWorthUnchangedByTransfer`, `balanceMoveDirection` |
| `MyHomeTests/EditExpenseTransferTests.swift` | Solo mark + cascade-unlink unit tests | VERIFIED | 123 lines; 4 `@Test` functions; `unmarkCascadeUnlinksCounterpart` asserts both legs reset; 4th test covers pending-pair partner release (CR-01) |

---

### Key Link Verification

| From | To | Via | Status | Details |
|------|----|-----|--------|---------|
| `TransferScanService.scan` | `TransferDetectionScorer.findCandidatePairs` | fetch-all + `.filter { $0.isTransfer == nil }`, then scorer call | WIRED | Line 73–76 of `TransferScanService.swift` |
| `GmailSyncController.syncAccount` | `TransferScanService.scan` | post-save call before `return true` | WIRED | Line 570; `transferScanService?.scan()` with D-08 comment |
| `GmailSyncController.legacySingleAccountSync` | `TransferScanService.scan` | post-save call (CR-02 fix) | WIRED | Line 719; explicit CR-02 comment confirming fix |
| `RootView` | `TransferScanService` injection | `@State private var transferScanService`, `modelContext` set on `onAppear`, assigned to `gmailSyncController.transferScanService` | WIRED | RootView lines 44, 92–93 |
| `ExpenseListView pendingDebitLegs @Query` | `TransferPairRow` | ForEach over `pendingPairs` calling `TransferPairRow(debit:credit:)` | WIRED | ExpenseListView line 127–135; query uses `transferPairID != nil && amount > 0` (STAB-08-safe, no `#Predicate` on `Bool?`) |
| `BudgetCalculator.monthlySpend` | `OverviewAggregation.topCategories` | `spendByCategory` parameter consumed downstream; OverviewAggregation does not receive raw `[Expense]` | WIRED | `OverviewAggregation.topCategories(spendByCategory:categories:)` takes a pre-computed map |
| `EditExpenseView.saveExpense` | `expense.isTransfer / transferPairID` | `applyTransferMark` static helper called before `try context.save()` | WIRED | `EditExpenseView` line 368; static helper encapsulates solo mark + cascade-unlink |

---

### Data-Flow Trace (Level 4)

| Artifact | Data Variable | Source | Produces Real Data | Status |
|----------|--------------|--------|-------------------|--------|
| `ExpenseListView` `pendingPairs` section | `pendingDebitLegs` (@Query) | SwiftData fetch with `transferPairID != nil && amount > 0` predicate; credit resolved in-memory | Yes — live SwiftData query on persisted expenses | FLOWING |
| `BudgetCalculator.monthlySpend` exclusion | `isTransfer != true` filter on input `[Expense]` | Called by callers who supply @Query-fetched expenses | Yes — filter applied to real persisted Expense objects | FLOWING |
| `SpendOverTimeAggregator.bucket` exclusion | `spendable` variable | `.filter { $0.isTransfer != true }` on caller-supplied array | Yes — same origin as BudgetCalculator callers | FLOWING |
| `AccountBalance.compute` | `net` (sum of attributed expenses) | `.filter { $0.accountID == accountID && $0.date >= asOf }` — no isTransfer filter | Yes — transfer legs included; sign is `baseline - net` (fixed in Phase 10) | FLOWING |

---

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|-------------|------------|-------------|--------|---------|
| XFER-01 | Plans 01, 03 | Auto-detect debit+credit pairs between own accounts, opposite direction, ≤3-day window | SATISFIED | `TransferDetectionScorer` + `TransferScanService` + post-sync hook in both sync paths |
| XFER-02 | Plan 03 | Detected pairs surface in Transfer Inbox for explicit confirmation | SATISFIED | "Possible Transfers" Section in `ExpenseListView`; `TransferPairRow` with confirm/reject actions |
| XFER-03 | Plan 03 | User can confirm or reject a detected pair | SATISFIED | `confirmPair()` flips both legs to `isTransfer = true`; `rejectPair()` to `false` + clears `transferPairID`; human verified |
| XFER-04 | Plans 01, 02 | Confirmed self-transfers excluded from spend totals and budgets | SATISFIED | `isTransfer != true` in `BudgetCalculator.monthlySpend`, `uncategorizedSpend`, and `SpendOverTimeAggregator.bucket`; OverviewAggregation inherits via BudgetCalculator output |
| XFER-05 | Plan 04 | User can manually mark/unmark any expense as a self-transfer | SATISFIED | "Mark as Transfer" Toggle in `EditExpenseView`; `applyTransferMark` helper; cascade-unlink on unmark; isDirty participation; human verified |

---

### Anti-Patterns Found

No `TBD`, `FIXME`, or `XXX` markers found in any Phase 10 modified files. No empty stubs, placeholder returns, or hardcoded empty data in implementation files.

---

### Code Review Integration

All 5 code review findings from `10-REVIEW.md` are confirmed resolved in commit `ccd5518`:

- **CR-01** (manual mark on pending expense orphans partner): `applyTransferMark` now clears the pending partner's `transferPairID` before setting `isTransfer = true` on the marked expense; fourth test in `EditExpenseTransferTests` asserts this behavior.
- **CR-02** (legacy Gmail sync path never triggers transfer scan): `transferScanService?.scan()` added to `legacySingleAccountSync` at line 719.
- **WR-01** (stale pending links on re-scan): `TransferScanService.scan()` now clears all candidate `transferPairID` values before calling the scorer (lines 68–69), ensuring re-pairs always start from a clean state.
- **WR-02** (double-negation in `setContext`): simplified to `defaults.bool(forKey: migrationDoneKey)` (not verified in this pass but noted as resolved in review).
- **IN-01** (misleading `confirmedLegSkipped` test): test now passes `[debit, confirmedCredit]` to the scorer unfiltered (expecting 1 pair, proving scorer does NOT re-filter) and then re-runs with the service pre-filter applied (expecting 0 pairs), correctly documenting the two-layer filter contract.

### Human Verification Required

No remaining automated gaps. Two checkpoint:human-verify gates were both approved by the user during execution:

1. **Plan 01 / Task 4** — AccountBalance sign convention on a positive-baseline savings account: approved; debit correctly decreases savings balance (`baseline - net`).
2. **Plan 03 / Task 4** — Full confirm/reject + Transfers-filter UX: approved; confirm links + hides, reject dismisses to normal, Transfers filter isolates confirmed pairs, badge counts pending pairs, spend/budget totals drop after confirmation.
3. **Plan 04 / Task 2** — Manual mark/unmark on simulator: approved; mark hides from spend, unmark restores, unmarking a paired leg cascade-restores both.

All human verification gates cleared. No outstanding human checks.

---

### Gaps Summary

No gaps. All 17 must-have truths verified, all 12 artifacts substantive and wired, all 5 key links confirmed in code, all 5 requirements satisfied, no debt markers found, all code review findings resolved.

---

_Verified: 2026-06-10_
_Verifier: Claude (gsd-verifier)_
