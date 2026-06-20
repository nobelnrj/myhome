# Phase 11: Asset Tracker - Pattern Map

**Mapped:** 2026-06-11
**Files analyzed:** 14 new/modified files
**Analogs found:** 13 / 14

---

## File Classification

| New/Modified File | Role | Data Flow | Closest Analog | Match Quality |
|---|---|---|---|---|
| `Persistence/Schema/SchemaV7.swift` | model/migration | CRUD | `Persistence/Schema/SchemaV6.swift` | exact |
| `Persistence/Models/NetWorthSnapshot.swift` | model | CRUD | `Persistence/Models/Account.swift` | exact |
| `Persistence/Models/Asset.swift` (typealias flip) | model | CRUD | `Persistence/Models/Account.swift` | exact |
| `Persistence/MigrationPlan.swift` (append v6→v7) | config | CRUD | existing `MigrationPlan.swift` | exact |
| `Persistence/ModelContainer+App.swift` (V7 bump) | config | CRUD | existing `ModelContainer+App.swift` | exact |
| `Support/AMFINavService.swift` | service | request-response | `Features/Notes/RoutineResetService.swift` + `Features/Gmail/TransferScanService.swift` | role-match |
| `Support/NetWorthSnapshotService.swift` | service | CRUD | `Features/Notes/RoutineResetService.swift` | role-match |
| `Features/Assets/AssetsListView.swift` | component | CRUD | `Features/Settings/AccountsListView.swift` | exact |
| `Features/Assets/EditAssetView.swift` | component | CRUD | `Features/Settings/EditAccountView.swift` | exact |
| `Features/Assets/AssetDetailView.swift` | component | request-response | `Features/Settings/AccountDetailView.swift` | exact |
| `Features/Assets/AMFISchemePickerView.swift` | component | request-response | `Features/Settings/AccountsListView.swift` (List + searchable) | role-match |
| `Features/Assets/NetWorthCard.swift` | component | request-response | `Features/Overview/OverviewView.swift` + `Features/Shared/DonutChart.swift` | role-match |
| `Features/Assets/NetWorthTrendChart.swift` | component | request-response | `Features/Overview/SpendOverTimeChart.swift` | exact |
| `Features/Assets/StalenessView.swift` | component | transform | no close analog | no-analog |
| `Features/Overview/OverviewView.swift` (modify) | component | request-response | existing `OverviewView.swift` | exact |
| `Features/Settings/SettingsView.swift` (modify) | config | request-response | existing `SettingsView.swift` | exact |
| `RootView.swift` (modify — wire new services) | config | event-driven | existing `RootView.swift` | exact |

---

## Pattern Assignments

### `Persistence/Schema/SchemaV7.swift` (model, CRUD)

**Analog:** `Persistence/Schema/SchemaV6.swift` (lines 247–266 for the Asset scaffold)

**Migration-version declaration pattern** (SchemaV6.swift lines 1–10):
```swift
import SwiftData

enum SchemaV7: VersionedSchema {
    static var versionIdentifier: Schema.Version { .init(7, 0, 0) }
    static var models: [any PersistentModel.Type] {
        // All V6 models PLUS NetWorthSnapshot — never remove or reorder
        [SchemaV7.Expense.self, SchemaV7.Category.self,
         SchemaV7.Note.self, SchemaV7.NoteBlock.self,
         SchemaV7.Account.self, SchemaV7.Asset.self,
         SchemaV7.NetWorthSnapshot.self]
    }
}
```

**Asset @Model — copy V6 verbatim and append amfiSchemeCode** (SchemaV6.swift lines 249–265):
```swift
@Model
final class Asset {
    // No @Attribute(.unique) — CloudKit does not support unique constraints (rule 2).
    var id: UUID = UUID()
    var name: String? = nil
    var assetClassRaw: String? = nil        // "mutual_fund" | "stock" | "nps" (rule 8)
    var units: Decimal? = nil               // Decimal not Double (rule 3)
    var costBasisPerUnit: Decimal? = nil    // Decimal (rule 3)
    var currentNAV: Decimal? = nil          // Decimal (rule 3)
    var navAsOfDate: Date? = nil            // UTC (rule 4)
    var createdAt: Date = Date()            // UTC (rule 4)
    // NEW in SchemaV7 — additive, defaults nil (D-01)
    var amfiSchemeCode: String? = nil

    init() {
        self.id = UUID()
        self.createdAt = Date()
    }
}
```

**NetWorthSnapshot @Model — new entity pattern** (no direct analog; follows CloudKit rules from SchemaV6):
```swift
@Model
final class NetWorthSnapshot {
    // No @Attribute(.unique) — CloudKit rule 2 (D-08 upsert via fetch-before-insert instead)
    var id: UUID = UUID()
    var date: Date = Date()                 // UTC; upsert key = startOfTodayIST
    var totalNetWorth: Decimal = Decimal(0) // Decimal (rule 3); never Double
    var mfValue: Decimal = Decimal(0)       // D-09: per-class sub-totals
    var stockValue: Decimal = Decimal(0)
    var npsValue: Decimal = Decimal(0)
    var cashValue: Decimal = Decimal(0)     // net of all account balances
    var createdAt: Date = Date()

    init() {
        self.id = UUID()
        self.createdAt = Date()
    }
}
```

---

### `Persistence/Models/NetWorthSnapshot.swift` (model, CRUD)

**Analog:** `Persistence/Models/Account.swift`

**Typealias pattern** (Account.swift lines 1–16):
```swift
import SwiftData

/// Convenience typealias so views and tests use bare `NetWorthSnapshot` without version prefix.
///
/// New in Phase 11 (SchemaV7). STAB-08: flip ALL typealiases together in the same commit
/// that appends SchemaV7.self to AppMigrationPlan.schemas. See Account.swift full rationale.
typealias NetWorthSnapshot = SchemaV7.NetWorthSnapshot
```

---

### `Persistence/Models/Asset.swift` (typealias flip)

**Analog:** `Persistence/Models/Account.swift`

**Change:** Single line flip from `SchemaV6.Asset` to `SchemaV7.Asset`. Must happen in the SAME commit as all other typealias flips (STAB-08 rule — see Account.swift lines 9–11 for rationale). Also flip: Account, Expense, Category, Note, NoteBlock.

---

### `Persistence/MigrationPlan.swift` (append v6→v7 stage)

**Analog:** existing `MigrationPlan.swift`

**schemas/stages array append pattern** (MigrationPlan.swift lines 10–16):
```swift
static var schemas: [any VersionedSchema.Type] {
    [SchemaV1.self, SchemaV2.self, SchemaV3.self, SchemaV4.self, SchemaV5.self, SchemaV6.self, SchemaV7.self]
}

static var stages: [MigrationStage] {
    [v1ToV2, v2ToV3, v3ToV4, v4ToV5, v5ToV6, v6ToV7]
}
```

**New additive stage — nil closures, no backfill needed** (MigrationPlan.swift lines 29–35 as template):
```swift
// V7 adds amfiSchemeCode (nil default) and NetWorthSnapshot (new entity).
// Purely additive — willMigrate/didMigrate are nil. No backfill needed.
// FB13812722: .custom over .lightweight is mandatory for ALL stages in this codebase.
static let v6ToV7 = MigrationStage.custom(
    fromVersion: SchemaV6.self,
    toVersion: SchemaV7.self,
    willMigrate: nil,
    didMigrate: nil   // amfiSchemeCode defaults nil; NetWorthSnapshot is new — no backfill
)
```

---

### `Persistence/ModelContainer+App.swift` (V7 bump)

**Analog:** existing `ModelContainer+App.swift`

**Schema version bump** (ModelContainer+App.swift lines 18, 42):
```swift
// Old:
let schema = Schema(versionedSchema: SchemaV6.self)
// New:
let schema = Schema(versionedSchema: SchemaV7.self)

// Old:
let container = try ModelContainer(
    for: schema,
    migrationPlan: AppMigrationPlan.self,
    configurations: [config]
)
// No other changes — store URL, App Group fallback, and seeding call are unchanged.
```

---

### `Support/AMFINavService.swift` (service, request-response)

**Primary analog:** `Features/Notes/RoutineResetService.swift` (lines 18–58) for class shape + IST gate
**Secondary analog:** `Features/Gmail/TransferScanService.swift` (lines 27–59) for modelContext injection pattern

**Class declaration + injection pattern** (RoutineResetService.swift lines 18–24 / TransferScanService.swift lines 27–32):
```swift
import Foundation
import SwiftData

@MainActor
@Observable
final class AMFINavService {
    var modelContext: ModelContext?                          // injected by RootView.onAppear
    private(set) var cachedSchemes: [String: AMFIScheme] = [:]
    var isFetching: Bool = false
}
```

**IST daily gate pattern** (RoutineResetService.swift lines 26–30):
```swift
func refreshIfNeeded() {
    guard let context = modelContext else { return }
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = TimeZone(identifier: "Asia/Kolkata")!
    let startOfTodayIST = cal.startOfDay(for: Date())
    let lastFetch = UserDefaults.standard.object(forKey: "amfiNavLastFetchDate") as? Date ?? .distantPast
    guard lastFetch < startOfTodayIST else { return }   // already fetched today — no-op
    isFetching = true
    Task { await performFetch(context: context, todayIST: startOfTodayIST) }
}

/// Bypasses the daily gate — for pull-to-refresh and "Fetch Now" in AMFISchemePickerView.
func forceRefresh() {
    guard let context = modelContext else { return }
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = TimeZone(identifier: "Asia/Kolkata")!
    isFetching = true
    Task { await performFetch(context: context, todayIST: cal.startOfDay(for: Date())) }
}
```

**Async fetch + silent-failure pattern** (TransferScanService.swift lines 49–59 for error handling idiom):
```swift
private func performFetch(context: ModelContext, todayIST: Date) async {
    defer { isFetching = false }
    guard let url = URL(string: "https://portal.amfiindia.com/spages/NAVAll.txt") else { return }
    do {
        let (data, _) = try await URLSession.shared.data(from: url)
        guard let text = String(data: data, encoding: .utf8) else { return }
        let schemes = parseNAVAll(text)                           // returns [AMFIScheme]
        cachedSchemes = Dictionary(uniqueKeysWithValues: schemes.map { ($0.code, $0) })
        // Update Asset.currentNAV / navAsOfDate for matching amfiSchemeCode
        let assets = try context.fetch(FetchDescriptor<Asset>())
        var didChange = false
        for asset in assets {
            guard let code = asset.amfiSchemeCode,
                  let scheme = cachedSchemes[code] else { continue }
            asset.currentNAV = scheme.nav
            asset.navAsOfDate = scheme.navDate
            didChange = true
        }
        if didChange { try context.save() }   // CR-01: explicit save
        UserDefaults.standard.set(todayIST, forKey: "amfiNavLastFetchDate")
    } catch {
        // D-07: fail silently — keep cached NAV; staleness badge handles UX
        print("[AMFINavService] fetch failed: \(error)")
    }
}
```

**NAVAll.txt date formatter — IST, POSIX locale:**
```swift
private let navDateFormatter: DateFormatter = {
    let f = DateFormatter()
    f.dateFormat = "dd-MMM-yyyy"
    f.locale = Locale(identifier: "en_US_POSIX")
    f.timeZone = TimeZone(identifier: "Asia/Kolkata")!
    return f
}()
```

**Parser — section-header skip guard:**
```swift
func parseNAVAll(_ text: String) -> [AMFIScheme] {
    var results: [AMFIScheme] = []
    let lines = text.components(separatedBy: "\n")
    for line in lines.dropFirst() {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.contains(";") else { continue }   // section header — skip
        let parts = trimmed.components(separatedBy: ";")
        guard parts.count >= 6 else { continue }
        let code    = parts[0].trimmingCharacters(in: .whitespaces)
        let name    = parts[3].trimmingCharacters(in: .whitespaces)
        let navStr  = parts[4].trimmingCharacters(in: .whitespaces)
        let dateStr = parts[5].trimmingCharacters(in: .whitespaces)
        guard let nav  = Decimal(string: navStr),        // Decimal — never Double (rule 3)
              let date = navDateFormatter.date(from: dateStr) else { continue }
        results.append(AMFIScheme(code: code, name: name, nav: nav, navDate: date))
    }
    return results
}
```

---

### `Support/NetWorthSnapshotService.swift` (service, CRUD)

**Analog:** `Features/Notes/RoutineResetService.swift` (lines 18–58)

**Class shape** — identical to RoutineResetService:
```swift
@MainActor
@Observable
final class NetWorthSnapshotService {
    var modelContext: ModelContext?
}
```

**Upsert pattern — no @Attribute(.unique) (CloudKit rule 2):**
```swift
func upsertIfNeeded() {
    guard let context = modelContext else { return }
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = TimeZone(identifier: "Asia/Kolkata")!
    let todayIST = cal.startOfDay(for: Date())

    Task {
        do {
            // Fetch-before-insert idempotency (mirrors v5ToV6.didMigrate lines 76–80)
            let existing = try context.fetch(FetchDescriptor<NetWorthSnapshot>(
                predicate: #Predicate { $0.date >= todayIST }
            ))
            let snapshot: NetWorthSnapshot
            if let found = existing.first {
                snapshot = found
            } else {
                snapshot = NetWorthSnapshot()
                context.insert(snapshot)
            }
            snapshot.date = todayIST
            // Compute totals — see net-worth aggregation pattern below
            // snapshot.totalNetWorth = ...
            // snapshot.mfValue = ...
            // etc.
            try context.save()   // CR-01: explicit save
        } catch {
            print("[NetWorthSnapshotService] upsert failed: \(error)")
        }
    }
}
```

**Net-worth aggregation (AccountBalance.swift compute() signature):**
```swift
// AccountBalance.swift lines 28–43 — AccountBalance.compute() signature:
static func compute(
    baseline: Decimal?,
    asOf: Date?,
    expenses: [Expense],
    accountID: UUID
) -> Decimal

// Usage inside NetWorthSnapshotService:
let assets = try context.fetch(FetchDescriptor<Asset>())
let accounts = try context.fetch(FetchDescriptor<Account>())
let allExpenses = try context.fetch(FetchDescriptor<Expense>())

let mfValue = assets.filter { $0.assetClassRaw == "mutual_fund" }
    .reduce(Decimal(0)) { sum, a in
        guard let u = a.units, let n = a.currentNAV else { return sum }
        return sum + u * n
    }
// same for stockValue, npsValue

let cashValue = accounts
    .filter { !($0.isArchived) }
    .reduce(Decimal(0)) { sum, account in
        sum + AccountBalance.compute(
            baseline: account.balanceBaseline,
            asOf: account.balanceAsOfDate,
            expenses: allExpenses,
            accountID: account.id
        )
    }
snapshot.totalNetWorth = mfValue + stockValue + npsValue + cashValue
snapshot.cashValue = cashValue   // may be negative — stored as-is (D-09 sign convention)
```

---

### `Features/Assets/AssetsListView.swift` (component, CRUD)

**Analog:** `Features/Settings/AccountsListView.swift` (lines 1–242)

**Imports + @Query + @Environment pattern** (AccountsListView.swift lines 1–22):
```swift
import SwiftUI
import SwiftData

struct AssetsListView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Asset.createdAt, order: .reverse) private var allAssets: [Asset]

    @State private var showAddSheet = false
    @State private var assetToDelete: Asset? = nil
    @State private var showDeleteConfirmation = false
}
```

**Empty state pattern** (AccountsListView.swift lines 47–53):
```swift
Group {
    if allAssets.isEmpty {
        ContentUnavailableView(
            "No Holdings Yet",
            systemImage: "chart.bar",
            description: Text("Tap + to add your first holding.")
        )
    } else {
        List { ... }
            .listStyle(.insetGrouped)
    }
}
```

**Holding row** (mirrors accountRow, AccountsListView.swift lines 181–211):
```swift
private func holdingRow(_ asset: Asset) -> some View {
    let currentValue: Decimal? = {
        guard let u = asset.units, let n = asset.currentNAV else { return nil }
        return u * n
    }()
    return HStack(spacing: 16) {
        IconTile(symbol: assetSymbol(asset.assetClassRaw),
                 color: assetColor(asset.assetClassRaw),
                 size: 30)
        VStack(alignment: .leading, spacing: 0) {
            Text(asset.name ?? "—").font(.body).foregroundStyle(.primary).lineLimit(1)
            Text(assetClassLabel(asset.assetClassRaw)).font(.subheadline).foregroundStyle(.secondary)
        }
        Spacer(minLength: 8)
        if let val = currentValue {
            Text(val.formattedINRWhole()).font(.body)
        } else {
            Text("—").font(.body).foregroundStyle(.secondary)
        }
    }
    .frame(minHeight: 44)
}
```

**Swipe-delete + confirmationDialog pattern** (AccountsListView.swift lines 86–97, 164–175):
```swift
.swipeActions(edge: .trailing) {
    Button(role: .destructive) {
        assetToDelete = asset
        showDeleteConfirmation = true
    } label: {
        Label("Delete", systemImage: "trash")
    }
}
// ...
.confirmationDialog("Delete Holding?", isPresented: $showDeleteConfirmation, titleVisibility: .visible) {
    Button("Delete Holding", role: .destructive) {
        if let a = assetToDelete { deleteAsset(a) }
    }
    Button("Cancel", role: .cancel) {}
} message: {
    Text("This holding will be permanently removed. This cannot be undone.")
}
```

**Delete action** (AccountsListView.swift lines 234–241):
```swift
private func deleteAsset(_ asset: Asset) {
    context.delete(asset)
    do {
        try context.save()   // CR-01: explicit save
    } catch {
        assertionFailure("Failed to delete asset: \(error)")
    }
}
```

**Pull-to-refresh** (new in AssetsListView — not in AccountsListView):
```swift
.refreshable {
    amfiNavService.forceRefresh()   // bypasses daily gate (D-06)
}
```

**Toolbar + sheet** (AccountsListView.swift lines 145–157):
```swift
.navigationBarTitleDisplayMode(.inline)
.toolbar {
    ToolbarItem(placement: .primaryAction) {
        Button { showAddSheet = true } label: { Image(systemName: "plus") }
            .accessibilityLabel("Add Holding")
    }
}
.sheet(isPresented: $showAddSheet) {
    EditAssetView(asset: nil)
}
```

---

### `Features/Assets/EditAssetView.swift` (component, CRUD)

**Analog:** `Features/Settings/EditAccountView.swift` (lines 1–280)

**Sheet structure** (EditAccountView.swift lines 13–16, 68–70):
```swift
struct EditAssetView: View {
    var asset: Asset?   // nil = create, non-nil = edit

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    // Form state
    @State private var name: String = ""
    @State private var assetClassRaw: String = "mutual_fund"
    @State private var units: Decimal = 0
    @State private var costBasisPerUnit: Decimal = 0
    @State private var currentNAV: Decimal = 0
    @State private var navAsOfDate: Date = Date()
    @State private var amfiSchemeCode: String? = nil
    @State private var nameError: String? = nil

    var body: some View {
        NavigationStack {
            Form { ... }
            .navigationTitle(asset == nil ? "New Holding" : "Edit Holding")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
```

**Validation pattern** (EditAccountView.swift lines 36–39):
```swift
private var isValid: Bool {
    !name.trimmingCharacters(in: .whitespaces).isEmpty
    && units > 0
    && abs(units) < 1_000_000          // T-09-05 mirrors
    && abs(costBasisPerUnit) < 1_000_000_000
}
```

**Inline field error pattern** (EditAccountView.swift lines 96–105):
```swift
VStack(alignment: .leading, spacing: 4) {
    TextField("Holding name", text: $name)
        .font(.body)
        .frame(minHeight: 44)
    if let error = nameError {
        Text(error)
            .font(.subheadline)
            .foregroundStyle(Color(.systemRed))
    }
}
```

**Segmented Picker for type** (EditAccountView.swift lines 115–122):
```swift
Section("Asset Class") {
    Picker("Asset Class", selection: $assetClassRaw) {
        Text("Mutual Fund").tag("mutual_fund")
        Text("Stock").tag("stock")
        Text("NPS").tag("nps")
    }
    .pickerStyle(.segmented)
}
```

**DatePicker for as-of date** (EditAccountView.swift lines 138–140):
```swift
DatePicker("As of", selection: $navAsOfDate, displayedComponents: [.date])
    .font(.body)
```

**Toolbar cancel/save** (EditAccountView.swift lines 200–210):
```swift
ToolbarItem(placement: .cancellationAction) {
    Button("Cancel") { dismiss() }
}
ToolbarItem(placement: .confirmationAction) {
    Button("Save Holding") { saveAsset() }
        .disabled(!isValid)
        .tint(.accentColor)
}
```

**onAppear pre-populate for edit mode** (EditAccountView.swift lines 212–222):
```swift
.onAppear {
    if let a = asset {
        name = a.name ?? ""
        assetClassRaw = a.assetClassRaw ?? "mutual_fund"
        units = a.units ?? 0
        costBasisPerUnit = a.costBasisPerUnit ?? 0
        currentNAV = a.currentNAV ?? 0
        navAsOfDate = a.navAsOfDate ?? Date()
        amfiSchemeCode = a.amfiSchemeCode
    }
}
```

**Save function pattern** (EditAccountView.swift lines 228–278):
```swift
private func saveAsset() {
    let trimmed = name.trimmingCharacters(in: .whitespaces)
    guard !trimmed.isEmpty else { nameError = "Holding name cannot be empty."; return }
    guard abs(units) < 1_000_000 else { nameError = "Units must be less than 10,00,000."; return }
    guard abs(costBasisPerUnit) < 1_000_000_000 else { nameError = "Cost basis too large."; return }

    do {
        let target: Asset
        if let existing = asset {
            target = existing
        } else {
            target = Asset()
            context.insert(target)
        }
        target.name = trimmed
        target.assetClassRaw = assetClassRaw
        target.units = units
        target.costBasisPerUnit = costBasisPerUnit
        target.currentNAV = currentNAV
        target.navAsOfDate = navAsOfDate
        target.amfiSchemeCode = assetClassRaw == "mutual_fund" ? amfiSchemeCode : nil
        try context.save()   // CR-01: explicit save
        nameError = nil
        dismiss()
    } catch {
        assertionFailure("Failed to save asset: \(error)")
    }
}
```

---

### `Features/Assets/AssetDetailView.swift` (component, request-response)

**Analog:** `Features/Settings/AccountDetailView.swift` (lines 1–80)

**Header card / detail list pattern** (AccountDetailView.swift lines 12–80):
```swift
struct AssetDetailView: View {
    var asset: Asset
    @State private var showEditSheet = false

    private var currentValue: Decimal? {
        guard let u = asset.units, let n = asset.currentNAV else { return nil }
        return u * n
    }

    private var totalCost: Decimal {
        (asset.units ?? 0) * (asset.costBasisPerUnit ?? 0)
    }

    private var absoluteGain: Decimal { (currentValue ?? 0) - totalCost }

    private var percentGain: Decimal? {
        guard totalCost > 0 else { return nil }
        return (absoluteGain / totalCost) * 100
    }
}
```

**Balance hero → current-value hero** (AccountDetailView.swift balanceCard pattern):
```swift
// Header card: mirrors balanceCard in AccountDetailView
VStack(alignment: .leading, spacing: 4) {
    Text(assetClassLabel(asset.assetClassRaw))
        .font(.subheadline).foregroundStyle(.secondary)
    if let val = currentValue {
        Text(val.formattedINRWhole())
            .font(.largeTitle.weight(.semibold))
    } else {
        Text("—").font(.largeTitle.weight(.semibold)).foregroundStyle(.secondary)
    }
    Text(asset.name ?? "—").font(.body).foregroundStyle(.secondary)
    // StalenessView + as-of date inline
}
.padding(16)
.background(Color(.secondarySystemBackground))
.clipShape(RoundedRectangle(cornerRadius: 16))
```

**Toolbar Edit button** (AccountDetailView.swift):
```swift
.toolbar {
    ToolbarItem(placement: .primaryAction) {
        Button("Edit") { showEditSheet = true }
    }
}
.sheet(isPresented: $showEditSheet) {
    EditAssetView(asset: asset)
}
```

---

### `Features/Assets/AMFISchemePickerView.swift` (component, request-response)

**Analog:** `Features/Settings/AccountsListView.swift` for List + navigationBarTitleDisplayMode(.inline) + ForEach pattern. No exact analog for searchable + multi-state.

**Core searchable list pattern** (AccountsListView.swift lines 54, 131–132 for list/listStyle):
```swift
struct AMFISchemePickerView: View {
    @Binding var selectedSchemeCode: String?
    let amfiNavService: AMFINavService   // passed from EditAssetView

    @State private var query: String = ""

    private var filteredSchemes: [AMFIScheme] {
        guard !query.isEmpty else { return amfiNavService.schemeList }
        return amfiNavService.schemeList.filter {
            $0.name.localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        Group {
            if amfiNavService.isFetching {
                ProgressView("Loading schemes…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if amfiNavService.schemeList.isEmpty {
                ContentUnavailableView(
                    "No Schemes Loaded",
                    systemImage: "arrow.down.circle",
                    description: Text("Scheme data hasn't been fetched yet.")
                )
                // "Fetch Now" button below ContentUnavailableView
            } else {
                List(filteredSchemes) { scheme in
                    Button { selectedSchemeCode = scheme.code; dismiss() } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(scheme.name).font(.body).lineLimit(2)
                                Text(scheme.code).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if selectedSchemeCode == scheme.code {
                                Image(systemName: "checkmark").foregroundStyle(.accentColor)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(selectedSchemeCode == scheme.code
                        ? Color.accentColor.opacity(0.12) : Color.clear)
                }
                .listStyle(.insetGrouped)
                .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always))
            }
        }
        .navigationTitle("Choose Scheme")
        .navigationBarTitleDisplayMode(.inline)
    }
}
```

---

### `Features/Assets/NetWorthCard.swift` (component, request-response)

**Analog:** `Features/Overview/OverviewView.swift` (sectionHeader + cardStyle patterns) + `Features/Shared/DonutChart.swift`

**DonutChart drop-in** (DonutChart.swift lines 4–47):
```swift
DonutChart(
    segments: [
        DonutSegment(id: "mf",    label: "Mutual Funds",
                     value: Double(truncating: max(mfValue, 0) as NSDecimalNumber),
                     color: Color(.systemBlue)),
        DonutSegment(id: "stock", label: "Stocks",
                     value: Double(truncating: max(stockValue, 0) as NSDecimalNumber),
                     color: Color(.systemGreen)),
        DonutSegment(id: "nps",   label: "NPS",
                     value: Double(truncating: max(npsValue, 0) as NSDecimalNumber),
                     color: Color(.systemOrange)),
        DonutSegment(id: "cash",  label: "Cash",
                     value: Double(truncating: max(cashValue, 0) as NSDecimalNumber), // CLAMP — never negative
                     color: Color(.systemTeal)),
    ],
    size: 132
) {
    VStack(spacing: 0) {
        Text("NET WORTH").font(.caption2).foregroundStyle(.secondary)
        Text(totalNetWorth.formattedINRWhole()).font(.headline).lineLimit(1).minimumScaleFactor(0.6)
    }
}
```

**Decimal-to-Double conversion** — use `NSDecimalNumber`:
```swift
Double(truncating: someDecimal as NSDecimalNumber)
// Same pattern as OverviewView.double(_:) — never cast directly
```

**Card container** (OverviewView sectionHeader + cardStyle pattern):
```swift
// Section header: mirrors OverviewView private func sectionHeader(_:action:)
// Card body: .padding(18).background(Color(.secondarySystemBackground)).clipShape(RoundedRectangle(cornerRadius: 16))
// Suppress when no data: if allAssets.isEmpty && cashValue == 0 { EmptyView() }
```

---

### `Features/Assets/NetWorthTrendChart.swift` (component, request-response)

**Analog:** `Features/Overview/SpendOverTimeChart.swift` (lines 1–155) — exact

**Core chart structure** (SpendOverTimeChart.swift lines 75–119):
```swift
import SwiftUI
import Charts

struct NetWorthTrendChart: View {
    let snapshots: [NetWorthSnapshot]   // passed from parent @Query

    var body: some View {
        // Pitfall A: convert OUTSIDE Chart DSL (SpendOverTimeChart.swift line 47)
        // Pitfall B: Decimal is not Plottable — convert to Double at boundary
        if snapshots.isEmpty {
            Text("No history yet.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .center)
                .frame(height: 80)
        } else {
            Chart(snapshots) { snap in
                AreaMark(
                    x: .value("Date", snap.date),
                    y: .value("Net Worth", Double(truncating: snap.totalNetWorth as NSDecimalNumber))
                )
                .foregroundStyle(Color.accentColor.opacity(0.15))

                LineMark(
                    x: .value("Date", snap.date),
                    y: .value("Net Worth", Double(truncating: snap.totalNetWorth as NSDecimalNumber))
                )
                .foregroundStyle(Color.accentColor)
                .lineStyle(StrokeStyle(lineWidth: 2))
            }
            .chartYAxis {
                AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let d = value.as(Double.self) {
                            Text(Decimal(d).formattedINRCompact()).font(.caption)
                        }
                    }
                }
            }
            .chartXAxis {
                AxisMarks(values: .automatic) { value in
                    AxisGridLine()
                    AxisValueLabel(format: .dateTime.month(.abbreviated)).font(.caption)
                }
            }
            .frame(height: 140)
            .accessibilityLabel("Net worth trend chart")
        }
    }
}
```

---

### `Features/Assets/StalenessView.swift` (component, transform)

**No close analog in codebase.** First staleness badge component. Pattern reference from UI-SPEC:

```swift
import SwiftUI

struct StalenessView: View {
    let navAsOfDate: Date?

    private var isStale: Bool {
        guard let date = navAsOfDate else { return false }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Kolkata")!
        let startOfTodayIST = cal.startOfDay(for: Date())
        let diff = cal.dateComponents([.day], from: date, to: startOfTodayIST).day ?? 0
        return diff > 1   // D-10: calendar-day threshold; ignores weekends/holidays (harmless)
    }

    var body: some View {
        if isStale {
            HStack(spacing: 3) {
                Image(systemName: "clock.badge.exclamationmark")
                Text("Stale")
            }
            .font(.caption)
            .foregroundStyle(Color(.systemOrange))
            .accessibilityLabel("Price is stale. Last updated \(formattedDate).")
        }
        // Fresh state: EmptyView (hidden)
    }

    private var formattedDate: String {
        navAsOfDate?.formatted(.dateTime.day().month(.abbreviated).year()) ?? "unknown"
    }
}
```

---

### `Features/Overview/OverviewView.swift` (modify — add NetWorthCard)

**Analog:** existing `Features/Overview/OverviewView.swift`

**Insert NetWorthCard after spend hero card** in `OverviewMonthContent` body. Follow the existing sectionHeader pattern:
```swift
// In OverviewMonthContent body — existing sectionHeader pattern:
sectionHeader("Net Worth", action: ("See holdings", { showAssetsView = true }))
    .padding(.bottom, -8)   // -8pt tighten as per spacing table

// Conditional rendering — suppress entirely when no assets and cash == 0 (UI-SPEC):
if !allAssets.isEmpty || cashValue != 0 {
    NetWorthCard(allAssets: allAssets, allAccounts: allAccounts, allExpenses: allExpenses,
                 snapshots: netWorthSnapshots)
        .padding(.horizontal, 16)
}
```

**@Query additions in OverviewMonthContent:**
```swift
@Query(sort: \Asset.createdAt, order: .reverse) private var allAssets: [Asset]
@Query(sort: \NetWorthSnapshot.date, order: .reverse) private var netWorthSnapshots: [NetWorthSnapshot]
@Query private var allAccounts: [Account]
```

---

### `Features/Settings/SettingsView.swift` (modify — add Assets row)

**Analog:** existing `Features/Settings/SettingsView.swift` (lines 186–200)

**Insert Assets NavigationLink adjacent to Accounts row** (SettingsView.swift line 187):
```swift
// After the Accounts NavigationLink:
NavigationLink(destination: AssetsListView()) {
    rowLabel("Assets", symbol: "chart.bar", color: Color(.systemPurple))
}
.foregroundStyle(.primary)
```

---

### `RootView.swift` (modify — wire AMFINavService + NetWorthSnapshotService)

**Analog:** existing `RootView.swift` (lines 41–44 for @State service pattern, lines 115–126 for scenePhase .active hook)

**@State service declarations** (mirrors RootView.swift lines 41–44):
```swift
@State private var amfiNavService = AMFINavService()
@State private var netWorthSnapshotService = NetWorthSnapshotService()
```

**modelContext injection in .onAppear** (mirrors existing routineResetService.modelContext pattern):
```swift
// In RootView .onAppear block — alongside existing injections:
amfiNavService.modelContext = modelContext
netWorthSnapshotService.modelContext = modelContext
```

**scenePhase .active hook additions** (RootView.swift lines 115–126):
```swift
.onChange(of: scenePhase) { _, newPhase in
    lockController.scenePhaseChanged(newPhase)
    gmailSyncController.scenePhaseChanged(newPhase)
    if newPhase == .active {
        routineResetService.resetIfNeeded()
        amfiNavService.refreshIfNeeded()          // NEW: daily AMFI NAV refresh (D-06)
        netWorthSnapshotService.upsertIfNeeded()  // NEW: daily snapshot upsert (D-08)
    }
    // existing lock auth block unchanged
}
```

---

## Shared Patterns

### @MainActor @Observable Service Pattern
**Source:** `Features/Notes/RoutineResetService.swift` lines 18–58
**Apply to:** `AMFINavService.swift`, `NetWorthSnapshotService.swift`
```swift
@MainActor
@Observable
final class <ServiceName> {
    var modelContext: ModelContext?   // injected by RootView.onAppear

    func <entryPoint>() {
        guard let context = modelContext else { return }
        // synchronous IST gate → Task { await performWork(context:) }
    }
}
```

### IST Daily Gate
**Source:** `Features/Notes/RoutineResetService.swift` lines 27–30
**Apply to:** `AMFINavService.refreshIfNeeded()`, `NetWorthSnapshotService.upsertIfNeeded()`
```swift
var cal = Calendar(identifier: .gregorian)
cal.timeZone = TimeZone(identifier: "Asia/Kolkata")!
let startOfTodayIST = cal.startOfDay(for: Date())
```

### Error Handling (Non-Fatal Service Errors)
**Source:** `Features/Notes/RoutineResetService.swift` lines 53–57
**Apply to:** All service classes
```swift
} catch {
    print("[ServiceName] failed: \(error)")
    // Never fatalError or crash on scene activation
}
```

### Explicit Save (CR-01)
**Source:** `Features/Settings/AccountsListView.swift` line 97 / `Features/Settings/EditAccountView.swift` line 273
**Apply to:** Every SwiftData mutation site
```swift
try context.save()   // CR-01: SwiftData does NOT auto-commit
// or try? context.save() for non-fatal mutation paths
```

### Decimal Money Rule (Rule 3)
**Source:** codebase-wide; `AccountBalance.swift` line 38 / `SchemaV6.swift` line 255
**Apply to:** All new @Model fields and all aggregation computations
```swift
// Always: Decimal not Double for money
// Convert to Double only at Swift Charts .value() boundary:
Double(truncating: someDecimal as NSDecimalNumber)
```

### CloudKit-Readiness Rules
**Source:** `SchemaV6.swift` inline comments / `MigrationPlan.swift` FB13812722 comment
**Apply to:** All new @Model properties in SchemaV7
- No `@Attribute(.unique)` on any property
- Every property has a default value or is optional
- No Swift enum stored properties — use `String` raw values
- Use `Decimal` (not `Double`) for money fields

### Plain Text Security Rule
**Source:** `AccountsListView.swift` line 195, `AccountDetailView.swift` line 8
**Apply to:** All views displaying asset names or scheme names
```swift
Text(asset.name ?? "—")   // T-09-06: plain Text() — never Text(AttributedString(markdown:))
```

---

## No Analog Found

| File | Role | Data Flow | Reason |
|------|------|-----------|--------|
| `Features/Assets/StalenessView.swift` | component | transform | No staleness/badge component exists anywhere in the codebase; first of its kind |

---

## Metadata

**Analog search scope:** `MyHomeApp/Persistence/`, `MyHomeApp/Features/Settings/`, `MyHomeApp/Features/Overview/`, `MyHomeApp/Features/Shared/`, `MyHomeApp/Support/`, `MyHomeApp/Features/Notes/`, `MyHomeApp/Features/Gmail/`
**Files read:** 15 source files
**Pattern extraction date:** 2026-06-11
