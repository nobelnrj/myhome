# Phase 11: Asset Tracker — Research

**Researched:** 2026-06-11
**Domain:** SwiftUI / SwiftData asset tracking — AMFI MF NAV fetch, SchemaV7 migration, net-worth aggregation, Swift Charts, IST-gated daily hooks
**Confidence:** HIGH

---

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

- **D-01:** MF holdings link to AMFI scheme via searchable picker; selection stores `amfiSchemeCode` on `Asset` for exact-code NAV matching.
- **D-02:** Scheme list sourced from the same `NAVAll.txt` fetch — one download feeds both picker and NAVs. Cache the parsed list.
- **D-03:** Add `amfiSchemeCode` to `Asset` and a new `NetWorthSnapshot` @Model in one additive **SchemaV7** migration. Follow additive/CloudKit-ready rules and FB13812722 `.custom`-stage discipline. V7 likely needs no `didMigrate` backfill (additive fields default to nil).
- **D-04:** Net-worth summary + allocation chart live on the **Overview screen** as a tappable card/section alongside existing spend cards.
- **D-05:** Holdings management (CRUD) lives under **Settings > Assets** — mirroring the Accounts pattern. Two entry points open the same view: (a) tapping the Overview net-worth section, (b) `Settings > Assets` row. Tab bar unchanged.
- **D-06:** AMFI NAV fetch fires **daily on `scenePhase .active`** using the same IST once-per-day gate as `RoutineResetService`. Plus manual pull-to-refresh.
- **D-07:** On fetch failure — **fail silently**. Keep cached NAV with its as-of date; staleness badge signals oldness. No error popups.
- **D-08:** Record **one snapshot per day on `scenePhase .active`** — upsert today's (overwrite if already exists). Ties into the same daily app-active hook as NAV refresh.
- **D-09:** Each snapshot stores total net worth AND per-asset-class breakdown (MF / stock / NPS / cash sub-totals).
- **D-10:** Staleness threshold is **calendar-based**: a price is stale when its as-of date is more than ~1 calendar day old. Ignores weekends/holidays — harmless.
- **D-11:** Donut "cash" slice = net sum of all account balances (savings positive, CC negative per Phase 9 D-09). Net worth = plain sum. Negative net (CC > cash) rendered gracefully.

### Claude's Discretion

- Exact `NetWorthSnapshot` model field shape (date granularity, per-class sub-total storage) within V7 migration.
- Gain/loss display layout (absolute + % per holding), empty/zero-cost-basis edge cases.
- How to render a negative-net donut / clamp negative cash gracefully (D-11).
- Multiple holdings of the same fund, NPS tier handling, other holding-modeling edge cases.
- Exact `NAVAll.txt` parsing + caching strategy and picker search ranking.

### Deferred Ideas (OUT OF SCOPE)

- Auto-fetch for stocks and NPS (manual-only in v1.1; Yahoo fragile, npsnav single-maintainer).
- CloudKit / sharing (v2.0 trigger).
- Any new SPM dependency (zero new deps across the milestone).
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| ASSET-01 | User can add, edit, and delete holdings across asset classes: mutual funds, stocks, NPS, and (via Accounts) cash balances. | Accounts CRUD pattern (AccountsListView/EditAccountView) directly mirrors Holdings CRUD. Asset @Model scaffold ready in SchemaV6. |
| ASSET-02 | User can record units and cost basis per holding, with current value derived. | `units: Decimal?` and `costBasisPerUnit: Decimal?` already on `SchemaV6.Asset`. Current value = units × currentNAV — pure computed Decimal. |
| ASSET-03 | Mutual fund NAV auto-refreshes from AMFI source (best-effort, cached, never blocks UI); user can always override NAV manually. | AMFI NAVAll.txt format verified. URLSession fetch + in-memory + UserDefaults cache. RootView scenePhase `.active` hook pattern confirmed. |
| ASSET-04 | Stock and NPS holdings are valued by manual current-value/NAV entry (no auto-fetch for stocks in v1.1). | `currentNAV: Decimal?` field on Asset used for manual entry. Same edit form as MF, minus AMFI picker. |
| ASSET-05 | User sees total net worth = sum of holding values + account balances. | `AccountBalance.compute()` provides account balances. MF/stock/NPS values = units × currentNAV sum. Both are Decimal. |
| ASSET-06 | User sees per-holding gain/loss (absolute and %) against cost basis. | Cost basis = units × costBasisPerUnit. Gain = currentValue − totalCost. Percent = gain / totalCost × 100. Edge case: costBasisPerUnit == nil or 0 → show "—". |
| ASSET-07 | User sees an asset-allocation chart (net worth split by asset class). | `DonutChart.swift` is a drop-in — takes `[DonutSegment]`. Four segments: MF, stock, NPS, cash. |
| ASSET-08 | App snapshots net worth over time and charts the trend. | `NetWorthSnapshot` @Model in SchemaV7. `SpendOverTimeChart` pattern for AreaMark+LineMark trend. |
| ASSET-09 | Price/NAV values display their as-of date and a stale indicator when data is older than the freshness threshold. | `navAsOfDate: Date?` on Asset. Staleness = calendar-day diff > 1 (D-10). Format: "as of DD-MMM-YYYY". |
</phase_requirements>

---

## Summary

Phase 11 builds a full asset-tracker feature on top of the `SchemaV6.Asset` scaffold introduced in Phase 9 but left without UI. The phase has three technical pillars: (1) a SchemaV7 additive migration adding `amfiSchemeCode: String?` to `Asset` and a new `NetWorthSnapshot` @Model; (2) a stateless `AMFINavService` that fetches `NAVAll.txt` from AMFI India, parses its semicolon-delimited format, and caches results for both the scheme-picker and daily NAV updates; and (3) UI surfaces on Overview (net-worth card + allocation donut) and Settings > Assets (holdings CRUD), wired into the existing `scenePhase .active` daily hook pattern.

All primary technical unknowns have been resolved through direct source inspection. The AMFI `NAVAll.txt` file format is confirmed: semicolon-delimited, six columns (`Scheme Code;ISIN Div Payout/ISIN Growth;ISIN Div Reinvestment;Scheme Name;Net Asset Value;Date`), with section-header lines that contain no semicolons — these are skipped during parsing. File size is ~1.6 MB (confirmed via HTTP Content-Length). NAV values are plain decimal strings (e.g. `105.6569`); dates use `DD-MMM-YYYY` format (e.g. `10-Jun-2026`). The fetch URL is `https://portal.amfiindia.com/spages/NAVAll.txt` (the `amfiindia.com` domain redirects to `portal.amfiindia.com`).

The existing codebase patterns — `RoutineResetService` (daily IST hook), `AccountsListView`/`EditAccountView` (Settings CRUD), `DonutChart` (allocation ring), `SpendOverTimeChart` (trend area chart), `AccountBalance.compute()` (cash slice source) — all translate directly. SchemaV7 follows the exact same additive rules as V6: `.custom` stage, `willMigrate: nil`, `didMigrate: nil` (no backfill needed since new fields default to nil), append `SchemaV7.self` to the arrays in `MigrationPlan.swift` and `ModelContainer+App.swift`, and flip ALL typealiases atomically (STAB-08).

**Primary recommendation:** Implement in two waves: Wave 1 is the atomic SchemaV7 commit (migration + all typealias flips + blocking migration test); Wave 2 is three parallelizable feature plans (AMFINavService + Holdings CRUD + Overview net-worth card/charts).

---

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| SchemaV7 migration (amfiSchemeCode + NetWorthSnapshot) | Persistence layer | — | Additive SwiftData schema change; no UI dependency |
| AMFINavService: fetch, parse, cache NAVAll.txt | Service layer (MainActor) | URLSession (network) | Business logic, no SwiftUI — mirrors RoutineResetService / TransferScanService pattern |
| Holdings CRUD (add/edit/delete Asset) | Settings feature | Shared EditAssetView sheet | Mirrors AccountsListView pattern exactly |
| AMFI scheme-code picker | Settings feature (AddEditAssetView) | AMFINavService (data source) | In-sheet searchable list; picker needs at least one successful fetch |
| Net-worth aggregation (holdings + account balances) | Service/computed | AccountBalance.compute() | Pure Decimal computation; no persistence |
| Allocation donut card | Overview feature | DonutChart.swift (reuse) | Card added to OverviewView / OverviewMonthContent body |
| Net-worth trend chart | Overview feature | SpendOverTimeChart pattern | New chart view; queries NetWorthSnapshot via @Query |
| Daily NAV refresh + snapshot upsert | RootView scenePhase hook | AMFINavService + new SnapshotService | Follows RoutineResetService wire-in in RootView.onChange |
| Staleness badge | Shared UI component | navAsOfDate on Asset | Calendar-day diff, rendered inline on holding rows and detail views |

---

## Standard Stack

### Core (zero new dependencies — all already in project)

| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| SwiftData | iOS 17+ | Persistence, @Model, @Query | Project-wide ORM; all models live here |
| Swift Charts | iOS 16+ | DonutChart (SectorMark), trend chart (AreaMark+LineMark) | Already used; DonutChart.swift and SpendOverTimeChart.swift are drop-in templates |
| Foundation / URLSession | iOS 17+ | Fetch NAVAll.txt from AMFI | Standard HTTP; no Alamofire or any 3rd-party networking |
| SwiftUI | iOS 17+ | All UI surfaces | Project-wide UI framework |

### No New SPM Dependencies

Zero new packages. Every capability is implemented with stdlib + platform frameworks per v1.1 milestone constraint.

---

## Package Legitimacy Audit

Not applicable — this phase introduces zero new external packages. All libraries are iOS SDK built-ins (SwiftData, Swift Charts, URLSession, SwiftUI). No slopcheck required.

---

## Architecture Patterns

### System Architecture Diagram

```
scenePhase .active (RootView.onChange)
        │
        ├──► AMFINavService.refreshIfNeeded()
        │         │
        │         ├── UserDefaults: lastFetchDate < startOfTodayIST?
        │         │         YES ──► URLSession.dataTask("https://portal.amfiindia.com/spages/NAVAll.txt")
        │         │                     │
        │         │                     ├── parse: split lines, split ";" → AMFIScheme(code, name, nav, date)
        │         │                     ├── update Asset.currentNAV / Asset.navAsOfDate (matched by amfiSchemeCode)
        │         │                     ├── cache parsed list in memory (for picker)
        │         │                     └── persist lastFetchDate = today (UserDefaults)
        │         │         NO  ──► no-op (today's data already loaded)
        │         └── on failure ──► silent (D-07: log, keep cached NAV, staleness badge handles UX)
        │
        └──► NetWorthSnapshotService.upsertIfNeeded()
                  │
                  ├── UserDefaults / @Query: snapshot for today already exists?
                  │         YES ──► overwrite total + sub-totals (upsert)
                  │         NO  ──► insert new NetWorthSnapshot
                  └── compute: Σ(Asset.units × Asset.currentNAV) + Σ(AccountBalance.compute(...))

User interaction
        │
        ├──► OverviewView → NetWorthCard (tappable → AssetsListView)
        │         ├── NetWorthSummaryRow: total = MF+stock+NPS+cash
        │         ├── DonutChart(segments: [MF, stock, NPS, cash]) — reuses DonutChart.swift
        │         └── NetWorthTrendChart (AreaMark+LineMark over NetWorthSnapshot @Query)
        │
        └──► Settings > Assets → AssetsListView
                  ├── ForEach Asset: holding row (name, units, currentNAV, value, gain/loss, staleness badge)
                  └── sheet ──► EditAssetView
                            ├── assetClassRaw picker (mutual_fund / stock / nps)
                            ├── IF mutual_fund ──► AMFISchemePickerView (searchable, feeds amfiSchemeCode)
                            ├── units: Decimal field
                            ├── costBasisPerUnit: Decimal field
                            └── currentNAV: Decimal field (manual override; auto-populated from AMFINavService for MF)
```

### Recommended Project Structure

```
MyHomeApp/Features/Assets/
├── AssetsListView.swift          # CRUD list under Settings (mirrors AccountsListView)
├── EditAssetView.swift           # Add/edit sheet (mirrors EditAccountView)
├── AMFISchemePickerView.swift    # Searchable MF scheme picker (in-sheet)
├── NetWorthCard.swift            # Overview card: summary + donut + trend
└── NetWorthTrendChart.swift      # AreaMark+LineMark over NetWorthSnapshot

MyHomeApp/Support/
└── AMFINavService.swift          # Fetch/parse/cache NAVAll.txt; inject context; daily refresh + upsert

MyHomeApp/Persistence/Schema/
└── SchemaV7.swift                # Additive: amfiSchemeCode on Asset + NetWorthSnapshot @Model

MyHomeApp/Persistence/Models/
└── NetWorthSnapshot.swift        # typealias NetWorthSnapshot = SchemaV7.NetWorthSnapshot
```

(Asset.swift typealias already exists and flips to SchemaV7 in the migration commit.)

---

## AMFI NAVAll.txt — Verified File Format

**Source:** `https://portal.amfiindia.com/spages/NAVAll.txt` (amfiindia.com redirects here) [VERIFIED: direct HTTP fetch 2026-06-11]

### Format Specification

| Property | Value |
|----------|-------|
| Encoding | UTF-8 plain text |
| Delimiter | Semicolon (`;`) |
| File size | ~1.6 MB (Content-Length: 1641244 as of 2026-06-11) |
| Update frequency | Daily (Last-Modified: Thu, 11 Jun 2026 08:38:05 GMT observed) |
| Total records | ~13,000–15,000 fund rows estimated from file size |

### Column Layout (Line 1 is the header)

```
Scheme Code;ISIN Div Payout/ ISIN Growth;ISIN Div Reinvestment;Scheme Name;Net Asset Value;Date
```

| Col # | Name | Example | Notes |
|-------|------|---------|-------|
| 0 | Scheme Code | `119551` | Numeric string; AMFI's canonical fund ID |
| 1 | ISIN Div Payout / ISIN Growth | `INF209KA12Z1` | May be `-` for absent ISIN |
| 2 | ISIN Div Reinvestment | `INF209KA13Z9` | May be `-` |
| 3 | Scheme Name | `Aditya Birla Sun Life Banking & PSU Debt Fund  - DIRECT - IDCW` | Free text; may contain extra spaces |
| 4 | Net Asset Value | `105.6569` | Decimal string; parse with `Decimal(string:)` |
| 5 | Date | `10-Jun-2026` | `DD-MMM-YYYY` format |

### Section Headers

Lines that contain no semicolons are **section-header lines** (AMC group names), e.g.:

```
Open Ended Schemes(Debt Scheme - Banking and PSU Fund)
```

These must be skipped during parsing. Detection rule: `line.contains(";") == false || line.isEmpty`.

### Date Parsing

NAV dates use `DD-MMM-YYYY` (e.g. `10-Jun-2026`). Parse with:

```swift
// Source: verified against real NAVAll.txt output 2026-06-11
let formatter = DateFormatter()
formatter.dateFormat = "dd-MMM-yyyy"
formatter.locale = Locale(identifier: "en_US_POSIX")
formatter.timeZone = TimeZone(identifier: "Asia/Kolkata")  // AMFI dates are IST
```

Storing the parsed `Date` in UTC on `Asset.navAsOfDate` is correct — the project-wide rule is "store UTC, compare/format in IST."

### NAV Value Parsing

`Decimal(string: navString)` is the correct parser — never `Double(navString)`. The Decimal rule is project-wide (Pitfall 17 in codebase comments; enforced on all money fields).

### Parsing Strategy in Swift

```swift
// Source: verified format from direct fetch 2026-06-11 [VERIFIED]
struct AMFIScheme {
    let code: String          // col 0
    let name: String          // col 3
    let nav: Decimal          // col 4
    let navDate: Date         // col 5, parsed DD-MMM-yyyy
}

func parseNAVAll(_ text: String) -> [AMFIScheme] {
    var results: [AMFIScheme] = []
    let lines = text.components(separatedBy: "\n")
    // Skip header line (line 0); skip section-header lines (no semicolons)
    for line in lines.dropFirst() {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.contains(";") else { continue }  // section header — skip
        let parts = trimmed.components(separatedBy: ";")
        guard parts.count >= 6 else { continue }        // malformed — skip
        let code = parts[0].trimmingCharacters(in: .whitespaces)
        let name = parts[3].trimmingCharacters(in: .whitespaces)
        let navString = parts[4].trimmingCharacters(in: .whitespaces)
        let dateString = parts[5].trimmingCharacters(in: .whitespaces)
        guard let nav = Decimal(string: navString),
              let navDate = navDateFormatter.date(from: dateString) else { continue }
        results.append(AMFIScheme(code: code, name: name, nav: nav, navDate: navDate))
    }
    return results
}
```

### Caching Strategy

- **In-memory cache:** `[String: AMFIScheme]` keyed by scheme code, stored on `AMFINavService` (@Observable). Populated after each successful parse. Serves the scheme picker immediately on subsequent opens.
- **Persistence of last-fetch date:** `UserDefaults` key `"amfiNavLastFetchDate"` (ISO date string or `timeIntervalSince1970`). The daily gate mirrors `RoutineResetService`: compare stored date against `startOfTodayIST`.
- **NAV values on Asset:** Stored persistently in SwiftData (`Asset.currentNAV`, `Asset.navAsOfDate`). These render immediately on app launch even before any network call.
- **No disk cache of the raw text:** At ~1.6 MB, re-fetching is fast enough on app active. The SwiftData Asset rows ARE the persistent NAV cache.

### Fetch Architecture

`AMFINavService` mirrors `TransferScanService`: `@MainActor @Observable final class`, `var modelContext: ModelContext?`, injected by `RootView.onAppear`. One method `refreshIfNeeded()` is called synchronously from `RootView.onChange(of: scenePhase)` — but the URLSession call inside uses `Task { }` to avoid blocking the main thread. Pattern:

```swift
// [VERIFIED: mirrors TransferScanService pattern in codebase]
func refreshIfNeeded() {
    guard let context = modelContext else { return }
    let cal = Calendar(identifier: .gregorian)
    // cal.timeZone = IST ...
    let todayIST = cal.startOfDay(for: Date())
    let lastFetch = UserDefaults.standard.object(forKey: "amfiNavLastFetchDate") as? Date ?? .distantPast
    guard lastFetch < todayIST else { return }  // already fetched today
    Task { await performFetch(context: context) }
}
```

---

## SchemaV7 Migration Pattern

### What Changes in V7

Based on direct reading of `SchemaV6.swift` and `MigrationPlan.swift`:

**Additive changes to `SchemaV7.Asset`** (copy V6.Asset verbatim, append):

```swift
// NEW in SchemaV7 — append AFTER all V6 fields (additive only)
var amfiSchemeCode: String? = nil   // D-01: AMFI scheme code; nil for stocks/NPS/manual MF
```

**New `SchemaV7.NetWorthSnapshot` @Model** (new entity — no migration backfill needed):

```swift
@Model
final class NetWorthSnapshot {
    var id: UUID = UUID()
    var date: Date = Date()          // UTC; represents start-of-day IST (upsert key)
    var totalNetWorth: Decimal = 0   // Decimal (rule 3); MF+stock+NPS+cash total
    // Per-class sub-totals (D-09) — Decimal fields, defaulted 0
    var mfValue: Decimal = 0
    var stockValue: Decimal = 0
    var npsValue: Decimal = 0
    var cashValue: Decimal = 0       // sum of AccountBalance.compute() for all active accounts
    var createdAt: Date = Date()

    init() { self.id = UUID(); self.createdAt = Date() }
}
```

CloudKit rules on `NetWorthSnapshot`: every property has a default or is optional; no `.unique`; Decimal for money; UUID primary key.

### MigrationPlan.swift Changes

```swift
// Append to schemas array:
[SchemaV1.self, SchemaV2.self, SchemaV3.self, SchemaV4.self, SchemaV5.self, SchemaV6.self, SchemaV7.self]

// Append to stages array:
[v1ToV2, v2ToV3, v3ToV4, v4ToV5, v5ToV6, v6ToV7]

// New stage (additive-only, no didMigrate backfill needed):
static let v6ToV7 = MigrationStage.custom(
    fromVersion: SchemaV6.self,
    toVersion: SchemaV7.self,
    willMigrate: nil,
    didMigrate: nil   // amfiSchemeCode defaults nil; NetWorthSnapshot is new — no backfill
)
```

### Typealias Flip (STAB-08 Rule — Critical)

All @Model typealiases must flip from SchemaV6 to SchemaV7 **in the same commit** as the MigrationPlan change:

| File | Change |
|------|--------|
| `Models/Asset.swift` | `typealias Asset = SchemaV7.Asset` |
| `Models/NetWorthSnapshot.swift` | `typealias NetWorthSnapshot = SchemaV7.NetWorthSnapshot` (new file) |
| `Models/Account.swift` | `typealias Account = SchemaV7.Account` |
| `Models/Expense.swift` | `typealias Expense = SchemaV7.Expense` |
| `Models/Category.swift` | `typealias Category = SchemaV7.Category` |
| `Models/Note.swift` | `typealias Note = SchemaV7.Note` |
| `Models/NoteBlock.swift` | `typealias NoteBlock = SchemaV7.NoteBlock` |
| `Persistence/ModelContainer+App.swift` | `Schema(versionedSchema: SchemaV7.self)` |

**STAB-08 crash vector:** If ANY typealias still points to SchemaV6 while the container uses SchemaV7, SwiftData will crash on save or query of that model type. All must flip together in one atomic commit.

### FB13812722 Compliance

Use `.custom(fromVersion:toVersion:willMigrate:didMigrate:)` not `.lightweight`. This is mandatory for all stages in this codebase to sidestep the iOS 17.0–17.3 SchemaMigrationPlan bug. [VERIFIED: MigrationPlan.swift comment + all existing stages]

### ModelContainer+App.swift Change

```swift
// Old:
let schema = Schema(versionedSchema: SchemaV6.self)
// New:
let schema = Schema(versionedSchema: SchemaV7.self)
```

The `models` array in `SchemaV7` must include `NetWorthSnapshot.self` alongside all V6 models.

---

## Net-Worth Aggregation

### Formula

```swift
// [VERIFIED: AccountBalance.compute() signature in AccountBalance.swift]
// All amounts are Decimal
let holdingValue: Decimal = assets.reduce(.zero) { sum, asset in
    guard let units = asset.units, let nav = asset.currentNAV else { return sum }
    return sum + units * nav
}

let cashValue: Decimal = accounts
    .filter { !$0.isArchived }
    .reduce(.zero) { sum, account in
        sum + AccountBalance.compute(
            baseline: account.balanceBaseline,
            asOf: account.balanceAsOfDate,
            expenses: allExpenses,
            accountID: account.id
        )
    }

let totalNetWorth = holdingValue + cashValue
// Note: cashValue may be negative (credit card debt > savings balance) — this is correct
```

### Sign Convention (from AccountBalance.swift — VERIFIED)

- Spends stored POSITIVE; balance = `baseline - net` (fixed Phase 10).
- CC baseline stored as negative amount-owed → CC balance is naturally negative.
- Net worth = holdingValue + cashValue: if cashValue is negative (CC debt > savings), net worth decreases. This is correct financial semantics.

### Per-Holding Gain/Loss

```swift
// ASSET-06
let totalCost = (asset.units ?? 0) * (asset.costBasisPerUnit ?? 0)
let currentValue = (asset.units ?? 0) * (asset.currentNAV ?? 0)
let absoluteGain = currentValue - totalCost
let percentGain: Decimal? = totalCost > 0 ? (absoluteGain / totalCost) * 100 : nil
// percentGain == nil → display "—" (zero cost basis edge case)
```

---

## scenePhase .active Daily Hook Pattern

**Template from `RoutineResetService`** [VERIFIED: RoutineResetService.swift + RootView.swift]:

```swift
// RootView.swift — existing .onChange block (line 115-126)
.onChange(of: scenePhase) { _, newPhase in
    lockController.scenePhaseChanged(newPhase)
    gmailSyncController.scenePhaseChanged(newPhase)
    if newPhase == .active {
        routineResetService.resetIfNeeded()   // synchronous — no Task needed
        // Phase 11 additions wire in here:
        // amfiNavService.refreshIfNeeded()      // synchronous IST gate, Task inside
        // netWorthSnapshotService.upsertIfNeeded() // synchronous IST gate, Task inside
    }
    // ...
}
```

**IST daily gate (from RoutineResetService.resetIfNeeded):**

```swift
var cal = Calendar(identifier: .gregorian)
cal.timeZone = TimeZone(identifier: "Asia/Kolkata")!
let startOfTodayIST = cal.startOfDay(for: Date())
// Compare stored date against startOfTodayIST
```

**Service injection pattern (from RootView.onAppear):**

```swift
// RootView.onAppear — add alongside existing injections:
amfiNavService.modelContext = modelContext
netWorthSnapshotService.modelContext = modelContext
```

Both new services declared as `@State private var amfiNavService = AMFINavService()` and `@State private var netWorthSnapshotService = NetWorthSnapshotService()` in RootView, mirroring `@State private var routineResetService = RoutineResetService()`.

---

## DonutChart Reuse Pattern

**From `DonutChart.swift`** [VERIFIED: direct read]:

```swift
// Drop-in usage for asset allocation:
DonutChart(
    segments: [
        DonutSegment(id: "mf",    label: "Mutual Funds", value: Double(mfValue),    color: .blue),
        DonutSegment(id: "stock", label: "Stocks",       value: Double(stockValue), color: .green),
        DonutSegment(id: "nps",   label: "NPS",          value: Double(npsValue),   color: .orange),
        DonutSegment(id: "cash",  label: "Cash",         value: Double(max(cashValue, 0)), color: .teal),
    ],
    size: 132
) {
    VStack(spacing: 0) {
        Text("NET WORTH").font(.caption2).foregroundStyle(.secondary)
        Text(totalNetWorth.formattedINR()).font(.headline).lineLimit(1).minimumScaleFactor(0.6)
    }
}
```

**Negative cash slice:** `max(cashValue, 0)` clamps negative cash to zero for the donut (negative slice value crashes SectorMark). Display total net worth as-is (can be negative); the donut simply shows a zero cash wedge when CC > savings.

**Decimal-to-Double conversion:** `NSDecimalNumber(decimal: d).doubleValue` or `Double(truncating: d as NSDecimalNumber)` — same pattern already used in `OverviewView.double(_:)`.

---

## Net-Worth Trend Chart Pattern

**Template from `SpendOverTimeChart.swift`** [VERIFIED: direct read]:

The trend chart for `NetWorthSnapshot` follows the AreaMark + LineMark pattern exactly:

```swift
// NetWorthTrendChart.swift — minimal structure
struct NetWorthTrendChart: View {
    let snapshots: [NetWorthSnapshot]  // passed from parent @Query

    var body: some View {
        Chart(snapshots) { snap in
            AreaMark(
                x: .value("Date", snap.date),
                y: .value("Net Worth", NSDecimalNumber(decimal: snap.totalNetWorth).doubleValue)
            )
            .foregroundStyle(Color.accentColor.opacity(0.15))
            LineMark(
                x: .value("Date", snap.date),
                y: .value("Net Worth", NSDecimalNumber(decimal: snap.totalNetWorth).doubleValue)
            )
            .foregroundStyle(Color.accentColor)
            .lineStyle(StrokeStyle(lineWidth: 2))
        }
        .chartYAxis { /* compact INR labels */ }
        .frame(height: 140)
    }
}
```

**Critical pattern:** Aggregate/convert to `Double` OUTSIDE the `Chart {}` DSL or at the `value:` call site. Never pass `Decimal` directly to `.value(...)` — Swift Charts only accepts `Plottable` types; `Decimal` is not `Plottable`. [VERIFIED: SpendOverTimeChart.swift Pitfall A/B guard comments]

---

## Accounts CRUD Mirror Pattern

**AssetsListView pattern** (mirrors `AccountsListView.swift` [VERIFIED]):

| AccountsListView | AssetsListView |
|-----------------|----------------|
| `@Query(sort: \Account.sortOrder) var allAccounts` | `@Query(sort: \Asset.createdAt, order: .reverse) var allAssets` |
| Active/Archived split | Active only (assets are not archived; delete is the action) |
| `AccountBalance.compute()` for balance display | `units × currentNAV` for current value display |
| `EditAccountView` sheet | `EditAssetView` sheet |
| NavigationLink → AccountDetailView | NavigationLink → AssetDetailView (or inline expansion) |
| `context.delete(account); try context.save()` | Same pattern |
| `ContentUnavailableView` when empty | Same pattern |

**SettingsView wiring:** Add a `NavigationLink(destination: AssetsListView())` row in the "Data" section of `SettingsView.swift`, adjacent to the existing "Accounts" row. No new state required — plain NavigationLink.

---

## Architecture Patterns

### Pattern 1: @MainActor @Observable Service (AMFINavService)

**What:** A `@MainActor @Observable final class` with an injected `modelContext: ModelContext?`, a synchronous IST-gated entry point, and async URLSession work wrapped in `Task {}`.
**When to use:** Any service that runs on app activation and touches SwiftData.
**Template:**

```swift
// [VERIFIED: mirrors RoutineResetService.swift and TransferScanService.swift]
@MainActor
@Observable
final class AMFINavService {
    var modelContext: ModelContext?
    private var cachedSchemes: [String: AMFIScheme] = [:]  // keyed by scheme code

    func refreshIfNeeded() {
        guard let context = modelContext else { return }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Kolkata")!
        let startOfTodayIST = cal.startOfDay(for: Date())
        let lastFetch = UserDefaults.standard.object(forKey: "amfiNavLastFetchDate") as? Date ?? .distantPast
        guard lastFetch < startOfTodayIST else { return }
        Task { await performFetch(context: context, todayIST: startOfTodayIST) }
    }

    private func performFetch(context: ModelContext, todayIST: Date) async {
        // URLSession.shared.data(from:) — no await boundary issues since context is MainActor
        // Parse NAVAll.txt, update Asset.currentNAV + navAsOfDate for matching amfiSchemeCode
        // Update cachedSchemes for picker
        // On success: UserDefaults "amfiNavLastFetchDate" = todayIST
        // On failure: log + return (D-07: silent failure)
    }
}
```

### Pattern 2: Snapshot Upsert (NetWorthSnapshotService)

**What:** Fetch-or-create a `NetWorthSnapshot` row for today's IST date; overwrite totals if exists.
**Key insight:** There is no `.unique` (CloudKit rule) — upsert is implemented via fetch-filter-or-create, same as the existing idempotency pattern in `v5ToV6.didMigrate`.

```swift
// Upsert pattern — no @Attribute(.unique) available (CloudKit rule)
func upsertIfNeeded() {
    guard let context = modelContext else { return }
    // IST start-of-today as the upsert key
    let todayIST = istStartOfDay(Date())
    Task {
        let existing = try? context.fetch(FetchDescriptor<NetWorthSnapshot>(
            predicate: #Predicate { $0.date >= todayIST }
        ))
        let snapshot = existing?.first ?? {
            let s = NetWorthSnapshot(); context.insert(s); return s
        }()
        snapshot.date = todayIST
        snapshot.totalNetWorth = computeTotal(context: context)
        snapshot.mfValue = computeMF(context: context)
        // ...etc
        try? context.save()
    }
}
```

### Anti-Patterns to Avoid

- **Passing Decimal to Swift Charts `.value()`:** `Decimal` is not `Plottable`. Always convert to `Double` at the aggregation boundary before entering `Chart {}`. See `SpendOverTimeChart` Pitfall B guard.
- **Storing enum on @Model:** Use `String` raw values (`assetClassRaw: String?`). `SchemaV6.Asset.assetClassRaw` is already `String?` — do not add a Swift enum stored property. [VERIFIED: SchemaV6.swift comment "rule 8"]
- **@Attribute(.unique) on NetWorthSnapshot.date:** CloudKit does not support uniqueness constraints (rule 2). Implement upsert via fetch-before-insert.
- **await inside didMigrate:** The `didMigrate` closure is synchronous (throws, NOT async throws). Never use `await` inside it. [VERIFIED: MigrationPlan.swift comment line 58]
- **Forgetting to flip ALL typealiases at once:** Partial typealias flip (e.g., only `Asset.swift` but not `Account.swift`) causes the STAB-08 crash — SwiftData saves/queries using the wrong schema version for the unfliped models. One commit, all files.
- **Negative Decimal in SectorMark:** `DonutSegment.value` is `Double`; a negative value causes a runtime crash in Swift Charts. Clamp `max(cashValue, 0)` when building the cash segment. Display the true (possibly negative) total separately as a Text label.
- **String.components(separatedBy:) on large strings:** For ~1.6 MB, `components(separatedBy: "\n")` allocates the full array at once. Acceptable for a background Task; don't do it on the main thread synchronously.
- **Name-matching NAVs at fetch time:** Store `amfiSchemeCode` on `Asset` (D-01) and use exact-code matching. Name matching is fragile — fund names have extra spaces, abbreviations change.

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Allocation donut chart | Custom SVG/Canvas ring | `DonutChart.swift` (existing, `SectorMark`) | Already polished, accessible, consistent |
| Net-worth trend area chart | Custom CoreGraphics drawing | `SpendOverTimeChart` pattern (Swift Charts `AreaMark`+`LineMark`) | Consistent with existing charts; correct Decimal→Double boundary handling |
| IST daily gate | Custom date comparison | `RoutineResetService.resetIfNeeded()` pattern (Calendar IST, `startOfDay`) | Established pattern; handles DST correctly |
| Account balance aggregation | Re-implementing balance formula | `AccountBalance.compute()` in `AccountBalance.swift` | Sign convention is non-obvious (POSITIVE spends, baseline-net formula); re-implementing risks sign error |
| Scheme-code lookup | Name fuzzy matching | Store `amfiSchemeCode` → exact dict lookup | Name matching fails on whitespace variants; code is canonical |

---

## Common Pitfalls

### Pitfall 1: Partial Typealias Flip (STAB-08)
**What goes wrong:** App crashes on save or query of any @Model type whose typealias still points to SchemaV6 while the container uses SchemaV7.
**Why it happens:** Each @Model typealias must match the active schema version. A mismatch causes SwiftData to generate the wrong persistent model descriptor.
**How to avoid:** Flip ALL seven typealiases (Expense, Category, Note, NoteBlock, Account, Asset, NetWorthSnapshot) + `ModelContainer+App.swift` in a single atomic commit. Use git to verify all files changed together.
**Warning signs:** Crash in `PersistentModel.setValue(forKey:)` or `FetchDescriptor` immediately after schema bump.

### Pitfall 2: Decimal Passed to Swift Charts
**What goes wrong:** Runtime crash or silent incorrect chart because `Decimal` is not a `Plottable` type.
**Why it happens:** Swift Charts `.value("label", someDecimal)` does not compile or silently truncates.
**How to avoid:** Convert to `Double` at the aggregation boundary: `NSDecimalNumber(decimal: d).doubleValue`. See `SpendOverTimeChart`'s "Pitfall B guard" comment. Never let a raw `Decimal` enter the `Chart {}` DSL.
**Warning signs:** Compiler error "type 'Decimal' does not conform to 'Plottable'" or chart renders as flat line.

### Pitfall 3: Negative SectorMark Value
**What goes wrong:** Swift Charts crashes at runtime if any `SectorMark` angle value is zero or negative.
**Why it happens:** The "cash" slice value = net account balances, which can be negative when CC debt exceeds savings.
**How to avoid:** Clamp: `let cashSliceValue = max(cashNetBalance, Decimal(0))`. Display the true total as a separate `Text` label outside the chart.
**Warning signs:** App crash in `Charts.SectorMark` when user has large CC balance.

### Pitfall 4: Section Headers in NAVAll.txt Treated as Data Rows
**What goes wrong:** Parser throws on `parts[5]` (index out of bounds) or emits a garbage `AMFIScheme` record.
**Why it happens:** Section-header lines (e.g., `Open Ended Schemes(Debt Scheme - Banking and PSU Fund)`) contain no semicolons. Splitting on `;` yields a single-element array.
**How to avoid:** Guard: `guard trimmed.contains(";") else { continue }` before splitting.
**Warning signs:** Parse produces far fewer records than expected (~1,000 instead of ~13,000+), or `parts.count < 6` guard fires frequently.

### Pitfall 5: amfiNavLastFetchDate UserDefaults Type Mismatch
**What goes wrong:** `UserDefaults.standard.object(forKey:) as? Date` returns nil because the value was stored as a different type on a prior app version.
**Why it happens:** `UserDefaults.set(_:forKey:)` with a `Date` stores as `Date` natively. But if a developer stores a String representation instead, the cast fails silently and fetches run every session.
**How to avoid:** Use `UserDefaults.standard.set(date, forKey:)` where `date: Date` — not a string serialization. Read back as `as? Date`. Consistent across all call sites.
**Warning signs:** NAV refresh fires on every `scenePhase .active` rather than once per day.

### Pitfall 6: Missing `try context.save()` in AMFINavService
**What goes wrong:** NAV updates are written to @Model objects in memory but never persisted. App closes, stale NAVs shown on next launch.
**Why it happens:** SwiftData does NOT auto-commit. Every mutation session requires explicit `try context.save()`. [VERIFIED: MigrationPlan.swift "Pitfall 3" comment; AccountsListView `try? context.save()` at every mutation site]
**How to avoid:** End every mutation batch with `try context.save()` (or `try? context.save()` for non-fatal paths). Match the codebase pattern.
**Warning signs:** NAVs appear updated in-session but revert on app relaunch.

### Pitfall 7: @Attribute(.unique) on NetWorthSnapshot.date
**What goes wrong:** CloudKit migration fails at runtime when CloudKit sync is enabled (v2.0).
**Why it happens:** CloudKit does not support `@Attribute(.unique)`. Using it on `snapshot.date` as a dedup key breaks the CloudKit-readiness contract.
**How to avoid:** Implement snapshot dedup via fetch-before-insert (upsert pattern). `NetWorthSnapshotService.upsertIfNeeded()` fetches `snapshots where date >= startOfTodayIST`, updates if found, inserts if not.
**Warning signs:** CloudKit sync errors in future; or `Schema` initialization crash if `.unique` is added.

---

## Runtime State Inventory

This is a greenfield phase for the Asset Tracker UI (SchemaV7 is additive). The `Asset` @Model has existed since Phase 9 but with no user data (no UI shipped). `NetWorthSnapshot` is a new entity.

| Category | Items Found | Action Required |
|----------|-------------|-----------------|
| Stored data | `Asset` rows: zero — SchemaV6.Asset scaffold had no CRUD UI; no user data exists yet | No migration/backfill needed for Asset rows |
| Stored data | `NetWorthSnapshot` rows: zero — new entity in V7 | No migration/backfill needed |
| Live service config | None — no external service config for AMFI (free public URL, no API key) | None |
| OS-registered state | None | None |
| Secrets/env vars | None — AMFI fetch requires no auth token | None |
| Build artifacts | `Asset.swift` typealias points to `SchemaV6.Asset` — must flip to `SchemaV7.Asset` in migration commit | Code change (typealias flip + schema bump, same commit) |

---

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| Xcode 26.5 | Build | ✓ | 26.5 (memory) | — |
| iOS 17+ simulator (iPhone 17) | Run | ✓ | (memory) | — |
| Swift Charts | Donut + trend chart | ✓ | iOS 16+ built-in | — |
| SwiftData | Schema V7 + @Query | ✓ | iOS 17+ built-in | — |
| URLSession | AMFI NAV fetch | ✓ | Foundation built-in | — |
| portal.amfiindia.com/spages/NAVAll.txt | MF NAV auto-fetch | ✓ (verified live 2026-06-11) | — | Manual override always available (D-07) |
| Network access (simulator) | AMFI fetch smoke test | ✓ | — | — |

**Missing dependencies with no fallback:** None.

**Missing dependencies with fallback:** AMFI endpoint unavailable (offline) → silent failure + cached NAV + staleness badge (D-07).

---

## Validation Architecture

### Test Framework

| Property | Value |
|----------|-------|
| Framework | Swift Testing (`import Testing`) |
| Config file | Xcode target `MyHomeTests` — existing |
| Quick run command | `xcodebuild test -scheme MyHome -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:MyHomeTests/<TestSuite>` |
| Full suite command | `xcodebuild test -scheme MyHome -destination 'platform=iOS Simulator,name=iPhone 17'` |

### Phase Requirements → Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| ASSET-01 | Holdings CRUD: insert/update/delete Asset in SwiftData | unit | `MyHomeTests/AssetCRUDTests` | ❌ Wave 0 |
| ASSET-02 | currentValue = units × currentNAV (Decimal math) | unit | `MyHomeTests/AssetValueTests` | ❌ Wave 0 |
| ASSET-03 | AMFINavService: parse NAVAll.txt → correct AMFIScheme records; updates Asset.currentNAV | unit | `MyHomeTests/AMFINavServiceTests` | ❌ Wave 0 |
| ASSET-04 | Manual NAV entry preserved (no auto-overwrite for stocks/NPS) | unit | `MyHomeTests/AssetCRUDTests` | ❌ Wave 0 |
| ASSET-05 | Net worth = holdings + account balances (sign convention) | unit | `MyHomeTests/NetWorthAggregationTests` | ❌ Wave 0 |
| ASSET-06 | Gain/loss absolute + %; zero-cost-basis returns nil % | unit | `MyHomeTests/AssetGainLossTests` | ❌ Wave 0 |
| ASSET-07 | DonutChart receives correct 4-segment values; cash clamped ≥ 0 | unit | `MyHomeTests/AllocationSegmentTests` | ❌ Wave 0 |
| ASSET-08 | Snapshot upsert: one record per day; second call same day overwrites | unit | `MyHomeTests/NetWorthSnapshotTests` | ❌ Wave 0 |
| ASSET-09 | Staleness: navAsOfDate yesterday → stale; today → fresh | unit | `MyHomeTests/StalenessBadgeTests` | ❌ Wave 0 |
| SchemaV7 migration | V6→V7: amfiSchemeCode nil on existing Assets; NetWorthSnapshot table created | integration | `MyHomeTests/SchemaV7MigrationTests` | ❌ Wave 0 |

### Sampling Rate

- **Per task commit:** Run the specific test suite for that task's component (e.g., `AMFINavServiceTests` after AMFINavService implementation).
- **Per wave merge:** Full `xcodebuild test` suite.
- **Phase gate:** Full suite green before `/gsd-verify-work`.

### Wave 0 Gaps

- [ ] `MyHomeTests/SchemaV7MigrationTests.swift` — V6→V7 migration fixture test (BLOCKING for Wave 1, mirrors `SchemaV6MigrationTests.swift`)
- [ ] `MyHomeTests/AMFINavServiceTests.swift` — parse, daily gate, silent-failure behavior
- [ ] `MyHomeTests/AssetCRUDTests.swift` — CRUD, currentValue derivation, manual NAV
- [ ] `MyHomeTests/NetWorthAggregationTests.swift` — total formula, sign convention with CC balances
- [ ] `MyHomeTests/AssetGainLossTests.swift` — gain/loss math, zero-basis edge case
- [ ] `MyHomeTests/AllocationSegmentTests.swift` — donut segment values, negative cash clamp
- [ ] `MyHomeTests/NetWorthSnapshotTests.swift` — daily upsert, no duplicates
- [ ] `MyHomeTests/StalenessBadgeTests.swift` — calendar-day threshold, IST boundary

---

## Security Domain

`security_enforcement: true`, ASVS Level 1.

### Applicable ASVS Categories

| ASVS Category | Applies | Standard Control |
|---------------|---------|-----------------|
| V2 Authentication | No | No new auth surface |
| V3 Session Management | No | No new session surface |
| V4 Access Control | No | Local-only app; no multi-user |
| V5 Input Validation | Yes | Decimal field bounds: `abs(units) < 1_000_000` guard; `abs(costBasis) < 1_000_000_000` guard (mirrors T-09-05 for accounts) |
| V6 Cryptography | No | No new crypto |
| V9 Communication | Yes | AMFI fetch is HTTPS (`https://portal.amfiindia.com`) — no plain HTTP |

### Known Threat Patterns

| Pattern | STRIDE | Standard Mitigation |
|---------|--------|---------------------|
| Unreasonably large units/cost entry (e.g., `1e18` Decimal) | Tampering | `abs(units) < 1_000_000` + `abs(costBasisPerUnit) < 1_000_000_000` guards in `EditAssetView.saveAsset()` — mirrors T-09-05 |
| HTTPS downgrade on AMFI fetch | Spoofing | Use `https://portal.amfiindia.com/spages/NAVAll.txt`; App Transport Security (ATS) blocks HTTP by default on iOS |
| Malformed NAVAll.txt (e.g. extra semicolons in scheme name, NaN NAV) | Tampering | Parser guards: `parts.count >= 6`, `Decimal(string:)` returns nil on non-numeric → skip row; never `fatalError` |
| Negative SectorMark crash via crafted asset data | Denial of Service | Clamp: `max(cashValue, 0)` before building donut segments |
| XSS via scheme name rendered as AttributedString | Tampering | Render scheme names as plain `Text(scheme.name)` — never `Text(AttributedString(markdown:))` (mirrors T-09-06) |

---

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| AMFI NAV fetch via unofficial scraping or paid API | `NAVAll.txt` free public endpoint | AMFI standardized | No cost, no ToS risk, reliable |
| Custom hand-rolled donut (SVG/Canvas) | Swift Charts `SectorMark` | iOS 16 / v1.0 | Consistent with existing Overview charts |
| `.lightweight` SchemaMigrationPlan | `.custom(willMigrate:didMigrate:)` with nil closures | FB13812722 workaround (iOS 17.0–17.3) | All migration stages use `.custom` in this codebase |

**Deprecated/outdated:**
- `.lightweight` migration stage: never use — FB13812722 workaround requires `.custom` for all stages in this project.
- `Double` for money: never use — project-wide `Decimal` rule (Pitfall 17).
- `@Attribute(.unique)`: never use on any @Model — breaks CloudKit-readiness (rule 2).

---

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | `NetWorthSnapshot` fields `mfValue/stockValue/npsValue/cashValue` are the right sub-total granularity for D-09 | SchemaV7 section | If planner wants a different field shape (e.g. a serialized JSON blob), the @Model design changes — but CloudKit-readiness rules still apply |
| A2 | AMFI file size (~1.6 MB) makes in-memory parsing acceptable in a background Task | AMFI section | If file grows significantly, a streaming line-by-line parser would be safer — but unlikely in the near term |
| A3 | `portal.amfiindia.com` redirect is stable (amfiindia.com 302 → portal.amfiindia.com) | AMFI section | If AMFI changes canonical URL, the fetch fails silently (D-07 safe); URL should be a named constant |

---

## Open Questions (RESOLVED)

1. **`NetWorthSnapshot` sub-total field shape**
   - What we know: D-09 requires total + per-class breakdown.
   - What's unclear: Whether `mfValue/stockValue/npsValue/cashValue` as separate `Decimal` fields is the right shape vs. a Codable value type serialized to `Data?` (like `reminderRecurrenceData`).
   - Recommendation: Use separate `Decimal` fields — simpler to query and display; CloudKit supports multiple Decimal fields. Codable blob adds indirection with no benefit for 4 sub-totals.

2. **Multiple holdings of the same AMFI fund**
   - What we know: A user might hold the same MF scheme in multiple folios (growth vs IDCW).
   - What's unclear: Should Holdings list show them as separate rows (different units/cost) or merge?
   - Recommendation: Separate rows (each `Asset` is a distinct holding with its own units and cost basis). The AMFI scheme code just governs NAV lookup — multiple Assets can share the same `amfiSchemeCode`.

3. **Picker search ranking when AMFINavService hasn't fetched yet**
   - What we know: D-02 says "cache the parsed list; picker needs at least one successful fetch to populate."
   - What's unclear: What to show in the picker before the first fetch.
   - Recommendation: Show `ContentUnavailableView("No schemes loaded", ...)` with a "Fetch now" button that triggers `AMFINavService.refreshIfNeeded()` immediately (ignoring the daily gate). After fetch completes, picker populates.

---

## Sources

### Primary (HIGH confidence — verified via direct read)

- `SchemaV6.swift` lines 247–266 — `Asset` @Model scaffold (field names, types, constraints)
- `MigrationPlan.swift` — `.custom` stage pattern, `didMigrate` synchronous constraint, FB13812722 rationale, V6 idempotency patterns
- `AccountBalance.swift` — sign convention (spends POSITIVE, balance = baseline − net), `compute()` signature
- `RootView.swift` lines 115–126 — `scenePhase .active` `.onChange` hook; service injection in `.onAppear`
- `RoutineResetService.swift` — IST daily gate pattern (Calendar IST, `startOfDay`, UserDefaults date compare)
- `TransferScanService.swift` — `@MainActor @Observable` service pattern with injected `modelContext`
- `DonutChart.swift` — `DonutSegment`, `SectorMark`, center overlay signature
- `SpendOverTimeChart.swift` — `AreaMark`+`LineMark` pattern, Pitfall A/B (aggregate outside Chart DSL, Double boundary)
- `AccountsListView.swift` — CRUD list pattern under Settings, balance row, archive/delete
- `EditAccountView.swift` — sheet pattern (nil = create, non-nil = edit), validation guards, save idiom
- `OverviewView.swift` — card structure, `LazyVStack` + `ScrollView`, `sectionHeader`, `cardStyle()`
- `ModelContainer+App.swift` — `Schema(versionedSchema: SchemaV6.self)`, store URL pattern
- `Asset.swift` (typealias) — STAB-08 note confirmed in file comments
- `https://portal.amfiindia.com/spages/NAVAll.txt` — file format verified live 2026-06-11 (Content-Length: 1641244, delimiter: `;`, 6 columns, date format `DD-MMM-YYYY`)

### Secondary (MEDIUM confidence — planning docs)

- `.planning/phases/11-asset-tracker/11-CONTEXT.md` — all decisions D-01 through D-11
- `.planning/REQUIREMENTS.md` — ASSET-01 through ASSET-09 requirement text
- `.planning/ROADMAP.md` — Phase 11 success criteria

---

## Metadata

**Confidence breakdown:**

- AMFI NAVAll.txt format: HIGH — verified via live fetch; headers, delimiters, date format confirmed
- SchemaV7 migration mechanics: HIGH — verified against SchemaV6 + MigrationPlan patterns; additive with no didMigrate
- Service patterns (AMFINavService, SnapshotService): HIGH — verified against RoutineResetService + TransferScanService
- UI reuse (DonutChart, SpendOverTimeChart, AccountsListView): HIGH — all source files read directly
- Net-worth formula / sign convention: HIGH — verified in AccountBalance.swift with Phase 10 fix note
- Swift Charts Decimal/Double boundary: HIGH — Pitfall B guard present and explained in existing code

**Research date:** 2026-06-11
**Valid until:** 2026-07-11 (AMFI URL stable; SwiftData APIs stable on iOS 17+; Swift Charts stable)
