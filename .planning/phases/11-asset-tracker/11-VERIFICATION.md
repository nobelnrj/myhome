---
phase: 11-asset-tracker
verified: 2026-06-11T00:00:00Z
status: passed
score: 9/9 must-haves verified
overrides_applied: 0
---

# Phase 11: Asset Tracker Verification Report

**Phase Goal:** Users can record all household holdings (mutual funds, stocks, NPS) and see total net worth as the sum of holding values and account balances; MF NAVs refresh best-effort from AMFI; every price carries its as-of date and a staleness indicator
**Verified:** 2026-06-11
**Status:** PASSED
**Re-verification:** No — initial verification

---

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | User can add, edit, and delete holdings (MF/stock/NPS) | VERIFIED | `AssetsListView` (CRUD list + swipe-delete + `context.delete` + `context.save`), `EditAssetView` (nil=create/non-nil=edit with `saveAsset`/`deleteAsset`), wired via `SettingsView` `NavigationLink(destination: AssetsListView())` at line 203 |
| 2 | User records units and cost basis; current value is derived | VERIFIED | `Asset` @Model has `units: Decimal?` + `costBasisPerUnit: Decimal?` + `currentNAV: Decimal?`; `AssetValuation.currentValue(units:currentNAV:)` = `(units ?? 0) * (currentNAV ?? 0)`; exercised by `AssetValueTests` |
| 3 | MF NAVs auto-refresh best-effort from AMFI (never blocks UI; cached on failure; user can override manually) | VERIFIED | `AMFINavService.refreshIfNeeded()` IST-gated; `performFetch` wrapped in `Task {}`; catch block logs + returns silently (D-07); `forceRefresh()` for pull-to-refresh; `EditAssetView` NAV field is always editable |
| 4 | Stock and NPS holdings are valued by manual current-price entry | VERIFIED | `EditAssetView` Section 4 labels "Current price" for non-MF classes; no scheme picker row rendered when `assetClassRaw != "mutual_fund"`; `saveAsset` sets `amfiSchemeCode = nil` for non-MF |
| 5 | User sees total net worth = sum of holding values + account balances | VERIFIED | `NetWorthCalculator.breakdown(assets:accounts:expenses:)` aggregates `mfValue + stockValue + npsValue + cashValue` where `cashValue` = `AccountBalance.compute(...)` for each non-archived account; rendered in `NetWorthCard` center overlay on OverviewView |
| 6 | User sees per-holding gain/loss (absolute and %) against cost basis | VERIFIED | `AssetValuation.absoluteGain/percentGain` (Decimal, nil when totalCost <= 0); rendered in `AssetDetailView` with explicit +/- prefix and green/red/primary color; zero-cost "—" path present |
| 7 | User sees asset-allocation chart (net worth split by asset class) | VERIFIED | `NetWorthCard.allocationSegments(mf:stock:nps:cash:)` → 4 `DonutSegment`s; cash clamped `max(v, 0)` via `NSDecimalNumber`; rendered in `DonutChart(segments:size:132)` inside `NetWorthCard`; negative-cash crash prevented |
| 8 | The app snapshots net worth over time and charts the trend | VERIFIED | `NetWorthSnapshotService.upsertIfNeeded()` → `performUpsert` with bounded `[todayIST, tomorrowIST)` fetch-before-insert (CR-01 fix); `NetWorthTrendChart` renders `AreaMark + LineMark` from `[NetWorthSnapshot]`; shown in `NetWorthCard` when `snapshots.count >= 2` |
| 9 | Every price carries its as-of date and a staleness indicator when data is older than the freshness threshold | VERIFIED | `StalenessView(navAsOfDate:)` uses `AssetValuation.isStale(navAsOfDate:)` with Asia/Kolkata IST calendar; threshold > 1 day; renders orange "Stale" badge; `AssetDetailView` shows "as of {date}" or "price not set" when nil |

**Score:** 9/9 truths verified

---

### Required Artifacts

| Artifact | Status | Details |
|----------|--------|---------|
| `MyHomeApp/Persistence/Schema/SchemaV7.swift` | VERIFIED | 295 lines; `enum SchemaV7: VersionedSchema` with `versionIdentifier` = `.init(7, 0, 0)`; all 7 @Models including `NetWorthSnapshot`; `amfiSchemeCode: String? = nil` on Asset; 0 actual `@Attribute(.unique)` usages (10 occurrences are all in comments) |
| `MyHomeApp/Persistence/Models/NetWorthSnapshot.swift` | VERIFIED | `typealias NetWorthSnapshot = SchemaV7.NetWorthSnapshot`; STAB-08 doc-comment present |
| `MyHomeApp/Persistence/Schema/MigrationPlan.swift` | VERIFIED | `schemas` ends with `SchemaV7.self`; `stages` ends with `v6ToV7`; `v6ToV7` is `.custom(willMigrate: nil, didMigrate: nil)` |
| `MyHomeApp/Persistence/ModelContainer+App.swift` | VERIFIED | `Schema(versionedSchema: SchemaV7.self)` (one declaration, reused for both `ModelConfiguration` and `ModelContainer`); 0 `SchemaV6` references |
| `MyHomeApp/Support/AMFINavService.swift` | VERIFIED | `@MainActor @Observable final class`; `parseNAVAll` with section-header skip, `parts.count >= 6`, `Decimal(string:)` guard; HTTPS only (`https://portal.amfiindia.com/spages/NAVAll.txt`); 0 `http://` occurrences; `isFetching` re-entrancy guard in both `refreshIfNeeded()` and `forceRefresh()` (WR-02 fix) |
| `MyHomeApp/Support/NetWorthCalculator.swift` | VERIFIED | Pure `enum NetWorthCalculator` with `static func breakdown(...)`; calls `AccountBalance.compute()` — never re-implements balance formula (T-11-07); all Decimal |
| `MyHomeApp/Support/NetWorthSnapshotService.swift` | VERIFIED | `@MainActor @Observable final class`; `performUpsert` uses bounded `[todayIST, tomorrowIST)` predicate (CR-01 fix); fetch-before-insert; defensive duplicate deletion; WR-04 documented as intentionally unconditional |
| `MyHomeApp/Features/Assets/AssetsListView.swift` | VERIFIED | 178 lines; `@Query` + `.insetGrouped` list; `StalenessView` per row; `.refreshable { amfiNavService.forceRefresh() }`; `.confirmationDialog("Delete Holding?", ...)` + `context.delete + context.save` |
| `MyHomeApp/Features/Assets/EditAssetView.swift` | VERIFIED | `isValid` + `saveAsset` both enforce `units > 0, abs(units) < 1_000_000` and `costBasisPerUnit >= 0, abs(...) < 1_000_000_000` (WR-01 fix); `amfiSchemeCode = nil` for non-MF; plain `Text()` only |
| `MyHomeApp/Features/Assets/AMFISchemePickerView.swift` | VERIFIED | `.searchable`; "Fetch Now" calls `forceRefresh()`; 4 states (loaded/empty/fetching/failed) |
| `MyHomeApp/Features/Assets/StalenessView.swift` | VERIFIED | `AssetValuation.isStale` uses `TimeZone(identifier: "Asia/Kolkata")`; threshold `> 1`; `EmptyView` when fresh or nil |
| `MyHomeApp/Features/Assets/AssetDetailView.swift` | VERIFIED | Reuses `AssetValuation` (no re-derived math); gain text has explicit "+"/"-" prefix; "—" for nil percent; AMFI Scheme Code row only for `mutual_fund`; "as of {date}" / "price not set" |
| `MyHomeApp/Features/Assets/NetWorthCard.swift` | VERIFIED | `allocationSegments` clamps via `max(v, 0)` and `NSDecimalNumber`; `NavigationLink(destination: AssetsListView())`; true total in center (not clamped); `DonutChart` + legend + `NetWorthTrendChart` |
| `MyHomeApp/Features/Assets/NetWorthTrendChart.swift` | VERIFIED | `AreaMark + LineMark`; `NSDecimalNumber(decimal: snap.totalNetWorth).doubleValue` at boundary (T-11-13); "No history yet." empty state at height 80; `.frame(height: 140)` |
| `MyHomeApp/Features/Overview/OverviewView.swift` | VERIFIED | `@Query` for `allAssets`, `netWorthSnapshots`, `allAccounts`; `showNetWorth = !allAssets.isEmpty || netWorthBreakdown.cashValue != 0`; `if showNetWorth { sectionHeader("Net Worth") + NetWorthCard(...) }` |
| `MyHomeApp/Features/Settings/SettingsView.swift` | VERIFIED | `NavigationLink(destination: AssetsListView())` at line 203 in the Data section |

---

### Key Link Verification

| From | To | Via | Status | Details |
|------|----|-----|--------|---------|
| `MigrationPlan.swift` | `SchemaV7.self` | `schemas` + `stages` arrays | WIRED | `schemas` ends with `SchemaV7.self`; `v6ToV7 = MigrationStage.custom(fromVersion: SchemaV6.self, toVersion: SchemaV7.self, ...)` |
| `ModelContainer+App.swift` | `SchemaV7.self` | `Schema(versionedSchema:)` | WIRED | Line 18: `Schema(versionedSchema: SchemaV7.self)`; reused for both `ModelConfiguration` and `ModelContainer(for:)` |
| `RootView.swift` | `amfiNavService.refreshIfNeeded()` + `netWorthSnapshotService.upsertIfNeeded()` | `scenePhase .active onChange` | WIRED | Lines 129-130; both services also receive `modelContext` injection in `.onAppear` (lines 100-101) |
| `RootView.swift` | `AMFINavService` | `.environment(amfiNavService)` | WIRED | Line 140: `.environment(amfiNavService)`; consumed by `@Environment(AMFINavService.self)` in `AssetsListView` and `EditAssetView` |
| `SettingsView.swift` | `AssetsListView` | `NavigationLink` in Data section | WIRED | Line 203 |
| `EditAssetView.swift` | `AMFISchemePickerView` | scheme row `NavigationLink`, binds `amfiSchemeCode` | WIRED | Lines 82-103; `$amfiSchemeCode` binding passed to picker |
| `AssetsListView.swift` | `amfiNavService.forceRefresh()` | `.refreshable` | WIRED | Line 57-59 |
| `NetWorthSnapshotService.swift` | `AccountBalance.compute` | `NetWorthCalculator.breakdown` | WIRED | `NetWorthCalculator.swift` line 54: `cash += AccountBalance.compute(baseline:asOf:expenses:accountID:)` |
| `OverviewView.swift` | `NetWorthCard` | conditional `if showNetWorth` in `OverviewMonthContent.body` | WIRED | Lines 181-190 |
| `NetWorthCard.swift` | `DonutChart` | `allocationSegments` with `max(cashValue, 0)` clamp | WIRED | Lines 32-37, 129-138 |
| `NetWorthCard.swift` | `AssetsListView` | card-tap `NavigationLink(destination: AssetsListView())` | WIRED | Line 39 |

---

### Data-Flow Trace (Level 4)

| Artifact | Data Variable | Source | Produces Real Data | Status |
|----------|---------------|--------|--------------------|--------|
| `NetWorthCard` | `breakdown` (mf/stock/nps/cash/total) | `NetWorthCalculator.breakdown(allAssets, allAccounts, allGlobalExpenses)` from `OverviewMonthContent` `@Query` arrays | Yes — iterates `Asset.units × currentNAV`; calls `AccountBalance.compute(baseline:asOf:expenses:accountID:)` for each account | FLOWING |
| `NetWorthTrendChart` | `snapshots` (`[NetWorthSnapshot]`) | `@Query(sort: \NetWorthSnapshot.date, order: .reverse)` in `OverviewMonthContent`; rows inserted by `NetWorthSnapshotService.performUpsert` | Yes — real SwiftData fetch; empty array renders "No history yet." | FLOWING |
| `AssetsListView.holdingRow` | `currentValue` | `asset.units * asset.currentNAV` from `@Query` live `Asset` rows; `currentNAV` updated by `AMFINavService.performFetch` or manual edit | Yes — live SwiftData query; "—" shown when NAV nil | FLOWING |
| `StalenessView` | `isStale` | `AssetValuation.isStale(navAsOfDate: asset.navAsOfDate)` with live `Date()` reference | Yes — computed from persisted `Asset.navAsOfDate` | FLOWING |

---

### Behavioral Spot-Checks

Step 7b: SKIPPED (iOS SwiftUI/SwiftData app — no runnable CLI entry points; requires simulator).
Both human-verify checkpoints (11-03 Holdings CRUD flow, 11-04 Overview net-worth card) were approved by the user and are treated as satisfying the behavioral checks for those flows.

---

### Probe Execution

No probe scripts declared for this phase (no `scripts/*/tests/probe-*.sh`). SKIPPED.

---

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|-------------|-------------|-------------|--------|----------|
| ASSET-01 | 11-01, 11-03 | Add/edit/delete holdings across MF/stock/NPS | SATISFIED | `AssetsListView` CRUD + `EditAssetView`; swipe-delete + `confirmationDialog`; Settings entry row |
| ASSET-02 | 11-01, 11-03 | Record units + cost basis; current value derived | SATISFIED | `Asset` @Model fields; `AssetValuation.currentValue` = `units × currentNAV`; `AssetValueTests` green |
| ASSET-03 | 11-02 | MF NAV auto-refreshes from AMFI best-effort | SATISFIED | `AMFINavService.refreshIfNeeded()` IST-gated; `performFetch` in `Task {}`; silent catch; forceRefresh for pull-to-refresh |
| ASSET-04 | 11-01, 11-03 | Stock/NPS valued by manual entry | SATISFIED | "Current price" label; no scheme picker for non-MF; `amfiSchemeCode = nil` on save |
| ASSET-05 | 11-02, 11-04 | Total net worth = holdings + account balances | SATISFIED | `NetWorthCalculator.breakdown(assets:accounts:expenses:)` reuses `AccountBalance.compute`; total displayed in `NetWorthCard` |
| ASSET-06 | 11-03 | Per-holding gain/loss (absolute + %) against cost basis | SATISFIED | `AssetValuation.absoluteGain/percentGain`; `AssetDetailView` renders with +/- prefix + green/red; "—" for zero-cost |
| ASSET-07 | 11-04 | Asset-allocation donut chart (net worth by class) | SATISFIED | `NetWorthCard.allocationSegments` → 4 `DonutSegment`s; negative-cash clamped; `AllocationSegmentTests` green |
| ASSET-08 | 11-01, 11-02, 11-04 | Net worth snapshots over time with trend chart | SATISFIED | `NetWorthSnapshotService` upserts daily; `NetWorthTrendChart` renders `AreaMark + LineMark`; `NetWorthSnapshotTests` green |
| ASSET-09 | 11-03 | As-of date + staleness indicator on prices | SATISFIED | `StalenessView` badge; `AssetDetailView` "as of {date}" / "price not set"; threshold > 1 IST calendar day; `StalenessBadgeTests` green |

All 9 requirements are satisfied. The REQUIREMENTS.md traceability table still shows "Pending" — that table is not updated by this phase (it is a human-update step at milestone close, not blocking verification).

---

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
|------|------|---------|----------|--------|
| `ModelContainer+App.swift` | 15, 28 | `TODO: migrate to App Group URL when paid account active` | Info | Pre-existing TODOs from Phase 9 referencing a known future upgrade; not introduced by Phase 11; no phase 11 work depends on this path |
| `EditAssetView.swift` | 210 | `try? context.save()` in delete path (WR-03) | Warning | Remaining from review — swallows save errors silently in the Danger Zone delete; `AssetsListView.deleteAsset` uses `assertionFailure` consistently. WR-03 was flagged as a warning (not critical) in the code review and was not in the set of items fixed post-review. Low real-world risk (SwiftData deletes rarely fail). |

**Debt-marker gate:** The two `TODO:` lines in `ModelContainer+App.swift` pre-date Phase 11 (they were introduced in Phase 9) and are not introduced by Phase 11's files. They reference a known future upgrade path (paid Apple Developer account) — no formal issue number required given they are in the pre-existing file, not in Phase 11's new files. No TBD/FIXME/XXX markers are present in Phase 11 source files.

**WR-03 assessment:** `try? context.save()` on the delete path is a warning-level inconsistency. The delete operation itself (`context.delete(a)`) is already staged before the save; a save failure means the deletion is not persisted but the sheet dismisses. This is not a data-loss path for assets the user just created — it only matters if SwiftData fails to flush, which is rare. The phase goal is not blocked by this. Carrying forward from review as an open warning.

---

### Human Verification Required

Both human-verify checkpoints were already approved by the user prior to this verification run:

- **11-03 checkpoint:** Holdings CRUD under Settings > Assets — add/edit/delete MF/stock/NPS, AMFI scheme picker, per-holding detail, pull-to-refresh — **approved**
- **11-04 checkpoint:** Overview net-worth card — total + donut + legend + trend, suppression when no data, tap navigation, negative-net rendering — **approved**

No additional human verification is required.

---

### Gaps Summary

No blocking gaps. All 9 ASSET requirements are implemented and wired in the codebase. The four review-identified blockers/correctness warnings (CR-01, WR-01, WR-02, WR-04) are confirmed fixed in the committed code. The remaining open items (WR-03, WR-05, WR-06, WR-07, IN-01 through IN-05) are warnings or info items that do not block the phase goal.

The only open warning in Phase 11 files is WR-03 (`try? context.save()` in the EditAssetView Danger Zone delete path). This is a pre-existing inconsistency carried forward from the code review as a known non-critical issue.

---

_Verified: 2026-06-11_
_Verifier: Claude (gsd-verifier)_
