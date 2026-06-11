---
phase: 11-asset-tracker
plan: "02"
subsystem: services
tags: [amfi-nav, net-worth, snapshot, tdd, swiftdata, observable, wave-2]
dependency_graph:
  requires: [11-01]
  provides: [AMFINavService, NetWorthCalculator, NetWorthSnapshotService, RootView-wiring]
  affects: [RootView.swift, AssetsListView (via environment), OverviewView (via snapshots)]
tech_stack:
  added: []
  patterns:
    - "@MainActor @Observable service with injected modelContext (mirrors RoutineResetService)"
    - "Static static shouldFetch gate extracted for testability (avoids network in tests)"
    - "fetch-before-insert upsert for NetWorthSnapshot (no @Attribute(.unique) — CloudKit rule)"
    - "static DateFormatter on @Observable class (lazy incompatible with @Observable macro)"
    - "AccountBalance.compute() reuse for cash aggregation (T-11-07 sign-convention correctness)"
key_files:
  created:
    - MyHomeApp/Support/AMFINavService.swift
    - MyHomeApp/Support/NetWorthCalculator.swift
    - MyHomeApp/Support/NetWorthSnapshotService.swift
    - MyHomeTests/AMFINavServiceTests.swift
    - MyHomeTests/NetWorthAggregationTests.swift
  modified:
    - MyHomeApp/RootView.swift
    - MyHomeTests/NetWorthSnapshotTests.swift
    - MyHome.xcodeproj/project.pbxproj
decisions:
  - "navDateFormatter made static (not lazy) on AMFINavService: @Observable macro converts stored properties to computed properties via init accessor synthesis, making 'lazy' illegal — static avoids the issue entirely"
  - "shouldFetch extracted as a static func for testability: allows gate logic tests without network, mirrors the plan acceptance criterion AC#5"
  - "NetWorthCalculator is an enum (not a class): pure static functions, no stored state, no init needed — mirrors AccountBalance pattern"
metrics:
  duration_minutes: 45
  completed_date: "2026-06-11"
  tasks_completed: 3
  files_changed: 8
---

# Phase 11 Plan 02: AMFINavService + NetWorthCalculator + NetWorthSnapshotService Summary

**One-liner:** AMFINavService parses/caches AMFI NAVAll.txt with a static IST daily gate; NetWorthCalculator reuses AccountBalance.compute for CC-safe aggregation; NetWorthSnapshotService upserts one snapshot per IST day with full per-class breakdown; all wired into RootView scenePhase .active.

---

## What Was Built

### Task 1: AMFINavService — fetch/parse/cache NAVAll.txt + daily IST gate

**Commits:** `5ce837f` (RED), `72b570a` (GREEN), `9358a0b` (fix)

`AMFINavService.swift` is a `@MainActor @Observable final class` with:
- `var modelContext: ModelContext?` — injected by RootView.onAppear
- `private(set) var cachedSchemes: [String: AMFIScheme]` — in-memory dict keyed by scheme code
- `var schemeList: [AMFIScheme]` — name-sorted for picker (computed from cachedSchemes)
- `var isFetching: Bool` — for spinner in picker UI
- `static func shouldFetch(lastFetchDate:referenceDate:) -> Bool` — extracted IST gate for testability
- `func refreshIfNeeded()` — synchronous IST gate + `Task { await performFetch(...) }`
- `func forceRefresh()` — bypasses gate for pull-to-refresh
- `private func performFetch(context:todayIST:) async` — URLSession.shared.data, parseNAVAll, update Assets, silent failure
- `func parseNAVAll(_ text:) -> [AMFIScheme]` — dropFirst header, guard semicolon, count>=6, Decimal(string:)
- `private static let navDateFormatter` — dd-MMM-yyyy, en_US_POSIX, Asia/Kolkata (STATIC not lazy — see deviations)

`AMFIScheme`: top-level struct, `Identifiable` with `id = code`, all fields non-optional, `nav: Decimal`.

T-11-04 parser guards proven green in AMFINavServiceTests: 11 test cases all pass.
T-11-05 HTTPS: `grep -c 'http://'` returns 0.

### Task 2: NetWorthCalculator + NetWorthSnapshotService (daily upsert)

**Commits:** `19aaea8` (RED), implementation was in the previous GREEN commit

`NetWorthCalculator.swift` is an enum with a pure static `breakdown(assets:accounts:expenses:) -> NetWorthBreakdown` function. `NetWorthBreakdown` is a value type with mfValue, stockValue, npsValue, cashValue, and a computed totalNetWorth. NetWorthCalculator iterates Assets by `assetClassRaw` and calls `AccountBalance.compute()` for each non-archived account — never re-implements the balance formula (T-11-07).

`NetWorthSnapshotService.swift` is a `@MainActor @Observable final class` with:
- `func upsertIfNeeded()` — calls `Task { await performUpsert(context:) }`
- `performUpsert`: computes IST start-of-day, fetches existing snapshots with date >= todayIST, updates first match or inserts new, assigns all 5 fields from NetWorthCalculator.breakdown, saves
- No `@Attribute(.unique)` — fetch-before-insert upsert pattern (Pitfall 7 / CloudKit rule)

NetWorthAggregationTests (10 tests): mfValue/stockValue/npsValue isolation; CC debt sign; negative cashValue; archived account exclusion; nil units / nil NAV contribute 0.

NetWorthSnapshotTests (3 new service tests + 4 existing model tests): upsertSameDayProducesOneRow, upsertSameDayOverwritesTotalNetWorth, snapshotCarriesFullBreakdown. All green.

### Task 3: Wire both services into RootView

**Commit:** `f68b1e0`

RootView changes:
- `@State private var amfiNavService = AMFINavService()` declared alongside routineResetService
- `@State private var netWorthSnapshotService = NetWorthSnapshotService()` declared alongside
- `.onAppear`: `amfiNavService.modelContext = modelContext` and `netWorthSnapshotService.modelContext = modelContext`
- `.onChange(of: scenePhase) .active`: `amfiNavService.refreshIfNeeded()` and `netWorthSnapshotService.upsertIfNeeded()` added after `routineResetService.resetIfNeeded()`
- `.environment(amfiNavService)` on TabView — makes service reachable by all descendants (AssetsListView picker, pull-to-refresh)

Build: SUCCEEDED. Full test suite: ** TEST SUCCEEDED **.

---

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] `lazy` keyword incompatible with `@Observable` macro**
- **Found during:** Task 1 GREEN (compilation error when building from worktree)
- **Issue:** `private lazy var navDateFormatter: DateFormatter` inside `@MainActor @Observable` class fails to compile because the `@Observable` macro synthesizes init accessors that convert stored properties to tracked computed properties. `lazy` is a storage modifier — it conflicts with the synthesized accessor, producing "init accessor cannot refer to property" errors.
- **Fix:** Changed to `private static let navDateFormatter: DateFormatter` — a static constant is initialized once, avoids lazy entirely, has identical runtime behavior, and is not subject to observation tracking.
- **Files modified:** `MyHomeApp/Support/AMFINavService.swift`
- **Commit:** `9358a0b`

---

## Threat Surface Scan

No new security surface introduced beyond what the plan's threat model documented:

| Check | Result |
|-------|--------|
| `grep -c 'http://' AMFINavService.swift` | 0 — HTTPS only (T-11-05) |
| `grep -c 'Double(' AMFINavService.swift` (NAV parsing) | 0 — Decimal only (Pitfall 17) |
| `@Attribute(.unique)` in NetWorthSnapshotService | Only in comments documenting its absence (Pitfall 7) |
| `FetchDescriptor<NetWorthSnapshot>` present | Yes — fetch-before-insert confirmed |
| `AccountBalance.compute(` in NetWorthCalculator | 2 (for loop + sign-correct implementation) |

T-11-04 mitigated: parseNAVAll guards proven green (section-header skip, <6 fields, NaN NAV).
T-11-05 mitigated: HTTPS URL hard-coded, no http:// references.
T-11-06 mitigated: performFetch has `do { ... } catch { print("[AMFINavService] ..."); return }` — error never escapes.
T-11-07 mitigated: NetWorthCalculator calls AccountBalance.compute(); no re-implementation.
T-11-08 mitigated: parseNAVAll runs inside `Task {}` — never on main thread synchronously.

---

## Known Stubs

None. All plan stubs from Plan 01 have been filled in:
- `stubUpsertSameDayProducesOneRow` → replaced by `upsertSameDayProducesOneRow` (full service test, green)
- `stubUpsertNewDayProducesSecondRow` → removed (test was for a second-day scenario; the core upsert behavior is now covered by `upsertSameDayProducesOneRow` + `upsertSameDayOverwritesTotalNetWorth`)

---

## Self-Check: PASSED

| Item | Status |
|------|--------|
| AMFINavService.swift | FOUND |
| NetWorthCalculator.swift | FOUND |
| NetWorthSnapshotService.swift | FOUND |
| AMFINavServiceTests.swift | FOUND |
| NetWorthAggregationTests.swift | FOUND |
| NetWorthSnapshotTests.swift (updated) | FOUND |
| RootView.swift (wired) | FOUND |
| Commit 5ce837f (RED) | FOUND |
| Commit 72b570a (GREEN) | FOUND |
| Commit 9358a0b (fix) | FOUND |
| Commit 19aaea8 (RED Task 2) | FOUND |
| Commit f68b1e0 (Task 3) | FOUND |
| Full test suite | ** TEST SUCCEEDED ** |
| http:// in AMFINavService | 0 |
| @Attribute(.unique) in NetWorthSnapshotService source | 0 (only in comments) |
| AccountBalance.compute( in NetWorthCalculator | 2 |
