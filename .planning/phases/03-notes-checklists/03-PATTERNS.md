# Phase 3: Notes & Checklists - Pattern Map

**Mapped:** 2026-05-30
**Files analyzed:** 18 (14 new, 4 modified)
**Analogs found:** 16 / 18 (2 no-analog: NotificationScheduler + NotificationCenterPort)

> Scope note: Phase 3 is the owner-expanded **Notes + Reminders hub** (note keeper NOT-01..06 PLUS reminders/recurrence/notifications/calendar SC-R1..R5). The notification layer is genuinely new surface area with no codebase analog — see "No Analog Found". Everything else copies an established Phase 1/2 pattern verbatim.

---

## File Classification

| New/Modified File | Role | Data Flow | Closest Analog | Match Quality |
|-------------------|------|-----------|----------------|---------------|
| `Persistence/Schema/SchemaV3.swift` | schema (model) | CRUD | `Persistence/Schema/SchemaV2.swift` | exact |
| `Persistence/Schema/MigrationPlan.swift` *(modify)* | migration | batch | self (`v1ToV2` stage) | exact |
| `Persistence/Models/Note.swift` (typealias) | model | CRUD | `Persistence/Models/Expense.swift` | exact |
| `Persistence/Models/NoteBlock.swift` (typealias) | model | CRUD | `Persistence/Models/Expense.swift` | exact |
| `Persistence/ModelContainer+App.swift` *(modify)* | config | CRUD | self | exact |
| `Features/Notes/NotesListView.swift` | view (list) | CRUD | `Features/Expenses/ExpenseListView.swift` | exact |
| `Features/Notes/NoteRow.swift` | view (component) | request-response | `Features/Expenses/ExpenseRow.swift` | role-match |
| `Features/Notes/EditNoteView.swift` | view (sheet) | CRUD | `Features/Expenses/EditExpenseView.swift` | exact |
| `Features/Notes/AddNoteView.swift` | view (sheet) | CRUD | `Features/Expenses/AddExpenseView.swift` | exact |
| `Features/Notes/ReminderEditView.swift` | view (sheet) | CRUD | `Features/Expenses/EditExpenseView.swift` | role-match |
| `Features/Notes/CalendarView.swift` | view (grid) | transform | `Features/Budgets/BudgetsView.swift` | partial (segmented host + derived data) |
| `Support/NotificationScheduler.swift` | service | event-driven | `Support/BudgetCalculator.swift` (pure-logic shape only) | partial |
| `Support/NotificationCenterPort.swift` | service (port) | event-driven | — | **no analog** |
| `Support/Date+Display.swift` *(modify)* | utility | transform | self | exact |
| `RootView.swift` *(modify)* | view (host) | request-response | self | exact |
| `MyHomeTests/NoteModelTests.swift` | test | CRUD | `MyHomeTests/ExpenseModelTests.swift` | exact |
| `MyHomeTests/NotificationSchedulerTests.swift` | test | event-driven | `MyHomeTests/BudgetCalculatorTests.swift` | role-match |
| `MyHomeTests/RecurrenceTests.swift` | test | transform | `MyHomeTests/BudgetCalculatorTests.swift` | role-match |
| `MyHomeTests/CalendarAggregationTests.swift` | test | transform | `MyHomeTests/BudgetCalculatorTests.swift` | role-match |
| `MyHomeTests/NoteListOrderingTests.swift` | test | CRUD | `MyHomeTests/BudgetCalculatorTests.swift` | role-match |
| `MyHomeTests/NoteSearchTests.swift` | test | CRUD | `MyHomeTests/ExpenseModelTests.swift` | role-match |
| `MyHomeTests/AutoSaveTests.swift` | test | event-driven | `MyHomeTests/ExpenseModelTests.swift` | role-match |
| `MyHomeTests/MigrationTests.swift` *(modify)* | test | batch | self (`v1StoreMigratesCleanly`) | exact |

---

## Pattern Assignments

### `Persistence/Schema/SchemaV3.swift` (schema, CRUD)

**Analog:** `Persistence/Schema/SchemaV2.swift`

**Structure to copy:** `enum SchemaV3: VersionedSchema` with `static let versionIdentifier = Schema.Version(3, 0, 0)`, a `static var models` array listing ALL V3 types (copy `Expense` + `Category` verbatim, ADD `Note` + `NoteBlock`). The header comment block enumerating the 8 CloudKit-readiness rules is the template (`SchemaV2.swift` lines 12-20).

**Models declaration** (`SchemaV2.swift:24-26`):
```swift
static var models: [any PersistentModel.Type] {
    [SchemaV2.Expense.self, SchemaV2.Category.self]
}
// V3: [SchemaV3.Expense.self, SchemaV3.Category.self, SchemaV3.Note.self, SchemaV3.NoteBlock.self]
```

**CloudKit-ready @Model + UUID PK + defaulted/optional fields + UTC dates** (`SchemaV2.swift:30-56`):
```swift
@Model
final class Category {
    var id: UUID = UUID()                    // NO @Attribute(.unique) — rule 2
    var name: String? = nil                  // optional per rule
    var sortOrder: Int = 0                   // defaulted per rule
    var createdAt: Date = Date()             // UTC timestamp
    @Relationship(deleteRule: .nullify)
    var expenses: [SchemaV2.Expense] = []    // inverse inferred from the OTHER side
    init(...) { ... }
}
```

**CRITICAL — `@Relationship` inverse-on-one-side-only caveat** (`SchemaV2.swift:42-48` + `:75`). Declaring `inverse:` on BOTH sides in the same file causes *"Circular reference resolving attached macro 'Relationship'"*. Apply the same rule to `Note ↔ NoteBlock`: declare `inverse:` ONLY on `Note.blocks` (or only on `NoteBlock.note`), never both. Research recommends it on `Note.blocks` with `deleteRule: .cascade` (note owns its blocks), inverse inferred on `NoteBlock.note`:
```swift
@Relationship(deleteRule: .cascade, inverse: \NoteBlock.note)
var blocks: [NoteBlock]? = []
```

**Reminder fields + no-stored-enum rule (D3-19 / Pitfall 6):** `kindRaw: String = "text"` (not an enum); recurrence/end-rule as Codable value types serialized to `Data?`. See RESEARCH `## Data Model Design` for the recommended field set.

---

### `Persistence/Schema/MigrationPlan.swift` (migration, batch — MODIFY)

**Analog:** self — the existing `v1ToV2` stage (`MigrationPlan.swift:19-24`).

**Append SchemaV3 to the schemas list** (`:8-10`), never remove/reorder:
```swift
static var schemas: [any VersionedSchema.Type] {
    [SchemaV1.self, SchemaV2.self, SchemaV3.self]   // append V3
}
static var stages: [MigrationStage] { [v1ToV2, v2ToV3] }
```

**Mirror the `.custom` stage** (`:19-24`) — `.custom` over `.lightweight` deliberately sidesteps FB13812722 (comment at `:16-18`). V3 adds only new models, so `willMigrate`/`didMigrate` are `nil`:
```swift
static let v2ToV3 = MigrationStage.custom(
    fromVersion: SchemaV2.self,
    toVersion: SchemaV3.self,
    willMigrate: nil,
    didMigrate: nil
)
```

---

### `Persistence/Models/Note.swift` + `NoteBlock.swift` (model, CRUD — NEW typealias)

**Analog:** `Persistence/Models/Expense.swift` (entire file).

**Typealias version-flip pattern** (`Expense.swift:11`):
```swift
typealias Expense = SchemaV2.Expense
// New: typealias Note = SchemaV3.Note  /  typealias NoteBlock = SchemaV3.NoteBlock
```
One bare-name typealias per `@Model`, pointed at the top schema version. All views/tests use the bare name. (RESEARCH `## Typealias Flip` confirms `SchemaV3.Note` / `SchemaV3.NoteBlock`.)

---

### `Persistence/ModelContainer+App.swift` (config, CRUD — MODIFY)

**Analog:** self.

**Flip the top schema to V3** (`:18`):
```swift
let schema = Schema(versionedSchema: SchemaV2.self)   // → SchemaV3.self
```
The App-Group-URL-with-fallback (`:21-33`), `ModelConfiguration(cloudKitDatabase: .none)` (`:35-39`), and `ModelContainer(for:migrationPlan:configurations:)` (`:41-45`) wiring stay identical. **Idempotent-seed hook pattern** (`:47-49` + the `seedCategoriesIfNeeded` body at `:64-95`: `fetchLimit = 1` → `guard existing.isEmpty` → batch insert → explicit `context.save()`) is the template if any reminder-category registration needs a launch-time seed (e.g. registering the notification action category — see Shared Patterns).

---

### `Features/Notes/NotesListView.swift` (view/list, CRUD)

**Analog:** `Features/Expenses/ExpenseListView.swift` (entire file).

**`@Query` + `@Environment(\.modelContext)` read/write, NO repository** (`ExpenseListView.swift:18-22`):
```swift
@Query(sort: \Expense.date, order: .reverse) private var expenses: [Expense]
@Environment(\.modelContext) private var context
@State private var showingAddSheet: Bool = false
@State private var editingExpense: Expense? = nil
```
For Notes, the List has THREE sections (Daily Routine → Pinned → Other, D3-08). `@Query` cannot express the Daily-Routine/Pinned grouping directly — fetch most-recent-first, then partition into sections in a computed property (test the partition logic in `NoteListOrderingTests`). Most-recent ordering uses `sort: \Note.modifiedAt, order: .reverse`.

**Empty state + List + toolbar "+" + edit `.sheet`** (`ExpenseListView.swift:24-64`):
```swift
NavigationStack {
    Group {
        if expenses.isEmpty {
            ContentUnavailableView("No Expenses Yet", systemImage: "tray",
                description: Text("Tap + to record your first expense."))
        } else {
            List { ForEach(expenses) { ExpenseRow(expense: $0)
                .contentShape(Rectangle()).onTapGesture { editingExpense = $0 } }
                .onDelete(perform: deleteExpenses) }
            .listStyle(.insetGrouped)
        }
    }
    .navigationTitle("Expenses").navigationBarTitleDisplayMode(.inline)
    .toolbar { ToolbarItem(placement: .primaryAction) {
        Button { showingAddSheet = true } label: { Image(systemName: "plus") }
            .tint(.accentColor).accessibilityLabel("Add Expense") } }
    .sheet(isPresented: $showingAddSheet) { AddExpenseView() }
    .sheet(item: $editingExpense) { EditExpenseView(expense: $0) }
}
```
Notes empty-state copy comes from UI-SPEC §4: `"No Notes Yet"` / `"Tap + to capture your first note or checklist."`. **`.searchable` (D3-18, NOT-06)** attaches to the `List`/`Group` here (note: ExpenseListView does not yet use `.searchable` — this is new; see RESEARCH Open Question 3 / Assumption A2 re: `#Predicate` reach into block text, fall back to in-memory filter).

**Explicit-save delete pattern** (`ExpenseListView.swift:69-81`):
```swift
private func deleteExpenses(at offsets: IndexSet) {
    for index in offsets { context.delete(expenses[index]) }
    do { try context.save() }
    catch { assertionFailure("Failed to save after deleting: \(error)"); print(...) }
}
```

**Segmented List|Calendar toggle (D3-17):** wrap the list/calendar in a `Picker(...).pickerStyle(.segmented)` driven by `@State` at the top of the Notes tab. Closest host shape is `BudgetsView.swift:30-54` (a `NavigationStack` whose `VStack` puts a control header above a content child). Switch between `NotesListView` content and `CalendarView` content based on the segment state.

---

### `Features/Notes/NoteRow.swift` (view/component, request-response)

**Analog:** `Features/Expenses/ExpenseRow.swift` (read for the exact label/HStack convention) + the `ForEach`-row consumption in `ExpenseListView.swift:35-41`. A note row shows title (headline 20pt), pin icon, reminder-count badge per UI-SPEC §2/§5. Checklist-row strikethrough+dim (checked rows) uses UI-SPEC §2: `.strikethrough()` + `.opacity(0.6)`.

---

### `Features/Notes/EditNoteView.swift` + `AddNoteView.swift` (view/sheet, CRUD)

**Analog:** `Features/Expenses/EditExpenseView.swift` + `AddExpenseView.swift`.

**`@Bindable` two-way binding to the @Model** (`EditExpenseView.swift:16-18`):
```swift
@Bindable var expense: Expense
@Environment(\.modelContext) private var context
@Environment(\.dismiss) private var dismiss
```

**NavigationStack-in-sheet + Cancel/confirm toolbar** (`EditExpenseView.swift:62-93`):
```swift
NavigationStack {
    ScrollView { VStack(spacing: 0) { ... } }
    .navigationTitle("Edit Expense").navigationBarTitleDisplayMode(.inline)
    .toolbar {
        ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
        ToolbarItem(placement: .confirmationAction) {
            Button("Save Expense") { saveExpense() }.disabled(!isSaveEnabled).tint(.accentColor) }
    }
}
```
**Auto-save override (NOT-05, D3-19):** Notes have NO save button (UI-SPEC §5). Replace the explicit Save toolbar item with a debounced ~500ms auto-save (debounce isolated + unit-tested in `AutoSaveTests`). Keep the `context.save()` + `do/catch` + `assertionFailure` write discipline from `saveExpense()` (`EditExpenseView.swift:295-304`). **Required-title / discard-on-dismiss (D3-03/D3-19):** on dismiss, if title is empty, delete the draft (`context.delete(note)`); mirror the `dismiss()` + clean-teardown pattern (`:305-306`).

**`isDirty` change-tracking** (`EditExpenseView.swift:39-50`) — useful to gate the debounced save (only save when actually changed).

**Destructive delete with confirmationDialog** (`EditExpenseView.swift:94-105` + `241-252`) — template for "Delete Note" / "Remove Reminder" (UI-SPEC §4 confirmation copy). Note: prefer `.confirmationDialog`, not `confirmationAction`, for the destructive path:
```swift
.confirmationDialog("Delete Expense?", isPresented: $showDeleteConfirmation, titleVisibility: .visible) {
    Button("Delete Expense", role: .destructive) { deleteExpense() }
    Button("Cancel", role: .cancel) {}
} message: { Text("This expense will be permanently removed.") }
```

**Plain-text only (Pitfall 1):** use `TextField` for title + text blocks (`EditExpenseView.swift:226` shows the `TextField` row pattern), NEVER `TextEditor`/`AttributedString(markdown:)` — note the explicit `T-01-06`/`T-02-07` plain-`Text` comments at `:196` and `:221`.

---

### `Features/Notes/ReminderEditView.swift` (view/sheet, CRUD)

**Analog:** `EditExpenseView.swift` (sheet shell + picker rows).

**Disclosure/picker row pattern** (`EditExpenseView.swift:145-180`) — the collapsible Date row (Button toggles `showDatePicker` → reveals a `DatePicker(...).datePickerStyle(.graphical)`) is the exact template for the reminder date/time picker. Build the recurrence menu (None/Daily/Weekly+weekdays/Monthly/Yearly), end-rule picker (Never/On Date/After N), all-day `Toggle`, lead-time stepper, and the pre-checked "Pin to top" `Toggle` for yearly reminders (D3-09) out of the same Button-row + reveal pattern. All-day vs timed switches `displayedComponents` between `[.date]` and `[.date, .hourAndMinute]` (`:170-174`).

---

### `Features/Notes/CalendarView.swift` (view/grid, transform)

**Analog:** `Features/Budgets/BudgetsView.swift` (NavigationStack + month-state header + derived child) — partial.

**Month state + derived content** (`BudgetsView.swift:16-19`, `30-54`):
```swift
@State private var viewedMonth: DateComponents = {
    Calendar.current.dateComponents([.year, .month], from: Date()) }()
// header above a child view that recomputes when month changes
```
The custom month grid is a `LazyVGrid` (D3-17 — SwiftUI ships no calendar component). Per-day reminder counts + the tapped-day agenda completion progress (e.g. 2/5) are **derived live** (D3-16, stores nothing). Put the aggregation math in a **pure helper** (mirroring `BudgetCalculator`'s static, SwiftData-free reduce functions — see below) and unit-test it in `CalendarAggregationTests`. `BudgetCalculator.monthBoundaries(for:)` (`BudgetCalculator.swift:105-115`) is directly reusable for month-edge math (already timezone-correct, `TimeZone.current`).

---

### `Support/NotificationScheduler.swift` (service, event-driven) — see "No Analog Found"

The *shape* (a pure, SwiftData-free, statically-testable value type) copies `Support/BudgetCalculator.swift`:

**Pure value-type service, no `@Query`, no SwiftUI, in-memory only** (`BudgetCalculator.swift:59-95`):
```swift
struct BudgetCalculator {
    static func monthlySpend(for expenses: [Expense], categories: [Category]) -> [...] {
        // operates on already-fetched arrays; no SwiftData fetching inside
    }
}
```
Apply this discipline to `NotificationScheduler.buildRequests(for:)` — keep it **pure** (returns the `[UNNotificationRequest]` set with no I/O) so it is asserted directly in unit tests; only `schedule`/`cancel` touch the injected `NotificationCenterPort`. The `BudgetColor`/`BudgetProgressData` value-type + computed-property + zero-guard style (`BudgetCalculator.swift:8-57`) is the template for `RecurrenceType`/`ReminderRecurrence`/`EndRuleType`/`ReminderEndRule` Codable value types. See RESEARCH `## Notification Service Architecture` for the full seam.

---

### `Support/Date+Display.swift` (utility, transform — MODIFY)

**Analog:** self.

**Locale+timezone display-formatting pattern** (`Date+Display.swift:8-15`, `42-49`):
```swift
func formattedForExpenseList() -> String {
    let formatter = DateFormatter()
    formatter.dateStyle = .medium; formatter.timeStyle = .short
    formatter.locale = .current; formatter.timeZone = .current   // store UTC, display local (D-02)
    return formatter.string(from: self)
}
```
Add reminder date/time labels, calendar day/month labels. Reuse `formattedAsMonthYear()` (`:42-49`, already uses `setLocalizedDateFormatFromTemplate("MMMMyyyy")`) for the Calendar month title. **Pitfall 5 (timezone):** display in `.current`; when BUILDING a `UNCalendarNotificationTrigger`, convert UTC → device timezone for the `DateComponents`.

---

### `RootView.swift` (view/host, request-response — MODIFY)

**Analog:** self.

**Add a Notes tab** (`RootView.swift:13-23`) — slot beside Expenses/Budgets; the Notes tab owns its own `NavigationStack` (no shared `NavigationPath`):
```swift
TabView {
    ExpenseListView().tabItem { Label("Expenses", systemImage: "list.bullet") }
    BudgetsView().tabItem { Label("Budgets", systemImage: "chart.bar") }
    // NotesHomeView().tabItem { Label("Notes", systemImage: "note.text") }
}
```
The Notes tab root hosts the List|Calendar segmented control internally (D3-17) — keep the tab bar lean (3 tabs; Overview P4 + Settings P5 still to come).

---

### Test files (`MyHomeTests/*`)

**Model/CRUD tests** — Analog: `ExpenseModelTests.swift`.

**Swift Testing + fresh in-memory container per test** (`ExpenseModelTests.swift:1-14`):
```swift
import Testing
import SwiftData
import Foundation
@testable import MyHome

@MainActor
struct NoteModelTests {
    private func makeContainer() throws -> ModelContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: Note.self, NoteBlock.self, configurations: config)
    }
    @Test("...") func ...() throws { ... #expect(...) }
}
```
**CloudKit-readiness schema-metadata assertion** (`ExpenseModelTests.swift:78-129`) — reuse verbatim for `Note`/`NoteBlock`: iterate `entity.attributes`, `#expect(isOptional || hasDefault)`, assert `entity.uniquenessConstraints.isEmpty`. This is the rule-2/rule-3 guard test.

**Pure-logic tests** (`NotificationSchedulerTests`, `RecurrenceTests`, `CalendarAggregationTests`, `NoteListOrderingTests`) — Analog: `BudgetCalculatorTests.swift`. Same `@MainActor struct` + `makeContainer()` + named `@Test` + `#expect`/`Issue.record` style. Note the `private typealias Cat = MyHome.Category` disambiguation trick (`BudgetCalculatorTests.swift:6`) — apply if any `NoteBlock.kind`/`Note` name clashes with an Obj-C runtime typedef.

**Migration test** (`MigrationTests.swift` — MODIFY) — Analog: self, `v1StoreMigratesCleanly` (`:16-56`). Add `v2StoreMigratesToV3`: bundle a new `MyHomeV2Seed.store`, copy to temp (`:29-33`), open `Schema(versionedSchema: SchemaV3.self)` under `AppMigrationPlan` (`:38-44`), assert pre-existing `Expense` rows survive (`:47-55`). Reuse the `private final class MigrationTestsClass {}` bundle-accessor (`:63-66`) and the `Bundle(for:).url(forResource:withExtension:"store")` lookup (`:21-26`).

> **Build-config action:** the new `MyHomeV2Seed.store` must be added to the `MyHomeTests` target's **Copy Bundle Resources** build phase (mirror the existing `MyHomeV1Seed.store` setup, called out in `MigrationTests.swift:24` and RESEARCH Wave 0 Gaps).

---

## Shared Patterns

### CloudKit-Readiness (8 rules)
**Source:** `Persistence/Schema/SchemaV2.swift:12-20` (rule list) + `:30-56` (applied).
**Apply to:** `Note`, `NoteBlock` @Models in `SchemaV3.swift`.
No `@Attribute(.unique)`; every stored property optional or defaulted; UTC dates; `@Relationship(inverse:)` on ONE side only (`:42-48`/`:75`); no stored enums (use `String` raw / Codable `Data?`).

### Explicit-Save Write Discipline
**Source:** `EditExpenseView.swift:295-304`, `ExpenseListView.swift:73-81`, `ModelContainer+App.swift:93-94`.
**Apply to:** every Notes/Block/Reminder write (auto-save, delete, check-row, reschedule).
```swift
do { try context.save() }
catch { assertionFailure("Failed to save ...: \(error)"); print("Failed to save ...: \(error)") }
```
Never rely on implicit autosave (Pitfall 3: schedule-then-forget-save loses notifications).

### State-Management Rule
**Source:** `ExpenseListView.swift:15` comment; applied throughout (`@Query`/`@State`/`@Bindable`/`@Environment`).
**Apply to:** all new views.
ONLY `@Observable` / `@State` / `@Bindable` / `@Query` / `@Environment`. NEVER `@StateObject` / `@ObservedObject` / `@Published` / Combine.

### Pure-Logic-Helper Seam (testability)
**Source:** `Support/BudgetCalculator.swift:59-115` (static, SwiftData-free, array-in/value-out).
**Apply to:** `NotificationScheduler.buildRequests`, recurrence expansion, "after N" tracking, calendar aggregation.
Keep OS/persistence I/O out of the testable core; inject a port for the I/O edge.

### Plain-Text-Only Discipline
**Source:** `EditExpenseView.swift:196`, `:221`, `:226` (`T-01-06`/`T-02-07` comments; `TextField`, plain `Text`).
**Apply to:** note title + all text/checkbox blocks.
`TextField` only — never `TextEditor`, never `AttributedString(markdown:)` (Pitfall 1).

### UTC-Store / Local-Display
**Source:** `Date+Display.swift:8-15` (`formatter.timeZone = .current`); `BudgetCalculator.monthBoundaries:105-115` (`cal.timeZone = TimeZone.current`).
**Apply to:** all reminder/calendar dates.
Store UTC in SwiftData; convert to device timezone for display AND for building `UNCalendarNotificationTrigger` `DateComponents` (Pitfall 5).

### Notification action-category registration (runtime OS state)
**Source:** idempotent-seed-hook shape at `ModelContainer+App.swift:47-49`/`:64-95` (closest analog for a launch-time one-time registration).
**Apply to:** registering the actionable Complete/Snooze `UNNotificationCategory` at launch (RESEARCH Runtime State Inventory) — register once at app/container init, cancel-on-delete/check to avoid orphaned pending requests.

---

## No Analog Found

| File | Role | Data Flow | Reason |
|------|------|-----------|--------|
| `Support/NotificationScheduler.swift` | service | event-driven | No `UNUserNotificationCenter` / scheduling service exists in the codebase. *Pure-logic shape* borrows from `BudgetCalculator`, but the notification domain (permission, repeating triggers, lead alerts, deep-link, 64-cap budgeting, reschedule-on-edit) is entirely new. Use RESEARCH `## Notification Service Architecture` as the spec. |
| `Support/NotificationCenterPort.swift` | service (port) | event-driven | No protocol-port + spy seam exists anywhere in the project (no dependency injection / mock pattern precedent). Production conformer wraps `UNUserNotificationCenter.current()`; `SpyCenter` test conformer is in-memory. Spec is RESEARCH `## Recommended seam (for testability)`. |

> Both files are L1-unit-testable by design (pure `buildRequests` + in-memory `SpyCenter`); notification **delivery**, the system permission prompt, Complete/Snooze, and deep-link are L3 **manual UAT** on the iPhone 17 simulator (RESEARCH `## Validation Architecture`).

---

## Metadata

**Analog search scope:** `MyHomeApp/Persistence/{Schema,Models}`, `MyHomeApp/Persistence/ModelContainer+App.swift`, `MyHomeApp/Features/{Expenses,Budgets}`, `MyHomeApp/Support`, `MyHomeApp/RootView.swift`, `MyHomeTests/`
**Files scanned:** 12 source + 3 test files read in full / targeted
**Pattern extraction date:** 2026-05-30
**Build env:** Swift 6.2 / SwiftUI / SwiftData, iOS 17+, Xcode 26.5, scheme/module `MyHome`, test target `MyHomeTests`, iPhone 17 simulator
