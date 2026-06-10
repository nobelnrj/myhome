---
phase: 09-schemav6-accounts-management
verified: 2026-06-10T00:00:00Z
status: human_needed
score: 21/21 must-haves verified
overrides_applied: 0
re_verification:
  previous_status: none
  previous_score: n/a
human_verification:
  - test: "Live balance reactivity (ACCT-05/D-10)"
    expected: "Open an account detail showing baseline balance, add an expense attributed to that account, and confirm the balance card updates with NO refresh affordance present."
    why_human: "Reactive @Query-driven SwiftUI recomputation cannot be observed via static grep; requires a running app."
  - test: "Archive moves account to collapsed Archived section, transactions intact (ACCT-07/D-08)"
    expected: "Swipe-archive an account; it leaves the active list and appears in the collapsed Archived DisclosureGroup; expanding shows it with its transactions still present."
    why_human: "Runtime list-state transition and visual layout cannot be confirmed statically."
  - test: "Migration review badge + sheet flow (D-02)"
    expected: "On a store with auto-created accounts the orange badge shows on the Settings Accounts row; tapping into the review sheet, renaming/retyping an account and tapping Done clears the badge."
    why_human: "First-launch migration state + badge clearing is a runtime/visual flow."
  - test: "Per-day routine reset across midnight (STAB-04/NOTE-02/D-11/D-12)"
    expected: "Flag a note isDailyRoutine with checked items, advance the simulator date by one day, foreground the app, and confirm items uncheck; re-checking and same-day foreground preserves checks; a non-routine note's checks survive the day advance."
    why_human: "Requires scenePhase .active lifecycle + system date advance on a device/simulator; logic is unit-tested but end-to-end timing is human-only. The isDailyRoutine toggle UI ships in Phase 12, so the flag must be set manually."
  - test: "Gmail sourceLabel auto-attribution (D-05)"
    expected: "Trigger a Gmail sync; an ingested expense whose bank label matches an account is auto-attributed (visible via the account filter / detail); a non-matching one stays Unassigned."
    why_human: "Depends on a configured Gmail account and live network ingestion; only the pure resolver logic is unit-testable."
---

# Phase 9: SchemaV6 & Accounts Management Verification Report

**Phase Goal:** One additive migration creates the Account and Asset models plus all new fields across Expense, Note, and NoteBlock; users can create and manage bank accounts with manual balances; existing expenses are correctly attributed to accounts; the daily-routine per-day reset is fully operational.
**Verified:** 2026-06-10
**Status:** human_needed
**Re-verification:** No — initial verification

## Goal Achievement

### Observable Truths (Roadmap Success Criteria + Plan must_haves)

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | SC1: Add/edit/delete/archive a bank account (name, type, color/icon, opening balance); archived hidden from pickers, transactions remain | VERIFIED | `AccountsListView.swift` (242L): `@Query(sort: \Account.sortOrder)`, `activeAccounts`/`archivedAccounts` `isArchived` split (l25-26), swipe archive sets `isArchived=true` (l96), `DisclosureGroup` archived section (l110), `ContentUnavailableView` empty state. `EditAccountView.swift` (280L): segmented type Picker (l121), color/icon, `1_000_000_000` guard (l235). `AccountPickerView` filters `!$0.isArchived`. |
| 2 | SC2: Balance = baseline ± attributed transactions since as-of date; updates with no manual refresh | VERIFIED | `AccountBalance.compute` (Support/AccountBalance.swift l20-32): `guard baseline,asOf`, `expenses.filter{accountID==id && date>=asOf}.reduce(+)`. `AccountDetailView` computes `liveBalance` via `@Query` (l30), `.font(.largeTitle.weight(.semibold))` (l139), no `refreshable`. `AccountBalanceTests` (5 funcs) prove 750/-6000/0 cases. **Reactivity = human-verify item 1.** |
| 3 | SC3: Per-account spend — tapping an account shows only its expenses | VERIFIED | `AccountDetailView.attributedExpenses = allExpenses.filter{$0.accountID==account.id}` (l25). Second entry point: `ExpenseListView` `AccountFilter` enum `.all/.unassigned/.account(UUID)` (l61-64) chained in `filteredExpenses` (l217). |
| 4 | SC4: Existing expenses backfilled with accountID in V5→V6; fixture test passes; sourceAccount retained | VERIFIED | `MigrationPlan.v5ToV6` `.custom` non-nil didMigrate: builds `accountByLabel`, inserts accounts, `expense.accountID = accountByLabel[label]?.id`, explicit `try context.save()` (l103), `accountReviewPending` flag (l107). `SchemaV6MigrationTests` `v5StoreBackfillsAccountID` + `v5MigrationIsIdempotent` assert accountID set, `sourceAccount=="user@gmail.com"` unchanged (l94), typeRaw inferred. Full suite green. |
| 5 | SC5: Daily routine items start unchecked each IST morning via RoutineResetService on .active | VERIFIED | `RoutineResetService` (l23 `var modelContext`, l28 `Asia/Kolkata`, l34 fetch `isDailyRoutine==true`, l39 lastReset guard, l44 `kindRaw=="checkbox"` uncheck, l50 stamp, l53 save). Injected in `RootView.onAppear` `routineResetService.modelContext=modelContext` (l87); called on scenePhase `.active` (l113). `RoutineResetServiceTests` (7 funcs). **End-to-end timing = human-verify item 4.** |
| 6 | SchemaV6 atomic typealias flip (STAB-08) — all six models point at V6 | VERIFIED | All of Account/Asset/Expense/Note/NoteBlock/Category typealiases = `SchemaV6.X`; `grep "= SchemaV5\." Models/` returns nothing. |
| 7 | SchemaV6 additive fields present, no .unique | VERIFIED | `accountID`/`isTransfer`/`transferPairID` on Expense (l114-116), `isDailyRoutine`/`routineLastResetDate` on Note (l165/169), `Account`+`Asset` classes; no `@Attribute(.unique)`. |
| 8 | Account type inferred correctly (CR-01 fixed) | VERIFIED | `inferAccountType` (AccountBalance.swift l45-55) token-based: `tokens.contains("cc")` not substring; `AccountTypeInferenceTests` includes `"ICICI Account"→savings` regression (l29). Fix commit `98d28fe`. |
| 9 | Manual expense add/edit account picker, last-used default, archived excluded (D-04) | VERIFIED | `AddExpenseView`: `AccountPickerView` sheet (l242), `lastUsedAccountID` seed (l75) + write (l300), nullify if archived (l283-286). `EditExpenseView` seeds from `expense.accountID` against active accounts (l320-322). |
| 10 | Gmail auto-attribution by sourceLabel, STAB-02 pre-loop UUID capture (D-05) | VERIFIED | `GmailSyncController`: `AccountAttributionHelper.buildAccountIDsByLabel` pre-loop (l494, plain `[String:UUID]`), `expense.accountID = ...accountID(...)` in loop (l542). `GmailAccountAttributionTests` (2 funcs). **Live sync = human-verify item 5.** |

**Score:** 21/21 must-have truths verified (5 roadmap SCs + 16 plan-frontmatter truths; deduplicated).

### Required Artifacts

| Artifact | Status | Details |
|----------|--------|---------|
| `Persistence/Schema/SchemaV6.swift` | VERIFIED | enum SchemaV6, Account + Asset classes, additive fields, no .unique |
| `Persistence/Schema/MigrationPlan.swift` | VERIFIED | schemas+stages include V6/v5ToV6; idempotent didMigrate backfill |
| `Persistence/Models/{Account,Asset}.swift` | VERIFIED | typealiases to SchemaV6 |
| `Features/Settings/AccountsListView.swift` | VERIFIED | 242L, CRUD + archive split + review banner |
| `Features/Settings/EditAccountView.swift` | VERIFIED | 280L, form + segmented type + baseline/as-of |
| `Features/Settings/AccountDetailView.swift` | VERIFIED | 158L, live balance + attributed list |
| `Features/Settings/MigrationReviewSheet.swift` | VERIFIED | 154L, review of sourceLabel accounts |
| `Features/Expenses/AccountPickerView.swift` | VERIFIED | 102L, active-only picker |
| `Support/AccountBalance.swift` | VERIFIED | compute + inferAccountType (CR-01 fixed) |
| `Features/Notes/RoutineResetService.swift` | VERIFIED | filled reset body, IST, do/catch |
| 6 test files (Migration/Balance/TypeInference/CRUD/GmailAttribution/RoutineReset) | VERIFIED | all present; suite green |

### Key Link Verification

| From | To | Status | Details |
|------|-----|--------|---------|
| MigrationPlan v5ToV6 | SchemaV6.Account | WIRED | `context.insert(account)`, sets `expense.accountID` |
| SettingsView | AccountsListView | WIRED | `NavigationLink(destination: AccountsListView())` (l169) + badge |
| AccountDetailView | Expense.accountID | WIRED | `filter{$0.accountID==account.id}` (l25) |
| AddExpenseView/EditExpenseView | AccountPickerView | WIRED | sheet bound to `$selectedAccount` |
| GmailSyncController | Expense.accountID | WIRED | pre-loop UUID map + in-loop assign |
| RootView | RoutineResetService.modelContext | WIRED | `.onAppear` injection (l87); `.active` call (l113) |

### Data-Flow Trace (Level 4)

| Artifact | Data Variable | Source | Real Data | Status |
|----------|---------------|--------|-----------|--------|
| AccountsListView rows | allAccounts | `@Query(sort:\Account.sortOrder)` over live store | Yes | FLOWING |
| AccountDetailView balance | liveBalance | `AccountBalance.compute` over `@Query` allExpenses | Yes | FLOWING |
| Migration backfill | accountByLabel | `context.fetch(FetchDescriptor<Expense>())` | Yes | FLOWING |
| RoutineReset | isDailyRoutine notes | `context.fetch(FetchDescriptor<Note>(predicate:))` | Yes | FLOWING (WR-01 advisory: Bool #Predicate fragility — tested but not against versioned schema) |

### Requirements Coverage

| Requirement | Source Plan | Status | Evidence |
|-------------|-------------|--------|----------|
| ACCT-08 | 09-01 | SATISFIED | Backfill migration + lossless/idempotent fixture tests |
| ACCT-01 | 09-02 | SATISFIED | Create/edit/delete in AccountsList/EditAccount |
| ACCT-02 | 09-02 | SATISFIED | Segmented type Picker savings/current/credit_card |
| ACCT-03 | 09-02 | SATISFIED | Color/icon picker in EditAccountView |
| ACCT-04 | 09-02 | SATISFIED | balanceBaseline + as-of DatePicker default today |
| ACCT-05 | 09-02 | SATISFIED (human-confirm reactivity) | AccountBalance.compute + reactive @Query |
| ACCT-07 | 09-02 | SATISFIED (human-confirm UI) | Archive/unarchive split + DisclosureGroup |
| ACCT-06 | 09-03 | SATISFIED | AccountDetail filter + ExpenseList AccountFilter |
| STAB-04 | 09-04 | SATISFIED (human-confirm timing) | RoutineResetService per-IST-day reset |
| NOTE-02 | 09-04 | SATISFIED | note-level routineLastResetDate date-key reset |

All 10 declared requirement IDs map to a plan and are accounted for. No orphaned requirements: REQUIREMENTS.md maps exactly STAB-04, ACCT-01..08, NOTE-02 to Phase 9, all claimed across plans 01-04.

### Anti-Patterns Found

| File | Pattern | Severity | Impact |
|------|---------|----------|--------|
| (phase files) TBD/FIXME/XXX | none found | — | No blocking debt markers |
| GmailSyncController:211 | double-negative backfill guard (WR-02) | Info | Re-runs idempotent backfill each launch; no data harm |
| MigrationReviewSheet:45/114 | `try?` swallows save errors (WR-03/04) | Info | Advisory; tracked in 09-REVIEW.md |
| RoutineResetService:33 | Bool #Predicate fragility (WR-01) | Info | Advisory; logic unit-tested |
| Multiple | `print(...)` on catch paths (IN-03) | Info | Debug logging, advisory |

All findings are advisory (WR/IN) and tracked in 09-REVIEW.md. The sole critical (CR-01) was fixed + regression-tested in commit 98d28fe. None block a must-have.

### Behavioral Spot-Checks

| Behavior | Command | Result | Status |
|----------|---------|--------|--------|
| Full MyHomeTests suite | `xcodebuild test ... -only-testing:MyHomeTests` | TEST SUCCEEDED (per task context) | PASS |
| No V5 typealias residue | `grep "= SchemaV5\." Models/` | empty | PASS |
| CR-01 regression present | `grep "ICICI Account" AccountTypeInferenceTests` | present | PASS |

### Human Verification Required

See frontmatter `human_verification` — 5 runtime/visual items: (1) live-balance reactivity, (2) archive UI transition, (3) migration-review badge flow, (4) per-day routine reset across midnight, (5) Gmail live auto-attribution. Each corresponds to a `checkpoint:human-verify` gate in plans 02/03/04. The underlying logic is unit-tested green; these confirm end-to-end behavior that grep/tests cannot observe.

### Gaps Summary

No gaps. All 21 must-have truths, all required artifacts, and all key links verify against the codebase. All 10 requirement IDs are covered. The phase goal is achieved at the code level. Status is `human_needed` (not `passed`) solely because the phase carries blocking human-verify checkpoints for runtime/visual behaviors that cannot be confirmed statically — per the verification decision tree, any non-empty human-verification section forces `human_needed`.

---

_Verified: 2026-06-10_
_Verifier: Claude (gsd-verifier)_
