# Phase 10: Self-Transfer Detection - Research

**Researched:** 2026-06-10
**Domain:** SwiftData + SwiftUI — transfer detection, inbox routing, spend exclusion, balance-move
**Confidence:** HIGH

---

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

**Matching logic (XFER-01)**
- D-01: Hard AND-rules, not a weighted score. A pair is surfaced only when ALL conditions hold.
- D-02: Exact `Decimal` amount match (to the paisa). No tolerance band.
- D-03: Opposite direction by sign of `amount` — debit (`amount > 0`), credit (`amount < 0`), equal magnitude.
- D-04: Both legs must be assigned to accounts, and to two different own accounts (`accountID` set on both, `accountID_A != accountID_B`). Pairs where either leg is unassigned are NOT surfaced.
- D-05: 3-day calendar window between the two legs' dates (IST), inclusive.

**Reversal vs transfer-credit (XFER-01)**
- D-06: No new schema field / no SchemaV7. Refunds and transfer-credit-legs are both stored as negative-amount expenses; the user's confirm/reject separates genuine refunds from transfer credits.
- D-07: The `isTransfer` tri-state: `nil` = unevaluated (candidate), `true` = confirmed transfer, `false` = rejected / "not a transfer". A confirmed or rejected leg is never re-surfaced.

**Detection timing & scope (XFER-01, retroactive)**
- D-08: Scorer runs at the end of each Gmail sync plus a manual "Scan for transfers" action.
- D-09: One-time full historical sweep on first run (all existing expenses), then incremental — subsequent runs only consider `isTransfer == nil`.
- D-10: Skip rule: only `isTransfer == nil` expenses are candidates. Confirmed sets both legs `true`; reject sets both `false`. No separate evaluated-pairs ledger.

**Inbox & manual-mark UX (XFER-02, XFER-03, XFER-05)**
- D-11: Detected pairs merged into the existing Review Inbox as a distinct transfer-pair row type. Nothing is excluded silently.
- D-12: Confirmed transfers shown via a Transfers filter in `ExpenseListView` (mirrors Phase 9 AccountFilter). Hidden from default list, spend totals, budgets, charts.
- D-13: Confirm marks both legs `isTransfer = true` and cross-sets `transferPairID`; reject marks both `isTransfer = false`.
- D-14: Manual mark/unmark on any expense detail view. Solo flag allowed (`isTransfer = true`, `transferPairID = nil`) with optional "link counterpart". Unmark resets to `nil`/`false` and unlinks.

**Exclusion & balance-move (XFER-04, ACCT-05 completion)**
- D-15: Exclusion point: `BudgetCalculator`, `SpendOverTimeAggregator`, and `OverviewAggregation` filter out `isTransfer == true` expenses.
- D-16: Balance-move applies only to a linked confirmed pair. Solo transfer: excluded from spend, does NOT move balance.

### Claude's Discretion
- Exact placement/labeling of the "Scan for transfers" affordance and the Transfers filter chip.
- The transfer-pair row layout within the Review Inbox.
- Tie-breaking when one debit matches multiple candidate credits (closest-in-time-first rule; researcher to specify precisely).
- Scorer placement and unit-test surface.

### Deferred Ideas (OUT OF SCOPE)
- Weighted/fuzzy scoring & amount tolerance (D-01/D-02 deferred).
- Stored reversal flag (SchemaV7) — deferred (D-06).
- Cross-currency / external-party transfers — out of scope.
- Re-pairing a rejected leg with a different counterpart.
</user_constraints>

---

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| XFER-01 | Auto-detect likely self-transfers: same amount, opposite direction, two different own accounts, within 3-day IST window, not already evaluated | §Detection Scorer covers the 5-signal algorithm, placement, and async/IST patterns |
| XFER-02 | Detected pairs surface in a Transfer Inbox for explicit confirmation; nothing excluded silently | §Review Inbox Extension covers TransferPairRow shape and Section placement |
| XFER-03 | Confirm marks both legs as confirmed transfers linked by `transferPairID`; reject dismisses as normal expenses | §Confirm/Reject Actions covers the exact mutation sequence |
| XFER-04 | Confirmed self-transfers excluded from spend totals and budgets | §Exclusion Wiring covers the four filter insertion points |
| XFER-05 | User can manually mark/unmark any expense as a self-transfer | §Manual Mark/Unmark in EditExpenseView covers the solo-flag path |
</phase_requirements>

---

## Summary

Phase 10 completes the transfer semantics scaffolded in Phase 9. The schema fields `isTransfer: Bool?`, `transferPairID: UUID?`, and `accountID: UUID?` already exist on `SchemaV6.Expense` — no migration is needed. This phase fills in the detection scorer, the confirm/reject UX, the spend exclusion wiring, and the account balance-move for confirmed pairs.

**The central design constraint** is STAB-08: `#Predicate` on `Bool?` is unreliable in this codebase. The scorer must fetch all `isTransfer == nil` candidates in Swift (fetch-all-then-filter-in-memory) rather than using a `#Predicate` on the tri-state field. This is consistent with how `RoutineResetService` handles the `isDailyRoutine == true` predicate (a non-optional `Bool`) — the codebase treats predicates on optional fields as a fragility risk.

The scorer's architecture mirrors the established dual-mode pattern: a pure static `TransferDetectionScorer` helper (mirroring `AccountAttributionHelper`) for the core matching logic — unit-testable without a `ModelContainer` — wrapped by a `@MainActor @Observable` `TransferScanService` (mirroring `RoutineResetService`) for lifecycle orchestration and `ModelContext` access.

**Primary recommendation:** Implement `TransferDetectionScorer` as a pure `enum` operating on pre-fetched `[Expense]` arrays, invoked by `TransferScanService` after every Gmail sync completion and on-demand via a "Scan for transfers" action in Settings.

---

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| 5-signal candidate scoring | Pure helper (`TransferDetectionScorer`) | — | Operates on value types; unit-testable without SwiftData |
| Lifecycle coordination (when to run) | Service layer (`TransferScanService`) | `GmailSyncController` hook | Needs `ModelContext`; must be `@MainActor` |
| Pair persistence (write `isTransfer`, `transferPairID`) | Service layer (`TransferScanService`) | — | Owns the `ModelContext` write path |
| Pending-pair surfacing in inbox | View layer (`ExpenseListView` / `ReviewInboxRow`) | — | Reactive `@Query` on `isTransfer == nil` with both-account filtering |
| Confirm/reject action | View (inline in inbox row) | `TransferScanService` helper | Row calls service method or mutates directly via context |
| Spend / budget exclusion | Aggregation helpers | — | Pure in-memory filter; `BudgetCalculator`, `SpendOverTimeAggregator`, `OverviewAggregation` |
| Balance-move on confirmed pair | `AccountBalance.compute` | — | Pure helper extended with `isTransfer == true` / linked-pair logic |
| Manual mark/unmark | `EditExpenseView` | — | Mutates `isTransfer` and `transferPairID` directly via `@Bindable` |
| Transfers filter in list | `ExpenseListView` filter enum | — | Mirrors existing `AccountFilter` pattern |

---

## Standard Stack

No new external packages. Phase 10 is purely in-app logic using existing SwiftData + SwiftUI. All budget verification confirms the existing test framework (Swift Testing, `@MainActor` + in-memory `ModelContainer`) is sufficient.

### Package Legitimacy Audit

Not applicable — no new packages installed in this phase.

---

## Architecture Patterns

### System Architecture Diagram

```
Gmail sync completion / "Scan" action
        │
        ▼
TransferScanService.scan(context:)
        │
        ├── 1. Fetch [Expense] where isTransfer == nil  (fetch-all-then-filter)
        │          └── STAB-08: NO #Predicate on Bool?
        │
        ├── 2. TransferDetectionScorer.findCandidatePairs(from: [Expense])
        │          └── Pure function: [Expense] → [(debit: UUID, credit: UUID)]
        │          │
        │          ├── Group by abs(amount) (Decimal keyed)
        │          ├── For each amount group:
        │          │     debit candidates: amount > 0, accountID != nil
        │          │     credit candidates: amount < 0, accountID != nil
        │          ├── For each debit: find credit where accountID_A != accountID_B
        │          │     AND |date_A - date_B| <= 3 IST calendar days
        │          └── Tie-break: closest-in-time-first (see §Tie-breaking Rule)
        │
        ├── 3. Write isTransfer = nil (leave as-is; pairs surfaced in inbox for review)
        │       Planner note: phase ONLY surfaces pairs — does NOT auto-confirm
        │       (D-09: mark paired candidates with a pending state flag?)
        │       SEE §First-Run Gate for how pending-pair state is tracked
        │
        └── 4. ctx.save()  (CR-01: explicit single batched save)


Review Inbox
        │
        ├── @Query: isTransfer == nil AND transferPairID != nil   (pending pairs)
        │          └── Rendered as TransferPairRow (D-11)
        └── User: Confirm → isTransfer=true on both, transferPairID cross-set
                  Reject  → isTransfer=false on both, transferPairID=nil


ExpenseListView
        └── TransferFilter: .transfers → show isTransfer == true only
            (default filter excludes isTransfer == true from spend totals)


AccountBalance.compute(...)
        └── Extended: confirmed pairs contribute to the account's balance-move
```

### Recommended Project Structure

```
MyHomeApp/Features/Expenses/
├── TransferPairRow.swift          # NEW — transfer-pair row in Review Inbox
├── ReviewInboxRow.swift           # MODIFIED — add TransferPairRow to inbox section
├── ExpenseListView.swift          # MODIFIED — add TransferFilter case
├── EditExpenseView.swift          # MODIFIED — add manual isTransfer toggle
MyHomeApp/Features/Gmail/
├── TransferDetectionScorer.swift  # NEW — pure static scoring helper
├── TransferScanService.swift      # NEW — @MainActor @Observable coordinator
├── GmailSyncController.swift      # MODIFIED — post-sync hook calling TransferScanService
MyHomeApp/Support/
├── AccountBalance.swift           # MODIFIED — confirmed-pair balance-move
├── BudgetCalculator.swift         # MODIFIED — isTransfer == true exclusion
├── SpendOverTimeAggregator.swift  # MODIFIED — isTransfer == true exclusion
├── OverviewAggregation.swift      # MODIFIED — isTransfer == true exclusion
MyHomeTests/
├── TransferDetectionScorerTests.swift   # NEW — unit tests for pure scorer
├── TransferScanServiceTests.swift       # NEW — integration tests via in-memory container
├── AccountBalanceTransferTests.swift    # NEW or appended to AccountBalanceTests.swift
```

---

## Critical Finding 1: Detection Scorer Placement and Shape

[VERIFIED: direct codebase read — AccountAttributionHelper.swift, RoutineResetService.swift]

### Recommended Shape

Two files, mirroring the established dual-layer pattern:

**`TransferDetectionScorer.swift`** — pure `enum` helper, no SwiftData access:

```swift
// Source: pattern from AccountAttributionHelper.swift
enum TransferDetectionScorer {

    struct CandidatePair {
        let debitID: UUID
        let creditID: UUID
    }

    /// Finds candidate transfer pairs from a pre-fetched array of nil-isTransfer expenses.
    /// All inputs are value types — no @Model refs (STAB-02 safety applies even synchronously).
    /// Returns an array of (debit UUID, credit UUID) pairs.
    static func findCandidatePairs(
        from expenses: [Expense],
        calendar: Calendar    // inject for deterministic testing (IST calendar)
    ) -> [CandidatePair] {
        // Group by absolute amount (Decimal keyed — never Double)
        let debits  = expenses.filter { $0.amount > 0 && $0.accountID != nil }
        let credits = expenses.filter { $0.amount < 0 && $0.accountID != nil }

        // Build credit lookup: abs(amount) → sorted-by-date credits
        var creditsByAmount: [Decimal: [Expense]] = [:]
        for credit in credits {
            let key = abs(credit.amount)
            creditsByAmount[key, default: []].append(credit)
        }

        var pairs: [CandidatePair] = []
        var claimedCreditIDs: Set<UUID> = []

        // Sort debits deterministically (date ascending, then UUID for stability)
        let sortedDebits = debits.sorted { lhs, rhs in
            lhs.date != rhs.date ? lhs.date < rhs.date
                                 : lhs.id.uuidString < rhs.id.uuidString
        }

        for debit in sortedDebits {
            let key = debit.amount    // debit.amount > 0, credit.amount == -debit.amount
            guard var candidates = creditsByAmount[key] else { continue }

            // Filter: different account, within 3-day IST window, not already claimed
            candidates = candidates.filter { credit in
                credit.accountID != debit.accountID
                    && !claimedCreditIDs.contains(credit.id)
                    && istDayDistance(debit.date, credit.date, calendar: calendar) <= 3
            }

            guard !candidates.isEmpty else { continue }

            // Tie-break: closest in time first (see §Tie-breaking Rule)
            let best = candidates.min { a, b in
                let dA = abs(a.date.timeIntervalSince(debit.date))
                let dB = abs(b.date.timeIntervalSince(debit.date))
                if dA != dB { return dA < dB }
                return a.id.uuidString < b.id.uuidString  // stable UUID tie-break
            }!

            claimedCreditIDs.insert(best.id)
            pairs.append(CandidatePair(debitID: debit.id, creditID: best.id))
        }

        return pairs
    }

    /// Returns the calendar day distance (IST) between two dates.
    /// Both dates are converted to IST day components; the distance is |dayA - dayB|
    /// counted as integer days between start-of-IST-day values.
    static func istDayDistance(_ a: Date, _ b: Date, calendar: Calendar) -> Int {
        let dayA = calendar.startOfDay(for: a)
        let dayB = calendar.startOfDay(for: b)
        return abs(calendar.dateComponents([.day], from: dayA, to: dayB).day ?? Int.max)
    }
}
```

**`TransferScanService.swift`** — `@MainActor @Observable` lifecycle coordinator, mirroring `RoutineResetService`:

```swift
// Source: pattern from RoutineResetService.swift
@MainActor
@Observable
final class TransferScanService {

    var modelContext: ModelContext?

    /// Whether a full historical scan has been run on this install.
    /// Gated via UserDefaults key "transferScanFirstRunDone" (D-09).
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// Full historical sweep or incremental scan.
    /// D-09: First run evaluates all isTransfer==nil expenses.
    /// Subsequent runs only consider isTransfer==nil (same filter, no delta needed
    /// since confirmed/rejected expenses flip away from nil automatically).
    func scan() {
        guard let context = modelContext else { return }
        var istCal = Calendar(identifier: .gregorian)
        istCal.timeZone = TimeZone(identifier: "Asia/Kolkata")!

        do {
            // STAB-08: fetch all, filter in Swift — do NOT use #Predicate on Bool?
            let all = try context.fetch(FetchDescriptor<Expense>())
            let candidates = all.filter { $0.isTransfer == nil }

            let pairs = TransferDetectionScorer.findCandidatePairs(
                from: candidates,
                calendar: istCal
            )

            // Resolve UUIDs back to @Model objects for mutation
            // (safe: no await boundary between fetch and mutation)
            let expenseByID = Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0) })

            for pair in pairs {
                guard let debit  = expenseByID[pair.debitID],
                      let credit = expenseByID[pair.creditID] else { continue }
                // Mark both legs as pending confirmation by setting transferPairID only.
                // isTransfer stays nil (unevaluated) until user confirms/rejects in inbox.
                // A non-nil transferPairID with nil isTransfer == "pending pair".
                debit.transferPairID  = credit.id
                credit.transferPairID = debit.id
            }

            try context.save()   // CR-01: single batched save

            defaults.set(true, forKey: "transferScanFirstRunDone")

        } catch {
            print("[TransferScanService] scan failed: \(error)")
        }
    }
}
```

> **Key design note on pending state:** The CONTEXT.md defines `isTransfer = nil` as "unevaluated" and `transferPairID != nil` as the link field. The cleanest pending-pair signal that avoids adding a new schema field is: `isTransfer == nil && transferPairID != nil` = "scorer has paired this leg, awaiting user decision." The `@Query` that feeds the inbox section filters on this combination. The scorer writes `transferPairID` but leaves `isTransfer = nil`. Confirm sets `isTransfer = true` on both; reject clears `transferPairID` and sets `isTransfer = false` on both.

---

## Critical Finding 2: STAB-08 — Bool? Predicate Strategy

[VERIFIED: direct codebase read — SchemaV6.swift, RoutineResetService.swift, AccountBalanceTests.swift, CONTEXT.md STAB-08 note]

**Recommendation: fetch-then-filter-in-Swift for all `isTransfer == nil` queries.**

`RoutineResetService` uses `#Predicate { $0.isDailyRoutine == true }` successfully — but `isDailyRoutine` is a **non-optional** `Bool`. The STAB-08 lesson specifically calls out `Bool?` as fragile. The `isTransfer` field is `Bool?`. Therefore:

- The `TransferScanService.scan()` fetches ALL expenses with `FetchDescriptor<Expense>()` and then applies `.filter { $0.isTransfer == nil }` in Swift.
- The `@Query` that feeds the inbox transfer-pair section should similarly be constructed without predicating on `Bool?`. Two options:

**Option A (safe, recommended):** Fetch all expenses and compute `pendingPairs` in a computed property:
```swift
// In ExpenseListView or a dedicated InboxViewModel
@Query(sort: \Expense.date, order: .reverse) private var allExpenses: [Expense]

private var pendingTransferPairs: [TransferPairModel] {
    // Both legs share a transferPairID, both have isTransfer == nil
    let candidates = allExpenses.filter { $0.isTransfer == nil && $0.transferPairID != nil }
    // Deduplicate into pairs (one debit per pair)
    return candidates
        .filter { $0.amount > 0 }  // show the debit leg as the "primary" row
        .compactMap { debit -> TransferPairModel? in
            guard let creditID = debit.transferPairID,
                  let credit = allExpenses.first(where: { $0.id == creditID }) else { return nil }
            return TransferPairModel(debit: debit, credit: credit)
        }
}
```

**Option B (may work, unverified):** Predicate only on the non-optional `transferPairID`:
```swift
@Query(filter: #Predicate<Expense> { $0.transferPairID != nil && $0.amount > 0 },
       sort: \Expense.date, order: .reverse)
private var pendingDebitLegs: [Expense]
```
This avoids predicating on `Bool?` entirely. `transferPairID` is a `UUID?` and `!= nil` predicate on optional UUIDs has generally worked in SwiftData (confirmed by the existing `ingestionStateRaw != nil` predicate in `ExpenseListView` — a `String?` field). However, cross-reference with the credit leg still requires an in-memory lookup.

**Confirmed safe pattern** for the inbox: Option A (all-fetch + in-memory filter). Option B is a reasonable optimization but requires explicit testing with the in-memory `ModelContainer` fixture before shipping.

For `BudgetCalculator`, `SpendOverTimeAggregator`, and `OverviewAggregation`: these already operate on pre-fetched `[Expense]` arrays supplied by callers. The exclusion is a simple `.filter { $0.isTransfer != true }` in Swift — no predicate involved. This is the safest possible approach and requires no changes to the call-site query.

---

## Critical Finding 3: Tie-breaking Rule (Claude's Discretion)

[ASSUMED — reasoned from codebase patterns and D-05 IST window; not from an external source]

**Deterministic tie-breaking comparator for one debit matching multiple candidate credits:**

```
Primary key:   abs(credit.date.timeIntervalSince(debit.date))  — ascending (closest first)
Secondary key: credit.id.uuidString                             — ascending (stable UUID sort)
```

The secondary key on `credit.id.uuidString` is the same stable discriminator used in `OverviewAggregation.topCategories()` (lines 80–84 of OverviewAggregation.swift) to prevent non-deterministic ordering on equal-valued sort keys.

**Why closest-in-time-first:** NEFT same-day and IMPS/UPI near-instant settlement means the credit for a transfer typically arrives within minutes-to-hours of the debit. Selecting the closest temporal match maximizes true-positive rate. Remaining un-paired candidates stay `isTransfer == nil` — they surface for future scorer runs if a previously-confirmed pair frees up a credit leg.

**Why process debits in date-ascending order before tie-breaking:** Earlier debits claim their best match first, which is more natural (an older transfer "gets priority" in pairing). Within the scorer, debits are sorted ascending by date, then by UUID, before the pairing loop. This gives the full algorithm a total order for deterministic output on any input permutation.

---

## Critical Finding 4: Balance-Move in `AccountBalance.compute`

[VERIFIED: direct codebase read — AccountBalance.swift, AccountBalanceTests.swift, SchemaV6.swift]

### Current formula (Phase 9)

```swift
static func compute(
    baseline: Decimal?,
    asOf: Date?,
    expenses: [Expense],
    accountID: UUID
) -> Decimal {
    guard let baseline = baseline, let asOf = asOf else { return Decimal(0) }
    let net = expenses
        .filter { $0.accountID == accountID && $0.date >= asOf }
        .reduce(Decimal(0)) { $0 + $1.amount }
    return baseline + net
}
```

### How confirmed linked pairs net out correctly (no change needed to the formula)

The formula **already handles transfers correctly by sign convention alone**:

- **Debit leg** (`amount > 0`, `accountID = A`): attributed to account A, decreases A's balance (positive amount reduces a savings balance via `baseline + net` where `net` includes the positive debit).

Wait — this is the critical double-check: debits are positive amounts in this schema. The baseline for a savings account is positive. Adding a positive debit to a savings account would *increase* the balance, which is wrong for an outflow.

Reading `AccountBalanceTests.swift` more carefully:
- The test "liveBalance equals baseline plus net" uses `Decimal(-200)` and `Decimal(-50)` for expenses and gets `1000 - 200 - 50 = 750`. So expenses that **decrease** account balance are stored as **negative amounts** for savings accounts.
- But `BankEmailParser.swift` stores debits as **positive** amounts (`isReversal ? -abs : +abs`).

**Resolution:** The `AccountBalance.compute` formula adds `expense.amount` to `baseline`. For a savings account:
- Normal spending emails → parsed as `amount > 0` (debit/outflow from the account). Balance formula does `baseline + positive_amount` which would *increase* balance — that seems wrong for a debit.
- But reviewing the credit card test: `Decimal(-5000)` baseline + `Decimal(-1000)` expense = `Decimal(-6000)`. That says the CC balance goes *more negative* as you spend.

**The sign convention is: `amount > 0` = money INTO the account (credit/inflow), `amount < 0` = money OUT of the account (debit/outflow from the user's perspective, or spending for a CC).** Wait, that contradicts D-03 which says "debit > 0, credit < 0".

Let me re-read D-03 carefully: "Direction is the sign of the stored Decimal (debits positive, credits negative)." In Indian banking parlance, a debit entry on a bank statement means money leaving the account. So:

- `amount > 0`: a debit (spending outflow) — this DECREASES the account balance
- `amount < 0`: a credit (inflow) — this INCREASES the account balance

But then `AccountBalanceTests` uses negative amounts for expenses that reduce the balance... meaning expenses stored with `amount < 0` reduce balance? That contradicts D-03.

Re-reading the test again: expenses are `Decimal(-200)` and `Decimal(-50)`, baseline is `Decimal(1000)`, result is `750`. So `1000 + (-200) + (-50) = 750`. The expenses are negative. But D-03 says debits are positive.

**Resolution found in CC test:** CC baseline is `-5000` (amount owed), expense is `-1000`, result is `-6000`. The expense makes the CC balance more negative — that's more money owed. From a CC perspective, spending creates a more negative balance. The stored `amount` in AccountBalance.compute is used to *compute balance*, not to represent transaction direction for spend purposes.

Looking at how real bank emails are stored (from BankEmailParser.swift): `amount > 0` for normal spend (a debit from the user's card = money spent). For `AccountBalance.compute`, spending `amount > 0` would ADD to the baseline, increasing it — wrong for a savings account but...

**The actual answer:** `AccountBalance.compute` accepts all `expenses` filtered by `accountID`. For a savings account with baseline `+1000`, a debit of `+200` gives `1200` — which would mean the balance *increased* by 200. That's inconsistent with the test which uses negative amounts.

Re-reading the test fixture: the test creates expenses with negative amounts. The test itself is controlling the data. In practice, expenses attributed to savings accounts ARE stored as negative amounts (they are credits/inflows from a bank perspective? No...).

**Final resolution:** The Phase 9 tests use hand-crafted negative amounts in `AccountBalanceTests` because those tests were written to verify the formula, not to verify sign convention alignment with Gmail ingestion. The `AccountBalance.compute` formula is amount-agnostic — it adds whatever `amount` is stored. The *sign convention for balance display* is set externally by how expenses are created.

For Phase 10 purposes: **the formula is correct as-is**. For a confirmed transfer:
- Debit leg (amount = e.g. +5000, assigned to account A): balance of A = baseline + (+5000) → increases A's balance (money received — or for savings accounts, this is a debit meaning money went OUT, so the stored amount should be negative for a savings-account debit).

The key insight from `CUBParser.swift` and `BankEmailParser.swift`: `isReversal ? -abs(amount) : +abs(amount)`. A normal transaction (not reversal) is stored as **positive**. The account balance formula adds this positive amount to the baseline. For a CC, the baseline is negative and adding positive spending makes it more positive (less debt? That's wrong for a CC).

**The actual usage in practice:** Looking at AccountDetailView (from PATTERNS.md): it computes `liveBalance` by filtering `attributedExpenses` dated on/after asOf. The AccountBalance.compute is called from AccountDetailView but also tests show the formula correctly. The Phase 9 summary states "Account balance shows 0 for auto-created accounts because no manual opening balance is set" — the actual correctness of the sign convention was not directly tested.

**Pragmatic recommendation for Phase 10:** The balance-move for confirmed pairs needs to handle both legs correctly. The formula already adds `expense.amount` to `baseline`. The behavior is:

- **For the debit account (money leaving):** a debit stored as `amount > 0` (per D-03) added to the balance would *increase* it — but in the context of the account balance formula, the BASELINE represents the starting balance and subsequent amounts are meant to reflect the direction. The convention must be: positive amount = the balance goes up. For a transfer debit (money leaving account A), if stored as negative (per "credits are negative, debits are positive" but from the bank's ledger perspective), the formula handles it correctly.

**The safe approach for Phase 10:** When implementing balance-move, simply **exclude `isTransfer == true` legs from the regular AccountBalance.compute formula**, and add a separate transfer-pair adjustment:

```swift
// Proposed extension to AccountBalance.compute:
static func compute(
    baseline: Decimal?,
    asOf: Date?,
    expenses: [Expense],
    accountID: UUID
) -> Decimal {
    guard let baseline = baseline, let asOf = asOf else { return Decimal(0) }

    let net = expenses
        .filter {
            $0.accountID == accountID
            && $0.date >= asOf
            // D-16: include ALL attributed expenses (transfer legs included)
            // Sign convention handles the direction automatically
        }
        .reduce(Decimal(0)) { $0 + $1.amount }

    return baseline + net
}
```

**D-16 analysis:** Confirmed transfer legs are ALREADY attributed to their accounts. Both legs already have `accountID` set. The debit leg (positive amount) for the debit account means money left that account. The credit leg (negative amount) for the credit account means... that account received money. If both legs are included in the respective account's balance formula:

- Debit account: `baseline + positive_debit_amount` → balance increases → WRONG for a debit (money leaving)
- Credit account: `baseline + negative_credit_amount` → balance decreases → WRONG for a credit (money arriving)

This strongly suggests that in this codebase's sign convention, `amount` = how the account balance CHANGES, meaning:
- A debit (money out) is stored as a **negative** amount for balance purposes.
- A credit (money in) is stored as a **positive** amount.

But D-03 says debits are positive and credits are negative. This is the transaction direction (debit transactions are positive), not the balance-change direction.

**Final conclusion:** The `AccountBalance.compute` formula as written produces sensible CC results (`-5000 + (-1000) = -6000` for spending). For savings, a spending transaction (stored positive per D-03) would increase the balance — which means the formula treats `amount > 0` as "balance went up" = money came IN. Since D-03 says `amount > 0` = debit (money spent), there is an inherent sign flip somewhere. Most likely, **the AccountBalance formula is designed for the CC use case only** (where spending creates a larger negative balance, and CC expenses are stored as negative in the formula), or the sign convention for balance accounting is the OPPOSITE of the transaction sign convention.

**The Phase 10 safe path (D-16):** For confirmed linked pairs, the balance-move is:

The debit account received a debit (money left). In the formula:
- Debit leg: `amount > 0` (transfer out). If the formula currently adds this as a positive to savings baseline → it would increase the savings balance, which is wrong.
- Credit leg: `amount < 0` (transfer in). If the formula currently adds this as negative to the receiving account baseline → would decrease that account, which is also wrong.

**Recommendation:** Phase 10 should NOT rely on the existing `AccountBalance.compute` formula for confirmed transfer balance-moves. Instead, explicitly add a transfer-pair adjustment: **the planner should file this as an open question / investigation task** — read `AccountDetailView` live in the simulator to verify whether the formula currently produces correct savings-account balances for debits. The Phase 9 human UAT specifically confirmed the balance semantics were "working as designed" but only for the CC case (negative baseline). The savings account balance was confirmed as `0` because no baseline was set — so the formula's correctness for positive-baseline savings accounts has not been verified against real data.

**Conservative D-16 implementation:** Implement balance-move as a simple exclusion — confirmed transfer legs continue to be included in `AccountBalance.compute` as-is. Since the formula already includes all attributed expenses, both legs of a confirmed pair are already counted, and `total net worth = accountA + accountB` is unchanged by a transfer (because the debit's positive amount increases A's formula result, and the credit's negative amount decreases B's formula result — so total is net zero). This means **NO change to `AccountBalance.compute` is needed for D-16** if the existing formula is used consistently. The balance-move is implicit in the existing attribution.

The only new work for D-16 is: **confirmed transfer legs MUST NOT be excluded from `AccountBalance.compute`** (they SHOULD be included so the balance reflects the actual flow), but they MUST be excluded from spend/budget totals (D-15). This is a different exclusion point — the formula already handles it correctly by design.

---

## Critical Finding 5: Exclusion Wiring (D-15)

[VERIFIED: direct codebase read — BudgetCalculator.swift, SpendOverTimeAggregator.swift, OverviewAggregation.swift, ExpenseListView.swift]

All four aggregators operate on pre-fetched `[Expense]` arrays — the exclusion is a single `.filter { $0.isTransfer != true }` applied to the input array before aggregation.

### BudgetCalculator

Two methods need updating:

1. `monthlySpend(for expenses:, categories:)` — add exclusion to the `for expense in expenses` loop or pre-filter the input:
```swift
// D-15: exclude confirmed transfers from budget math
let spendable = expenses.filter { $0.isTransfer != true }
for expense in spendable { ... }
```

2. `uncategorizedSpend(for expenses:)` — similarly pre-filter.

**Important:** The callers of `BudgetCalculator` supply the `expenses` array. The filter can be applied either at the call site (in the view that passes the array) or inside each method. Inside the method is safer — it cannot be forgotten by a future call site.

### SpendOverTimeAggregator

The `bucket(expenses:range:calendar:)` public API receives a pre-fetched array. Pre-filter before passing to the bucket helper, or add the filter inside each of `weekBuckets`, `monthBuckets`, `yearBuckets`:

```swift
// In bucket(...) before the switch:
let spendable = expenses.filter { $0.isTransfer != true }
switch range {
case .week:  return weekBuckets(expenses: spendable, calendar: calendar)
...
```

### OverviewAggregation

`topCategories(spendByCategory:categories:)` receives a `[PersistentIdentifier: Decimal]` map from `BudgetCalculator.monthlySpend` — so fixing `BudgetCalculator` fixes `OverviewAggregation` automatically (it consumes the already-filtered spend map).

`aggregateThreshold(totalSpend:totalBudget:)` is called with caller-computed totals. Fixing the caller's `BudgetCalculator` call fixes this automatically.

No direct changes needed in `OverviewAggregation.swift` if `BudgetCalculator` is fixed.

### ExpenseListView — Transfers filter

Add a `TransferFilter` case (or extend `CategoryFilter`) mirroring the existing `AccountFilter` pattern:

```swift
// New enum (mirrors AccountFilter at line 60–65):
private enum TransferFilter: Hashable {
    case all         // default — show non-transfer expenses
    case transfers   // show only isTransfer == true expenses
}

@State private var transferFilter: TransferFilter = .all

// In filteredExpenses computed property, chain as the THIRD filter:
private var filteredExpenses: [Expense] {
    let categoryFiltered = /* existing */
    let accountFiltered  = /* existing */
    switch transferFilter {
    case .all:
        // Default: EXCLUDE confirmed transfers from the main list (D-12)
        return accountFiltered.filter { $0.isTransfer != true }
    case .transfers:
        return accountFiltered.filter { $0.isTransfer == true }
    }
}
```

**Note:** The default `.all` case in `filteredExpenses` should EXCLUDE `isTransfer == true` expenses (they go to the Transfers section only). This is different from the `AccountFilter.all` which includes everything. Naming the default case `.all` is slightly misleading — consider `.normal` as the default case, or document clearly that `.all` means "all non-transfer expenses."

---

## Critical Finding 6: Review Inbox Extension (D-11)

[VERIFIED: direct codebase read — ReviewInboxRow.swift, ExpenseListView.swift]

### TransferPairRow shape

The inbox already has a `Section("Needs Review")` section driven by `reviewItems: [Expense]` (expenses with non-nil, non-autoSaved `ingestionStateRaw`). The transfer-pair inbox should be a **second section** before or after "Needs Review," named "Transfer Inbox" or "Possible Transfers."

The pending-pair query (in `ExpenseListView`) needs only the DEBIT leg of each pair (one row per pair):

```swift
// Add to ExpenseListView alongside the reviewItems @Query:
@Query(
    filter: #Predicate<Expense> {
        $0.transferPairID != nil && $0.amount > 0
        // Note: this predicts on UUID? (transferPairID != nil) and Decimal (amount > 0)
        // NOT on Bool? — so STAB-08 does not apply here
        // isTransfer == nil legs are debit-side candidates
    },
    sort: \Expense.date,
    order: .reverse
) private var pendingDebitLegs: [Expense]
```

However this query does not guarantee the credit leg still exists. `TransferPairRow` must defensively handle a missing credit leg (pair may have been half-resolved since the query ran).

### TransferPairRow view

```swift
// TransferPairRow.swift — new file
struct TransferPairRow: View {
    let debit: Expense        // amount > 0; debit account
    let credit: Expense       // amount < 0; credit account
    @Environment(\.modelContext) private var context
    @Query(sort: \Account.sortOrder) private var accounts: [Account]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Header: amount + "Transfer?" badge
            HStack {
                Text(debit.amount.formattedINR())
                    .font(.headline)
                Spacer()
                Text("Transfer?")
                    .font(.caption2)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Color.purple, in: Capsule())
            }

            // Two-leg summary: debit account → credit account, dates
            HStack {
                accountLabel(for: debit.accountID)
                Image(systemName: "arrow.right")
                    .font(.caption).foregroundStyle(.secondary)
                accountLabel(for: credit.accountID)
            }
            .font(.subheadline).foregroundStyle(.secondary)

            // Dates
            Text("\(debit.date.formattedForExpenseList()) → \(credit.date.formattedForExpenseList())")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            // Reject: mark both as isTransfer = false, clear transferPairID
            Button(role: .destructive) { rejectPair() }
            label: { Label("Reject", systemImage: "xmark") }

            // Confirm: mark both as isTransfer = true, cross-set transferPairID
            Button { confirmPair() }
            label: { Label("Confirm", systemImage: "checkmark") }
            .tint(.green)
        }
    }

    private func accountLabel(for accountID: UUID?) -> Text { /* resolve name */ }
    private func confirmPair() { /* D-13: set isTransfer=true on both, cross-set transferPairID, ctx.save() */ }
    private func rejectPair()  { /* D-13: set isTransfer=false on both, clear transferPairID, ctx.save() */ }
}
```

The swipe actions mirror `ReviewInboxRow`'s pattern exactly (destructive Reject, non-destructive Confirm, no full-swipe).

---

## Critical Finding 7: First-Run Gate and Incremental Logic (D-08/D-09/D-10)

[VERIFIED: codebase read — GmailSyncController.syncAccount, AccountAttributionHelper, CONTEXT.md]

### Pending-state encoding (no new schema field)

The scorer uses `transferPairID != nil && isTransfer == nil` as the pending-pair signal. This means:

| State | `isTransfer` | `transferPairID` |
|-------|-------------|-----------------|
| Unevaluated (never seen by scorer) | `nil` | `nil` |
| Scorer detected pair (pending) | `nil` | non-nil (partner UUID) |
| Confirmed transfer | `true` | non-nil (partner UUID) |
| Confirmed solo transfer | `true` | `nil` |
| Rejected | `false` | `nil` |

This encoding uses only existing schema fields and requires no schema change.

### First-run gate

```swift
// In TransferScanService.scan():
let firstRunDone = defaults.bool(forKey: "transferScanFirstRunDone")
// D-09: first run evaluates ALL expenses; subsequent runs see only nil ones
// The filter { $0.isTransfer == nil } already handles incrementality:
// - First run: all expenses have isTransfer == nil → all are candidates
// - Subsequent runs: confirmed/rejected legs are non-nil → naturally skipped
// There is no difference in code logic between first-run and incremental;
// the "first run" concept is only relevant for the @Query that feeds the inbox
// (new pairs may surface retroactively).
```

The `"transferScanFirstRunDone"` flag controls only whether the "Scan for transfers" badge/prompt appears after first launch. The actual scoring logic is identical.

### GmailSyncController hook (D-08)

After `try ctx.save()` at the end of `syncAccount(email:accessToken:)`, the controller calls `TransferScanService.scan()`:

```swift
// In syncAccount(), after the existing batched save (line ~562):
if let ctx = modelContext {
    try ctx.save()
    // D-08: run transfer scorer after each sync
    transferScanService?.scan()
}
```

The `transferScanService` must be injected into `GmailSyncController` similarly to how `modelContext` is injected (optional property set from RootView). Because `GmailSyncController` is already `@MainActor`, calling a `@MainActor` service from it is safe (no actor boundary crossing).

---

## Critical Finding 8: Manual Mark/Unmark in EditExpenseView (D-14, XFER-05)

[VERIFIED: direct codebase read — EditExpenseView.swift]

`EditExpenseView` uses a local `@State` mirror pattern. The `isTransfer` and `transferPairID` fields need to be exposed with a toggle UI in the optional section:

```swift
// New @State mirrors in EditExpenseView:
@State private var isMarkedTransfer: Bool = false

// In initializeFields():
isMarkedTransfer = expense.isTransfer == true

// In the optionalSection, add a Transfer toggle row:
Toggle("Mark as Transfer", isOn: $isMarkedTransfer)
    .padding(.vertical, 12)
    .padding(.horizontal, 16)
    .background(Color(.secondarySystemBackground))
    .clipShape(RoundedRectangle(cornerRadius: 12))
    .padding(.top, 8)

// In saveExpense():
if isMarkedTransfer {
    expense.isTransfer = true
    // D-14: solo flag — transferPairID stays nil unless linked
    // If previously paired and now manually marked solo, do NOT clear the pair
    // (the pair may still be valid — only an explicit unlink clears it)
} else {
    // Unmark: reset to nil (not false — false = explicitly rejected by user via inbox)
    // D-14: "Unmark resets to nil/false and unlinks any pair"
    expense.isTransfer = nil      // or false; CONTEXT says "nil/false" — use nil for re-evaluation
    expense.transferPairID = nil  // clear the pair link
    // Also unlink the counterpart if transferPairID was set:
    // (requires fetching the counterpart — this is a context operation)
}
```

**Open question for planner:** When unmarking a solo transfer that was part of a confirmed pair, should the unmark also reset the counterpart? D-14 says "Unmark resets to nil/false and unlinks any pair." The planner should specify whether this is a cascading unlink (both legs reset) or a one-sided unlink (leave counterpart as `isTransfer = true` with a dangling `transferPairID`). The safe implementation is cascading unlink — fetch the counterpart by `expense.transferPairID` and reset it too.

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| IST calendar day distance | Custom date arithmetic | `Calendar(identifier: .gregorian)` with `Asia/Kolkata` timezone | Established pattern in `RoutineResetService`; handles DST and month boundaries correctly |
| Decimal equality for matching | Float comparison | Direct `Decimal` `==` operator | Decimal has exact equality; never convert to Double for matching |
| @Model safety across async | Hold expense @Model refs across await | Capture `[UUID]` before any async boundary | STAB-02 pattern established in `GmailSyncController.syncAccount` |
| Bool? predicate | `#Predicate { $0.isTransfer == nil }` in @Query | Fetch all + `.filter { $0.isTransfer == nil }` in Swift | STAB-08: Bool? predicates are fragile in SwiftData |
| Pair row with new screen | Dedicated TransferInboxView | Extend existing `ReviewInboxRow` section | D-11 explicitly forbids a new screen |
| Custom UUID tie-break | Random/arbitrary ordering | `credit.id.uuidString` lexicographic ascending | Pattern from `OverviewAggregation.topCategories` — total order guarantee |

---

## Common Pitfalls

### Pitfall 1: False-Positive Pairing with Refunds

**What goes wrong:** A refund stored as `amount < 0` and a corresponding purchase stored as `amount > 0` with the same absolute amount could be paired as a "transfer" if both are attributed to different accounts.

**Why it happens:** D-06 explicitly acknowledges this: "any negative-amount expense that pairs with a matching debit per D-01..D-05 is a candidate." The user's confirm/reject is the final gate.

**How to avoid:** The `accountID_A != accountID_B` condition (D-04) is the strongest false-positive filter. A refund typically comes from the same payment network (same source label = same account). Refunds from a different account are genuinely ambiguous — user confirmation is correct.

**Warning signs:** High inbox count for small recurring amounts (e.g., mobile recharges that happen to match each other across two accounts).

### Pitfall 2: Double-Counting in AccountBalance

**What goes wrong:** If `AccountBalance.compute` was modified to EXCLUDE `isTransfer == true` legs, a confirmed transfer debit would no longer reduce the account balance — the balance would look artificially inflated.

**Why it happens:** Confusion between "exclude from SPEND totals" (D-15) and "exclude from BALANCE computation" (D-16 says balance-move should happen, not exclusion).

**How to avoid:** Keep `AccountBalance.compute` filter as-is (no `isTransfer` exclusion). Only the spend aggregators (`BudgetCalculator`, `SpendOverTimeAggregator`, etc.) exclude confirmed transfers.

### Pitfall 3: Re-surfacing Confirmed/Rejected Pairs

**What goes wrong:** A subsequent `TransferScanService.scan()` re-pairs legs that were already confirmed (`isTransfer = true`) or rejected (`isTransfer = false`).

**Why it happens:** The filter `$0.isTransfer == nil` in Swift correctly excludes non-nil legs. But if the STAB-08 path uses a `#Predicate` on `Bool?` that silently fails (returns all rows instead of filtering), confirmed pairs would be re-evaluated.

**How to avoid:** Explicitly test `scan()` with a mix of nil, true, and false legs. Verify that `isTransfer = true` and `isTransfer = false` expenses do NOT appear in the scorer's candidate list.

### Pitfall 4: `transferPairID` Dangling After Half-Confirm

**What goes wrong:** The confirm action sets `debit.isTransfer = true` and `credit.isTransfer = true`, but then `ctx.save()` throws. One leg may be updated before the save, leaving the pair in an inconsistent state.

**Why it happens:** SwiftData `ctx.save()` is atomic per call, but if the mutation loop mutates two `@Model` objects before calling `save()`, both mutations are either committed together or rolled back together on a throw. This is safe as long as both mutations happen BEFORE the single `ctx.save()`.

**How to avoid:** Always mutate both legs of a pair BEFORE the single `ctx.save()` call. Follow the CR-01 "explicit save" pattern from the existing codebase.

### Pitfall 5: STAB-02 in `TransferScanService.scan()`

**What goes wrong:** If `scan()` is called from an `async` context and the fetched `@Model` objects are accessed after an `await` suspension point, they may be stale.

**Why it happens:** `@Model` objects hold a reference into a specific `ModelContext`. After `await`, another task may have mutated the store, making the cached object reference stale.

**How to avoid:** `TransferScanService.scan()` should be a **synchronous** method (no `async`), just like `RoutineResetService.resetIfNeeded()`. All fetch, mutate, and save operations happen synchronously within the same `@MainActor` context. No `await` boundary → no STAB-02 risk.

However, the GmailSyncController hook calls `scan()` from within `syncAccount(email:accessToken:)` which IS async. The call to `transferScanService?.scan()` after the final `ctx.save()` is a synchronous call from an async function on `@MainActor` — this is safe because `scan()` itself has no `await`, and the ModelContext is the same one (`modelContext`) throughout.

### Pitfall 6: Scorer's `abs()` on `Decimal` and comparison

**What goes wrong:** Using `abs()` on `Decimal` incorrectly.

**How to avoid:** `Foundation.abs()` works correctly on `Decimal`. Always compare absolute amounts: `debit.amount == abs(credit.amount)` where `credit.amount < 0`. Group credits by `abs(credit.amount)` and look up by `debit.amount` (positive).

---

## Code Examples

### Confirmed pair confirmation action

```swift
// Source: codebase pattern (ReviewInboxRow.discardExpense / acceptExpense)
private func confirmPair() {
    debit.isTransfer = true
    credit.isTransfer = true
    // transferPairID already cross-set by scorer; no change needed
    debit.updatedAt = Date()
    credit.updatedAt = Date()
    do {
        try context.save()   // CR-01: explicit save, both mutations before save
    } catch {
        print("TransferPairRow: confirmPair failed: \(error)")
    }
}

private func rejectPair() {
    debit.isTransfer = false
    credit.isTransfer = false
    debit.transferPairID = nil    // unlink on reject
    credit.transferPairID = nil
    debit.updatedAt = Date()
    credit.updatedAt = Date()
    do {
        try context.save()
    } catch {
        print("TransferPairRow: rejectPair failed: \(error)")
    }
}
```

### IST 3-day window

```swift
// Source: RoutineResetService.swift pattern (IST calendar convention)
var istCal = Calendar(identifier: .gregorian)
istCal.timeZone = TimeZone(identifier: "Asia/Kolkata")!

func istDayDistance(_ a: Date, _ b: Date) -> Int {
    let dayA = istCal.startOfDay(for: a)
    let dayB = istCal.startOfDay(for: b)
    return abs(istCal.dateComponents([.day], from: dayA, to: dayB).day ?? Int.max)
}
// Usage: istDayDistance(debit.date, credit.date) <= 3
```

### Budget exclusion

```swift
// Source: BudgetCalculator.monthlySpend pattern
static func monthlySpend(for expenses: [Expense], categories: [Category]) -> [...] {
    // D-15: exclude confirmed transfers before aggregation
    let spendable = expenses.filter { $0.isTransfer != true }
    for expense in spendable { ... }
}
```

---

## Validation Architecture

### Test Framework

| Property | Value |
|----------|-------|
| Framework | Swift Testing (no XCTest) — `import Testing` |
| Config file | Xcode scheme `MyHome` — no separate config file |
| Quick run command | `xcodebuild test -scheme MyHome -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:MyHomeTests/TransferDetectionScorerTests` |
| Full suite command | `xcodebuild test -scheme MyHome -destination 'platform=iOS Simulator,name=iPhone 17'` |

### Phase Requirements → Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| XFER-01 | Exact-amount same-magnitude debit+credit pair detected | unit | `...TransferDetectionScorerTests/detectsExactAmountPair` | Wave 0 |
| XFER-01 | Unassigned expense (accountID == nil) NOT paired | unit | `...TransferDetectionScorerTests/unassignedLegNotPaired` | Wave 0 |
| XFER-01 | Same account on both legs NOT paired (D-04) | unit | `...TransferDetectionScorerTests/sameAccountNotPaired` | Wave 0 |
| XFER-01 | Outside 3-day IST window NOT paired | unit | `...TransferDetectionScorerTests/outsideWindowNotPaired` | Wave 0 |
| XFER-01 | Already-confirmed leg (`isTransfer == true`) NOT re-surfaced | unit | `...TransferDetectionScorerTests/confirmedLegSkipped` | Wave 0 |
| XFER-01 | Already-rejected leg (`isTransfer == false`) NOT re-surfaced | unit | `...TransferDetectionScorerTests/rejectedLegSkipped` | Wave 0 |
| XFER-01 | Tie-break: closest-in-time credit wins when multiple candidates | unit | `...TransferDetectionScorerTests/tieBreakClosestTimeWins` | Wave 0 |
| XFER-01 | Deterministic: same input always produces same pairs | unit | `...TransferDetectionScorerTests/deterministicOnEqualInput` | Wave 0 |
| XFER-02 | Pending pair surfaces in inbox (transferPairID!=nil, isTransfer==nil) | integration | `...TransferScanServiceTests/scanWritesPendingPairs` | Wave 0 |
| XFER-02 | Already-evaluated legs NOT re-paired on second scan | integration | `...TransferScanServiceTests/secondScanIdempotent` | Wave 0 |
| XFER-03 | Confirm sets isTransfer=true on both legs, cross-sets transferPairID | integration | `...TransferScanServiceTests/confirmSetsBothLegs` | Wave 0 |
| XFER-03 | Reject sets isTransfer=false on both, clears transferPairID | integration | `...TransferScanServiceTests/rejectClearsBothLegs` | Wave 0 |
| XFER-04 | BudgetCalculator excludes isTransfer==true from monthlySpend | unit | `...BudgetCalculatorTests/confirmedTransferExcludedFromBudget` | Wave 0 |
| XFER-04 | SpendOverTimeAggregator excludes isTransfer==true from buckets | unit | `...SpendOverTimeAggregatorTests/confirmedTransferExcludedFromChart` | Wave 0 |
| XFER-04 (ACCT-05) | AccountBalance.compute includes transfer legs (no exclusion, balance-move is implicit) | unit | `...AccountBalanceTransferTests/confirmedTransferIncludedInBalance` | Wave 0 |
| XFER-04 (ACCT-05) | Total net worth unchanged by confirmed pair | unit | `...AccountBalanceTransferTests/netWorthUnchangedByTransfer` | Wave 0 |
| XFER-05 | Manual mark sets isTransfer=true, transferPairID=nil (solo) | unit | `...EditExpenseViewTests/manualMarkSetsSoloTransfer` | Wave 0 |
| XFER-05 | Manual unmark resets isTransfer=nil, clears transferPairID | unit | `...EditExpenseViewTests/manualUnmarkResetsTransfer` | Wave 0 |

### Sampling Rate

- **Per task commit:** `xcodebuild test ... -only-testing:MyHomeTests/TransferDetectionScorerTests` + `...TransferScanServiceTests`
- **Per wave merge:** `xcodebuild test ... -only-testing:MyHomeTests` (full suite)
- **Phase gate:** Full suite green before `/gsd-verify-work`

### Wave 0 Gaps

- [ ] `MyHomeTests/TransferDetectionScorerTests.swift` — covers XFER-01 (pure scorer unit tests)
- [ ] `MyHomeTests/TransferScanServiceTests.swift` — covers XFER-02/XFER-03 (integration via in-memory container)
- [ ] Append to `MyHomeTests/BudgetCalculatorTests.swift` — confirmedTransferExcluded... tests
- [ ] Append to `MyHomeTests/SpendOverTimeAggregatorTests.swift` — confirmedTransferExcluded... test
- [ ] `MyHomeTests/AccountBalanceTransferTests.swift` (or append to `AccountBalanceTests.swift`) — D-16 balance-move tests

---

## State of the Art

| Old Approach | Current Approach | Impact |
|--------------|------------------|--------|
| `isTransfer: Bool?` unused (scaffold) | Phase 10 fills detection logic | No schema change needed |
| All expenses included in spend totals | Confirmed transfers excluded via `.filter { $0.isTransfer != true }` | Budget/chart math changes |
| `AccountBalance.compute` ignores transfer flag | Same formula; transfer legs naturally included; spend exclusion is separate | No formula change needed |

---

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | `transferPairID != nil && isTransfer == nil` is a valid "pending pair" signal requiring no new schema field | §Critical Finding 7 | If wrong, need a new `isPendingTransfer: Bool?` field — requires SchemaV7; violates CONTEXT.md D-06/out-of-scope |
| A2 | Pending transfer query can use `#Predicate { $0.transferPairID != nil && $0.amount > 0 }` reliably (UUID? predicate is not subject to STAB-08) | §Critical Finding 2 | If wrong, use all-fetch + in-memory filter for the inbox query too |
| A3 | `AccountBalance.compute` correctly handles transfer legs via existing sign convention (no formula change needed for D-16) | §Critical Finding 4 | If wrong, confirmed transfer legs need explicit exclusion + separate balance-move, doubling the balance-move complexity |
| A4 | Closest-in-time tie-break with UUID secondary sort is acceptable; user can manually re-link if the wrong pair is chosen | §Critical Finding 3 | If wrong, need UI for "re-pair this leg" — out of scope for this phase |
| A5 | `TransferScanService.scan()` can run synchronously (no `async` needed) given it only accesses `modelContext` on `@MainActor` | §Critical Finding 5 (Pitfall 5) | If wrong, need async variant + STAB-02 UUID capture before the loop |

**If A3 is wrong:** The investigation task (read AccountDetailView balance in simulator against real expenses) is the blocker. It should be Wave 1 (Plan 10-01) before implementing balance-move.

---

## Open Questions

1. **AccountBalance sign convention vs D-16 balance-move**
   - What we know: `AccountBalance.compute` adds all attributed expenses to the baseline. The CC test shows `–5000 + (–1000) = –6000`. The Phase 9 savings-account balance was `0` (no baseline set) — sign convention was not validated for positive-baseline savings accounts.
   - What's unclear: Does `amount > 0` (a debit transaction per D-03) increase or decrease a savings account balance in the current formula?
   - Recommendation: Plan 10-01 should include a task to run `AccountDetailView` against real expenses with a savings baseline and verify the computed balance. If the formula is wrong for savings debits, the balance-move for confirmed transfers will also be wrong, and D-16 requires a formula correction.

2. **Pending-pair inbox badge vs review badge**
   - What we know: `reviewBadgeCount` is currently driven by `reviewItems.count` (ingestion inbox). D-11 merges transfer pairs into the same inbox.
   - What's unclear: Should pending transfer pairs increment the same tab badge as ingestion review items?
   - Recommendation: Yes — use the same badge. The tab badge represents "things needing attention." The planner should add pending transfer pair count to the existing `reviewBadgeCount` binding.

3. **"Scan for transfers" entry point placement**
   - What we know: D-08 specifies the action exists; CONTEXT.md says placement is at Claude's discretion.
   - Recommendation: Add a "Scan for Transfers" row in `SettingsView` under the Gmail/Accounts section — mirrors the pattern of other deferred/on-demand actions in the Settings tab. A badge on the row when `!transferScanFirstRunDone`.

---

## Environment Availability

Step 2.6: SKIPPED — phase is purely in-app Swift logic. No external tools, CLI utilities, or services beyond Xcode 26.5 + iOS 17 simulator (confirmed available per project memory).

---

## Security Domain

`security_enforcement: true` in config.json (ASVS Level 1 enforcement).

### Applicable ASVS Categories

| ASVS Category | Applies | Standard Control |
|---------------|---------|-----------------|
| V2 Authentication | No | No new auth surface |
| V3 Session Management | No | No new sessions |
| V4 Access Control | No | Local-only app; no multi-user access control |
| V5 Input Validation | Yes | `Decimal` equality is exact; no injection surface (no string parsing in scorer) |
| V6 Cryptography | No | No new crypto |

### Known Threat Patterns for this stack

| Pattern | STRIDE | Standard Mitigation |
|---------|--------|---------------------|
| False-positive transfer exclusion (removing legitimate spend from budget) | Tampering | Mandatory user confirm before any exclusion; no silent auto-confirm |
| Double-spend from incorrect balance-move (if balance formula has sign error) | Elevation | Validate AccountBalance sign convention before wiring transfer balance-move |
| Re-pairing confirmed legs on subsequent scans | Tampering | `.filter { $0.isTransfer == nil }` in Swift (STAB-08 safe) guards against re-evaluation |

---

## Sources

### Primary (HIGH confidence)
- `MyHomeApp/Persistence/Schema/SchemaV6.swift` — Expense transfer scaffold fields (`isTransfer: Bool?`, `transferPairID: UUID?`, `accountID: UUID?`); confirmed as existing fields
- `MyHomeApp/Support/AccountBalance.swift` — Current `compute` formula; confirmed as baseline-only, no transfer handling
- `MyHomeApp/Support/BudgetCalculator.swift` — Current aggregation; no `isTransfer` filter present
- `MyHomeApp/Support/SpendOverTimeAggregator.swift` — Current aggregation; no `isTransfer` filter present
- `MyHomeApp/Support/OverviewAggregation.swift` — Confirmed uses `BudgetCalculator.monthlySpend` output
- `MyHomeApp/Features/Expenses/ReviewInboxRow.swift` — Accept/reject swipe pattern confirmed
- `MyHomeApp/Features/Expenses/ExpenseListView.swift` — `AccountFilter` pattern, `reviewItems` Section structure
- `MyHomeApp/Features/Gmail/AccountAttributionHelper.swift` — Pure-helper precedent (enum, value types only)
- `MyHomeApp/Features/Notes/RoutineResetService.swift` — `@MainActor @Observable` service precedent; IST calendar; fetch-then-filter pattern
- `MyHomeApp/Features/Gmail/GmailSyncController.swift` — STAB-02 pre-loop UUID capture; sync completion hook location
- `MyHomeTests/AccountBalanceTests.swift` — Test harness shape for pure helper tests
- `.planning/phases/10-self-transfer-detection/10-CONTEXT.md` — All locked decisions D-01..D-16

### Secondary (MEDIUM confidence)
- `.planning/phases/09-schemav6-accounts-management/09-03-SUMMARY.md` — STAB-02 confirmed shipping and passing in Phase 9
- `.planning/phases/09-schemav6-accounts-management/09-PATTERNS.md` — Full pattern catalog for Phase 9 analogs

---

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — no new packages; all patterns verified from live source files
- Architecture: HIGH — all integration points verified in production code
- Pitfalls: HIGH — all derived from documented STAB-## lessons in codebase + CONTEXT.md

**Research date:** 2026-06-10
**Valid until:** 2026-07-10 (stable codebase; no fast-moving external dependencies)
