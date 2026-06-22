# Phase 15: Analytics Screen - Context

**Gathered:** 2026-06-23
**Status:** Ready for planning
**Mode:** Auto-generated (discuss skipped via workflow.skip_discuss — autonomous run while user asleep)

<domain>
## Phase Boundary

A dedicated Analytics screen — accessible via a navigation push from Overview (not a new tab) — gives users a clear view of their spending trend, category breakdown, and period-over-period delta for any of three time ranges (week, month, year), with all data backed by a single testable aggregator whose output also feeds the AI card (Phase 16).

In scope: the Analytics screen UI, a Week/Month/Year range control, a spending-trend area (or bar) chart with IST-correct bucketing, a by-category horizontal bar breakdown, period-over-period delta chips with inverted color semantics, and a single `AnalyticsAggregator` value-type aggregator + tests. Entry point: a tap target on Overview that pushes the screen.

Out of scope: the AI insight card (Phase 16), any new tab, changes to the tab-bar layout.
</domain>

<decisions>
## Implementation Decisions

### Claude's Discretion
All implementation choices are at Claude's discretion — discuss was skipped per the autonomous run. Honor the established v1.2 design language already converged on in Phases 13–14:
- Neumorphic surfaces via `.neuSurface(.raised/.floating/.recessed)`; dark-only palette from `DesignTokens`.
- Category colors via `CategoryStyle.color(for:)` / `DesignTokens.cat*`.
- Solid `.semibold`/`.bold` `.default`-design numerals for headline figures (NOT thin ultraLight-rounded) — per the user's hero-font preference.
- Rounded "word" amounts (`formattedINRWhole`/`formattedINRWords`) for compact chart readouts.
- Charts: rounded bars, gradient fills, per-category colors; reuse `ActivityRing` / chart patterns from Overview where sensible.
- Inverted delta color convention (ANL-05): green = spend DECREASED vs prior period; coral/`negative` = spend INCREASED.
- Pre-aggregate outside any Chart DSL (Pitfall A guard); never let raw `@Query` arrays enter a Chart; `Double` only at the aggregation boundary, `Decimal` for stored/displayed money (Pitfall B).
- New `.swift` files MUST be registered in `MyHome.xcodeproj/project.pbxproj` (no synchronized groups — the explicit-file-refs footgun).
</decisions>

<code_context>
## Existing Code Insights

- `BudgetCalculator` (`Support/`) already does monthly category aggregation; `SpendOverTimeAggregator` buckets expenses by week/month/year for the Overview trend chart — the new `AnalyticsAggregator` should follow these patterns (value-type output, IST day boundaries) and may consolidate/extend them.
- `SpendByCategoryChart` (Overview) is a track-backed horizontal bar list — reuse the pattern for the by-category breakdown.
- IST midnight bucketing is the known correctness risk (Success Criterion 6 — 18:29Z vs 18:31Z land on different IST days). Use `Calendar` with the IST timezone explicitly.
- Navigation: Overview's `OverviewView` is inside a `NavigationStack`; add a `.navigationDestination` push to the Analytics screen (mirror the existing `navigateToAssets` pattern).
- Codebase context will be deepened during plan-phase research.
</code_context>

<specifics>
## Specific Ideas

Success criteria (from ROADMAP, authoritative):
1. Single tap on Overview opens Analytics via navigation push (slide-in); not a tab; tab bar unchanged.
2. Week/Month/Year switch updates headline, delta chip, area chart, and category bars simultaneously — no stale data.
3. Trend chart buckets into IST-correct day (week) / week (month) / month (year); Year shows only months up to current month (no future zero-bars).
4. By-category horizontal bars show all categories for the range, sorted descending by spend, correct neumorphic palette.
5. Delta chips: inverted color (green = decreased, coral = increased); tapping a chip reveals the category/period detail that drove the change.
6. `AnalyticsAggregatorTests.testMidnightISTBucketBoundary` passes (18:29Z & 18:31Z → different IST day buckets).
7. `xcodebuild clean build` succeeds after all new `Features/Analytics/` + `Support/` files are registered in `project.pbxproj`.

Requirements: ANL-01, ANL-02, ANL-03, ANL-04, ANL-05, ANL-06, ANL-07.
</specifics>

<deferred>
## Deferred Ideas

- AI insight card consuming the aggregator output → Phase 16.
- Light mode → backlog Phase 999.1.
</deferred>
