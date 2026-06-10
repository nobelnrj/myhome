# Phase 10: Self-Transfer Detection - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-06-10
**Phase:** 10-self-transfer-detection
**Areas discussed:** Matching strictness, Reversal vs transfer-credit, Detection timing & scope, Inbox & manual mark UX

---

## Matching strictness

| Option | Description | Selected |
|--------|-------------|----------|
| Hard AND-rules | Surface only pairs meeting ALL criteria; "5 signals" become required conditions | ✓ |
| Weighted 5-signal score | Score signals, surface above a confidence cutoff even with a weak signal | |
| Hard now, weighted later | Ship hard rules, leave a scoring hook | |

**User's choice:** Hard AND-rules
**Notes:** No fuzzy scoring this phase. → D-01

| Option | Description | Selected |
|--------|-------------|----------|
| Exact Decimal match | Same amount to the paisa | ✓ |
| Small tolerance | ±₹1 / ±0.5% to absorb fees/rounding | |

**User's choice:** Exact Decimal match → D-02

| Option | Description | Selected |
|--------|-------------|----------|
| Both assigned, different accounts | Both legs have accountID set, to two different own accounts | ✓ |
| Allow one leg unassigned | Surface pairs with one unassigned side; assign on confirm | |

**User's choice:** Both assigned, different accounts → D-04

---

## Reversal vs transfer-credit

| Option | Description | Selected |
|--------|-------------|----------|
| No new field — user confirms | Any negative-amount expense pairing a matching debit is a candidate; confirm/reject separates refund from transfer; no SchemaV7 | ✓ |
| Add stored isReversal flag (SchemaV7) | Persist parser isReversal; exclude flagged reversals; requires migration | |

**User's choice:** No new field → D-06

| Option | Description | Selected |
|--------|-------------|----------|
| isTransfer tri-state | nil = unevaluated, true = confirmed, false = rejected; never re-surface non-nil | ✓ |
| Also skip ingestion-credit notes | Additionally skip parser-marked refunds before the inbox | |

**User's choice:** isTransfer tri-state → D-07

---

## Detection timing & scope

| Option | Description | Selected |
|--------|-------------|----------|
| After Gmail sync + manual scan | Run at end of each sync + a manual Scan action | ✓ |
| On app activation | Run on scenePhase .active like the routine reset | |
| On-demand only | Only when the Transfer Inbox opens | |

**User's choice:** After Gmail sync + manual scan → D-08

| Option | Description | Selected |
|--------|-------------|----------|
| One-time full sweep, then incremental | Evaluate all history once, then only new/unevaluated expenses | ✓ |
| Rolling window only | Only ever scan a recent window (e.g. 90 days) | |

**User's choice:** One-time full sweep, then incremental → D-09

| Option | Description | Selected |
|--------|-------------|----------|
| Skip non-nil isTransfer | Only nil-isTransfer expenses are candidates; confirm→true, reject→false | ✓ |
| Track evaluated pairs separately | Separate pair-key ledger | |

**User's choice:** Skip non-nil isTransfer → D-10

---

## Inbox & manual mark UX

| Option | Description | Selected |
|--------|-------------|----------|
| Separate Transfer Inbox | Dedicated transfer-pairs list reusing accept/reject | |
| Merge into Review Inbox | Transfer-pair rows as a distinct type in the existing Review Inbox | ✓ |

**User's choice:** Merge into Review Inbox → D-11

| Option | Description | Selected |
|--------|-------------|----------|
| Filter in Expenses list | Transfers filter/section in ExpenseListView (mirrors account filter) | ✓ |
| Dedicated Transfers screen | Separate screen listing confirmed transfers | |

**User's choice:** Filter in Expenses list → D-12

| Option | Description | Selected |
|--------|-------------|----------|
| Solo allowed + optional pairing | Flag single expense as transfer, optional link counterpart; balance-move only when paired | ✓ |
| Require counterpart selection | Manual mark forces choosing a matching expense to form a pair | |

**User's choice:** Solo allowed + optional pairing → D-14

---

## Claude's Discretion

- "Scan for transfers" affordance placement and Transfers filter chip labeling
- Transfer-pair row layout in the Review Inbox
- Tie-breaking when one debit matches multiple candidate credits (deterministic rule TBD by planner/researcher)
- Where the scorer helper lives + its unit-test surface

## Deferred Ideas

- Weighted/fuzzy scoring & amount tolerance (revisit if hard rules miss real transfers)
- Stored reversal flag / SchemaV7 (revisit if confirm is too noisy)
- Cross-currency / external-party transfers (out of scope)
- Re-pairing a rejected leg with a different counterpart (known v1 limitation)
