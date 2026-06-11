---
phase: 11-asset-tracker
plan: "04"
subsystem: ui-overview
tags: [net-worth-card, donut-chart, trend-chart, overview, swiftui, tdd, wave-4]
dependency_graph:
  requires: [11-02, 11-03]
  provides: [NetWorthCard, NetWorthTrendChart, allocationSegments-builder, OverviewView-net-worth-section]
  affects: [OverviewView.swift, AssetsListView (navigation target)]
tech_stack:
  added: []
  patterns:
    - "Static allocationSegments() builder in NetWorthCard — pure Decimal→DonutSegment mapper, testable without SwiftData"
    - "max(v, 0) clamp via NSDecimalNumber for all 4 asset-class segments (T-11-12 / T-11-13)"
    - "NavigationLink wrapping entire NetWorthCard (buttonStyle: .plain) for tap-to-holdings"
    - "@State navigateToAssets + navigationDestination for sectionHeader action navigation"
    - "allGlobalExpenses @Query (unbounded) separate from monthExpenses for AccountBalance.compute correctness"
    - "NetWorthBreakdown computed outside ScrollView body (Pitfall A guard — never inside Chart DSL)"
key_files:
  created:
    - MyHomeApp/Features/Assets/NetWorthCard.swift
    - MyHomeApp/Features/Assets/NetWorthTrendChart.swift
    - MyHomeTests/AllocationSegmentTests.swift
  modified:
    - MyHomeApp/Features/Overview/OverviewView.swift
    - MyHome.xcodeproj/project.pbxproj
decisions:
  - "allocationSegments() is a static func on NetWorthCard (not a free function) so AllocationSegmentTests can import it via @testable without importing the whole view hierarchy"
  - "allGlobalExpenses: @Query separate from monthExpenses to provide unbounded expense history to AccountBalance.compute (month-bounded array would give wrong balances for old accounts)"
  - "navigateToAssets @State + navigationDestination used for 'See holdings' header action (sectionHeader action takes () -> Void closure; NavigationLink can't be triggered from a closure)"
  - "NetWorthBreakdown computed once in body and passed into both showNetWorth check and NetWorthCard init (avoid double-compute)"
  - "LockStateTests/enableLockAuthFailed pre-existing flaky test — unrelated to plan-04 changes; confirmed by git history"
metrics:
  duration_minutes: 35
  completed_date: "2026-06-11"
  tasks_completed: 2
  files_changed: 5
---

# Phase 11 Plan 04: Overview Net-Worth Card Summary

**One-liner:** NetWorthCard (4-class allocation donut + legend + trend chart) inserted into OverviewView after spend hero; cash segment clamped via NSDecimalNumber max(v,0); suppressed when no assets and cash is 0; tappable to AssetsListView.

---

## What Was Built

### Task 1 (TDD): allocationSegments builder + NetWorthCard + NetWorthTrendChart

**Commits:** `6e4fced`

**NetWorthCard.swift** (`MyHomeApp/Features/Assets/NetWorthCard.swift`, 134 lines):

- `static func allocationSegments(mf:stock:nps:cash:) -> [DonutSegment]` — pure builder, 4 segments with `NSDecimalNumber(decimal: max(v, 0)).doubleValue` (T-11-12: cash clamp; T-11-13: NSDecimalNumber boundary). Segment IDs: "mf", "stock", "nps", "cash". Colors: `Color(.systemBlue)/.systemGreen/.systemOrange/.systemTeal`.
- `var body`: computes `NetWorthBreakdown` from `NetWorthCalculator.breakdown(...)`, builds segments, wraps card in `NavigationLink(destination: AssetsListView())` with `.buttonStyle(.plain)`.
- Card layout mirrors `WhereItsGoingCard`: `HStack` with `DonutChart(segments:size:132)` left (center overlay: "NET WORTH" `.caption2.weight(.semibold)` + `totalNetWorth.formattedINRWhole()` `.headline`, `minimumScaleFactor(0.5)`, `.accessibilityValue(total.formattedINR())`), legend `VStack` right (4 rows: 10×10 swatch + label + sub-total, spacing 11), then `NetWorthTrendChart` below.
- `cardStyle(cornerRadius: 16, padding: 18)`.
- `DonutChart` has `.accessibilityHidden(true)` built into the component itself.

**NetWorthTrendChart.swift** (`MyHomeApp/Features/Assets/NetWorthTrendChart.swift`, 86 lines):

- Accepts `[NetWorthSnapshot]`.
- Converts `snap.totalNetWorth` to `Double` via `NSDecimalNumber(decimal:).doubleValue` at the boundary (T-11-13) — never passes raw `Decimal` to `.value(...)`.
- `Chart(points, id: \.date)` with `AreaMark` + `LineMark` (lineWidth 2, accentColor).
- `chartYAxis`: `formattedINRCompact()` labels.
- `chartXAxis`: `.dateTime.month(.abbreviated)`.
- `.frame(height: 140)`.
- Empty state: `Text("No history yet.")` `.subheadline` `.secondary`, `frame(height: 80)`.
- `.accessibilityLabel("Net worth trend chart")`.

**AllocationSegmentTests.swift** (`MyHomeTests/AllocationSegmentTests.swift`, 7 test cases):
1. `testAlwaysReturns4Segments` — count 4 in all edge cases
2. `testNegativeCashSegmentClampsToZero` — cash=-300_000 → cash segment value==0.0
3. `testLargeNegativeCashClampsToZero` — very large CC debt → cash segment value==0.0
4. `testTrueTotalPreservedWhenNegative` — NetWorthBreakdown.totalNetWorth=-985_000, positive mf/stock segments carry real values
5. `testPositiveValuesConvertedCorrectly` — mf/stock/nps/cash positive values pass through
6. `testZeroSubTotalProducesZeroValueSegment` — stock=0 → stock segment value==0.0
7. `testSegmentIDsAreCorrect` — all 4 IDs present

Result: `** TEST SUCCEEDED **` on iPhone 17 Pro.

### Task 2: Insert NetWorthCard into OverviewView

**Commit:** `f87eead`

Changes to `OverviewMonthContent` in `OverviewView.swift`:

1. Added 4 `@Query` declarations:
   - `@Query(sort: \Asset.createdAt, order: .reverse) private var allAssets: [Asset]`
   - `@Query(sort: \NetWorthSnapshot.date, order: .reverse) private var netWorthSnapshots: [NetWorthSnapshot]`
   - `@Query private var allAccounts: [Account]`
   - `@Query private var allGlobalExpenses: [Expense]` (unbounded — distinct from monthExpenses)

2. Added `@State private var navigateToAssets = false`.

3. In `body`, before `ScrollView`: compute `netWorthBreakdown` from `NetWorthCalculator.breakdown(assets:accounts:expenses:)` and derive `showNetWorth = !allAssets.isEmpty || netWorthBreakdown.cashValue != 0` (suppression test outside Chart DSL — Pitfall A guard).

4. Inserted after SpendBudgetCard (and optional ReviewBanner), before "Where it's going":
   ```swift
   if showNetWorth {
       sectionHeader("Net Worth", action: ("See holdings", { navigateToAssets = true }))
       NetWorthCard(allAssets: allAssets, allAccounts: allAccounts, allExpenses: allGlobalExpenses, snapshots: netWorthSnapshots)
           .padding(.horizontal, 16)
   }
   ```
   No section header or card is rendered when `!showNetWorth`.

5. Added `.navigationDestination(isPresented: $navigateToAssets) { AssetsListView() }` on the ScrollView.

Build result: `** BUILD SUCCEEDED **`.
Full test suite: `** TEST FAILED **` — only `LockStateTests/enableLockAuthFailed()` failed; this is a pre-existing flaky biometric auth test confirmed present in `5ff93c3` (wave-3 completion commit) and unrelated to plan-04 changes.

---

## Human-Verify Checkpoint: PENDING orchestrator/user

The final task is `type="checkpoint:human-verify"` (gate="blocking"). Per the orchestrator's instructions, this worktree completes all implementation; human verification is run by the orchestrator after the worktree is merged.

### Verbatim Verification Steps (from 11-04-PLAN.md checkpoint task):

**How to verify:**
1. Build & run on iPhone 17 simulator (scheme MyHome). With NO holdings and all account balances 0: open Overview — confirm NO "Net Worth" section/card appears.
2. Add at least one holding (Settings > Assets) and/or ensure an account has a balance. Return to Overview — the "Net Worth" card now appears after the spend hero, before "Where it's going".
3. Confirm the donut center shows "NET WORTH" + the total (formatted INR). Confirm the legend lists Mutual Funds (blue), Stocks (green), NPS (orange), Cash (teal) with sub-totals.
4. Confirm the net-worth trend chart renders below (or "No history yet." if only one day of snapshots — relaunch the app the next IST day, or it shows the single point/empty state).
5. Tap the card (and separately the "See holdings" header action) — both navigate to the holdings list.
6. Negative-net case (optional): set a credit-card account with debt larger than savings + holdings. Confirm the center total shows a negative value (e.g. "−₹...") and the donut renders without crashing (cash slice absent/zero).

**Resume signal:** Type "approved" or describe any issues (placement, donut colors/legend, trend chart, navigation, negative-net rendering).

---

## Deviations from Plan

### Auto-fixed Issues

None — plan executed exactly as written.

### Notes

**Pre-existing test failure (out of scope):** `LockStateTests/enableLockAuthFailed()` fails intermittently due to biometric mock timing (confirmed present in main@5ff93c3 before this plan). Not caused by plan-04 changes. Logged to deferred-items for tracking.

---

## Threat Surface Scan

All threats in the plan's threat register are mitigated:

| Threat | Status | Evidence |
|--------|--------|---------|
| T-11-12 (negative cash crashes SectorMark) | Mitigated | `NSDecimalNumber(decimal: max(v, 0)).doubleValue` in allocationSegments(); AllocationSegmentTests covers this case (3 tests) |
| T-11-13 (raw Decimal in .value()) | Mitigated | NetWorthCard uses `NSDecimalNumber(decimal: max(v, 0)).doubleValue`; NetWorthTrendChart uses `NSDecimalNumber(decimal: snap.totalNetWorth).doubleValue` — zero raw Decimal calls in Chart DSL |
| T-11-SC (package installs) | Accept | Zero new SPM dependencies — Swift Charts is built-in |

No new security surface beyond the plan's threat model.

---

## Known Stubs

None. NetWorthCard and NetWorthTrendChart are fully implemented:
- `NetWorthCard` wired to `NetWorthCalculator.breakdown()` — live data, not placeholder
- `NetWorthTrendChart` renders from `[NetWorthSnapshot]` — live snapshots from SwiftData
- Suppression logic: `showNetWorth` derived from real `@Query` arrays

---

## Self-Check: PASSED

| Item | Status |
|------|--------|
| NetWorthCard.swift | FOUND |
| NetWorthTrendChart.swift | FOUND |
| AllocationSegmentTests.swift | FOUND |
| OverviewView.swift (updated) | FOUND |
| project.pbxproj (4 new entries each for app+test files) | FOUND |
| Commit 6e4fced (Task 1) | FOUND |
| Commit f87eead (Task 2) | FOUND |
| `max(` in NetWorthCard.allocationSegments | FOUND (line 126) |
| `NSDecimalNumber` in NetWorthCard | FOUND (line 126) |
| `NSDecimalNumber` in NetWorthTrendChart | FOUND (line 33) |
| No raw Decimal in .value() calls | CONFIRMED |
| `accessibilityHidden(true)` on DonutChart | Built into DonutChart component |
| `accessibilityValue` on total text | FOUND (line 71) |
| `accessibilityLabel("Net worth trend chart")` | FOUND |
| AllocationSegmentTests: negative cash clamped | FOUND (tests 2+3) |
| AllocationSegmentTests: 4 segments | FOUND (test 1) |
| AllocationSegmentTests: true total not clamped | FOUND (test 4) |
| AllocationSegmentTests GREEN on iPhone 17 Pro | PASSED |
| Full build: BUILD SUCCEEDED | CONFIRMED |
| @Query Asset in OverviewView | FOUND (line 99) |
| @Query NetWorthSnapshot in OverviewView | FOUND (line 100) |
| @Query Account in OverviewView | FOUND (line 101) |
| Conditional render NetWorthCard | FOUND (`if showNetWorth`) |
| navigationDestination to AssetsListView | FOUND (line 238) |
| "See holdings" sectionHeader action | FOUND (line 182) |
