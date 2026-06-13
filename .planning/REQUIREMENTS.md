# Requirements — Milestone v1.1: Accounts, Assets & Household Polish

**Milestone goal:** Grow My Home from an automated expense tracker into a light household finance + ops hub — account-aware spend with self-transfer detection, a net-worth asset tracker, smarter daily-routine reminders, and a stability/UX cleanup pass.

**Constraints carried from v1.0:** local-only (no CloudKit/sharing), zero recurring cost, no paid third-party services/SDKs, no analytics/telemetry, free public data sources only with manual override always available, CloudKit-ready SwiftData schema (additive, no `.unique`, optional/defaulted).

---

## v1.1 Requirements

### Stabilization (STAB)

<!-- Bug fixes + safety. Ships first; gates all schema/feature work. -->

- [x] **STAB-01**: App no longer crashes when the Notes calendar / day-agenda is open and a note or block is deleted (guard `DayAgendaView` / `AgendaReminderItem` against tombstoned `@Model` references).
- [x] **STAB-02**: Gmail sync no longer crashes or stalls (re-fetch `Category` references after `await` suspension points; move `ctx.save()` out of the per-message loop into a single batched save).
- [x] **STAB-03**: Adding a new category surfaces it at the top of the list (stable insertion order via `min(sortOrder)-1`). [Reversed from "bottom" during Phase 8 execution per user direction — supersedes decision D-05.]
- [x] **STAB-04**: A daily routine's completed/checked state automatically resets when the day ends, so each new day starts uncompleted.

### Accounts Management (ACCT)

<!-- New Account entity; builds on existing Expense.sourceAccount (retained as Gmail dedup key). -->

- [x] **ACCT-01**: User can create, edit, and delete a bank account (name, last-4 optional).
- [x] **ACCT-02**: User can set an account type (savings / current / credit card).
- [x] **ACCT-03**: User can assign a color/icon to an account for visual identification.
- [x] **ACCT-04**: User can manually set an account's balance as a reconciliation baseline (an opening/anchor balance with an as-of date).
- [x] **ACCT-05**: Account balance auto-updates from attributed transactions — debits decrease and credits increase the balance from the baseline; confirmed self-transfers move balance between accounts without changing total net worth. Displayed balance = baseline ± transactions since the baseline date.
- [x] **ACCT-06**: User can view spend filtered to a single account (per-account spend view).
- [x] **ACCT-07**: User can archive/hide a closed account so it stays out of pickers without losing its transaction history.
- [x] **ACCT-08**: Existing expenses are attributed to accounts via an additive `accountID` without disturbing `sourceAccount` (the Gmail dedup idempotency key); legacy data is backfilled in the V5→V6 migration without loss.

### Self-Transfer Detection (XFER)

<!-- Deterministic 5-signal scorer; auto-detect + mandatory confirm; never silent. -->

- [x] **XFER-01**: The app auto-detects likely self-transfers — a debit and credit of the same amount between two of the user's own accounts, opposite direction, within a 3-day window, neither already categorized nor flagged as a reversal.
- [x] **XFER-02**: Detected self-transfer pairs surface in a Transfer Inbox for explicit user confirmation (reusing the Review Inbox accept/reject pattern); nothing is excluded silently.
- [x] **XFER-03**: User can confirm or reject a detected pair; confirmed transfers are marked as transfers and linked as a pair.
- [x] **XFER-04**: Confirmed self-transfers are excluded from spend totals and budgets (BudgetCalculator filters them out).
- [x] **XFER-05**: User can manually mark/unmark any expense as a self-transfer when auto-detection misses or misfires.

### Asset Tracker (ASSET)

<!-- New Asset/Holding entity; manual holdings + free MF NAV; net worth = holdings + account balances. -->

- [x] **ASSET-01**: User can add, edit, and delete holdings across asset classes: mutual funds, stocks, NPS, and (via Accounts) cash balances.
- [x] **ASSET-02**: User can record units and cost basis per holding, with current value derived.
- [x] **ASSET-03**: Mutual fund NAV auto-refreshes from the free AMFI source (best-effort, cached last-known value, never blocks the UI); user can always override NAV manually.
- [x] **ASSET-04**: Stock and NPS holdings are valued by manual current-value/NAV entry (no fragile auto-fetch for stocks in v1.1).
- [x] **ASSET-05**: User sees total net worth = sum of holding values + account balances.
- [x] **ASSET-06**: User sees per-holding gain/loss (absolute and %) against cost basis.
- [x] **ASSET-07**: User sees an asset-allocation chart (net worth split by asset class).
- [x] **ASSET-08**: The app snapshots net worth over time and charts the trend.
- [x] **ASSET-09**: Price/NAV values display their as-of date and a stale indicator when data is older than the freshness threshold.

### Notes & Daily Routine Enhancement (NOTE)

<!-- Date-keyed routine completion; reuses existing recurrence/calendar/notification machinery. -->

- [x] **NOTE-01**: User can mark a note as a daily routine; it surfaces on every day in the calendar view automatically.
- [x] **NOTE-02**: A daily routine's checklist completion is tracked per-day (date-keyed `lastCheckedDate`), so it resets cleanly each day (satisfies STAB-04 at the data-model level).
- [x] **NOTE-03**: User can set an optional reminder time for a daily routine, delivering a local notification (reuses existing NotificationScheduler).
- [x] **NOTE-04**: User can reorder checklist items within a routine note (drag-to-reorder).
- [x] **NOTE-05**: The app logs per-day routine completions and shows a streak/history view.

---

## Future Requirements (deferred)

- Stock quote auto-fetch (best-effort Yahoo endpoint) — deferred until the manual flow is proven and the fragility/ToS risk is worth it.
- NPS NAV auto-fetch (npsnav.in) — deferred; single-maintainer source risk, manual entry suffices for v1.1.
- CAS / broker import, XIRR — anti-featured for a 2-person private tool.
- RoutineCompletion-driven analytics beyond simple streaks (heatmaps, insights).

## Out of Scope (explicit)

- **CloudKit sync / sharing with wife's Apple ID** — remains the v2.0 trigger, gated on the $99/yr Apple Developer upgrade. v1.1 is local-only.
- **Real-time / intraday stock prices** — out of charter; this is a net-worth snapshot tool, not a trading app.
- **Open Banking / Plaid / account balance auto-sync** — no free reliable India option; balances are manual.
- **Multi-currency / FX** — INR-only display retained from v1.0.
- **Paid data providers or any SDK** — free public sources only.

---

## Traceability

| Requirement | Phase | Status |
|-------------|-------|--------|
| STAB-01 | Phase 8 | Complete |
| STAB-02 | Phase 8 | Complete |
| STAB-03 | Phase 8 | Complete |
| STAB-04 | Phase 9 | Complete |
| ACCT-01 | Phase 9 | Complete |
| ACCT-02 | Phase 9 | Complete |
| ACCT-03 | Phase 9 | Complete |
| ACCT-04 | Phase 9 | Complete |
| ACCT-05 | Phase 9 | Complete |
| ACCT-06 | Phase 9 | Complete |
| ACCT-07 | Phase 9 | Complete |
| ACCT-08 | Phase 9 | Complete |
| XFER-01 | Phase 10 | Complete |
| XFER-02 | Phase 10 | Complete |
| XFER-03 | Phase 10 | Complete |
| XFER-04 | Phase 10 | Complete |
| XFER-05 | Phase 10 | Complete |
| ASSET-01 | Phase 11 | Complete |
| ASSET-02 | Phase 11 | Complete |
| ASSET-03 | Phase 11 | Complete |
| ASSET-04 | Phase 11 | Complete |
| ASSET-05 | Phase 11 | Complete |
| ASSET-06 | Phase 11 | Complete |
| ASSET-07 | Phase 11 | Complete |
| ASSET-08 | Phase 11 | Complete |
| ASSET-09 | Phase 11 | Complete |
| NOTE-01 | Phase 12 | Complete |
| NOTE-02 | Phase 9 | Complete |
| NOTE-03 | Phase 12 | Complete |
| NOTE-04 | Phase 12 | Complete |
| NOTE-05 | Phase 12 | Complete |
