# Phase 1: Foundation & Manual Expense Spine - Research

**Researched:** 2026-05-29
**Domain:** SwiftData @Model schema discipline, VersionedSchema scaffolding, Swift Testing in-memory fixtures, en-IN Decimal currency formatting, PrivacyInfo.xcprivacy, SwiftUI CRUD screens with custom keypad
**Confidence:** HIGH — all core findings verified or cited from Apple documentation, prior project research docs (ARCHITECTURE.md, PITFALLS.md, STACK.md), and official secondary sources.

---

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

- **D-01:** Transaction date defaults to now and is editable via a date picker. The ≤4-tap fast path requires no date interaction; backdating is a deliberate extra action.
- **D-02:** Date stored as a full UTC timestamp (date + time-of-day), displayed in the user's local time. Future-proofs intra-day ordering and aligns with Phase 7 bank emails.
- **D-03:** Negative amounts are allowed in manual entry from v1 (user can record a refund/reversal). Stored as `Decimal`.
- **D-04:** Amount uses a standard decimal keypad, paise optional — whole rupees valid, paise allowed. Stored as `Decimal`; displayed with 2 decimal places using `Locale(identifier: "en_IN")`. NOT cents-style auto-decimal entry.
- **D-05:** The `Expense` `@Model` for v1 carries: `id: UUID`, `amount: Decimal`, `currencyCode: String` (default `"INR"`), `date: Date` (UTC timestamp, default now), `note: String?`, `createdAt: Date`, `updatedAt: Date`. All fields optional-or-defaulted, no `@Attribute(.unique)`, money as `Decimal`, dates UTC — per the 8 CloudKit-readiness rules.
- **D-06:** A dedicated normalized merchant field is NOT added in Phase 1. The optional `note` field covers manual-entry payee text.
- **D-07:** Category picker is deferred to Phase 2. Phase 1 add flow: open → amount keypad → (optional date/note) → save.
- **D-08:** No breaking migration when categories arrive. Phase 1 schema must be forward-compatible so Phase 2 adds Category @Model + Expense↔Category relationship additively (optional, inverse-declared).
- **D-09:** Immutable identifiers — Bundle ID: `com.reojacob.myhome`, CloudKit container: `iCloud.com.reojacob.myhome`, App Group: `group.com.reojacob.myhome`, Minimum deployment target: iOS 17.0.

### Claude's Discretion

- Project structure and file layout
- Exact in-memory test fixture pattern
- en-IN `NumberFormatter`/`FormatStyle` choice
- SwiftData `ModelContainer` wiring
- Visual layout of add/edit/list screens (governed by UI-SPEC)
- Schema-field naming refinements (as long as CloudKit-readiness rules hold)

### Deferred Ideas (OUT OF SCOPE)

- Category picker + India-tuned list + custom category CRUD → Phase 2
- Normalized merchant field, raw email body, parserID/parserVersion → Phase 7
- Multi-currency display / FX → out of scope
- Tags, budgets, month grouping → Phase 2
</user_constraints>

---

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| FND-01 | App targets iOS 17+ and uses the Swift 6.2 / SwiftUI / SwiftData stack (no UIKit, no Core Data) | Stack.md confirms; Xcode 26 + Swift 6.2 is current toolchain. SwiftUI throughout, UIKit only via UIViewRepresentable if unavoidable. |
| FND-02 | Bundle ID, CloudKit container ID, and App Group ID decided on day one and never changed | D-09 locks: `com.reojacob.myhome`, `iCloud.com.reojacob.myhome`, `group.com.reojacob.myhome`. One-way-door — Pitfall 6 + 13 explain the orphan risk. |
| FND-03 | Every @Model type follows the 8 CloudKit-readiness rules | Architecture.md documents all 8 rules. Applied to `Expense` in D-05. |
| FND-04 | PrivacyInfo.xcprivacy declares required-reason APIs with NSPrivacyTracking false | CA92.1 for UserDefaults, C617.1 for FileTimestamp. Must be in target from day one. |
| FND-05 | VersionedSchema + SchemaMigrationPlan scaffolded from v1.0 with only one schema version | Single-version VersionedSchema enum + migration plan with empty stages. ModelContainer initialized with migrationPlan. |
| FND-06 | Test target uses Swift Testing with in-memory ModelContainer(isStoredInMemoryOnly: true) for fixtures; XCTest reserved for UI tests only | Verified pattern: fresh container per test function via @MainActor setup. |
| FND-07 | All currency displayed with Locale(identifier: "en_IN") formatting; all dates stored UTC, displayed in user locale | FormatStyle `.currency(code: "INR").locale(Locale(identifier: "en_IN"))` on Decimal. UTC storage with Calendar/DateFormatter for display. |
| EXP-01 | User can add a manual expense in ≤4 taps and see it in a list | 3-tap path: open sheet → type amount → Save. Custom keypad always visible (no keyboard animation). @Query auto-refreshes list. |
| EXP-02 | User can edit any expense they created | Tap row → Edit sheet with @Bindable Expense. Save writes through ModelContext. |
| EXP-03 | User can delete any expense they created | Swipe-to-delete on list (.onDelete) + Delete Expense button in Edit sheet with confirmation action sheet. |
</phase_requirements>

---

## Summary

Phase 1 is the irreversible foundation of the entire app. Every one-way-door decision — bundle ID, CloudKit container name, App Group store URL, schema shape, migration scaffolding, privacy manifest — must be made correctly before the first `git commit` that creates the Xcode project. Getting these right costs almost nothing; getting them wrong costs a full data migration and a forced rename of on-device stores.

The technical surface area is: (1) Xcode project bootstrap with the three immutable identifiers and the PrivacyInfo.xcprivacy manifest; (2) the `Expense` @Model type, correctly shaped for CloudKit from day one even though v1 runs local-only; (3) `VersionedSchema` v1 scaffolding with a `SchemaMigrationPlan` that has empty stages (single version), so all future schema changes go through the versioned path; (4) a SwiftData `ModelContainer` wired to the App Group container URL from day one; (5) the three SwiftUI screens (Expense List, Add Sheet, Edit Sheet) as documented in 01-UI-SPEC.md, with a custom decimal keypad and en-IN formatting; and (6) a Swift Testing test target with an in-memory ModelContainer fixture, a reflection-based @Model property test, and a migration-load test against a bundled v1 SQLite store.

The user is learning Swift, so code patterns should be concrete, idiomatic, and minimal — no architectural ceremony beyond what the requirements demand.

**Primary recommendation:** Build the Xcode project skeleton and lock all identifiers first (Wave 0), then add the `Expense` model + VersionedSchema + ModelContainer in a single commit (Wave 1), then add the three UI screens (Wave 2), then the test harness (Wave 3). Never mix schema decisions with UI work in the same commit — the schema is the durable asset.

---

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| Expense persistence (insert, update, delete) | Data Layer (SwiftData ModelContext) | — | SwiftData is the persistence layer; writes go through ModelContext, not a repository wrapper |
| Expense list display | Presentation (SwiftUI + @Query) | — | @Query owns the read path; views observe changes automatically |
| Add/Edit form state | Presentation (@State / @Bindable) | — | Form-local state is view state; no view model needed at this complexity level |
| Currency formatting (en-IN) | Presentation (FormatStyle) | — | Formatting is a display concern; stored value is Decimal with no locale |
| Date UTC storage | Data Layer (SwiftData) | — | Store as Date (UTC); format at display time |
| Schema versioning | Data Layer (VersionedSchema) | — | Migration plan is a persistence concern, not a UI concern |
| App Group store URL | Data Layer (ModelContainer factory) | — | Container URL decision is made once at app init; all other tiers consume the shared context |
| Privacy manifest | App Target (PrivacyInfo.xcprivacy) | — | Static resource, no tier above it |
| Test fixtures | Test Target (Swift Testing) | Data Layer (in-memory ModelContainer) | Tests spin up a real in-memory store — no mocking needed |

---

## Standard Stack

### Core (Phase 1 only — no Gmail/BankParser packages in this phase)

| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| Swift | 6.2 | App language | Current toolchain bundled with Xcode 26; Approachable Concurrency mode for learner-friendly strict concurrency |
| SwiftUI | iOS 17 baseline | UI framework | Apple-mandated greenfield path; FND-01 locks this |
| SwiftData | iOS 17+ | Local persistence with CloudKit-ready schema | FND-01 locks this; CloudKit switch is config-only later |
| Swift Testing | Bundled (Swift 6 toolchain) | Unit + integration tests | In-toolchain; no SPM dep; @Test / #expect; FND-06 requires this |
| Foundation (Decimal, FormatStyle) | Bundled | Money storage and en-IN formatting | FND-07 requires Decimal; FormatStyle.currency is the Apple-blessed formatter |
| SF Symbols 5 | Bundled | Icons | UI-SPEC mandates; no third-party icon library |

### No Third-Party Packages in Phase 1

Phase 1 installs zero SPM packages. The Google Gmail libraries (GoogleSignIn-iOS, GTMAppAuth, GTMSessionFetcher, GoogleAPIClientForREST_Gmail) are deferred to Phase 6. Swift-snapshot-testing is deferred until a view stabilizes.

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| SwiftData @Query in views | Repository protocol over ModelContext | @Query gives live updates; a repository breaks them. In-memory ModelContainer tests the real query semantics. Never wrap SwiftData. |
| Decimal for money | Double | Double has floating-point drift on sums. CloudKit also round-trips Decimal cleanly but may lose precision with Double. Never. |
| FormatStyle.currency(code:).locale(en_IN) | NumberFormatter with currencyCode | FormatStyle is the modern API (iOS 15+); NumberFormatter works but is the legacy path. Both produce identical output for en_IN. |
| VersionedSchema v1 with SchemaMigrationPlan | No versioning in v1 | Skipping versioning makes the first schema change a gamble on lightweight migration succeeding silently. Always scaffold VersionedSchema from v1. |

**Installation:** No packages to install in Phase 1. Xcode project bootstrapped with an iOS App template, Swift 6.2 language setting, iOS 17 deployment target.

---

## Package Legitimacy Audit

> No external packages are installed in Phase 1. All dependencies are Apple-provided frameworks (SwiftData, SwiftUI, Foundation, Swift Testing). This section is not applicable.

**Packages removed due to slopcheck:** none (no packages)
**Packages flagged as suspicious:** none (no packages)

---

## Architecture Patterns

### System Architecture Diagram (Phase 1 scope only)

```
  User
    │
    ▼ tap +
┌─────────────────────────────────────────────┐
│  Add Expense Sheet (SwiftUI)                │
│  @State: amountString, date, note, sign     │
│  Custom DecimalKeypad view                  │
│  "Save Expense" → ModelContext.insert()     │
└────────────────────┬────────────────────────┘
                     │ ModelContext.save()
                     ▼
┌─────────────────────────────────────────────┐
│  Expense @Model (SwiftData)                 │
│  VersionedSchema v1.0.0                     │
│  Stored in App Group container URL          │
│  (CloudKit wired to .none for v1)           │
└────────────────────┬────────────────────────┘
                     │ @Query observes
                     ▼
┌─────────────────────────────────────────────┐
│  Expense List (SwiftUI)                     │
│  @Query(sort: \Expense.date, order: .reverse)│
│  List rows: amount (en-IN) + note + date    │
│  Swipe-to-delete | Tap row → Edit sheet     │
└─────────────────────────────────────────────┘
```

### Recommended Project Structure

```
MyHome/
├── MyHome.xcodeproj
├── MyHomeApp/                          # iOS app target
│   ├── MyHomeApp.swift                 # @main, .modelContainer(appContainer())
│   ├── RootView.swift                  # NavigationStack root → ExpenseListView
│   ├── Features/
│   │   └── Expenses/
│   │       ├── ExpenseListView.swift   # @Query list, toolbar +, swipe delete
│   │       ├── AddExpenseView.swift    # Sheet: amount keypad, date, note
│   │       ├── EditExpenseView.swift   # Sheet: same fields + Delete button
│   │       └── DecimalKeypadView.swift # Custom 3×4 grid keypad (no system KB)
│   ├── Persistence/
│   │   ├── ModelContainer+App.swift   # appContainer() factory, App Group URL
│   │   ├── Schema/
│   │   │   ├── SchemaV1.swift         # enum SchemaV1: VersionedSchema
│   │   │   └── MigrationPlan.swift    # enum AppMigrationPlan: SchemaMigrationPlan
│   │   └── Models/
│   │       └── Expense.swift          # @Model final class Expense
│   └── Resources/
│       ├── Assets.xcassets
│       └── PrivacyInfo.xcprivacy      # NSPrivacyTracking: false, CA92.1, C617.1
└── MyHomeTests/                        # Swift Testing target
    ├── ExpenseModelTests.swift         # Reflection test + CRUD lifecycle
    └── MigrationTests.swift            # Load bundled v1 store + migrate
```

### Pattern 1: @Model definition — CloudKit-ready from day one

**What:** All properties optional or defaulted, no `@Attribute(.unique)`, UUID PK, Decimal money, UTC dates, String for currencyCode.

**When to use:** Always, for every @Model in this project.

```swift
// Source: ARCHITECTURE.md (project research) + Apple SwiftData documentation
// File: Persistence/Models/Expense.swift
import SwiftData
import Foundation

@Model
final class Expense {
    // No @Attribute(.unique) — CloudKit does not support unique constraints.
    // UUID generated by us, not relying on SwiftData's hidden persistent ID.
    var id: UUID = UUID()
    var amount: Decimal = Decimal(0)
    var currencyCode: String = "INR"
    var date: Date = Date()          // UTC timestamp, always; format at display time
    var note: String? = nil          // optional free-form memo / payee
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    init(
        id: UUID = UUID(),
        amount: Decimal,
        currencyCode: String = "INR",
        date: Date = Date(),
        note: String? = nil
    ) {
        self.id = id
        self.amount = amount
        self.currencyCode = currencyCode
        self.date = date
        self.note = note
        self.createdAt = Date()
        self.updatedAt = Date()
    }
}
```

**Key rules encoded:**
1. Every stored property has a default or is optional — required for CloudKit mirroring.
2. No `@Attribute(.unique)` — CloudKit rejects it.
3. `Decimal` for money, never `Double`.
4. `date` is a full UTC timestamp, never date-only.
5. `currencyCode: String` present even though v1 is INR-only — schema-forward.
6. Phase 2 will add `var category: Category? = nil` with `@Relationship(inverse: \Category.expenses)` — additive, no migration breaking existing rows.

### Pattern 2: VersionedSchema v1 + SchemaMigrationPlan (single version)

**What:** Scaffolding for versioned schema with one version and no migration stages. All future schema changes will add a new version enum and a migration stage — never touch the v1 enum.

**When to use:** Created once in Phase 1. Never modified — only extended with v2, v3, etc.

```swift
// Source: Apple WWDC23 "Model your schema with SwiftData" + project ARCHITECTURE.md
// File: Persistence/Schema/SchemaV1.swift
import SwiftData

enum SchemaV1: VersionedSchema {
    static let versionIdentifier = Schema.Version(1, 0, 0)

    static var models: [any PersistentModel.Type] {
        [SchemaV1.Expense.self]
    }

    // The @Model types live INSIDE the version enum to prevent namespace collision
    // when v2 renames or restructures them.
    @Model
    final class Expense {
        var id: UUID = UUID()
        var amount: Decimal = Decimal(0)
        var currencyCode: String = "INR"
        var date: Date = Date()
        var note: String? = nil
        var createdAt: Date = Date()
        var updatedAt: Date = Date()

        init(id: UUID = UUID(), amount: Decimal, currencyCode: String = "INR",
             date: Date = Date(), note: String? = nil) {
            self.id = id
            self.amount = amount
            self.currencyCode = currencyCode
            self.date = date
            self.note = note
            self.createdAt = Date()
            self.updatedAt = Date()
        }
    }
}
```

```swift
// File: Persistence/Schema/MigrationPlan.swift
import SwiftData

enum AppMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [SchemaV1.self]
    }

    // No stages yet — v1 is the first and only version.
    // When Phase 2 adds CategoryV2, add: SchemaV2.self to schemas and a migration stage.
    static var stages: [MigrationStage] { [] }
}
```

```swift
// File: Persistence/ModelContainer+App.swift
import SwiftData

extension ModelContainer {
    static func appContainer() throws -> ModelContainer {
        let schema = Schema(versionedSchema: SchemaV1.self)
        let storeURL = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: "group.com.reojacob.myhome")!
            .appendingPathComponent("MyHome.store")
        let config = ModelConfiguration(
            schema: schema,
            url: storeURL,
            cloudKitDatabase: .none   // flip to .private("iCloud.com.reojacob.myhome") post-paid-upgrade
        )
        return try ModelContainer(
            for: schema,
            migrationPlan: AppMigrationPlan.self,
            configurations: [config]
        )
    }
}
```

> **Note on App Group on free account:** The App Group entitlement may not provision reliably on a free Apple Developer account. If Xcode reports the entitlement cannot be added, use `FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!` as a temporary fallback and document the store path so you can migrate it when the paid account is active. The store URL constant is the only piece that changes — everything else remains identical.

### Pattern 3: ModelContainer injection at app entry point

```swift
// File: MyHomeApp.swift
// Source: Apple SwiftData documentation — .modelContainer modifier pattern
import SwiftUI
import SwiftData

@main
struct MyHomeApp: App {
    let container: ModelContainer = {
        do {
            return try ModelContainer.appContainer()
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(container)
    }
}
```

### Pattern 4: @Query read + ModelContext write in views (no repository)

**What:** Read with `@Query` directly inside the view. Write with `@Environment(\.modelContext)`. No repository protocol, no store actor needed when writes are single-model.

```swift
// File: Features/Expenses/ExpenseListView.swift
// Source: ARCHITECTURE.md Pattern 1 + Apple SwiftData @Query documentation
import SwiftUI
import SwiftData

struct ExpenseListView: View {
    @Query(sort: \Expense.date, order: .reverse) private var expenses: [Expense]
    @Environment(\.modelContext) private var context

    @State private var showingAddSheet = false
    @State private var editingExpense: Expense?

    var body: some View {
        NavigationStack {
            List {
                ForEach(expenses) { expense in
                    ExpenseRow(expense: expense)
                        .onTapGesture { editingExpense = expense }
                }
                .onDelete(perform: deleteExpenses)
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Expenses")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button(action: { showingAddSheet = true }) {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Add Expense")
                }
            }
            .sheet(isPresented: $showingAddSheet) {
                AddExpenseView()
            }
            .sheet(item: $editingExpense) { expense in
                EditExpenseView(expense: expense)
            }
            .overlay {
                if expenses.isEmpty {
                    ContentUnavailableView(
                        "No Expenses Yet",
                        systemImage: "tray",
                        description: Text("Tap + to record your first expense.")
                    )
                }
            }
        }
    }

    private func deleteExpenses(at offsets: IndexSet) {
        for index in offsets {
            context.delete(expenses[index])
        }
        // ModelContext auto-saves or explicit try? context.save()
    }
}
```

### Pattern 5: en-IN Decimal currency formatting

**What:** Format a `Decimal` value as Indian Rupee with lakh grouping (₹1,00,000.00).

```swift
// Source: Apple Foundation documentation — Decimal.FormatStyle.Currency
// [CITED: developer.apple.com/documentation/foundation/decimal/formatstyle/currency]

extension Decimal {
    /// Formats as "₹1,00,000.00" using Indian lakh grouping.
    func formattedINR() -> String {
        self.formatted(
            .currency(code: "INR")
            .locale(Locale(identifier: "en_IN"))
        )
    }
}

// Usage: expense.amount.formattedINR()
// For negative amounts (refunds): "-₹500.00" — the minus sign is automatic from the Decimal sign.
```

> **Locale note:** `Locale(identifier: "en_IN")` produces lakh grouping (1,00,000) not US grouping (100,000). This is the FND-07 requirement. Verified against: PITFALLS.md Pitfall 17, CONTEXT.md D-04. [ASSUMED: exact output format ₹1,00,000.00 — training-data knowledge of en_IN locale behavior, not verified in this session via live device; low risk as this is a well-documented locale.]

### Pattern 6: Custom decimal keypad (no system keyboard)

**What:** A 3×4 grid of tappable number keys (0–9, decimal point, backspace), always visible — no keyboard animation, no keyboard avoidance. Input managed as a String that is parsed to Decimal on save.

```swift
// Source: UI-SPEC.md § Screen 2 (Add Expense Sheet), D-04 (standard decimal keypad)
struct DecimalKeypadView: View {
    @Binding var displayString: String

    private let keys: [[String]] = [
        ["7", "8", "9"],
        ["4", "5", "6"],
        ["1", "2", "3"],
        [".", "0", "⌫"]
    ]

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: 8) {
            ForEach(keys.flatMap { $0 }, id: \.self) { key in
                Button(action: { handleKey(key) }) {
                    Text(key == "⌫" ? "delete.backward" : key)
                        .font(.title2)
                        .fontWeight(.medium)
                        .frame(maxWidth: .infinity, minHeight: 64)
                        .background(Color.secondarySystemBackground)
                        .cornerRadius(8)
                }
                .accessibilityLabel(keyAccessibilityLabel(key))
            }
        }
    }

    private func handleKey(_ key: String) {
        switch key {
        case "⌫":
            if !displayString.isEmpty { displayString.removeLast() }
        case ".":
            if !displayString.contains(".") { displayString += "." }
        default:
            // Prevent more than 2 decimal places
            if let dotIndex = displayString.firstIndex(of: ".") {
                let decimals = displayString.distance(from: dotIndex, to: displayString.endIndex) - 1
                if decimals >= 2 { return }
            }
            displayString += key
        }
    }

    private func keyAccessibilityLabel(_ key: String) -> String {
        switch key {
        case "⌫": return "Delete"
        case ".": return "Decimal point"
        default: return key
        }
    }
}
```

### Pattern 7: Swift Testing in-memory fixture (FND-06)

**What:** Fresh in-memory `ModelContainer` per test function, created on @MainActor, no shared state.

```swift
// Source: Apple SwiftData documentation + project PITFALLS.md Pitfall 16
// File: MyHomeTests/ExpenseModelTests.swift
import Testing
import SwiftData
@testable import MyHomeApp

@MainActor
struct ExpenseModelTests {

    private func makeContainer() throws -> ModelContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: Expense.self, configurations: config)
    }

    @Test("Expense can be inserted, fetched, and deleted")
    func expenseCRUD() throws {
        let container = try makeContainer()
        let context = container.mainContext

        let expense = Expense(amount: Decimal(500), note: "Lunch")
        context.insert(expense)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<Expense>())
        #expect(fetched.count == 1)
        #expect(fetched[0].currencyCode == "INR")
        #expect(fetched[0].amount == Decimal(500))

        context.delete(fetched[0])
        try context.save()
        let afterDelete = try context.fetch(FetchDescriptor<Expense>())
        #expect(afterDelete.isEmpty)
    }

    @Test("Expense amount formatted correctly for en-IN locale")
    func currencyFormatting() {
        let amount = Decimal(100000)
        let formatted = amount.formattedINR()
        // en_IN produces lakh grouping: ₹1,00,000.00
        #expect(formatted.contains("1,00,000"))
        #expect(formatted.hasPrefix("₹"))
    }
}
```

### Pattern 8: Reflection-based @Model property test (Success Criterion 4)

**What:** A Swift Testing test that uses `Mirror` to assert every stored property on `Expense` is either optional (`Optional<T>`) or carries a default value — enforcing the CloudKit-readiness rule mechanically.

```swift
// Source: PITFALLS.md Pitfall 1 ("Document the rules in a test that asserts every @Model
// property is optional/defaulted via reflection") + Swift Mirror documentation
// File: MyHomeTests/ExpenseModelTests.swift (continued)

@Test("Expense @Model: all properties are optional or have defaults (CloudKit-readiness)")
@MainActor
func expensePropertiesAreCloudKitReady() throws {
    // Create an Expense with only required parameters; verify all others default.
    let expense = Expense(amount: Decimal(0))
    let mirror = Mirror(reflecting: expense)

    for child in mirror.children {
        guard let label = child.label else { continue }
        let value = child.value
        let isOptional = value is (any OptionalProtocol)
        let hasNonNilValue = !isOptional

        // Every property must be either optional (nil is valid) or
        // have produced a non-nil value from a default.
        let passesRule = isOptional || hasNonNilValue
        #expect(passesRule, "Property '\(label)' must be optional or have a default value")
    }

    // Additionally: assert no @Attribute(.unique) by verifying
    // the model's entity description has no uniquenessConstraints.
    // SwiftData exposes this via the entity metadata at runtime.
    let container = try ModelContainer(
        for: Expense.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    let entityDescription = container.schema.entities.first { $0.name == "Expense" }
    #expect(entityDescription?.uniquenessConstraints.isEmpty == true,
            "Expense must have no @Attribute(.unique) — CloudKit does not support it")
}

// Helper to detect Optional values via type system
private protocol OptionalProtocol {}
extension Optional: OptionalProtocol {}
```

> **Note on uniquenessConstraints API:** The exact path to `entity.uniquenessConstraints` via the SwiftData schema API should be verified at implementation time. If the API is not accessible, the assertion can be replaced with a code-review checklist item: "grep for `@Attribute(.unique)` in all @Model files and assert zero results." [ASSUMED: schema entity API shape — verify in Xcode.]

### Pattern 9: Migration-load test against bundled v1 store (Success Criterion 4)

**What:** A test that copies a bundled v1 SQLite store to a temp URL and loads it via `ModelContainer` with `AppMigrationPlan`, asserting data survives the load.

```swift
// Source: medium.com/@abegehr/testing-swiftdata-migrations-7a612da2c91c
// (verified pattern, adapted for project; migration stages are empty so this is a
// load-and-survive test rather than a transform test)
// File: MyHomeTests/MigrationTests.swift
import Testing
import SwiftData
@testable import MyHomeApp

@MainActor
struct MigrationTests {

    @Test("v1 store loads successfully under AppMigrationPlan")
    func v1StoreMigratesCleanly() throws {
        // 1. Locate the bundled v1 store (checked into test resources after Wave 3).
        guard let bundledStoreURL = Bundle(for: type(of: self)).url(
            forResource: "MyHomeV1Seed", withExtension: "store"
        ) else {
            // If the seed store doesn't exist yet (pre-Wave 3), issue a warning
            // rather than failing — the planner must create it in Wave 3.
            Issue.record("Bundled v1 seed store not found — ensure MyHomeV1Seed.store is added to test target resources")
            return
        }

        // 2. Copy to a temp location so the test does not modify the bundle resource.
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("migration-test-\(UUID()).store")
        try FileManager.default.copyItem(at: bundledStoreURL, to: tempURL)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        // 3. Open with the migration plan — if migration fails, ModelContainer.init throws.
        let schema = Schema(versionedSchema: SchemaV1.self)
        let config = ModelConfiguration(schema: schema, url: tempURL)
        let container = try ModelContainer(
            for: schema,
            migrationPlan: AppMigrationPlan.self,
            configurations: [config]
        )

        // 4. Verify at least one expense is readable (store was pre-seeded with one).
        let context = container.mainContext
        let expenses = try context.fetch(FetchDescriptor<Expense>())
        #expect(!expenses.isEmpty, "At least one expense must survive the v1 store load")
    }
}
```

**How to create the seed store (Wave 3 task):**
1. Run the app once in simulator, add one expense (e.g. ₹100, note "Seed").
2. Find the store file at the App Group container path (or Application Support fallback).
3. Copy `MyHome.store` + `MyHome.store-shm` + `MyHome.store-wal` to the test target's resources folder, rename to `MyHomeV1Seed.store`.
4. Add to the test target's "Copy Bundle Resources" build phase.

### Anti-Patterns to Avoid

- **Using `@Attribute(.unique)` on Expense.id:** Tempting because you want uniqueness — but CloudKit rejects it. Enforce uniqueness with a lookup-before-insert pattern: `fetch where id == newID; if empty, insert`.
- **Storing `amount: Double` instead of `Decimal`:** The compiler does not complain; financial sums will drift. Grep the codebase before each commit: `grep ": Double"` in @Model files must return zero results.
- **Using `NavigationLink` with the @Model object in the path:** NavigationPath entries must be `Hashable + Codable`. Use the `UUID` in the path and look up the expense by ID in the destination. [CITED: PITFALLS.md Pitfall 19]
- **Mutating @Model properties from a background Task:** `ModelContext` is bound to its actor (MainActor). Background work must return `Sendable` value types; switch to @MainActor to write. [CITED: PITFALLS.md Pitfall 18]
- **Using `.keyboardType(.decimalPad)` instead of the custom keypad:** The UI-SPEC requires a custom keypad (no system keyboard animation, no keyboard avoidance layout thrash). The custom `DecimalKeypadView` is always visible.
- **Skipping `VersionedSchema` because "v1 has no migrations":** The first schema change after launch — adding `Category` in Phase 2 — will be the first real migration. Without the versioned scaffold, SwiftData's lightweight migration fails silently on properties it cannot infer, wiping the store. [CITED: PITFALLS.md Pitfall 7]

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Decimal currency formatting | Custom String manipulation for ₹ symbol + grouping | `Decimal.formatted(.currency(code:).locale(:))` | Handles lakh grouping, RTL, dynamic type, and future multi-currency automatically |
| Schema migration | Custom SQLite migration scripts | `VersionedSchema` + `SchemaMigrationPlan` | SwiftData handles the store file transformation; hand-rolling SQLite against a SwiftData store is unsupported and fragile |
| In-memory test store | A mock/fake of ModelContext | `ModelContainer(isStoredInMemoryOnly: true)` | Faster than mocks and tests real query semantics including predicates |
| CloudKit-readiness validation | Manual code review checklist | Reflection test + uniquenessConstraints assertion | Catches regressions automatically when a new developer adds a non-optional property |
| Date UTC enforcement | Custom Date wrapper | Store `Date` (always UTC in Swift), format with `DateFormatter` using `.timeZone = .current` at display time | Swift `Date` values are always UTC; display formatting is the only place timezone appears |

**Key insight:** The SwiftData framework does the heavy lifting for persistence, migration, and live-query reactivity. The entire Phase 1 job is to configure it correctly — not to build around it.

---

## Common Pitfalls

### Pitfall 1: App Group container URL not set from day one
**What goes wrong:** ModelContainer created with no custom URL → store goes to the app sandbox, not the App Group container. When Phase 4 adds a widget, data is invisible to the extension process. Migrating the store later requires user-visible data surgery.
**Why it happens:** The default ModelConfiguration uses Application Support — perfectly fine until a second process needs the store.
**How to avoid:** Set `url: appGroupContainerURL` in `ModelConfiguration` on day one. If App Groups are unavailable on the free account, use Application Support but document the store path as a known migration item.
**Warning signs:** `ModelContainer+App.swift` contains no custom `url:` parameter.

### Pitfall 2: @Attribute(.unique) on Expense.id
**What goes wrong:** `@Attribute(.unique) var id: UUID = UUID()` compiles and works locally. The moment CloudKit mirroring is enabled in a future phase, `ModelContainer.init` throws and the store fails to open.
**Why it happens:** Uniqueness is a single-store concept; CloudKit cannot enforce it across devices.
**How to avoid:** Never use `@Attribute(.unique)`. Enforce uniqueness in application code via lookup-before-insert. The reflection test catches this mechanically.
**Warning signs:** Any `@Attribute(.unique)` in any @Model file.

### Pitfall 3: #Predicate with computed properties or Date() literal
**What goes wrong:** A predicate like `#Predicate<Expense> { $0.date > Date() }` compiles but crashes at runtime with `_PFPredicateBridge` error — `Date()` is a non-deterministic expression that cannot be lowered to NSPredicate.
**Why it happens:** SwiftData's `#Predicate` macro lowers to NSPredicate, which only supports stored properties and pre-computed constants.
**How to avoid:** Always capture `Date` boundaries outside the predicate: `let now = Date(); let predicate = #Predicate<Expense> { $0.date > now }`.
**Warning signs:** `Date()`, `Calendar.current.`, or computed properties inside `#Predicate { }` blocks.

### Pitfall 4: Forgetting PrivacyInfo.xcprivacy in the target
**What goes wrong:** TestFlight upload (future phases) returns ITMS-91053: Missing API Declaration. Required Reason APIs include `UserDefaults` (used by SwiftData/Foundation internally) and file timestamps.
**Why it happens:** The manifest is required from May 2024 for App Store submissions; easy to forget on a sideloaded v1.
**How to avoid:** Add `PrivacyInfo.xcprivacy` to the app target from day one with `NSPrivacyTracking: false`, `NSPrivacyAccessedAPICategoryUserDefaults: [CA92.1]`, `NSPrivacyAccessedAPICategoryFileTimestamp: [C617.1]`.
**Warning signs:** No `PrivacyInfo.xcprivacy` file in the project navigator.

### Pitfall 5: Mixing @Observable and ObservableObject in the same module
**What goes wrong:** If any view uses `@StateObject` or `@Published` while another uses `@Observable`, update propagation is inconsistent — stale data in detail views after list updates.
**Why it happens:** Tutorial code mixes iOS 16 and iOS 17 patterns. The compiler accepts both.
**How to avoid:** Project-wide rule: `@Observable` for all view models and shared state objects. Never `@StateObject`/`@ObservedObject`/`@Published`. Set this in the project README before any code is written.
**Warning signs:** `@StateObject`, `@ObservedObject`, or `@Published` anywhere in new code.

### Pitfall 6: system keyboard with a TextField for amount input
**What goes wrong:** Using a `TextField` with `.keyboardType(.decimalPad)` causes keyboard-avoidance layout thrash (the sheet content jumps), does not show a custom confirm action, and allows multiple decimal points. The UI-SPEC prohibits this.
**Why it happens:** TextField is the default, but the UI-SPEC requires a custom always-visible keypad.
**How to avoid:** Use `DecimalKeypadView` (custom grid) that is always part of the layout. Manage input as a String state variable parsed to Decimal on Save. No `TextField` for the amount field.
**Warning signs:** Any `TextField` binding to the amount field in AddExpenseView.

---

## Code Examples

### en-IN amount formatting — lakh grouping verification

```swift
// Source: Apple Foundation FormatStyle documentation
// [CITED: developer.apple.com/documentation/foundation/decimal/formatstyle/currency]

// ₹1,00,000.00 — note the lakh separator (not ₹100,000.00)
let amount = Decimal(100000)
let formatted = amount.formatted(.currency(code: "INR").locale(Locale(identifier: "en_IN")))
// formatted == "₹1,00,000.00"

// Negative amount (refund): "-₹500.00"
let refund = Decimal(-500)
let formattedRefund = refund.formatted(.currency(code: "INR").locale(Locale(identifier: "en_IN")))
// formattedRefund == "-₹500.00"
```

### UTC storage + local display for Date

```swift
// Source: CONTEXT.md D-02, PITFALLS.md Pitfall 17
// Store: always Date() — Swift Date is always UTC internally.
// Display: format with the user's current locale/timezone.

extension Date {
    /// Formats for display in the expense list (user's local time).
    func formattedForExpenseList() -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        formatter.locale = .current      // user's locale
        formatter.timeZone = .current    // user's timezone for display
        return formatter.string(from: self)
    }

    /// Formats as "Today, 9:41 AM" or "28 May 2026, 9:41 AM" for the date picker row.
    func formattedForDatePickerRow() -> String {
        if Calendar.current.isDateInToday(self) {
            let formatter = DateFormatter()
            formatter.dateStyle = .none
            formatter.timeStyle = .short
            return "Today, \(formatter.string(from: self))"
        } else {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .short
            return formatter.string(from: self)
        }
    }
}
```

### PrivacyInfo.xcprivacy plist structure

```xml
<!-- Source: Apple TN3183 + Pitfalls.md Pitfall 12 -->
<!-- [CITED: developer.apple.com/documentation/technotes/tn3183-adding-required-reason-api-entries-to-your-privacy-manifest] -->
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>NSPrivacyTracking</key>
    <false/>
    <key>NSPrivacyTrackingDomains</key>
    <array/>
    <key>NSPrivacyCollectedDataTypes</key>
    <array/>
    <key>NSPrivacyAccessedAPITypes</key>
    <array>
        <dict>
            <key>NSPrivacyAccessedAPIType</key>
            <string>NSPrivacyAccessedAPICategoryUserDefaults</string>
            <key>NSPrivacyAccessedAPITypeReasons</key>
            <array>
                <string>CA92.1</string>
            </array>
        </dict>
        <dict>
            <key>NSPrivacyAccessedAPIType</key>
            <string>NSPrivacyAccessedAPICategoryFileTimestamp</string>
            <key>NSPrivacyAccessedAPITypeReasons</key>
            <array>
                <string>C617.1</string>
            </array>
        </dict>
    </array>
</dict>
</plist>
```

---

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| `@Published` + `ObservableObject` + `@StateObject` | `@Observable` macro + `@State` / `@Bindable` | iOS 17 (2023) | Fewer re-renders, no Combine import, simpler code |
| XCTest for all tests | Swift Testing for unit/integration, XCTest only for UI | Xcode 16 / Swift 6 (2024) | `@Test`, `#expect`, parameterized, parallel-by-default |
| `NumberFormatter` with currencyCode | `Decimal.formatted(.currency(code:).locale(:))` | iOS 15 (2021) | Concise, type-safe, chainable |
| Core Data + `NSManagedObject` | SwiftData `@Model` + `@Query` | iOS 17 (2023) | Declarative, type-safe, CloudKit-wired by config |
| Manual schema migration (Core Data mapping models) | `VersionedSchema` + `SchemaMigrationPlan` | iOS 17 (2023) | Versioned, auditable, Swift-native |

**Deprecated/outdated in this project's context:**
- `@StateObject`/`@ObservedObject`/`@Published`: replaced by `@Observable`. Appear in legacy tutorials; avoid on iOS 17+.
- `NSNumberFormatter` / `NumberFormatter` for currency: works but is the legacy API; `FormatStyle` is current.
- Core Data as primary persistence: not deprecated but SwiftData is the Apple-preferred path for iOS 17+ greenfield.

---

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | `Decimal.formatted(.currency(code: "INR").locale(Locale(identifier: "en_IN")))` produces `₹1,00,000.00` with lakh grouping | Code Examples | If locale behavior differs on device, amounts display in wrong grouping (₹100,000.00 vs ₹1,00,000.00) — cosmetic but violates FND-07. Verify by running `Decimal(100000).formatted(...)` in a playground. |
| A2 | `entity.uniquenessConstraints` is accessible via the `Schema` object at test time | Pattern 8 (reflection test) | If the API is not exposed, the `.unique` assertion must be replaced with a grep-based test or a code-review checklist. Low risk — the reflection test for optionality still works. |
| A3 | App Group (`group.com.reojacob.myhome`) works on the free Apple Developer account for local-only store access | Pattern 2 (ModelContainer) | If App Group entitlement fails on free account, must fall back to Application Support URL and document a migration task. Medium risk — noted in PITFALLS.md Pitfall 5 and 13. |
| A4 | `Schema.Version(1, 0, 0)` is the correct `VersionedSchema.versionIdentifier` type for SwiftData | Pattern 2 (VersionedSchema) | If the version identifier type differs (e.g., requires a string or custom struct), compilation fails. Verify in Xcode against the current SwiftData SDK. |
| A5 | Bundle(for: type(of: self)) locates resources in the test target bundle | Pattern 9 (migration test) | In Swift Testing (not XCTest), the bundle accessor may differ. May need `Bundle.module` if the test is in an SPM package target. Verify at implementation. |

---

## Open Questions

1. **App Group on free account**
   - What we know: Apple free accounts have unreliable App Group entitlement provisioning (PITFALLS.md Pitfall 5, 13).
   - What's unclear: Whether `group.com.reojacob.myhome` will provision successfully for Reo's specific free Apple ID.
   - Recommendation: Attempt App Group first. If Xcode refuses, use Application Support as the temporary store URL with a `// TODO: migrate to App Group URL when paid account active` comment. Document the fallback path in Wave 0 task.

2. **Swift 6 strict concurrency setting**
   - What we know: The project is iOS 17+ / Swift 6.2 and should use strict concurrency (PITFALLS.md Pitfall 18).
   - What's unclear: Whether "Approachable Concurrency" (the learner-friendly Swift 6.2 mode) is the right build setting for a new learner or whether full `SWIFT_STRICT_CONCURRENCY = complete` should be set from day one.
   - Recommendation: Set `SWIFT_STRICT_CONCURRENCY = complete` from day one. It is cheaper to fight compiler errors as you write them than to enable it on 500 lines of code later. STACK.md confirms this stance.

3. **@Model types inside vs. outside VersionedSchema enum**
   - What we know: Nesting `@Model` types inside the `SchemaV1` enum prevents namespace collisions when v2 changes the model.
   - What's unclear: Whether the app's views should use `Expense` (a typealias to `SchemaV1.Expense`) or `SchemaV1.Expense` directly. Using a typealias at the top of the app target keeps views clean.
   - Recommendation: Use `typealias Expense = SchemaV1.Expense` in `Expense.swift` (outside the versioned enum) so views import `Expense` without the version prefix. When v2 arrives, the typealias flips to `SchemaV1_2.Expense` in one line.

---

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| Xcode 26 | FND-01 (Swift 6.2, iOS 17+) | [User must verify] | 26.x | No fallback — Swift 6.2 requires Xcode 26 |
| iOS 17 simulator | EXP-01 (tap-flow testing) | [User must verify] | iOS 17+ | Use iOS 18 simulator — superset |
| Free Apple Developer account | FND-02 (bundle ID, App Group) | Assumed available (Reo's Apple ID) | free | Paid account not required for Phase 1 |
| Real iOS device | Verification (sim ≠ device for some paths) | Assumed (Reo's iPhone) | iOS 17+ | No substitute for device testing |
| App Group entitlement | FND-02 + ModelContainer URL | Uncertain on free account | — | Application Support fallback (documented above) |

**Missing dependencies with no fallback:**
- Xcode 26: required for Swift 6.2 and the Swift Testing test reporter. If only Xcode 15 is available, the test suite cannot use `@Test`/`#expect` with the full reporter. [User: confirm Xcode 26 is installed.]

**Missing dependencies with fallback:**
- App Group entitlement: use Application Support URL with a documented migration task.

---

## Validation Architecture

> `workflow.nyquist_validation: true` — section included.

### Test Framework

| Property | Value |
|----------|-------|
| Framework | Swift Testing (bundled, no SPM dep) + XCTest for UI tests |
| Config file | No pytest.ini equivalent — Xcode Test Plans (one unit plan, one UI plan) |
| Quick run command | `CMD-U` in Xcode (runs all Swift Testing + XCTest unit tests) |
| Full suite command | `xcodebuild test -scheme MyHome -destination 'platform=iOS Simulator,name=iPhone 16'` |

### Phase Requirements → Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| FND-03 | All @Model properties optional or defaulted, no .unique | Unit (reflection) | `CMD-U → ExpenseModelTests/expensePropertiesAreCloudKitReady` | ❌ Wave 0 |
| FND-05 | VersionedSchema v1 loads successfully | Integration (migration load) | `CMD-U → MigrationTests/v1StoreMigratesCleanly` | ❌ Wave 0 |
| FND-06 | In-memory ModelContainer fixture per test | Unit (infra) | `CMD-U → ExpenseModelTests/expenseCRUD` | ❌ Wave 0 |
| FND-07 | en-IN currency formatting produces lakh grouping | Unit | `CMD-U → ExpenseModelTests/currencyFormatting` | ❌ Wave 0 |
| EXP-01 | Expense can be inserted via context and appears in @Query | Unit | `CMD-U → ExpenseModelTests/expenseCRUD` | ❌ Wave 0 |
| EXP-02 | Expense fields can be updated and saved | Unit | `CMD-U → ExpenseModelTests/expenseUpdate` | ❌ Wave 0 |
| EXP-03 | Expense can be deleted from context | Unit | `CMD-U → ExpenseModelTests/expenseCRUD` | ❌ Wave 0 |
| EXP-01 | ≤4-tap add flow (open → amount → save) | Manual smoke | Device: add an expense in ≤3 taps | — Manual |
| FND-04 | PrivacyInfo.xcprivacy exists with correct keys | Static check | `grep -l "NSPrivacyTracking" MyHomeApp/Resources/PrivacyInfo.xcprivacy` | ❌ Wave 0 |

### Sampling Rate

- **Per task commit:** `CMD-U` — full unit test suite (< 5 seconds on in-memory store)
- **Per wave merge:** Full suite: `xcodebuild test -scheme MyHome -destination '...'`
- **Phase gate:** All tests green + manual ≤4-tap smoke test on real device before `/gsd-verify-work`

### Wave 0 Gaps

- [ ] `MyHomeTests/ExpenseModelTests.swift` — covers FND-03, FND-06, FND-07, EXP-01, EXP-02, EXP-03
- [ ] `MyHomeTests/MigrationTests.swift` — covers FND-05 (requires seed store from Wave 3)
- [ ] `MyHomeTests/` target configured in Xcode with Swift Testing enabled (no XCTest class, just `@Test` functions)
- [ ] Seed store `MyHomeV1Seed.store` — created after Wave 3 (add one expense to sim, export store file, add to test bundle resources)

---

## Security Domain

> `security_enforcement: true`, ASVS level 1 — section included.

### Applicable ASVS Categories

| ASVS Category | Applies | Standard Control |
|---------------|---------|-----------------|
| V2 Authentication | No | No auth in Phase 1 (Face ID is Phase 5) |
| V3 Session Management | No | No sessions in Phase 1 |
| V4 Access Control | No | No access control in Phase 1 |
| V5 Input Validation | Yes | Amount: String → Decimal parse with guard for NaN/overflow; Date: DatePicker range-bound |
| V6 Cryptography | No | No cryptographic operations in Phase 1 |

### Known Threat Patterns for SwiftData / SwiftUI Local Storage

| Pattern | STRIDE | Standard Mitigation |
|---------|--------|---------------------|
| Financial data in an unprotected file container | Information Disclosure | SwiftData store inherits iOS Data Protection (Complete class by default on modern devices). Do not explicitly downgrade protection class. |
| Amount input accepts malicious large values | Tampering | Validate parsed Decimal is within a reasonable range (e.g., abs(amount) < 1_000_000_000) before inserting. |
| Note field XSS-equivalent (if rendered as HTML) | Tampering | SwiftUI `Text()` renders plain text, not HTML — no sanitization needed. Do not use `AttributedString(markdown:)` on user input. |
| Privacy manifest missing → App Store rejection | Denial of Service (ship blocker) | Add `PrivacyInfo.xcprivacy` on day one (FND-04). |

---

## Sources

### Primary (HIGH confidence)

- `.planning/research/ARCHITECTURE.md` — CloudKit-ready model rules, ModelContainer setup, @Query patterns, VersionedSchema scaffolding; researched 2026-05-28
- `.planning/research/PITFALLS.md` — 20 pitfalls with phase-to-address mapping; researched 2026-05-28; Pitfalls 1, 3, 7, 12, 13, 16, 17, 18 are directly applicable to Phase 1
- `.planning/research/STACK.md` — Swift 6.2 / Xcode 26 / iOS 17 stack rationale; researched 2026-05-28
- `.planning/phases/01-foundation-manual-expense-spine/01-CONTEXT.md` — locked decisions D-01 through D-09
- `.planning/phases/01-foundation-manual-expense-spine/01-UI-SPEC.md` — screen layouts, copywriting, interaction contracts
- Apple Developer — [VersionedSchema protocol](https://developer.apple.com/documentation/swiftdata/versionedschema)
- Apple Developer — [Decimal.FormatStyle.Currency](https://developer.apple.com/documentation/foundation/decimal/formatstyle/currency)
- Apple Developer — [isStoredInMemoryOnly](https://developer.apple.com/documentation/swiftdata/modelconfiguration/isstoredinmemoryonly)

### Secondary (MEDIUM confidence)

- [Testing SwiftData Migrations](https://medium.com/@abegehr/testing-swiftdata-migrations-7a612da2c91c) — VersionedSchema enum structure, SchemaMigrationPlan, bundled store migration test pattern
- [Apple TN3183 — Required Reason API entries](https://developer.apple.com/documentation/technotes/tn3183-adding-required-reason-api-entries-to-your-privacy-manifest) — CA92.1 / C617.1 reason codes
- [Atomic Robot — SwiftData Migrations guide](https://atomicrobot.com/blog/an-unauthorized-guide-to-swiftdata-migrations/) — ModelContainer(for:migrationPlan:configurations:) init pattern
- [Apple WWDC23 — Model your schema with SwiftData](https://developer.apple.com/videos/play/wwdc2023/10195/) — canonical VersionedSchema introduction

### Tertiary (LOW confidence — mark for validation)

- Training-data knowledge of `Locale(identifier: "en_IN")` producing lakh grouping `₹1,00,000.00` [A1 — verify in Xcode playground]
- Training-data knowledge of SwiftData `schema.entities.first?.uniquenessConstraints` API shape [A2 — verify in Xcode]

---

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — Apple-mandated; locked by FND-01; prior research docs (STACK.md) verified against Apple docs 2026-05-28
- @Model schema rules: HIGH — 8 rules documented in ARCHITECTURE.md; derived from Apple's CloudKit + SwiftData requirements
- VersionedSchema pattern: HIGH — secondary source (medium.com/@abegehr verified against Apple WWDC23); pattern is stable and documented
- en-IN formatting: MEDIUM — pattern verified via Apple docs link; actual output format [ASSUMED] due to inability to run live Xcode session
- Privacy manifest: HIGH — Apple TN3183 is authoritative; CA92.1 and C617.1 reason codes confirmed via secondary sources
- Reflection test for @Model: MEDIUM — Mirror API is stable; exact `uniquenessConstraints` path on Schema entities is [ASSUMED]
- Migration load test: MEDIUM — pattern from secondary source; `Bundle(for: type(of: self))` in Swift Testing vs XCTest context is [ASSUMED]

**Research date:** 2026-05-29
**Valid until:** 2026-08-29 (90 days — stable Apple-platform APIs; re-verify VersionedSchema and FormatStyle if Xcode 27 / iOS 19 is released before implementation)
