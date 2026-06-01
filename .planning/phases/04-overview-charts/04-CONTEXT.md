# Phase 4: Overview & Charts - Context

**Gathered:** 2026-06-01
**Status:** Ready for planning

<domain>
## Phase Boundary

Deliver the app's **Home / Overview surface** — the screen a user lands on when
opening the app — that **aggregates and surfaces data the app already has** from
Phase 2 (categories/tags/budgets) and Phase 3 (notes), plus **two Swift Charts**
that sell the app's value. This is a **read + compose** phase: **no new data
models, no new persisted state, no schema migration.** Everything is derived live
from existing `Expense` / `Category` / budget data and `Note` data.

**In scope (OVR-01..04, EXP-10, EXP-11):**
- **OVR-01** — Current-month **total spend vs. total monthly budget as a single
  bar** (total budget = sum of all per-category monthly budgets).
- **OVR-02** — **Top 3 spend categories** this month with absolute ₹ amounts.
- **OVR-03** — Surface the **most-recent pinned note (or latest checklist)** as a
  card.
- **OVR-04** — A **quick-add expense `+`** action.
- **EXP-10** — **Spend-by-category chart** for the current month (Swift Charts).
- **EXP-11** — **Spend-over-time chart** across configurable date ranges (Swift
  Charts).

**Out of scope (later phases / not this phase):**
- Face ID gate + Settings shell (Phase 5) — Overview becomes leftmost tab now;
  Settings arrives in P5 as the 5th tab.
- Gmail OAuth + bank-email ingestion (Phases 6–7).
- Any **new** expense/note data entry beyond reusing the existing Add Expense
  sheet (OVR-04 quick-add). Editing notes/budgets stays in their own tabs.
- Cross-device sync / sharing — post-v1; schema already CloudKit-ready, untouched
  by this phase.
- New chart types beyond the two specified (e.g., budget-burn-down, per-tag
  charts) — not in scope; capture as deferred if they surface.

**No-schema-change constraint:** Phase 4 introduces **zero** `@Model` types and
**no** migration stage. It only reads. The most "new surface area" is importing
**Swift Charts** (no `Charts` import exists in the codebase yet) and adding the
Overview tab + its aggregation helpers.

</domain>

<decisions>
## Implementation Decisions

### Home tab & landing (discussed)
- **D4-01:** **Overview becomes `tag 0`, leftmost, AND the app's launch/default
  tab.** The existing tabs shift right: **Overview(0) → Expenses(1) → Budgets(2)
  → Notes(3)**. Rationale: the phase's whole framing is "user opens the app and
  immediately sees how the household is doing this month." Update `RootView.swift`
  default `selectedTab` to `0` and reorder the `TabView` children accordingly.
  Note: with Settings (P5) this makes **5 tabs** — exactly the iOS limit before
  the "More" overflow, so no More menu (consistent with D3-17's tab-bar-lean
  intent). The existing Notes deep-link sets `selectedTab = 2` on banner tap —
  **that constant must be updated to the new Notes tag (3)** when reordering.

### Spend-vs-budget bar — OVR-01 (discussed)
- **D4-02:** The single bar compares **current-month total spend** against
  **total monthly budget = sum of ALL per-category monthly budgets** set in
  Phase 2. The bar reuses the **existing `BudgetCalculator` /
  `BudgetProgressData` / `BudgetColor`** over-budget treatment (the red/overflow
  state when spend exceeds budget), so the Overview bar is visually consistent
  with the Budgets tab. Do **not** re-derive spend/budget math — call into
  `BudgetCalculator` (`monthlySpend`, `monthBoundaries`). *Discretion:* how to
  fold per-category budgets into a single aggregate (sum) and the exact bar
  component layout is the planner/UI-SPEC's call, provided it reuses the existing
  color thresholds.

### Charts placement (discussed)
- **D4-03:** **Both Swift Charts live ON the Overview screen**, scrolled **below**
  the summary cards (bar → top-3 → pinned-note card → charts). Overview is **one
  rich scrolling dashboard**, not a launchpad-with-pushed-detail. Implies the
  Overview root is a `ScrollView`/`List`-style vertical stack that can grow.

### Spend-over-time chart — EXP-11 (discussed)
- **D4-04:** Configurable ranges = **Week / Month / Year** (segmented control).
  Bucketing: **Week → daily**, **Month → daily**, **Year → monthly**. Keep the
  range→bucket mapping in a small, testable helper (TDD default), separate from
  the chart view.
- **D4-05 (style):** Spend-over-time renders as a **`LineMark`** (trend).

### Spend-by-category chart — EXP-10 (discussed)
- **D4-05 (style):** Spend-by-category renders as **`BarMark`** ranking
  categories by current-month spend. (Same decision id D4-05 covers both chart
  styles: **category = bars, over-time = line.**)

### Quick-add — OVR-04 (discussed)
- **D4-06:** The Overview **quick-add `+` reuses the existing full Add Expense
  sheet** from the Expenses tab (custom decimal keypad, category/tag, ≤3-tap
  add). **No new/stripped entry UI** — present the same sheet via `.sheet`. This
  keeps entry behavior identical everywhere and avoids new surface area.

### Empty / zero states (discussed)
- **D4-07:** Cards **degrade gracefully in place with inline prompts** — cards
  are always rendered, never hidden, each nudging the next action:
  - **No budget set** → bar shows spend only + a **"Set a budget"** nudge.
  - **No expenses this month** → top-3 and charts show a friendly **"No spend
    yet"** state (not a blank/broken chart).
  - **No pinned note** → card invites **"Pin a note to see it here."**
  *Discretion:* exact copy and visual treatment owned by the UI-SPEC.

### Claude's Discretion (planner / UI-SPEC)
- **D4-08:** Left to the researcher/planner/UI-SPEC using standard SwiftUI +
  Swift Charts + SwiftData conventions:
  - The **Overview tab icon + label** (e.g. `house` / "Home" vs `square.grid.2x2`
    / "Overview") — pick one consistent with the existing SF Symbol tab style.
  - **OVR-03 fallback resolution** — "most-recent pinned note **or** latest
    checklist": prefer the most-recent **pinned** note (via `NoteListOrganizer`'s
    `pinned`); when none is pinned, fall back to the most-recent note that
    contains a checkbox block (the "latest checklist"); when neither exists, the
    D4-07 empty prompt. Exact fallback ordering is the planner's call.
  - **Top-3 tie-breaking**, category color/labeling on the by-category chart,
    chart axis/`₹` formatting (reuse `Decimal+INR`), and accessibility labels.
  - How aggregation is structured: prefer **small pure helpers in `Support/`**
    (mirroring `BudgetCalculator` / `CalendarAggregator`) fed by `@Query`
    results, kept unit-testable per the TDD default — **no repository layer.**
  - Whether the Overview root is `ScrollView` + `LazyVStack` vs `List` sections.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Requirement & roadmap sources
- `.planning/ROADMAP.md` §"Phase 4: Overview & Charts" — goal, success criteria
  (4 items), requirement set OVR-01..04 + EXP-10/11, UI hint: yes.
- `.planning/REQUIREMENTS.md` — OVR-01..04 (lines ~74–77), EXP-10/11 (lines
  ~37–38). The authoritative requirement text.

### Project charter & scope
- `.planning/PROJECT.md` — Overview/Home requirements ("month spend vs budget
  single bar", "top 3 categories", "pinned notes/checklist surfaced"); INR
  single-currency en-IN formatting; performance explicitly NOT a constraint
  (two-user, low volume — do not over-engineer aggregation); iOS 17+ stack.

### Domain research (load-bearing)
- `.planning/research/STACK.md` — Swift 6.2 / SwiftUI / SwiftData / iOS 17+ stack;
  Swift Charts availability/version.
- `.planning/research/PITFALLS.md` — SwiftData/SwiftUI landmines: `@Observable` /
  `@Bindable` / `@State` ONLY (never `@StateObject` / `@ObservedObject` /
  `@Published`); CloudKit-ready model rules (unaffected here — no new models).
- `.planning/research/ARCHITECTURE.md` — schema discipline (confirms Phase 4 is
  read-only; no `SchemaV4`, no migration stage).

### Prior phase context (binding patterns)
- `.planning/phases/02-categories-tags-budgets/02-CONTEXT.md` — D2-10 (TabView
  shell), "no repository layer / `@Query` + `modelContext`" pattern, budget/
  category model decisions the Overview reads.
- `.planning/phases/03-notes-checklists/03-CONTEXT.md` — note/block model,
  pin/daily-routine sections (`NoteListOrganizer`), the `selectedTab = 2`
  deep-link constant that must be re-tagged when Notes moves to tag 3.
- `.planning/phases/01-foundation-manual-expense-spine/01-CONTEXT.md` — UTC date
  discipline, `Decimal` money storage, INR formatting conventions.

### Source the phase builds on (read before implementing)
- `MyHomeApp/RootView.swift` — `TabView` host. **Add Overview as tag 0 + make it
  the default `selectedTab`; reorder Expenses→1 / Budgets→2 / Notes→3; update the
  `selectedTab = 2` deep-link constant to the new Notes tag.**
- `MyHomeApp/Support/BudgetCalculator.swift` — `monthlySpend`, `monthBoundaries`,
  `uncategorizedSpend`, `BudgetProgressData`, `BudgetColor`. **Reuse for OVR-01
  bar, OVR-02 top-3, and the by-category chart aggregation.**
- `MyHomeApp/Support/CalendarAggregator.swift` — reference pattern for a pure,
  unit-tested `Support/` aggregator (mirror this shape for any new
  Overview/spend-over-time aggregation helper).
- `MyHomeApp/Support/NoteListOrganizer.swift` — `pinned` / `dailyRoutine`
  sections; source for OVR-03's "most-recent pinned note".
- `MyHomeApp/Support/Decimal+INR.swift` — en-IN ₹ formatting for amounts and
  chart axis labels.
- `MyHomeApp/Features/Budgets/BudgetsView.swift` + `BudgetProgressView.swift` +
  `BudgetCategoryCard.swift` — visual reference for the aggregate bar; reuse
  `BudgetProgressData`/`BudgetColor` so Overview matches.
- `MyHomeApp/Features/Expenses/` (Add Expense sheet) — the **exact sheet OVR-04
  re-presents**; find the existing add-sheet view + its `.sheet` trigger pattern.
- `MyHomeApp/Persistence/Models/` (`Expense`, `Category`, `Note`, `NoteBlock`) —
  the read models; **no edits** to these in Phase 4.

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- **`BudgetCalculator`** (`Support/`) — already computes month spend, month
  boundaries, uncategorized spend, and exposes `BudgetProgressData` / `BudgetColor`.
  Powers OVR-01 (aggregate bar), OVR-02 (top-3), and the EXP-10 by-category data.
- **`NoteListOrganizer`** (`Support/`) — `pinned` section directly answers OVR-03.
- **`Decimal+INR`** (`Support/`) — ₹ formatting for cards and chart axes.
- **Add Expense sheet** (`Features/Expenses/`) — reused verbatim for OVR-04.
- **`CalendarAggregator`** (`Support/`) — template for a new pure spend-over-time
  bucketing helper (Week→daily / Month→daily / Year→monthly).
- **TabView shell** (`RootView.swift`) — Overview slots in as the new leftmost
  default tab.

### Established Patterns (binding)
- **Views talk to SwiftData directly** via `@Query` + `@Environment(\.modelContext)`
  — **no repository layer.** Aggregation goes in pure `Support/` helpers fed by
  `@Query` results (mirror `BudgetCalculator` / `CalendarAggregator`), kept
  unit-testable (TDD default).
- **State:** `@Observable` / `@State` / `@Bindable` only — never `@StateObject` /
  `@ObservedObject` / `@Published`.
- **No new schema / migration** — Phase 4 is read-only over existing models.

### Integration Points
- `RootView.swift` `TabView` — add Overview tab (tag 0, default), reorder others,
  re-tag the Notes deep-link constant (currently `selectedTab = 2` → `3`).
- **Swift Charts** is net-new (`import Charts`) — first use in the project;
  confirm availability for the iOS 17+ deployment target in research.
- Overview reads across **both** expense data (Phase 2) and note data (Phase 3) —
  the first screen to compose the two independent features.

</code_context>

<specifics>
## Specific Ideas

- Overview is the **home screen** — leftmost tab, app launches into it; "open the
  app, immediately see how the household is doing this month."
- One **rich scrolling dashboard**: spend-vs-budget bar → top-3 categories →
  pinned-note card + quick-add `+` → by-category bar chart → spend-over-time line
  chart, all on one screen.
- The aggregate budget bar should **look and behave like the Budgets tab** (same
  `BudgetColor` over-budget red), just summed across all categories.
- Spend-over-time: **Week / Month / Year**, daily buckets for Week & Month,
  monthly for Year, drawn as a **line**.
- Empty cards **coach the user** ("Set a budget", "No spend yet", "Pin a note")
  rather than disappearing.

</specifics>

<deferred>
## Deferred Ideas

- **All-time / multi-year spend-over-time range** — considered, deferred; v1 caps
  at Week/Month/Year (D4-04). Revisit once there's enough history to be useful.
- **Donut/pie share-of-spend chart** — considered for by-category, deferred in
  favor of bars for accurate ranking. Possible future visual polish.
- **Additional charts** (budget burn-down, per-tag breakdown, month-over-month
  comparison) — out of scope for OVR/EXP-10/11; future phase if desired.
- **Quick-add note action from the Overview pinned-note card** — considered;
  v1 quick-add is expense-only (D4-06). Could revisit if home-screen note capture
  proves wanted.
- **Per-card customization / reordering the dashboard** — not in v1.

None of these block Phase 4; they stay out unless explicitly re-scoped.

</deferred>

---

*Phase: 4-Overview & Charts*
*Context gathered: 2026-06-01*
