---
phase: "04-overview-charts"
plan: "02"
subsystem: "support"
tags: [tdd, green, spend-aggregation, overview, inr-formatting, pure-helpers]
dependency_graph:
  requires:
    - MyHomeTests/SpendOverTimeAggregatorTests.swift
    - MyHomeTests/OverviewAggregationTests.swift
    - MyHomeTests/DecimalINRTests.swift
  provides:
    - MyHomeApp/Support/SpendOverTimeAggregator.swift
    - MyHomeApp/Support/OverviewAggregation.swift
    - MyHomeApp/Support/Decimal+INR.swift (extended)
  affects:
    - MyHome.xcodeproj/project.pbxproj
tech_stack:
  added: []
  patterns:
    - NSDecimalNumber(decimal:).doubleValue for Decimal→Double at aggregation boundary (Pitfall B)
    - Pure enum namespace (no stored state, no SwiftUI) — mirrors CalendarAggregator discipline
    - startOfDay helper copied verbatim from CalendarAggregator (device-timezone bucketing)
    - NoteListOrganizer.organize routing for OVR-03 (not isPinned directly — Pitfall E)
key_files:
  created:
    - MyHomeApp/Support/SpendOverTimeAggregator.swift
    - MyHomeApp/Support/OverviewAggregation.swift
  modified:
    - MyHomeApp/Support/Decimal+INR.swift
    - MyHomeTests/OverviewAggregationTests.swift
    - MyHome.xcodeproj/project.pbxproj
decisions:
  - "Decimal→Double conversion via NSDecimalNumber(decimal:).doubleValue only at SpendBucket construction — money stays Decimal through entire accumulation loop"
  - "OVR-03 routes through NoteListOrganizer.organize(_:).pinned.first — daily-routine+pinned notes excluded without special-casing (Pitfall E)"
  - "All zero-spend slots emitted — never omit empty buckets (Pitfall C, chart gap prevention)"
metrics:
  duration: 45
  completed_date: "2026-06-01"
---

# Phase 4 Plan 2: GREEN Phase — Three Pure Helpers Summary

GREEN phase: implemented SpendOverTimeAggregator (EXP-11 week/month/year bucketing), OverviewAggregation (OVR-01/02/03 aggregate math), and formattedINRCompact() (chart axis formatter). All 30 tests from Plan 04-01's RED scaffold now pass.

## What Was Built

### Task 1: formattedINRCompact() on Decimal

**File:** `MyHomeApp/Support/Decimal+INR.swift` (extended)

Added `formattedINRCompact()` immediately after `formattedINR()` in the existing extension:

```swift
extension Decimal {
    func formattedINRCompact() -> String {
        let d = NSDecimalNumber(decimal: self).doubleValue
        if d >= 100_000 { return "₹\(Int(d / 100_000))L" }
        if d >= 1_000   { return "₹\(Int(d / 1_000))k" }
        return "₹\(Int(d))"
    }
}
```

- No NumberFormatter introduced; uses Int truncation per spec
- Conversion via NSDecimalNumber(decimal:).doubleValue (Pitfall B guard)
- Doc-comment distinguishes this from formattedINR() (chart axis only vs. everywhere else)

**DecimalINRTests:** 10/10 tests GREEN

### Task 2: SpendOverTimeAggregator + SpendRange + SpendBucket (EXP-11)

**File:** `MyHomeApp/Support/SpendOverTimeAggregator.swift` (new)

**Final public signatures:**

```swift
enum SpendRange: String, CaseIterable {
    case week, month, year
    var label: String  // "Week" / "Month" / "Year"
}

struct SpendBucket: Identifiable {
    let id: Date
    let date: Date
    let spent: Double
    var dateLabel: String
}

enum SpendOverTimeAggregator {
    static func bucket(
        expenses: [Expense],
        range: SpendRange,
        calendar: Calendar = .current
    ) -> [SpendBucket]
}
```

Key implementation decisions:
- All slots emitted including zero-spend (Pitfall C guard — chart would show gaps otherwise)
- Decimal accumulated per-slot; NSDecimalNumber(decimal:).doubleValue only at SpendBucket init
- startOfDay helper copied verbatim from CalendarAggregator (device-timezone bucketing)
- Negative amounts (refunds) reduce the bucket — consistent with BudgetCalculator convention
- No import Charts, no SwiftUI, no @Query

**SpendOverTimeAggregatorTests:** 7/7 tests GREEN

### Task 3: OverviewAggregation helper (OVR-01/02/03)

**File:** `MyHomeApp/Support/OverviewAggregation.swift` (new)

**Final public signatures:**

```swift
enum OverviewAggregation {
    static func aggregateThreshold(
        totalSpend: Decimal,
        totalBudget: Decimal
    ) -> (fractionUsed: Double?, color: BudgetColor)

    static func topCategories(
        spendByCategory: [PersistentIdentifier: Decimal],
        categories: [Category]
    ) -> [(category: Category, spent: Decimal)]

    static func pinnedOrChecklistNote(from notes: [Note]) -> Note?
}
```

Key implementation:
- OVR-01: totalBudget <= 0 → fractionUsed nil; thresholds 0.8/1.0 mirror BudgetProgressData
- OVR-02: compactMap (spend > 0 filter) → sorted (descending spend, alphabetical tie-break) → prefix(3)
- OVR-03: NoteListOrganizer.organize(notes).pinned.first → checklist block fallback → nil

**OverviewAggregationTests:** 13/13 tests GREEN

---

## Full Suite Result

All 3 RED suites from Plan 04-01 are now GREEN:
- `DecimalINRTests`: 10 tests PASSED
- `SpendOverTimeAggregatorTests`: 7 tests PASSED
- `OverviewAggregationTests`: 13 tests PASSED
- Full project test suite: SUCCEEDED (all prior tests still pass)

---

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] ReminderRecurrence initializer had invalid `interval:` parameter**
- **Found during:** Task 3 (first build attempt)
- **Issue:** `OverviewAggregationTests.swift` (created in Plan 04-01) called `ReminderRecurrence(type: .daily, interval: 1)` but `ReminderRecurrence.init` only accepts `(type:weekdays:)` — the `interval` parameter does not exist, causing a compile error.
- **Fix:** Changed to `ReminderRecurrence(type: .daily)` — correct call with no extra arguments.
- **Files modified:** `MyHomeTests/OverviewAggregationTests.swift`
- **Commit:** 130eb41

---

## Known Stubs

None. These are pure computation helpers with no UI rendering and no data wiring. No stub patterns introduced.

---

## Threat Flags

None. No new network endpoints, auth paths, file access patterns, or schema changes introduced. All three helpers are pure read-only aggregation over already-fetched local arrays.

---

## Self-Check: PASSED

| Check | Result |
|-------|--------|
| `MyHomeApp/Support/Decimal+INR.swift` formattedINRCompact exists | FOUND (grep -c returns 1) |
| `MyHomeApp/Support/SpendOverTimeAggregator.swift` exists | FOUND |
| `MyHomeApp/Support/OverviewAggregation.swift` exists | FOUND |
| commit 902c1be exists | FOUND |
| commit 8140a2f exists | FOUND |
| commit 130eb41 exists | FOUND |
| Full test suite SUCCEEDED | CONFIRMED |
| import Charts in SpendOverTimeAggregator | 0 (CONFIRMED) |
| import SwiftUI in OverviewAggregation | 0 (CONFIRMED) |
| note.isPinned in OverviewAggregation | 0 (CONFIRMED) |
| NoteListOrganizer.organize in OverviewAggregation | 2 (CONFIRMED) |
| NSDecimalNumber(decimal: in SpendOverTimeAggregator | 5 (CONFIRMED) |
