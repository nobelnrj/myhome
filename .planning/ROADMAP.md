# Roadmap: My Home

## Overview

My Home is a single-user (v1) iOS app for a two-person Indian household, built as a Swift learning vehicle on the Swift 6.2 / SwiftUI / SwiftData stack, iOS 17+. v1.0 shipped the full MVP: manual + automated (Gmail) expense tracking, categories/tags/budgets, a notes + reminders hub, an overview dashboard with charts, and a Face ID gate — all on a CloudKit-ready schema so post-v1 sync is a configuration flip, not a rewrite.

## Milestones

- ✅ **v1.0 MVP** — Phases 1-7 (shipped 2026-06-03) — see [milestones/v1.0-ROADMAP.md](milestones/v1.0-ROADMAP.md)
- 🔜 **v1.1 Accounts, Assets & Household Polish** — Phases 8-12 (in progress)

## Phases

<details>
<summary>✅ v1.0 MVP (Phases 1-7) — SHIPPED 2026-06-03</summary>

- [x] Phase 1: Foundation & Manual Expense Spine (4/4 plans) — completed 2026-05-29
- [x] Phase 2: Categories, Tags & Budgets (5/5 plans) — completed 2026-05-30
- [x] Phase 3: Notes & Checklists (6/6 plans) — completed 2026-05-30
- [x] Phase 4: Overview & Charts (5/5 plans) — completed 2026-06-01
- [x] Phase 5: Face ID Gate & Settings (2/2 plans) — completed 2026-06-01
- [x] Phase 6: Gmail Sign-In & Client (4/4 plans) — completed 2026-06-02
- [x] Phase 7: Bank Parsers & Ingestion Pipeline (6/6 plans) — completed 2026-06-03

Full phase details archived in [milestones/v1.0-ROADMAP.md](milestones/v1.0-ROADMAP.md).

</details>

### v1.1: Accounts, Assets & Household Polish

- [x] **Phase 8: Stabilization** — Fix two crash vectors, category sort order, and seed the daily-routine reset service (completed 2026-06-09)
- [x] **Phase 9: SchemaV6 & Accounts Management** — Additive migration (Account + Asset models, transfer fields, routine fields) + full Accounts CRUD and per-account spend (completed 2026-06-10)
- [x] **Phase 10: Self-Transfer Detection** — 5-signal scorer, Transfer Inbox confirm flow, spend/budget exclusion, retroactive detection (completed 2026-06-10)
- [x] **Phase 11: Asset Tracker** — Holdings CRUD, AMFI MF NAV fetch, net-worth aggregation, allocation chart, staleness indicators (completed 2026-06-11)
- [ ] **Phase 12: Notes & Daily Routine Enhancement** — Routine toggle, per-day completion reset, optional reminder time, drag-reorder, streak/history

---

## Phase Details

### Phase 8: Stabilization

**Goal**: The live app is crash-free and category ordering works correctly; the daily-routine reset service is seeded and ready for the SchemaV6 field it will consume in Phase 9
**Depends on**: Nothing (first phase of v1.1; no schema changes required)
**Requirements**: STAB-01, STAB-02, STAB-03
**Success Criteria** (what must be TRUE):

  1. Opening Notes calendar or deleting a note/block no longer crashes the app — DayAgendaView and AgendaReminderItem guard all @Model property accesses against deleted/tombstoned objects
  2. Gmail sync runs to completion without crashing or stalling regardless of inbox size — Category references are re-fetched by PersistentIdentifier after each await; ctx.save() is called once after the full batch, not inside the per-message loop
  3. Adding a new custom category places it at the bottom of the category list, not the top — insertion uses max(existing.sortOrder) + 1
  4. RoutineResetService skeleton exists, is wired to RootView.onChange(of: scenePhase) on .active, and is ready to accept the lastCheckedDate field from Phase 9 (no schema change in this phase; service is a no-op stub until Phase 9 completes it)**Plans**: 4 plans
  - [x] 08-01-PLAN.md — STAB-01: tombstone-guard Notes calendar / day-agenda against deleted @Model refs
  - [x] 08-02-PLAN.md — STAB-02: re-resolve Category by PersistentIdentifier + single batched save in both Gmail sync paths
  - [x] 08-03-PLAN.md — STAB-03: lock in max(sortOrder)+1 category insertion (regression test + defensive comment + live-app confirm)
  - [x] 08-04-PLAN.md — STAB-04: RoutineResetService scaffold wired to RootView scenePhase .active (logged no-op)

---

### Phase 9: SchemaV6 & Accounts Management

**Goal**: One additive migration creates the Account and Asset models plus all new fields across Expense, Note, and NoteBlock; users can create and manage bank accounts with manual balances; existing expenses are correctly attributed to accounts; the daily-routine per-day reset is fully operational
**Depends on**: Phase 8
**Requirements**: STAB-04, ACCT-01, ACCT-02, ACCT-03, ACCT-04, ACCT-05, ACCT-06, ACCT-07, ACCT-08, NOTE-02
**Success Criteria** (what must be TRUE):

  1. User can add, edit, delete, and archive a bank account with a name, type (savings/current/credit card), color/icon, and a manual opening balance — the archived account disappears from pickers but its transactions remain visible in history
  2. Account balance displayed in AccountsView equals the manually set baseline ± debits and credits from attributed transactions since the baseline date; the figure updates without any manual refresh
  3. User can view per-account monthly spend — tapping an account shows only expenses attributed to that account
  4. All existing expenses attributed to a sourceAccount string are backfilled with the correct accountID UUID during the V5→V6 migration; a Swift Testing fixture test against a real V5 store passes before the phase ships (sourceAccount field is retained unchanged as the Gmail dedup key)
  5. A daily routine's checklist items start unchecked every morning — lastCheckedDate date-keys the per-block completion state; RoutineResetService resets all blocks on scenePhase .active when routineLastResetDate < startOfToday in IST

**Plans**: 4 plans (1 wave of schema foundation, then 3 parallel feature plans)
**Wave 1**

  - [x] 09-01-PLAN.md — SchemaV6 atomic commit (Account + Asset models, additive Expense/Note fields, all typealias flips, v5ToV6 didMigrate backfill) + BLOCKING migration fixture test [ACCT-08]

**Wave 2** *(blocked on Wave 1 completion)*

  - [x] 09-02-PLAN.md — Accounts CRUD under Settings: list/edit/detail with live balance, archive, migration review sheet [ACCT-01/02/03/04/05/07]
  - [x] 09-03-PLAN.md — Expense attribution: account picker, main-list account filter, Gmail auto-attribution by sourceLabel [ACCT-06]
  - [x] 09-04-PLAN.md — RoutineResetService body + RootView ModelContext injection (per-day IST reset) [STAB-04, NOTE-02]

**UI hint**: yes

---

### Phase 10: Self-Transfer Detection

**Goal**: The app automatically identifies likely self-transfers between own accounts and routes them to an explicit confirm flow; confirmed transfers are excluded from all spend and budget totals; account balances reflect confirmed transfer balance-moves
**Depends on**: Phase 9
**Requirements**: XFER-01, XFER-02, XFER-03, XFER-04, XFER-05
**Success Criteria** (what must be TRUE):

  1. A debit and credit of the same Decimal amount, opposite direction, both from known own accounts, within a 3-day calendar window, neither already flagged as a reversal, surfaces in a Transfer Inbox — nothing is silently excluded
  2. User can confirm a detected pair as a transfer (both expenses marked as confirmed transfers and linked) or reject it (pair is dismissed and scored as normal expenses); a manual mark/unmark action is available on any expense detail view
  3. Confirmed self-transfers are absent from all spend totals, budget progress bars, and charts; they appear only in a dedicated Transfers section
  4. Account balances for both accounts in a confirmed transfer reflect the balance-move — debit account decreases, credit account increases, total net worth is unchanged (completing the ACCT-05 transfer semantics from Phase 9)

**Plans**: 4 plans

Plans:
- [x] 10-01-PLAN.md — Detection scorer + scan service + AccountBalance sign verification (XFER-01, XFER-04)
- [x] 10-02-PLAN.md — Confirmed-transfer spend/budget/chart exclusion (XFER-04)
- [x] 10-03-PLAN.md — Review-Inbox confirm/reject + Transfers filter + post-sync scan hook (XFER-02, XFER-03)
- [x] 10-04-PLAN.md — Manual mark/unmark transfer on expense edit view (XFER-05)

**UI hint**: yes

---

### Phase 11: Asset Tracker

**Goal**: Users can record all household holdings (mutual funds, stocks, NPS) and see total net worth as the sum of holding values and account balances; MF NAVs refresh best-effort from AMFI; every price carries its as-of date and a staleness indicator
**Depends on**: Phase 9
**Requirements**: ASSET-01, ASSET-02, ASSET-03, ASSET-04, ASSET-05, ASSET-06, ASSET-07, ASSET-08, ASSET-09
**Success Criteria** (what must be TRUE):

  1. User can add, edit, and delete holdings for mutual funds, stocks, and NPS — each holding records units, cost basis, and a current NAV/price (auto-fetched for MFs; manual-entry for stocks and NPS)
  2. Mutual fund NAVs auto-refresh from AMFI NAVAll.txt in the background; the net-worth view renders immediately from the last cached value and never blocks on a network call; a staleness badge appears when the stored NAV date is older than one trading day
  3. Total net worth (holdings value + account balances) is shown with a per-holding breakdown including absolute and percentage gain/loss against cost basis
  4. An asset-allocation chart (donut/pie via Swift Charts) shows the portfolio split by asset class — mutual funds, stocks, NPS, cash
  5. The app records net-worth snapshots over time and displays a trend chart; every displayed NAV or price carries an explicit as-of date label; user can always override any price manually

**Plans**: 4 plans (1 schema wave, 2 parallel feature plans, 1 Overview plan)

**Wave 1**

  - [x] 11-01-PLAN.md — SchemaV7 atomic migration (amfiSchemeCode + NetWorthSnapshot) + Wave-0 test scaffolds incl. BLOCKING migration fixture [ASSET-01, ASSET-08]

**Wave 2** *(blocked on Wave 1)*

  - [x] 11-02-PLAN.md — AMFINavService + NetWorthCalculator + NetWorthSnapshotService + RootView daily hooks [ASSET-03, ASSET-05, ASSET-08]
  - [x] 11-03-PLAN.md — Holdings CRUD under Settings > Assets: list/edit/detail/AMFI picker/staleness [ASSET-01, ASSET-02, ASSET-04, ASSET-06, ASSET-09]

**Wave 3** *(blocked on Wave 2)*

  - [x] 11-04-PLAN.md — Overview net-worth card: allocation donut + trend chart [ASSET-05, ASSET-07, ASSET-08]

**UI hint**: yes

---

### Phase 11.1: SIP Automation and NPS NAV auto-refresh (INSERTED)

**Goal:** [Urgent work - to be planned]
**Requirements**: TBD
**Depends on:** Phase 11
**Plans:** 0 plans

Plans:
- [ ] TBD (run /gsd-plan-phase 11.1 to break down)

### Phase 12: Notes & Daily Routine Enhancement

**Goal**: Users can designate any note as a daily routine that appears on every calendar day, receives an optional timed notification, supports drag-to-reorder checklist items, and tracks a completion streak
**Depends on**: Phase 9
**Requirements**: NOTE-01, NOTE-03, NOTE-04, NOTE-05
**Success Criteria** (what must be TRUE):

  1. A note marked as a daily routine appears as a repeating event on every day in CalendarView without requiring any recurring reminder to be separately configured
  2. User can set an optional reminder time on a routine note; the notification fires once per day at that time — exactly one pending notification exists per routine note at any time (re-scheduling does not stack duplicates)
  3. User can drag-reorder checklist items within a routine note and the new order persists after the view is dismissed
  4. The app shows a streak count (current consecutive days where all checklist items were marked complete) and a scrollable history of past per-day completions per routine note

**Plans**: TBD
**UI hint**: yes

---

## Progress

| Phase | Milestone | Plans Complete | Status | Completed |
|-------|-----------|----------------|--------|-----------|
| 1. Foundation & Manual Expense Spine | v1.0 | 4/4 | Complete | 2026-05-29 |
| 2. Categories, Tags & Budgets | v1.0 | 5/5 | Complete | 2026-05-30 |
| 3. Notes & Checklists | v1.0 | 6/6 | Complete | 2026-05-30 |
| 4. Overview & Charts | v1.0 | 5/5 | Complete | 2026-06-01 |
| 5. Face ID Gate & Settings | v1.0 | 2/2 | Complete | 2026-06-01 |
| 6. Gmail Sign-In & Client | v1.0 | 4/4 | Complete | 2026-06-02 |
| 7. Bank Parsers & Ingestion Pipeline | v1.0 | 6/6 | Complete | 2026-06-03 |
| 8. Stabilization | v1.1 | 4/4 | Complete    | 2026-06-09 |
| 9. SchemaV6 & Accounts Management | v1.1 | 4/4 | Complete    | 2026-06-10 |
| 10. Self-Transfer Detection | v1.1 | 4/4 | Complete    | 2026-06-10 |
| 11. Asset Tracker | v1.1 | 4/4 | Complete    | 2026-06-11 |
| 11.1 SIP Automation & NPS NAV (INSERTED) | v1.1 | 0/? | Not started | - |
| 12. Notes & Daily Routine Enhancement | v1.1 | 0/? | Not started | - |

---

## Coverage Map — v1.1

| Requirement | Phase |
|-------------|-------|
| STAB-01 | Phase 8 |
| STAB-02 | Phase 8 |
| STAB-03 | Phase 8 |
| STAB-04 | Phase 9 |
| ACCT-01 | Phase 9 |
| ACCT-02 | Phase 9 |
| ACCT-03 | Phase 9 |
| ACCT-04 | Phase 9 |
| ACCT-05 | Phase 9 |
| ACCT-06 | Phase 9 |
| ACCT-07 | Phase 9 |
| ACCT-08 | Phase 9 |
| XFER-01 | Phase 10 |
| XFER-02 | Phase 10 |
| XFER-03 | Phase 10 |
| XFER-04 | Phase 10 |
| XFER-05 | Phase 10 |
| ASSET-01 | Phase 11 |
| ASSET-02 | Phase 11 |
| ASSET-03 | Phase 11 |
| ASSET-04 | Phase 11 |
| ASSET-05 | Phase 11 |
| ASSET-06 | Phase 11 |
| ASSET-07 | Phase 11 |
| ASSET-08 | Phase 11 |
| ASSET-09 | Phase 11 |
| NOTE-01 | Phase 12 |
| NOTE-02 | Phase 9 |
| NOTE-03 | Phase 12 |
| NOTE-04 | Phase 12 |
| NOTE-05 | Phase 12 |

**All 32 v1.1 requirements mapped. No orphans.**

---

## Cross-Phase Notes

- **STAB-04 / NOTE-02 split:** STAB-04 (daily routine resets each day) is satisfied by NOTE-02 at the data-model level. Phase 8 ships the RoutineResetService skeleton wired to scenePhase; Phase 9 adds the `NoteBlock.lastCheckedDate` field and completes the full per-day reset. STAB-04 is assigned to Phase 9 because its observable behavior (the reset actually working) requires the schema field.
- **ACCT-05 / XFER cross-reference:** ACCT-05 (auto-update balance from transactions) is assigned to Phase 9 for baseline ± own-account transaction calculation. Transfer balance-move semantics (confirmed self-transfers shift balance between accounts) are completed in Phase 10 and explicit in Phase 10 success criterion 4.
- **NOTE-02 in Phase 9:** `NoteBlock.lastCheckedDate` is bundled into SchemaV6 to avoid an extra intermediate migration stage. The observable per-day reset behavior is Phase 9 success criterion 5.
- **Phase 11 and Phase 12 are independent after Phase 9:** Both depend only on SchemaV6. In single-track serial order Phase 11 (Asset Tracker) precedes Phase 12 (Notes Enhancement) so spend accuracy is confirmed complete before net-worth figures are presented — though Phase 12 has no logical dependency on Phase 11.
- **Phase 9 research flag:** The V5→V6 `didMigrate` closure is the first non-nil `didMigrate` in this codebase. Verify error-handling behavior (throwing closure: rollback vs. partial state) against the existing FB13812722 workaround in MigrationPlan.swift before writing the migration stage.
- **Phase 9 reset-mechanism reconciliation (planning decision):** Success criterion 5 mentions both a per-block `lastCheckedDate` and a note-level `routineLastResetDate`. Per CONTEXT.md D-12, Phase 9 implements the **note-level `routineLastResetDate`** marker on `Note` (with `isDailyRoutine: Bool`), which fully satisfies the observable per-day reset. Per-block `lastCheckedDate` is deferred to Phase 12 (needed only for streak/history, NOTE-05). No `NoteBlock` schema change in Phase 9.
