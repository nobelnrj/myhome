# Phase 4: Overview & Charts — Research

**Researched:** 2026-06-01
**Domain:** SwiftUI dashboard composition, Swift Charts (BarMark / LineMark), spend aggregation helpers, TabView reorder
**Confidence:** HIGH — all findings grounded in the actual codebase + Apple-platform stack already verified in prior phase research

---

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

- **D4-01** — Overview becomes `tag 0`, leftmost, AND the app's launch/default tab. Tabs shift: Overview(0) → Expenses(1) → Budgets(2) → Notes(3). Notes deep-link constant `selectedTab = 2` must be re-tagged to `selectedTab = 3`.
- **D4-02** — Aggregate bar compares current-month total spend vs. sum of ALL per-category `monthlyBudget` values. Reuse `BudgetCalculator` / `BudgetProgressData` / `BudgetColor` — do not re-derive spend or budget math.
- **D4-03** — Both Swift Charts live ON the Overview screen, scrolled below the summary cards. Overview is one rich scrolling dashboard, not a launchpad.
- **D4-04** — Spend-over-time ranges: Week / Month / Year (segmented control). Bucketing: Week → daily, Month → daily, Year → monthly. Keep range→bucket mapping in a small, testable helper.
- **D4-05** — Spend-by-category = `BarMark` (ranking); spend-over-time = `LineMark` (trend).
- **D4-06** — Quick-add reuses the existing `AddExpenseView` sheet verbatim. No new entry UI.
- **D4-07** — Cards always render; never hidden. Empty states: "Set a budget", "No spend yet", "Pin a note to see it here."

### Claude's Discretion

- Overview tab icon + label: `house` / "Home" (decided in UI-SPEC — treat as locked).
- OVR-03 fallback resolution: pinned first → checklist note → empty state.
- Top-3 tie-breaking: alphabetical by `category.name`.
- Chart axis/₹ formatting via `formattedINRCompact()` (new extension on `Decimal`).
- Aggregation in pure `Support/` helpers fed by `@Query` results — no repository layer.
- Overview root: `ScrollView` + `LazyVStack` (confirmed in UI-SPEC).

### Deferred Ideas (OUT OF SCOPE)

- All-time / multi-year spend-over-time range
- Donut/pie share-of-spend chart
- Additional charts (burn-down, per-tag, month-over-month)
- Quick-add note action from the pinned-note card
- Per-card customization / dashboard reordering
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| OVR-01 | Overview screen shows current-month total spend vs. total monthly budget as a single bar | `BudgetCalculator.monthlySpend` + `BudgetProgressData` + `BudgetColor` are the exact APIs; aggregate bar mirrors `BudgetProgressView` at 16pt height |
| OVR-02 | Overview screen shows the top 3 spend categories this month with absolute ₹ amounts | `BudgetCalculator.monthlySpend` returns `[PersistentIdentifier: Decimal]`; sort descending, take prefix(3), tie-break alphabetically |
| OVR-03 | Overview screen surfaces the most-recent pinned note (or latest checklist) as a card | `NoteListOrganizer.organize(notes).pinned.first`; fallback to first note with a checkbox block |
| OVR-04 | Overview screen exposes a quick-add expense `+` action | `AddExpenseView` presented via `.sheet(isPresented:)` from the navigation toolbar |
| EXP-10 | User can view a spend-by-category chart for the current month | Swift Charts `BarMark` (iOS 16+, well within iOS 17 target); data pre-aggregated via `BudgetCalculator.monthlySpend` |
| EXP-11 | User can view a spend-over-time chart across configurable date ranges | Swift Charts `LineMark` + `AreaMark`; new `SpendOverTimeAggregator` pure helper in `Support/`; `SpendRange` enum drives bucketing |
</phase_requirements>

---

## Summary

Phase 4 is a **read + compose** phase. No new `@Model` types, no schema migration (stays on SchemaV3), no new persisted state. The implementation work is: (1) add `OverviewView` with five card sections, (2) add `SpendOverTimeAggregator` + `SpendRange` + `SpendBucket` helpers in `Support/`, (3) add `formattedINRCompact()` to `Decimal+INR.swift`, (4) reorder `RootView.swift` TabView and update the one deep-link constant, and (5) write tests for the new pure helpers.

The phase's primary complexity is **not** the chart DSL — that's straightforward with Swift Charts. The two genuinely careful areas are: (a) pre-aggregating data **outside** the chart view body (Pitfall 15 — raw `@Query` into `Chart {}` causes re-layout on every micro-update), and (b) the date-bucketing math for spend-over-time (UTC dates stored, device-timezone display, all zero-spend buckets included so the line has no gaps).

**Primary recommendation:** Model `OverviewView` as a single `@Query`-holding view that passes pre-computed structs down to dumb card subviews. The aggregation step is a pure function call that goes in the `var body` computed path, not inside the chart DSL.

---

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| OVR-01 aggregate bar | Frontend view (OverviewView card) | Support/ pure helper (BudgetCalculator) | Existing BudgetCalculator owns the math; card owns the rendering |
| OVR-02 top-3 categories | Frontend view (OverviewView card) | Support/ pure helper (BudgetCalculator) | Sort + prefix(3) is 2 lines in the view using BudgetCalculator output |
| OVR-03 pinned note | Frontend view (OverviewView card) | Support/ pure helper (NoteListOrganizer) | NoteListOrganizer.organize already partitions pinned — call it directly |
| OVR-04 quick-add sheet | Frontend view (OverviewView toolbar) | Existing AddExpenseView (no changes) | Sheet presentation is 3 lines; AddExpenseView is unchanged |
| EXP-10 by-category chart | Frontend view (chart card) | Support/ (BudgetCalculator.monthlySpend for data) | Chart is display-only; data from BudgetCalculator |
| EXP-11 spend-over-time chart | Frontend view (chart card) | Support/ SpendOverTimeAggregator (new) | Bucketing logic must be testable; lives in Support/ |
| Tab reorder | Frontend host (RootView.swift) | — | Single file change: reorder TabView children, update tag integers, fix deep-link constant |
| formattedINRCompact() | Support/ (Decimal+INR.swift extension) | — | Axis/annotation formatting; chart-only, extends existing helper |

---

## Standard Stack

### Core (no new packages — zero external dependencies added in Phase 4)

| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| Swift Charts (`import Charts`) | iOS 16+ (iOS 17 target) | BarMark + LineMark + AreaMark | First-party Apple framework; no third-party charting library needed. Confirmed available on iOS 16+, well within the iOS 17 deployment target. [CITED: STACK.md] |
| SwiftUI | iOS 17+ | All UI | Project baseline; `@Observable`, `@State`, `@Query` — no change from prior phases |
| SwiftData | iOS 17+ (SchemaV3) | Data access via `@Query` | No schema changes; read-only over existing Expense / Category / Note / NoteBlock |
| Swift Testing | Toolchain (Xcode 26) | Unit tests for new pure helpers | Project standard (FND-06); `@MainActor` struct + `#expect` pattern already established |

### No New External Packages

Phase 4 introduces zero SPM dependencies. Swift Charts is a first-party Apple framework — `import Charts` is sufficient. [CITED: 04-UI-SPEC.md § Registry Safety]

### Package Legitimacy Audit

Not applicable — no external packages are introduced in this phase.

---

## Architecture Patterns

### System Architecture Diagram

```
User opens app
       │
       ▼
RootView (TabView)
 tag 0: OverviewView ◄─── DEFAULT LAUNCH TAB (D4-01)
 tag 1: ExpenseListView
 tag 2: BudgetsView
 tag 3: NotesHomeView ◄─── deepLinkNoteID / deepLinkBlockID bindings unchanged
       │
       ▼ (tab 0 selected)
OverviewView
  NavigationStack → ".navigationTitle("Home")"
  toolbar: + button → .sheet(AddExpenseView) ──► SwiftData insert (OVR-04)
  ScrollView
    LazyVStack(spacing: 16)
      │
      ├─ Card 1: SpendBudgetCard
      │    reads: @Query[Expense] (current month) + @Query[Category]
      │    computes: BudgetCalculator.monthlySpend + sum(monthlyBudget)
      │    renders: BudgetProgressData → BudgetColor → bar at 16pt
      │
      ├─ Card 2: TopCategoriesCard
      │    reads: same @Query results passed down
      │    computes: sorted + prefix(3)
      │
      ├─ Card 3: PinnedNoteCard
      │    reads: @Query[Note] (all notes, modifiedAt desc)
      │    computes: NoteListOrganizer.organize(notes).pinned.first
      │    fallback: first note with checkbox block
      │    action: selectedTab = 3, deepLinkNoteID = note.id
      │
      ├─ Card 4: SpendByCategoryChart (EXP-10)
      │    data: BudgetCalculator.monthlySpend → [CategorySpendItem]
      │    Swift Charts BarMark (horizontal, x=amount, y=category name)
      │
      └─ Card 5: SpendOverTimeChart (EXP-11)
           @State selectedRange: SpendRange = .month
           data: SpendOverTimeAggregator.bucket(expenses, range, calendar)
           Swift Charts LineMark + AreaMark
```

### Recommended Project Structure (Phase 4 additions only)

```
MyHomeApp/
├── Features/
│   ├── Overview/                          # NEW — Phase 4
│   │   ├── OverviewView.swift             # Root dashboard view (ScrollView + LazyVStack)
│   │   ├── SpendBudgetCard.swift          # OVR-01 aggregate bar card
│   │   ├── TopCategoriesCard.swift        # OVR-02 top-3 card
│   │   ├── PinnedNoteCard.swift           # OVR-03 pinned note card
│   │   ├── SpendByCategoryChart.swift     # EXP-10 BarMark chart card
│   │   └── SpendOverTimeChart.swift       # EXP-11 LineMark chart card
│   ├── Expenses/                          # UNCHANGED
│   ├── Budgets/                           # UNCHANGED
│   └── Notes/                            # UNCHANGED
├── Support/
│   ├── BudgetCalculator.swift             # UNCHANGED — reused for OVR-01/02/EXP-10
│   ├── CalendarAggregator.swift           # UNCHANGED — shape reference only
│   ├── NoteListOrganizer.swift            # UNCHANGED — reused for OVR-03
│   ├── Decimal+INR.swift                  # EXTENDED — add formattedINRCompact()
│   └── SpendOverTimeAggregator.swift      # NEW — EXP-11 bucketing helper
├── RootView.swift                          # MODIFIED — tab reorder + deep-link re-tag
└── Persistence/Models/                    # UNCHANGED — read-only
```

### Pattern 1: @Query in the parent view, pre-computed data passed to card subviews

**What:** `OverviewView` owns two `@Query` properties (expenses for current month, all categories, all notes). It calls aggregation helpers in `var body` and passes simple value-type structs to child card views.

**When to use:** Always for Phase 4 — avoids chart re-layout from live-model changes and keeps card views dumb/testable.

**Example:**
```swift
// Source: Pitfall 15 prevention + existing BudgetsMonthView pattern
struct OverviewView: View {
    @Query private var categories: [Category]
    @Query private var allNotes: [Note]
    // Current-month expenses via child view re-init pattern (same as BudgetsMonthView)
    // ...

    var body: some View {
        // Pre-aggregate OUTSIDE the Chart DSL
        let spendByCategory = BudgetCalculator.monthlySpend(
            for: monthExpenses, categories: categories)
        let totalBudget = categories.compactMap(\.monthlyBudget).reduce(.zero, +)
        let totalSpend = spendByCategory.values.reduce(.zero, +)
        let sections = NoteListOrganizer.organize(allNotes)

        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                SpendBudgetCard(totalSpend: totalSpend, totalBudget: totalBudget)
                TopCategoriesCard(spendByCategory: spendByCategory, categories: categories)
                PinnedNoteCard(pinnedNote: sections.pinned.first, allNotes: allNotes,
                               selectedTab: $selectedTab, deepLinkNoteID: $deepLinkNoteID)
                SpendByCategoryChart(spendByCategory: spendByCategory, categories: categories)
                SpendOverTimeChart(expenses: monthExpenses)
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
        }
    }
}
```

### Pattern 2: Child view re-init for scoped @Query (current-month expenses)

**What:** The same pattern as `BudgetsMonthView` in `BudgetsView.swift` — a private inner view that accepts `start: Date` and `end: Date` and initialises its `@Query` with those bounds. `OverviewView` re-initialises it with current-month boundaries computed from `BudgetCalculator.monthBoundaries`.

**Why:** `@Query` with a `#Predicate` that uses a date range requires the predicate constants to be captured at init time. The child-view re-init pattern is the established project solution (see `BudgetsMonthView`).

**Example (existing code in BudgetsView.swift — mirror this):**
```swift
// Source: MyHomeApp/Features/Budgets/BudgetsView.swift lines 122–141
private struct BudgetsMonthView: View {
    let start: Date
    let end: Date
    @Query private var monthExpenses: [Expense]

    init(start: Date, end: Date) {
        self.start = start
        self.end = end
        let lo = start, hi = end
        _monthExpenses = Query(
            filter: #Predicate<Expense> { expense in
                expense.date >= lo && expense.date <= hi
            },
            sort: \.date, order: .reverse
        )
    }
}
```

### Pattern 3: SpendOverTimeAggregator — mirrors CalendarAggregator

**What:** A pure `enum SpendOverTimeAggregator` with a single static method. Input: `[Expense]` + `SpendRange` + `Calendar`. Output: `[SpendBucket]` covering all date slots in the range, including zero-spend buckets.

**Contract (binding for implementation):**
```swift
// Source: 04-UI-SPEC.md § Chart Implementation Notes
enum SpendRange { case week, month, year
    var label: String { /* "Week" / "Month" / "Year" */ }
}

struct SpendBucket: Identifiable {
    let id: Date          // start-of-day (week/month) or start-of-month (year) in device timezone
    let date: Date        // same as id; used as Chart x-axis value
    let spent: Double     // Decimal→Double conversion happens HERE, not inside chart DSL
    var dateLabel: String // for accessibilityLabel: "Mon 2 Jun" etc.
}

enum SpendOverTimeAggregator {
    static func bucket(
        expenses: [Expense],
        range: SpendRange,
        calendar: Calendar = .current
    ) -> [SpendBucket]
}
```

**Key constraint:** `Decimal` is NOT `Plottable`. Convert `Decimal` → `Double` at the aggregation boundary (`NSDecimalNumber(decimal: x).doubleValue`) — money arithmetic stays `Decimal` throughout, only the final chart-input value is `Double`. [CITED: 04-UI-SPEC.md § Chart Implementation Notes item 3]

**Zero-spend buckets:** Every date slot in the range MUST appear in the output array even if spend is 0. Omitting zero points creates misleading gaps in the LineMark. [CITED: 04-UI-SPEC.md § Card 5 Zero-spend buckets]

**Date bucketing (UTC → device timezone):** Use `Calendar.current` with `TimeZone.current`. Week bucketing: 7 consecutive days ending today (or the 7 most-recent days in the range). Month bucketing: all calendar days in the current month. Year bucketing: 12 months in the current year, keyed to the start of each month.

```swift
// Source: 04-CONTEXT.md D4-04 + CalendarAggregator.swift pattern
// All bucket keys are "start of day" in device timezone, mirroring CalendarAggregator.startOfDay
private static func startOfDay(_ date: Date, calendar: Calendar) -> Date {
    var cal = calendar
    cal.timeZone = TimeZone.current
    return cal.startOfDay(for: date)
}
```

### Pattern 4: Tab reorder + deep-link re-tag

**What:** `RootView.swift` currently has 3 tabs. Phase 4 inserts Overview as `tag 0` and shifts the existing three tabs to `tag 1`, `2`, `3`. One deep-link constant must be updated.

**Exact changes (grounded in actual source):**

Current `RootView.swift` (lines 24-52):
- `ExpenseListView` → `tag: 0` (line 29)
- `BudgetsView` → `tag: 1` (line 35)
- `NotesHomeView` → `tag: 2` (line 41)
- `selectedTab = 2` in the `.onReceive` handler (line 49) — the Notes deep-link

After Phase 4:
- **Add** `OverviewView` → `tag: 0`, and set `@State private var selectedTab: Int = 0` (already is 0 — no change to the initial value, but now 0 means Overview, not Expenses)
- `ExpenseListView` → `tag: 1`
- `BudgetsView` → `tag: 2`
- `NotesHomeView` → `tag: 3`
- **Update** `selectedTab = 2` to `selectedTab = 3` in the `.onReceive` handler (line 49) — the only reference

`deepLinkNoteID` and `deepLinkBlockID` bindings passed to `NotesHomeView` are unchanged. The Notes deep-link mechanism (kOpenNoteNotification → RootView.onReceive → set deepLinkNoteID + selectedTab) is unchanged except the constant.

No other files reference `selectedTab` — confirmed by grep (RootView.swift is the only reference site).

### Anti-Patterns to Avoid

- **Raw `@Query` result into `Chart {}`:** Do not write `Chart(monthExpenses) { ... }`. Always pre-aggregate to a small value-type array first. [Pitfall 15, PITFALLS.md]
- **`@StateObject` / `@ObservedObject` / `@Published`:** Use `@Observable` + `@State`. Never the Combine-era types. [Pitfall 10, PITFALLS.md]
- **`Decimal` inside chart value closures:** Swift Charts requires `Plottable` types; `Decimal` is not `Plottable`. Convert at the aggregation layer, not inside `.value("Spend", item.spent)`.
- **Omitting zero-spend date buckets:** Produces misleading gaps in the LineMark. Always emit all buckets.
- **`GeometryReader` inside `LazyVStack` without a fixed height:** GeometryReader in a lazy container can collapse. Always `.frame(height: N)` on the GeometryReader container.
- **Re-implementing month boundary math:** Use `BudgetCalculator.monthBoundaries(for:)`. Already tested; do not duplicate.

---

## Concrete API Signatures — Verified from Source

### BudgetCalculator (`MyHomeApp/Support/BudgetCalculator.swift`)

```swift
// Returns spend per category keyed by PersistentIdentifier
static func monthlySpend(
    for expenses: [Expense],
    categories: [Category]
) -> [PersistentIdentifier: Decimal]

// Returns total spend for expenses with no category
static func uncategorizedSpend(for expenses: [Expense]) -> Decimal

// Returns (start, end) bounds for a calendar month in the user's timezone
static func monthBoundaries(for month: DateComponents) -> (start: Date, end: Date)?
```

**How to build totalBudget for OVR-01:**
```swift
// No existing BudgetCalculator method for aggregate total budget — compute inline:
let totalBudget: Decimal = categories.compactMap(\.monthlyBudget).reduce(.zero, +)
// hasBudget: totalBudget > 0
```

**How to build totalSpend for OVR-01:**
```swift
let spendMap = BudgetCalculator.monthlySpend(for: monthExpenses, categories: categories)
let totalSpend = spendMap.values.reduce(.zero, +)
// Note: uncategorized spend is NOT included in spendMap; add if needed:
// let totalSpend = spendMap.values.reduce(.zero, +) + BudgetCalculator.uncategorizedSpend(for: monthExpenses)
// D4-02 says "total spend vs total budget"; include all spend (categorized + uncategorized).
```

**Note on total spend scope:** `BudgetCalculator.monthlySpend` only sums expenses that have a category. Uncategorized expenses are separate (`uncategorizedSpend`). For OVR-01's "current-month total spend" the planner should decide whether to include uncategorized in the aggregate — the UI-SPEC does not specify explicitly. The most natural reading of "total spend" includes uncategorized. [ASSUMED — planner should resolve]

### BudgetProgressData and BudgetColor

```swift
// Pure value type — accepts Decimal values directly, no @Model required
struct BudgetProgressData {
    let category: Category   // needed for colorThreshold logic
    let spent: Decimal
    let budget: Decimal?
    var remaining: Decimal?  { get }
    var fractionUsed: Double? { get }
    var colorThreshold: BudgetColor { get }
}

enum BudgetColor { case normal, warning, overBudget }
```

**For OVR-01 aggregate bar:** There is no `Category` to pass. The planner needs to decide: either (a) compute `fractionUsed` and `colorThreshold` inline in the card view using the same threshold logic, or (b) create a lightweight helper that replicates the threshold logic without a `Category`. Option (a) is simpler and avoids a new type. [Planner's call — Claude's discretion per D4-08]

**BudgetColor → SwiftUI Color mapping** (from `BudgetProgressView.swift` lines 16-22):
```swift
// Reuse this exact mapping in OverviewView's aggregate bar card:
switch colorThreshold {
case .normal:     Color.accentColor
case .warning:    Color(.systemOrange)
case .overBudget: Color(.systemRed)
}
```

### NoteListOrganizer (`MyHomeApp/Support/NoteListOrganizer.swift`)

```swift
enum NoteListOrganizer {
    static func organize(_ notes: [Note]) -> NoteListSections
}

struct NoteListSections {
    let dailyRoutine: [Note]   // daily-recurring reminder notes
    let pinned: [Note]          // isPinned == true AND not daily-recurring
    let other: [Note]           // everything else
}
```

**OVR-03 implementation:**
```swift
let sections = NoteListOrganizer.organize(allNotes)
let pinnedNote = sections.pinned.first   // most-recent pinned (input is modifiedAt desc)
// Fallback: first note with at least one checkbox block
let checklistNote = pinnedNote == nil
    ? allNotes.first(where: { ($0.blocks ?? []).contains(where: { $0.kindRaw == "checkbox" }) })
    : nil
let displayNote = pinnedNote ?? checklistNote  // nil → empty state
```

### Decimal+INR (`MyHomeApp/Support/Decimal+INR.swift`)

Existing:
```swift
extension Decimal {
    func formattedINR() -> String  // "₹1,00,000.00" — full Indian lakh formatting
}
```

**New (add in Phase 4):**
```swift
// Source: 04-UI-SPEC.md § Chart Implementation Notes item 6
extension Decimal {
    func formattedINRCompact() -> String {
        let d = NSDecimalNumber(decimal: self).doubleValue
        if d >= 100_000 { return "₹\(Int(d / 100_000))L" }
        if d >= 1_000   { return "₹\(Int(d / 1_000))k" }
        return "₹\(Int(d))"
    }
}
```
Use `formattedINRCompact()` only for chart axis labels and bar annotations. Use `formattedINR()` everywhere else.

### AddExpenseView (`MyHomeApp/Features/Expenses/AddExpenseView.swift`)

`AddExpenseView` is a `View` struct with no required init parameters — takes everything from `@Environment`. Present as:

```swift
// Source: AddExpenseView.swift — no public init parameters needed
.sheet(isPresented: $showAddExpense) {
    AddExpenseView()
}
```

The sheet handles its own `dismiss()` after save or cancel. The `@Query`-driven Overview auto-refreshes via SwiftData reactivity after the sheet saves an expense — no manual refresh needed. [CITED: 04-CONTEXT.md D4-06]

### RootView.swift — Current Tab Tag Map

Verified from source (lines 24-52):
```
tag 0 → ExpenseListView    (currently Expenses)
tag 1 → BudgetsView        (currently Budgets)
tag 2 → NotesHomeView      (currently Notes)
selectedTab = 2 in .onReceive handler (line 49) — Notes deep-link
```

Phase 4 target:
```
tag 0 → OverviewView       (NEW default launch tab, sf symbol: "house")
tag 1 → ExpenseListView
tag 2 → BudgetsView
tag 3 → NotesHomeView
selectedTab = 3 in .onReceive handler — MUST update
```

### Expense and Category Model Fields (SchemaV3)

```swift
// Expense — relevant fields for Phase 4 aggregation
var amount: Decimal      // spend amount (negative = refund)
var date: Date           // UTC; filter by current month boundaries
var categories: [Category] = []  // to-many; v1 UI uses .first

// Category — relevant fields
var name: String?        // display name (optional per CloudKit rules)
var symbolName: String?  // SF Symbol name
var monthlyBudget: Decimal?  // nil = no budget set
var sortOrder: Int       // for ordering (not used for spend ranking)

// Note — relevant fields for OVR-03
var title: String = ""
var isPinned: Bool = false
var modifiedAt: Date     // used for ordering (@Query sort)
var blocks: [NoteBlock]? = []  // nil or array

// NoteBlock — relevant fields for OVR-03 fallback
var kindRaw: String      // "text" | "checkbox"
var text: String
var isChecked: Bool
```

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Month boundary math | Custom date arithmetic | `BudgetCalculator.monthBoundaries(for:)` | Already tested; Pitfall 3 (incorrect month edge at timezone boundary) |
| Category spend totals | Custom reduce loop | `BudgetCalculator.monthlySpend(for:categories:)` | Already handles the `categories.first` convention and refund reduction |
| Budget color thresholds | Re-derive 80%/100% logic | `BudgetColor` enum + existing mapping | OVR-01 MUST be visually consistent with Budgets tab per D4-02 |
| Note section partitioning | Custom isPinned filter | `NoteListOrganizer.organize(_:).pinned` | Already handles dailyRoutine exclusion — a note can be pinned AND daily-recurring; the organizer correctly excludes daily-routine from pinned |
| Chart Y-axis ₹ labels | `formattedINR()` on axis | New `formattedINRCompact()` (add to Decimal+INR.swift) | Full INR format is too wide for chart axes at small widths |
| INR number parsing / display | Custom String(format:) | `formattedINR()` / `formattedINRCompact()` | FND-07 requires `en_IN` locale; hand-rolling breaks lakh grouping |
| Decimal→Plottable | Custom conformance | `NSDecimalNumber(decimal: x).doubleValue` at aggregation boundary | `Decimal` is not `Plottable`; conversion must happen before Chart DSL |

---

## Common Pitfalls

### Pitfall A: Raw @Query array passed directly into Chart { }

**What goes wrong:** Every `Expense` insertion (including after using the quick-add sheet) causes the chart to re-layout. With 200+ data points, animation judders during scroll.

**How to avoid:** Pre-aggregate in `var body` before the `LazyVStack`. The aggregated array (5–14 category items, or 7/28–31/12 time buckets) is small and stable. Use `.animation(.default, value: aggregatedData)` only if the aggregated result changes (it changes at most once per expense add). [CITED: PITFALLS.md Pitfall 15]

### Pitfall B: Decimal not Plottable

**What goes wrong:** Build-time error or silent chart rendering failure when passing `Decimal` values to `.value("Amount", item.spent)`.

**How to avoid:** `SpendBucket.spent` and `CategorySpendItem.spent` are `Double` (converted at the aggregation boundary). Money arithmetic stays `Decimal` inside `BudgetCalculator` and `SpendOverTimeAggregator`. [CITED: 04-UI-SPEC.md Chart Implementation Notes item 3]

### Pitfall C: Missing zero-spend buckets in spend-over-time

**What goes wrong:** On days/months with no expenses, those date slots are absent from the aggregation output. The LineMark renders a gap or skips data points, creating a misleading chart.

**How to avoid:** `SpendOverTimeAggregator` must generate all slots for the range first (as a sequence of dates), then fill in spend from the expense data. Default spend for empty slots is `0.0` (Double). [CITED: 04-UI-SPEC.md Card 5 Zero-spend buckets]

### Pitfall D: Tab tag integer drift (selectedTab = 2 deep-link)

**What goes wrong:** Notes notification banner taps after Phase 4 navigate to the Budgets tab (tag 2) instead of Notes (now tag 3). The fix is one integer in one place.

**How to avoid:** There is exactly ONE place in the codebase where `selectedTab = 2` is written as a Notes deep-link: `RootView.swift` line 49. Update it to `selectedTab = 3`. No other file references `selectedTab`. [VERIFIED — grep of `MyHomeApp/` confirms single reference site]

### Pitfall E: NoteListOrganizer pinned vs. dailyRoutine confusion

**What goes wrong:** A note can be both pinned AND daily-recurring. If you filter on `note.isPinned` directly, you may surface a daily-routine note in OVR-03 that `NoteListOrganizer` correctly excludes from the pinned section.

**How to avoid:** Always call `NoteListOrganizer.organize(allNotes).pinned.first` — do not filter `allNotes` with `note.isPinned` directly. The organizer's partition rule explicitly excludes daily-recurring notes from `pinned`. [VERIFIED: NoteListOrganizer.swift lines 64-70]

### Pitfall F: GeometryReader height collapse in LazyVStack

**What goes wrong:** The aggregate bar uses `GeometryReader` to fill at `min(fraction, 1.0) * geo.size.width`. Inside a `LazyVStack`, a `GeometryReader` with no fixed height collapses to zero.

**How to avoid:** Always `.frame(height: 16)` on the `GeometryReader` container. [CITED: 04-UI-SPEC.md Card 1 Row C + BudgetProgressView.swift pattern]

### Pitfall G: chartScrollableAxes conflicts with parent ScrollView

**What goes wrong:** If `chartScrollableAxes(.vertical)` is applied to the spend-by-category chart inside the outer `ScrollView`, scroll gestures may conflict or the chart may not scroll.

**How to avoid:** According to the UI-SPEC, `.chartScrollableAxes(.vertical)` uses SwiftUI's built-in chart scroll handling which respects the parent scroll view. This is the documented approach; however the planner should note it requires iOS 17+ (confirmed) and the chart height must be fixed to prevent infinite expansion. [ASSUMED — verify in simulator; if conflict occurs, cap chart to 7 categories without scroll]

---

## Code Examples

### BarMark (EXP-10) — Horizontal spend-by-category

```swift
// Source: 04-UI-SPEC.md Card 4 Row B
Chart(categoryItems.sorted { $0.spent > $1.spent }) { item in
    BarMark(
        x: .value("Amount", item.spent),   // item.spent is Double
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
```

### LineMark + AreaMark (EXP-11) — Spend over time

```swift
// Source: 04-UI-SPEC.md Card 5 Row C
Chart(bucketedData) { point in
    AreaMark(
        x: .value("Date", point.date),
        y: .value("Spend", point.spent)  // point.spent is Double
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

X-axis date format helper:
```swift
// Source: 04-UI-SPEC.md Card 5 X-axis date formats
func xAxisDateFormat(for range: SpendRange) -> Date.FormatStyle {
    switch range {
    case .week:  return .dateTime.weekday(.abbreviated)    // "Mon"
    case .month: return .dateTime.day()                    // "1"
    case .year:  return .dateTime.month(.abbreviated)      // "Jan"
    }
}
```

### SpendOverTimeAggregator — Week bucketing example

```swift
// Source: 04-CONTEXT.md D4-04, 04-UI-SPEC.md SpendOverTimeAggregator shape
// Week → 7 daily buckets (last 7 days including today)
private static func weekBuckets(
    expenses: [Expense],
    calendar: Calendar
) -> [SpendBucket] {
    var cal = calendar
    cal.timeZone = TimeZone.current
    let today = cal.startOfDay(for: Date())
    // 7 slots: today-6 through today
    let slots: [Date] = (0..<7).map { offset in
        cal.date(byAdding: .day, value: -(6 - offset), to: today)!
    }
    // Build spend map keyed by start-of-day
    var spendMap: [Date: Decimal] = [:]
    for expense in expenses {
        let key = cal.startOfDay(for: expense.date)
        if slots.contains(key) {
            spendMap[key, default: .zero] += expense.amount
        }
    }
    return slots.map { day in
        let d = NSDecimalNumber(decimal: spendMap[day] ?? .zero).doubleValue
        return SpendBucket(id: day, date: day, spent: max(d, 0),
                           dateLabel: day.formatted(.dateTime.weekday(.wide).day().month()))
    }
}
```

---

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| `ObservableObject` / `@Published` / `@StateObject` | `@Observable` macro + `@State` | iOS 17 / Swift 5.9 | All helpers must use Observation framework — project already all-in |
| `NumberFormatter` for currency | `FormatStyle.currency(code:INR).locale(en_IN)` | iOS 15 | `formattedINR()` already uses modern API; do not introduce `NumberFormatter` |
| DGCharts (third-party) | Swift Charts (first-party, iOS 16+) | iOS 16 | No alternative; Swift Charts is the only right choice |
| `UICollectionView` for scroll perf | `LazyVStack` in `ScrollView` | iOS 14+ | `LazyVStack` renders chart cards lazily on scroll |

---

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | OVR-01 "total spend" includes uncategorized expenses (not just categorized) | Concrete API Signatures § BudgetCalculator | If wrong, the bar understates actual spend; planner should confirm with `BudgetCalculator.uncategorizedSpend` inclusion |
| A2 | `chartScrollableAxes(.vertical)` on the spend-by-category chart cooperates with the parent `ScrollView` without gesture conflict | Common Pitfalls § Pitfall G | If it conflicts, cap to 7 categories with no scroll (still meets EXP-10) |
| A3 | `formattedINRCompact()` lakh threshold is `>= 100_000` (as in UI-SPEC) | Code Examples (Decimal+INR extension) | If wrong, axis labels will show "₹100k" instead of "₹1L" for amounts ≥ ₹1,00,000 |

---

## Open Questions

1. **OVR-01 totalSpend scope: include uncategorized?**
   - What we know: `BudgetCalculator.monthlySpend` only counts categorized expenses. `uncategorizedSpend` is separate.
   - What's unclear: Should the aggregate "total spend" bar include uncategorized expenses?
   - Recommendation: Yes, include them — "total spend" should mean all spending. Wire as `totalSpend = spendMap.values.reduce(.zero, +) + BudgetCalculator.uncategorizedSpend(for: monthExpenses)`.

2. **BudgetProgressData for the aggregate bar: Category-free fractionUsed?**
   - What we know: `BudgetProgressData` requires a `Category` instance. The aggregate bar has no single category.
   - What's unclear: How to produce `fractionUsed` and `colorThreshold` for the aggregate card without a Category.
   - Recommendation: Compute inline in `SpendBudgetCard`: `let fraction = totalBudget > 0 ? Double(truncating: (totalSpend / totalBudget) as NSDecimalNumber) : nil`. Apply the same 0.8/1.0 thresholds directly. This avoids creating a stub Category.

---

## Environment Availability

Step 2.6: No new external dependencies. Phase 4 only needs what Phases 1–3 already required: Xcode 26.5, iPhone 17 simulator, Swift 6.2 toolchain. Swift Charts (`import Charts`) is a first-party Apple framework — no installation step.

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| Swift Charts (`import Charts`) | EXP-10, EXP-11 | ✓ | iOS 16+ (well within iOS 17 target) | — |
| SwiftData (SchemaV3) | All cards | ✓ | Phase 3 established | — |
| Xcode 26.5 | Build/sim | ✓ | Confirmed in MEMORY.md | — |
| iPhone 17 simulator | Testing | ✓ | Confirmed in MEMORY.md | — |

---

## Validation Architecture

Nyquist validation is enabled (`workflow.nyquist_validation: true` in config.json).

### Test Framework

| Property | Value |
|----------|-------|
| Framework | Swift Testing (bundled, no SPM dep) |
| Config file | Xcode Test Plan (existing `MyHomeTests` target) |
| Quick run command | `xcodebuild test -scheme MyHome -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:MyHomeTests/SpendOverTimeAggregatorTests` |
| Full suite command | `xcodebuild test -scheme MyHome -destination 'platform=iOS Simulator,name=iPhone 17'` |

### Phase Requirements → Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| OVR-01 | Aggregate bar: fractionUsed = totalSpend / totalBudget; thresholds 0.8 / 1.0 | unit | `…-only-testing:MyHomeTests/OverviewAggregationTests` | ❌ Wave 0 |
| OVR-01 | "No budget set" when totalBudget == 0 | unit | same file | ❌ Wave 0 |
| OVR-02 | Top-3 sorted by spend desc; tie-break alphabetical; fewer than 3 renders correctly | unit | `…-only-testing:MyHomeTests/OverviewAggregationTests` | ❌ Wave 0 |
| OVR-03 | Pinned note surfaced; fallback to checklist note; empty state when neither | unit | `…-only-testing:MyHomeTests/OverviewAggregationTests` | ❌ Wave 0 |
| EXP-10 | (display-only chart; data from BudgetCalculator already tested in BudgetCalculatorTests) | — | existing BudgetCalculatorTests | ✅ |
| EXP-11 | Week→7 daily buckets; Month→28-31 daily; Year→12 monthly; all slots emitted even at 0 | unit | `…-only-testing:MyHomeTests/SpendOverTimeAggregatorTests` | ❌ Wave 0 |
| EXP-11 | Zero-spend month: all buckets present with spent = 0.0 | unit | same file | ❌ Wave 0 |
| EXP-11 | Decimal→Double conversion: no money rounding in display | unit | same file | ❌ Wave 0 |
| D4-01 | Tab reorder: Overview is tag 0, Notes is tag 3 | manual smoke | app launch → check tab order | — |
| formattedINRCompact() | < 1000 → "₹N"; ≥ 1000 → "₹Nk"; ≥ 100000 → "₹NL" | unit | `…-only-testing:MyHomeTests/DecimalINRTests` | ❌ Wave 0 |

### Sampling Rate

- **Per task commit:** `xcodebuild test -scheme MyHome -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:MyHomeTests/SpendOverTimeAggregatorTests -only-testing:MyHomeTests/OverviewAggregationTests`
- **Per wave merge:** Full suite: `xcodebuild test -scheme MyHome -destination 'platform=iOS Simulator,name=iPhone 17'`
- **Phase gate:** Full suite green before `/gsd-verify-work`

### Wave 0 Gaps

- [ ] `MyHomeTests/SpendOverTimeAggregatorTests.swift` — covers EXP-11 bucketing (week/month/year), zero-spend slots, Decimal→Double boundary
- [ ] `MyHomeTests/OverviewAggregationTests.swift` — covers OVR-01 threshold math, OVR-02 top-3 sort + tie-break, OVR-03 pinned/fallback/empty logic
- [ ] `MyHomeTests/DecimalINRTests.swift` — covers `formattedINRCompact()` thresholds (< 1000, 1000–99999, ≥ 100000)

**Note:** `BudgetCalculatorTests.swift` already exists and covers `monthlySpend`, `monthBoundaries`, `BudgetProgressData`, and `BudgetColor`. No new tests needed for those existing helpers.

---

## Security Domain

`security_enforcement: true` in config.json. ASVS Level 1.

| ASVS Category | Applies | Standard Control |
|---------------|---------|-----------------|
| V2 Authentication | No | Phase 4 is read-only display; no auth flows |
| V3 Session Management | No | No session state introduced |
| V4 Access Control | No | Read-only overview; no write paths beyond the existing AddExpenseView sheet |
| V5 Input Validation | Minimal | No user text input in Phase 4 except the existing AddExpenseView (already validated with T-01-03 amount guard in existing code) |
| V6 Cryptography | No | No new secret storage |

**Threat patterns for Phase 4:**

| Pattern | STRIDE | Standard Mitigation |
|---------|--------|---------------------|
| Chart axis label injection | Spoofing/Tampering | Labels derive from `Decimal.formattedINRCompact()` — pure math, no user-supplied strings ever rendered as axis labels |
| Note content in OVR-03 card preview | Info Disclosure | Renders via plain `Text()` with `lineLimit(2)` — never `AttributedString(markdown:)` (T-01-06 / T-03-09 patterns from prior phases) |
| Deep-link tab switch to wrong tab | Tampering | `selectedTab = 3` is an integer assignment to a local `@State`; no URL parsing, no external input |

No new threat surface. Phase 4 is read-only composition over already-validated Phase 1–3 data.

---

## Sources

### Primary (HIGH confidence)
- `MyHomeApp/RootView.swift` — exact tab tags, `selectedTab` initial value, single `selectedTab = 2` deep-link reference (line 49)
- `MyHomeApp/Support/BudgetCalculator.swift` — exact signatures for `monthlySpend`, `uncategorizedSpend`, `monthBoundaries`, `BudgetProgressData`, `BudgetColor`
- `MyHomeApp/Support/NoteListOrganizer.swift` — exact `organize(_:)` signature and partition rules; confirms dailyRoutine exclusion from pinned
- `MyHomeApp/Support/Decimal+INR.swift` — existing `formattedINR()` implementation; confirms extension pattern for `formattedINRCompact()`
- `MyHomeApp/Support/CalendarAggregator.swift` — shape reference for `SpendOverTimeAggregator`; `startOfDay` + timezone pattern
- `MyHomeApp/Features/Expenses/AddExpenseView.swift` — no-parameter init; `dismiss()` after save; confirms `@Environment` pattern
- `MyHomeApp/Features/Budgets/BudgetsView.swift` — `BudgetsMonthView` child re-init pattern for scoped `@Query`; `BudgetProgressData` construction
- `MyHomeApp/Features/Budgets/BudgetProgressView.swift` — `BudgetColor` → SwiftUI Color mapping; `GeometryReader` + `ZStack` progress bar at 8pt (OVR-01 uses 16pt)
- `MyHomeApp/Features/Budgets/BudgetCategoryCard.swift` — card shell pattern (secondarySystemBackground, cornerRadius 12, shadow)
- `MyHomeApp/Persistence/Schema/SchemaV3.swift` — model fields confirmed: `Expense.date`, `Expense.amount`, `Category.monthlyBudget`, `Note.isPinned`, `Note.blocks`, `NoteBlock.kindRaw`, `NoteBlock.isChecked`
- `.planning/phases/04-overview-charts/04-CONTEXT.md` — locked decisions D4-01 through D4-08
- `.planning/phases/04-overview-charts/04-UI-SPEC.md` — visual + interaction contracts, chart code examples, card layouts
- `.planning/research/PITFALLS.md` — Pitfall 10 (state model), Pitfall 15 (Swift Charts reactive data), Pitfall 17 (Decimal vs Double)
- `.planning/research/STACK.md` — Swift Charts availability confirmed iOS 16+

### Secondary (MEDIUM confidence)
- `.planning/REQUIREMENTS.md` — OVR-01..04 (lines 74–77), EXP-10/11 (lines 37–38) — requirement text confirmed

---

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — no new packages; Swift Charts confirmed first-party iOS 16+
- API signatures: HIGH — read directly from source files
- Architecture: HIGH — follows verified BudgetsMonthView + CalendarAggregator patterns
- Tab reorder: HIGH — single reference site confirmed by grep
- Pitfalls: HIGH — grounded in existing PITFALLS.md + actual codebase patterns
- SpendOverTimeAggregator shape: HIGH — mirrors CalendarAggregator exactly
- OVR-01 uncategorized spend scope: ASSUMED (A1)

**Research date:** 2026-06-01
**Valid until:** 2026-07-01 (stable Apple platform; no external dependencies)
