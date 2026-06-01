# Phase 4: Overview & Charts - Pattern Map

**Mapped:** 2026-06-01
**Files analyzed:** 11 (7 new, 1 extended, 1 modified, 2 new test files)
**Analogs found:** 11 / 11

---

## File Classification

| New/Modified File | Role | Data Flow | Closest Analog | Match Quality |
|-------------------|------|-----------|----------------|---------------|
| `MyHomeApp/Features/Overview/OverviewView.swift` | view (dashboard root) | request-response / CRUD-read | `MyHomeApp/Features/Budgets/BudgetsView.swift` | exact — same @Query-in-child + aggregation-in-body pattern |
| `MyHomeApp/Features/Overview/SpendBudgetCard.swift` | component (card) | request-response | `MyHomeApp/Features/Budgets/BudgetCategoryCard.swift` + `BudgetProgressView.swift` | exact — same card shell, BudgetColor fill, GeometryReader bar |
| `MyHomeApp/Features/Overview/TopCategoriesCard.swift` | component (card) | request-response | `MyHomeApp/Features/Budgets/BudgetsView.swift` (uncategorized row, lines 182–201) | role-match — same HStack row + card shell pattern |
| `MyHomeApp/Features/Overview/PinnedNoteCard.swift` | component (card) | request-response | `MyHomeApp/Features/Budgets/BudgetCategoryCard.swift` (card shell) + `NoteListOrganizer` | role-match — card shell identical; data source is NoteListOrganizer |
| `MyHomeApp/Features/Overview/SpendByCategoryChart.swift` | component (chart card) | request-response | `MyHomeApp/Features/Budgets/BudgetCategoryCard.swift` (card shell) | role-match — card shell; chart DSL is net-new (Swift Charts first use) |
| `MyHomeApp/Features/Overview/SpendOverTimeChart.swift` | component (chart card) | request-response | `MyHomeApp/Features/Budgets/BudgetCategoryCard.swift` (card shell) | role-match — card shell; chart + segmented control are net-new |
| `MyHomeApp/Support/SpendOverTimeAggregator.swift` | utility (pure helper) | transform / batch | `MyHomeApp/Support/CalendarAggregator.swift` | exact — same pure enum + static methods + startOfDay timezone pattern |
| `MyHomeApp/Support/Decimal+INR.swift` *(extend)* | utility (formatter extension) | transform | same file (lines 1–18) | exact — add `formattedINRCompact()` following identical extension pattern |
| `MyHomeApp/RootView.swift` *(modify)* | host (TabView shell) | event-driven | same file | — (in-place edit: reorder tabs, update deep-link constant) |
| `MyHomeTests/SpendOverTimeAggregatorTests.swift` | test | batch | `MyHomeTests/CalendarAggregationTests.swift` | exact — same @MainActor struct + in-memory ModelContainer + #expect pattern |
| `MyHomeTests/OverviewAggregationTests.swift` | test | batch | `MyHomeTests/BudgetCalculatorTests.swift` | exact — same makeContainer() helper + @MainActor + #expect pattern |

---

## Pattern Assignments

---

### `MyHomeApp/Features/Overview/OverviewView.swift` (view, dashboard root)

**Analog:** `MyHomeApp/Features/Budgets/BudgetsView.swift`

**Imports pattern** (BudgetsView.swift lines 1–2):
```swift
import SwiftUI
import SwiftData
```

**NavigationStack + toolbar + sheet pattern** (BudgetsView.swift lines 31–54):
```swift
var body: some View {
    NavigationStack {
        VStack(spacing: 0) {
            // ... content
        }
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
}
```
For OverviewView: replace the toolbar button with the `+` (Add Expense) button; replace `VStack` with `ScrollView` + `LazyVStack`.

**Child view re-init for scoped @Query** (BudgetsView.swift lines 36–39):
```swift
if let (start, end) = BudgetCalculator.monthBoundaries(for: viewedMonth) {
    BudgetsMonthView(start: start, end: end)
}
```
For OverviewView: pass current-month boundaries (no month-paging needed — always current month). Compute boundaries once in `var body` and pass to an inner `OverviewMonthContent` child that owns `@Query private var monthExpenses`.

**Child view @Query init pattern** (BudgetsView.swift lines 122–141):
```swift
private struct BudgetsMonthView: View {
    let start: Date
    let end: Date
    @Query(sort: \Category.sortOrder) private var categories: [Category]
    @Query private var monthExpenses: [Expense]

    init(start: Date, end: Date) {
        self.start = start
        self.end = end
        let lo = start
        let hi = end
        _monthExpenses = Query(
            filter: #Predicate<Expense> { expense in
                expense.date >= lo && expense.date <= hi
            },
            sort: \.date, order: .reverse
        )
    }
    // ...
}
```

**Pre-aggregation in body before passing to dumb cards** (BudgetsView.swift lines 143–145):
```swift
let spendByCategory = BudgetCalculator.monthlySpend(for: monthExpenses, categories: categories)
let uncategorizedTotal = BudgetCalculator.uncategorizedSpend(for: monthExpenses)
```
For OverviewView extend to:
```swift
let spendByCategory = BudgetCalculator.monthlySpend(for: monthExpenses, categories: categories)
let totalBudget: Decimal = categories.compactMap(\.monthlyBudget).reduce(.zero, +)
let totalSpend = spendByCategory.values.reduce(.zero, +)
    + BudgetCalculator.uncategorizedSpend(for: monthExpenses)
let sections = NoteListOrganizer.organize(allNotes)
```
Pass computed values down to card subviews — never pass raw `@Query` arrays into `Chart {}`.

---

### `MyHomeApp/Features/Overview/SpendBudgetCard.swift` (component, OVR-01)

**Analog:** `MyHomeApp/Features/Budgets/BudgetProgressView.swift` + `BudgetCategoryCard.swift`

**Card shell pattern** (BudgetCategoryCard.swift lines 47–56):
```swift
VStack(alignment: .leading, spacing: 8) {
    // ... rows
}
.padding(16)
.background(Color(.secondarySystemBackground))
.clipShape(RoundedRectangle(cornerRadius: 12))
.shadow(color: .black.opacity(0.04), radius: 2, y: 1)
.accessibilityElement(children: .combine)
```

**BudgetColor → SwiftUI Color mapping** (BudgetProgressView.swift lines 17–22):
```swift
private var fillColor: Color {
    switch data.colorThreshold {
    case .normal:     return .accentColor
    case .warning:    return Color(.systemOrange)
    case .overBudget: return Color(.systemRed)
    }
}
```
Copy this mapping verbatim for the aggregate bar's `barFillColor`.

**GeometryReader progress bar at fixed height** (BudgetProgressView.swift lines 36–55):
```swift
GeometryReader { geo in
    ZStack(alignment: .leading) {
        RoundedRectangle(cornerRadius: 4)
            .fill(Color(.secondarySystemBackground))
            .frame(height: 8)
        if let fraction = data.fractionUsed {
            RoundedRectangle(cornerRadius: 4)
                .fill(fillColor)
                .frame(
                    width: min(CGFloat(fraction), 1.0) * geo.size.width,
                    height: 8
                )
                .animation(.easeInOut(duration: 0.3), value: fraction)
        }
    }
}
.frame(height: 8)          // ← OVR-01 uses 16pt; copy pattern, change height + cornerRadius to 8
.accessibilityElement(children: .ignore)
```

**No-budget branch** (BudgetProgressView.swift lines 28–30):
```swift
if data.budget == nil {
    Text("No budget set")
        .font(.subheadline)
        .foregroundStyle(.tertiary)
}
```
For SpendBudgetCard: replace with inline "Set a budget to track your spending." prompt + `Button("Set a budget") { selectedTab = 2 }`.

**fractionUsed + colorThreshold inline** (BudgetCalculator.swift lines 41–56 for thresholds):
Since `BudgetProgressData` requires a `Category`, compute inline in the card:
```swift
// Inline fractionUsed for the aggregate bar (no Category instance needed):
let fractionUsed: Double? = totalBudget > 0
    ? Double(truncating: (totalSpend / totalBudget) as NSDecimalNumber)
    : nil
// Inline colorThreshold mirroring BudgetProgressData.colorThreshold:
let colorThreshold: BudgetColor = {
    guard let f = fractionUsed else { return .normal }
    if f >= 1.0 { return .overBudget }
    if f >= 0.8 { return .warning }
    return .normal
}()
```

---

### `MyHomeApp/Features/Overview/TopCategoriesCard.swift` (component, OVR-02)

**Analog:** `MyHomeApp/Features/Budgets/BudgetsView.swift` (uncategorized row, lines 182–201)

**Card shell pattern** — same as SpendBudgetCard above.

**HStack category row pattern** (BudgetsView.swift lines 182–201):
```swift
HStack {
    Image(systemName: "tray")
        .font(.body)
        .foregroundStyle(.secondary)
        .frame(width: 28, height: 28)
        .accessibilityHidden(true)
    Text("Uncategorized")
        .font(.body)
        .foregroundStyle(.primary)
    Spacer()
    Text(total.formattedINR())
        .font(.subheadline)
        .foregroundStyle(.secondary)
}
.padding(16)
.background(Color(.secondarySystemBackground))
.clipShape(RoundedRectangle(cornerRadius: 12))
.shadow(color: .black.opacity(0.04), radius: 2, y: 1)
```
For TopCategoriesCard: adapt to a `VStack` of rows (one per top-3 category), each row being an `HStack` with rank label + SF Symbol icon + category name + Spacer + ₹ amount. Row `minHeight: 44`.

**Sort + prefix(3) computation** (caller's body — mirrors BudgetsView.swift line 144 pattern):
```swift
// Compute in parent (OverviewView body), pass as pre-sorted array:
let top3: [(category: Category, spent: Decimal)] = categories
    .compactMap { cat -> (Category, Decimal)? in
        let spent = spendByCategory[cat.persistentModelID] ?? .zero
        return spent > 0 ? (cat, spent) : nil
    }
    .sorted {
        $0.1 != $1.1
            ? $0.1 > $1.1                           // descending spend
            : ($0.0.name ?? "") < ($1.0.name ?? "") // tie-break alphabetical
    }
    .prefix(3)
    .map { $0 }
```

---

### `MyHomeApp/Features/Overview/PinnedNoteCard.swift` (component, OVR-03)

**Analog:** `MyHomeApp/Features/Budgets/BudgetCategoryCard.swift` (card shell) + `MyHomeApp/Support/NoteListOrganizer.swift` (data)

**Card shell pattern** — identical to above (padding 16, secondarySystemBackground, cornerRadius 12, shadow 0.04).

**Accessibility combine pattern** (BudgetCategoryCard.swift line 52):
```swift
.accessibilityElement(children: .combine)
```

**NoteListOrganizer pinned access** (NoteListOrganizer.swift lines 59–75):
```swift
// Called by parent OverviewView; result passed as pinnedNote: Note? parameter:
let sections = NoteListOrganizer.organize(allNotes)
let pinnedNote: Note? = sections.pinned.first
// Fallback to first checklist note when no pinned note:
let checklistNote: Note? = pinnedNote == nil
    ? allNotes.first(where: { ($0.blocks ?? []).contains(where: { $0.kindRaw == "checkbox" }) })
    : nil
let displayNote: Note? = pinnedNote ?? checklistNote
```

**Deep-link navigation** (mirror of RootView.swift lines 44–50 pattern, but triggered programmatically):
```swift
// PinnedNoteCard receives @Binding var selectedTab: Int and @Binding var deepLinkNoteID: UUID?
// On "Open note" button tap:
Button("Open note") {
    deepLinkNoteID = note.id
    selectedTab = 3        // Notes is tag 3 after Phase 4 reorder
}
```

---

### `MyHomeApp/Features/Overview/SpendByCategoryChart.swift` (component, EXP-10)

**Analog:** `MyHomeApp/Features/Budgets/BudgetCategoryCard.swift` (card shell only; chart DSL is net-new)

**Card shell pattern** — identical to above.

**Data type for chart** (pure value struct, mirrors DayProgress from CalendarAggregator.swift lines 8–24):
```swift
struct CategorySpendItem: Identifiable {
    let id: PersistentIdentifier   // category's persistentModelID
    let name: String
    let spent: Double              // Decimal→Double at aggregation boundary
}
```

**BarMark chart pattern** (from 04-UI-SPEC.md Card 4 Row B — first use of Charts in project):
```swift
import Charts

Chart(categoryItems) { item in
    BarMark(
        x: .value("Amount", item.spent),
        y: .value("Category", item.name)
    )
    .foregroundStyle(Color.accentColor)
    .annotation(position: .trailing) {
        Text(Decimal(item.spent).formattedINRCompact())
            .font(.caption)
            .foregroundStyle(.secondary)
    }
    .accessibilityLabel("\(item.name), \(Decimal(item.spent).formattedINR())")
}
.chartXAxis(.hidden)
.chartYAxis {
    AxisMarks(values: .automatic) { _ in
        AxisValueLabel().font(.caption)
    }
}
.frame(height: 220)
.chartScrollableAxes(.vertical)
.accessibilityLabel("Spend by category chart")
```
**Note:** `Decimal` is not `Plottable` — `item.spent` must be `Double`, converted at the `CategorySpendItem` construction site, not inside `Chart {}`.

---

### `MyHomeApp/Features/Overview/SpendOverTimeChart.swift` (component, EXP-11)

**Analog:** `MyHomeApp/Features/Budgets/BudgetCategoryCard.swift` (card shell); `MyHomeApp/Support/CalendarAggregator.swift` (data shape)

**Card shell pattern** — identical to above.

**@State for segmented control** (mirrors BudgetsView.swift `@State private var viewedMonth`):
```swift
@State private var selectedRange: SpendRange = .month
```

**Picker segmented control** (mirrors Phase 2/3 segment patterns):
```swift
Picker("Range", selection: $selectedRange) {
    Text("Week").tag(SpendRange.week)
    Text("Month").tag(SpendRange.month)
    Text("Year").tag(SpendRange.year)
}
.pickerStyle(.segmented)
```

**LineMark + AreaMark chart pattern** (from 04-UI-SPEC.md Card 5 Row C — net-new):
```swift
Chart(bucketedData) { point in
    AreaMark(
        x: .value("Date", point.date),
        y: .value("Spend", point.spent)   // point.spent is Double
    )
    .foregroundStyle(Color.accentColor.opacity(0.15))

    LineMark(
        x: .value("Date", point.date),
        y: .value("Spend", point.spent)
    )
    .foregroundStyle(Color.accentColor)
    .lineStyle(StrokeStyle(lineWidth: 2))
    .symbol(.circle)
    .symbolSize(30)
    .accessibilityLabel("\(point.dateLabel), \(Decimal(point.spent).formattedINR())")
}
.chartXAxis {
    AxisMarks(values: .automatic) { value in
        AxisGridLine()
        AxisValueLabel(format: xAxisDateFormat(for: selectedRange))
            .font(.caption)
    }
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
.frame(height: 200)
.accessibilityLabel("Spend over time chart, \(selectedRange.label) view")
```

**Chart data aggregation** — called in parent's body before LazyVStack (anti-pattern prevention):
```swift
let bucketedData = SpendOverTimeAggregator.bucket(
    expenses: monthExpenses,
    range: selectedRange
)
```

---

### `MyHomeApp/Support/SpendOverTimeAggregator.swift` (utility, pure helper)

**Analog:** `MyHomeApp/Support/CalendarAggregator.swift` — exact structural mirror

**File header / doc-comment pattern** (CalendarAggregator.swift lines 27–40):
```swift
/// Pure static helper for [description] (requirement refs).
///
/// **Pure contract:** operates on already-fetched arrays; no SwiftData access,
/// no @Query, no SwiftUI. Mirrors the BudgetCalculator discipline.
///
/// Calendar fire-date bucketing follows Pitfall 5: all Date values are UTC instants;
/// bucketing into a calendar day is done using `Calendar.current` with
/// `TimeZone.current` (device timezone) so the displayed day matches the user's clock.
enum CalendarAggregator {
```

**`startOfDay` private helper** (CalendarAggregator.swift lines 44–49):
```swift
private static func startOfDay(_ date: Date) -> Date {
    var cal = Calendar.current
    cal.timeZone = TimeZone.current
    return cal.startOfDay(for: date)
}
```
Copy verbatim into `SpendOverTimeAggregator` — same timezone discipline.

**Value type output struct** (mirrors `DayProgress` from CalendarAggregator.swift lines 8–24):
```swift
struct SpendBucket: Identifiable {
    let id: Date        // start-of-day (week/month) or start-of-month (year) — device timezone
    let date: Date      // same as id; used as Chart x-axis value
    let spent: Double   // Decimal→Double conversion HERE via NSDecimalNumber(decimal:).doubleValue
    var dateLabel: String  // accessible label: "Mon 2 Jun" etc.
}
```

**SpendRange enum** (mirrors `NoteSegment` enum in NotesHomeView.swift lines 33–43):
```swift
enum SpendRange: String, CaseIterable {
    case week, month, year
    var label: String {
        switch self {
        case .week: return "Week"
        case .month: return "Month"
        case .year: return "Year"
        }
    }
}
```

**Public static method signature** (mirrors CalendarAggregator.swift line 103):
```swift
enum SpendOverTimeAggregator {
    static func bucket(
        expenses: [Expense],
        range: SpendRange,
        calendar: Calendar = .current
    ) -> [SpendBucket]
}
```

**Decimal → Double conversion at aggregation boundary** (from BudgetProgressData.swift line 43):
```swift
// Do NOT use Decimal inside chart value closures.
// Convert here, in the aggregator, not in the Chart {} DSL:
let d = NSDecimalNumber(decimal: spendMap[day] ?? .zero).doubleValue
```

---

### `MyHomeApp/Support/Decimal+INR.swift` *(extend — add `formattedINRCompact()`)*

**Analog:** Same file, lines 3–18 — add a second extension method following the identical pattern.

**Existing pattern to follow** (Decimal+INR.swift lines 3–18):
```swift
import Foundation

extension Decimal {
    func formattedINR() -> String {
        self.formatted(
            .currency(code: "INR")
            .locale(Locale(identifier: "en_IN"))
        )
    }
}
```

**New method to add** (immediately after `formattedINR()`):
```swift
/// Compact ₹ label for chart axes and bar annotations (Phase 4, EXP-10/11).
/// Full `formattedINR()` is used everywhere else.
/// Examples: Decimal(500) → "₹500", Decimal(5000) → "₹5k", Decimal(150000) → "₹1L"
func formattedINRCompact() -> String {
    let d = NSDecimalNumber(decimal: self).doubleValue
    if d >= 100_000 { return "₹\(Int(d / 100_000))L" }
    if d >= 1_000   { return "₹\(Int(d / 1_000))k" }
    return "₹\(Int(d))"
}
```

---

### `MyHomeApp/RootView.swift` *(modify — tab reorder + deep-link re-tag)*

**Analog:** Same file — in-place modification only.

**Current tab structure** (RootView.swift lines 24–52):
```swift
ExpenseListView()
    .tabItem { Label("Expenses", systemImage: "list.bullet") }
    .tag(0)

BudgetsView()
    .tabItem { Label("Budgets", systemImage: "chart.bar") }
    .tag(1)

NotesHomeView(deepLinkNoteID: $deepLinkNoteID, deepLinkBlockID: $deepLinkBlockID)
    .tabItem { Label("Notes", systemImage: "note.text") }
    .tag(2)

// line 49:
selectedTab = 2   // ← Notes deep-link constant
```

**Target state after Phase 4:**
```swift
OverviewView(selectedTab: $selectedTab, deepLinkNoteID: $deepLinkNoteID)
    .tabItem { Label("Home", systemImage: "house") }
    .tag(0)

ExpenseListView()
    .tabItem { Label("Expenses", systemImage: "list.bullet") }
    .tag(1)

BudgetsView()
    .tabItem { Label("Budgets", systemImage: "chart.bar") }
    .tag(2)

NotesHomeView(deepLinkNoteID: $deepLinkNoteID, deepLinkBlockID: $deepLinkBlockID)
    .tabItem { Label("Notes", systemImage: "note.text") }
    .tag(3)

// line 49 update:
selectedTab = 3   // ← ONLY change to the .onReceive handler
```
`@State private var selectedTab: Int = 0` stays at `0` — value unchanged, meaning changes (0 now means Overview, not Expenses).

---

### `MyHomeTests/SpendOverTimeAggregatorTests.swift` (test)

**Analog:** `MyHomeTests/CalendarAggregationTests.swift` — exact structural mirror

**File header + imports pattern** (CalendarAggregationTests.swift lines 1–17):
```swift
import Testing
import Foundation
import SwiftData
@testable import MyHome

// Requirements: [req refs]
// Validation command: xcodebuild test ... -only-testing:MyHomeTests/SpendOverTimeAggregatorTests

/// SpendOverTimeAggregatorTests — pure-logic tests for spend bucketing.
@MainActor
struct SpendOverTimeAggregatorTests {
```

**In-memory container pattern** (CalendarAggregationTests.swift lines 24–26):
```swift
let container = try ModelContainer(for: Note.self, NoteBlock.self,
    configurations: ModelConfiguration(isStoredInMemoryOnly: true))
```
For SpendOverTimeAggregatorTests: use `Expense.self, Category.self` — same `ModelConfiguration(isStoredInMemoryOnly: true)` idiom.

**Test method shape** (CalendarAggregationTests.swift lines 22–23):
```swift
@Test("perDayCountsAndProgress: per-day counts and x/y completion math correct — SC-R4(a,b)")
func perDayCountsAndProgress() throws {
    // Arrange / Act / Assert with #expect
}
```

**Key test cases to cover:**
- Week range → exactly 7 `SpendBucket` entries; zero-spend days present
- Month range → 28–31 entries; all dates in current month
- Year range → exactly 12 entries (one per month)
- Zero-spend scenario: all `bucket.spent == 0.0` when no expenses
- Decimal→Double conversion: `Decimal(1234.56)` rounds correctly at aggregation boundary

---

### `MyHomeTests/OverviewAggregationTests.swift` (test)

**Analog:** `MyHomeTests/BudgetCalculatorTests.swift` — exact structural mirror

**File header + makeContainer() pattern** (BudgetCalculatorTests.swift lines 1–19):
```swift
import Testing
import SwiftData
import Foundation
@testable import MyHome

private typealias Cat = MyHome.Category

@MainActor
struct OverviewAggregationTests {

    private func makeContainer() throws -> ModelContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: Expense.self, Cat.self, configurations: config)
    }
```

**@Test decorator + #expect pattern** (BudgetCalculatorTests.swift lines 24–40):
```swift
@Test("colorThreshold: budget 1000, spent 700 → fractionUsed 0.7, .normal, remaining 300")
func colorThresholdNormal() throws {
    let container = try makeContainer()
    let context = container.mainContext
    // ... setup
    #expect(data.colorThreshold == .normal)
    #expect(data.remaining == Decimal(300))
}
```

**Issue.record for nil-guard failures** (BudgetCalculatorTests.swift lines 37–39):
```swift
if let f = data.fractionUsed {
    #expect(f > 0.69 && f < 0.71, "Expected fractionUsed ≈ 0.7, got \(f)")
} else {
    Issue.record("fractionUsed must not be nil when budget is 1000")
}
```

**Key test cases to cover:**
- OVR-01: `fractionUsed = 0.5` → `.normal`; `fractionUsed = 0.85` → `.warning`; `fractionUsed = 1.1` → `.overBudget`
- OVR-01: `totalBudget == 0` → `fractionUsed` is nil → "no budget" branch
- OVR-02: 3 categories, sorted descending; alphabetical tie-break; only 1 category with spend → renders 1 row
- OVR-03: `NoteListOrganizer.organize(notes).pinned.first` returns pinned note; fallback to checklist note when none pinned; nil when neither

---

## Shared Patterns

### Card Shell
**Source:** `MyHomeApp/Features/Budgets/BudgetCategoryCard.swift` lines 47–56
**Apply to:** `SpendBudgetCard`, `TopCategoriesCard`, `PinnedNoteCard`, `SpendByCategoryChart`, `SpendOverTimeChart`
```swift
.padding(16)
.background(Color(.secondarySystemBackground))
.clipShape(RoundedRectangle(cornerRadius: 12))
.shadow(color: .black.opacity(0.04), radius: 2, y: 1)
.accessibilityElement(children: .combine)
```

### BudgetColor → SwiftUI Color Mapping
**Source:** `MyHomeApp/Features/Budgets/BudgetProgressView.swift` lines 17–22
**Apply to:** `SpendBudgetCard` bar fill color
```swift
switch colorThreshold {
case .normal:     return .accentColor
case .warning:    return Color(.systemOrange)
case .overBudget: return Color(.systemRed)
}
```

### GeometryReader Progress Bar at Fixed Height
**Source:** `MyHomeApp/Features/Budgets/BudgetProgressView.swift` lines 36–55
**Apply to:** `SpendBudgetCard` aggregate bar (use `height: 16`, `cornerRadius: 8` per UI-SPEC — double the Phase 2 values)
```swift
GeometryReader { geo in
    ZStack(alignment: .leading) {
        RoundedRectangle(cornerRadius: 4)
            .fill(Color(.secondarySystemBackground))
            .frame(height: 8)
        if let fraction = data.fractionUsed {
            RoundedRectangle(cornerRadius: 4)
                .fill(fillColor)
                .frame(width: min(CGFloat(fraction), 1.0) * geo.size.width, height: 8)
                .animation(.easeInOut(duration: 0.3), value: fraction)
        }
    }
}
.frame(height: 8)   // ← OVR-01: change to 16; cornerRadius to 8
.accessibilityElement(children: .ignore)
```

### Decimal → Double Conversion at Aggregation Boundary
**Source:** `MyHomeApp/Support/BudgetCalculator.swift` line 43 (`NSDecimalNumber` pattern)
**Apply to:** `SpendOverTimeAggregator` (SpendBucket.spent), `SpendByCategoryChart` data prep (CategorySpendItem.spent)
```swift
// CORRECT — convert in the aggregator/data-prep, never inside Chart {}:
let d = NSDecimalNumber(decimal: someDecimal).doubleValue
// Also acceptable (from BudgetProgressData.fractionUsed):
Double(truncating: (spent / budget) as NSDecimalNumber)
```

### startOfDay Timezone Helper
**Source:** `MyHomeApp/Support/CalendarAggregator.swift` lines 44–49
**Apply to:** `SpendOverTimeAggregator` (copy verbatim)
```swift
private static func startOfDay(_ date: Date) -> Date {
    var cal = Calendar.current
    cal.timeZone = TimeZone.current
    return cal.startOfDay(for: date)
}
```

### @Query Scoped by Date Range (Child View Re-init)
**Source:** `MyHomeApp/Features/Budgets/BudgetsView.swift` lines 122–141
**Apply to:** `OverviewView` inner content child (`OverviewMonthContent`)
```swift
_monthExpenses = Query(
    filter: #Predicate<Expense> { expense in
        expense.date >= lo && expense.date <= hi
    },
    sort: \.date, order: .reverse
)
```

### State: @Observable / @State Only (Never @StateObject)
**Source:** `MyHomeApp/Features/Budgets/BudgetsView.swift` — `@State private var viewedMonth`, `@State private var showManageCategories`
**Apply to:** All Phase 4 views — `@State` for local UI state; `@Query` for data; no `@StateObject`, `@ObservedObject`, `@Published`.

### Plain Text() for User Content (Security T-01-06)
**Source:** `MyHomeApp/Features/Expenses/AddExpenseView.swift` line 13 (doc comment)
**Apply to:** `PinnedNoteCard` — render `note.title` and block text via `Text(note.title)`, never `Text(AttributedString(markdown: note.title))`.

### Swift Testing Test Structure (@MainActor + #expect)
**Source:** `MyHomeTests/BudgetCalculatorTests.swift` lines 14–19
**Apply to:** `SpendOverTimeAggregatorTests`, `OverviewAggregationTests`
```swift
@MainActor
struct SomeTests {
    private func makeContainer() throws -> ModelContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: Expense.self, Category.self, configurations: config)
    }
}
```

---

## No Analog Found

All Phase 4 files have a close structural analog in the codebase. The only net-new surface area is the Swift Charts DSL (`import Charts`), for which the 04-RESEARCH.md Code Examples section and 04-UI-SPEC.md provide binding reference patterns.

| File | Role | Data Flow | Note |
|------|------|-----------|------|
| *(none)* | — | — | — |

---

## Metadata

**Analog search scope:** `MyHomeApp/Features/Budgets/`, `MyHomeApp/Features/Expenses/`, `MyHomeApp/Features/Notes/`, `MyHomeApp/Support/`, `MyHomeApp/RootView.swift`, `MyHomeTests/`
**Files scanned:** 12 source files + 6 test files
**Pattern extraction date:** 2026-06-01
