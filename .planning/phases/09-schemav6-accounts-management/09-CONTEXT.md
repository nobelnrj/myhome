# Phase 9: SchemaV6 & Accounts Management - Context

**Gathered:** 2026-06-09
**Status:** Ready for planning

<domain>
## Phase Boundary

One **additive** V5→V6 SwiftData migration plus full Accounts management:

1. **SchemaV6 migration** — adds the `Account` model, the `Asset` model (schema-only scaffold for Phase 11; no UI this phase), `accountID` + transfer-scaffold fields on `Expense`, and routine fields on `Note`/`NoteBlock`. CloudKit-ready: every field optional/defaulted, no `.unique`, Decimal for money, UTC dates. This is the codebase's **first non-nil `didMigrate`** (used to auto-create + backfill accounts).
2. **Accounts CRUD** (ACCT-01/02/03/07) — create/edit/delete/archive a bank account with name, type, color/icon, optional last-4. Managed under **Settings**.
3. **Balance baseline + live balance** (ACCT-04/05) — manual opening balance with an as-of date; displayed balance = baseline ± attributed transactions since the as-of date, computed live (no manual refresh).
4. **Attribution** (ACCT-08) — additive `accountID` on Expense; `sourceAccount` (Gmail mailbox dedup key) untouched. Legacy expenses backfilled during migration; new Gmail-ingested expenses auto-attributed by `sourceLabel`.
5. **Per-account spend** (ACCT-06) — reachable two ways: account detail screen (Settings) + account filter on the main expense list.
6. **Daily-routine per-day reset** (STAB-04 / NOTE-02) — fills the Phase 8 `RoutineResetService` stub; routine-flagged notes reset their checklist each IST morning.

**Out of scope (later phases):** self-transfer detection + Transfer Inbox (Phase 10 — Phase 9 only scaffolds the transfer fields in V6), Asset Tracker UI / NAV fetch / net-worth (Phase 11 — V6 ships the `Asset` model only), the "mark note as routine" UI toggle and streak/history (Phase 12).

</domain>

<decisions>
## Implementation Decisions

### Migration backfill & attribution
- **D-01:** V5→V6 `didMigrate` **auto-creates one Account per distinct non-nil `sourceLabel`** (e.g. "HDFC CC", "ICICI Savings") and sets each existing expense's `accountID`. Expenses with nil `sourceLabel` stay `accountID = nil` ("Unassigned"). Grouping key is **`sourceLabel`** (human-readable bank), NOT `sourceAccount` (which is the owning Gmail mailbox email / dedup key).
- **D-02:** Auto-created accounts surface in an **editable review list on first launch after migration** — user can rename / merge / delete before they're locked in. Migration writes are idempotent (re-running must not duplicate accounts).
- **D-03:** Auto-created account **type is inferred**: `sourceLabel` containing "CC" / "credit" / "card" (case-insensitive) → `credit card`; everything else → `savings`. User corrects wrong guesses in the review step.
- **D-04:** Manual expense add/edit has an **optional account picker that defaults to the last-used account**; leaving it blank = Unassigned. Mirrors how categories/tags already behave (low friction, preserves quick-add).
- **D-05:** Going forward, **Gmail sync auto-attributes** a newly-ingested expense to the account whose name/label matches its `sourceLabel`; no match → `accountID = nil` (Unassigned). This is the natural extension of the D-01 backfill logic into the live ingestion path.

### Accounts placement & navigation
- **D-06:** Account **management (create/edit/delete/archive) lives under Settings** — `Settings > Accounts`. Not a top-level tab, not an Overview section.
- **D-07:** **Per-account spend is reachable two ways** (ACCT-06): (a) tapping an account in the Settings > Accounts list opens its **detail screen** (balance, as-of date, attributed transaction list / monthly spend), and (b) an **account filter on the main expense list**. CRUD stays in Settings; spend is a first-class filter elsewhere.
- **D-08:** **Archive** (ACCT-07): an archived account is **hidden from the expense account-picker and active lists, but its past transactions remain visible & attributed**, and it appears in a collapsed "Archived" section in Settings > Accounts that can be expanded. (Matches success criterion 1 exactly.)

### Balance semantics
- **D-09:** **Credit-card balance is shown as negative (amount owed)** — savings/current show positive available cash; a credit card goes more negative as you spend and toward zero as you pay. Net worth = simple sum, so CC debt subtracts naturally (keeps Phase 11 net-worth math a plain addition with no per-type special-casing).
- **D-10:** **Opening balance = amount + as-of date picker, defaulting to today.** Live balance = baseline ± transactions dated on/after the as-of date. Re-setting the baseline later re-anchors from the new as-of date. Balance is computed (not stored) so it updates without manual refresh (ACCT-05).

### Routine reset scope
- **D-11:** **SchemaV6 adds an `isDailyRoutine: Bool = false` field to `Note`** (the roadmap's "routine fields"). `RoutineResetService` resets checklist blocks **only on notes flagged `isDailyRoutine`** — ordinary checklists are never auto-unchecked. Phase 12's UI toggle simply flips this flag; the data seam + correct reset behavior land now.
- **D-12:** **Reset uses a note-level `routineLastResetDate`** marker (not per-block date-keying). On `scenePhase .active`, if `routineLastResetDate < startOfToday` in **IST**, set `isChecked = false` on all that note's checklist blocks and stamp the new date. Idempotent — repeated `.active` events the same day are no-ops. See reconciliation note below.

### Claude's Discretion
- Account color/icon picker UX (ACCT-03) — follow the existing category symbol/color picker pattern in `ManageCategoriesView`.
- Exact `Asset` model field shape — scaffold for Phase 11; planner/Phase-11 researcher refines. Phase 9 only needs a CloudKit-ready, additive model present in V6.
- Exact transfer-scaffold fields on `Expense` (e.g. `isTransfer`, `transferPairID`) — add minimally so Phase 10 needs no further migration; Phase 10 owns the semantics.
- Migration `didMigrate` error-handling (throw → rollback vs. partial state) — **must** be verified against the FB13812722 workaround before writing (see canonical refs / roadmap research flag).
- Test-harness shape for the V5→V6 fixture test — follow existing Swift Testing + in-memory `ModelContainer` patterns.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Roadmap & requirements (binding contract)
- `.planning/ROADMAP.md` §"Phase 9: SchemaV6 & Accounts Management" — goal + 5 success criteria
- `.planning/ROADMAP.md` §"Cross-Phase Notes" — STAB-04/NOTE-02 split, ACCT-05/XFER cross-reference, NOTE-02-in-Phase-9 rationale, **Phase 9 research flag** (first non-nil `didMigrate`; verify FB13812722 throw/rollback behavior)
- `.planning/REQUIREMENTS.md` — STAB-04, ACCT-01…ACCT-08, NOTE-02 requirement text + the "sourceAccount retained as dedup key" constraint and v1.1 constraints (local-only, CloudKit-ready, no `.unique`)

### Schema & migration (read before writing V6)
- `MyHomeApp/Persistence/Schema/MigrationPlan.swift` — `AppMigrationPlan`; append `SchemaV6.self` (never remove V1–V5); the `.custom(willMigrate:nil, didMigrate:nil)` FB13812722 rationale — V6 introduces the first non-nil `didMigrate`
- `MyHomeApp/Persistence/Schema/SchemaV5.swift` — V5 models to copy verbatim into V6; CloudKit-readiness rules (1–8) at top of file; `Expense.sourceAccount` / `sourceLabel` / `gmailMessageID` semantics; `Note` / `NoteBlock` fields; the STAB-03 `sortOrder` footgun comment
- Memory: `[[schema-version-mutation-footgun]]` — flip ALL `Note`/`NoteBlock` (and any) typealiases to SchemaV6 together when bumping; mismatched typealias caused the STAB-08 save/query crash

### Models & integration surfaces
- `MyHomeApp/Persistence/Models/` — `Expense.swift`, `Note.swift`, `NoteBlock.swift`, `Category.swift` (typealias targets to flip to V6)
- `MyHomeApp/Features/Gmail/GmailSyncController.swift` — `syncAccount`; where D-05 auto-attribution-by-`sourceLabel` hooks in (and the Phase 8 batched-save / category re-fetch refactor)
- `MyHomeApp/Features/Settings/` — host location for `Settings > Accounts` (D-06)
- `MyHomeApp/Features/Expenses/` — main expense list (D-07 account filter) + expense add/edit form (D-04 account picker)
- `MyHomeApp/Features/Budgets/ManageCategoriesView.swift` — color/icon picker + `max/min(sortOrder)` insertion pattern to reuse for accounts
- `MyHomeApp/RootView.swift` §`scenePhase .active` — `RoutineResetService` wiring seam (Phase 8 stub) for D-11/D-12

### Prior context
- `.planning/phases/08-stabilization/08-CONTEXT.md` — RoutineResetService scaffold (D-06/D-07), IST start-of-today seam, live-binding constraint, sourceAccount-as-dedup-key

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `RoutineResetService` stub + `RootView.scenePhase .active` wiring (Phase 8) — D-11/D-12 fill the body; the IST `startOfToday` comparison was already sketched here.
- `ManageCategoriesView` symbol/color picker + sort-order insertion — reuse for the account color/icon picker (ACCT-03) and any ordered account list.
- Existing expense list + filter machinery (categories/tags) — D-07 account filter and D-04 optional-account picker should follow these established patterns.
- Existing Settings feature module — host for Settings > Accounts (D-06).

### Established Patterns
- Additive-only versioned schemas; `.custom` stages over `.lightweight` to dodge FB13812722. V6 keeps this but adds the **first non-nil `didMigrate`** for backfill — verify throw/rollback semantics first.
- All `@Model` typealiases must point at the same schema version (STAB-08 lesson) — flip every typealias to V6 in one commit.
- Money is `Decimal`; dates are UTC stored, formatted/compared in IST at the edge.
- Gmail sync tolerates per-message failures and batches `ctx.save()` once (Phase 8) — D-05 attribution must not reintroduce per-message saves or unguarded post-`await` references.

### Integration Points
- V5→V6 `didMigrate` ← reads distinct `sourceLabel` values, creates `Account`s, sets `Expense.accountID` (D-01/D-02/D-03).
- `GmailSyncController.syncAccount` ← `sourceLabel`→account auto-match on new ingestion (D-05).
- Settings ← new Accounts CRUD + per-account detail (D-06/D-07).
- Expense list / add-edit form ← account filter + optional account picker (D-04/D-07).
- `RootView` scenePhase ← completed `RoutineResetService.resetIfNeeded()` (D-11/D-12).

</code_context>

<specifics>
## Specific Ideas

- **Reset-mechanism reconciliation (flag for planner):** Roadmap success criterion 5 wording mentions BOTH a per-block `lastCheckedDate` AND a note-level `routineLastResetDate`. The user chose the **note-level `routineLastResetDate`** as the Phase 9 reset mechanism (D-12). The note-level marker fully satisfies the observable per-day reset behavior. Per-block per-day completion *logging* (`lastCheckedDate`) is only actually needed for Phase 12's streak/history (NOTE-05) — defer adding per-block date fields to Phase 12 unless the planner finds a Phase 9 need. Do not block the phase on the literal field name.
- Build/run on iPhone 17 simulator, Xcode 26.5, scheme `MyHome`, iOS 17+.
- IST (`Asia/Kolkata`) is the household timezone for all "start of today" comparisons.
- Success criterion 4 requires a **Swift Testing fixture test against a real V5 store** proving lossless V5→V6 backfill before the phase ships.

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope. (Self-transfer detection, Asset Tracker UI/NAV/net-worth, and the routine-marking toggle + streak/history are already roadmapped to Phases 10–12.)

</deferred>

---

*Phase: 9-SchemaV6 & Accounts Management*
*Context gathered: 2026-06-09*
