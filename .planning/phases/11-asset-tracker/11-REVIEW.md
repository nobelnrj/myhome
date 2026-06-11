---
phase: 11-asset-tracker
reviewed: 2026-06-11T00:00:00Z
depth: standard
files_reviewed: 23
files_reviewed_list:
  - MyHomeApp/Features/Assets/AMFISchemePickerView.swift
  - MyHomeApp/Features/Assets/AssetDetailView.swift
  - MyHomeApp/Features/Assets/AssetsListView.swift
  - MyHomeApp/Features/Assets/EditAssetView.swift
  - MyHomeApp/Features/Assets/NetWorthCard.swift
  - MyHomeApp/Features/Assets/NetWorthTrendChart.swift
  - MyHomeApp/Features/Assets/StalenessView.swift
  - MyHomeApp/Features/Overview/OverviewView.swift
  - MyHomeApp/Features/Settings/SettingsView.swift
  - MyHomeApp/Persistence/ModelContainer+App.swift
  - MyHomeApp/Persistence/Models/Asset.swift
  - MyHomeApp/Persistence/Models/NetWorthSnapshot.swift
  - MyHomeApp/Persistence/Schema/MigrationPlan.swift
  - MyHomeApp/Persistence/Schema/SchemaV7.swift
  - MyHomeApp/RootView.swift
  - MyHomeApp/Support/AMFINavService.swift
  - MyHomeApp/Support/NetWorthCalculator.swift
  - MyHomeApp/Support/NetWorthSnapshotService.swift
  - MyHomeTests/AMFINavServiceTests.swift
  - MyHomeTests/AllocationSegmentTests.swift
  - MyHomeTests/AssetGainLossTests.swift
  - MyHomeTests/NetWorthAggregationTests.swift
  - MyHomeTests/StalenessBadgeTests.swift
findings:
  critical: 1
  warning: 7
  info: 5
  total: 13
status: issues_found
---

# Phase 11: Code Review Report

**Reviewed:** 2026-06-11
**Depth:** standard
**Files Reviewed:** 23
**Status:** issues_found

## Summary

Reviewed the Phase 11 Asset Tracker implementation: holdings CRUD, AMFI NAV fetch/parse, net-worth aggregation, allocation donut, trend chart, and staleness. The code is generally well-structured and the threat mitigations called out in the plan (T-11-10 plain-Text rendering, T-11-11 divide-by-zero guard, T-11-12 negative-cash clamp, T-11-13 Decimal→Double conversion, Decimal money handling) are correctly implemented. SchemaV7 follows the CloudKit-readiness rules (all stored props optional/defaulted, no `@Attribute(.unique)`, Decimal for money) and the v6→v7 migration is correctly additive.

The most serious issue is a correctness bug in the daily net-worth snapshot upsert predicate, which can pick the wrong row and silently corrupt a prior day's snapshot. Several warnings concern incomplete input-validation bounds (threat T-11-09 is only partially enforced), an unbounded snapshot query, and a concurrency gap that allows overlapping AMFI fetches.

## Critical Issues

### CR-01: Snapshot upsert predicate `date >= todayIST` is unbounded and can overwrite the wrong day's snapshot

**File:** `MyHomeApp/Support/NetWorthSnapshotService.swift:47-59`
**Issue:** The upsert fetches existing snapshots with `#Predicate { $0.date >= todayIST }`. This has two defects:

1. **No upper bound.** The predicate matches today's snapshot *and any future-dated snapshot*. If a future-dated row exists (e.g. the device clock was advanced and later corrected, or a CloudKit sync brings down a row stamped on a device in a later IST day), the fetch returns that future row. The code then does `snapshot.date = todayIST` and overwrites it — silently clobbering the future day's totals and stamping it with today's date. With CloudKit enabled later (the schema is explicitly CloudKit-ready), cross-device clock skew makes this realistic.

2. **`existing.first` on an unsorted fetch is non-deterministic.** When more than one row satisfies the predicate (e.g. multiple future rows, or a duplicate already present), `FetchDescriptor` has no sort, so which row is mutated is undefined. The "idempotent overwrite — never produces duplicates" guarantee in the doc comment does not hold: it can mutate an *arbitrary* matching row rather than today's, and leave a genuine duplicate of today untouched.

The intent (find *today's* snapshot only) requires a bounded range. The upsert key is start-of-day IST, so the correct predicate is `date == todayIST` (the value is deterministic) or a `[todayIST, tomorrowIST)` half-open range.

**Fix:**
```swift
let tomorrowIST = cal.date(byAdding: .day, value: 1, to: todayIST)!
let existing = try context.fetch(
    FetchDescriptor<NetWorthSnapshot>(
        predicate: #Predicate { $0.date >= todayIST && $0.date < tomorrowIST }
    )
)
// Defensive: if multiple today-rows somehow exist, keep the first and delete the rest
let snapshot: NetWorthSnapshot
if let first = existing.first {
    snapshot = first
    for dup in existing.dropFirst() { context.delete(dup) }
} else {
    let s = NetWorthSnapshot()
    context.insert(s)
    snapshot = s
}
```

## Warnings

### WR-01: T-11-09 lower/upper bounds are incomplete — units = 0.0001 and huge cost pass, negative values accepted in `saveAsset`

**File:** `MyHomeApp/Features/Assets/EditAssetView.swift:45-50, 222-236`
**Issue:** The validation story is inconsistent between `isValid` (gates the Save button) and `saveAsset` (the actual guard), and neither fully enforces the documented threat bound:

- `isValid` requires `units > 0` but `saveAsset` only checks `abs(units) < 1_000_000`. If the Save button is somehow triggered with `units <= 0` (e.g. programmatic, or future refactor), `saveAsset` would persist a zero/negative holding because its own guard uses `abs(units)` and never re-checks `> 0`. The two code paths disagree on what "valid" means.
- There is no *lower* bound or upper bound on `costBasisPerUnit` other than `< 1_000_000_000`; a negative cost basis (`-500`) passes `abs(...) < 1e9` and is saved, producing nonsensical negative `totalCost` and inverted gain/loss.
- `units` upper bound is exclusive `< 1_000_000` but there is no minimum-precision floor; this is acceptable, but the asymmetry with the `> 0` check living only in `isValid` is the real risk.

**Fix:** Make `saveAsset` the single source of truth and re-assert every bound there, including positivity:
```swift
guard units > 0, abs(units) < 1_000_000 else {
    nameError = "Units must be greater than 0 and less than 1,000,000."
    return
}
guard costBasisPerUnit >= 0, abs(costBasisPerUnit) < 1_000_000_000 else {
    nameError = "Cost per unit must be between ₹0 and ₹1,00,00,00,000."
    return
}
```
Also guard `currentNAV >= 0` before persisting it.

### WR-02: AMFI fetch has no in-flight guard — `forceRefresh()` can launch overlapping fetches

**File:** `MyHomeApp/Support/AMFINavService.swift:84-106`
**Issue:** `forceRefresh()` is wired to pull-to-refresh (`AssetsListView.refreshable`) and the picker "Fetch Now" button (`AMFISchemePickerView`). Neither `forceRefresh()` nor `refreshIfNeeded()` checks `isFetching` before spawning a new `Task { await performFetch(...) }`. Rapid pull-to-refresh, or tapping "Fetch Now" while a scene-phase refresh is already running, launches multiple concurrent `performFetch` tasks. Each rebuilds `cachedSchemes` and writes `Asset.currentNAV` / calls `context.save()`. Two overlapping saves on the main context, plus the `defer { isFetching = false }` from the first task clearing the flag while the second is still running, leave the UI spinner state inconsistent and double the network/parse work. `isFetching` is set *before* the Task but never consulted as a re-entrancy guard.

**Fix:**
```swift
func forceRefresh() {
    guard let context = modelContext, !isFetching else { return }
    ...
}
// and in refreshIfNeeded(), add `!isFetching` to the early-return guards
```

### WR-03: `EditAssetView` delete path swallows save errors silently while the list path asserts

**File:** `MyHomeApp/Features/Assets/EditAssetView.swift:208-213`
**Issue:** The Danger-Zone delete uses `try? context.save()` and then `dismiss()` unconditionally. If the save throws, the error is discarded, the sheet dismisses, and the user believes the holding was deleted when it may not have been persisted. This is inconsistent with `AssetsListView.deleteAsset` (line 170-177) and `saveAsset` (line 259-261), which both surface the failure via `assertionFailure`. Inconsistent error handling for the same operation is a maintainability and correctness hazard.

**Fix:**
```swift
context.delete(a)
do {
    try context.save()
    dismiss()
} catch {
    assertionFailure("Failed to delete asset: \(error)")
}
```

### WR-04: `NetWorthSnapshotService.upsertIfNeeded()` has no IST daily gate despite the doc claim

**File:** `MyHomeApp/Support/NetWorthSnapshotService.swift:33-36`
**Issue:** The type doc comment states "`upsertIfNeeded()` is synchronous (IST gate) + wraps compute/persist in `Task {}`", and RootView calls it on every `.active` scene phase alongside `amfiNavService.refreshIfNeeded()` (which *does* gate). But `upsertIfNeeded()` contains no gate at all — it unconditionally spawns `performUpsert` on every foreground. While the upsert is idempotent for *today*, this means a full fetch of all assets, accounts, and expenses plus a `context.save()` runs on every single app foregrounding, not once per IST day as documented. Combined with CR-01's predicate bug, every needless run is also an opportunity to mutate the wrong row. The behavior contradicts the documented contract.

**Fix:** Add the same IST last-run gate used by `AMFINavService` (a `UserDefaults` date key + `shouldFetch`-style comparison), or document explicitly that the upsert is intentionally unconditional and remove the "(IST gate)" claim. Preferred: gate it to match the stated design.

### WR-05: `formattedPercent` rounds via `Double` — defeats the Decimal-money guarantee at the display boundary

**File:** `MyHomeApp/Features/Assets/AssetDetailView.swift:202-211`
**Issue:** `percentGain` is computed as an exact `Decimal`, then `formattedPercent` converts it to `Double` via `NSDecimalNumber(...).doubleValue` and formats with `String(format: "%.2f", ...)`. For a percentage this is cosmetically tolerable, but it reintroduces binary-floating-point rounding at the boundary the rest of the module carefully avoids, and `String(format:)` uses the current C locale rather than the user's locale (no thousands/decimal localization). A percent like `33.335` may round inconsistently. Lower severity because it is display-only and not a money total, but it is an inconsistency with the module's stated Decimal discipline.

**Fix:** Format the `Decimal` directly with a `NumberFormatter` (style `.percent` or `.decimal`, `maximumFractionDigits = 2`, `roundingMode = .halfUp`) so rounding and locale are deterministic, instead of routing through `Double` + `String(format:)`.

### WR-06: `print()` of raw fetch/parse errors leaks failure details to the console in shipping builds

**File:** `MyHomeApp/Support/AMFINavService.swift:117, 149`; `MyHomeApp/Support/NetWorthSnapshotService.swift:79`
**Issue:** The silent-failure pattern (D-07, T-11-06) is correctly chosen, but the implementation uses bare `print(...)` of the full `error`. `print` is not stripped in release builds and writes to the device console/unified log, which is readable via Console.app and sysdiagnose. For a network error this is low-risk, but it is an inconsistent logging practice and can surface URLs, server messages, or SwiftData internals. The codebase elsewhere appears to standardize on a logging abstraction.

**Fix:** Route through `os.Logger` at `.debug`/`.error` level (which respects privacy redaction and log levels), e.g. `Logger(subsystem: ..., category: "amfi").error("fetch failed: \(error, privacy: .public)")`, or wrap in `#if DEBUG`.

### WR-07: `OverviewView` net-worth suppression recomputes the full breakdown twice per render

**File:** `MyHomeApp/Features/Overview/OverviewView.swift:154-157, 183-188`
**Issue:** `OverviewMonthContent.body` calls `NetWorthCalculator.breakdown(...)` at line 154 only to read `cashValue` for the `showNetWorth` flag, then `NetWorthCard` (line 183) recomputes the identical `breakdown` internally in its own `body` (NetWorthCard.swift:27). The aggregation — which fetches/iterates all assets, all accounts, and `AccountBalance.compute` over every expense per account — runs twice on every Overview render. This is flagged as a correctness-adjacent maintainability concern (not pure perf): the two call sites can silently diverge if one is later changed, and the duplicated suppression logic is easy to get out of sync with the card's own rendering. (Pure performance is out of v1 scope, noted here only for the divergence risk.)

**Fix:** Compute the breakdown once in `OverviewMonthContent` and pass it into `NetWorthCard` as a parameter, so suppression and rendering share a single source of truth.

## Info

### IN-01: `AssetsListView.holdingRow` force-unwraps `nav!` after a nil check on a separate binding

**File:** `MyHomeApp/Features/Assets/AssetsListView.swift:96-97`
**Issue:** `let currentValue: Decimal? = nav != nil ? units * nav! : nil` uses a force-unwrap guarded by a ternary. It is currently safe, but force-unwrap-after-ternary is a fragile pattern that a future edit can break.
**Fix:** `let currentValue = asset.currentNAV.map { units * $0 }`

### IN-02: `AssetDetailView.formattedAbsoluteGain` has two identical branches

**File:** `MyHomeApp/Features/Assets/AssetDetailView.swift:191-200`
**Issue:** The `else if absoluteGain < 0` and `else` branches both `return absoluteGain.formattedINRWhole()` — dead branching. The whole function reduces to: prefix `+` when positive, otherwise return the formatted value as-is.
**Fix:**
```swift
private var formattedAbsoluteGain: String {
    absoluteGain > 0 ? "+\(absoluteGain.formattedINRWhole())" : absoluteGain.formattedINRWhole()
}
```

### IN-03: Stale doc comments on `Asset.swift` reference SchemaV6/Phase 9

**File:** `MyHomeApp/Persistence/Models/Asset.swift:3-17`
**Issue:** The typealias is now `SchemaV7.Asset` but the comment body still says "scaffold only in Phase 9", "production container is built with `Schema(versionedSchema: SchemaV6.self)`", and "MUST use SchemaV6.Asset". This contradicts the actual `SchemaV7` typealias and ModelContainer+App.swift:18. Misleading for the next maintainer applying the STAB-08 typealias-flip rule.
**Fix:** Update the comment to reference SchemaV7 / Phase 11 to match the typealias.

### IN-04: `MigrationPlan.swift` header comment only documents up to v3

**File:** `MyHomeApp/Persistence/Schema/MigrationPlan.swift:4-8`
**Issue:** The enum doc comment describes v1→v2→v3 only and stops; v4 through v7 stages are undocumented in the header. Low impact, but the header no longer reflects the seven-version chain it manages.
**Fix:** Extend the header summary to mention v4–v7 (or replace with "see individual MigrationStage declarations below").

### IN-05: `StalenessView.isStale` uses live `Date()` and cannot be previewed/tested deterministically

**File:** `MyHomeApp/Features/Assets/StalenessView.swift:77-79`
**Issue:** The view's computed `isStale` calls `AssetValuation.isStale(navAsOfDate:)` with the default `referenceDate: Date()`. The pure helper is fully tested with injected dates (StalenessBadgeTests), but the View itself has no seam to inject a reference date, so SwiftUI previews and snapshot tests around the badge are time-dependent. Minor.
**Fix:** Optionally expose a `referenceDate: Date = Date()` parameter on `StalenessView` for previews/tests; not required for production correctness.

---

_Reviewed: 2026-06-11_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
