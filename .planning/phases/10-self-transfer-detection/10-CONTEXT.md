# Phase 10: Self-Transfer Detection - Context

**Gathered:** 2026-06-10
**Status:** Ready for planning

<domain>
## Phase Boundary

Auto-detect likely self-transfers — a debit and credit of the same amount between two of the user's own accounts, opposite direction, within a 3-day window — and route detected pairs to an explicit confirm flow. Confirmed self-transfers are excluded from all spend totals, budget progress, and charts (visible only under a Transfers filter), and a confirmed pair moves balance between the two accounts (debit account decreases, credit account increases, total net worth unchanged — completing the ACCT-05 transfer semantics scaffolded in Phase 9).

Requirements: XFER-01, XFER-02, XFER-03, XFER-04, XFER-05.

**In scope:** detection scorer, Review-Inbox confirm/reject for pairs, spend/budget/chart exclusion, account balance-move on confirmed pairs, manual mark/unmark, retroactive one-time sweep.
**Out of scope:** fuzzy/weighted scoring, cross-currency transfers, external-party transfers, any SchemaV7 migration, the isDailyRoutine toggle UI (Phase 12), asset/net-worth aggregation (Phase 11).

</domain>

<decisions>
## Implementation Decisions

### Matching logic (XFER-01)
- **D-01:** **Hard AND-rules**, not a weighted score. A pair is surfaced only when ALL conditions hold — the "5 signals" are required conditions, not weights. No confidence threshold, no fuzzy matching this phase.
- **D-02:** **Exact `Decimal` amount match** between the two legs (to the paisa). No tolerance band.
- **D-03:** **Opposite direction by sign of `amount`** — one leg is a debit (`amount > 0`), the other a credit (`amount < 0`), with equal magnitude. Direction is the sign of the stored `Decimal` (debits positive, credits negative); there is no separate direction field.
- **D-04:** **Both legs must be assigned to accounts**, and to **two different** own accounts (`accountID` set on both, `accountID_A != accountID_B`). Pairs where either leg is unassigned are NOT surfaced. This is the strongest false-positive filter.
- **D-05:** **3-day calendar window** between the two legs' dates (IST), inclusive. Use the same IST calendar convention established in Phase 9 (`Asia/Kolkata`).

### Reversal vs transfer-credit (XFER-01)
- **D-06:** **No new schema field / no SchemaV7.** Refunds and transfer-credit-legs are both stored as negative-amount expenses; the app does not persist a reversal flag. Any negative-amount expense that pairs with a matching debit per D-01..D-05 is a candidate — the user's confirm/reject in the inbox is what separates a genuine refund from the credit half of a transfer.
- **D-07:** The roadmap's "neither already flagged as a reversal" criterion is realized via the **`isTransfer` tri-state**: `nil` = unevaluated (candidate), `true` = confirmed transfer, `false` = rejected / "not a transfer". A confirmed or rejected leg is never re-surfaced.

### Detection timing & scope (XFER-01, retroactive)
- **D-08:** Scorer runs **at the end of each Gmail sync** (new expenses just landed) **plus a manual "Scan for transfers" action**. Not on app-activation, not lazy-on-open.
- **D-09:** **One-time full historical sweep** on first run (evaluate all existing expenses for pairs), then **incremental** — subsequent runs only consider expenses with `isTransfer == nil`.
- **D-10:** **Skip rule:** only `isTransfer == nil` expenses are detection candidates. Confirm sets both legs `true`; reject sets both legs `false`. Re-scans ignore anything non-nil. No separate evaluated-pairs ledger.

### Inbox & manual-mark UX (XFER-02, XFER-03, XFER-05)
- **D-11:** Detected pairs are **merged into the existing Review Inbox** as a distinct transfer-pair row type (reusing the accept/reject pattern from `ReviewInboxRow`), not a separate inbox screen. Nothing is excluded silently — every detected pair surfaces for explicit confirmation.
- **D-12:** Confirmed transfers are shown via a **Transfers filter/section in `ExpenseListView`** (mirrors the Phase 9 account filter). Confirmed transfers are hidden from the default list, spend totals, budgets, and charts; they appear only under this filter.
- **D-13:** **Confirm** marks both legs `isTransfer = true` and links them (`transferPairID` cross-set); **reject** marks both `isTransfer = false` and dismisses (scored as normal expenses).
- **D-14:** **Manual mark/unmark (XFER-05)** is available on any expense detail view. A **solo flag is allowed** (`isTransfer = true`, `transferPairID = nil`) with an **optional "link counterpart"** action. Unmark resets to `nil`/`false` and unlinks any pair.

### Exclusion & balance-move (XFER-04, ACCT-05 completion)
- **D-15:** **Exclusion point:** `BudgetCalculator`, `SpendOverTimeAggregator`, and `OverviewAggregation` filter out `isTransfer == true` expenses from all spend/budget/chart math. A solo manually-marked transfer is excluded from spend the same way.
- **D-16:** **Balance-move** applies **only to a linked confirmed pair**: in `AccountBalance.compute`, a confirmed transfer's debit leg decreases its account and the credit leg increases its account, leaving total net worth unchanged. A **solo** transfer (no counterpart) is excluded from spend but does **not** move balance between accounts (there is no second account). This is consistent with ACCT-05, which defines balance-move on confirmed pairs.

### Claude's Discretion
- Exact placement/labeling of the "Scan for transfers" affordance and the Transfers filter chip.
- The transfer-pair row layout within the Review Inbox (what each side shows — account name, amount, date), following existing `ReviewInboxRow`/`ExpenseRow` skeletons.
- Tie-breaking when one debit exactly matches multiple candidate credits (e.g., surface the closest-in-time pair first; remaining candidates stay `nil`). Planner/researcher to choose a deterministic rule.
- Where exactly the detection scorer lives (a pure helper mirroring the `AccountAttributionHelper` / `RoutineResetService` patterns) and its unit-test surface.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Schema & transfer scaffold
- `MyHomeApp/Persistence/Schema/SchemaV6.swift` — the `Expense` model incl. the Phase 10 transfer scaffold: `accountID: UUID?`, `isTransfer: Bool?`, `transferPairID: UUID?`. These already exist — Phase 10 fills the logic, NO schema bump.
- `MyHomeApp/Persistence/Models/Expense.swift` — `Expense` typealias (= `SchemaV6.Expense`) and the STAB-08 typealias-flip rationale.
- `MyHomeApp/Persistence/Models/Account.swift` — own-account model; `Account.id` is the `accountID` target; `Account.expenses` inverse relationship.

### Direction / ingestion semantics
- `MyHomeApp/Features/Ingestion/BankEmailParser.swift` — `ParsedExpense.isReversal` + "negative amount for reversals/refunds/credits (ING-09)"; defines how credits become negative-`amount` expenses.
- `MyHomeApp/Features/Ingestion/CUBParser.swift` §parseCredit — concrete credit/reversal path producing `amount: -abs(amount)`.

### Reuse targets (confirm flow, exclusion, balance)
- `MyHomeApp/Features/Expenses/ReviewInboxRow.swift` — accept/reject row pattern to extend for transfer-pair rows (D-11).
- `MyHomeApp/Features/Expenses/ExpenseListView.swift` — Phase 9 `AccountFilter` pattern to mirror for the Transfers filter (D-12).
- `MyHomeApp/Support/BudgetCalculator.swift` — spend/budget math; add `isTransfer == true` exclusion (D-15).
- `MyHomeApp/Support/SpendOverTimeAggregator.swift`, `MyHomeApp/Support/OverviewAggregation.swift` — chart/overview aggregations; same exclusion (D-15).
- `MyHomeApp/Support/AccountBalance.swift` — `compute` baseline ± attributed-since formula; extend with confirmed-pair balance-move (D-16, completes ACCT-05).
- `MyHomeApp/Features/Gmail/GmailSyncController.swift` — sync completion hook where the post-sync scan runs (D-08); STAB-02 pre-loop-UUID pattern for `@Model`-safe async.

### Requirements / roadmap
- `.planning/REQUIREMENTS.md` §Self-Transfer Detection (XFER) — XFER-01..05 and ACCT-05 transfer clause.
- `.planning/ROADMAP.md` §Phase 10 — goal + 4 success criteria.
- `.planning/phases/09-schemav6-accounts-management/09-03-SUMMARY.md` — Gmail attribution + STAB-02 pre-loop UUID capture (the `@Model`-across-await rule the scorer must also respect).

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `ReviewInboxRow` — accept/reject row skeleton; extend with a transfer-pair variant (D-11).
- `ExpenseListView.AccountFilter` — Phase 9 filter enum chained in `filteredExpenses`; add a Transfers filter the same way (D-12).
- `AccountBalance.compute` — pure balance engine; the natural home for the confirmed-pair balance-move (D-16).
- `AccountAttributionHelper` / `RoutineResetService` — precedents for a pure, unit-testable helper + a `@MainActor` service injected with `ModelContext` (good shape for the transfer scorer).

### Established Patterns
- Direction = sign of `Decimal amount` (debit > 0, credit < 0); money is always `Decimal`, never `Double`.
- IST (`Asia/Kolkata`) calendar for day-window math (Phase 9 / RoutineResetService convention).
- STAB-02: never hold `@Model` references across `await`; capture plain values (UUIDs) before async loops.
- SwiftData `#Predicate` on `Bool?` is fragile (STAB-08 lesson) — prefer fetching and filtering in Swift where a tri-state `isTransfer` is involved, or test the predicate explicitly under the versioned schema.

### Integration Points
- Gmail sync completion → run scorer (D-08).
- Review Inbox list → transfer-pair rows (D-11).
- ExpenseListView filter + spend/budget/chart aggregators → exclusion (D-12, D-15).
- AccountBalance.compute → balance-move (D-16).
- Expense detail view → manual mark/unmark + optional link (D-14).

</code_context>

<specifics>
## Specific Ideas

- "5-signal scorer" from the milestone framing is realized as 5 **required** boolean conditions (D-01..D-05): equal amount, opposite sign, two different assigned own accounts, ≤3-day IST window, not-already-evaluated (`isTransfer == nil`).
- Reuse over new surfaces: confirm flow rides the Review Inbox; confirmed view rides the ExpenseListView filter. Avoid building standalone screens this phase.

</specifics>

<deferred>
## Deferred Ideas

- **Weighted/fuzzy scoring & amount tolerance** — explicitly deferred (D-01/D-02). Revisit only if hard rules miss real transfers in practice; a scoring hook can be added later.
- **Stored reversal flag (SchemaV7)** — deferred (D-06); reconsider if user confirm proves too noisy.
- **Cross-currency / external-party transfers** — out of scope; single-currency (INR) own-account transfers only.
- **Re-pairing a rejected leg with a different counterpart** — known limitation of the `false` skip rule (D-10); acceptable for v1.

None of these block the phase.

</deferred>

---

*Phase: 10-self-transfer-detection*
*Context gathered: 2026-06-10*
