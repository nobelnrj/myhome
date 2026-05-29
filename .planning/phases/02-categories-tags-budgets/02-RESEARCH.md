# Phase 2: Categories, Tags & Budgets - Research

**Researched:** 2026-05-29
**Domain:** SwiftData schema migration + CloudKit-ready relationships + budget aggregation + TabView shell
**Confidence:** HIGH for SwiftData patterns and SwiftUI; MEDIUM for migration edge-case behavior (documented bugs exist)

---

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

- **D2-01:** "Category" and "tag" are a single unified taxonomy. One picker. Predefined + custom = same `Category` `@Model`. No separate Tag entity.
- **D2-02:** Expense carries a single category in v1 UI, but schema models an optional inverse-declared to-many relationship (`Expense ↔ Category`) so multiple categories require no future breaking migration. Must honor the 8 CloudKit-readiness rules: optional, inverse-declared, `.nullify` delete rule.
- **D2-03:** Ship 14 India-tuned predefined categories seeded on first launch (idempotent — no duplicates on relaunch): Groceries, Dining, Fuel, Utilities, Rent, Auto/Cab, Shopping, Health/Pharmacy, Entertainment, Recharge/DTH, Maid/Help, UPI to Person, ATM, Misc.
- **D2-04:** Predefined and custom categories are treated uniformly — all can be renamed and deleted. Deleting a category nullifies the link on its expenses. Budget attached to a deleted category is removed with it.
- **D2-05:** Budget is a single recurring monthly limit per category — set once, applies every calendar month. No per-specific-month budget rows.
- **D2-06:** Recommended storage: `monthlyBudget: Decimal?` directly on `Category` (nil = no budget). A separate `Budget` model is acceptable but per-month rows are explicitly NOT needed.
- **D2-07:** Budget scope is the calendar month. Default viewed month = current month.
- **D2-08:** Uncategorized spend counts in month totals but against no budget. Surfaces as its own "Uncategorized" group in month view, excluded from per-category budget math.
- **D2-09:** Budget bar color thresholds: under 80% = normal/accent; 80%–99% = warning (amber/orange); ≥100% = over-budget (red). Color never the sole signal — pair with % / ₹-remaining text.
- **D2-10:** Introduce `TabView` in `RootView`. Phase 2 tabs: (1) Expenses — existing `ExpenseListView` essentially unchanged; (2) Budgets — per-category cards with month paging, tap-through to filtered transaction list.
- **D2-11:** Category + budget management lives inline on the Budgets surface in Phase 2. No Settings shell in Phase 2. Phase 5 relocates/mirrors into Settings.
- **D2-12:** Phase 1 add/edit sheets gain an optional category picker row (Section 2, off the ≤3-tap critical path). Reuse existing sheet/`@Bindable` patterns. Do not regress ≤4-tap add target (EXP-01).

### Claude's Discretion

- Exact `Category` field set and SF Symbol/sort-order modeling.
- Idempotent seeding mechanism.
- `SchemaV2` + `MigrationStage` wiring and `Expense` typealias flip.
- Category-picker UI affordance (menu vs sheet vs inline list).
- Month-paging control.
- All visual layout (owned by Phase 2 UI-SPEC).
- Schema-field naming (as long as 8 CloudKit-readiness rules and D2-02/D2-06 hold).

### Deferred Ideas (OUT OF SCOPE)

- Multi-select tags in the UI (schema supports it; v1 UI is single-select).
- Spend-by-category and spend-over-time charts → Phase 4.
- Overview / home surface → Phase 4.
- Settings shell owning category + budget management → Phase 5.
- Per-month (non-recurring) budgets / festival-month overrides → not in v1.
- Budget-threshold notifications (80%/100%) → v2 (NTF-V2-01).
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| EXP-04 | App ships with India-tuned predefined category list (14 categories) | D2-03 idempotent seed on first launch; FetchDescriptor + fetchLimit:1 empty-check pattern |
| EXP-05 | User can add, rename, and delete custom categories | `Category` @Model with standard SwiftData CRUD; `.nullify` cascade to expenses on delete |
| EXP-06 | User can attach one tag to an expense; schema supports multiple for future UI | D2-02 to-many relationship declared in SchemaV2; v1 UI surfaces single-select picker |
| EXP-07 | User can set a monthly budget per category (calendar month default) | `monthlyBudget: Decimal?` on `Category`; calendar-month scoping via UTC date boundaries |
| EXP-08 | Per-category budget progress shown as ₹-remaining + % bar with color shift at 80% and 100% | In-memory aggregation of this-month spend per category; `BudgetProgressView` component |
| EXP-09 | Month view shows expenses grouped by category with tap-through to transaction list | Budgets tab with month paging; per-category `FetchDescriptor` predicate using `persistentModelID` workaround |
</phase_requirements>

---

## Summary

Phase 2 has five technically distinct sub-problems, each with its own risk profile:

**1. SchemaV2 migration.** The project already has a `VersionedSchema` + `SchemaMigrationPlan` scaffolded from Phase 1. Adding `Category` as a new `@Model` type and adding a new optional to-many relationship on `Expense` qualifies as a **lightweight migration** per Apple's documented rules (adding entities, adding optional relationships). However, a class of SwiftData bugs (present on iOS 17.0–17.4, largely addressed by 17.4+ and iOS 18) caused certain lightweight stages to fail when an existing `SchemaMigrationPlan` was provided. The safe mitigation is to use an **empty `MigrationStage.custom`** (both `willMigrate` and `didMigrate` = nil) instead of `.lightweight` when in doubt — it is semantically identical for additive changes but sidesteps the reported `SchemaMigrationPlan`-interaction bugs. The existing `MigrationTests.swift` + bundled `MyHomeV1Seed.store` fixture will immediately catch any regression.

**2. Relationship cardinality.** D2-02 requires an optional to-many relationship with inverse and `.nullify` delete rule. SwiftData requires Array (not Set) for to-many. The relationship must be declared in SchemaV2.Expense and SchemaV2.Category with explicit `inverse:` to satisfy CloudKit readiness rule 4. Performance note: appending to a to-many relationship in a loop is 30× slower than batch `append(contentsOf:)` — relevant for the seeding step.

**3. Idempotent seeding.** The standard pattern is a post-migration hook inside `ModelContainer+App.swift`: fetch `Category` with `FetchDescriptor(fetchLimit: 1)` — if count == 0, insert all 14 predefined categories and call `try context.save()`. This is safe, fast, and survives future migration runs without duplicating records.

**4. Budget aggregation queries.** SwiftData's `#Predicate` does not support: computed properties, `Date()` as a non-deterministic expression, relationship-object comparison (use `persistentModelID` instead), or `Decimal` aggregation functions. The recommended approach is to **fetch all expenses for the viewed month via a date-bounded FetchDescriptor** (pre-compute `startOfMonth`/`endOfMonth` as `let` constants outside the predicate), then **aggregate in-memory in Swift** — grouping by category `persistentModelID` and summing `amount` with `reduce`. This is fast and correct for the data volumes involved (one household, months of data).

**5. TabView shell.** The RootView today is a thin wrapper around `ExpenseListView`. Replacing it with a `TabView` that embeds two `NavigationStack`-owning tabs is straightforward; the canonical pattern is one independent `NavigationStack` per tab, each owning its own navigation path. No coordinator pattern needed.

**Primary recommendation:** Define `SchemaV2` with `Category` @Model and the updated `Expense` (with optional to-many `categories` relationship), wire a `MigrationStage.custom(willMigrate: nil, didMigrate: nil)` as the V1→V2 stage (safer than `.lightweight` given the known iOS 17 SchemaMigrationPlan bugs), seed categories post-migration using `FetchDescriptor(fetchLimit: 1)` empty-check, compute budget aggregation entirely in-memory via fetched arrays, and introduce the `TabView` shell as a wrapper with two `NavigationStack` tabs.

---

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| Category @Model + schema | Data Layer (SwiftData) | — | @Model type lives in Persistence/Schema/SchemaV2 |
| V1→V2 migration | Data Layer (ModelContainer+App) | — | MigrationPlan + migration stage wiring at container boot |
| Idempotent category seeding | Data Layer (ModelContainer+App) | — | Runs once per process after container init, before first view appears |
| Category CRUD (add/rename/delete) | Presentation Layer (BudgetsView) | — | Direct @Environment(\.modelContext) writes per established pattern |
| Category picker in add/edit flow | Presentation Layer (AddExpenseView, EditExpenseView) | — | @Bindable pattern already in place; picker is a new Section 2 row |
| Month-scoped spend aggregation | Presentation Layer (BudgetsView, computed) | — | FetchDescriptor + in-memory reduce; no repository layer (established pattern) |
| Budget progress visualization | Presentation Layer (BudgetProgressView) | — | Pure SwiftUI view consuming pre-computed Decimal values |
| TabView shell | Presentation Layer (RootView) | — | Wrapper only; each tab owns its NavigationStack |
| Month paging state | Presentation Layer (@State in BudgetsView) | — | Local UI state — DateComponents for viewed month |

---

## Standard Stack

### Core (no new packages — all first-party)

| Technology | Version | Purpose | Why Standard |
|-----------|---------|---------|--------------|
| SwiftData | iOS 17+ (VersionedSchema) | Category @Model, SchemaV2 migration | Already in use; additive change only |
| SwiftUI | iOS 17+ | TabView, category picker, BudgetProgressView | Already in use; all needed views are standard primitives |
| Foundation | — | Calendar date boundaries, Decimal arithmetic | Built-in |

**No new package dependencies in Phase 2.** All functionality is achievable with first-party frameworks already in use.

### Package Legitimacy Audit

> No external packages are installed in this phase. All capabilities use first-party Apple frameworks. Audit not applicable.

**Packages removed due to slopcheck [SLOP] verdict:** none
**Packages flagged as suspicious [SUS]:** none

---

## Architecture Patterns

### System Architecture Diagram

```
  User taps + (Expenses tab)
        │
        ▼
  AddExpenseView / EditExpenseView
        │  reads all Categories via @Query
        │  user selects one category (optional)
        │  saves: expense.categories = [selectedCategory]
        ▼
  ModelContext.save() → SwiftData (SchemaV2 store)
        │
        ├─────────────────────────────────────────┐
        │                                         │
        ▼                                         ▼
  ExpenseListView (@Query all expenses)     BudgetsView
        │                                         │
        │                                    month-paging state (@State viewedMonth)
        │                                         │
        │                                    FetchDescriptor(predicate: date in [start, end])
        │                                    → [Expense] for this month
        │                                         │
        │                                    in-memory group by category.persistentModelID
        │                                    in-memory sum expense.amount per group
        │                                         │
        │                                    per-category card:
        │                                      spent / budget → progress bar
        │                                      tap → FilteredExpenseListView
        │                                           (same FetchDescriptor + category filter)
        │
  (no change to ExpenseListView; category picker row added to Section 2)
```

### Recommended Project Structure for Phase 2

```
MyHomeApp/
├── Persistence/
│   ├── Schema/
│   │   ├── SchemaV1.swift           (unchanged — never mutate)
│   │   └── SchemaV2.swift           (NEW: Category @Model + updated Expense with .categories)
│   ├── MigrationPlan.swift          (updated: SchemaV2 added, V1→V2 stage added)
│   ├── Models/
│   │   ├── Expense.swift            (typealias flipped to SchemaV2.Expense)
│   │   └── Category.swift           (NEW: typealias → SchemaV2.Category)
│   └── ModelContainer+App.swift     (updated: Schema(versionedSchema: SchemaV2.self) + seed hook)
├── Features/
│   ├── Expenses/
│   │   ├── ExpenseListView.swift    (unchanged)
│   │   ├── AddExpenseView.swift     (updated: optional category picker row in Section 2)
│   │   ├── EditExpenseView.swift    (updated: optional category picker row in Section 2)
│   │   ├── CategoryPickerView.swift (NEW: sheet or menu picker, reusable by both add/edit)
│   │   ├── ExpenseRow.swift         (unchanged or minor: optionally show category badge)
│   │   └── DecimalKeypadView.swift  (unchanged — reused for budget entry)
│   └── Budgets/                     (NEW vertical slice)
│       ├── BudgetsView.swift        (TabView tab 2: month header + category cards + Manage entry)
│       ├── BudgetCategoryCard.swift (card: category name, icon, spent, budget, progress bar)
│       ├── BudgetProgressView.swift (reusable progress bar with color thresholds)
│       ├── ManageCategoriesView.swift (add/rename/delete categories)
│       ├── EditBudgetSheet.swift    (set/clear monthlyBudget for one category)
│       └── FilteredExpenseListView.swift (tap-through: expenses for month+category)
└── RootView.swift                   (updated: TabView wrapping two NavigationStack-owning tabs)
```

### Pattern 1: SchemaV2 with Category + Lightweight-via-Custom Migration

**What:** Add `SchemaV2` as a new `VersionedSchema` enum containing (a) a `Category` @Model and (b) a copy of `Expense` from SchemaV1 with one new field: `var categories: [SchemaV2.Category] = []`. Register a V1→V2 `MigrationStage.custom(willMigrate: nil, didMigrate: nil)` — this is semantically a no-op custom migration, which is the safest form for additive changes given known SchemaMigrationPlan interaction bugs in early iOS 17 builds. [CITED: developer.apple.com/forums/thread/740243]

**When to use:** Any additive schema change that adds a new entity or a new optional relationship.

```swift
// SchemaV2.swift
// Source: Apple WWDC23 "Model your schema with SwiftData" + established project pattern
enum SchemaV2: VersionedSchema {
    static let versionIdentifier = Schema.Version(2, 0, 0)

    static var models: [any PersistentModel.Type] {
        [SchemaV2.Expense.self, SchemaV2.Category.self]
    }

    // Category @Model — CloudKit-readiness rules applied (FND-03, ARCHITECTURE.md)
    @Model
    final class Category {
        var id: UUID = UUID()                    // rule 1: own UUID PK
        var name: String? = nil                  // rule 2: optional/defaulted
        var symbolName: String? = nil            // SF Symbol name, e.g. "cart"
        var sortOrder: Int = 0                   // for predefined list ordering
        var monthlyBudget: Decimal? = nil        // nil = no budget (D2-06)
        var currencyCode: String = "INR"
        var createdAt: Date = Date()

        // Inverse side of the to-many relationship (rule 4)
        @Relationship(deleteRule: .nullify, inverse: \SchemaV2.Expense.categories)
        var expenses: [SchemaV2.Expense] = []

        init(name: String, symbolName: String?, sortOrder: Int = 0) {
            self.id = UUID()
            self.name = name
            self.symbolName = symbolName
            self.sortOrder = sortOrder
            self.createdAt = Date()
        }
    }

    // Expense @Model — copy of SchemaV1.Expense + categories relationship
    @Model
    final class Expense {
        var id: UUID = UUID()
        var amount: Decimal = Decimal(0)
        var currencyCode: String = "INR"
        var date: Date = Date()
        var note: String? = nil
        var createdAt: Date = Date()
        var updatedAt: Date = Date()

        // NEW in V2: optional to-many relationship to Category (D2-02, CloudKit rule 4)
        // Single-select in v1 UI; schema supports multiple without future migration.
        @Relationship(deleteRule: .nullify, inverse: \SchemaV2.Category.expenses)
        var categories: [SchemaV2.Category] = []

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
}
```

```swift
// MigrationPlan.swift — updated
enum AppMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [SchemaV1.self, SchemaV2.self]
    }

    // Use .custom(willMigrate: nil, didMigrate: nil) instead of .lightweight
    // to sidestep the iOS 17 SchemaMigrationPlan interaction bug (FB13812722).
    // Semantically identical for additive-only changes.
    static var stages: [MigrationStage] {
        [v1ToV2]
    }

    static let v1ToV2 = MigrationStage.custom(
        fromVersion: SchemaV1.self,
        toVersion: SchemaV2.self,
        willMigrate: nil,
        didMigrate: nil
    )
}
```

```swift
// Models/Expense.swift — typealias flip
typealias Expense = SchemaV2.Expense

// Models/Category.swift — new typealias
typealias Category = SchemaV2.Category
```

```swift
// ModelContainer+App.swift — Schema wiring update
let schema = Schema(versionedSchema: SchemaV2.self)
// ... rest unchanged (same storeURL, cloudKitDatabase: .none)
// After container init, call: try seedCategoriesIfNeeded(context: container.mainContext)
```

### Pattern 2: Idempotent Category Seeding

**What:** On first launch (and only on first launch), insert the 14 predefined categories. Use `FetchDescriptor<Category>(fetchLimit: 1)` to check for emptiness before inserting — fast, idempotent, survives migration reruns. [CITED: andrewcbancroft.com/blog/ios-development/data-persistence/pre-populate-swiftdata-persistent-store/]

**When to use:** Any predefined-data seeding that must not duplicate on subsequent launches.

```swift
// Called once in ModelContainer+App.swift after container creation
// Source: Andrew Bancroft seeding pattern + Apple FetchDescriptor docs
@MainActor
func seedCategoriesIfNeeded(context: ModelContext) throws {
    var descriptor = FetchDescriptor<Category>()
    descriptor.fetchLimit = 1
    let existing = try context.fetch(descriptor)
    guard existing.isEmpty else { return }  // already seeded

    let predefined: [(name: String, symbol: String, order: Int)] = [
        ("Groceries",      "cart",                    0),
        ("Dining",         "fork.knife",              1),
        ("Fuel",           "fuelpump",                2),
        ("Utilities",      "bolt",                    3),
        ("Rent",           "house",                   4),
        ("Auto/Cab",       "car",                     5),
        ("Shopping",       "bag",                     6),
        ("Health/Pharmacy","cross.case",              7),
        ("Entertainment",  "film",                    8),
        ("Recharge/DTH",   "antenna.radiowaves.left.and.right", 9),
        ("Maid/Help",      "person.2",               10),
        ("UPI to Person",  "arrow.up.right",         11),
        ("ATM",            "banknote",               12),
        ("Misc",           "tray",                   13),
    ]

    // Batch insert — avoid repeated single-append (30× perf difference per fatbobman)
    let categories = predefined.map { Category(name: $0.name, symbolName: $0.symbol, sortOrder: $0.order) }
    categories.forEach { context.insert($0) }
    try context.save()
}
```

### Pattern 3: Month-Scoped Aggregation (In-Memory)

**What:** Pre-compute `startOfMonth` and `endOfMonth` as `let` constants outside `#Predicate` (date expressions inside predicates are unsupported). Fetch all expenses in the month with a FetchDescriptor. Group and sum in-memory. [CITED: developer.apple.com/documentation/swiftdata/filtering-and-sorting-persistent-data]

**When to use:** Any per-category or per-month spend calculation. Do NOT attempt SQL-style aggregation through `#Predicate` — SwiftData does not support it.

```swift
// Source: Apple FetchDescriptor docs + established #Predicate limitation workaround
struct BudgetCalculator {
    // Returns a dict: category.persistentModelID -> total spend for the viewed month
    static func monthlySpend(
        for expenses: [Expense],  // already fetched from @Query for the month
        categories: [Category]
    ) -> [PersistentIdentifier: Decimal] {
        var totals: [PersistentIdentifier: Decimal] = [:]
        for expense in expenses {
            // v1 UI: single category (use first); schema supports multiple
            if let category = expense.categories.first {
                let key = category.persistentModelID
                totals[key, default: .zero] += expense.amount
            }
            // Uncategorized expenses (expense.categories.isEmpty) are ignored per-budget
            // but must be counted in a separate "Uncategorized" bucket (D2-08)
        }
        return totals
    }

    // Date boundary helper — must be computed OUTSIDE #Predicate
    static func monthBoundaries(for month: DateComponents) -> (start: Date, end: Date)? {
        let cal = Calendar.current
        guard let start = cal.date(from: month),
              let end = cal.date(byAdding: DateComponents(month: 1, second: -1), to: start)
        else { return nil }
        return (start, end)
    }
}
```

```swift
// @Query for the viewed month in BudgetsView
// Source: Pitfall 3 — capture constants OUTSIDE #Predicate
private func makeMonthQuery(start: Date, end: Date) -> Query<Expense, [Expense]> {
    // Pre-computed constants captured into the predicate closure
    let lo = start
    let hi = end
    return Query(
        filter: #Predicate<Expense> { expense in
            expense.date >= lo && expense.date <= hi
        },
        sort: \.date, order: .reverse
    )
}
```

### Pattern 4: Filtering Expenses by Category (persistentModelID workaround)

**What:** SwiftData predicates cannot reference a related entity object directly — use `persistentModelID` comparison instead. [CITED: simplykyra.com/blog/swiftdata-problems-with-filtering-by-entity-in-the-predicate/]

**When to use:** `FilteredExpenseListView` tap-through — show only expenses for a specific category in the tapped month.

```swift
// Source: simplykyra.com workaround for SwiftData relationship predicate limitation
struct FilteredExpenseListView: View {
    let category: Category
    let start: Date
    let end: Date

    // Use persistentModelID — not the Category object directly
    @Query private var expenses: [Expense]

    init(category: Category, start: Date, end: Date) {
        self.category = category
        self.start = start
        self.end = end

        let categoryID = category.persistentModelID
        let lo = start
        let hi = end
        _expenses = Query(
            filter: #Predicate<Expense> { expense in
                expense.date >= lo && expense.date <= hi
                && expense.categories.contains(where: { $0.persistentModelID == categoryID })
            },
            sort: \.date, order: .reverse
        )
    }
    // ...
}
```

> **Warning:** Relationship-contains predicates in SwiftData are known to be fragile ("very buggy and limited" per official Apple forums thread 731655). If the predicate fails at runtime, fall back to the in-memory filter: fetch all month expenses, then `.filter { $0.categories.contains(where: { $0.id == category.id }) }`. [ASSUMED: the `contains(where:)` predicate on a to-many relationship compiles and runs correctly on iOS 17.4+]

### Pattern 5: TabView Shell Introduction

**What:** Replace `RootView` body with a `TabView` containing two tabs. Each tab owns its own `NavigationStack`. Phase 1 `ExpenseListView` requires no changes other than being embedded as tab 1. [ASSUMED: standard SwiftUI TabView + NavigationStack per-tab pattern]

```swift
// RootView.swift — updated
// Source: ARCHITECTURE.md TabView pattern + Apple HIG tab navigation
struct RootView: View {
    var body: some View {
        TabView {
            ExpenseListView()
                .tabItem {
                    Label("Expenses", systemImage: "list.bullet")
                }

            BudgetsView()
                .tabItem {
                    Label("Budgets", systemImage: "chart.bar")
                }
        }
    }
}
```

### Anti-Patterns to Avoid

- **Hand-rolling migration**: Never edit `SchemaV1.swift`. Always add a new `SchemaV2`. The `SchemaV1.Expense` is the immutable ground truth; `SchemaV2.Expense` is a copy with additions.
- **`#Predicate` with `Date()` inline**: `Date()` is non-deterministic inside a predicate — SwiftData rejects it at runtime. Always capture start/end dates as `let` constants before the predicate closure.
- **`#Predicate` with `Decimal` aggregation**: No SQL `SUM()` exists in `#Predicate`. Aggregate in Swift after fetching.
- **Comparing relationship objects in `#Predicate`**: Use `persistentModelID` comparison, not the object itself.
- **Repeated single-append to to-many array**: Use `append(contentsOf:)` for batch inserts; single appends are 30× slower (relevant for seeding and any bulk operations).
- **Seeding without empty check**: Always gate seeding on `FetchDescriptor(fetchLimit: 1)` result being empty — never assume the store is fresh.
- **`@StateObject`/`@ObservedObject`/`@Published` anywhere**: Use `@Observable`/`@State`/`@Bindable` only (Pitfall 10 / established project constraint).

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| SwiftData schema migration | Manual SQLite ALTER TABLE | `VersionedSchema` + `SchemaMigrationPlan` | Handles WAL journal, schema version tracking, rollback; hand-rolling corrupts stores |
| Month boundary math | Custom date-string parsing | `Calendar.current.date(from:)` + `date(byAdding:)` | Calendar correctly handles month lengths, DST, leap years |
| INR currency formatting | String(format: "₹%.2f", ...) | `Decimal.formattedINR()` (already exists in `Decimal+INR.swift`) | Handles lakh grouping, correct sign placement; already tested |
| Budget entry keypad | System TextField with numeric keyboard | Existing `DecimalKeypadView` | Already built and tested; avoids keyboard avoidance layout thrash (Pitfall 6) |
| Progress bar | UIProgressView or third-party | Plain `GeometryReader` + `Rectangle` overlay in SwiftUI | Phase 1 UI-SPEC requires system-only components; no third-party |
| Category uniqueness enforcement | `@Attribute(.unique)` | Lookup-before-insert (fetch by name, insert only if not found) | `.unique` is incompatible with CloudKit (ARCHITECTURE.md rule 3) |

**Key insight:** SwiftData already IS the repository for this app. Never wrap it in an additional abstraction layer — that breaks `@Query` live updates and defeats the point of SwiftData's observation model.

---

## Common Pitfalls

### Pitfall P2-01: Mutating SchemaV1

**What goes wrong:** Developer edits `SchemaV1.Expense` to add the category relationship instead of creating `SchemaV2`. The migration plan has no basis for inference; the on-device store fails to open; all expenses disappear.

**Why it happens:** It appears to work in the simulator when installing a fresh build (no existing store), but fails silently on the device where a v1 store exists.

**How to avoid:** Rule: `SchemaV1.swift` is append-only after Phase 1 shipped. The comment at lines 40-42 marks the *insertion point documentation*, not permission to edit. Create `SchemaV2.swift` as a new enum.

**Warning signs:** SchemaV1 has more than the original 7 properties.

### Pitfall P2-02: `#Predicate` with date expressions or relationship objects

**What goes wrong:** `#Predicate { $0.date >= Date() }` crashes at runtime ("unsupported predicate"). `#Predicate { $0.categories.first?.name == "Groceries" }` causes compiler timeout.

**Why it happens:** `#Predicate` lowers to Core Data `NSPredicate`; `Date()` is non-deterministic; relationship-object comparison has no NSPredicate representation (Pitfall 3 in PITFALLS.md).

**How to avoid:**
1. Always capture date boundaries as `let lo = start; let hi = end` before the predicate closure.
2. Use `persistentModelID` for relationship filtering.
3. When in doubt about predicate support, fall back to in-memory filter after fetch.

**Warning signs:** `_PFPredicateBridge` or "unsupported expression" in crash logs.

### Pitfall P2-03: Seeding races / duplicate categories on reinstall

**What goes wrong:** The seed function is called without checking if categories already exist — reinstalling the app (or a migration that runs `didMigrate`) re-seeds all 14 categories, creating duplicates.

**Why it happens:** Reinstall on iOS does NOT wipe the SwiftData store if the App Group URL is used (the store survives reinstall via the App Group container). [ASSUMED: this behavior is consistent on current iOS versions]

**How to avoid:** Always gate seeding on `FetchDescriptor<Category>(fetchLimit: 1)` returning empty. A count of 1 means "already seeded — skip".

**Warning signs:** Category list shows "Groceries, Groceries, Groceries..." after reinstall.

### Pitfall P2-04: SchemaMigrationPlan interaction bug on early iOS 17

**What goes wrong:** On iOS 17.0–17.3 devices, providing a `SchemaMigrationPlan` with a `.lightweight` stage for additive changes caused a fatal crash at container initialization ("could not fetch ModelContainer" or "Expected only Arrays for Relationships"). [CITED: developer.apple.com/forums/thread/740243]

**Why it happens:** A SwiftData bug (FB13812722, partially fixed in 17.4, more in iOS 18) where the migration plan validation code conflates lightweight and custom stage semantics when a new model is added.

**How to avoid:** Use `MigrationStage.custom(fromVersion:toVersion:willMigrate:nil, didMigrate:nil)` instead of `.lightweight` for the V1→V2 stage. Semantically identical for additive-only changes, but bypasses the buggy validation path.

**Warning signs:** App crashes immediately on first launch after update on a device running iOS 17.x.

### Pitfall P2-05: UTC date boundary miscalculation for "this month"

**What goes wrong:** Developer uses `Calendar.current.dateInterval(of: .month, for: Date())` and stores the start as the beginning of the day in the user's timezone, but `expense.date` is stored in UTC. Expenses at 11:30 PM IST (which is 6:00 PM UTC the SAME DAY) appear in the wrong month's aggregation.

**Why it happens:** `expense.date` is stored as UTC. Calendar month boundaries computed in the user's timezone don't align with UTC midnight. (PITFALLS.md — Pitfall 3 / UTC dates.)

**How to avoid:** Compute month boundaries using `Calendar(identifier: .gregorian)` with `timeZone = .current` to get the correct local-timezone boundaries, then pass those `Date` values (which internally are UTC) to the predicate. The `Date` type is always UTC-absolute; comparison is unambiguous once boundaries are correctly computed.

```swift
// Correct: boundaries in user's timezone, compared as absolute UTC instants
var cal = Calendar.current  // user's locale + timezone
cal.timeZone = TimeZone.current
let startOfMonth = cal.date(from: DateComponents(year: year, month: month, day: 1))!
let endOfMonth = cal.date(byAdding: DateComponents(month: 1, second: -1), to: startOfMonth)!
// Now use startOfMonth and endOfMonth in #Predicate — they are absolute Date values
```

### Pitfall P2-06: Categories with `@Attribute(.unique)` on name

**What goes wrong:** Developer adds `@Attribute(.unique) var name: String` to prevent duplicate category names. This works locally but breaks when CloudKit is enabled (ARCHITECTURE.md rule 3).

**Why it happens:** CloudKit does not support uniqueness constraints on synced fields.

**How to avoid:** Enforce uniqueness in application code: before inserting a new category, fetch with `#Predicate { $0.name == newName }` and only insert if count == 0.

**Warning signs:** `@Attribute(.unique)` anywhere in `SchemaV2.Category`.

---

## Code Examples

### Month paging state in BudgetsView

```swift
// Source: Foundation Calendar pattern (established project convention)
// BudgetsView.swift
@State private var viewedMonth: DateComponents = {
    let now = Date()
    let cal = Calendar.current
    return cal.dateComponents([.year, .month], from: now)
}()

// Month navigation
private func previousMonth() {
    guard let date = Calendar.current.date(from: viewedMonth),
          let prev = Calendar.current.date(byAdding: .month, value: -1, to: date)
    else { return }
    viewedMonth = Calendar.current.dateComponents([.year, .month], from: prev)
}

private func nextMonth() {
    guard let date = Calendar.current.date(from: viewedMonth),
          let next = Calendar.current.date(byAdding: .month, value: 1, to: date)
    else { return }
    viewedMonth = Calendar.current.dateComponents([.year, .month], from: next)
}
```

### Budget progress computation

```swift
// Source: established Decimal+INR pattern + in-memory aggregation approach
struct BudgetProgressData {
    let category: Category
    let spent: Decimal       // sum of expense.amount for the viewed month (negative = refund reduces spend)
    let budget: Decimal?     // nil = no budget set

    var remaining: Decimal? {
        guard let b = budget else { return nil }
        return b - spent
    }

    var fractionUsed: Double? {
        guard let b = budget, b > 0 else { return nil }
        return Double(truncating: (spent / b) as NSDecimalNumber)
    }

    var colorThreshold: BudgetColor {
        guard let f = fractionUsed else { return .normal }
        if f >= 1.0 { return .overBudget }
        if f >= 0.8 { return .warning }
        return .normal
    }
}

enum BudgetColor {
    case normal      // .accentColor (systemIndigo, Phase 1 design system)
    case warning     // Color(.systemOrange)
    case overBudget  // Color(.systemRed)
}
```

### Category picker (for add/edit flow)

```swift
// Source: established @Bindable + sheet pattern from EditExpenseView
// CategoryPickerView.swift — reusable by both AddExpenseView and EditExpenseView
struct CategoryPickerView: View {
    @Binding var selectedCategory: Category?
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Category.sortOrder) private var categories: [Category]

    var body: some View {
        NavigationStack {
            List(categories) { category in
                Button(action: {
                    selectedCategory = category
                    dismiss()
                }) {
                    HStack {
                        if let symbol = category.symbolName {
                            Image(systemName: symbol)
                                .frame(width: 24)
                        }
                        Text(category.name ?? "")
                        Spacer()
                        if selectedCategory?.persistentModelID == category.persistentModelID {
                            Image(systemName: "checkmark")
                                .foregroundStyle(.accentColor)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
            .navigationTitle("Category")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                if selectedCategory != nil {
                    ToolbarItem(placement: .destructiveAction) {
                        Button("Clear") {
                            selectedCategory = nil
                            dismiss()
                        }
                    }
                }
            }
        }
    }
}
```

---

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| `@Published` + `ObservableObject` | `@Observable` + `@State`/`@Bindable` | iOS 17 / Swift 5.9 | Project already uses the new approach; no change needed |
| Core Data `NSPredicate` strings | SwiftData `#Predicate` macro | iOS 17 | Compile-time checked but has runtime limitations for relationships and date expressions |
| `NSFetchedResultsController` | `@Query` in views | iOS 17 | Project already uses `@Query`; no change needed |
| `NSManagedObject` migration | `VersionedSchema` + `SchemaMigrationPlan` | iOS 17 | Existing scaffold already in place |

**Deprecated/outdated:**
- `@StateObject` / `@ObservedObject` / `@Published`: not used in this project (enforced by Pitfall 10 constraint); must not be introduced in Phase 2.
- `Set<>` for to-many relationships: SwiftData requires `Array<>` — this is a SwiftData-specific requirement, not a choice.

---

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | `MigrationStage.custom(willMigrate: nil, didMigrate: nil)` is semantically identical to `.lightweight` for additive-only changes (new entity, new optional relationship) | Pattern 1 | If false, a custom stage with nil closures is rejected — fall back to `.lightweight` and test on iOS 17.4+ device |
| A2 | The App Group container survives iOS reinstall (store file persists), so seeding must be idempotent even after reinstall | Pitfall P2-03 | If false, seeding is less critical — but idempotent seed is still correct behavior |
| A3 | `expense.categories.contains(where: { $0.persistentModelID == categoryID })` compiles and runs correctly in `#Predicate` on iOS 17.4+ | Pattern 4 | If false (relationship-contains predicates fail), use in-memory filter after fetching all month expenses |
| A4 | TabView + per-tab NavigationStack is the correct pattern (each tab maintains independent navigation state) | Pattern 5 | If wrong: shared NavigationPath causes tab-to-tab navigation conflicts — easy to fix but requires RootView refactor |
| A5 | `Category.sortOrder: Int` is sufficient for predefined-list ordering; no UUID-stable ordering mechanism needed | Pattern 2 (seed data) | Low risk — sort is stable and user-visible order matches sortOrder field |

**If this table is empty:** All claims were verified — it is not empty; 5 assumptions are logged above.

---

## Open Questions

1. **Does the relationship-contains `#Predicate` work reliably on iOS 17.4+ for the `FilteredExpenseListView`?**
   - What we know: SwiftData relationship filtering is documented as "very buggy and limited" (Apple forums thread 731655). The `persistentModelID` comparison workaround is confirmed for to-one relationships (simplykyra.com). Its behavior for `contains(where:)` on a to-many is not confirmed in the research sources.
   - What's unclear: Whether `$0.categories.contains(where: { $0.persistentModelID == categoryID })` survives runtime on the target iOS version.
   - Recommendation: Implement with the `#Predicate` approach first. If runtime crashes occur, the planner should add an explicit task: "replace with in-memory filter after fetching month expenses". This fallback has zero performance impact at household data volumes.

2. **Category picker UX: sheet vs. menu vs. inline navigation row?**
   - What we know: The project uses sheet-based forms exclusively in Phase 1. D2-12 says "reuse existing sheet/`@Bindable` patterns". Menu (`.confirmationDialog`) is lightweight but shows no SF Symbol alongside names.
   - What's unclear: Which affordance best fits the Phase 2 UI-SPEC (to be authored).
   - Recommendation: Default to a sheet-presented `CategoryPickerView` (consistent with Phase 1 pattern). The UI-SPEC author can refine to a `.menu` or inline `picker(.navigationLink)` if preferred.

3. **Should the Budgets tab @Query use `@State`-driven dynamic query or a static query with view redraw?**
   - What we know: `@Query` in SwiftUI does not support a dynamically-changing predicate via a stored property — the workaround is to use a child view initialized with the predicate parameters (so the `_query` init runs fresh on month change).
   - Recommendation: Create a `BudgetsMonthView(start: Date, end: Date)` sub-view that owns the `@Query` and is reconstructed when `viewedMonth` changes in the parent. This is the established SwiftData dynamic-query pattern.

---

## Environment Availability

Step 2.6: Skipped. Phase 2 is a pure code change within an existing Xcode project. No new external dependencies (CLI tools, services, databases, runtimes) are introduced. All tooling (Xcode 26.5, Swift 6.2, iPhone 17 simulator) is confirmed available per project memory.

---

## Validation Architecture

> `workflow.nyquist_validation` = true in config.json — section included.

### Test Framework

| Property | Value |
|----------|-------|
| Framework | Swift Testing (bundled in Swift 6.2 toolchain, Xcode 26) |
| Config file | Xcode Test Plan (no external config file) |
| Test target | MyHomeTests |
| Quick run command | `xcodebuild test -scheme MyHome -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing MyHomeTests 2>&1 \| tail -20` |
| Full suite command | `xcodebuild test -scheme MyHome -destination 'platform=iOS Simulator,name=iPhone 17' 2>&1 \| tail -30` |

**Existing test infrastructure:** `ExpenseModelTests.swift` + `MigrationTests.swift` + `MyHomeV1Seed.store` bundled resource. All tests use `ModelConfiguration(isStoredInMemoryOnly: true)` except `MigrationTests` which uses the bundled store.

### Phase Requirements → Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| EXP-04 | 14 predefined categories seeded on empty store | Unit | `xcodebuild test -only-testing MyHomeTests/CategorySeedTests` | ❌ Wave 0 |
| EXP-04 | Seeding is idempotent (no duplicates on second run) | Unit | `xcodebuild test -only-testing MyHomeTests/CategorySeedTests/seedIsIdempotent` | ❌ Wave 0 |
| EXP-05 | Category can be added, renamed, deleted | Unit | `xcodebuild test -only-testing MyHomeTests/CategoryCRUDTests` | ❌ Wave 0 |
| EXP-05 | Deleting a category nullifies expense.categories | Unit | `xcodebuild test -only-testing MyHomeTests/CategoryCRUDTests/deleteNullifiesExpenseLink` | ❌ Wave 0 |
| EXP-06 | Expense can have category assigned and cleared | Unit | `xcodebuild test -only-testing MyHomeTests/ExpenseCategoryTests` | ❌ Wave 0 |
| EXP-07 | monthlyBudget stores and retrieves Decimal correctly | Unit | `xcodebuild test -only-testing MyHomeTests/BudgetModelTests` | ❌ Wave 0 |
| EXP-08 | BudgetProgressData computes fraction, remaining, color threshold correctly | Unit | `xcodebuild test -only-testing MyHomeTests/BudgetCalculatorTests` | ❌ Wave 0 |
| EXP-08 | Color threshold: <80% = .normal, 80-99% = .warning, ≥100% = .overBudget | Unit | `xcodebuild test -only-testing MyHomeTests/BudgetCalculatorTests/colorThresholds` | ❌ Wave 0 |
| EXP-09 | Month-scoped aggregation groups expenses correctly by category | Unit | `xcodebuild test -only-testing MyHomeTests/BudgetCalculatorTests/monthlyAggregation` | ❌ Wave 0 |
| EXP-09 | Uncategorized expenses appear in separate bucket (not counted against any budget) | Unit | `xcodebuild test -only-testing MyHomeTests/BudgetCalculatorTests/uncategorizedBucket` | ❌ Wave 0 |
| Migration | V1 store opens cleanly under SchemaV2 + AppMigrationPlan | Integration | `xcodebuild test -only-testing MyHomeTests/MigrationTests` | ✅ exists (needs SchemaV2 update) |
| Migration | V1 expense is readable post-V2 migration (amount, note, date intact) | Integration | `xcodebuild test -only-testing MyHomeTests/MigrationTests/v1StoreMigratesCleanly` | ✅ (update needed) |

### Sampling Rate

- **Per task commit:** `xcodebuild test -only-testing MyHomeTests/CategorySeedTests -only-testing MyHomeTests/BudgetCalculatorTests ...` (relevant unit tests for the task)
- **Per wave merge:** Full suite — `xcodebuild test -scheme MyHome -destination 'platform=iOS Simulator,name=iPhone 17'`
- **Phase gate:** Full suite green before `/gsd-verify-work`

### Wave 0 Gaps

The following test files must be created before implementation begins:

- [ ] `MyHomeTests/CategorySeedTests.swift` — covers EXP-04 (seeding, idempotency)
- [ ] `MyHomeTests/CategoryCRUDTests.swift` — covers EXP-05 (add/rename/delete, nullify cascade)
- [ ] `MyHomeTests/ExpenseCategoryTests.swift` — covers EXP-06 (attach/clear category on expense)
- [ ] `MyHomeTests/BudgetModelTests.swift` — covers EXP-07 (monthlyBudget field storage)
- [ ] `MyHomeTests/BudgetCalculatorTests.swift` — covers EXP-08 + EXP-09 (aggregation, color thresholds, uncategorized bucket)
- [ ] Update `MyHomeTests/MigrationTests.swift` — update schema reference from SchemaV1 to SchemaV2; existing `MyHomeV1Seed.store` remains valid (migration test still opens the v1 store and migrates it forward)

All test files use the existing `ModelConfiguration(isStoredInMemoryOnly: true)` pattern (FND-06, Pitfall 16). `BudgetCalculatorTests` can be pure Swift tests requiring no ModelContainer (pure function tests on `BudgetProgressData` and `BudgetCalculator`).

---

## Security Domain

> `security_enforcement` = true, `security_asvs_level` = 1 in config.json.

### Applicable ASVS Categories

| ASVS Category | Applies | Standard Control |
|---------------|---------|-----------------|
| V2 Authentication | no | No new auth in Phase 2 |
| V3 Session Management | no | No sessions |
| V4 Access Control | no | Single-user household app; no role distinctions |
| V5 Input Validation | yes (category name, budget amount) | Same pattern as expense amount: non-empty name trim, `abs(budget) < 1_000_000_000` guard, `Decimal` not `Double` |
| V6 Cryptography | no | No new secrets or encrypted storage |

### Known Threat Patterns for SwiftUI + SwiftData

| Pattern | STRIDE | Standard Mitigation |
|---------|--------|---------------------|
| Category name injection into UI display | Spoofing/Tampering | Plain `Text(category.name ?? "")` — never `AttributedString(markdown:)`; consistent with T-01-06 from Phase 1 |
| Budget amount overflow/NaN via Decimal | Tampering | Same guard as expense amount: `abs(amount) < Decimal(1_000_000_000)` + reject nil/zero |
| Duplicate category insert (no `.unique`) | Tampering | Lookup-before-insert: fetch by name before creating; show error if name already exists |
| Seeding race on cold launch | Tampering | Idempotent seed with `FetchDescriptor(fetchLimit:1)` empty-check before insert |

---

## Sources

### Primary (HIGH confidence)
- Apple Developer — WWDC23 "Model your schema with SwiftData" (video 10195) — VersionedSchema, MigrationStage patterns [CITED]
- Apple Developer — SwiftData `FetchDescriptor` documentation — predicate, fetchLimit patterns [CITED]
- Apple Developer — SwiftData Relationship macro documentation — inverse, deleteRule parameters [CITED]
- Project file: `.planning/research/ARCHITECTURE.md` — 8 CloudKit-readiness rules, schema patterns [VERIFIED: codebase]
- Project file: `.planning/research/PITFALLS.md` — Pitfall 1, 3, 7, 10, 17 directly applicable [VERIFIED: codebase]
- Project file: `MyHomeApp/Persistence/Schema/SchemaV1.swift` — exact Phase 2 insertion point [VERIFIED: codebase]
- Project file: `MyHomeApp/Persistence/Schema/MigrationPlan.swift` — exact append point [VERIFIED: codebase]

### Secondary (MEDIUM confidence)
- fatbobman.com — "Relationships in SwiftData: Changes and Considerations" — Array requirement, 30× performance difference for single vs batch appends [CITED]
- fatbobman.com — "Designing Models for CloudKit Sync" — CloudKit relationship rules confirmation [CITED]
- andrewcbancroft.com — "Pre-populate a SwiftData Persistent Store" — FetchDescriptor(fetchLimit:1) empty-check seeding pattern [CITED]
- simplykyra.com — "SwiftData: Solving Filtering by an Entity in the Predicate" — persistentModelID workaround for relationship filtering [CITED]
- donnywals.com — "A Deep Dive into SwiftData migrations" — lightweight migration rules, `.custom` stage syntax [CITED]

### Tertiary (LOW confidence — flagged as [ASSUMED])
- Apple Developer Forums thread/740243 — SchemaMigrationPlan + lightweight stage interaction bug (iOS 17.0–17.3); `custom(willMigrate:nil, didMigrate:nil)` workaround [CITED: forum post, LOW — forum workaround, not official docs]
- Apple Developer Forums thread/731655 — "SwiftData query relationships not..." — to-many contains-predicate fragility [CITED: forum post, LOW]

---

## Metadata

**Confidence breakdown:**
- SchemaV2 structure and migration pattern: HIGH — well-documented VersionedSchema pattern, confirmed in official WWDC session
- CloudKit relationship rules: HIGH — confirmed via fatbobman.com + ARCHITECTURE.md project research
- Idempotent seeding: HIGH — confirmed pattern via andrewcbancroft.com + Apple FetchDescriptor docs
- In-memory aggregation approach: HIGH — established workaround for known #Predicate limitations
- Migration stage bug mitigation: MEDIUM — based on forum report (FB13812722), not official docs; custom-nil stage is a reasonable workaround but unverified against all iOS versions
- to-many `contains(where:)` in #Predicate: LOW — relationship predicate support in SwiftData is documented as fragile; in-memory fallback is the safe path

**Research date:** 2026-05-29
**Valid until:** 2026-08-29 (stable Apple API; 90 days)
