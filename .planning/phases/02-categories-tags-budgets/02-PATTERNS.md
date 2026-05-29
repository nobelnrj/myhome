# Phase 2: Categories, Tags & Budgets — Pattern Map

**Mapped:** 2026-05-29
**Files analyzed:** 20 (new + modified)
**Analogs found:** 20 / 20

---

## File Classification

| New/Modified File | Role | Data Flow | Closest Analog | Match Quality |
|-------------------|------|-----------|----------------|---------------|
| `MyHomeApp/Persistence/Schema/SchemaV2.swift` | model | CRUD | `SchemaV1.swift` | exact |
| `MyHomeApp/Persistence/Schema/MigrationPlan.swift` (update) | config | batch | `MigrationPlan.swift` (self) | exact |
| `MyHomeApp/Persistence/Models/Expense.swift` (typealias flip) | config | — | `Expense.swift` (self) | exact |
| `MyHomeApp/Persistence/Models/Category.swift` | config | — | `Expense.swift` | exact |
| `MyHomeApp/Persistence/ModelContainer+App.swift` (update) | config | batch | `ModelContainer+App.swift` (self) | exact |
| `MyHomeApp/RootView.swift` (update) | component | request-response | `RootView.swift` (self) | exact |
| `MyHomeApp/Features/Expenses/AddExpenseView.swift` (update) | component | request-response | `AddExpenseView.swift` (self) | exact |
| `MyHomeApp/Features/Expenses/EditExpenseView.swift` (update) | component | request-response | `EditExpenseView.swift` (self) | exact |
| `MyHomeApp/Features/Expenses/CategoryPickerView.swift` | component | request-response | `EditExpenseView.swift` | role-match |
| `MyHomeApp/Features/Budgets/BudgetsView.swift` | component | CRUD | `ExpenseListView.swift` | role-match |
| `MyHomeApp/Features/Budgets/BudgetCategoryCard.swift` | component | request-response | `ExpenseRow.swift` | role-match |
| `MyHomeApp/Features/Budgets/BudgetProgressView.swift` | component | transform | `ExpenseRow.swift` | role-match |
| `MyHomeApp/Features/Budgets/FilteredExpenseListView.swift` | component | CRUD | `ExpenseListView.swift` | role-match |
| `MyHomeApp/Features/Budgets/ManageCategoriesView.swift` | component | CRUD | `ExpenseListView.swift` + `EditExpenseView.swift` | role-match |
| `MyHomeApp/Features/Budgets/EditBudgetSheet.swift` | component | request-response | `EditExpenseView.swift` | exact |
| `MyHomeApp/Support/BudgetCalculator.swift` | utility | transform | `Decimal+INR.swift` | role-match |
| `MyHomeApp/Support/Date+Display.swift` (update) | utility | transform | `Date+Display.swift` (self) | exact |
| `MyHomeTests/CategorySeedTests.swift` | test | batch | `ExpenseModelTests.swift` | exact |
| `MyHomeTests/CategoryCRUDTests.swift` | test | CRUD | `ExpenseModelTests.swift` | exact |
| `MyHomeTests/BudgetCalculatorTests.swift` | test | transform | `ExpenseModelTests.swift` | exact |
| `MyHomeTests/MigrationTests.swift` (update) | test | batch | `MigrationTests.swift` (self) | exact |

---

## Pattern Assignments

---

### `MyHomeApp/Persistence/Schema/SchemaV2.swift` (model, CRUD)

**Analog:** `MyHomeApp/Persistence/Schema/SchemaV1.swift`

**Imports pattern** (lines 1–3):
```swift
import SwiftData
import Foundation
```

**VersionedSchema enum shell** (lines 19–24):
```swift
enum SchemaV1: VersionedSchema {
    static let versionIdentifier = Schema.Version(1, 0, 0)

    static var models: [any PersistentModel.Type] {
        [SchemaV1.Expense.self]
    }
```
Copy this shell verbatim, rename to `SchemaV2`, bump version to `(2, 0, 0)`, list both `SchemaV2.Expense.self` and `SchemaV2.Category.self`.

**@Model field pattern — all fields optional or defaulted** (lines 29–38):
```swift
@Model
final class Expense {
    var id: UUID = UUID()
    var amount: Decimal = Decimal(0)        // never Double (Pitfall 17)
    var currencyCode: String = "INR"
    var date: Date = Date()
    var note: String? = nil
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
```
Apply the same rule to `Category`: every stored property either `= defaultValue` or `?: nil`. No stored enums. No `@Attribute(.unique)`.

**Relationship insertion point documented in SchemaV1** (lines 40–42):
```swift
    // Phase 2 will add:
    // @Relationship(deleteRule: .nullify, inverse: \Category.expenses)
    // var category: Category? = nil
```
In SchemaV2.Expense this becomes the live declaration (to-many, not to-one):
```swift
    @Relationship(deleteRule: .nullify, inverse: \SchemaV2.Category.expenses)
    var categories: [SchemaV2.Category] = []
```
In SchemaV2.Category, the inverse side:
```swift
    @Relationship(deleteRule: .nullify, inverse: \SchemaV2.Expense.categories)
    var expenses: [SchemaV2.Expense] = []
```
Both sides must declare `inverse:` explicitly — CloudKit readiness rule 4.

**init pattern** (lines 44–58):
```swift
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
```
Copy the same `init` shape for `Category`; parameters: `name: String, symbolName: String?, sortOrder: Int = 0`. Assign `self.createdAt = Date()` in body.

---

### `MyHomeApp/Persistence/Schema/MigrationPlan.swift` (config, batch) — update

**Analog:** `MyHomeApp/Persistence/Schema/MigrationPlan.swift` (self, lines 1–16)

**Full current file** (lines 1–16):
```swift
import SwiftData

enum AppMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [SchemaV1.self]
    }

    /// No stages — v1 is the initial version (D-08: forward-compat from day one).
    /// Phase 2 will add: .lightweight(fromVersion: SchemaV1.self, toVersion: SchemaV2.self) { ... }
    static var stages: [MigrationStage] { [] }
}
```

**After update — append SchemaV2 to schemas, add the V1→V2 stage:**
```swift
import SwiftData

enum AppMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [SchemaV1.self, SchemaV2.self]            // append SchemaV2 — never remove SchemaV1
    }

    static var stages: [MigrationStage] {
        [v1ToV2]
    }

    // Use .custom(willMigrate: nil, didMigrate: nil) rather than .lightweight
    // to sidestep iOS 17.0–17.3 SchemaMigrationPlan interaction bug (FB13812722).
    // Semantically identical for additive-only changes.
    static let v1ToV2 = MigrationStage.custom(
        fromVersion: SchemaV1.self,
        toVersion: SchemaV2.self,
        willMigrate: nil,
        didMigrate: nil
    )
}
```

---

### `MyHomeApp/Persistence/Models/Expense.swift` (config) — typealias flip

**Analog:** `MyHomeApp/Persistence/Models/Expense.swift` (self, lines 1–11)

**Current file** (lines 1–11):
```swift
import SwiftData

/// Convenience typealias so views and tests use bare `Expense` without the version prefix.
///
/// When Phase 2 introduces SchemaV2 with an updated Expense shape,
/// this typealias flips to `SchemaV2.Expense` in one line — no view changes needed.
///
/// Usage:
///   let expense = Expense(amount: Decimal(500), note: "Lunch")
///   @Query var expenses: [Expense]
typealias Expense = SchemaV1.Expense
```

**After flip — single line change:**
```swift
typealias Expense = SchemaV2.Expense
```
No other change. All views and tests that use `Expense` continue to compile unchanged.

---

### `MyHomeApp/Persistence/Models/Category.swift` (config) — new typealias

**Analog:** `MyHomeApp/Persistence/Models/Expense.swift` (lines 1–11)

Copy the docstring pattern verbatim, adjust for Category:
```swift
import SwiftData

/// Convenience typealias so views and tests use bare `Category` without the version prefix.
///
/// If a SchemaV3 renames or extends Category, flip this typealias in one line.
typealias Category = SchemaV2.Category
```

---

### `MyHomeApp/Persistence/ModelContainer+App.swift` (config, batch) — update

**Analog:** `MyHomeApp/Persistence/ModelContainer+App.swift` (self, lines 1–44)

**Schema init line** (line 17):
```swift
let schema = Schema(versionedSchema: SchemaV1.self)
```
**After update:**
```swift
let schema = Schema(versionedSchema: SchemaV2.self)
```

**ModelContainer init** (lines 38–43):
```swift
return try ModelContainer(
    for: schema,
    migrationPlan: AppMigrationPlan.self,
    configurations: [config]
)
```
This is unchanged structurally. After the container is created, call the seed function before returning:
```swift
let container = try ModelContainer(
    for: schema,
    migrationPlan: AppMigrationPlan.self,
    configurations: [config]
)
// Idempotent seed — runs once on first launch, no-op thereafter
try seedCategoriesIfNeeded(context: container.mainContext)
return container
```

**Seed function** — add as a file-level private function in the same file, below the extension:
```swift
@MainActor
private func seedCategoriesIfNeeded(context: ModelContext) throws {
    var descriptor = FetchDescriptor<Category>()
    descriptor.fetchLimit = 1
    let existing = try context.fetch(descriptor)
    guard existing.isEmpty else { return }   // already seeded — skip

    let predefined: [(name: String, symbol: String, order: Int)] = [
        ("Groceries",       "cart",                               0),
        ("Dining",          "fork.knife",                         1),
        ("Fuel",            "fuelpump",                           2),
        ("Utilities",       "bolt",                               3),
        ("Rent",            "house",                              4),
        ("Auto/Cab",        "car",                                5),
        ("Shopping",        "bag",                                6),
        ("Health/Pharmacy", "cross.case",                         7),
        ("Entertainment",   "film",                               8),
        ("Recharge/DTH",    "antenna.radiowaves.left.and.right",  9),
        ("Maid/Help",       "person.2",                          10),
        ("UPI to Person",   "arrow.up.right",                    11),
        ("ATM",             "banknote",                          12),
        ("Misc",            "tray",                              13),
    ]

    let categories = predefined.map {
        Category(name: $0.name, symbolName: $0.symbol, sortOrder: $0.order)
    }
    // Batch insert — append(contentsOf:) is 30× faster than single inserts in a loop
    categories.forEach { context.insert($0) }
    // CR-01: persist explicitly — financial/configuration write
    try context.save()
}
```

---

### `MyHomeApp/RootView.swift` (component, request-response) — update

**Analog:** `MyHomeApp/RootView.swift` (self, lines 1–9)

**Current file** (lines 1–9):
```swift
import SwiftUI

/// Root navigation host.
/// Wires to ExpenseListView which owns its own NavigationStack.
struct RootView: View {
    var body: some View {
        ExpenseListView()
    }
}
```

**After update — TabView with two independent NavigationStack tabs:**
```swift
import SwiftUI

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
`ExpenseListView` already owns its own `NavigationStack` (line 25 of `ExpenseListView.swift`). `BudgetsView` must also own its own `NavigationStack` internally. No shared navigation path.

---

### `MyHomeApp/Features/Expenses/AddExpenseView.swift` (component, request-response) — update

**Analog:** `MyHomeApp/Features/Expenses/AddExpenseView.swift` (self)

**Imports** (lines 1–3): unchanged — `import SwiftUI` + `import SwiftData`.

**@Environment + @State block** (lines 17–29):
```swift
@Environment(\.modelContext) private var context
@Environment(\.dismiss) private var dismiss

@State private var amountString: String = ""
@State private var isNegative: Bool = false
@State private var amountShakeOffset: CGFloat = 0
@State private var amountIsError: Bool = false

// Optional fields (Section 2 — off the ≤3-tap critical path)
@State private var date: Date = Date()
@State private var note: String = ""
@State private var showDatePicker: Bool = false
```
**Add one new @State property for the category picker:**
```swift
@State private var selectedCategory: Category? = nil
@State private var showCategoryPicker: Bool = false
```

**optionalSection computed var** (lines 116–171): add a Category row after the Date block and before the Note field, matching the Date-row style exactly:
```swift
// Category row (Section 2, optional — off the ≤3-tap critical path)
Button(action: { showCategoryPicker = true }) {
    HStack {
        Text("Category")
            .foregroundStyle(.primary)
        Spacer()
        if let cat = selectedCategory, let name = cat.name {
            if let symbol = cat.symbolName {
                Image(systemName: symbol)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Text(name)
                .foregroundStyle(.secondary)
                .font(.subheadline)
        } else {
            Text("None")
                .foregroundStyle(.secondary)
                .font(.subheadline)
        }
        Image(systemName: "chevron.right")
            .foregroundStyle(.secondary)
            .font(.caption)
    }
    .padding(.vertical, 12)
    .padding(.horizontal, 16)
    .frame(minHeight: 44)
}
.buttonStyle(.plain)
.background(Color(.secondarySystemBackground))
.clipShape(RoundedRectangle(cornerRadius: 12))
.padding(.top, 8)
.sheet(isPresented: $showCategoryPicker) {
    CategoryPickerView(selectedCategory: $selectedCategory)
}
```

**saveExpense() action** (lines 175–213): after creating the Expense, wire the category:
```swift
let expense = Expense(amount: amount, date: date, note: trimmedNote)
context.insert(expense)
if let cat = selectedCategory {
    expense.categories = [cat]   // v1 UI: single-select; schema supports multiple
}
// CR-01: persist explicitly (financial write)
try context.save()
```

---

### `MyHomeApp/Features/Expenses/EditExpenseView.swift` (component, request-response) — update

**Analog:** `MyHomeApp/Features/Expenses/EditExpenseView.swift` (self)

**@Bindable + @State block** (lines 16–28): unchanged structure. Add one new @State pair:
```swift
@State private var selectedCategory: Category? = nil
@State private var showCategoryPicker: Bool = false
```

**initializeFields()** (lines 216–234): add category initialization:
```swift
selectedCategory = expense.categories.first   // v1 UI: single-select
```

**optionalSection** (lines 142–196): add Category row in same position and with same styling as the AddExpenseView update above. `.sheet` presentation of `CategoryPickerView(selectedCategory: $selectedCategory)`.

**saveExpense()** (lines 236–264): apply category before save:
```swift
expense.categories = selectedCategory.map { [$0] } ?? []
expense.updatedAt = Date()
// CR-01: persist explicitly
try context.save()
```

**isDirty computed var** (lines 37–42): extend to include category in dirty check:
```swift
private var isDirty: Bool {
    guard let amount = parsedAmount else { return false }
    return amount != expense.amount
        || date != expense.date
        || (note.trimmingCharacters(in: .whitespaces).isEmpty ? nil : note.trimmingCharacters(in: .whitespaces)) != expense.note
        || selectedCategory?.persistentModelID != expense.categories.first?.persistentModelID
}
```

---

### `MyHomeApp/Features/Expenses/CategoryPickerView.swift` (component, request-response) — new

**Analog:** `MyHomeApp/Features/Expenses/EditExpenseView.swift`

**Imports:**
```swift
import SwiftUI
import SwiftData
```

**Struct declaration + property pattern** — copy the sheet-in-NavigationStack shell from `EditExpenseView` (lines 58–79):
```swift
struct CategoryPickerView: View {
    @Binding var selectedCategory: Category?
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Category.sortOrder) private var categories: [Category]
```

**Toolbar pattern** (lines 64–89 of EditExpenseView):
```swift
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
            .tint(Color(.systemRed))
        }
    }
}
```

**List row pattern** — copy the `ExpenseRow` HStack structure (lines 14–39 of `ExpenseRow.swift`), adapted for categories:
```swift
List {
    // "None" row — top of list
    Button(action: { selectedCategory = nil; dismiss() }) {
        HStack {
            Image(systemName: "circle.slash")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(width: 24)
                .accessibilityHidden(true)
            Text("None")
                .font(.body)
                .foregroundStyle(.primary)
            Spacer()
            if selectedCategory == nil {
                Image(systemName: "checkmark")
                    .foregroundStyle(.accentColor)
            }
        }
        .frame(minHeight: 44)
    }
    .buttonStyle(.plain)

    ForEach(categories) { category in
        Button(action: { selectedCategory = category; dismiss() }) {
            HStack {
                if let symbol = category.symbolName {
                    Image(systemName: symbol)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(width: 24)
                        .accessibilityHidden(true)
                }
                Text(category.name ?? "")
                    .font(.body)
                    .foregroundStyle(.primary)
                Spacer()
                if selectedCategory?.persistentModelID == category.persistentModelID {
                    Image(systemName: "checkmark")
                        .foregroundStyle(.accentColor)
                }
            }
            .frame(minHeight: 44)
        }
        .buttonStyle(.plain)
    }
}
.listStyle(.insetGrouped)
.navigationTitle("Category")
.navigationBarTitleDisplayMode(.inline)
```
Wrap in `NavigationStack { … }` — same sheet-contains-NavigationStack pattern as `EditExpenseView` (line 59).

---

### `MyHomeApp/Features/Budgets/BudgetsView.swift` (component, CRUD)

**Analog:** `MyHomeApp/Features/Expenses/ExpenseListView.swift`

**Imports + struct declaration** (lines 1–21 of `ExpenseListView.swift`):
```swift
import SwiftUI
import SwiftData

struct BudgetsView: View {

    @Environment(\.modelContext) private var context

    // Month paging state (local UI state — DateComponents)
    @State private var viewedMonth: DateComponents = {
        let cal = Calendar.current
        return cal.dateComponents([.year, .month], from: Date())
    }()

    @State private var showManageCategories: Bool = false
```

**@Query pattern** (line 18 of `ExpenseListView.swift`):
```swift
@Query(sort: \Expense.date, order: .reverse) private var expenses: [Expense]
@Query(sort: \Category.sortOrder) private var categories: [Category]
```
The month-scoped expense query must use a child view (`BudgetsMonthView`) that is re-initialized when `viewedMonth` changes (per RESEARCH.md Open Question 3 resolution). The parent `BudgetsView` passes `start`/`end` boundaries as parameters.

**NavigationStack + toolbar pattern** (lines 24–65 of `ExpenseListView.swift`):
```swift
NavigationStack {
    // ... list content ...
    .navigationTitle("Budgets")
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
        ToolbarItem(placement: .primaryAction) {
            Button("Manage Categories") { showManageCategories = true }
        }
    }
    .sheet(isPresented: $showManageCategories) {
        ManageCategoriesView()
    }
}
```

**Delete/save pattern for category CRUD** (lines 69–80 of `ExpenseListView.swift`):
```swift
private func deleteCategory(_ category: Category) {
    context.delete(category)
    // CR-01: persist explicitly — configuration write
    do {
        try context.save()
    } catch {
        assertionFailure("Failed to save after deleting category: \(error)")
        print("Failed to save after deleting category: \(error)")
    }
}
```

---

### `MyHomeApp/Features/Budgets/BudgetCategoryCard.swift` (component, request-response)

**Analog:** `MyHomeApp/Features/Expenses/ExpenseRow.swift`

**Struct + let property pattern** (lines 9–12 of `ExpenseRow.swift`):
```swift
struct BudgetCategoryCard: View {
    let progressData: BudgetProgressData
    @State private var showEditBudget: Bool = false
```

**HStack layout pattern** (lines 13–42 of `ExpenseRow.swift`):
```swift
VStack(alignment: .leading, spacing: 8) {
    // Row 1: icon + name + spent + edit button
    HStack {
        if let symbol = progressData.category.symbolName {
            Image(systemName: symbol)
                .font(.body)
                .foregroundStyle(.secondary)
                .frame(width: 28, height: 28)
                .accessibilityHidden(true)
        }
        Text(progressData.category.name ?? "")
            .font(.body)
            .lineLimit(1)
        Spacer()
        Text(progressData.spent.formattedINR())
            .font(.subheadline)
            .foregroundStyle(.secondary)
        Button(action: { showEditBudget = true }) {
            Image(systemName: "pencil")
                .frame(minWidth: 44, minHeight: 44)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .accessibilityLabel("Edit budget for \(progressData.category.name ?? "category")")
    }
    // Row 2 + 3 or "No budget set" — delegate to BudgetProgressView
    BudgetProgressView(data: progressData)
}
.padding(16)
.background(Color(.secondarySystemBackground))
.clipShape(RoundedRectangle(cornerRadius: 12))
.shadow(color: .black.opacity(0.04), radius: 2, y: 1)
.sheet(isPresented: $showEditBudget) {
    EditBudgetSheet(category: progressData.category)
}
```

**accessibilityElement** (line 41 of `ExpenseRow.swift`):
```swift
.accessibilityElement(children: .combine)
```

---

### `MyHomeApp/Features/Budgets/BudgetProgressView.swift` (component, transform)

**Analog:** `MyHomeApp/Features/Expenses/ExpenseRow.swift` — pure display component, no SwiftData

**Struct pattern** — copy the `let` property pattern of `ExpenseRow`:
```swift
struct BudgetProgressView: View {
    let data: BudgetProgressData   // pure value — no @Bindable, no @Query

    private var fillColor: Color {
        switch data.colorThreshold {
        case .normal:     return .accentColor
        case .warning:    return Color(.systemOrange)
        case .overBudget: return Color(.systemRed)
        }
    }
```

**Progress bar using GeometryReader** (no analog in Phase 1 — see RESEARCH.md Pattern 3 / UI-SPEC Screen 3):
```swift
GeometryReader { geo in
    ZStack(alignment: .leading) {
        // Track
        RoundedRectangle(cornerRadius: 4)
            .fill(Color(.secondarySystemBackground))
            .frame(height: 8)
        // Fill — capped at 100% width
        if let fraction = data.fractionUsed {
            RoundedRectangle(cornerRadius: 4)
                .fill(fillColor)
                .frame(width: min(CGFloat(fraction), 1.0) * geo.size.width, height: 8)
                .animation(.easeInOut(duration: 0.3), value: fraction)
        }
    }
}
.frame(height: 8)
.accessibilityElement(children: .ignore)
```

**"No budget set" branch** — copy the `if let note` pattern from `ExpenseRow` (lines 26–31):
```swift
if data.budget == nil {
    Text("No budget set")
        .font(.subheadline)
        .foregroundStyle(.tertiary)
}
```

---

### `MyHomeApp/Features/Budgets/FilteredExpenseListView.swift` (component, CRUD)

**Analog:** `MyHomeApp/Features/Expenses/ExpenseListView.swift`

**@Query with init-time predicate construction** (lines 16–21 of `ExpenseListView.swift` for the @Query pattern):
```swift
struct FilteredExpenseListView: View {
    let category: Category
    let start: Date
    let end: Date

    @Query private var expenses: [Expense]

    init(category: Category, start: Date, end: Date) {
        self.category = category
        self.start = start
        self.end = end

        // Use persistentModelID — not the Category object directly (Pitfall P2-02)
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
```
If the `contains(where:)` predicate crashes at runtime (known fragility per RESEARCH.md Open Question 1), fall back to fetching all month expenses and filtering in-memory: `expenses.filter { $0.categories.contains(where: { $0.id == category.id }) }`.

**List + empty state pattern** (lines 26–46 of `ExpenseListView.swift`):
```swift
Group {
    if expenses.isEmpty {
        ContentUnavailableView(
            "No Expenses",
            systemImage: "tray",
            description: Text("No expenses in \(category.name ?? "this category") for \(monthLabel).")
        )
    } else {
        List {
            ForEach(expenses) { expense in
                ExpenseRow(expense: expense)
            }
        }
        .listStyle(.insetGrouped)
    }
}
.navigationTitle(category.name ?? "Uncategorized")
.navigationBarTitleDisplayMode(.inline)
```
This view is read-only (no add/edit toolbar, no `.onDelete`). Navigation back button is system-provided.

---

### `MyHomeApp/Features/Budgets/ManageCategoriesView.swift` (component, CRUD)

**Analog:** `MyHomeApp/Features/Expenses/ExpenseListView.swift` (List + .onDelete) + `MyHomeApp/Features/Expenses/EditExpenseView.swift` (sheet + confirmationDialog)

**Imports + property block** (lines 1–22 of `ExpenseListView.swift`):
```swift
import SwiftUI
import SwiftData

struct ManageCategoriesView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Category.sortOrder) private var categories: [Category]

    @State private var showAddField: Bool = false
    @State private var newCategoryName: String = ""
    @State private var categoryToDelete: Category? = nil
    @State private var showDeleteConfirmation: Bool = false
    @State private var nameError: String? = nil
```

**confirmationDialog pattern** (lines 91–102 of `EditExpenseView.swift`):
```swift
.confirmationDialog(
    "Delete Category?",
    isPresented: $showDeleteConfirmation,
    titleVisibility: .visible
) {
    Button("Delete Category", role: .destructive) {
        if let cat = categoryToDelete { deleteCategory(cat) }
    }
    Button("Cancel", role: .cancel) {}
} message: {
    Text("All expenses in this category will become uncategorized. Any budget set for this category will also be removed.")
}
```

**Delete action** — same CR-01 explicit save pattern as `ExpenseListView.deleteExpenses` (lines 69–80):
```swift
private func deleteCategory(_ category: Category) {
    context.delete(category)
    do {
        try context.save()
    } catch {
        assertionFailure("Failed to save after deleting category: \(error)")
        print("Failed to save after deleting category: \(error)")
    }
}
```

**Uniqueness check before insert** (no `.@Attribute(.unique)` allowed — CloudKit rule 3):
```swift
private func addCategory(name: String) throws {
    let trimmed = name.trimmingCharacters(in: .whitespaces)
    guard !trimmed.isEmpty else {
        nameError = "Category name cannot be empty."
        return
    }
    // Lookup-before-insert: fetch by name (case-insensitive) to prevent duplicates
    let lower = trimmed.lowercased()
    let existing = try context.fetch(
        FetchDescriptor<Category>(predicate: #Predicate { ($0.name ?? "").lowercased() == lower })
    )
    guard existing.isEmpty else {
        nameError = "A category with that name already exists."
        return
    }
    let category = Category(name: trimmed, symbolName: "tag", sortOrder: 1000 + categories.count)
    context.insert(category)
    try context.save()   // CR-01
    nameError = nil
}
```

---

### `MyHomeApp/Features/Budgets/EditBudgetSheet.swift` (component, request-response)

**Analog:** `MyHomeApp/Features/Expenses/EditExpenseView.swift` — closest structural match (sheet, @Bindable-style, DecimalKeypadView, CR-01 save, confirmationDialog)

**Struct + property block** (lines 14–28 of `EditExpenseView.swift`):
```swift
struct EditBudgetSheet: View {
    @Bindable var category: Category
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var amountString: String = ""
    @State private var amountShakeOffset: CGFloat = 0
    @State private var amountIsError: Bool = false
    @State private var showRemoveConfirmation: Bool = false
```

**amountSection with DecimalKeypadView** (lines 111–138 of `EditExpenseView.swift`):
```swift
private var amountSection: some View {
    VStack(spacing: 16) {
        Text(displayAmount)
            .font(.largeTitle)
            .fontWeight(.bold)
            .frame(maxWidth: .infinity, alignment: .center)
            .offset(x: amountShakeOffset)
            .animation(.default, value: amountShakeOffset)

        DecimalKeypadView(displayString: $amountString)
    }
    .padding(16)
    .background(Color(.secondarySystemBackground))
    .clipShape(RoundedRectangle(cornerRadius: 12))
}
```
No sign toggle — budgets are always positive.

**Toolbar pattern** (lines 75–89 of `EditExpenseView.swift`):
```swift
ToolbarItem(placement: .cancellationAction) {
    Button("Cancel") { dismiss() }
}
ToolbarItem(placement: .confirmationAction) {
    Button("Save Budget") {
        saveBudget()
    }
    .disabled(!isSaveEnabled)
    .tint(.accentColor)
}
```

**deleteSection → "Remove Budget" button** (lines 201–212 of `EditExpenseView.swift`):
```swift
private var removeBudgetSection: some View {
    Button(role: .destructive) {
        showRemoveConfirmation = true
    } label: {
        Text("Remove Budget")
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
    }
    .buttonStyle(.bordered)
    .tint(Color(.systemRed))
    .frame(minHeight: 44)
}
```
Only rendered when `category.monthlyBudget != nil`.

**confirmationDialog for remove** (lines 91–102 of `EditExpenseView.swift`):
```swift
.confirmationDialog(
    "Remove Budget?",
    isPresented: $showRemoveConfirmation,
    titleVisibility: .visible
) {
    Button("Remove Budget", role: .destructive) {
        category.monthlyBudget = nil
        try? context.save()   // CR-01
        dismiss()
    }
    Button("Cancel", role: .cancel) {}
} message: {
    Text("The monthly budget for this category will be removed. Spending data is not affected.")
}
```

**saveBudget action** (lines 236–264 of `EditExpenseView.swift` — copy the guard + save + dismiss pattern):
```swift
private func saveBudget() {
    guard let amount = parsedAmount, amount > 0 else {
        // shake animation
        return
    }
    guard abs(amount) < Decimal(1_000_000_000) else {
        // shake animation
        return
    }
    category.monthlyBudget = amount
    do {
        try context.save()   // CR-01
    } catch {
        assertionFailure("Failed to save budget: \(error)")
        return
    }
    dismiss()
}
```

---

### `MyHomeApp/Support/BudgetCalculator.swift` (utility, transform)

**Analog:** `MyHomeApp/Support/Decimal+INR.swift` — pure value/function, no SwiftData, no UI

**File structure** (lines 1–18 of `Decimal+INR.swift`):
```swift
import Foundation
```
No `import SwiftUI`. No `import SwiftData`. `BudgetCalculator` is a pure struct with static methods and `BudgetProgressData` + `BudgetColor` are pure value types — testable without a ModelContainer.

**BudgetProgressData shape** (from RESEARCH.md Code Examples):
```swift
struct BudgetProgressData {
    let category: Category
    let spent: Decimal        // sum of expense.amount for the viewed month
    let budget: Decimal?      // nil = no budget set

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
    case normal      // Color.accentColor
    case warning     // Color(.systemOrange)
    case overBudget  // Color(.systemRed)
}
```

**BudgetCalculator static methods** (from RESEARCH.md Pattern 3):
```swift
struct BudgetCalculator {
    static func monthlySpend(
        for expenses: [Expense],
        categories: [Category]
    ) -> [PersistentIdentifier: Decimal] { … }

    static func monthBoundaries(for month: DateComponents) -> (start: Date, end: Date)? {
        var cal = Calendar.current
        cal.timeZone = TimeZone.current   // Pitfall P2-05: use user's timezone for boundaries
        guard let start = cal.date(from: month),
              let end = cal.date(byAdding: DateComponents(month: 1, second: -1), to: start)
        else { return nil }
        return (start, end)
    }
}
```

---

### `MyHomeApp/Support/Date+Display.swift` (utility, transform) — update

**Analog:** `MyHomeApp/Support/Date+Display.swift` (self, lines 1–37)

**Existing extension pattern** (lines 3–37):
```swift
extension Date {
    func formattedForExpenseList() -> String { … }
    func formattedForDatePickerRow() -> String { … }
}
```
**Add a new method for month-header labels:**
```swift
/// Formats this date as "May 2026" for the Budgets tab month pager.
/// Uses the user's current locale and timezone.
func formattedAsMonthYear() -> String {
    let formatter = DateFormatter()
    formatter.dateFormat = "MMMM yyyy"
    formatter.locale = .current
    formatter.timeZone = .current
    return formatter.string(from: self)
}
```
Append inside the existing `extension Date` block — do not create a second extension.

---

### `MyHomeTests/CategorySeedTests.swift` (test, batch) — new

**Analog:** `MyHomeTests/ExpenseModelTests.swift`

**File header + @MainActor struct + makeContainer** (lines 1–14 of `ExpenseModelTests.swift`):
```swift
import Testing
import SwiftData
import Foundation
@testable import MyHome

@MainActor
struct CategorySeedTests {

    private func makeContainer() throws -> ModelContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: Expense.self, Category.self, configurations: config)
    }
```
Note: both `Expense.self` and `Category.self` must be listed in the ModelContainer init — Phase 2 changes the schema.

**@Test macro pattern** (lines 16–34 of `ExpenseModelTests.swift`):
```swift
    @Test("14 predefined categories are seeded on empty store")
    func seedsOnEmptyStore() throws {
        let container = try makeContainer()
        let context = container.mainContext
        try seedCategoriesIfNeeded(context: context)   // call directly in test
        let all = try context.fetch(FetchDescriptor<Category>())
        #expect(all.count == 14)
    }

    @Test("Seeding is idempotent — no duplicates on second run")
    func seedIsIdempotent() throws {
        let container = try makeContainer()
        let context = container.mainContext
        try seedCategoriesIfNeeded(context: context)
        try seedCategoriesIfNeeded(context: context)   // second call must be a no-op
        let all = try context.fetch(FetchDescriptor<Category>())
        #expect(all.count == 14, "Expected 14 categories, got \(all.count)")
    }
```
`seedCategoriesIfNeeded` must be `internal` (not `private`) in `ModelContainer+App.swift` to be callable from tests — or move to a separate testable file.

---

### `MyHomeTests/CategoryCRUDTests.swift` (test, CRUD) — new

**Analog:** `MyHomeTests/ExpenseModelTests.swift` — same makeContainer + @Test pattern

```swift
@Test("Deleting a category nullifies expense.categories link")
func deleteNullifiesExpenseLink() throws {
    let container = try makeContainer()
    let context = container.mainContext

    let cat = Category(name: "Test", symbolName: nil)
    context.insert(cat)
    let expense = Expense(amount: Decimal(100))
    expense.categories = [cat]
    context.insert(expense)
    try context.save()

    context.delete(cat)
    try context.save()

    let fetched = try context.fetch(FetchDescriptor<Expense>())
    #expect(fetched.first?.categories.isEmpty == true,
            "Deleting category must nullify expense.categories (D2-04, .nullify deleteRule)")
}
```
Copy `makeContainer` from `ExpenseModelTests.swift` exactly; add `Category.self` to the model list.

---

### `MyHomeTests/BudgetCalculatorTests.swift` (test, transform) — new

**Analog:** `MyHomeTests/ExpenseModelTests.swift` — `currencyFormatting` test (lines 61–76) is a pure-function test with no ModelContainer; same pattern applies here.

```swift
// These tests need NO ModelContainer — BudgetProgressData and BudgetCalculator
// are pure value types (same pattern as the currencyFormatting test in ExpenseModelTests).

@Test("BudgetProgressData: fractionUsed and colorThreshold — under 80%")
func colorThresholdNormal() {
    // Create BudgetProgressData directly — no SwiftData needed
    // (requires a Category instance; use in-memory Category if @Model init allows it,
    //  or restructure BudgetProgressData to use category ID + name only for pure tests)
}

@Test("Color threshold: ≥80% = warning")
func colorThresholdWarning() { … }

@Test("Color threshold: ≥100% = overBudget")
func colorThresholdOverBudget() { … }

@Test("monthlySpend aggregation groups by category correctly")
func monthlyAggregation() throws {
    // This test does need a ModelContainer (for PersistentIdentifier)
    let container = try makeContainer()
    // …
}
```
If `BudgetProgressData` takes a full `Category` `@Model` instance, it requires a ModelContainer in tests. Consider accepting `(name: String, budget: Decimal?, spent: Decimal)` tuples in a secondary init for pure-function tests.

---

### `MyHomeTests/MigrationTests.swift` (test, batch) — update

**Analog:** `MyHomeTests/MigrationTests.swift` (self, lines 1–65)

**One-line schema change** (line 37):
```swift
let schema = Schema(versionedSchema: SchemaV1.self)
```
**After update:**
```swift
let schema = Schema(versionedSchema: SchemaV2.self)
```
The `AppMigrationPlan` reference on line 40 and the `FetchDescriptor<Expense>` on line 47 remain unchanged — the typealias flip means `Expense` is already `SchemaV2.Expense`. The bundled `MyHomeV1Seed.store` remains valid; the test verifies the V1→V2 migration succeeds and the seeded expense is still readable post-migration.

---

## Shared Patterns

### CR-01: Explicit Save (All write paths)
**Source:** `MyHomeApp/Features/Expenses/ExpenseListView.swift` lines 69–80; `AddExpenseView.swift` lines 188–198; `EditExpenseView.swift` lines 252–262
**Apply to:** Every `context.insert()`, `context.delete()`, or property mutation in BudgetsView, ManageCategoriesView, EditBudgetSheet, seed function
```swift
do {
    try context.save()
} catch {
    assertionFailure("Failed to save: \(error)")
    print("Failed to save: \(error)")
}
```
Financial and configuration writes must never rely on implicit autosave.

### @Query + @Environment(\.modelContext) (All view reads)
**Source:** `MyHomeApp/Features/Expenses/ExpenseListView.swift` lines 18–19
**Apply to:** BudgetsView, FilteredExpenseListView, CategoryPickerView, ManageCategoriesView
```swift
@Query(sort: \Expense.date, order: .reverse) private var expenses: [Expense]
@Environment(\.modelContext) private var context
```
No repository wrapper. Views talk to SwiftData directly.

### @Bindable edit pattern (All edit sheets)
**Source:** `MyHomeApp/Features/Expenses/EditExpenseView.swift` line 16
**Apply to:** EditBudgetSheet
```swift
@Bindable var category: Category
```
Used for live two-way binding on `@Model` instances passed into sheets.

### NavigationStack-in-sheet pattern (All sheets)
**Source:** `MyHomeApp/Features/Expenses/EditExpenseView.swift` lines 58–79; `AddExpenseView.swift` lines 52–79
**Apply to:** CategoryPickerView, ManageCategoriesView, EditBudgetSheet
```swift
var body: some View {
    NavigationStack {
        // content
        .navigationTitle("…")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { … }
    }
}
```

### confirmationDialog pattern (Destructive actions)
**Source:** `MyHomeApp/Features/Expenses/EditExpenseView.swift` lines 91–102
**Apply to:** ManageCategoriesView (delete category), EditBudgetSheet (remove budget)
```swift
.confirmationDialog("Title?", isPresented: $flag, titleVisibility: .visible) {
    Button("Destructive Action", role: .destructive) { … }
    Button("Cancel", role: .cancel) {}
} message: { Text("…") }
```

### In-memory ModelContainer for tests
**Source:** `MyHomeTests/ExpenseModelTests.swift` lines 11–13
**Apply to:** All new test files
```swift
private func makeContainer() throws -> ModelContainer {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    return try ModelContainer(for: Expense.self, Category.self, configurations: config)
}
```
`@MainActor` on the test struct — copy from `ExpenseModelTests.swift` line 8.

### Amount validation guard (All financial input)
**Source:** `MyHomeApp/Features/Expenses/AddExpenseView.swift` lines 181–183; `EditExpenseView.swift` lines 241–243
**Apply to:** EditBudgetSheet.saveBudget()
```swift
guard abs(amount) < Decimal(1_000_000_000) else {
    shakeAmount()
    return
}
```

### Decimal.formattedINR() (All money display)
**Source:** `MyHomeApp/Support/Decimal+INR.swift` lines 12–17
**Apply to:** BudgetCategoryCard, BudgetProgressView (₹ remaining), FilteredExpenseListView rows, EditBudgetSheet amount display
```swift
value.formattedINR()
```

---

## No Analog Found

All files have analogs in the existing codebase. No files require falling back to RESEARCH.md-only patterns.

---

## Metadata

**Analog search scope:** `MyHomeApp/Persistence/`, `MyHomeApp/Features/Expenses/`, `MyHomeApp/Support/`, `MyHomeTests/`
**Files scanned:** 12 source files read in full
**Pattern extraction date:** 2026-05-29
