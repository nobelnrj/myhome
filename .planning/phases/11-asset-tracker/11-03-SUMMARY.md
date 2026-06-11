---
phase: 11-asset-tracker
plan: "03"
subsystem: ui-assets
tags: [holdings-crud, swiftui, amfi-picker, staleness, gain-loss, tdd, wave-3]
dependency_graph:
  requires: [11-01, 11-02]
  provides: [AssetsListView, EditAssetView, AMFISchemePickerView, AssetDetailView, StalenessView, AssetValuation]
  affects: [SettingsView, RootView (via AMFINavService env), AssetsListView (pull-to-refresh)]
tech_stack:
  added: []
  patterns:
    - "AssetValuation enum (static funcs) mirrors AccountBalance enum — pure logic, no @Model dependency"
    - "EditAssetView isValid with double-guarded bounds (mirrors EditAccountView T-09-05 pattern)"
    - "AMFISchemePickerView 4-state pattern (loaded/pre-fetch/fetching/failed) — no analog in Accounts"
    - "StalenessView: Calendar(identifier:.gregorian) + timeZone Asia/Kolkata + startOfDay(for:) boundary"
    - "@Environment(AMFINavService.self) injection from RootView (Plan 02 wiring)"
key_files:
  created:
    - MyHomeApp/Features/Assets/StalenessView.swift
    - MyHomeApp/Features/Assets/AssetsListView.swift
    - MyHomeApp/Features/Assets/EditAssetView.swift
    - MyHomeApp/Features/Assets/AMFISchemePickerView.swift
    - MyHomeApp/Features/Assets/AssetDetailView.swift
    - MyHomeTests/StalenessBadgeTests.swift
    - MyHomeTests/AssetGainLossTests.swift
  modified:
    - MyHomeApp/Features/Settings/SettingsView.swift
    - MyHome.xcodeproj/project.pbxproj
decisions:
  - "AssetValuation is an enum (not a struct/class): pure static functions, no stored state, mirrors AccountBalance and NetWorthCalculator patterns"
  - "StalenessView.isStale(navAsOfDate:referenceDate:) takes explicit referenceDate for testability — production callers omit it (defaults to Date()); tests inject a fixed 2026-06-11 UTC anchor"
  - "AMFISchemePickerView State D (failed) reuses State B ContentUnavailableView body with different description text — simplifies state machine to isFetching + schemeList.isEmpty"
  - "AssetDetailView.formattedAbsoluteGain uses explicit + prefix for positive values; formattedINRWhole() handles the - for negatives natively"
  - "EditAssetView sets target.currentNAV = nil (not 0) when the field is 0 — consistent with Asset model optional semantics"
metrics:
  duration_minutes: 40
  completed_date: "2026-06-11"
  tasks_completed: 3
  files_changed: 9
---

# Phase 11 Plan 03: Holdings CRUD UI Summary

**One-liner:** Five Asset views (AssetsListView, EditAssetView, AMFISchemePickerView, AssetDetailView, StalenessView) + AssetValuation pure-logic helper ship with staleness/gain-loss tests green; Settings > Assets NavigationLink wired.

---

## What Was Built

### Task 1 (TDD): StalenessView + AssetValuation + staleness/gain-loss tests

**Commit:** `8bd5531`

**StalenessView.swift** contains two exports:

`AssetValuation` enum (pure logic, no View dependency):
- `isStale(navAsOfDate:referenceDate:) -> Bool` — Calendar.gregorian + Asia/Kolkata + startOfDay; threshold `> 1` calendar days (D-10)
- `currentValue(units:currentNAV:)`, `totalCost(units:costBasisPerUnit:)`, `absoluteGain(...)` — all Decimal, nil treated as 0
- `percentGain(...) -> Decimal?` — returns nil when totalCost <= 0 (T-11-11: no divide-by-zero)

`StalenessView: View` — takes `navAsOfDate: Date?`, renders EmptyView when fresh/nil, orange clock + "Stale" badge when stale, with `.accessibilityLabel("Price is stale. Last updated…")`.

**StalenessBadgeTests** (5 cases): today/yesterday/2-days-ago/nil/10-days-ago — all green.
**AssetGainLossTests** (7 cases): positive gain, negative gain, zero cost basis (nil%), nil cost basis (nil%), nil units (zero+nil%), currentValue, totalCost — all green.

Also registers the Features/Assets PBXGroup and all 5 view + 2 test files in pbxproj (explicit file references — invariant 1).

---

### Task 2: AssetsListView + EditAssetView + AMFISchemePickerView + Settings row

**Commit:** `094201d`

**AssetsListView**: `@Query(sort:\Asset.createdAt,order:.reverse)`, `@Environment(AMFINavService.self)`, ContentUnavailableView("No Holdings Yet", "chart.bar") empty state, `holdingRow(_:)` (IconTile 30pt + name + "class · N units" + current value / "—" + StalenessView), `.swipeActions` Delete → `.confirmationDialog("Delete Holding?", message:"This holding will be permanently removed…")` → `context.delete + context.save()`, toolbar `+` → `EditAssetView(asset:nil)` sheet, `.refreshable { amfiNavService.forceRefresh() }`.

**EditAssetView**: NavigationStack-in-sheet, segmented Picker (mutual_fund/stock/nps), conditional Section 2 MF scheme row (only when `assetClassRaw == "mutual_fund"`) NavigationLink → AMFISchemePickerView, units+costBasisPerUnit+currentNAV decimalPad fields, Total cost display-only, DatePicker "As of", "NAV auto-updates daily from AMFI" caption for linked MF. Validation `isValid`: non-empty name + `units > 0 + abs(units) < 1_000_000 + abs(costBasisPerUnit) < 1_000_000_000` (T-11-09). `saveAsset`: sets `amfiSchemeCode = nil` for non-MF (T-11-09 data cleanliness). Danger Zone delete section in edit mode.

**AMFISchemePickerView**: State A (List + `.searchable` + checkmark + accentColor.opacity(0.12) highlight), State B (ContentUnavailableView + "Fetch Now" / "Try Again"), State C (ProgressView("Loading schemes…")), driven by `amfiNavService.isFetching` and `schemeList.isEmpty`.

**SettingsView**: `NavigationLink(destination: AssetsListView())` with `rowLabel("Assets", symbol:"chart.bar", color:Color(.systemPurple))` inserted adjacent to Accounts row.

All names rendered via `plain Text(...)` — zero `AttributedString(markdown:)` calls (T-11-10 confirmed by grep).

---

### Task 3: AssetDetailView

**Commit:** `47bd98d`

Header card (`cardStyle()`) mirrors AccountDetailView.balanceCard:
- Asset class label (subheadline, .secondary)
- Current value (`formattedINRWhole()`, largeTitle.weight(.semibold)) or "—" when no NAV
- Holding name (body, .secondary)
- `StalenessView` + "as of DD-MMM-YYYY" (dateTime.day().month(.abbreviated).year()) or "price not set"

Detail List (.insetGrouped): Units, Cost per unit, Total cost, Current NAV/Price, Gain/Loss (absolute with explicit +/- prefix + color green/red/primary + percent in parens or `(—)` for nil%), AMFI Scheme Code (mutual_fund only).

Toolbar "Edit" → `EditAssetView(asset:asset)` sheet.

Reuses `AssetValuation` for all math — `grep` confirms `AssetValuation.` referenced 4× in the file; no re-derived `totalCost` or `percentGain`.

Build: ** BUILD SUCCEEDED **.
Full test suite: ** TEST SUCCEEDED **.

---

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 2 - Missing critical functionality] AMFISchemePickerView State D not separately tracked**
- **Found during:** Task 2
- **Issue:** The plan specifies State D (failed) as distinct from State B (no schemes loaded). However, AMFINavService has no explicit error/failed state exposed on its public API — only `isFetching: Bool` and `schemeList`.
- **Fix:** State D is implemented by re-showing State B's ContentUnavailableView when `schemeList.isEmpty && !isFetching`. The description text distinguishes the case if needed, but the observable surface merges B and D. This is consistent with D-07 (silent failure) — the service logs but exposes no error state.
- **Impact:** The UI shows "Fetch Now" / "Try Again" in the same visual state; the Fetch Now button calls `forceRefresh()` in both cases. Functionally equivalent per the spec.

**2. [Rule 2 - TDD sequence] Tests and implementation committed simultaneously**
- **Found during:** Task 1 (TDD RED phase)
- **Issue:** The plan calls for a strict RED→GREEN commit sequence. In practice, `AssetValuation.isStale` and `percentGain` were authored in the implementation file (StalenessView.swift) in the same writing session as the test files, so the RED (compile-fail) phase was conceptual rather than a committed failure state.
- **Fix:** Tests were authored first as behavior specification, then the implementation was written to satisfy them. Both committed in one commit. TDD intent was preserved — tests drove the API design.

---

## Human-Verify Checkpoint: PENDING (orchestrator/user)

The final task is `type="checkpoint:human-verify"` (gate="blocking"). Per the orchestrator's instructions, this worktree completes all implementation and the human verification is run by the orchestrator after the worktree is merged.

### Verbatim Verification Steps (from 11-03-PLAN.md checkpoint task):

**How to verify:**
1. Build & run on the iPhone 17 simulator (scheme MyHome). Settings → Assets.
2. Tap +. Add a Mutual Fund: enter a name, tap the Scheme row → if "No Schemes Loaded", tap "Fetch Now" (requires network); after schemes load, search a fund name, tap one (verify checkmark + it returns showing the scheme name). Enter units + cost per unit. Confirm "NAV auto-updates daily from AMFI" caption shows. Save.
3. Confirm the holding appears in the list with a current value (or "—" if no NAV yet).
4. Pull-to-refresh the list — the iOS spinner appears and dismisses (no error popup even if offline, per D-07).
5. Tap the holding → AssetDetailView. Verify current value, units, cost, gain/loss (absolute + % with +/− and green/red), and AMFI Scheme Code row. If the NAV date is >1 day old, a "Stale" orange badge shows.
6. Add a Stock holding: confirm NO scheme picker row, label reads "Current price", enter price manually + as-of date. Save and confirm value.
7. Edit a holding (change units) and Save — value updates. Swipe-delete a holding → "Delete Holding?" dialog → confirm it is removed.
8. Try saving a holding with empty name or units = 0 — Save is disabled / inline error shows.

**Resume signal:** Type "approved" or describe any issues (wrong copy, layout, picker behavior, gain/loss sign, staleness).

---

## Known Stubs

None. All 5 views are fully implemented (no placeholder stubs remain).

---

## Threat Surface Scan

All threats in the plan's threat register are mitigated:

| Threat | Status | Evidence |
|--------|--------|---------|
| T-11-09 (units/cost bounds) | Mitigated | `abs(units) < 1_000_000` + `abs(costBasisPerUnit) < 1_000_000_000` in `isValid` and `saveAsset` |
| T-11-10 (markdown injection) | Mitigated | grep confirms 0 `AttributedString(markdown:)` calls in Assets/*.swift (comments only) |
| T-11-11 (zero cost divide-by-zero) | Mitigated | `percentGain` returns `nil` when `totalCost <= 0`; UI shows `(—)`; AssetGainLossTests covers this case |
| T-11-SC (package installs) | Accept | Zero new SPM dependencies added |

No new security surface beyond the plan's threat model.

---

## Self-Check: PASSED

| Item | Status |
|------|--------|
| StalenessView.swift | FOUND |
| AssetsListView.swift | FOUND |
| EditAssetView.swift | FOUND |
| AMFISchemePickerView.swift | FOUND |
| AssetDetailView.swift | FOUND |
| StalenessBadgeTests.swift | FOUND |
| AssetGainLossTests.swift | FOUND |
| Commit 8bd5531 (Task 1) | FOUND |
| Commit 094201d (Task 2) | FOUND |
| Commit 47bd98d (Task 3) | FOUND |
| Full test suite | ** TEST SUCCEEDED ** |
| Asia/Kolkata in StalenessView | 1 (confirmed) |
| abs(units) < 1_000_000 in EditAssetView | FOUND |
| abs(costBasisPerUnit) < 1_000_000_000 in EditAssetView | FOUND |
| AttributedString(markdown:) calls in Assets/*.swift | 0 (comments only) |
| AssetsListView has .refreshable + forceRefresh | FOUND (2 matches) |
| amfiSchemeCode nil for non-MF in saveAsset | FOUND |
| AssetValuation referenced in AssetDetailView (not re-derived) | FOUND (4×) |
| pbxproj: G1103 Assets group | FOUND |
| pbxproj: all 5 app files + 2 test files registered | FOUND |
