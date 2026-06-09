# Phase 9: SchemaV6 & Accounts Management — Research

**Researched:** 2026-06-09
**Domain:** SwiftData staged migration (first non-nil `didMigrate`), SwiftUI CRUD, reactive computed balance
**Confidence:** HIGH (schema/migration/test patterns verified from codebase); MEDIUM (didMigrate throw/rollback — Apple docs inaccessible, community-verified pattern)

---

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

- **D-01:** V5→V6 `didMigrate` auto-creates one `Account` per distinct non-nil `sourceLabel` (e.g. "HDFC CC", "ICICI Savings") and sets each existing expense's `accountID`. Expenses with nil `sourceLabel` stay `accountID = nil` ("Unassigned"). Grouping key is `sourceLabel` (human-readable bank label), NOT `sourceAccount` (Gmail mailbox dedup email).
- **D-02:** Auto-created accounts surface in an editable review list on first launch after migration — user can rename / merge / delete before locked in. Migration writes are idempotent (re-running must not duplicate accounts).
- **D-03:** Auto-created account type is inferred: `sourceLabel` containing "CC" / "credit" / "card" (case-insensitive) → `credit card`; everything else → `savings`. User corrects wrong guesses in the review step.
- **D-04:** Manual expense add/edit has an optional account picker that defaults to the last-used account; leaving it blank = Unassigned. Mirrors categories/tags (low friction, quick-add).
- **D-05:** Gmail sync auto-attributes a newly-ingested expense to the account whose name/label matches its `sourceLabel`; no match → `accountID = nil` (Unassigned).
- **D-06:** Account management (create/edit/delete/archive) lives under Settings — `Settings > Accounts`. Not a top-level tab, not an Overview section.
- **D-07:** Per-account spend reachable two ways: (a) tapping an account in Settings > Accounts opens its detail screen, and (b) account filter on the main expense list. CRUD stays in Settings; spend is a first-class filter elsewhere.
- **D-08:** Archive (ACCT-07): archived account hidden from expense account-picker and active lists, but past transactions remain visible & attributed, and it appears in a collapsed "Archived" section in Settings > Accounts that can be expanded.
- **D-09:** Credit-card balance shown as negative (amount owed) — savings/current show positive available cash. Net worth = simple sum so CC debt subtracts naturally.
- **D-10:** Opening balance = amount + as-of date picker, defaulting to today. Live balance = baseline ± transactions dated on/after the as-of date. Re-setting the baseline re-anchors from the new as-of date. Balance is computed (not stored) so it updates without manual refresh.
- **D-11:** SchemaV6 adds `isDailyRoutine: Bool = false` to `Note`. `RoutineResetService` resets checklist blocks only on notes flagged `isDailyRoutine`. Phase 12 UI toggle simply flips this flag.
- **D-12:** Reset uses a note-level `routineLastResetDate` marker (not per-block date-keying). On `scenePhase .active`, if `routineLastResetDate < startOfToday` in IST, set `isChecked = false` on all that note's checklist blocks and stamp the new date. Idempotent — repeated `.active` events same day are no-ops.

### Claude's Discretion

- Account color/icon picker UX (ACCT-03) — follow the existing category symbol/color picker pattern in `ManageCategoriesView`.
- Exact `Asset` model field shape — scaffold for Phase 11; minimal CloudKit-ready additive model only.
- Exact transfer-scaffold fields on `Expense` (e.g. `isTransfer: Bool? = nil`, `transferPairID: UUID? = nil`) — add minimally so Phase 10 needs no further migration; Phase 10 owns the semantics.
- Migration `didMigrate` error-handling (throw → rollback vs. partial state) — must be verified against the FB13812722 workaround before writing (see research below).
- Test-harness shape for the V5→V6 fixture test — follow existing Swift Testing + temp-file `ModelContainer` patterns.

### Deferred Ideas (OUT OF SCOPE)

- Self-transfer detection + Transfer Inbox (Phase 10 only — Phase 9 scaffolds transfer fields in V6).
- Asset Tracker UI / NAV fetch / net-worth (Phase 11 — V6 ships the `Asset` model only).
- "Mark note as routine" UI toggle and streak/history (Phase 12).

</user_constraints>

---

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| STAB-04 | A daily routine's checked state automatically resets when the day ends | D-11/D-12: `isDailyRoutine` field on Note + `routineLastResetDate` + IST calendar comparison in `RoutineResetService.resetIfNeeded()` |
| ACCT-01 | User can create, edit, and delete a bank account (name, last-4 optional) | Settings > Accounts CRUD following `ManageCategoriesView` patterns; lookup-before-insert, `confirmationDialog` for delete |
| ACCT-02 | User can set an account type (savings / current / credit card) | Stored as `String` raw value (rule 8: no stored enums); segmented control or picker in edit form |
| ACCT-03 | User can assign a color/icon to an account | Reuse category `symbolName: String?` + `colorHex: String?` pattern from `ManageCategoriesView`; `IconTile` component already exists |
| ACCT-04 | User can manually set account's balance as a reconciliation baseline | `balanceBaseline: Decimal = 0` + `balanceAsOfDate: Date = Date()` fields in V6 `Account` model |
| ACCT-05 | Account balance auto-updates from attributed transactions; displayed balance = baseline ± transactions since baseline date | Computed property on `Account` or in `AccountDetailView` using `@Query` filtered by `accountID` + `date >= balanceAsOfDate`; no stored derived value |
| ACCT-06 | User can view spend filtered to a single account | `AccountFilter` enum mirroring existing `CategoryFilter` in `ExpenseListView`; account detail in Settings also shows attributed expenses |
| ACCT-07 | User can archive/hide a closed account | `isArchived: Bool = false` field; archived accounts hidden from pickers, collapsed section in Settings > Accounts |
| ACCT-08 | Existing expenses backfilled with `accountID` during V5→V6 migration without disturbing `sourceAccount` | `didMigrate` closure reads distinct `sourceLabel` values, creates `Account` objects, sets `Expense.accountID`; idempotent on re-run |
| NOTE-02 | Daily routine checklist completion tracked per-day so it resets cleanly each day | `routineLastResetDate: Date?` on `Note` (V6); `RoutineResetService` body fills Phase 8 stub |

</phase_requirements>

---

## Summary

Phase 9 is the largest schema and feature phase in v1.1. It introduces SchemaV6 with five additions: the `Account` model (full CRUD), the `Asset` model (scaffold only), four new fields on `Expense` (`accountID`, `isTransfer`, `transferPairID`), and two new fields on `Note` (`isDailyRoutine`, `routineLastResetDate`). The V5→V6 migration stage is the first in this codebase to use a non-nil `didMigrate` closure, which makes it the highest-risk element of the phase.

The primary technical risk is the `didMigrate` backfill for account attribution. Community research (Apple Developer Forums, byby.dev) confirms: `didMigrate` closures are throwing, must call `try context.save()` explicitly, and — critically — **there is no documented automatic rollback** if the closure throws. The migration fails (ModelContainer init throws), leaving the store in an indeterminate state. This means the backfill logic must be designed for idempotency so it is safe to retry on next app launch. The existing FB13812722 workaround (`.custom` over `.lightweight`) is preserved and extended — the V6 stage adds a non-nil `didMigrate` while keeping `.custom` semantics.

The balance computation (ACCT-04/05) is a computed value, not stored, matching the D-10 decision. The reactive update requirement (ACCT-05) is satisfied naturally by SwiftUI's `@Query` observation and computed properties reacting to model changes — no explicit invalidation needed.

**Primary recommendation:** Implement the `didMigrate` backfill as a fetch-and-check idempotency guard (find existing accounts by `sourceLabel` before inserting); wrap the entire closure body in a `do/catch` that logs the error and re-throws so migration failure is observable; write the fixture test (V5 store → V6 migration → assert backfill) before writing the production migration code.

---

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| V5→V6 schema migration + backfill | Persistence / Migration | — | `AppMigrationPlan` + `SchemaV6`; `didMigrate` runs in the SwiftData migration context at container init time |
| Account CRUD (create/edit/delete/archive) | Settings feature module | — | D-06: lives under `Settings > Accounts`; follows `ManageCategoriesView` pattern |
| Live account balance computation | AccountDetail view / computed property | Account model | Computed from `@Query` of attributed expenses — pure derivation, no stored cache |
| Per-account expense filter | Expense list (main feature) | Account detail | D-07: reachable from both Settings detail and main list filter |
| Gmail auto-attribution (D-05) | GmailSyncController | — | Existing `syncAccount` method; add `sourceLabel`→`Account` lookup after expense creation |
| Daily-routine reset | RoutineResetService | RootView scenePhase | Phase 8 wiring already exists; Phase 9 fills the body |
| Model typealiases | Persistence / Models | — | All four `typealias X = SchemaV5.X` files flip to `SchemaV6.X` atomically in one commit |

---

## Standard Stack

No new external dependencies are introduced in this phase. Everything uses the existing first-party stack.

### Core (already in project)

| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| SwiftData | iOS 17+ (built-in) | Persistence, migration | First-party; the entire schema chain is built on it |
| SwiftUI | iOS 17+ (built-in) | UI | Project-wide convention |
| Foundation | built-in | Calendar, UUID, Decimal, Date | IST calendar, money, UUIDs |

### No new packages

No external packages are needed for this phase. [VERIFIED: codebase inspection]

---

## Package Legitimacy Audit

No external packages are installed in this phase. All capabilities use first-party Apple frameworks.

**Packages removed due to slopcheck [SLOP] verdict:** none
**Packages flagged as suspicious [SUS]:** none

---

## Architecture Patterns

### System Architecture Diagram

```
[App launch]
    │
    ▼
[ModelContainer init]
    │── AppMigrationPlan.v5ToV6 ──► [SchemaV6 struct layout applied (additive)]
    │                                   │
    │                               [didMigrate context]
    │                                   │── fetch distinct Expense.sourceLabel values
    │                                   │── idempotency: fetch existing Account by sourceLabel
    │                                   │── insert Account if not exists
    │                                   │── set Expense.accountID = account.id
    │                                   │── try context.save()  ← REQUIRED; throws on failure
    │
    ▼
[RootView]
    │── scenePhase .active ──► RoutineResetService.resetIfNeeded()
    │                               │── fetch Note where isDailyRoutine == true
    │                               │── for each: if routineLastResetDate < startOfToday (IST)
    │                               │        set NoteBlock.isChecked = false on all checklist blocks
    │                               │        stamp routineLastResetDate = today
    │                               └── try context.save()
    │
    ▼
[SettingsView]
    │── "Accounts" row ──► AccountsListView
    │                           │── AccountRowView (name, type, color, balance)
    │                           │── archive / delete swipe actions
    │                           └── NavigationLink ──► AccountDetailView
    │                                                       │── balance headline (computed)
    │                                                       └── attributed expense list
    │
[ExpenseListView]
    │── AccountFilter picker (all / by account / unassigned)
    │── filtered expense list (in-memory filter on Expense.accountID)
    │
[AddExpenseView / EditExpenseView]
    └── optional AccountPickerView (mirrors CategoryPickerView)
            └── defaults to lastUsedAccountID stored in UserDefaults
```

### Recommended Project Structure (additions only)

```
MyHomeApp/Persistence/Schema/
├── SchemaV6.swift          # new — V6 models; copy V5 verbatim + additive fields
└── MigrationPlan.swift     # edit — append SchemaV6.self + v5ToV6 stage

MyHomeApp/Persistence/Models/
├── Account.swift           # new — typealias Account = SchemaV6.Account
├── Asset.swift             # new — typealias Asset = SchemaV6.Asset
├── Expense.swift           # edit — flip to SchemaV6.Expense
├── Note.swift              # edit — flip to SchemaV6.Note
├── NoteBlock.swift         # edit — flip to SchemaV6.NoteBlock
└── Category.swift          # edit — flip to SchemaV6.Category

MyHomeApp/Features/Settings/
├── SettingsView.swift      # edit — add "Accounts" row
├── AccountsListView.swift  # new — list + create + archive + delete
├── AccountDetailView.swift # new — balance headline + attributed expense list
└── EditAccountView.swift   # new — create/edit form (name, type, color/icon, balance baseline, as-of date)

MyHomeApp/Features/Expenses/
├── ExpenseListView.swift   # edit — add AccountFilter (mirrors CategoryFilter)
├── AddExpenseView.swift    # edit — add optional AccountPickerView
├── EditExpenseView.swift   # edit — add optional AccountPickerView
└── AccountPickerView.swift # new — mirrors CategoryPickerView

MyHomeApp/Features/Notes/
└── RoutineResetService.swift  # edit — fill Phase 8 stub body

MyHomeTests/
└── SchemaV6MigrationTests.swift  # new — V5→V6 fixture test (success criterion 4)
```

---

## Critical Pattern 1: V5→V6 `didMigrate` — First Non-nil Closure

### What It Is

The V5→V6 stage is the codebase's **first non-nil `didMigrate`**. All prior stages used `didMigrate: nil` to sidestep FB13812722. The V6 stage must keep `.custom` semantics (preserving the FB13812722 workaround) while adding a non-nil `didMigrate` for backfill.

### Verified `didMigrate` Behavior [ASSUMED — verified from community sources, not official Apple docs which were inaccessible]

| Property | Behavior |
|----------|----------|
| Closure signature | `(ModelContext) throws -> Void` |
| Context type | A migration-scoped `ModelContext` providing V6 models |
| `context.save()` | **Must be called explicitly.** Changes are NOT auto-committed. |
| If closure throws | Migration stage fails → `ModelContainer` init throws → app launch fails |
| Rollback semantics | **No documented automatic rollback.** Store may be in partial state if `didMigrate` throws after some inserts but before `context.save()`. |
| Re-run safety | SwiftData re-runs the stage on next launch if container init failed. The backfill MUST be idempotent to survive re-runs. |

### The FB13812722 Workaround — Preserved

The existing code uses `.custom` instead of `.lightweight` for all stages because of an iOS 17.0–17.3 bug where `SchemaMigrationPlan` with `.lightweight` stages crashes at migration time. This workaround is carried forward unchanged into V6. The V6 stage uses `.custom` with a non-nil `didMigrate`. [VERIFIED: codebase — MigrationPlan.swift lines 17-21 + comments]

### Idempotent Backfill Pattern

The backfill must not duplicate `Account` rows if `didMigrate` is called more than once (retry on crash):

```swift
// Source: pattern derived from codebase MigrationTests.swift + community byby.dev pattern
static let v5ToV6 = MigrationStage.custom(
    fromVersion: SchemaV5.self,
    toVersion: SchemaV6.self,
    willMigrate: nil,
    didMigrate: { context in
        // 1. Fetch all expenses (V6 model now available — sourceLabel retained verbatim)
        let expenses = try context.fetch(FetchDescriptor<SchemaV6.Expense>())

        // 2. Collect distinct non-nil sourceLabels
        let labels = Set(expenses.compactMap(\.sourceLabel))

        // 3. Build a map of existing accounts by sourceLabel for idempotency
        let existingAccounts = try context.fetch(FetchDescriptor<SchemaV6.Account>())
        var accountByLabel: [String: SchemaV6.Account] = [:]
        for account in existingAccounts {
            if let label = account.sourceLabel { accountByLabel[label] = account }
        }

        // 4. Create missing accounts (idempotent: only insert if not already present)
        for label in labels {
            if accountByLabel[label] == nil {
                let typeRaw = inferAccountType(from: label)  // "credit_card" or "savings"
                let account = SchemaV6.Account(name: label, typeRaw: typeRaw, sourceLabel: label)
                context.insert(account)
                accountByLabel[label] = account
            }
        }

        // 5. Backfill Expense.accountID (idempotent: skip expenses already attributed)
        for expense in expenses {
            guard expense.accountID == nil, let label = expense.sourceLabel else { continue }
            expense.accountID = accountByLabel[label]?.id
        }

        // 6. Explicit save — required; not auto-committed
        try context.save()
    }
)
```

**Key idempotency guards:**
- Step 3: fetch existing accounts before inserting (prevents duplicates on retry)
- Step 5: `guard expense.accountID == nil` (skips already-attributed expenses on retry)

### First-Launch Review Flag

D-02 requires surfacing auto-created accounts in a review list on first post-migration launch. Implement this as a `UserDefaults` flag: `accountReviewPending: Bool`. The `didMigrate` closure sets it to `true` when it creates accounts. `AccountsListView` (or a sheet from `SettingsView`) reads this flag and shows the review prompt. This flag is NOT stored in SwiftData (avoids a migration cycle for a transient UX state).

---

## Critical Pattern 2: All Typealiases Must Flip Atomically

The STAB-08 lesson: mismatched typealiases (one file pointing at V4 while the container runs V5) caused note save/query crashes. For V6, all six files must flip in a **single commit**:

```
Expense.swift:   typealias Expense  = SchemaV6.Expense
Note.swift:      typealias Note     = SchemaV6.Note
NoteBlock.swift: typealias NoteBlock = SchemaV6.NoteBlock
Category.swift:  typealias Category = SchemaV6.Category
Account.swift:   typealias Account  = SchemaV6.Account   ← NEW file
Asset.swift:     typealias Asset    = SchemaV6.Asset      ← NEW file
```

And `MigrationPlan.swift` must be updated in the same commit:

```swift
static var schemas: [any VersionedSchema.Type] {
    [SchemaV1.self, SchemaV2.self, SchemaV3.self, SchemaV4.self, SchemaV5.self, SchemaV6.self]
}
```

[VERIFIED: codebase — STAB-08 lesson documented in Note.swift and NoteBlock.swift comments]

---

## Critical Pattern 3: SchemaV6 Model Definitions

### Account Model

```swift
// Source: derived from SchemaV5 CloudKit-readiness rules (SchemaV5.swift lines 1-20)
@Model
final class Account {
    var id: UUID = UUID()
    var name: String? = nil               // optional per CloudKit rule 2
    var typeRaw: String? = nil            // "savings" | "current" | "credit_card" — String not enum (rule 8)
    var symbolName: String? = nil         // SF Symbol name
    var colorHex: String? = nil           // hex string e.g. "#FF3B30"
    var last4: String? = nil              // optional last 4 digits
    var balanceBaseline: Decimal? = nil   // Decimal not Double (rule 3); nil = no baseline set
    var balanceAsOfDate: Date? = nil      // UTC (rule 4)
    var isArchived: Bool = false          // D-08: archive hides from pickers
    var sortOrder: Int = 0               // for ordered list display
    var sourceLabel: String? = nil        // set by migration for auto-created accounts; nil for manual
    var createdAt: Date = Date()          // UTC (rule 4)

    // Inverse relationship to Expense.account (declared on ONE side — rule 7)
    @Relationship(deleteRule: .nullify)
    var expenses: [SchemaV6.Expense] = []

    init(name: String, typeRaw: String = "savings", sourceLabel: String? = nil) { ... }
}
```

**CloudKit rule checklist for Account:**
- [x] Every stored property has default or is optional
- [x] No `.unique`
- [x] Decimal for money (`balanceBaseline`)
- [x] UTC dates (`balanceAsOfDate`, `createdAt`)
- [x] UUID primary key
- [x] Inverse on ONE side only
- [x] No stored enums (typeRaw is String)

### Asset Model (scaffold only — no UI this phase)

```swift
@Model
final class Asset {
    var id: UUID = UUID()
    var name: String? = nil
    var assetClassRaw: String? = nil   // "mutual_fund" | "stock" | "nps" — Phase 11 populates
    var units: Decimal? = nil
    var costBasisPerUnit: Decimal? = nil
    var currentNAV: Decimal? = nil
    var navAsOfDate: Date? = nil
    var createdAt: Date = Date()
    init() { self.id = UUID(); self.createdAt = Date() }
}
```

### New fields on Expense (V6 additive additions)

```swift
// Add to SchemaV6.Expense (copy V5 verbatim, then append):
var accountID: UUID? = nil              // D-01: links to Account.id; nil = Unassigned
var isTransfer: Bool? = nil             // Phase 10 transfer scaffold; nil = not evaluated
var transferPairID: UUID? = nil         // Phase 10 transfer scaffold; links paired expense
```

### New fields on Note (V6 additive additions)

```swift
// Add to SchemaV6.Note (copy V5 verbatim, then append):
var isDailyRoutine: Bool = false           // D-11: flags note for RoutineResetService
var routineLastResetDate: Date? = nil      // D-12: note-level reset marker; nil = never reset
```

No new fields on NoteBlock in Phase 9. (Per-block `lastCheckedDate` is deferred to Phase 12 for streak/history per CONTEXT.md reconciliation note.)

### Category — no change; copy verbatim from V5

---

## Critical Pattern 4: Live Balance Computation (ACCT-04/05, D-09/D-10)

The balance is **never stored** — it is computed in the view layer from `@Query` results.

```swift
// Source: derived from existing OverviewAggregationTests pattern + D-09/D-10 semantics
// In AccountDetailView or a dedicated AccountBalanceViewModel

func computeBalance(for account: SchemaV6.Account, expenses: [Expense]) -> Decimal {
    guard let baseline = account.balanceBaseline,
          let asOf = account.balanceAsOfDate else { return Decimal(0) }

    // Sum expenses dated on or after the as-of date attributed to this account
    let attributed = expenses.filter { expense in
        expense.accountID == account.id && expense.date >= asOf
    }
    let netTransactions = attributed.reduce(Decimal(0)) { $0 + $1.amount }
    // amount is negative for debits (expenses), positive for credits (reversals/income)

    // D-09: credit card accounts: baseline is negative (amount owed), goes more negative as you spend
    // savings/current: baseline is positive, decreases as you spend
    // Both use the same formula: baseline + net — the sign convention is carried in the data, not the formula
    return baseline + netTransactions
}
```

**Reactive update:** `AccountDetailView` uses `@Query` for expenses filtered by `accountID`. SwiftData's `@Query` automatically re-evaluates when the underlying store changes, so the computed balance updates without any manual trigger. [VERIFIED: codebase — existing `@Query` usage in `ExpenseListView.swift`]

**Account filter query pattern (mirrors `CategoryFilter` in `ExpenseListView.swift`):**

```swift
// In AccountDetailView — shows only expenses for this account
@Query private var allExpenses: [Expense]
// filtered in-memory (same pattern as CategoryFilter):
var attributed: [Expense] { allExpenses.filter { $0.accountID == account.id } }
```

For the main expense list `AccountFilter`, mirror the existing `CategoryFilter` enum precisely:

```swift
private enum AccountFilter: Hashable {
    case all
    case unassigned          // accountID == nil
    case account(UUID)       // accountID == specific UUID
}
```

---

## Critical Pattern 5: RoutineResetService Body (STAB-04, D-11/D-12)

The Phase 8 stub already has the IST calendar and the `resetIfNeeded()` call site wired in `RootView`. Phase 9 fills the body:

```swift
// Source: RoutineResetService.swift (Phase 8 scaffold) + D-11/D-12 decisions
@MainActor
@Observable
final class RoutineResetService {
    var modelContext: ModelContext?   // injected by RootView.onAppear (same pattern as gmailSyncController)

    func resetIfNeeded() {
        guard let context = modelContext else { return }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Kolkata")!
        let startOfTodayIST = cal.startOfDay(for: Date())

        do {
            // Fetch only isDailyRoutine notes (D-11)
            let notes = try context.fetch(
                FetchDescriptor<Note>(predicate: #Predicate { $0.isDailyRoutine == true })
            )
            var didChange = false
            for note in notes {
                // D-12: compare note-level routineLastResetDate
                let lastReset = note.routineLastResetDate ?? .distantPast
                guard lastReset < startOfTodayIST else { continue }   // idempotent: same day = no-op

                // Reset all checkbox blocks on this note
                for block in note.blocks ?? [] {
                    if block.kindRaw == "checkbox" && block.isChecked {
                        block.isChecked = false
                        didChange = true
                    }
                }
                note.routineLastResetDate = startOfTodayIST
                didChange = true
            }
            if didChange { try context.save() }
        } catch {
            print("[RoutineResetService] reset failed: \(error)")
        }
    }
}
```

**Injection:** `RoutineResetService` must be passed a `ModelContext` by `RootView.onAppear` (same pattern as `gmailSyncController.setContext(modelContext)`). The existing `@State private var routineResetService = RoutineResetService()` in `RootView` is the injection site.

---

## Critical Pattern 6: Gmail Auto-Attribution on Ingestion (D-05)

In `GmailSyncController.syncAccount`, after creating the `Expense` object (around line 526):

```swift
// D-05: Auto-attribute to matching Account by sourceLabel
// Re-use the same modelContext reference; no extra async suspension needed
if let label = parsed.rawSourceLabel,
   let ctx = modelContext {
    let matchingAccounts = (try? ctx.fetch(FetchDescriptor<Account>())) ?? []
    if let match = matchingAccounts.first(where: { $0.sourceLabel == label && !$0.isArchived }) {
        expense.accountID = match.id
    }
    // No match → accountID stays nil (Unassigned) per D-05
}
```

**Constraint:** The account fetch must happen **before** the async `await` boundary or must re-fetch after any `await` suspension (STAB-02 lesson). The existing category-fetch pattern (`categoryIDsByName` captured as `[String: PersistentIdentifier]` once before the loop) is the correct model: capture account IDs before the per-message loop, not inside it.

---

## Critical Pattern 7: Account CRUD — Settings > Accounts

The `AccountsListView` follows the `ManageCategoriesView` pattern directly:

- `@Query(sort: \Account.sortOrder)` for active accounts (filter `!isArchived`)
- Separate `@Query` or filtered section for archived accounts (shown collapsed)
- New account creation via `min(existing.sortOrder) - 1` insertion (same as STAB-03 category pattern) [VERIFIED: codebase — ManageCategoriesView.swift lines 194–196]
- `confirmationDialog` for delete (same pattern as `ManageCategoriesView`)
- `EditAccountView` sheet for create/edit — NavigationStack-in-sheet pattern

**Color/icon picker:** The `ManageCategoriesView` category rows show `symbolName` via `IconTile(symbol:color:size:)`. The same `IconTile` component is used for accounts. Color stored as `colorHex: String?` (hex string, rule 8 — no stored Color/UIColor).

**sortOrder for accounts:** Same `min(existing.sortOrder) - 1` prepend pattern used for categories. New accounts appear at the top of the active list.

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Reactive UI updates when balance changes | Manual `@Published`/notification system | `@Query` + computed property in view | SwiftData's `@Query` already observes store changes; computing balance from query results is free reactivity |
| Duplicate account detection | Custom hash/UUID scheme | `fetch-before-insert` + `sourceLabel` string comparison | Matches the existing category uniqueness pattern (no `.unique` — CloudKit rule 2); same approach proven in `ManageCategoriesView` |
| Migration retry detection | Custom store version flag | Idempotency guards in `didMigrate` itself | SwiftData re-runs the stage on init failure; design the closure to be safe to run twice |
| IST "start of today" | Custom timezone arithmetic | `Calendar.current` with `timeZone = .init(identifier: "Asia/Kolkata")` + `startOfDay(for:)` | Already proven in Phase 8 `RoutineResetService` scaffold |
| Account type display | Custom enum + stored enum | `String` raw value + computed display property | CloudKit rule 8: no stored enums; display strings derived at runtime |
| Last-used account preference | Model field | `UserDefaults.standard` (same pattern as other per-device prefs) | This is a device preference, not synced data; keeps the schema clean |

---

## Common Pitfalls

### Pitfall 1: Typealias Mismatch Across Schema Version (STAB-08)

**What goes wrong:** Creating a `Note` or `NoteBlock` (or any `@Model`) with a typealias still pointing at `SchemaV5` while the container runs `SchemaV6` causes a SwiftData assertion crash on `save()` and in `@Query` results.

**Why it happens:** The `@Model` macro registers the class with a specific `Schema.Entity` name that includes the enclosing enum (e.g., `SchemaV5.Note` vs `SchemaV6.Note`). The container schema has `SchemaV6.Note`; attempting to insert a `SchemaV5.Note` object hits an entity mismatch.

**How to avoid:** Flip ALL typealiases — `Expense`, `Note`, `NoteBlock`, `Category`, `Account` (new), `Asset` (new) — in the **same commit** that updates `AppMigrationPlan.schemas` to include `SchemaV6.self`.

**Warning signs:** `save()` throws `SwiftData.SwiftDataError` with "entity not found"; `@Query` returns empty array that should have results.

### Pitfall 2: `didMigrate` Throwing Without Idempotency Guard

**What goes wrong:** `didMigrate` inserts `Account` rows and then crashes (or `context.save()` throws). On next launch SwiftData re-runs the stage, inserting duplicate `Account` rows for the same `sourceLabel`.

**Why it happens:** SwiftData re-runs the migration stage if the container init fails (the store's schema version was not committed). Without an idempotency guard, the backfill runs again on duplicate data.

**How to avoid:** Always fetch existing accounts by `sourceLabel` before inserting (step 3 in the backfill pattern above). Guard `expense.accountID == nil` before setting it.

**Warning signs:** Multiple `Account` rows with the same `sourceLabel`; expenses attributed to duplicate account objects.

### Pitfall 3: `context.save()` Missing in `didMigrate`

**What goes wrong:** All backfill writes are silently discarded. The migration "succeeds" (no throw) but expenses have `accountID == nil` and no `Account` rows exist.

**Why it happens:** Unlike `ModelContext` in views (which auto-saves in some contexts), the migration context does NOT auto-commit. The explicit `try context.save()` is required.

**How to avoid:** Always end `didMigrate` with `try context.save()`.

### Pitfall 4: Category Re-fetch Pattern Broken After Adding Account Lookup (D-05)

**What goes wrong:** Adding an account lookup inside the per-message loop in `syncAccount` introduces a new `modelContext.fetch()` call inside the loop, which could read from a context that has already been partially modified by the loop. More critically, if this fetch is added after an `await`, the captured `Account` `@Model` objects may be invalidated.

**Why it happens:** STAB-02 fix moved `Category` resolution to `PersistentIdentifier` capture before the loop. The account lookup must follow the same pre-capture pattern.

**How to avoid:** Capture `[String: PersistentIdentifier]` for accounts before the message loop (mirror `categoryIDsByName`). Re-resolve by `PersistentIdentifier` inside the loop. See Critical Pattern 6 for the safe implementation.

**Warning signs:** Expenses ingested after migration have `accountID == nil` even when a matching account exists; occasional crashes in `syncAccount` after `await` suspension.

### Pitfall 5: `Account` Relationship on `Expense` vs `accountID` UUID

**What goes wrong:** Declaring a SwiftData `@Relationship` from `Expense` to `Account` (instead of using a bare `accountID: UUID?`) can interfere with CloudKit readiness and adds complexity to the migration backfill (which would need to resolve model instances, not UUIDs).

**How to avoid:** Use `accountID: UUID? = nil` (a bare UUID, not a relationship) on `Expense`. The `Account` model declares the inverse `@Relationship` side (its `expenses` array). This matches the existing `Category.expenses` pattern. [VERIFIED: codebase — SchemaV5.swift line 85: `@Relationship(deleteRule: .nullify, inverse: \SchemaV5.Category.expenses)`]

**Warning signs:** Circular macro expansion error "Circular reference resolving attached macro 'Relationship'"; CloudKit sync failures on `@Relationship`-decorated UUID fields.

**Note:** The above recommendation uses `accountID` as a bare UUID. If a full `@Relationship` from `Expense` to `Account` is preferred for query expressiveness, declare the inverse on `Account.expenses` only (as shown in the Account model definition above), and reference `Account` directly on `Expense` with `var account: SchemaV6.Account? = nil`. Either approach works; the bare UUID approach is simpler for the migration backfill and avoids the circular macro issue.

### Pitfall 6: Archived Accounts Appearing in Pickers

**What goes wrong:** Account picker in `AddExpenseView` / `EditExpenseView` shows archived accounts, confusing users who thought they were hidden.

**How to avoid:** Filter pickers with `!account.isArchived`. Separate `@Query` or in-memory filter for active vs. archived accounts.

### Pitfall 7: Credit Card Balance Sign Convention (D-09)

**What goes wrong:** Credit card balance shows as positive (available credit) instead of negative (amount owed), breaking Phase 11 net-worth math.

**How to avoid:** D-09 is explicit: credit card `balanceBaseline` must be entered as a negative number (amount owed). The `EditAccountView` form should display a signed amount and label it "Amount owed" for credit cards. `computeBalance` uses the same formula for all account types; the sign semantics are in the data, not the formula.

---

## Anti-Patterns to Avoid

- **Storing computed balance:** `Account.balance: Decimal` as a stored property. Always compute from attributed expenses. Stored derived values go stale.
- **Inserting accounts before `ModelContainer` init completes:** Any code that tries to create `Account` objects outside `didMigrate` or normal app flow (e.g., in a "migration check" on app launch) risks running against a partially migrated store.
- **Using `.lightweight` for V6 stage:** The FB13812722 workaround requires `.custom`. Do not switch to `.lightweight` even though V6 is additive. [VERIFIED: MigrationPlan.swift — comment at line 17-19]
- **Async `didMigrate`:** The `didMigrate` closure is synchronous (`throws`, not `async throws`). Do NOT attempt `await` inside it. [ASSUMED — based on SwiftData API design and community reports; async migration is not documented as supported]

---

## V5→V6 Migration Test Pattern (Success Criterion 4)

The existing `MigrationTests.swift` shows the exact harness shape: seed a prior-version store using a trimmed migration plan that stops at V5, copy to temp URL, re-open under the full `AppMigrationPlan` + `SchemaV6`, assert on results. [VERIFIED: codebase — MigrationTests.swift lines 105-173]

```swift
// File: MyHomeTests/SchemaV6MigrationTests.swift
// Source: derived from MigrationTests.swift v3StoreMigratesToV4 pattern

@MainActor
struct SchemaV6MigrationTests {

    @Test("V5→V6: expenses with sourceLabel are backfilled with accountID; sourceAccount unchanged")
    func v5StoreBackfillsAccountID() throws {
        let seedURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("v5seed-\(UUID()).store")
        let migrateURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("v5tov6-\(UUID()).store")
        defer {
            try? FileManager.default.removeItem(at: seedURL)
            try? FileManager.default.removeItem(at: migrateURL)
        }

        // 1. Build a V5 store and seed expenses with distinct sourceLabels
        try {
            let v5Schema = Schema(versionedSchema: SchemaV5.self)
            let config = ModelConfiguration(schema: v5Schema, url: seedURL)
            let container = try ModelContainer(
                for: v5Schema,
                migrationPlan: MigrationTestsPlanV5.self,   // stops at V5
                configurations: [config]
            )
            let ctx = container.mainContext
            let e1 = SchemaV5.Expense(amount: Decimal(100))
            e1.sourceLabel = "HDFC CC"
            e1.sourceAccount = "user@gmail.com"
            ctx.insert(e1)
            let e2 = SchemaV5.Expense(amount: Decimal(50))
            e2.sourceLabel = "ICICI Savings"
            e2.sourceAccount = "user@gmail.com"
            ctx.insert(e2)
            let e3 = SchemaV5.Expense(amount: Decimal(25))
            // e3: no sourceLabel — should remain unassigned after migration
            ctx.insert(e3)
            try ctx.save()
            try ctx.save()  // flush WAL
        }()

        try FileManager.default.copyItem(at: seedURL, to: migrateURL)

        // 2. Migrate to V6
        let v6Schema = Schema(versionedSchema: SchemaV6.self)
        let migrateConfig = ModelConfiguration(schema: v6Schema, url: migrateURL)
        let container = try ModelContainer(
            for: v6Schema,
            migrationPlan: AppMigrationPlan.self,
            configurations: [migrateConfig]
        )
        let ctx = container.mainContext

        // 3. Assert accounts were created
        let accounts = try ctx.fetch(FetchDescriptor<Account>())
        #expect(accounts.count == 2, "Should create exactly 2 accounts (HDFC CC, ICICI Savings)")

        // 4. Assert expenses have correct accountIDs
        let expenses = try ctx.fetch(FetchDescriptor<Expense>())
        let hdfcAccount = accounts.first { $0.sourceLabel == "HDFC CC" }
        let icicAccount = accounts.first { $0.sourceLabel == "ICICI Savings" }

        let e1Migrated = expenses.first { $0.amount == Decimal(100) }
        #expect(e1Migrated?.accountID == hdfcAccount?.id, "HDFC CC expense must be attributed")
        #expect(e1Migrated?.sourceAccount == "user@gmail.com", "sourceAccount must be retained unchanged")

        let e2Migrated = expenses.first { $0.amount == Decimal(50) }
        #expect(e2Migrated?.accountID == icicAccount?.id, "ICICI expense must be attributed")

        let e3Migrated = expenses.first { $0.amount == Decimal(25) }
        #expect(e3Migrated?.accountID == nil, "Nil-sourceLabel expense must remain Unassigned")

        // 5. Type inference (D-03)
        #expect(hdfcAccount?.typeRaw == "credit_card", "HDFC CC should be inferred as credit_card")
        #expect(icicAccount?.typeRaw == "savings", "ICICI Savings should be inferred as savings")
    }

    @Test("V5→V6 migration is idempotent — re-running does not duplicate accounts")
    func v5MigrationIsIdempotent() throws { ... }
}

// Trimmed migration plan stopping at V5 (for seeding V5 stores in tests)
enum MigrationTestsPlanV5: SchemaMigrationPlan { ... }
```

---

## Runtime State Inventory

This phase is additive, not a rename/refactor. However, there is one runtime state item:

| Category | Items Found | Action Required |
|----------|-------------|------------------|
| Stored data | No existing `Account` rows — migration creates them from scratch | `didMigrate` backfill (covered) |
| Live service config | No external services reference account schema | None |
| OS-registered state | No OS-level registrations embed account concepts | None |
| Secrets/env vars | No account-related secrets | None |
| Build artifacts | `egg-info` / derived data — standard Xcode clean resolves | Standard Xcode clean on schema bump |

**Nothing found that requires data migration beyond the `didMigrate` backfill.** Existing `sourceAccount` field on `Expense` is RETAINED unchanged (it is the Gmail dedup key — not the new `accountID`). [VERIFIED: codebase — SchemaV5.swift line 104; REQUIREMENTS.md ACCT-08]

---

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| Xcode 26.5 | Build + test | ✓ (per MEMORY.md) | 26.5 | — |
| iPhone 17 simulator | Run/test | ✓ (per MEMORY.md) | — | — |
| Swift Testing | Unit tests | ✓ | built-in Xcode 16+ | — |
| SwiftData | Schema migration | ✓ | iOS 17+ | — |

---

## Validation Architecture

### Test Framework

| Property | Value |
|----------|-------|
| Framework | Swift Testing (built-in, no external package) |
| Config file | None — Xcode test target `MyHomeTests` |
| Quick run command | `xcodebuild test -scheme MyHome -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:MyHomeTests/SchemaV6MigrationTests` |
| Full suite command | `xcodebuild test -scheme MyHome -destination 'platform=iOS Simulator,name=iPhone 17'` |

### Phase Requirements → Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| ACCT-08 | V5→V6 backfill attributes expenses to accounts; `sourceAccount` unchanged | integration | `xcodebuild test ... -only-testing:MyHomeTests/SchemaV6MigrationTests/v5StoreBackfillsAccountID` | ❌ Wave 0 |
| ACCT-08 | Migration is idempotent on re-run | integration | `xcodebuild test ... -only-testing:MyHomeTests/SchemaV6MigrationTests/v5MigrationIsIdempotent` | ❌ Wave 0 |
| STAB-04 | `resetIfNeeded` resets isChecked only for isDailyRoutine notes when date crosses midnight IST | unit | `xcodebuild test ... -only-testing:MyHomeTests/RoutineResetServiceTests` | ❌ Wave 0 |
| STAB-04 | `resetIfNeeded` is idempotent — calling twice same day does not double-reset | unit | `xcodebuild test ... -only-testing:MyHomeTests/RoutineResetServiceTests/resetIsIdempotent` | ❌ Wave 0 |
| ACCT-05 | Live balance = baseline + net attributed transactions since as-of date | unit | `xcodebuild test ... -only-testing:MyHomeTests/AccountBalanceTests` | ❌ Wave 0 |
| ACCT-05 | Credit card balance is negative (amount owed) | unit | `xcodebuild test ... -only-testing:MyHomeTests/AccountBalanceTests/creditCardIsNegative` | ❌ Wave 0 |
| ACCT-01/07 | Archive hides account from pickers | unit/integration | `xcodebuild test ... -only-testing:MyHomeTests/AccountCRUDTests` | ❌ Wave 0 |
| D-03 | Type inference: "CC"/"credit"/"card" → credit_card; else → savings | unit | `xcodebuild test ... -only-testing:MyHomeTests/AccountTypeInferenceTests` | ❌ Wave 0 |

### Sampling Rate

- **Per task commit:** `xcodebuild test ... -only-testing:MyHomeTests/<new test file for that task>`
- **Per wave merge:** Full suite on iPhone 17 simulator
- **Phase gate:** Full suite green before `/gsd-verify-work`

### Wave 0 Gaps

- [ ] `MyHomeTests/SchemaV6MigrationTests.swift` — covers ACCT-08; requires `MigrationTestsPlanV5` helper enum
- [ ] `MyHomeTests/RoutineResetServiceTests.swift` — covers STAB-04 (reset, idempotency, non-routine note untouched)
- [ ] `MyHomeTests/AccountBalanceTests.swift` — covers ACCT-05 (live balance formula; credit card sign)
- [ ] `MyHomeTests/AccountCRUDTests.swift` — covers ACCT-01/07 (archive, picker exclusion)
- [ ] `MyHomeTests/AccountTypeInferenceTests.swift` — covers D-03 type inference logic

---

## Security Domain

`security_enforcement: true`, `security_asvs_level: 1`.

### Applicable ASVS Categories

| ASVS Category | Applies | Standard Control |
|---------------|---------|-----------------|
| V2 Authentication | No — no new auth in this phase | — |
| V3 Session Management | No | — |
| V4 Access Control | No — local-only, single-user app | — |
| V5 Input Validation | Yes — account name, last-4, balance | Trim + empty check (matches `ManageCategoriesView` pattern); `abs(balanceBaseline) < 1_000_000_000` guard (mirrors T-01-03 from `AddExpenseView`) |
| V6 Cryptography | No — no new crypto | — |

### Known Threat Patterns for SwiftData / SwiftUI

| Pattern | STRIDE | Standard Mitigation |
|---------|--------|---------------------|
| XSS via account name in views | Tampering | `Text(account.name ?? "")` — plain `Text()`, never `AttributedString(markdown:)` (T-02-15 pattern) |
| Unreasonably large balance baseline crashing Decimal arithmetic | Tampering | Validate `abs(baseline) < 1_000_000_000` before save (matches T-01-03) |
| Archive bypass — archived account's `accountID` still usable in manual expense form | Elevation | Filter `!isArchived` in pickers AND in `addExpense` pre-save validation |

---

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| `didMigrate: nil` for all stages | `didMigrate: { context in ... }` for V6 | Phase 9 (this phase) | First active backfill in this codebase; all patterns above apply |
| `RoutineResetService` = logged no-op stub | Full reset logic using `isDailyRoutine` + `routineLastResetDate` | Phase 9 (this phase) | Completes Phase 8 scaffold |
| Expense has no account concept | `Expense.accountID: UUID?` + `Account` model | Phase 9 (this phase) | Attribution without disrupting `sourceAccount` dedup key |

---

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | `didMigrate` closure is synchronous (no `async throws`) — `await` is not permitted inside it | Critical Pattern 1 | If async were supported, the backfill could be simpler; but attempting `await` in a sync closure is a compile error, so this is safe-to-assume |
| A2 | There is no automatic rollback if `didMigrate` throws — store may be in partial state | Critical Pattern 1 | If Apple implements rollback, idempotency guards are still correct (safe to over-guard); if no rollback exists and we assumed rollback, data corruption |
| A3 | SwiftData re-runs the failed migration stage on next launch (allowing idempotency to rescue the situation) | Critical Pattern 1 | If SwiftData marks the store as permanently corrupted instead of retrying, the only recovery is app delete/reinstall. Risk is LOW because this is consistent with SQLite WAL behavior and community reports |
| A4 | `@Relationship` inverse on `Account.expenses` + bare `accountID: UUID?` on `Expense` is the correct pattern for CloudKit-ready one-to-many without circular macro error | Critical Pattern 3 | If wrong, we get a compile error (easily caught). Confidence HIGH based on existing `Category.expenses` ↔ `Expense.categories` pattern in SchemaV5 |
| A5 | `isDailyRoutine` on `Note` is sufficient for STAB-04 / NOTE-02 with no per-block date field needed in Phase 9 | Critical Pattern 5 | Per-block `lastCheckedDate` is explicitly deferred to Phase 12 per CONTEXT.md reconciliation note. Risk: if Phase 12 planner finds the note-level reset insufficient, a schema bump is needed. Acceptable deferral. |

---

## Open Questions

1. **`Account` ↔ `Expense` relationship direction**
   - What we know: `Category` uses `@Relationship(deleteRule: .nullify)` on `Category.expenses` + `@Relationship(deleteRule: .nullify, inverse: \SchemaV5.Category.expenses)` on `Expense.categories`. The Account↔Expense relationship could follow this or use a bare UUID.
   - What's unclear: Whether a full `@Relationship` (for cascade/nullify on account delete) is preferable to a bare `accountID: UUID?`. A `@Relationship` enables `deleteRule: .nullify` (account delete sets expense.account = nil automatically); bare UUID requires explicit nullification logic on account delete.
   - Recommendation: Use `@Relationship(deleteRule: .nullify)` on `Account.expenses: [SchemaV6.Expense]` and `var account: SchemaV6.Account? = nil` on `Expense`. This enables nullify on delete and keeps the pattern consistent with Category. The planner should confirm which field name to use on Expense (`account` vs `accountID`).

2. **First-launch review prompt placement (D-02)**
   - What we know: A `UserDefaults` `accountReviewPending` flag is set by `didMigrate` when accounts are auto-created.
   - What's unclear: Whether the review prompt appears as a sheet from `SettingsView` (user must go to Settings) or as a modal/overlay from `RootView` (surfaced immediately on first launch).
   - Recommendation: Sheet from `SettingsView > Accounts` with a badge indicator on the Settings row, not a full modal. Less disruptive; user can ignore and review later. Planner to decide.

---

## Sources

### Primary (HIGH confidence — codebase, verified by reading)
- `MyHomeApp/Persistence/Schema/MigrationPlan.swift` — AppMigrationPlan structure, FB13812722 workaround rationale
- `MyHomeApp/Persistence/Schema/SchemaV5.swift` — CloudKit-readiness rules 1–8; V5 model field definitions; STAB-03 sortOrder footgun comment
- `MyHomeApp/Persistence/Models/*.swift` — typealias pattern; STAB-08 lesson documented in comments
- `MyHomeTests/MigrationTests.swift` — V3→V4, V4→V5 fixture test patterns; `MigrationTestsPlanV3` helper enum
- `MyHomeTests/CategoryCRUDTests.swift` — in-memory `ModelContainer` test setup; `@Test` / `#expect` patterns
- `MyHomeApp/Features/Budgets/ManageCategoriesView.swift` — `min(sortOrder)-1` insertion; `confirmationDialog` delete pattern; `lookup-before-insert` uniqueness pattern
- `MyHomeApp/Features/Expenses/ExpenseListView.swift` — `CategoryFilter` enum; `@Query` filter pattern; in-memory filter for the main list
- `MyHomeApp/Features/Gmail/GmailSyncController.swift` — `syncAccount` method; `categoryIDsByName` pre-capture pattern; batched save after loop
- `MyHomeApp/RootView.swift` — `routineResetService` injection site; `scenePhase .active` observer
- `MyHomeApp/Features/Notes/RoutineResetService.swift` — Phase 8 scaffold; IST calendar; Phase 9 hook comment

### Secondary (MEDIUM confidence — community-verified patterns)
- [byby.dev SwiftData migrations](https://byby.dev/swiftdata-migrations) — `didMigrate` is `throws`; `context.save()` required; migration fails if throws
- [Tung Vu Medium article](https://medium.com/@tungvt.it.01/%EF%B8%8F-migrating-swiftdata-models-how-to-handle-complex-changes-safely-00a28b2859c1) — `didMigrate` code pattern; explicit `try context.save()`
- [Apple Developer Forums thread/758874](https://developer.apple.com/forums/thread/758874) — crash before `didMigrate` behavior; CloudKit + custom migration incompatibility
- [Apple Developer Forums thread/748049](https://developer.apple.com/forums/thread/748049) — schema checksum mismatch prevents migration running; importance of not modifying prior schema versions

### Tertiary (LOW confidence — not independently verified)
- [atomicrobot.com unauthorized guide](https://atomicrobot.com/blog/an-unauthorized-guide-to-swiftdata-migrations/) — accessing deleted model properties crashes; validate relationships before migration
- Community consensus on "no documented rollback" for `didMigrate` — not in official Apple docs (inaccessible during research)

---

## Metadata

**Confidence breakdown:**
- Schema / V6 model definitions: HIGH — derived directly from V5 source and CloudKit rules in the codebase
- Migration pattern (nil → non-nil `didMigrate`): HIGH — code pattern; MEDIUM — throw/rollback semantics (Apple docs inaccessible, community-verified)
- Typealias atomicity requirement: HIGH — STAB-08 lesson is code-documented
- Reactive balance computation: HIGH — based on existing `@Query` patterns in the codebase
- `RoutineResetService` body: HIGH — Phase 8 stub already has the call site; D-11/D-12 decisions are precise
- Test fixture shape: HIGH — `MigrationTests.swift` provides the exact pattern to extend

**Research date:** 2026-06-09
**Valid until:** 2026-07-09 (SwiftData is stable; SwiftUI patterns in this codebase are locked conventions)
