# Project Research Summary

**Project:** My Home — v1.1 Milestone: Accounts, Assets & Household Polish
**Domain:** iOS-only personal-finance + household-ops app (SwiftData, SwiftUI, India-focused)
**Researched:** 2026-06-08
**Confidence:** HIGH (stack, architecture, pitfalls from direct codebase inspection); MEDIUM (NPS pricing source, self-transfer edge cases)

---

## Executive Summary

My Home v1.1 adds four feature areas — Accounts Management, Self-Transfer Detection, Asset Tracker, and Notes/Daily Routine enhancement — to a shipped, stable v1.0 app. All four agents converge on one non-negotiable ordering constraint: **stabilization must come first**. There are two confirmed crash vectors in the live app that must be fixed before any schema or feature work begins. The DayAgendaView/AgendaReminderItem path holds live references to cascade-deleted NoteBlock objects (EXC_BAD_ACCESS), and GmailSyncController.syncAccount() captures live `@Model` Category references across `await` suspension points and calls `ctx.save()` inside a per-message loop. Both crashes are well-understood and have deterministic fixes; neither requires a schema change. The daily-routine stale-completion bug (NoteBlock.isChecked persisting across days) is also resolved in this stabilization pass via a date-keyed approach — `RoutineResetService` triggered on `scenePhase .active`, not a timer or background job.

The single riskiest non-crash task in v1.1 is the SchemaV6 migration. All four research agents agree the migration must be **additive only**: `Expense.sourceAccount` (the Gmail dedup idempotency key) is retained unchanged, and `Expense.accountID` (UUID FK to the new `Account` entity) is added alongside it — the two fields serve different purposes and must coexist through at least SchemaV7. The one migration task that requires special attention is backfilling `accountID` on existing expenses from the legacy `sourceAccount` string. This is the single highest-risk task in the milestone and requires a real migration test against a V5 fixture store (a copy of the live simulator `default.store`) run under Swift Testing before the feature ships. All new fields across all four feature areas are additive and optional-with-defaults, keeping the migration stage `willMigrate: nil` and only requiring a non-nil `didMigrate` for the account-backfill pass.

Data source reliability is tiered and the app design must reflect this: AMFI NAV (mutual funds via `portal.amfiindia.com/spages/NAVAll.txt`) is HIGH confidence — official, stable, free; NPS NAV via `npsnav.in` is MEDIUM confidence — reliable data from Protean CRA but single-maintainer risk; Indian stock quotes via Yahoo Finance `v8/finance/chart` are LOW confidence — undocumented, fragile, legally grey. Manual override is mandatory for stocks and NPS; it is the primary entry path, not a fallback. The net-worth view must always render from cached data and must never block on a network call. Zero new SPM dependencies are required across all four feature areas.

---

## Key Findings

### Recommended Stack

The v1.0 stack (Swift 6.2 + SwiftUI + SwiftData + Swift Testing, iOS 17 minimum, Xcode 26) is unchanged for v1.1. The only meaningful additions are a set of free external HTTP data sources for asset pricing — all hit via existing `URLSession` — and a `PriceFetchService` actor pattern for fetch/cache. Zero new SPM packages are added.

**Core technologies:**
- **Swift 6.2 / Xcode 26:** Application language and IDE — no change from v1.0
- **SwiftData (VersionedSchema → SchemaV6):** Persistence layer; additive migration adds `Account`, `Asset` @Model types and five fields on `Expense`, two on `Note`, one on `NoteBlock`
- **URLSession (no SDK):** All price fetching (AMFI, npsnav.in, Yahoo Finance) — existing framework, zero new deps
- **PriceFetchService (`@Observable` class):** Owns all external price fetching; owned by `AssetsView` via `@State`, not a singleton; matches `GmailSyncController` ownership pattern
- **UNUserNotificationCenter / NotificationScheduler (existing):** Daily routine notification — reuse existing `.daily` recurrence path; no new infrastructure
- **Swift Testing (in-toolchain):** Primary test harness — critical for migration fixture test (V5 → V6 backfill)

**Data source reliability (critical for design decisions):**

| Source | Asset Type | Confidence | Notes |
|--------|-----------|------------|-------|
| `portal.amfiindia.com/spages/NAVAll.txt` | Mutual funds | HIGH | Official AMFI bulk file; stable multi-year URL; ~5 MB plain text; parse on background actor |
| `api.mfapi.in/mf/{schemeCode}` | Mutual funds (fallback/onboarding) | MEDIUM-HIGH | Third-party JSON wrapper over AMFI; convenient but adds SPoF |
| `npsnav.in/api/latest-min` | NPS | MEDIUM | Data from Protean CRA (official); single-maintainer open-source aggregator risk |
| `query1.finance.yahoo.com/v8/finance/chart/{sym}` | Stocks | LOW | Undocumented, unofficial, historically fragile; ~360 req/hr cap; legally grey for personal use |
| Manual entry | All types | N/A — mandatory | Primary path for NPS, FD, other; mandatory fallback for stocks |

### Expected Features

All four areas constitute the v1.1 MVP. No area can be deferred without shipping a partial milestone.

**Must have (table stakes):**
- **Accounts:** Add/edit/delete Account with name, type, last-4, opening balance; manual balance entry + timestamp; per-account monthly spend total; account list view; link expenses via `sourceAccount` string matching to `accountID` FK
- **Self-Transfer:** 5-signal scorer (exact amount + both own accounts + opposite direction within 3 days + not categorised + not a reversal) surfaced to Transfer Inbox with three-state confirm (Mark as Transfer / Not a Transfer / Dismiss for now); `transferStateRaw` field on Expense; confirmed transfers excluded from ALL spend/budget queries
- **Asset Tracker:** Add/edit/delete holding (name, type, units, cost basis); current value = `units × currentNAV`; total net worth = holdings value + account balances; asset allocation chart (pie/donut via Swift Charts); manual NAV override with staleness label; MF NAV refresh from AMFI/mfapi.in (best-effort, non-blocking)
- **Notes/Daily Routine:** `Note.isRoutine` + `Note.routineTime` fields; `NoteBlock.lastCheckedDate` (the bug fix — replaces permanent `isChecked` bool for daily routines); per-day checkbox reset on `scenePhase .active` via `RoutineResetService`; daily notification via existing `NotificationScheduler`; calendar view shows routine as repeating event

**Should have (differentiators — include in v1.1 if time permits):**
- Color/SF Symbol per account for fast visual identification
- "Unlinked expenses" indicator after initial account setup
- Retroactive self-transfer detection over all historical expenses on first v1.1 launch
- Net transfer flow summary on Overview (₹X moved between own accounts this month)
- Holdings grouped by fund house; staleness badge per holding
- Multiple daily routines (morning + evening) as independent Notes

**Defer (v2+):**
- CloudKit sync for account balances, holdings, routine completions across devices
- Holding transaction log (purchase tranches) for XIRR calculation
- CAS or broker import for holdings
- Balance history snapshots → net-worth-over-time chart (NetWorthSnapshot model)
- Routine completion history log (RoutineCompletion model)

### Architecture Approach

The existing layered architecture (SwiftUI Views → Service/Aggregator layer → SwiftData/Persistence) extends cleanly for all four feature areas. New services follow established patterns: `SelfTransferDetector` mirrors `DedupChecker` (pure static struct), `NetWorthAggregator` mirrors `BudgetCalculator` (pure static enum), `PriceFetchService` mirrors `GmailSyncController` (owned via `@State`, not singleton), `RoutineResetService` is called from `RootView.onChange(of: scenePhase)` at the same hook as `GmailSyncController.scenePhaseChanged()`. The UUID FK pattern (`accountID: UUID?` on Expense rather than `@Relationship`) is the established CloudKit-safe approach already used by `GmailAccountStore`.

**Major components (new and modified):**
1. **SchemaV6 + AppMigrationPlan** — one additive migration stage; two new @Model types (Account, Asset); new fields on Expense, Note, NoteBlock; `didMigrate` closure for account backfill
2. **AccountsView + AccountLinkingService** — CRUD for accounts; post-creation backfill pass sets `accountID` on existing expenses by matching `sourceAccount` strings; `GmailSyncController` stamps `accountID` on new ingested expenses by looking up accounts by `gmailAddress`
3. **SelfTransferDetector + TransferConfirmView** — pure static scorer called after each sync batch; confirm UI reuses `ReviewInboxRow` pattern; flagged pairs get `transferStateRaw = "pendingReview"`
4. **PriceFetchService + NetWorthAggregator + AssetsView** — `@Observable` fetch service; `NetWorthAggregator.totalNetWorth(accounts:assets:)` is pure/synchronous; always renders from cached `lastKnownNav`
5. **RoutineResetService** — pure struct; called on `scenePhase .active`; resets `block.isChecked = false` on all blocks of routine notes where `routineLastResetDate < startOfToday`; explicit `context.save()` at end
6. **BudgetCalculator (modified)** — all spend queries gain `transferStateRaw != "confirmed"` predicate; confirmed transfers visible only in a dedicated Transfers section

**Key anti-patterns to avoid (all four agents agree):**
- `@Relationship` between Account and Expense (fan-out + CloudKit incompatibility) — use UUID FK
- Storing asset type as a Swift enum in @Model — use `assetTypeRaw: String?`
- PriceFetchService as a singleton — own as `@State` in AssetsView
- BGAppRefreshTask for routine reset — use `scenePhase .active` hook instead
- Replacing `sourceAccount` with `accountID` FK — keep both; sourceAccount is the dedup key

### Critical Pitfalls

1. **DayAgendaView EXC_BAD_ACCESS on cascade-deleted NoteBlock** — Guard every model property access in CalendarView/DayAgendaView with `isDeleted`/`modelContext != nil` check before accessing `block.isChecked` or `note.blocks`. Fix before any schema work. (PITFALLS.md Pitfall 1, vector c)

2. **GmailSyncController cross-actor Category references across await suspension points** — Capture only `[String: PersistentIdentifier]` before the `for messageID` loop; re-fetch `Category` by ID inside the same context after each await. Move `ctx.save()` outside the per-message loop — batch all inserts, one save after the loop. (PITFALLS.md Pitfall 1, vectors b and e)

3. **SchemaV6 backfill: sourceAccount string → accountID FK** — This is the single highest-risk migration task. Must have a non-nil `didMigrate` closure that walks all existing Expenses and links `accountID` by matching `sourceAccount` strings to Account entities. Requires a V5 fixture migration test under Swift Testing before shipping. Silent failure leaves all existing expenses unlinked with no crash or error. (PITFALLS.md Pitfall 4)

4. **Self-transfer false positives hiding real spend** — Never auto-exclude. The confirm flow is mandatory. Gate "own account" signal strictly: both `sourceAccount` values must resolve to known Account entities. Exact Decimal match only — no fuzzy amount tolerance for Indian bank alerts. (PITFALLS.md Pitfall 5)

5. **Stale asset prices presented without date context** — Every asset price shown must carry an "as-of date" label. Manual override must always be available. UI must never block on a network call; always render from `lastKnownNav` immediately, refresh in background. Amber stale badge when `navDate` is >1 trading day old. Parse NAV values as `String` → `Decimal(string:)`, never `Double`. (PITFALLS.md Pitfalls 6, 7, 8)

---

## Implications for Roadmap

### Suggested Build Order

```
Phase 1: Stabilization (bugs + routine data model fix)
    |
    v  (gates everything — no schema work until crashes are fixed)
Phase 2: SchemaV6 + Accounts Management
    |
    v  (gates self-transfer — needs Account entity for "own account" signal)
Phase 3: Self-Transfer Detection
    |
    v  (independent of assets; completes spend-accuracy picture before net-worth view)
Phase 4: Asset Tracker           (only needs Phase 2; can parallel Phase 3)
    |
Phase 5: Notes Enhancement       (only needs Phase 2; can parallel Phases 3 and 4)
```

Notes Enhancement and Asset Tracker can run in parallel or interleaved after SchemaV6 is complete; both only depend on the schema phase, not on each other or on Self-Transfer.

---

### Phase 1: Stabilization

**Rationale:** Two confirmed crash vectors and one data-model bug must be resolved before any schema or feature work. These fixes require no migration, no new models, and no new dependencies — they are pure logic/guard corrections. All four agents rank this as the unconditional gate.

**Delivers:**
- Crash-free Notes + Calendar: `DayAgendaView`/`AgendaReminderItem` `isDeleted` guard before accessing `block.isChecked` or `note.blocks`
- Crash-safe Gmail sync: `Category` PersistentIdentifier capture replaces live @Model reference across `await` suspension points; `ctx.save()` moved outside per-message loop
- Category sort order fix: `max(existing.sortOrder) + 1` on insert
- RoutineResetService skeleton wired to `scenePhase .active` (the `lastCheckedDate` field itself lands in SchemaV6 in Phase 2; Phase 1 ships the crash fixes and seeds the service structure)

**Addresses:** FEATURES.md "Stabilisation fixes: category ordering, sync/notes crash" (P1 must-have)

**Avoids:** PITFALLS.md Pitfalls 1 (crash), 2 (stale routine completion), 3 (category sort), 10a (timezone routine reset)

**Research flag:** Standard patterns; no research phase needed.

**TENSION — routine fix phasing:** FEATURES.md and PITFALLS.md classify the routine data-model fix as Phase 1. ARCHITECTURE.md places the `lastCheckedDate` field addition in SchemaV6. **Resolution:** The RoutineResetService logic and the DayAgendaView guard ship in Phase 1 (no schema change required for the guard). The `lastCheckedDate` field is bundled into SchemaV6 in Phase 2 to avoid an intermediate migration stage. Phase 1 delivers the crash fixes and service skeleton; Phase 2 completes the data model and wires the full per-day reset.

---

### Phase 2: SchemaV6 + Accounts Management

**Rationale:** SchemaV6 is the foundation for all feature areas. All new models, fields, and migration stages must be in place before any feature that reads or writes them. Accounts is bundled here because Account is the first new @Model and its `didMigrate` backfill is the riskiest migration task — validating it early contains that risk before other features build on top.

**Delivers:**
- SchemaV6 migration: `Account` and `Asset` @Model types; `Expense.accountID`, `isTransfer`, `transferPairID`, `transferConfirmed`, `transferStateRaw`; `Note.isRoutine`, `routineLastResetDate`; `NoteBlock.lastCheckedDate`
- `v5ToV6` `didMigrate` closure: backfills `expense.accountID` from `sourceAccount` strings; covered by a migration test against a real V5 fixture store
- `sourceAccount` field retained unchanged on `Expense` — it is the Gmail dedup key, must not be removed
- AccountsView CRUD (add/edit/delete Account; manual balance; last-updated timestamp)
- AccountLinkingService: post-creation backfill pass + GmailSyncController `accountID` stamping on new ingested expenses
- Per-account monthly spend total (filtered @Query on Expense)
- `NoteBlock.lastCheckedDate` wired into RoutineResetService; full per-day reset operational

**Addresses:** FEATURES.md Accounts table stakes (all five)

**Avoids:** PITFALLS.md Pitfall 4 (sourceAccount → Account migration data loss); Pitfall 1.6 (ModelContainer migration crash)

**Research flag:** The `didMigrate` closure pattern may benefit from a focused planning research pass. This is the codebase's first non-nil `didMigrate` closure — verify error-handling behavior (does a throwing closure roll back or leave the store partially migrated?) against the existing `FB13812722` workaround in `MigrationPlan.swift`. All other Accounts work is standard SwiftData CRUD.

---

### Phase 3: Self-Transfer Detection

**Rationale:** Requires the Account entity (Phase 2) to be complete — the "both accounts are own accounts" signal is the essential false-positive gate. The `transferStateRaw` and other Expense transfer fields are already in SchemaV6 from Phase 2.

**Delivers:**
- `SelfTransferDetector` pure static struct: 5-signal scorer, 3-day calendar window, exact Decimal amount match, own-account gate
- Transfer Inbox (TransferConfirmView): three-state confirm UI reusing `ReviewInboxRow` pattern; separate section from low-confidence parse inbox
- `BudgetCalculator` and `SpendOverTimeAggregator` updated: `transferStateRaw != "confirmed"` predicate on all spend queries
- Retroactive detection pass on v1.1 first launch over historical expenses
- Net transfer flow summary on Overview

**Addresses:** FEATURES.md Self-Transfer table stakes and differentiators

**Avoids:** PITFALLS.md Pitfall 5 (false positives); UX pitfall of auto-exclusion without confirmation

**Research flag:** Standard patterns — signal scorer logic and ReviewInboxRow reuse are well-understood. No research phase needed. During planning, spot-check a sample of the household's historical expenses to validate the 3-day window covers all actual self-transfers (the window is reasoned but unvalidated against real data).

---

### Phase 4: Asset Tracker

**Rationale:** Depends only on SchemaV6 (Phase 2). Independent of Self-Transfer (Phase 3) and Notes Enhancement (Phase 5). Can be built in parallel with Phase 3 in a two-track workflow; in single-track serial order it comes after Self-Transfer to keep spend-accuracy complete before net-worth is built.

**Delivers:**
- `Asset` @Model CRUD (add/edit/delete holding; units, cost basis, manual NAV override)
- PriceFetchService: AMFI NAVAll.txt bulk parse (primary MF source); mfapi.in (fallback/onboarding search); Yahoo Finance `v8/finance/chart` for stocks (best-effort, timeout < 3s); npsnav.in for NPS (best-effort)
- NetWorthAggregator: pure static `totalNetWorth(accounts:assets:)`
- NetWorthView: account balances + holdings; "as of [date]" label on every price; amber stale badge for NAVs older than 1 trading day; always renders from `lastKnownNav` (never blocks)
- Asset allocation chart (pie/donut by type via Swift Charts)
- Manual NAV override with "manual" badge

**Addresses:** FEATURES.md Asset Tracker table stakes (all seven)

**Avoids:** PITFALLS.md Pitfalls 6 (unofficial endpoint breaking), 7 (Decimal vs Double), 8 (stale price as live), 10b (timezone NAV date parsing with `TimeZone(identifier: "Asia/Kolkata")`)

**Research flag:** AMFI NAVAll.txt field format and Yahoo Finance response structure are already verified in STACK.md. No additional research phase needed. If Yahoo Finance breaks during implementation: fall back to manual-only for stocks without delay; do not chase alternative endpoints.

---

### Phase 5: Notes Enhancement (Daily Routine Calendar Reminder)

**Rationale:** Depends only on SchemaV6 (Phase 2). Independent of Phases 3 and 4. In single-track serial order it comes last; it can be parallelized with Phase 4 once Phase 2 is complete.

**Delivers:**
- `Note.isRoutine` toggle in EditNoteView; `Note.routineTime` time picker
- RoutineResetService fully wired: resets `block.isChecked = false` where `routineLastResetDate < startOfToday(IST)`; explicit `context.save()`; called from `RootView.onChange(of: scenePhase)` on `.active`
- Daily notification via existing `NotificationScheduler` with `.daily` recurrence; `schedule()` called only on enable/edit, never on every BGAppRefreshTask run
- CalendarAggregator integration: `isRoutine = true` notes surface as repeating daily events in CalendarView (no changes to CalendarAggregator needed — existing `reminderEnabled = true` + `RecurrenceType.daily` path already handles this)
- Multiple routines supported via independent Notes with `isRoutine = true`

**Addresses:** FEATURES.md Notes Enhancement table stakes (all six)

**Avoids:** PITFALLS.md Pitfall 9 (notification explosion from re-scheduling on every BGAppRefreshTask); Pitfall 10a (timezone routine reset must use `Calendar.current` with explicit `timeZone = TimeZone.current`, not UTC calendar)

**Research flag:** All infrastructure exists. The only new code is thin wiring. No research phase needed. One unit test is critical and must be written: call `schedule()` N times for the same reminder ID and assert `pendingCount() == 1`.

---

### Phase Ordering Rationale

- **Stabilization before schema:** Crash fixes are no-migration logic changes; doing schema work on a crashing app risks masking or compounding crash vectors and makes debugging harder.
- **SchemaV6 + Accounts before Self-Transfer:** The "both accounts are own accounts" signal is the false-positive gate — Account entity must exist before the scorer is meaningful.
- **SchemaV6 before Assets and Notes Enhancement:** Both depend on new @Model fields in SchemaV6.
- **Assets and Notes Enhancement are parallel after SchemaV6:** Neither depends on the other; both depend only on the schema phase.
- **Self-Transfer before Assets in serial order:** Self-Transfer completes the spend-accuracy picture (confirmed transfers excluded from totals) before the net-worth view is built, ensuring net-worth figures are correct from day one.

### Research Flags

Phases needing deeper research during planning:
- **Phase 2 (`didMigrate` closure):** First non-nil `didMigrate` closure in this codebase. Recommend a focused research pass on SwiftData custom migration error-handling behavior before writing the migration stage.

Phases with standard patterns (skip research phase):
- **Phase 1 (Stabilization):** Root causes are confirmed; fixes are deterministic.
- **Phase 3 (Self-Transfer):** Signal scorer and ReviewInboxRow reuse are well-understood. Spot-check historical data during planning to validate the 3-day window.
- **Phase 4 (Asset Tracker):** AMFI and Yahoo Finance formats are verified. PriceFetchService mirrors existing GmailSyncController pattern.
- **Phase 5 (Notes Enhancement):** All infrastructure exists; thin wiring only.

---

## Confidence Assessment

| Area | Confidence | Notes |
|------|------------|-------|
| Stack | HIGH | v1.0 stack unchanged; v1.1 data sources verified June 2026; Yahoo Finance is LOW for that specific source but overall stack is HIGH |
| Features | HIGH | All four areas well-scoped; dependency graph is clear; anti-features explicitly called out |
| Architecture | HIGH | Based on direct codebase reading (SchemaV5, MigrationPlan, GmailSyncController, CalendarView, NotificationScheduler); no speculation |
| Pitfalls | HIGH | Root causes confirmed against codebase + Apple Developer Forums; crash vectors are identified, not inferred |

**Overall confidence:** HIGH

### Gaps to Address

- **SchemaV6 `didMigrate` closure error handling:** The codebase has no prior example of a non-nil `didMigrate` closure. Before writing it, validate whether a throwing `didMigrate` rolls back the migration or leaves the store in a partial state — particularly in the context of the existing `FB13812722` workaround in `MigrationPlan.swift`.

- **Self-transfer 3-day window validation:** The 3-day window is well-reasoned for Indian domestic settlement (NEFT/IMPS/UPI) but has not been validated against the household's actual transaction history. Spot-check historical expenses during Phase 3 planning to confirm 3 days is sufficient and does not miss weekend-lag transfers.

- **Yahoo Finance rate-limit behavior for this household:** A 2-person household with ~10–20 stock holdings fetching once per day is far below the reported ~360 req/hr community cap. The accepted risk is that the endpoint can add auth requirements without notice. The implementation must fall back to manual immediately on any non-200 or decode error — do not retry.

- **npsnav.in availability guarantee:** Single-maintainer hobby project. App must degrade gracefully to last-known NAV on any fetch failure. Manual override is the primary NPS entry path; treat the API as a convenience-only enhancement.

---

## Sources

### Primary (HIGH confidence)
- Direct codebase reading — `SchemaV5.swift`, `MigrationPlan.swift`, `GmailSyncController.swift`, `CalendarView.swift`, `NotificationScheduler.swift`, `CalendarAggregator.swift`, `ReviewInboxRow.swift`, `GmailAccountStore.swift`
- `portal.amfiindia.com/spages/NAVAll.txt` — Verified field format June 2026; semicolon-delimited; Scheme Code field 1, NAV field 5, Date field 6 in DD-MMM-YYYY format
- developer.apple.com — Swift 6.2, Xcode 26, SwiftData iOS 17+, `@Observable`, `BGAppRefreshTask`
- github.com/apple/swift-testing — Bundled in Swift 6 toolchain; parameterized + parallel + async-native

### Secondary (MEDIUM confidence)
- `api.mfapi.in/mf/{schemeCode}` — Verified June 2026; JSON; `data[0].nav` string decimal; community-maintained AMFI wrapper
- `npsnav.in/api/latest-min` — Verified June 2026; JSON `[schemeCode, nav]` pairs; data from Protean CRA (official PFRDA-appointed CRA); single-maintainer open-source aggregator
- YNAB transfer matching documentation — Exact-amount-match requirement and two-transaction rule; adapted to 3-day window for Indian settlement
- Apple Developer Forums — SwiftData EXC_BAD_ACCESS, cross-actor ModelContext violations, migration relationship crashes (forums.developer.apple.com/forums/thread/745424, /757820)
- fatbobman.com, simplykyra.com, delasign.com — SwiftData threading and deleted-object crash patterns

### Tertiary (LOW confidence)
- `query1.finance.yahoo.com/v8/finance/chart/{sym}` — Verified working June 2026; `chart.result[0].meta.regularMarketPrice`; undocumented, no formal ToS coverage; `~360 req/hr` rate limit per community reports (github.com/ranaroussi/yfinance issue #2128)
- 0xramm/Indian-Stock-Market-API, maanavshah/stock-market-india — Unofficial Yahoo Finance wrappers for India stocks; confirms fragility of the ecosystem

---

*Research completed: 2026-06-08*
*Ready for roadmap: yes*
