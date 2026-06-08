# Architecture Research

**Domain:** iOS SwiftData personal-finance + household-ops app (v1.1 additive milestone)
**Researched:** 2026-06-08
**Confidence:** HIGH — based on direct codebase reading; no external sources needed

---

## Context: What Exists at SchemaV5

Four @Model types live in `SchemaV5` (the current schema):

| Model | Key fields | Notes |
|-------|-----------|-------|
| `Expense` | amount, date, note, categories[], sourceAccount (String?), gmailMessageID, ingestionStateRaw, parseConfidence | sourceAccount = Gmail email address, not a real Account entity |
| `Category` | name, symbolName, sortOrder, monthlyBudget, expenses[] | |
| `Note` | title, blocks[], isPinned, reminder* fields (Data? encoded) | |
| `NoteBlock` | kindRaw, text, isChecked, order, note, reminder* fields | |

`typealias Expense = SchemaV5.Expense` pattern is used throughout — all views bind to bare `Expense`, `Note`, etc. The typealias is flipped in `Persistence/Models/` at each schema bump; no view file needs touching.

Migration strategy: `.custom(willMigrate: nil, didMigrate: nil)` for every stage (workaround for FB13812722). All migrations so far are purely additive — new optional fields or new models. This pattern must continue for CloudKit readiness.

---

## SchemaV6 Migration Shape

### New @Model Types to Add

**Account** — represents a household bank account:
```
var id: UUID = UUID()
var name: String? = nil               // "HDFC Savings", "ICICI CC"
var institutionName: String? = nil    // "HDFC Bank"
var accountTypeRaw: String? = nil     // "savings" | "credit" | "demat" | "nps" | "other"
var last4: String? = nil              // last 4 digits of card/account — display only
var balance: Decimal? = nil           // manually entered or API-refreshed current balance
var balanceCurrencyCode: String = "INR"
var balanceUpdatedAt: Date? = nil     // when balance was last set
var gmailAddress: String? = nil       // link to GmailAccount.email for auto-linking ingested expenses
var isActive: Bool = true             // soft-delete alternative; keeps history intact
var sortOrder: Int = 0
var createdAt: Date = Date()
var updatedAt: Date = Date()
// Relationship declared on Expense side (see below)
```

**Asset** — a single holding (mutual fund, stock, NPS tier, or external balance entry):
```
var id: UUID = UUID()
var name: String? = nil               // "Mirae Asset Large Cap", "HDFC NIFTY 50"
var assetTypeRaw: String? = nil       // "mf" | "stock" | "nps" | "fd" | "other"
var isinOrCode: String? = nil         // ISIN for MF/stock; scheme code for AMFI lookup
var units: Decimal? = nil             // units held (MF/NPS); nil for stocks with qty=1
var quantity: Decimal? = nil          // quantity for stocks
var purchaseNav: Decimal? = nil       // purchase price / NAV
var purchaseCurrencyCode: String = "INR"
var lastKnownNav: Decimal? = nil      // cached last fetch
var lastNavFetchedAt: Date? = nil     // when lastKnownNav was set
var manualOverrideNav: Decimal? = nil // if set, use this instead of fetched NAV for net-worth
var sortOrder: Int = 0
var isActive: Bool = true
var createdAt: Date = Date()
var updatedAt: Date = Date()
// accountID: UUID? — optional link to an Account (for MF folios in a demat, etc.)
var accountID: UUID? = nil            // denormalised FK avoids cross-type @Relationship issues
```

### Modified @Model: Expense (V5 -> V6)

Add these optional fields:
```
var accountID: UUID? = nil            // FK to Account.id; nil = no account linked
var isTransfer: Bool = false          // flagged as self-transfer
var transferPairID: UUID? = nil       // ID of the paired expense (debit <-> credit)
var transferConfirmed: Bool = false   // user confirmed this is a transfer
var transferStateRaw: String? = nil   // "pendingReview" | "confirmed" | "rejected"
```

`sourceAccount` (String = Gmail email) is RETAINED as-is. It serves the dedup/idempotency key (D-MA-03) and must not be replaced. `accountID` is the new FK to the real `Account` entity and can be set independently.

**Rationale for UUID FK instead of @Relationship:** CloudKit does not support cross-entity relationships reliably when one side is optional and the other is a large fan-out. Using a UUID FK with application-side joins is the established CloudKit-safe pattern already used by GmailAccountStore (which stores email strings, not @Relationship references).

### Modified @Model: Note (V5 -> V6)

Add daily-routine reset tracking fields:
```
var isRoutine: Bool = false                  // marks this note as a daily routine
var routineLastResetDate: Date? = nil        // UTC start-of-day when completions last reset
```

These two fields enable the per-day completion-state model (see Daily Routine section below).

### SchemaV6 Models List
```swift
enum SchemaV6: VersionedSchema {
    static let versionIdentifier = Schema.Version(6, 0, 0)
    static var models: [any PersistentModel.Type] {
        [
            SchemaV6.Expense.self,
            SchemaV6.Category.self,
            SchemaV6.Note.self,
            SchemaV6.NoteBlock.self,
            SchemaV6.Account.self,    // NEW
            SchemaV6.Asset.self,      // NEW
        ]
    }
    // ... copies of V5 models verbatim with additive changes + new Account + Asset
}
```

### Migration Stage v5ToV6
```swift
static let v5ToV6 = MigrationStage.custom(
    fromVersion: SchemaV5.self,
    toVersion: SchemaV6.self,
    willMigrate: nil,
    didMigrate: nil
)
```
Purely additive: two new models, five new optional fields on Expense, two new optional fields on Note. No data transformation needed. `willMigrate/didMigrate` stay nil.

### Typealias Updates (Persistence/Models/)
- `Expense.swift`: flip to `SchemaV6.Expense`
- `Note.swift`: flip to `SchemaV6.Note`
- Add `Account.swift`: `typealias Account = SchemaV6.Account`
- Add `Asset.swift`: `typealias Asset = SchemaV6.Asset`

---

## System Architecture Overview

```
+--------------------------------------------------------------------------+
|                          SwiftUI Views Layer                              |
+------------+---------------+-------------+--------------+----------------+
|  Expenses  |   Accounts    |   Assets    |    Notes     |    Overview    |
|  (exists)  |   (NEW)       |   (NEW)     |  (enhanced)  |  (+ net worth) |
+------------+---------------+-------------+--------------+----------------+
|                         Service / Aggregator Layer                        |
|  GmailSyncController   PriceFetchService    SelfTransferDetector          |
|  NotificationScheduler  NetWorthAggregator  RoutineResetService           |
|  BudgetCalculator       CalendarAggregator  AccountLinkingService         |
+--------------------------------------------------------------------------+
|                        SwiftData / Persistence Layer                      |
|  SchemaV6: Expense, Category, Note, NoteBlock, Account, Asset            |
|  AppMigrationPlan: V1->V2->V3->V4->V5->V6                               |
|  ModelContainer+App: App Group store URL, CloudKit=.none (v1.1)          |
+--------------------------------------------------------------------------+
```

---

## Component Responsibilities

| Component | Responsibility | Where It Lives | Status |
|-----------|---------------|----------------|--------|
| `Account` @Model | Household bank account entity | `SchemaV6` + `Persistence/Models/Account.swift` | NEW |
| `Asset` @Model | Single investment holding | `SchemaV6` + `Persistence/Models/Asset.swift` | NEW |
| `AccountsView` | CRUD for accounts; per-account spend | `Features/Accounts/` | NEW |
| `AssetsView` | CRUD for assets; holdings list | `Features/Assets/` | NEW |
| `NetWorthView` | Net worth = account balances + holding values | `Features/Assets/` | NEW |
| `PriceFetchService` | Best-effort AMFI NAV / unofficial stock quote | `Features/Assets/PriceFetchService.swift` | NEW |
| `NetWorthAggregator` | Pure static helper: sum balances + holdings value | `Support/NetWorthAggregator.swift` | NEW |
| `SelfTransferDetector` | Post-ingestion pass: detect debit/credit pairs across accounts | `Features/Ingestion/SelfTransferDetector.swift` | NEW |
| `TransferConfirmView` | Review Inbox-style confirm UI for transfer pairs | `Features/Expenses/TransferConfirmView.swift` | NEW |
| `RoutineResetService` | Per-day reset of routine checklist state | `Support/RoutineResetService.swift` | NEW |
| `GmailSyncController` | Add post-sync SelfTransferDetector call; stamp accountID | `Features/Gmail/` | MODIFIED |
| `Note` @Model | Add `isRoutine`, `routineLastResetDate` fields | `SchemaV6` | MODIFIED |
| `Expense` @Model | Add `accountID`, `isTransfer`, `transferPairID`, `transferConfirmed`, `transferStateRaw` | `SchemaV6` | MODIFIED |
| `BudgetCalculator` | Filter out confirmed transfers from spend totals | `Support/BudgetCalculator.swift` | MODIFIED |

---

## Recommended Project Structure (New Folders)

```
MyHomeApp/Features/
+-- Accounts/               # NEW -- Account management feature
|   +-- AccountsView.swift      # list + quick-edit of accounts
|   +-- AddAccountView.swift    # add/edit sheet
|   +-- AccountRow.swift        # row component
+-- Assets/                 # NEW -- Asset tracker + net worth
|   +-- AssetsView.swift        # holdings list
|   +-- AddAssetView.swift      # add/edit holding
|   +-- NetWorthView.swift      # net worth breakdown card
|   +-- AssetRow.swift          # holding row
|   +-- PriceFetchService.swift # URLSession price fetch
+-- Expenses/               # EXISTING -- add TransferConfirmView
|   +-- TransferConfirmView.swift   # NEW -- self-transfer confirm UI

MyHomeApp/Support/
+-- NetWorthAggregator.swift    # NEW -- pure static sum helper
+-- RoutineResetService.swift   # NEW -- per-day reset logic

MyHomeApp/Features/Ingestion/
+-- SelfTransferDetector.swift  # NEW -- debit/credit pair detection

MyHomeApp/Persistence/Models/
+-- Account.swift               # NEW -- typealias Account = SchemaV6.Account
+-- Asset.swift                 # NEW -- typealias Asset = SchemaV6.Asset
```

---

## Integration Points: New vs Existing

### 1. Account @Model vs Expense.sourceAccount

`Expense.sourceAccount` is a Gmail email string used for ingestion dedup -- do NOT replace it with a FK.
`Expense.accountID` (UUID?) is the new FK to `Account.id` that links an expense to a household account entity.

Linking strategy:
- When a user creates an `Account`, they can set `gmailAddress` on it (matching GmailAccount.email).
- An `AccountLinkingService` pass at Account creation time sets `accountID` on all existing Expenses where `expense.sourceAccount == account.gmailAddress`.
- Going forward, `GmailSyncController.syncAccount()` stamps `accountID` on new ingested expenses by looking up accounts by `gmailAddress` before inserting. One extra fetch at sync start: `let accountsByGmail: [String: Account]`.
- Manual expenses get `accountID` set via an optional picker in `AddExpenseView`.

Account deletion: application-side nil-out of `accountID` on affected Expenses before deleting the Account model. No cascade needed in SwiftData.

### 2. Self-Transfer Detection Seam

`SelfTransferDetector` is a pure value-type struct (mirrors `DedupChecker`):
```swift
struct SelfTransferDetector {
    /// Returns matched (debit, credit) pairs from the provided expense window.
    static func detectPairs(in expenses: [Expense], windowHours: Int = 6) -> [(Expense, Expense)]
}
```

Called from `GmailSyncController.syncAccount()` after the last `ctx.save()` in each sync batch:
```swift
// After all expenses written for this sync batch:
let recentExpenses = (try? ctx.fetch(FetchDescriptor<Expense>())) ?? []
let pairs = SelfTransferDetector.detectPairs(in: recentExpenses)
for (debit, credit) in pairs {
    debit.isTransfer = true
    debit.transferPairID = credit.id
    debit.transferStateRaw = "pendingReview"
    credit.isTransfer = true
    credit.transferPairID = debit.id
    credit.transferStateRaw = "pendingReview"
}
try? ctx.save()
```

The `TransferConfirmView` reuses the `ReviewInboxRow` skeleton -- a section in `ExpenseListView` titled "Possible Transfers" above the existing "Needs Review" section. Swipe-to-confirm mirrors the accept/discard pattern. Confirmed transfers (`transferStateRaw = "confirmed"`) are excluded from spend aggregation by updating `BudgetCalculator` and `SpendOverTimeAggregator` to filter on `isTransfer && transferConfirmed`.

### 3. Price-Fetch Service Seam

`PriceFetchService` is an `@Observable` class owned by `AssetsView` (or a parent coordinator) via `@State`. Not a singleton. Matches how `GmailSyncController` is owned by `RootView` via `@State`.

```swift
@Observable
final class PriceFetchService {
    var isFetching: Bool = false
    var lastError: String? = nil

    func fetchAll(assets: [Asset], modelContext: ModelContext) async
    func fetchAMFI(schemeCode: String) async throws -> Decimal   // AMFI free API
    func fetchStockQuote(symbol: String) async -> Decimal?       // best-effort, unofficial
}
```

AMFI endpoint (HIGH confidence -- free, stable):
`https://api.mfapi.in/mf/<schemeCode>` returns NAV JSON. Most reliable free Indian MF NAV source.

Stock quotes (LOW confidence on free official sources):
Yahoo Finance `v8/finance/chart/` is de-facto standard but unofficial. Always allow `manualOverrideNav` to take precedence. Show "approx" indicator when `lastNavFetchedAt` is stale (>24h).

Caching: `lastKnownNav` + `lastNavFetchedAt` are persisted on `Asset` @Model. PriceFetchService reads these first -- if within 4h, skip the network call.

`NetWorthAggregator` (pure static, mirrors BudgetCalculator):
```swift
enum NetWorthAggregator {
    static func totalNetWorth(accounts: [Account], assets: [Asset]) -> Decimal
    static func totalAccountBalance(accounts: [Account]) -> Decimal
    static func totalHoldingsValue(assets: [Asset]) -> Decimal
    // Per-asset current value:
    // (manualOverrideNav ?? lastKnownNav ?? purchaseNav ?? 0) * (units ?? quantity ?? 1)
}
```

### 4. Daily Routine Per-Day Completion Reset

The bug: a note with daily-recurrence reminder has its checklist blocks (`NoteBlock.isChecked`) persist across days. The checklist should reset to unchecked when the user opens the app on a new day.

Model approach -- date-keyed completion via routineLastResetDate (recommended):
- `Note.isRoutine: Bool = false` -- marks this as a daily routine note
- `Note.routineLastResetDate: Date? = nil` -- UTC start-of-day of the last reset

`RoutineResetService` (pure struct, called on app foreground):
```swift
struct RoutineResetService {
    static func resetIfNeeded(notes: [Note], context: ModelContext) throws
    // For each note where isRoutine == true && routineLastResetDate < startOfToday:
    //   set all blocks.isChecked = false
    //   note.routineLastResetDate = startOfToday (UTC)
    // Explicit context.save() at end
}
```

Called from `RootView.onChange(of: scenePhase)` on `.active` transition -- the same hook used by `GmailSyncController.scenePhaseChanged()`. Deterministic; no background task needed.

Calendar integration: a routine note with `isRoutine = true` and `reminderEnabled = true` (daily `RecurrenceType.daily`) already surfaces in `CalendarView` on every day via the existing `CalendarAggregator.perDayCounts()`. No changes to CalendarAggregator needed. The "daily reminder in calendar" feature is achieved by: set `isRoutine = true` in `EditNoteView`, auto-configure reminder to daily recurrence. The existing `NotificationScheduler` handles the rest.

---

## Key Data Flows

### Expense Ingestion (V1.1 extended)
```
Gmail sync (GmailSyncController.syncAccount)
    |
    v
Parse + ConfidenceScorer + DedupChecker  [existing]
    |
    v
Write Expense with sourceAccount + accountID (lookup by gmailAddress)
    |
    v
SelfTransferDetector.detectPairs(in: recentExpenses)   [NEW]
    |
    v
Flag transfer pairs: isTransfer=true, transferStateRaw="pendingReview"
    |
    v
TransferConfirmView shows pairs -> user confirms or rejects
    |
    v
BudgetCalculator / SpendOverTimeAggregator filter out confirmed transfers
```

### Net Worth Computation
```
AssetsView appears
    |
    v
PriceFetchService.fetchAll(assets:modelContext:)  [async, best-effort]
    |
    v
Asset.lastKnownNav updated in SwiftData
    |
    v
NetWorthView (@Query on Account + Asset, live)
    |
    v
NetWorthAggregator.totalNetWorth(accounts:assets:)  [pure, synchronous]
    |
    v
Account Balances + Holdings Value = Net Worth
```

### Daily Routine Reset
```
App transitions to foreground (ScenePhase .active)
    |
    v
RootView.onChange(of: scenePhase)
    |
    v
RoutineResetService.resetIfNeeded(notes:context:)
    |
    v
For each Note where isRoutine && routineLastResetDate < startOfToday:
    block.isChecked = false  (all blocks)
    note.routineLastResetDate = startOfToday
    |
    v
context.save()  [explicit -- no autosave reliance per CLAUDE.md]
```

---

## Dependency-Ordered Build Sequence

```
Phase 0: Stabilization         (no schema changes; fixes 3 bugs before V6 work)
    |
    v
Phase 1: SchemaV6 + Migration  (Account + Asset models; all new fields on Expense + Note)
    |
    v
Phase 2: Accounts Feature      (AccountsView, AccountLinkingService, per-account spend)
    |
    v
Phase 3: Self-Transfer         (SelfTransferDetector, TransferConfirmView, aggregator filter)
    |
    v
Phase 4: Asset Tracker         (AssetsView, PriceFetchService, NetWorthAggregator, NetWorthView)
    |
    v  (independent of 3; can swap with Phase 3)
Phase 5: Notes Enhancement     (isRoutine toggle, RoutineResetService, calendar daily reminder)
```

Phase 4 (Assets) only needs Phase 1 complete -- it is independent of Phases 2 and 3 and can be built in parallel with them if needed.

Phase 5 (Notes) only needs Phase 1 complete -- independent of Phases 2, 3, 4.

---

## Anti-Patterns to Avoid

### Anti-Pattern 1: @Relationship between Account and Expense
**What people do:** Add `@Relationship var expenses: [Expense]` on Account.
**Why it's wrong:** SchemaV5 documents this exact pattern as causing "Circular reference resolving attached macro 'Relationship'" on fan-out relationships. CloudKit also does not support large fan-out relationships reliably.
**Do this instead:** UUID FK (`accountID: UUID?` on Expense). Join at query time in aggregators and filtered views.

### Anti-Pattern 2: Storing asset type as a Swift enum in @Model
**What people do:** `var assetType: AssetType` where AssetType is a Swift enum.
**Why it's wrong:** CloudKit rule 8 (no stored enums). Same pitfall as `ingestionStateRaw` on Expense and `kindRaw` on NoteBlock.
**Do this instead:** `var assetTypeRaw: String?` with a computed var for decoding.

### Anti-Pattern 3: PriceFetchService as a singleton
**What people do:** `static let shared = PriceFetchService()` injected via environment.
**Why it's wrong:** The service holds network tasks; singletons can't be cleaned up cleanly. Tests become complex.
**Do this instead:** Own as `@State private var priceFetcher = PriceFetchService()` in `AssetsView`, inject `modelContext` explicitly. Matches the GmailSyncController ownership pattern.

### Anti-Pattern 4: Background rollover job for routine reset
**What people do:** BGAppRefreshTask that resets routine checklists overnight.
**Why it's wrong:** BGAppRefreshTask execution is not guaranteed and the slot is already used for Gmail sync.
**Do this instead:** `RoutineResetService.resetIfNeeded()` on foreground activation -- deterministic and always runs before the user sees content.

### Anti-Pattern 5: Replacing sourceAccount with accountID FK
**What people do:** Treating `Expense.sourceAccount` (Gmail email) as redundant once `accountID` exists.
**Why it's wrong:** `sourceAccount` is the dedup idempotency key in `GmailSyncController.syncAccount()` (D-MA-03). Removing it breaks dedup for all existing and future ingested expenses.
**Do this instead:** Keep both. `sourceAccount` = Gmail email for ingestion pipeline. `accountID` = FK to Account entity for spend/account views.

### Anti-Pattern 6: Separate RoutineCompletion @Model
**What people do:** A `RoutineCompletion` @Model with `(noteID, date, isCompleted)` records.
**Why it's wrong:** Creates a growing append-only table, CloudKit sync overhead, complex cleanup.
**Do this instead:** Reset `NoteBlock.isChecked = false` directly on live blocks when day changes. Store only `routineLastResetDate` on Note for idempotency.

---

## CloudKit Readiness Checklist for New Models

Both Account and Asset must follow all SchemaV5 rules:
- All stored properties have a default or are optional
- No `@Attribute(.unique)` anywhere
- Decimal for money (never Double)
- UTC timestamps via `Date = Date()`
- UUID primary key (`id: UUID = UUID()`)
- No stored enums (use `*Raw: String?`)
- No `@Relationship` fan-out from Account to Expense (use UUID FK instead)
- Both added to `SchemaV6.models` list and to `AppMigrationPlan.schemas`

---

## Sources

- Direct codebase reading (HIGH confidence, first-party source):
  - `MyHomeApp/Persistence/Schema/SchemaV5.swift`
  - `MyHomeApp/Persistence/Schema/MigrationPlan.swift`
  - `MyHomeApp/Persistence/ModelContainer+App.swift`
  - `MyHomeApp/Features/Gmail/GmailSyncController.swift`
  - `MyHomeApp/Features/Gmail/GmailAccountStore.swift`
  - `MyHomeApp/Support/NotificationScheduler.swift`
  - `MyHomeApp/Support/CalendarAggregator.swift`
  - `MyHomeApp/Features/Notes/CalendarView.swift`
  - `MyHomeApp/Persistence/Models/ReminderValueTypes.swift`
  - `MyHomeApp/Features/Expenses/ReviewInboxRow.swift`
- AMFI MF NAV API (`api.mfapi.in`) -- free Indian MF NAV endpoint (MEDIUM confidence)

---
*Architecture research for: MyHome v1.1 -- Accounts, Assets & Household Polish*
*Researched: 2026-06-08*
