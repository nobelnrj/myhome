---
phase: 04-overview-charts
reviewed: 2026-06-01T00:00:00Z
depth: standard
files_reviewed: 13
files_reviewed_list:
  - MyHomeApp/Features/Overview/OverviewView.swift
  - MyHomeApp/Features/Overview/PinnedNoteCard.swift
  - MyHomeApp/Features/Overview/SpendBudgetCard.swift
  - MyHomeApp/Features/Overview/SpendByCategoryChart.swift
  - MyHomeApp/Features/Overview/SpendOverTimeChart.swift
  - MyHomeApp/Features/Overview/TopCategoriesCard.swift
  - MyHomeApp/RootView.swift
  - MyHomeApp/Support/Decimal+INR.swift
  - MyHomeApp/Support/OverviewAggregation.swift
  - MyHomeApp/Support/SpendOverTimeAggregator.swift
  - MyHomeTests/DecimalINRTests.swift
  - MyHomeTests/OverviewAggregationTests.swift
  - MyHomeTests/SpendOverTimeAggregatorTests.swift
findings:
  critical: 1
  warning: 6
  info: 4
  total: 11
status: issues_found
---

# Phase 4: Code Review Report

**Reviewed:** 2026-06-01
**Depth:** standard
**Files Reviewed:** 13
**Status:** issues_found

## Summary

The Overview/charts implementation is well-structured: aggregation logic is cleanly separated into pure static helpers (`OverviewAggregation`, `SpendOverTimeAggregator`), money stays `Decimal` until the charting boundary, and the `Decimal -> Double` conversions are routed through `NSDecimalNumber(...).doubleValue` as documented. Tests cover the aggregator and formatter boundaries reasonably.

However, there is one correctness BLOCKER: the **Spend Over Time** chart's Week and Year ranges are fed an expense array that the parent has already bounded to the *current month* via `@Query` predicate — directly contradicting the chart's own documented contract that the array "need not be bounded to a single month." The Year view will show only the current month's data spread across a 12-month axis, and Week views straddling a month boundary will silently drop prior-month days. Several WARNING-level issues follow, most notably that `formattedINRCompact()` produces garbage for negative (refund) values, and that the `isFallbackChecklist` computation is logically incoherent.

## Critical Issues

### CR-01: Spend Over Time chart shows wrong data for Week/Year ranges (month-bounded query)

**File:** `MyHomeApp/Features/Overview/OverviewView.swift:87-92`, `MyHomeApp/Features/Overview/SpendOverTimeChart.swift:9-21,146`

**Issue:** `OverviewMonthContent.init` builds `_monthExpenses` with a predicate restricting expenses to the current month:
```swift
_monthExpenses = Query(
    filter: #Predicate<Expense> { expense in
        expense.date >= lo && expense.date <= hi   // lo/hi = current-month boundaries
    },
    sort: \.date, order: .reverse
)
```
That same `monthExpenses` array is passed verbatim into `SpendOverTimeChart(monthExpenses: monthExpenses)`. But `SpendOverTimeAggregator.yearBuckets` buckets across **all 12 months of the current year**, and `weekBuckets` buckets the **rolling 7 days ending today** (which can include days from the previous month near month start).

The chart's own doc-comment asserts the opposite is safe:
> "the aggregator computes its own date windows from `Date()` ... so the expense array need not be bounded to a single month when `.week` or `.year` range is selected."

This contract is violated. Concrete consequences:
- **Year view:** 11 of 12 month buckets render as 0 spend regardless of actual history — the chart is simply wrong.
- **Week view (early in the month):** days falling in the prior month (e.g. on the 3rd, the slots for the 28th–31st) are silently dropped, undercounting those days.

**Fix:** The chart needs an expense source scoped to the widest range it can display (the calendar year), not the month. Either pass a separate year-scoped (or unbounded) query into `SpendOverTimeChart`, or have the chart own its own `@Query` keyed off the selected range. Minimal correct option — give the chart a year-bounded query:
```swift
// In a dedicated child that owns the query, or widen the parent's bounds for this card:
let yearStart = Calendar.current.date(from: Calendar.current.dateComponents([.year], from: Date()))!
_yearExpenses = Query(
    filter: #Predicate<Expense> { $0.date >= yearStart },
    sort: \.date, order: .reverse
)
// pass yearExpenses to SpendOverTimeChart
```
Do not keep feeding the month-bounded array while claiming the aggregator handles windowing — it does not have data it was never given.

## Warnings

### WR-01: `formattedINRCompact()` produces incorrect output for negative amounts

**File:** `MyHomeApp/Support/Decimal+INR.swift:29-34`

**Issue:** The compact formatter only handles the positive branches; negatives fall through to `"₹\(Int(d))"`, and integer truncation toward zero yields misleading labels. Examples:
- `Decimal(-500).formattedINRCompact()` -> `"₹-500"` (sign in the wrong place vs. `formattedINR()`'s `"-₹500"`).
- `Decimal(-50000).formattedINRCompact()` -> `"₹-50000"` — never compacted to `k`/`L` because `d >= 1_000` is false for negatives.

Refunds are a first-class concept here (`SpendOverTimeAggregatorTests.refundReducesBucket` explicitly tests negative expenses), and a single large refund can drive a daily/monthly bucket negative. The Y-axis label (`SpendOverTimeChart.swift:103`) and bar annotations would then render inconsistent, un-compacted strings.

**Fix:** Operate on magnitude and reapply the sign:
```swift
func formattedINRCompact() -> String {
    let d = NSDecimalNumber(decimal: self).doubleValue
    let sign = d < 0 ? "-" : ""
    let a = abs(d)
    if a >= 100_000 { return "\(sign)₹\(Int(a / 100_000))L" }
    if a >= 1_000   { return "\(sign)₹\(Int(a / 1_000))k" }
    return "\(sign)₹\(Int(a))"
}
```
Note there is no test for negative input in `DecimalINRTests` — add one.

### WR-02: `isFallbackChecklist` logic is incoherent and double-computes

**File:** `MyHomeApp/Features/Overview/OverviewView.swift:107-112`

**Issue:**
```swift
let isFallbackChecklist: Bool = {
    guard let note = pinnedNote else { return false }
    let sections = NoteListOrganizer.organize(allNotes)
    return sections.pinned.first == nil
}()
```
- The local `note` binding is captured but never used (`guard let note` could be `guard pinnedNote != nil`), so the compiler will warn about an unused variable.
- `NoteListOrganizer.organize(allNotes)` is run a *second* time here, having already been run inside `OverviewAggregation.pinnedOrChecklistNote(from:)` at line 106 — duplicated work and a duplicated source of truth. If the two `organize` calls ever diverge (e.g. due to ordering), the chip icon and the resolved note disagree.

This is fragile by construction: the flag is derived independently of the value it is supposed to describe. The cleaner contract is for `pinnedOrChecklistNote` to return whether the note came from the pinned path or the checklist-fallback path.

**Fix:** Have the aggregation return the provenance, e.g.:
```swift
static func pinnedOrChecklistNote(from notes: [Note]) -> (note: Note?, isFallback: Bool) {
    let sections = NoteListOrganizer.organize(notes)
    if let pinned = sections.pinned.first { return (pinned, false) }
    let checklist = notes.first { $0.blocks?.contains { $0.kindRaw == "checkbox" } == true }
    return (checklist, checklist != nil)
}
```
Then `isFallbackChecklist = result.isFallback` — single organize call, no unused binding, no divergence risk.

### WR-03: Chart annotation/axis round-trips Double back to Decimal, defeating precision intent

**File:** `MyHomeApp/Features/Overview/SpendByCategoryChart.swift:58,62`; `MyHomeApp/Features/Overview/SpendOverTimeChart.swift:88,103`

**Issue:** The code goes to lengths to keep money as `Decimal` until the charting boundary, then reconstructs a `Decimal` from the lossy `Double` for display: `Decimal(item.spent).formattedINR()`, `Decimal(point.spent).formattedINR()`, `Decimal(d).formattedINRCompact()`. `Decimal(Double)` carries the float representation error into the displayed currency string (e.g. an amount that was exactly `1234.56` as `Decimal` can become `1234.5600000000001` after `Decimal -> Double -> Decimal`), and `formattedINR()` renders 2 fraction digits, so drift can surface. This contradicts the stated "no float drift in stored/displayed money" discipline (Pitfall B/17) that the rest of the file cites.

**Fix:** Carry the original `Decimal` (or a pre-formatted display string) on `CategorySpendItem` / `SpendBucket` alongside the `Double` plot value, and format from that — never reconstruct a `Decimal` from the chart's `Double`. For the Y-axis label (`value.as(Double.self)`) the value genuinely originates as `Double` from Charts, so compact formatting there is acceptable; the bar/point annotations should use the source `Decimal`.

### WR-04: OverviewView silently renders empty when `monthBoundaries` returns nil

**File:** `MyHomeApp/Features/Overview/OverviewView.swift:28-36`

**Issue:** `if let (start, end) = BudgetCalculator.monthBoundaries(for: currentMonth)` has no `else`. If `monthBoundaries` ever returns `nil` (it is an `Optional`-returning API guarding `cal.date(from:)`), the entire Home tab content disappears with no message, no fallback, and no log — a blank screen under the nav bar. While `dateComponents([.year,.month], from: Date())` is unlikely to fail in practice, a screen that can silently render nothing is a robustness defect for the app's default launch tab.

**Fix:** Provide an `else` branch with a minimal fallback (e.g. a "Couldn't load this month" placeholder) or assert/log so the failure is observable rather than invisible.

### WR-05: `topCategories` tie-break is not a total order (unstable for duplicate names)

**File:** `MyHomeApp/Support/OverviewAggregation.swift:70-78`

**Issue:** The sort comparator falls back to `lName < rName`. When two categories have equal spend *and* equal (or both-nil -> "") names, the comparator returns `false` for both orderings, so the relative order is unspecified. With nil names both map to `""`, so any two unnamed equal-spend categories are non-deterministically ordered, which can make the rendered top-3 flip between renders and makes `ForEach(..., id: \.offset)` (TopCategoriesCard.swift:39) diff oddly. Not a crash, but a determinism/quality defect with no test covering equal-name or nil-name ties.

**Fix:** Add a final stable discriminator, e.g. compare `persistentModelID` string or include original index, so the comparator defines a strict total order.

### WR-06: `currentMonth` recomputed via `Date()` on every body evaluation; child never re-queries across a month rollover

**File:** `MyHomeApp/Features/Overview/OverviewView.swift:22-24,28`

**Issue:** `currentMonth` calls `Date()` inside a computed property read during `body`. Two related issues: (a) the value is recomputed on every render (minor), and (b) more importantly, `OverviewMonthContent` is re-initialized only when `start`/`end` change — but because `body` is not re-evaluated merely due to wall-clock passing, an app left open across a midnight-into-new-month boundary will keep showing the previous month's `@Query` results until some unrelated state change forces a re-render. The comment at lines 10-12 asserts re-init "re-triggers @Query execution," which is true only when SwiftUI actually re-evaluates the parent body.

**Fix:** Out of strict scope if month-rollover-while-open is deemed acceptable, but at minimum document the limitation. A robust fix drives `currentMonth` off a date that updates (e.g. a `.onReceive` of a day-change notification or a timer-backed `@State`).

## Info

### IN-01: Inconsistent card-title styling (`.bold()` applied unevenly)

**File:** `SpendByCategoryChart.swift:40`, `SpendOverTimeChart.swift:54` vs. `SpendBudgetCard.swift:63`, `TopCategoriesCard.swift:27`, `PinnedNoteCard.swift:52`

**Issue:** "Spend by Category" and "Spend Over Time" titles use `.font(.title2)` without `.bold()`, while the other three cards use `.font(.title2).bold()`. Likely an unintended visual inconsistency across the dashboard cards.

**Fix:** Apply `.bold()` consistently (or extract a shared card-title style).

### IN-02: `TopCategoriesCard` "3 categories" preview is a non-functional placeholder

**File:** `MyHomeApp/Features/Overview/TopCategoriesCard.swift:89-95`

**Issue:** The first `#Preview` renders a `Text("TopCategoriesCard — needs live preview context")` instead of the actual card with data, so the primary (populated) state has no usable preview. Other charts in this phase manage to build an in-memory `ModelContainer` for previews (`SpendByCategoryChart.swift:102-112`).

**Fix:** Build an in-memory container with sample `Category` rows like the other previews, or have `TopCategoriesCard` accept enough plain value data to preview without a context.

### IN-03: Magic tab-index integers scattered across views

**File:** `PinnedNoteCard.swift:88,103`, `SpendBudgetCard.swift:91`, `OverviewView.swift` (selectedTab), `RootView.swift:29-47`

**Issue:** Tab targets are raw integers (`selectedTab = 2`, `selectedTab = 3`). The mapping lives only in `RootView`'s doc comment. A reordering of tabs would silently break every deep-link/tab-switch button.

**Fix:** Introduce an enum (e.g. `enum Tab: Int { case home, expenses, budgets, notes }`) used by both `RootView.tag(...)` and the buttons.

### IN-04: `deepLinkBlockID` from notification userInfo is unvalidated cast

**File:** `MyHomeApp/RootView.swift:51-54`

**Issue:** `notification.userInfo?["noteID"] as? UUID` / `["blockID"] as? UUID` trust the notification payload. This is internal (posted by the app's own scheduler) so it is low-risk, and the `as? UUID` cast fails closed (nil) rather than crashing — hence Info, not a security finding. Worth a brief comment noting the payload is app-internal and not externally reachable, consistent with the T-04-07 mitigation notes elsewhere.

**Fix:** None required; optionally document the trust boundary.

---

_Reviewed: 2026-06-01_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
