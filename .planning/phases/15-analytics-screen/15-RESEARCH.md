# Phase 15: Analytics Screen — Research

**Researched:** 2026-06-23
**Domain:** SwiftUI / Swift Charts / IST bucketing / Navigation push / neumorphic UI
**Confidence:** HIGH (all findings grounded in the actual codebase; no speculative claims)

---

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions
All implementation choices are at Claude's discretion — discuss was skipped per the autonomous run.
Honor the established v1.2 design language already converged on in Phases 13–14:
- Neumorphic surfaces via `.neuSurface(.raised/.floating/.recessed)`; dark-only palette from `DesignTokens`.
- Category colors via `CategoryStyle.color(for:)` / `DesignTokens.cat*`.
- Solid `.semibold`/`.bold` `.default`-design numerals for headline figures (NOT thin ultraLight-rounded) — per the user's hero-font preference.
- Rounded "word" amounts (`formattedINRWhole`/`formattedINRWords`) for compact chart readouts.
- Charts: rounded bars, gradient fills, per-category colors; reuse `ActivityRing` / chart patterns from Overview where sensible.
- Inverted delta color convention (ANL-05): green = spend DECREASED vs prior period; coral/`negative` = spend INCREASED.
- Pre-aggregate outside any Chart DSL (Pitfall A guard); never let raw `@Query` arrays enter a Chart; `Double` only at the aggregation boundary, `Decimal` for stored/displayed money (Pitfall B).
- New `.swift` files MUST be registered in `MyHome.xcodeproj/project.pbxproj` (no synchronized groups — the explicit-file-refs footgun).

### Claude's Discretion
All implementation choices not listed above are at Claude's discretion.

### Deferred Ideas (OUT OF SCOPE)
- AI insight card consuming the aggregator output → Phase 16.
- Light mode → backlog Phase 999.1.
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| ANL-01 | Dedicated Analytics screen reachable by push from Overview (not a tab) | Navigation push pattern mirrors existing `navigateToAssets` — see §Navigation |
| ANL-02 | Week/Month/Year range tabs scope all analytics content | Reuse `SpendRange` enum already in `SpendOverTimeAggregator.swift`; same `Picker(.segmented)` pattern |
| ANL-03 | Spending-trend area chart with IST-correct date bucketing; reuses `SpendOverTimeAggregator` | `AnalyticsAggregator` delegates bucketing to `SpendOverTimeAggregator.bucket(...)` — no re-implementation |
| ANL-04 | By-category bar breakdown (`BarMark`) for selected range | Mirror `SpendByCategoryChart` track-backed bar pattern |
| ANL-05 | Delta chips: inverted color convention (green = decreased, coral = increased) | Chips use `DesignTokens.positive` / `DesignTokens.negative` with inverted semantics |
| ANL-06 | Tapping a delta chip drills into category/period detail | Sheet presentation is recommended (see §Drill-down) |
| ANL-07 | Single `AnalyticsAggregator` producing `SpendSummary`; IST-midnight boundary test required | Full design in §Aggregator & SpendSummary Design |
</phase_requirements>

---

## Summary

Phase 15 builds a dedicated Analytics screen pushed from the Overview. The screen provides three temporal views (week / month / year) of spend data — a trend chart, a by-category breakdown, and a period-over-period delta chip — all fed from a single pure `AnalyticsAggregator` that also serves Phase 16's AI card.

The codebase already contains everything the aggregator needs. `SpendOverTimeAggregator` (in `Support/`) already buckets expenses by IST-aware day/week/month into `[SpendBucket]` using `Calendar.current` + `TimeZone.current`. The new aggregator must delegate to it rather than re-implement bucketing, then add the per-category breakdown and period-over-period delta that the existing aggregator does not produce. `BudgetCalculator.monthlySpend(for:categories:)` already computes per-category totals with self-transfer exclusion; the Analytics aggregator can call it for the current and prior periods.

The chart UI pattern is established: `SpendOverTimeChart` already renders the trend as a `BarMark` chart using pre-aggregated `[SpendBucket]` values (Pitfall A guard in place); `SpendByCategoryChart` provides the track-backed horizontal bar row pattern. Both patterns are copy-and-adapt targets. Navigation from Overview already follows the `@State var navigateToAssets` + `.navigationDestination(isPresented:)` pattern — wire the same pattern for Analytics.

**Primary recommendation:** Build `AnalyticsAggregator` first as a pure value-type helper (no SwiftUI, no SwiftData), test the IST boundary, then build the UI shell against it.

---

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| Data aggregation (totals, deltas, buckets) | `AnalyticsAggregator` (pure Swift helper) | — | Must be testable in isolation; no SwiftUI/SwiftData dependencies |
| SwiftData fetching | `AnalyticsView` (or its child with `@Query`) | — | Same pattern as OverviewMonthContent: child view owns @Query, passes arrays to aggregator |
| Trend chart rendering | `AnalyticsTrendChart` (SwiftUI + Charts) | — | Display-only; receives pre-aggregated `[SpendBucket]` |
| Category bar rendering | `AnalyticsCategoryBars` (SwiftUI + Charts or track-backed rows) | — | Display-only; receives pre-aggregated `[CategorySpendItem]` |
| Delta chip + drill-down | `DeltaChip` + `DeltaDrillDownSheet` | — | Chip is inline; drill-down is a `.sheet` |
| Range switching | `AnalyticsView` (`@State var selectedRange: SpendRange`) | — | Drives re-aggregation when changed |
| Navigation entry point | `OverviewMonthContent` (`@State var navigateToAnalytics = false`) | — | Mirrors `navigateToAssets` pattern exactly |

---

## Aggregator & SpendSummary Design

### SpendSummary value type

`SpendSummary` is the output of `AnalyticsAggregator`. It must be a plain struct (no SwiftUI, no Identifiable requirement) so Phase 16 can consume it without modification.

```swift
// Support/AnalyticsAggregator.swift
struct SpendSummary {
    // --- Range identity ---
    let range: SpendRange

    // --- Headline figures (Decimal for display; Double only at Chart boundary) ---
    let totalSpend: Decimal         // current period, self-transfer-excluded
    let priorTotalSpend: Decimal    // same-length prior period for delta chip

    // --- Period-over-period delta ---
    // Positive = spent MORE (bad / coral); negative = spent LESS (good / green).
    // Inverted color semantics applied in the View layer, not here.
    var delta: Decimal { totalSpend - priorTotalSpend }
    var deltaFraction: Double {     // for "↓ 12%" display; zero-guarded
        guard priorTotalSpend > 0 else { return 0 }
        return NSDecimalNumber(decimal: delta / priorTotalSpend).doubleValue
    }

    // --- Trend chart data (pre-bucketed, already Double at the boundary) ---
    let trendBuckets: [SpendBucket] // reused from SpendOverTimeAggregator

    // --- Category breakdown (current period only) ---
    // Sorted descending by spend (callers can re-sort, but aggregator provides the canonical order).
    let categoryBreakdown: [CategorySpendItem]  // reuse existing CategorySpendItem type

    // --- Per-category prior period (for category-level delta chips) ---
    // Keyed by PersistentIdentifier for O(1) lookup.
    let priorCategorySpend: [PersistentIdentifier: Decimal]
}
```

**Why this shape:**
- `trendBuckets: [SpendBucket]` delegates bucketing entirely to `SpendOverTimeAggregator` — ANL-03 satisfied with zero re-implementation.
- `categoryBreakdown: [CategorySpendItem]` reuses the existing type from `SpendByCategoryChart`, so the category bar view needs zero changes to accept data from this aggregator vs the Overview's manual construction.
- `priorCategorySpend` enables the drill-down sheet (ANL-06) to show which categories drove the delta.
- Phase 16 (`InsightService`) only needs `totalSpend`, `priorTotalSpend`, `delta`, `deltaFraction`, and `categoryBreakdown` — all present.

### AnalyticsAggregator API

```swift
// Support/AnalyticsAggregator.swift
enum AnalyticsAggregator {

    /// Produces a SpendSummary for the given range.
    ///
    /// - Parameters:
    ///   - expenses: All expenses for the current AND prior period combined
    ///               (caller must supply wide enough range; see "Query width" note below).
    ///   - categories: All categories (for color + name resolution).
    ///   - range: .week / .month / .year
    ///   - calendar: Defaults to .current but injectable for tests (IST override).
    static func summarize(
        expenses: [Expense],
        categories: [Category],
        range: SpendRange,
        calendar: Calendar = .current
    ) -> SpendSummary
}
```

**Query width note:** The parent view's `@Query` must span *current period + prior period* so the aggregator has both. For `.year`, that means 24 months of data (this year + last year). The aggregator slices internally by calling `periodBounds(for:range:calendar:)`.

### Delegation to SpendOverTimeAggregator

```swift
// Inside AnalyticsAggregator.summarize(...)
let currentExpenses = expenses.filter { isInCurrentPeriod($0.date, range: range, calendar: calendar) }
    .filter { $0.isTransfer != true }

// Delegate bucketing — no re-implementation of IST logic
let trendBuckets = SpendOverTimeAggregator.bucket(
    expenses: currentExpenses,
    range: range,
    calendar: calendar
)
```

This is the literal ANL-03 requirement: "reuses the existing `SpendOverTimeAggregator`; no re-implementation."

### Period boundary helpers

```swift
// Returns (start, end) for the current period in the given calendar.
private static func currentPeriodBounds(range: SpendRange, calendar: Calendar) -> (Date, Date)

// Returns (start, end) for the immediately prior period of the same length.
private static func priorPeriodBounds(range: SpendRange, calendar: Calendar) -> (Date, Date)
```

For `.week`: current = today-6 to today; prior = today-13 to today-7.
For `.month`: current = start-of-month to end-of-month; prior = start-of-last-month to end-of-last-month.
For `.year`: current = Jan 1 this year to today; prior = Jan 1 last year to Dec 31 last year.

---

## IST Bucketing: Exact Calendar Setup & Boundary Test

### The problem

`SpendOverTimeAggregator` currently uses `TimeZone.current` (device timezone). For correctness in India, it must be forced to `Asia/Kolkata` (IST = UTC+5:30). The key boundary:

- **18:29 UTC** = 23:59 IST (still on day D)
- **18:31 UTC** = 00:01 IST on day D+1 (next IST day)

If `TimeZone.current` is UTC (as in a CI/Simulator environment), both timestamps land in the same UTC day bucket — **wrong**. With `Asia/Kolkata`, they land in different IST day buckets — **correct**.

The existing `SpendOverTimeAggregator` uses `TimeZone.current`, which is correct when the user's device is set to IST. However, `AnalyticsAggregator` should accept an injectable `Calendar` with its `timeZone` already set, so tests can pass an IST-forced calendar without depending on the device's timezone setting.

### Exact Calendar setup for IST

```swift
// In AnalyticsAggregator (and the test):
var istCalendar = Calendar(identifier: .gregorian)
istCalendar.timeZone = TimeZone(identifier: "Asia/Kolkata")!
```

### Required test: `testMidnightISTBucketBoundary`

Success criterion 6 requires this test to pass. Implement in `MyHomeTests/AnalyticsAggregatorTests.swift`:

```swift
@Test("testMidnightISTBucketBoundary: 18:29Z and 18:31Z on the same UTC date land in different IST day buckets")
func testMidnightISTBucketBoundary() throws {
    // UTC midnight for IST is 18:30 UTC.
    // 18:29Z = 23:59 IST on day D.
    // 18:31Z = 00:01 IST on day D+1.
    let formatter = ISO8601DateFormatter()
    let dayD_2359_IST = formatter.date(from: "2025-03-15T18:29:00Z")!   // 23:59 IST Mar 15
    let dayD1_0001_IST = formatter.date(from: "2025-03-15T18:31:00Z")!  // 00:01 IST Mar 16

    var istCalendar = Calendar(identifier: .gregorian)
    istCalendar.timeZone = TimeZone(identifier: "Asia/Kolkata")!

    // Build a minimal expense set containing only these two timestamps
    // (use in-memory ModelContainer, same pattern as SpendOverTimeAggregatorTests)
    let container = try makeContainer()
    let e1 = Expense(amount: Decimal(100)); e1.date = dayD_2359_IST
    let e2 = Expense(amount: Decimal(200)); e2.date = dayD1_0001_IST
    container.mainContext.insert(e1)
    container.mainContext.insert(e2)

    // Use the .week range so day-level bucketing is active.
    // Pass the IST calendar explicitly (the injectable parameter).
    let summary = AnalyticsAggregator.summarize(
        expenses: [e1, e2],
        categories: [],
        range: .week,
        calendar: istCalendar
    )

    // The two expenses must land in separate day buckets (non-zero spend on 2 distinct dates).
    let nonZeroBuckets = summary.trendBuckets.filter { $0.spent > 0 }
    #expect(nonZeroBuckets.count == 2, "Expected 2 non-zero buckets (one per IST day); got \(nonZeroBuckets.count)")

    // Optional: verify the bucket dates themselves differ by 1 IST day
    if nonZeroBuckets.count == 2 {
        let days = nonZeroBuckets.map { istCalendar.dateComponents([.day, .month], from: $0.date) }
        #expect(days[0].day != days[1].day)
    }
}
```

**Key:** Pass `calendar: istCalendar` all the way down to `SpendOverTimeAggregator.bucket(expenses:range:calendar:)` — the existing aggregator already has the `calendar:` parameter and uses it for all `timeZone` assignment, so the IST injection flows through without changes to that file.

---

## Chart Patterns & Pitfalls

### Pitfall A — Pre-aggregate outside the Chart DSL

**Established pattern (verbatim from `SpendOverTimeChart.swift`):**
```swift
var body: some View {
    // Pitfall A: aggregate OUTSIDE the Chart DSL
    let bucketedData = SpendOverTimeAggregator.bucket(
        expenses: expenses,
        range: selectedRange
    )
    // ... then pass bucketedData into Chart { } — never pass raw expenses
}
```
Analytics must follow the same discipline: aggregate in `body` (or a computed property) before entering `Chart {}`.

### Pitfall B — Double only at aggregation boundary

`SpendBucket.spent` is already `Double`. `CategorySpendItem.spent` is already `Double`. Both types carry the original `Decimal` alongside (`.spentDecimal`). The rules:
- Never pass `Decimal` into a `.value(...)` call inside `Chart {}`.
- Never reconstruct `Decimal` from `Double`.
- Display formatting (e.g. axis labels) uses `Decimal` (not `Double`) to format via `.formattedINRCompact()`.

Existing example from `SpendOverTimeChart.swift`:
```swift
AxisValueLabel {
    if let d = value.as(Double.self) {
        Text(Decimal(d).formattedINRCompact())   // Decimal(d) is lossy but acceptable for axis labels only
            .font(.caption)
    }
}
```
Note: `Decimal(d)` from a `Double` is lossy but acceptable for axis *labels*; never use it for stored or displayed money amounts. For displayed amounts use `spentDecimal.formattedINRWhole()`.

### Trend chart: AreaMark vs BarMark

ANL-03 says "area chart (`AreaMark`)". The existing `SpendOverTimeChart` uses `BarMark`. For Analytics, use `AreaMark` with a `LineMark` overlay for the trend reading:

```swift
Chart(buckets) { point in
    AreaMark(
        x: .value("Date", point.date),
        y: .value("Spend", point.spent)
    )
    .foregroundStyle(
        LinearGradient(
            colors: [DesignTokens.accent.opacity(0.35), DesignTokens.accent.opacity(0.0)],
            startPoint: .top,
            endPoint: .bottom
        )
    )
    LineMark(
        x: .value("Date", point.date),
        y: .value("Spend", point.spent)
    )
    .foregroundStyle(DesignTokens.accent)
    .lineStyle(StrokeStyle(lineWidth: 2))
    .interpolationMethod(.catmullRom)
}
```

### Category breakdown: Track-backed rows vs native BarMark

`SpendByCategoryChart` uses track-backed rows (not native `BarMark`). ANL-04 says "BarMark" but the existing WHOOP-style track-backed bar pattern is already established and matches the design language better than native Charts bars on this screen. Recommend reusing the track-backed row pattern from `SpendByCategoryChart` — it is semantically a "bar breakdown" and satisfies ANL-04.

If native `BarMark` is preferred (e.g. for `.horizontal` orientation with `BarMark`), use:
```swift
Chart(categoryItems) { item in
    BarMark(
        x: .value("Spend", item.spent),
        y: .value("Category", item.name)
    )
    .foregroundStyle(item.color.gradient)
    .cornerRadius(4)
}
```
Either approach satisfies ANL-04. The track-backed row approach requires less Chart DSL and is already tested.

### Year range: no future zero-bars

Success criterion 3 requires the Year tab to show only months up to and including the current month. The existing `SpendOverTimeAggregator.yearBuckets` generates all 12 months. `AnalyticsAggregator` must filter the returned buckets before passing them to the chart:

```swift
let currentMonth = calendar.component(.month, from: Date())
let filteredBuckets = trendBuckets.filter {
    calendar.component(.month, from: $0.date) <= currentMonth
}
```

---

## Navigation: Push from Overview

### Existing pattern (verbatim from `OverviewMonthContent`)

```swift
// OverviewMonthContent, line 109:
@State private var navigateToAssets = false

// OverviewMonthContent body, line 281:
.navigationDestination(isPresented: $navigateToAssets) {
    AssetsListView()
}

// Triggered by:
sectionHeader("Net Worth", action: ("See holdings", { navigateToAssets = true }))
```

### Analytics entry point

Add to `OverviewMonthContent` (not `OverviewView` — the `NavigationStack` is owned by `OverviewView`, but `.navigationDestination` must be placed inside the stack's content, which is `OverviewMonthContent`):

```swift
// Add alongside navigateToAssets:
@State private var navigateToAnalytics = false

// In body:
.navigationDestination(isPresented: $navigateToAnalytics) {
    AnalyticsView(expenses: allGlobalExpenses, categories: categories)
}
```

**Tap target:** Add a section header or a tappable card/button on Overview. A minimal option is a "See Analytics" button alongside the "Over Time" section header. A richer option is a dedicated "Spending Analytics" card tile that shows the current-month total and pushes on tap.

`AnalyticsView` is not a tab (ANL-01). The tab-bar layout is unchanged. The `NavigationStack` in `OverviewView` provides the slide-in push animation automatically.

### Data passed to AnalyticsView

`AnalyticsView` needs `allGlobalExpenses` (already in scope in `OverviewMonthContent`) and `categories`. The view owns its own `@State var selectedRange` and re-computes `SpendSummary` via `AnalyticsAggregator` on range change.

**Do not pass a pre-computed `SpendSummary` from Overview** — the Analytics screen controls its own range and needs to recompute on tab switch.

---

## Delta Chips & Drill-Down

### Delta chip design

```swift
struct DeltaChip: View {
    let delta: Decimal       // positive = more spend (bad), negative = less (good)
    let priorTotal: Decimal
    let onTap: () -> Void

    private var isPositive: Bool { delta > 0 }  // MORE spend = coral
    private var chipColor: Color { isPositive ? DesignTokens.negative : DesignTokens.positive }
    private var arrow: String { isPositive ? "arrow.up" : "arrow.down" }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 4) {
                Image(systemName: arrow)
                    .font(.caption.weight(.bold))
                Text(pctLabel)
                    .font(.caption.weight(.semibold))
                    .monospacedDigit()
            }
            .foregroundStyle(chipColor)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(chipColor.opacity(0.15))
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private var pctLabel: String {
        guard priorTotal > 0 else { return "—" }
        let pct = abs(NSDecimalNumber(decimal: delta / priorTotal).doubleValue) * 100
        return String(format: "%.0f%%", pct)
    }
}
```

### Drill-down: Sheet (recommended over inline expand)

ANL-06 says "tapping a delta chip reveals the underlying category or period detail." A `.sheet` is the correct pattern here because:
1. The detail content (per-category delta comparison) needs its own scroll space.
2. Inline expand would re-layout the Analytics scroll view unpredictably.
3. Sheet is consistent with how the rest of the app exposes detail (EditExpenseView, EditBudgetSheet, MigrationReviewSheet all use `.sheet`).

```swift
// In AnalyticsView:
@State private var showDeltaDrillDown = false

// Chip triggers:
DeltaChip(delta: summary.delta, priorTotal: summary.priorTotalSpend) {
    showDeltaDrillDown = true
}
.sheet(isPresented: $showDeltaDrillDown) {
    DeltaDrillDownSheet(summary: summary)
}
```

`DeltaDrillDownSheet` shows a list of categories, each row displaying current vs prior spend and a per-category delta chip. Sorted descending by absolute delta (biggest movers first). Uses `summary.priorCategorySpend` keyed lookup.

---

## Week/Month/Year Range Switching — No Stale Data

### Problem

SwiftUI `View.body` is recomputed when `@State` changes, so changing `selectedRange` naturally triggers re-aggregation. However, stale data can appear if:
1. The aggregator is called inside a `Group` or `LazyVStack` that does not re-evaluate.
2. The `@Query` supplying expenses is too narrow and does not cover all three ranges.

### Solution

1. **Declare `selectedRange` as `@State` directly in `AnalyticsView`** (not in a child view). All subviews receive the pre-aggregated `SpendSummary` as a `let` parameter.
2. **Compute `summary` at the top of `body`**, not inside a nested view:
   ```swift
   var body: some View {
       let summary = AnalyticsAggregator.summarize(
           expenses: expenses,
           categories: categories,
           range: selectedRange
       )
       // pass summary to all subviews
   }
   ```
3. **`@Query` in `AnalyticsView` must span 2 years** (current + prior year) so `.year` range can compute its delta against the prior year. Use an unfiltered `@Query(sort: \Expense.date, order: .reverse)` and let the aggregator slice. This is the same pattern as `SpendOverTimeChart` receiving `allGlobalExpenses` from `OverviewMonthContent`.

### Picker pattern

Reuse the exact `Picker` + `.pickerStyle(.segmented)` from `SpendOverTimeChart`:
```swift
Picker("Range", selection: $selectedRange) {
    Text(SpendRange.week.label).tag(SpendRange.week)
    Text(SpendRange.month.label).tag(SpendRange.month)
    Text(SpendRange.year.label).tag(SpendRange.year)
}
.pickerStyle(.segmented)
```
`SpendRange` already exists in `SpendOverTimeAggregator.swift` with the right `.label` properties — no duplication needed.

---

## File/Component Breakdown

### New files (all require 4 pbxproj edits each)

| File | Location | Group | Purpose |
|------|----------|-------|---------|
| `AnalyticsAggregator.swift` | `MyHomeApp/Support/` | `G140` | Pure aggregator + `SpendSummary` struct |
| `AnalyticsView.swift` | `MyHomeApp/Features/Analytics/` | `G_ANL` (new) | Root screen; owns `@Query`, range @State, delegates to subviews |
| `AnalyticsTrendChart.swift` | `MyHomeApp/Features/Analytics/` | `G_ANL` | `AreaMark` + `LineMark` chart; accepts `[SpendBucket]` |
| `AnalyticsCategoryBars.swift` | `MyHomeApp/Features/Analytics/` | `G_ANL` | Track-backed category bars; accepts `[CategorySpendItem]` |
| `DeltaChip.swift` | `MyHomeApp/Features/Analytics/` | `G_ANL` | Reusable delta chip (used by ANL-05; consumed by Phase 16 too) |
| `DeltaDrillDownSheet.swift` | `MyHomeApp/Features/Analytics/` | `G_ANL` | Sheet for ANL-06 drill-down |
| `AnalyticsAggregatorTests.swift` | `MyHomeTests/` | `G200` | IST boundary test + range coverage tests |

### Files modified (no new pbxproj entries needed)

| File | Change |
|------|--------|
| `OverviewView.swift` (OverviewMonthContent) | Add `@State var navigateToAnalytics = false`, `.navigationDestination`, and tap trigger |
| `MyHome.xcodeproj/project.pbxproj` | New `G_ANL` group + 4 edits × 6 new files (see pbxproj section) |

### No new types needed from Support/

- `SpendRange` — already exists in `SpendOverTimeAggregator.swift`
- `SpendBucket` — already exists
- `CategorySpendItem` — already exists in `SpendByCategoryChart.swift`

---

## pbxproj Registration Protocol

The project has NO synchronized groups. Every new `.swift` file requires exactly 4 manual edits in `MyHome.xcodeproj/project.pbxproj`:

1. **`PBXFileReference` section** — declare the file:
   ```
   FANL01 /* AnalyticsAggregator.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = AnalyticsAggregator.swift; sourceTree = "<group>"; };
   ```

2. **`PBXBuildFile` section** — declare the build file:
   ```
   AANL01 /* AnalyticsAggregator.swift in Sources */ = {isa = PBXBuildFile; fileRef = FANL01 /* AnalyticsAggregator.swift */; };
   ```

3. **`PBXGroup` section** — add the file ref to its parent group. For `Support/` files add to `G140`; for new `Features/Analytics/` files create a new `G_ANL` group and add it to `G120 /* Features */`.

4. **`PBXSourcesBuildPhase`** — add the build file reference to the main target's sources list:
   ```
   AANL01 /* AnalyticsAggregator.swift in Sources */,
   ```

**New group block for `G_ANL`** (add inside the `G120 /* Features */` group's children list AND as a new group block):
```
G_ANL /* Analytics */ = {
    isa = PBXGroup;
    children = (
        FANL02 /* AnalyticsView.swift */,
        FANL03 /* AnalyticsTrendChart.swift */,
        FANL04 /* AnalyticsCategoryBars.swift */,
        FANL05 /* DeltaChip.swift */,
        FANL06 /* DeltaDrillDownSheet.swift */,
    );
    path = Analytics;
    sourceTree = "<group>";
};
```

**Test file** registers in the `G200 /* MyHomeTests */` group and the test target's `PBXSourcesBuildPhase` only (2 edits, not 4, since the test target has its own build phase).

The ID naming convention observed in this codebase: use `F` prefix + sequential numbers or mnemonic (e.g., `F1402SDC` for SpendDonutCard, `F1402SDCT` for its test). Use `FANL01`–`FANL06` for the new files and `AANL01`–`AANL06` for their build file entries.

---

## Pitfalls & Risks

### Pitfall 1: IST bucketing broken in CI (Simulator timezone)
**What goes wrong:** CI simulators default to UTC. Tests that don't inject an IST calendar will pass locally (device set to IST) but fail or produce wrong groupings in CI.
**Prevention:** `AnalyticsAggregator.summarize` accepts `calendar: Calendar = .current`. Tests always pass `istCalendar`. The boundary test (`testMidnightISTBucketBoundary`) explicitly uses `TimeZone(identifier: "Asia/Kolkata")`.

### Pitfall 2: AnalyticsView @Query too narrow
**What goes wrong:** If `@Query` only fetches the current month, the `.year` delta chip has no prior-year data → `priorTotalSpend = 0` → delta always shows 100% increase.
**Prevention:** Query all expenses (no date filter), same as `allGlobalExpenses` in `OverviewMonthContent`. The aggregator slices to the correct period window internally.

### Pitfall 3: Re-implementing bucketing instead of delegating
**What goes wrong:** Writing a new `startOfDay` / `startOfMonth` in `AnalyticsAggregator` instead of calling `SpendOverTimeAggregator.bucket(...)`. Creates two code paths, two test surfaces, divergence risk.
**Prevention:** `AnalyticsAggregator` calls `SpendOverTimeAggregator.bucket(expenses:range:calendar:)` for `trendBuckets`. No new date bucketing code.

### Pitfall 4: Year tab shows future zero-bars
**What goes wrong:** `SpendOverTimeAggregator.yearBuckets` generates all 12 months. If passed directly to the chart, months after the current month show zero bars.
**Prevention:** Filter `trendBuckets` in `AnalyticsAggregator` for `.year` range: keep only months where `calendar.component(.month, from: bucket.date) <= calendar.component(.month, from: Date())`.

### Pitfall 5: Missing pbxproj registration for Analytics/ group
**What goes wrong:** Files in a new `Features/Analytics/` subdirectory that don't have a PBXGroup parent referencing that path won't be found by the compiler even if the file reference and build file entries exist. The project uses explicit file references — the group `path` field must match the actual directory.
**Prevention:** Create the `Features/Analytics/` directory first. Then add the `G_ANL` group block with `path = Analytics` inside `G120 /* Features */`. Verify with `xcodebuild clean build`.

### Pitfall 6: Delta color inversion
**What goes wrong:** Applying `DesignTokens.positive` (green) when delta > 0 (spent more). The semantics are inverted: green means you spent *less* (good outcome).
**Prevention:** In `DeltaChip`: `chipColor = delta > 0 ? DesignTokens.negative : DesignTokens.positive`. Document the inversion in a comment referencing ANL-05.

### Pitfall 7: Decimal→Double in prior-period delta math
**What goes wrong:** Computing `deltaFraction` as `Double(delta) / Double(priorTotal)` instead of `NSDecimalNumber(decimal: delta / priorTotal).doubleValue`. Float precision error causes wrong percentages.
**Prevention:** All Decimal→Double conversions use `NSDecimalNumber(decimal:).doubleValue`. The `delta / priorTotal` division stays in Decimal until the final conversion.

---

## Suggested Plan Task Split

Phase 15 naturally splits into 3 plans:

### Plan 15-01: AnalyticsAggregator + SpendSummary + Tests (Wave 1)
**Scope:** Pure Swift only. No UI.
- Define `SpendSummary` struct in `Support/AnalyticsAggregator.swift`
- Implement `AnalyticsAggregator.summarize(expenses:categories:range:calendar:)`
- Implement `currentPeriodBounds` / `priorPeriodBounds` helpers
- Delegate trend bucketing to `SpendOverTimeAggregator`
- Filter year buckets to current-month-and-before
- Implement `AnalyticsAggregatorTests.swift`:
  - `testMidnightISTBucketBoundary` (required exit criterion — ANL-07)
  - `testWeekDeltaChip` (current vs prior 7-day total)
  - `testYearNofutureBuckets` (year range shows ≤ current month count)
  - `testSelfTransferExclusion`
- Register `AnalyticsAggregator.swift` in pbxproj (`G140` / `G_ANL`; test in `G200`)

**Dependencies:** None (pure Swift helpers).

### Plan 15-02: AnalyticsView UI Shell + Navigation + Charts (Wave 2)
**Scope:** Full screen UI. Blocked on Plan 15-01 (`SpendSummary` must exist).
- Create `Features/Analytics/` directory
- `AnalyticsView.swift`: `@Query` (all expenses), range picker, `AnalyticsAggregator.summarize` in body, pass summary down
- `AnalyticsTrendChart.swift`: `AreaMark` + `LineMark`, IST-correct x-axis labels, year-range filtered
- `AnalyticsCategoryBars.swift`: track-backed rows reusing `SpendByCategoryChart` pattern, all categories for range sorted descending
- Wire navigation in `OverviewMonthContent`: `@State var navigateToAnalytics`, `.navigationDestination`, tappable "Analytics" entry on Overview (section header CTA or dedicated card)
- Register all new `Features/Analytics/` files in pbxproj (`G_ANL` group inside `G120`)
- Verify `xcodebuild clean build`

**Dependencies:** Plan 15-01 (SpendSummary, AnalyticsAggregator).

### Plan 15-03: Delta Chips + Drill-Down Sheet + Final Build Gate (Wave 3)
**Scope:** Delta chips, drill-down sheet, cleanup. Blocked on 15-02 (AnalyticsView layout must be stable).
- `DeltaChip.swift`: inverted color semantics (ANL-05), accessible label
- Wire `DeltaChip` into `AnalyticsView` headline section
- `DeltaDrillDownSheet.swift`: per-category current vs prior rows, sorted by absolute delta, ANL-06
- Wire `.sheet(isPresented: $showDeltaDrillDown)` in `AnalyticsView`
- Register `DeltaChip.swift` and `DeltaDrillDownSheet.swift` in pbxproj
- Final `xcodebuild clean build` gate (ANL-07 / success criterion 7)
- Human-verify checkpoint: visual inspection on simulator (iPhone 17, Xcode 26.5)

**Dependencies:** Plans 15-01 and 15-02.

---

## Environment Availability

| Dependency | Required By | Available | Notes |
|------------|------------|-----------|-------|
| Swift Charts | AreaMark, BarMark | Yes (iOS 16+; project targets iOS 17) | First-party framework |
| SwiftData | @Query | Yes (iOS 17; already in project) | First-party framework |
| `SpendRange` | ANL-02, ANL-03 | Yes — `Support/SpendOverTimeAggregator.swift` | No duplication needed |
| `SpendBucket` | Trend chart | Yes — `Support/SpendOverTimeAggregator.swift` | No duplication needed |
| `CategorySpendItem` | Category bars | Yes — `Features/Overview/SpendByCategoryChart.swift` | No duplication needed |
| `CategoryStyle.color(for:)` | Category colors | Yes — `Features/Shared/CategoryStyle.swift` | Import pattern established |
| `DesignTokens` | All surfaces/colors | Yes — `DesignSystem/DesignTokens.swift` | `.positive`, `.negative`, `.accent` all defined |
| `NeuSurface` / `.neuSurface()` | Card surfaces | Yes — `DesignSystem/NeuSurface.swift` | `.raised`, `.floating`, `.recessed` all available |
| `Decimal+INR.swift` | Money formatting | Yes — `Support/Decimal+INR.swift` | `formattedINRWhole()`, `formattedINRWords()`, `formattedINRCompact()` all present |
| `ActivityRing` | Optional trend ring | Yes (already used by SpendDonutCard) | Optional — only if Overview ring style is wanted for analytics |

---

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | Swift Testing (`import Testing`) — used across all existing tests |
| Config file | None — scheme-based (`MyHome` scheme, `MyHomeTests` target) |
| Quick run command | `xcodebuild test -scheme MyHome -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:MyHomeTests/AnalyticsAggregatorTests` |
| Full suite command | `xcodebuild test -scheme MyHome -destination 'platform=iOS Simulator,name=iPhone 17'` |

### Phase Requirements → Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| ANL-07 | IST midnight boundary: 18:29Z & 18:31Z → different day buckets | unit | `...AnalyticsAggregatorTests/testMidnightISTBucketBoundary` | ❌ Wave 0 |
| ANL-07 | Year range: no future zero-bars | unit | `...AnalyticsAggregatorTests/testYearNoFutureBuckets` | ❌ Wave 0 |
| ANL-05 | Delta chip inverted color: delta>0 → negative (coral) | unit | `...AnalyticsAggregatorTests/testDeltaColorSemantics` | ❌ Wave 0 |
| ANL-07 | Self-transfer exclusion from totals | unit | `...AnalyticsAggregatorTests/testSelfTransferExclusion` | ❌ Wave 0 |
| ANL-01 | Navigation push (not tab) | manual-only | Visual inspection — tab bar unchanged | — |
| ANL-03 | Bucketing delegates to SpendOverTimeAggregator | unit (structural) | Verified by IST boundary test | ❌ Wave 0 |

### Wave 0 Gaps
- [ ] `MyHomeTests/AnalyticsAggregatorTests.swift` — covers ANL-07 IST test + delta/year tests
- [ ] `MyHomeApp/Support/AnalyticsAggregator.swift` — required for tests to compile

---

## Sources

### Primary (HIGH confidence — codebase inspection)
- `MyHomeApp/Support/SpendOverTimeAggregator.swift` — bucketing pattern, `SpendRange`, `SpendBucket` types, `calendar:` injectable parameter
- `MyHomeApp/Support/BudgetCalculator.swift` — `monthlySpend(for:categories:)` monthly per-category aggregation pattern
- `MyHomeApp/Features/Overview/SpendByCategoryChart.swift` — `CategorySpendItem` type, track-backed bar pattern, Pitfall A/B guards
- `MyHomeApp/Features/Overview/SpendOverTimeChart.swift` — `AreaMark`/`BarMark` Chart DSL pattern, Pitfall A/B guards in place
- `MyHomeApp/Features/Overview/OverviewView.swift` — `navigateToAssets` + `.navigationDestination(isPresented:)` push pattern, `allGlobalExpenses` query width pattern
- `MyHomeApp/DesignSystem/DesignTokens.swift` — `positive`, `negative`, `accent`, `bgCanvas`, `surfaceRaised`, spacing constants
- `MyHomeApp/DesignSystem/NeuSurface.swift` — `.neuSurface(.raised/.floating/.recessed)` modifier API
- `MyHomeApp/Features/Shared/CategoryStyle.swift` — `CategoryStyle.color(for:)` signature
- `MyHome.xcodeproj/project.pbxproj` — group structure (`G140` Support, `G120` Features, `G124` Overview), 4-edit-per-file registration pattern, naming convention (`F`/`A` prefix)
- `MyHomeTests/SpendOverTimeAggregatorTests.swift` — test file structure pattern, `@testable import MyHome`, `@MainActor struct`, `makeContainer()` helper

### Secondary (MEDIUM confidence — requirements + context)
- `.planning/phases/15-analytics-screen/15-CONTEXT.md` — phase boundary, design decisions, success criteria
- `.planning/REQUIREMENTS.md` — ANL-01..ANL-07 exact wording
- `.planning/ROADMAP.md` — Phase 15 success criteria

---

## Metadata

**Confidence breakdown:**
- Aggregator design: HIGH — grounded in existing aggregator types; re-uses confirmed APIs
- IST bucketing: HIGH — boundary case is mathematically verifiable; calendar API is standard
- Chart patterns: HIGH — exact patterns copied from existing shipping code
- Navigation: HIGH — mirrors existing `navigateToAssets` pattern verbatim
- Delta chips: HIGH — uses established DesignTokens colors; semantics from CONTEXT.md
- pbxproj registration: HIGH — group structure fully inspected; naming convention confirmed

**Research date:** 2026-06-23
**Valid until:** Phase 15 completion (stable codebase, no schema changes in scope)
