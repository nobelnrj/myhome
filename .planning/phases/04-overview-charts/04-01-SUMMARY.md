---
phase: "04-overview-charts"
plan: "01"
subsystem: "tests"
tags: [tdd, red, nyquist, spend-aggregation, overview, inr-formatting]
dependency_graph:
  requires: []
  provides:
    - MyHomeTests/SpendOverTimeAggregatorTests.swift
    - MyHomeTests/OverviewAggregationTests.swift
    - MyHomeTests/DecimalINRTests.swift
  affects:
    - MyHome.xcodeproj/project.pbxproj
tech_stack:
  added: []
  patterns:
    - Swift Testing (@MainActor struct + @Test + #expect)
    - In-memory ModelContainer (isStoredInMemoryOnly: true)
    - RED-state compile-fail scaffold (TDD Wave 0)
key_files:
  created:
    - MyHomeTests/SpendOverTimeAggregatorTests.swift
    - MyHomeTests/OverviewAggregationTests.swift
    - MyHomeTests/DecimalINRTests.swift
  modified:
    - MyHome.xcodeproj/project.pbxproj
decisions:
  - "OverviewAggregation.pinnedOrChecklistNote routed through NoteListOrganizer.organize (not note.isPinned) — Pitfall E guard enforced in test"
  - "SpendRange.week/month/year written as explicit SpendRange.week (not .week) for grep-verifiable contract"
  - "Added Pitfall-E test case that checks a dailyRoutine+pinned note is excluded from the pinned card"
metrics:
  duration: 31
  completed_date: "2026-06-01"
---

# Phase 4 Plan 1: Failing-Test Scaffold (Wave 0 RED) Summary

Wave 0 RED scaffold: three failing-test files encoding the EXP-11 bucketing, OVR-01/02/03 aggregation, and formattedINRCompact() contracts. Build fails on missing production symbols as expected.

## What Was Built

### Task 1: SpendOverTimeAggregatorTests.swift (EXP-11 RED)

**File:** `MyHomeTests/SpendOverTimeAggregatorTests.swift`
**Tests:** 7 `@Test` methods
**Covers:**
- Week range → exactly 7 daily `SpendBucket` entries
- Month range → 28-31 daily entries (current month day count)
- Year range → exactly 12 monthly entries
- Zero-spend week: all 7 buckets present with `spent == 0.0` (Pitfall C)
- Zero-spend year: all 12 buckets present with `spent == 0.0`
- `Decimal(1234.56)` → `Double` boundary (tolerance `< 0.01`)
- Refund: negative-amount expense reduces day bucket (net 300 or clamped 0)

**RED state:** `cannot find 'SpendOverTimeAggregator' in scope`, `cannot find 'SpendRange' in scope`

### Task 2: OverviewAggregationTests.swift (OVR-01/02/03 RED)

**File:** `MyHomeTests/OverviewAggregationTests.swift`
**Tests:** 13 `@Test` methods
**Covers:**

OVR-01 aggregate threshold:
- `fractionUsed = 0.5` → `.normal`
- `fractionUsed = 0.85` → `.warning` (boundary case)
- `fractionUsed = 1.1` → `.overBudget`
- `totalBudget == 0` → `fractionUsed nil`, color `.normal` (no divide-by-zero)
- `totalSpend` includes uncategorized (800/1000 = 0.8 → `.warning` boundary)

OVR-02 top-3:
- 4 categories with spend → exactly 3 returned, descending
- Alphabetical tie-break: "Dining" < "Groceries" when spend equal
- Sparse spend (1 category) → 1 row returned (no placeholders)

OVR-03 pinned note:
- Pinned note present → returned
- No pinned, checklist note exists → checklist note returned
- No pinned, no checklist → `nil` (empty state)
- Empty notes array → `nil`
- **Pitfall E guard:** daily-routine + pinned note excluded via `NoteListOrganizer.organize` (not `note.isPinned`)

**RED state:** `cannot find 'OverviewAggregation' in scope`

### Task 3: DecimalINRTests.swift (formattedINRCompact RED)

**File:** `MyHomeTests/DecimalINRTests.swift`
**Tests:** 10 `@Test` methods (pure, no ModelContainer)
**Covers:**
- `< 1000` bucket: `Decimal(500)` → `"₹500"`, `Decimal(1)` → `"₹1"`, `Decimal(999)` → `"₹999"`
- `≥ 1000` bucket: `Decimal(1000)` → `"₹1k"` (boundary inclusive), `Decimal(5000)` → `"₹5k"`, `Decimal(50000)` → `"₹50k"`, `Decimal(99000)` → `"₹99k"`
- `≥ 100000` bucket: `Decimal(100000)` → `"₹1L"` (boundary inclusive; not `"₹100k"`), `Decimal(150000)` → `"₹1L"`, `Decimal(500000)` → `"₹5L"`

**RED state:** `value of type 'Decimal' has no member 'formattedINRCompact'`

---

## Function Signatures Expected by Tests (Plan 04-02 Must Implement Verbatim)

```swift
// MyHomeApp/Support/SpendOverTimeAggregator.swift (new)
enum SpendRange { case week, month, year }

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

// MyHomeApp/Support/OverviewAggregation.swift (new)
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

// MyHomeApp/Support/Decimal+INR.swift (extend — add after formattedINR())
extension Decimal {
    func formattedINRCompact() -> String {
        let d = NSDecimalNumber(decimal: self).doubleValue
        if d >= 100_000 { return "₹\(Int(d / 100_000))L" }
        if d >= 1_000   { return "₹\(Int(d / 1_000))k" }
        return "₹\(Int(d))"
    }
}
```

---

## Verification

### RED state confirmed (build-for-testing output):
```
/MyHomeTests/SpendOverTimeAggregatorTests.swift:59: error: cannot find 'SpendOverTimeAggregator' in scope
/MyHomeTests/SpendOverTimeAggregatorTests.swift:61: error: cannot find 'SpendRange' in scope
/MyHomeTests/DecimalINRTests.swift:24: error: value of type 'Decimal' has no member 'formattedINRCompact'
/MyHomeTests/OverviewAggregationTests.swift: error: cannot find 'OverviewAggregation' in scope
```

Only errors are "cannot find ... in scope" for not-yet-written symbols — exactly the Nyquist gate RED state.

### No production source files were modified.

---

## Deviations from Plan

**1. [Rule 2 - Missing Critical] Added explicit NoteListOrganizer.organize call in test (Pitfall E)**
- **Found during:** Task 2
- **Issue:** Plan acceptance criteria requires `NoteListOrganizer.organize` to appear in the test file. Initial version had it only in comments. Also added a dedicated Pitfall-E test that verifies a dailyRoutine+pinned note is excluded, with a direct `NoteListOrganizer.organize` assertion before the `OverviewAggregation` call.
- **Fix:** Added `pinnedOrChecklistNote_usesNoteListOrganizer` test method with explicit `NoteListOrganizer.organize` code call.
- **Files modified:** `MyHomeTests/OverviewAggregationTests.swift`
- **Commit:** 6bd20a9

**2. [Rule 1 - Bug] Explicit SpendRange.week syntax for grep-verifiability**
- **Found during:** Task 1
- **Issue:** Initial file used `range: .week` (enum dot syntax) which the acceptance criteria grep pattern `SpendRange.week` would not match.
- **Fix:** Changed all `range: .week/.month/.year` to explicit `range: SpendRange.week/SpendRange.month/SpendRange.year`.
- **Files modified:** `MyHomeTests/SpendOverTimeAggregatorTests.swift`
- **Commit:** 3c14a33

---

## TDD Gate Compliance

This plan is a pure TDD RED phase (Wave 0 scaffold).

| Gate | Status |
|------|--------|
| RED commits exist | All 3 `test(04-01):` commits present (3c14a33, 6bd20a9, 7afe53b) |
| GREEN gate | Not applicable — GREEN is Plan 04-02 |
| REFACTOR gate | Not applicable |

---

## Known Stubs

None. This plan creates only test scaffolding (no production code, no UI, no data wiring).

---

## Threat Flags

None. No new input surface, network paths, auth paths, or persistence writes introduced. Test files use in-memory `ModelContainer(isStoredInMemoryOnly: true)` — no real data.

---

## Self-Check: PASSED

| Check | Result |
|-------|--------|
| `MyHomeTests/SpendOverTimeAggregatorTests.swift` exists | FOUND |
| `MyHomeTests/OverviewAggregationTests.swift` exists | FOUND |
| `MyHomeTests/DecimalINRTests.swift` exists | FOUND |
| commit 3c14a33 exists | FOUND |
| commit 6bd20a9 exists | FOUND |
| commit 7afe53b exists | FOUND |
| Build fails RED (missing symbols) | CONFIRMED |
