# Phase 11: Asset Tracker - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-06-11
**Phase:** 11-Asset Tracker
**Areas discussed:** MF↔AMFI linkage, Tracker placement, NAV refresh trigger, Net-worth snapshots, Staleness, Cash treatment

---

## MF ↔ AMFI linkage

| Option | Description | Selected |
|--------|-------------|----------|
| Searchable picker | Search AMFI scheme list by name; store scheme code on Asset; exact-code fetch | ✓ |
| Free-text + fuzzy match | Type fund name; best-effort match at fetch time; brittle | |
| Manual code entry | User pastes AMFI scheme code; high friction | |

**User's choice:** Searchable picker (stores scheme code).

| Option | Description | Selected |
|--------|-------------|----------|
| Add field via SchemaV7 | New additive V7 migration for amfiSchemeCode + snapshot model | ✓ |
| Reuse existing field | Encode code in existing field; hacky | |
| You decide | Planner picks minimal schema change | |

**User's choice:** Add field via SchemaV7.

| Option | Description | Selected |
|--------|-------------|----------|
| Same NAVAll.txt fetch | One download feeds both picker and NAVs | ✓ |
| Separate lookup endpoint | Second data source; against single-source preference | |
| You decide | Planner picks based on file contents | |

**User's choice:** Same NAVAll.txt fetch.

---

## Tracker placement

| Option | Description | Selected |
|--------|-------------|----------|
| New top-level tab | Dedicated Net Worth/Assets tab | |
| Section in Overview | Net-worth card on Overview | (partial) |
| Under Settings | Like Accounts (D-06) | (partial) |

**User's choice (free-text):** Net-worth summary + allocation shown on Overview; **management/CRUD via Settings view**. Both the Overview section and a Settings section act as entry points that open the same holdings CRUD view.
**Notes:** Confirmed back to user — summary on Overview, CRUD under Settings (Accounts pattern), two entry points into one management screen, tab bar unchanged.

---

## NAV refresh trigger

| Option | Description | Selected |
|--------|-------------|----------|
| Daily on app-active | scenePhase .active, once/day IST + manual pull-to-refresh | ✓ |
| Every app-active | Refresh every foreground; wasteful | |
| Manual only | Pull-to-refresh / button only | |

**User's choice:** Daily on app-active.

| Option | Description | Selected |
|--------|-------------|----------|
| Silent + staleness badge | Cached value + as-of date + existing stale badge; no popups | ✓ |
| Silent + subtle retry hint | Cached value + small retry affordance | |
| You decide | Planner picks least intrusive | |

**User's choice:** Silent + staleness badge.

---

## Net-worth snapshots

| Option | Description | Selected |
|--------|-------------|----------|
| One per day (on app-active) | Upsert today's snapshot; clean daily trend | ✓ |
| On every net-worth change | Dense, noisy | |
| Manual snapshot button | Sparse, user-dependent | |

**User's choice:** One per day (on app-active).

| Option | Description | Selected |
|--------|-------------|----------|
| New model in SchemaV7 | NetWorthSnapshot @Model in same V7 migration | ✓ |
| You decide | Planner designs model shape | |

**User's choice:** New model in SchemaV7.

| Option | Description | Selected |
|--------|-------------|----------|
| Total + per-class breakdown | MF/stock/NPS/cash sub-totals per snapshot | ✓ |
| Total only | Single net-worth number | |
| You decide | Planner picks | |

**User's choice:** Total + per-class breakdown.

---

## Staleness

| Option | Description | Selected |
|--------|-------------|----------|
| Older than ~1 calendar day | Simple; ignores weekends/holidays | ✓ |
| Trading-day aware | Holiday calendar; more correct, more complex | |
| You decide | Planner picks | |

**User's choice:** Older than ~1 calendar day (same rule for manual stocks/NPS).

---

## Cash treatment

| Option | Description | Selected |
|--------|-------------|----------|
| Cash = sum of account balances | Net of all balances (CC negative); plain-sum net worth | ✓ |
| You decide | Planner decides donut rendering | |

**User's choice:** Cash = sum of account balances; planner handles negative-net donut edge case gracefully.

---

## Claude's Discretion

- Exact `NetWorthSnapshot` field shape within V7 (honoring total + per-class breakdown).
- Gain/loss display layout; zero-cost-basis edge cases.
- Negative-net / negative-cash donut rendering.
- Multiple holdings of same fund, NPS tier handling.
- `NAVAll.txt` parsing/caching strategy and picker search ranking.

## Deferred Ideas

None — discussion stayed within phase scope. (Stock/NPS auto-fetch intentionally out of v1.1; CloudKit/sharing is the v2.0 trigger.)
