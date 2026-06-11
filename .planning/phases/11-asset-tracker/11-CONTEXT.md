# Phase 11: Asset Tracker - Context

**Gathered:** 2026-06-11
**Status:** Ready for planning

<domain>
## Phase Boundary

Build the Asset Tracker on top of the SchemaV6 `Asset` scaffold:

1. **Holdings CRUD** (ASSET-01/02/04) — add/edit/delete holdings across three asset classes: mutual funds, stocks, NPS. Each records units + cost basis; current value derived. **Stocks and NPS are manual-only** (manual current-NAV/price entry) — no auto-fetch in v1.1.
2. **MF NAV auto-fetch** (ASSET-03) — best-effort background refresh of mutual-fund NAVs from AMFI `NAVAll.txt`; cached last-known value renders the UI immediately and never blocks on the network; manual override always available.
3. **Net-worth aggregation** (ASSET-05/06) — total net worth = sum of holding values + account balances (plain sum; CC balances already negative per Phase 9 D-09). Per-holding gain/loss (absolute + %) vs cost basis.
4. **Allocation chart** (ASSET-07) — donut/pie split by asset class: mutual funds, stocks, NPS, cash.
5. **Net-worth snapshots + trend** (ASSET-08) — record net-worth snapshots over time; chart the trend.
6. **As-of dates + staleness** (ASSET-09) — every NAV/price shows its as-of date and a staleness badge when older than the freshness threshold.

**Out of scope (deferred / other phases):** auto-fetch for stocks and NPS (manual-only in v1.1 — Yahoo fragile, npsnav single-maintainer); CloudKit/sharing (v2.0 trigger); any new SPM dependency (zero new deps across the milestone).

</domain>

<decisions>
## Implementation Decisions

### MF ↔ AMFI linkage
- **D-01:** Mutual-fund holdings link to their AMFI scheme via a **searchable picker** (search by scheme name) on the MF add/edit form. The selection **stores the AMFI scheme code on the Asset**, giving exact-code NAV matching (no fragile name matching at fetch time).
- **D-02:** The searchable scheme list is **sourced from the same `NAVAll.txt` fetch** — that file carries scheme code + name + NAV, so one download feeds both the picker and the NAVs. Single source, always current. Cache the parsed list; the picker needs at least one successful fetch to populate.

### Schema
- **D-03:** Add an `amfiSchemeCode` field to `Asset` and a new `NetWorthSnapshot` @Model in **one additive SchemaV7 migration** this phase. Follow Phase 9's additive/CloudKit-ready rules and the `didMigrate` throw/rollback care (FB13812722) — though V7 likely needs no `didMigrate` backfill (additive fields default to nil).

### Tracker placement & navigation
- **D-04:** The **net-worth summary + allocation chart live on the Overview screen** as a card/section (alongside the existing spend cards), and is tappable.
- **D-05:** **Holdings management (CRUD) lives under Settings** — mirroring the Accounts pattern (Phase 9 D-06). Two entry points open the same holdings management/CRUD view: (a) tapping the Overview net-worth section, and (b) a `Settings > Assets` section. Tab bar stays unchanged.

### NAV refresh
- **D-06:** AMFI NAV fetch fires **daily on `scenePhase .active`** — if the last fetch was before today (IST), kick a best-effort background refresh; the cache renders first and the fetch never blocks UI. Plus **manual pull-to-refresh** on the assets/overview view. Mirrors the `RoutineResetService` once-per-day app-active pattern.
- **D-07:** On fetch failure (offline / AMFI down): **fail silently** — keep showing the cached NAV with its as-of date; the existing staleness badge (ASSET-09) signals oldness. No error popups.

### Net-worth snapshots
- **D-08:** Record **one snapshot per day, on `scenePhase .active`** — upsert today's snapshot (overwrite if one already exists for today) so the daily trend line has no duplicates. Ties into the same daily app-active hook as the NAV refresh.
- **D-09:** Each snapshot stores the **total net worth AND the per-asset-class breakdown** (MF / stock / NPS / cash sub-totals), enabling a stacked-area trend and historical-allocation reconstruction later.

### Staleness & cash treatment
- **D-10:** Staleness threshold (ASSET-09) is **calendar-based: a price is stale when its as-of date is more than ~1 calendar day old.** Simple; ignores weekends/holidays (a fresh Friday NAV may read "stale" on Sunday — harmless). Manual stocks/NPS get the same calendar rule.
- **D-11:** The donut's **"cash" slice = the net sum of all account balances** (savings positive, CC negative per D-09). Net worth stays a plain sum. A negative net (CC debt > cash) is an edge case the planner renders gracefully in the donut.

### Claude's Discretion
- Exact `NetWorthSnapshot` model field shape (date granularity, how per-class sub-totals are stored) within the V7 migration — planner refines, honoring D-09's total+breakdown requirement.
- Gain/loss display layout (absolute + % per holding), empty/zero-cost-basis edge cases.
- How to render a negative-net donut / clamp negative cash gracefully (D-11).
- Multiple holdings of the same fund, NPS tier handling, and other holding-modeling edge cases.
- Exact `NAVAll.txt` parsing + caching strategy and picker search ranking (planner picks based on the file's real format).

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Roadmap & requirements (binding contract)
- `.planning/ROADMAP.md` §"Phase 11: Asset Tracker" — goal + 5 success criteria + "UI hint: yes"
- `.planning/REQUIREMENTS.md` — ASSET-01…ASSET-09 requirement text (esp. ASSET-03 best-effort/cached/never-blocks/manual-override; ASSET-04 stocks+NPS manual-only; ASSET-09 as-of date + stale threshold) and the v1.1 constraints (local-only, CloudKit-ready, no `.unique`, free public data only, zero new SPM deps)

### Schema & migration (read before writing V7)
- `MyHomeApp/Persistence/Schema/SchemaV6.swift` §`Asset` @Model (lines ~247-266) — the scaffold to extend: `name, assetClassRaw ("mutual_fund"|"stock"|"nps"), units, costBasisPerUnit, currentNAV, navAsOfDate, createdAt`. Copy verbatim into V7 and add `amfiSchemeCode`.
- `MyHomeApp/Persistence/Schema/MigrationPlan.swift` — `AppMigrationPlan`; append `SchemaV7.self` (never remove V1–V6); the FB13812722 `.custom` rationale; Phase 9's first non-nil `didMigrate` precedent
- Memory `[[schema-version-mutation-footgun]]` — flip ALL `@Model` typealiases (Asset/Account/Expense/Note/NoteBlock/Category…) to SchemaV7 together in one commit; mismatched typealias caused the STAB-08 save/query crash
- `.planning/phases/09-schemav6-accounts-management/09-CONTEXT.md` — V6 migration patterns, CloudKit-readiness rules, additive-only discipline

### Net-worth aggregation surfaces
- `MyHomeApp/Support/AccountBalance.swift` — central account-balance computation; net worth = holdings + these balances. Memory `[[account-balance-sign-convention]]`: spends stored POSITIVE, balance = baseline − net; CC shown negative (Phase 9 D-09) so it subtracts naturally.
- `MyHomeApp/Features/Settings/AccountsListView.swift`, `AccountDetailView.swift`, `EditAccountView.swift` — Accounts CRUD pattern to mirror for `Settings > Assets` (D-05)

### UI / charts (reuse — zero new deps)
- `MyHomeApp/Features/Shared/DonutChart.swift` — reuse for the allocation donut (ASSET-07)
- `MyHomeApp/Features/Overview/SpendByCategoryChart.swift`, `SpendOverTimeChart.swift` — existing Swift Charts patterns; net-worth trend chart (ASSET-08) follows `SpendOverTimeChart`
- `MyHomeApp/Features/Overview/OverviewView.swift` + the `*Card.swift` files — where the net-worth/allocation card lands (D-04)

### App-active hooks
- `MyHomeApp/RootView.swift` §`scenePhase .active` — daily NAV refresh (D-06) and daily snapshot upsert (D-08) wire in here, alongside the existing `RoutineResetService.resetIfNeeded()` once-per-day IST pattern

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `Shared/DonutChart.swift` — drop-in for the asset-allocation donut (ASSET-07).
- `Overview/SpendOverTimeChart.swift` — template for the net-worth trend line/area chart (ASSET-08).
- Accounts CRUD module (`Settings/AccountsListView` + `AccountDetailView` + `EditAccountView`) — direct pattern for `Settings > Assets` holdings management (D-05).
- `Support/AccountBalance.swift` — the balance source for the "cash" slice and net-worth total (D-11).
- `RootView.scenePhase .active` once-per-day IST gate (RoutineResetService) — same hook for daily NAV refresh + snapshot (D-06/D-08).

### Established Patterns
- Additive-only versioned schemas; `.custom` stages over `.lightweight` (FB13812722). All `@Model` typealiases flip to the new version in one commit (STAB-08 lesson).
- Money is `Decimal`; dates stored UTC, compared/formatted in IST (`Asia/Kolkata`) at the edge — staleness + daily-snapshot "start of today" use IST.
- Summary-on-Overview + CRUD-under-Settings split already established for Accounts (Phase 9) — Assets reuses it.

### Integration Points
- SchemaV7 ← `amfiSchemeCode` on `Asset` + new `NetWorthSnapshot` @Model (D-03).
- `OverviewView` ← net-worth + allocation card, tappable into holdings CRUD (D-04/D-05).
- `Settings` ← `Settings > Assets` holdings management entry (D-05).
- `RootView.scenePhase` ← daily AMFI NAV refresh + daily net-worth snapshot upsert (D-06/D-08).
- New AMFI fetch/parse service ← downloads `NAVAll.txt`, parses code+name+NAV, caches for both picker (D-02) and NAV updates (D-01).

</code_context>

<specifics>
## Specific Ideas

- AMFI source is `NAVAll.txt` (best-effort, cached, manual override) — single data source for both the scheme picker and NAVs (D-02). No second endpoint.
- Stocks + NPS are **manual-only** in v1.1 by deliberate milestone scope (Yahoo fragile, npsnav single-maintainer) — do not add stock/NPS auto-fetch.
- Zero new SPM dependencies — use URLSession + Swift Charts already in the project.
- Build/run on iPhone 17 simulator, Xcode 26.5, scheme `MyHome`, iOS 17+ (memory `[[ios-build-simulator]]`).
- IST (`Asia/Kolkata`) governs all "start of today" / staleness comparisons.

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope. (Stock/NPS auto-fetch is intentionally out of v1.1 per milestone charter; CloudKit/sharing is the v2.0 trigger.)

</deferred>

---

*Phase: 11-Asset Tracker*
*Context gathered: 2026-06-11*
