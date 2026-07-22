---
phase: 21-overview-filtering
reviewed: 2026-07-22T00:00:00Z
depth: standard
files_reviewed: 6
files_reviewed_list:
  - MyHomeApp/Support/OverviewFilter.swift
  - MyHomeApp/Features/Overview/OverviewView.swift
  - MyHomeApp/Features/Overview/OverviewFilterSheet.swift
  - MyHomeApp/Features/Overview/OverviewScopePill.swift
  - MyHomeApp/MyHomeApp.swift
  - MyHomeTests/OverviewFilterTests.swift
findings:
  critical: 0
  warning: 4
  info: 4
  total: 8
status: issues_found
---

# Phase 21: Code Review Report

**Reviewed:** 2026-07-22
**Depth:** standard
**Files Reviewed:** 6
**Status:** issues_found

## Summary

Phase 21 adds an Overview account × date-range filter (`OverviewFilter` value type +
`OverviewFilterEngine` pure helpers + a scope pill + a filter sheet). The four highlighted
risk areas were traced and found **correct**:

- **Transfer exclusion (T-21-02):** `OverviewFilterEngine.apply` deliberately handles only the
  account dimension and defers cash-flow math to `BudgetCalculator.grossSpend`/`grossIncome`,
  which route through `isTransferForCashFlow`. That helper excludes a leg as soon as
  `transferPairID != nil` (not merely `isTransfer == true`), so single-leg pending pairs are
  excluded even after account filtering. `transferExclusionPreserved` proves it. No divergence
  from the hero readout.
- **Date boundaries (T-21-01):** `rangeBoundaries` produces inclusive `[startOfDay, 23:59:59]`,
  mirrors `BudgetCalculator.monthBoundaries` exactly, is injectable-calendar and IST-tested, and
  defensively swaps `from > to`. `ClosedRange` construction in `applyCustomRange` is guarded with
  `min`/`max`, so no range-trap.
- **Default == cleared:** `OverviewFilter()` is `Equatable` and produces the neutral scope
  (`isActive == false`); `Reset`/`onClear` both assign `OverviewFilter()`. Confirmed.
- **@State/@Binding threading:** parent `@State filter` flows through child `@Binding`; sheet
  seeds local `@State` via `State(initialValue:)` in `init`. Correct.

No BLOCKER-tier defects. The findings below are display-correctness, timezone-consistency, and
maintainability issues, plus one DEBUG-only crash path.

## Warnings

### WR-01: Scope pill drops the "from" year on cross-year ranges (ambiguous disclosure)

**File:** `MyHomeApp/Features/Overview/OverviewScopePill.swift:95-109`
**Issue:** In `OverviewScopePill.rangeLabel`, `fromFmt` is *always* `"dMMM"` (never year), while
`toFmt` adds the year only when the two endpoints are in *different* years. For a range spanning a
year boundary (e.g. 5 Dec 2025 – 12 Jan 2026) the pill renders **"5 Dec – 12 Jan 2026"** — the
2025 on the from-side is silently lost, so the label is ambiguous about which December. Because the
pill is the primary "these figures are scoped" disclosure (threat T-21-05), an ambiguous scope
label undercuts its purpose. Note this also disagrees with `OverviewView.rangeLabel` (WR-02), whose
`fromFmt` *does* conditionally show the year — so the header and the pill can display different
strings for the identical range.
**Fix:** Show the from-side year whenever the endpoints span different years, matching
`OverviewView.rangeLabel`:
```swift
fromFmt.setLocalizedDateFormatFromTemplate(sameYear ? "dMMM" : "dMMMyyyy")
```

### WR-02: Duplicated, divergent `rangeLabel` implementations

**File:** `MyHomeApp/Features/Overview/OverviewView.swift:56-71` and `MyHomeApp/Features/Overview/OverviewScopePill.swift:95-109`
**Issue:** Two near-identical private `rangeLabel(from:to:)` helpers exist. They are not just
duplicated — they format differently (header always shows the trailing year and conditionally shows
the from-year; pill never shows the from-year), so the same custom range produces two different
human-readable strings in two places on the same screen. This is both a maintenance hazard and a
user-facing inconsistency.
**Fix:** Extract a single shared formatter (e.g. a `static func` on `OverviewFilterEngine` or a
`Date` range extension) and call it from both the header and the pill so the label is defined once.

### WR-03: Clear button's 44×44 hit target overhangs the capsule and the label

**File:** `MyHomeApp/Features/Overview/OverviewScopePill.swift:37-38, 63-75`
**Issue:** When active, the layout only *reserves* a 20×20 `Color.clear` inside the capsule
(line 38), but the overlaid clear `Button` uses a 44×44 `contentShape(Rectangle())` frame
(line 69) pinned `.trailing`. A 44pt tap target on a ~36pt-tall capsule extends above/below the
capsule and inward over the trailing edge of the summary label. Taps near the right end of the
label — the region a user reads to check scope, then taps to edit — can land on "Clear filters"
and wipe the filter instead of opening the sheet. Given clear has no confirmation (OVF-03), an
accidental clear is a silent data-scope reset.
**Fix:** Shrink the clear button's hit frame to match the reserved slot (e.g. `frame(width: 28,
height: 28)`) or increase the reserved `Color.clear` width so the label never sits under the
overlay; verify the label and clear regions do not overlap.

### WR-04: Production range/label math uses `Calendar.current`, so boundary correctness depends on device timezone

**File:** `MyHomeApp/Features/Overview/OverviewView.swift:45, 57-58` and `MyHomeApp/Support/OverviewFilter.swift:100`
**Issue:** `rangeBoundaries` is injectable-calendar and the tests pin Asia/Kolkata, but every
production call site uses the `.current` default (`effectiveBounds` at line 45, `rangeLabel` at
57-58). The `@Query` window (`expense.date >= lo && expense.date <= hi`) is therefore built from
the *device* timezone's day edges, while bank-mail expense timestamps are IST-anchored. On a device
whose timezone differs from IST (traveling, or a second household phone set to another region — this
is a two-phone-sync app), a custom "1–15 Jul" range can shift its start/end by the UTC offset and
include or drop a boundary day's expenses relative to what the label claims. The app is IST-centric
so impact is low in practice, but the tested-correct engine is not exercising the same calendar the
UI uses.
**Fix:** Either standardize the app on an explicit IST calendar for financial day-edges, or make the
timezone assumption explicit and documented at the call sites; at minimum add a test that runs the
production path (`effectiveBounds`) under a non-IST device calendar to pin the intended behavior.

## Info

### IN-01: DEBUG `-filterRangeDays` can trap on a reversed ClosedRange

**File:** `MyHomeApp/Features/Overview/OverviewView.swift:421-425`
**Issue:** `filter.dateRange = from...to` where `from = ...date(byAdding: .day, value: -days,...)`.
A negative launch argument (`-filterRangeDays -5`) makes `from > to`, and `from...to` traps at
runtime. DEBUG-only and self-inflicted, but unlike `applyCustomRange` there is no `min`/`max` guard.
**Fix:** Build the range defensively: `let (a, b) = from <= to ? (from, to) : (to, from); filter.dateRange = a...b`.

### IN-02: `double`/`fraction` helpers duplicated across views

**File:** `MyHomeApp/Features/Overview/OverviewView.swift:473-477` and `MyHomeApp/Features/Overview/OverviewView.swift:634-637`
**Issue:** Identical `Decimal → Double` fraction helpers exist in both `OverviewMonthContent` and
`BudgetGlancePills`. Minor duplication of the same NaN-guard logic.
**Fix:** Hoist to a shared `Decimal` extension or a single fileprivate helper.

### IN-03: Custom-range pickers are not visually re-ordered

**File:** `MyHomeApp/Features/Overview/OverviewFilterSheet.swift:243-247, 326-330`
**Issue:** `applyCustomRange` clamps with `min`/`max` for storage (correct), but the `From`/`To`
`DatePicker`s bind directly to `customFrom`/`customTo` with no `in:` range, so the UI can display a
"From" date later than "To" while the stored range is silently swapped. Harmless to data, mildly
confusing to the user.
**Fix:** Bound the pickers (`DatePicker("To", selection: $customTo, in: customFrom...)`) or reflect
the clamp back into the local state after `applyCustomRange`.

### IN-04: 23:59:59 end boundary can exclude sub-second events on the end day

**File:** `MyHomeApp/Support/OverviewFilter.swift:104-107`
**Issue:** `end` is `startOfDay(hi) + 1 day − 1 second` (23:59:59.000). An expense timestamped in
the final sub-second of the end day (e.g. 23:59:59.6) would fall outside the inclusive window. This
mirrors `BudgetCalculator.monthBoundaries`, so it is a consistent, pre-existing convention rather
than a regression — noted only for completeness.
**Fix:** None required for consistency; if ever tightened, do it in both `rangeBoundaries` and
`monthBoundaries` together (e.g. use start-of-next-day with a strict `< end` predicate).

---

_Reviewed: 2026-07-22_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
