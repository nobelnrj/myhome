# Phase 2: Categories, Tags & Budgets - Context

**Gathered:** 2026-05-29
**Status:** Ready for planning

<domain>
## Phase Boundary

Close the manual-expense loop so the tracker is usable end-to-end with no backend.
This phase introduces a **categorization taxonomy**, **per-category monthly budgets
with progress visualization**, and a **by-category month view** over the existing
`Expense` spine from Phase 1.

**In scope:** EXP-04, EXP-05, EXP-06, EXP-07, EXP-08, EXP-09 — the India-tuned
predefined category list, custom-category CRUD (add/rename/delete), attaching a
category/tag to an expense (single-select in v1 UI, schema models multiple),
recurring per-category monthly budgets, a ₹-remaining + % progress bar with color
shifts at 80% and 100%, and a current-month view grouped by category with
tap-through to the filtered transaction list. Introduces a `TabView` app shell.

**Out of scope (later phases):**
- Spend charts / Swift Charts (Phase 4 — EXP-10, EXP-11)
- Overview / home surface (Phase 4 — OVR-01..04)
- Face ID gate + the real Settings shell that owns category/budget management
  (Phase 5 — SEC-01/02, SET-01/02/03). Phase 2 hosts budget + category management
  inline on the Budgets surface; Phase 5 relocates/mirrors it into Settings.
- Multi-select of tags in the UI (schema supports it; UI stays single-select)
- Gmail OAuth + ingestion + merchant normalization (Phases 6–7)

**Schema constraint:** Adding the `Category` model + the `Expense ↔ Category`
relationship (and any budget storage) is a **`SchemaV2` + lightweight,
non-destructive migration** — never mutate `SchemaV1`, never a rewrite (D-08).

</domain>

<decisions>
## Implementation Decisions

### Taxonomy — one unified axis (discussed)
- **D2-01:** **"Category" and "tag" are a single unified taxonomy in v1.** There is
  one picker. Predefined entries and user-created custom entries are all the same
  kind of record — a `Category` `@Model`. There is no separate "tag" entity.
  This satisfies EXP-04 (predefined list), EXP-05 (custom CRUD), and EXP-06 (one
  tag per expense) with one model.
- **D2-02:** **An expense carries a single category in the v1 UI, but the schema
  models the relationship so that multiple are supported without a future breaking
  migration** (EXP-06 "schema supports multiple"). Recommended mechanism: an
  optional, inverse-declared **to-many** `Expense ↔ Category` relationship
  surfaced as single-select in the UI; final cardinality mechanism is the
  researcher/planner's call as long as it (a) honors the 8 CloudKit-readiness
  rules — optional, inverse-declared, `.nullify` delete rule — and (b) lets a
  future phase enable multi-select with **no breaking migration**.

### Predefined category list (Claude's discretion — from EXP-04)
- **D2-03:** Ship the India-tuned predefined list from EXP-04, **seeded on first
  launch** (idempotent seed — do not duplicate on relaunch): Groceries, Dining,
  Fuel, Utilities, Rent, Auto/Cab, Shopping, Health/Pharmacy, Entertainment,
  Recharge/DTH, Maid/Help, UPI to Person, ATM, Misc. Each gets a sensible default
  SF Symbol (planner/UI-SPEC choice). Seeding strategy (e.g., on first
  `ModelContainer` boot when the Category store is empty) is the planner's call.
- **D2-04:** **Predefined and custom categories are treated uniformly** — both can
  be renamed and deleted (EXP-05). No special protection on predefined entries
  (simplest model for a single-household app). Deleting a category **nullifies**
  the link on its expenses (they become uncategorized), consistent with the
  established `.nullify` delete-rule pattern. Any budget attached to a deleted
  category is removed with it.

### Budgets — recurring monthly limit (discussed)
- **D2-05:** A budget is a **single recurring monthly limit per category** — set
  once, applies to every calendar month. Progress for any viewed month is computed
  against that month's spend in that category. (Not per-specific-month budgets.)
- **D2-06:** Recommended storage: a **`monthlyBudget: Decimal?` on the `Category`**
  (nil = no budget set), keeping money as `Decimal` and the model CloudKit-ready.
  A separate `Budget` model is acceptable if the planner prefers, but per-month
  budget rows are explicitly NOT needed given D2-05.
- **D2-07:** **Budget scope is the calendar month** (already locked by ROADMAP
  success criteria / EXP-07). Default viewed month = the current month.
- **D2-08:** **Uncategorized spend counts in month totals but against no budget.**
  It surfaces as its own "Uncategorized" group in the month view and is excluded
  from per-category budget math.

### Budget progress visualization (from EXP-08)
- **D2-09:** Each category with a budget shows a **₹-remaining + % progress bar**.
  Color thresholds: under 80% = normal/accent, **80%–99% = warning (amber/orange)**,
  **≥100% = over-budget (red)**. Exact color tokens are owned by the Phase 2
  UI-SPEC (must follow the Phase 1 semantic-color system); color is never the sole
  signal (pair with the % / ₹-remaining text). Negative-amount expenses (refunds)
  reduce spend toward the budget.

### Navigation — introduce the TabView shell (discussed)
- **D2-10:** **Introduce a `TabView` in `RootView` now** (the code already
  anticipates this — `RootView.swift`). Phase 2 tabs:
  1. **Expenses** — the existing flat reverse-chron `ExpenseListView`, essentially
     unchanged (the add/edit flow gains a category picker — see D2-12).
  2. **Budgets** — per-category cards showing the recurring budget's progress for
     the selected month, with **month paging (prev/next)**; tapping a category
     opens its **filtered transaction list** for that month. This single surface
     satisfies **EXP-08 (progress)** and **EXP-09 (month-grouped by category +
     tap-through)** together.
  Future phases add tabs: Overview (Phase 4), Settings (Phase 5).
- **D2-11:** **Category + budget management lives inline on the Budgets surface**
  in Phase 2 (an "edit budget" affordance per category card; a "Manage Categories"
  entry for add/rename/delete). **No Settings shell is built in Phase 2** — Phase 5
  (SET-02/03) relocates/mirrors this management into Settings, which is a moved
  entry point, not throwaway work.

### Add/Edit flow gains a category picker (Claude's discretion)
- **D2-12:** The Phase 1 add/edit sheets gain an **optional category picker row**
  (Section 2, off the ≤3-tap critical path — leaving an expense uncategorized stays
  valid). This finally realizes ROADMAP Phase 1 success-criterion #1's
  "amount → category → save" intent, deferred from Phase 1 by D-07. Reuse the
  existing sheet/`@Bindable` patterns; do not regress the ≤4-tap add target (EXP-01).

### Claude's Discretion
Left to researcher/planner using standard SwiftData/SwiftUI conventions: the exact
`Category` field set and SF Symbol/sort-order modeling; the idempotent seeding
mechanism; the `SchemaV2` + `MigrationStage` wiring and the `Expense` typealias
flip; category-picker UI affordance (menu vs sheet vs inline list); month-paging
control; and all visual layout (owned by the Phase 2 UI-SPEC). Schema-field naming
may be refined as long as the 8 CloudKit-readiness rules and D2-02/D2-06 hold.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Project charter & scope
- `.planning/PROJECT.md` — constraints, key decisions (categories+tags, INR, CloudKit-ready stance)
- `.planning/REQUIREMENTS.md` — EXP-04..09 (v1 requirement text + acceptance intent)
- `.planning/ROADMAP.md` §"Phase 2" — goal, success criteria, requirement mapping

### Prior phase context (load-bearing)
- `.planning/phases/01-foundation-manual-expense-spine/01-CONTEXT.md` — D-05 (Expense fields), D-07 (category deferred to P2), **D-08 (additive non-destructive migration constraint)**
- `.planning/phases/01-foundation-manual-expense-spine/01-UI-SPEC.md` — the Phase 1 design system (semantic colors, spacing, typography, copywriting) that the Phase 2 UI-SPEC must extend

### Domain research
- `.planning/research/ARCHITECTURE.md` — CloudKit-ready schema discipline, the 8 `@Model` rules, VersionedSchema scaffolding
- `.planning/research/PITFALLS.md` — SwiftData + CloudKit landmines (no `.unique`, optional/defaulted fields, no stored enums, Decimal money, UTC dates; @Observable/@Bindable only — no @StateObject/@Published)
- `.planning/research/STACK.md` — Swift 6.2 / SwiftUI / SwiftData / iOS 17+ stack

### Source the phase builds on
- `MyHomeApp/Persistence/Schema/SchemaV1.swift` — current `Expense` `@Model`; comment at lines 40-42 marks the Phase 2 category relationship insertion point
- `MyHomeApp/Persistence/Schema/MigrationPlan.swift` — where `SchemaV2.self` + the `.lightweight` stage get appended (comment at lines 13-14)
- `MyHomeApp/Persistence/Models/Expense.swift` — the `typealias Expense` flip point for SchemaV2
- `MyHomeApp/Persistence/ModelContainer+App.swift` — `Schema(versionedSchema:)` wiring + seed hook location
- `MyHomeApp/RootView.swift` — single screen today; becomes the `TabView` (D2-10)
- `MyHomeApp/Features/Expenses/ExpenseListView.swift`, `AddExpenseView.swift`, `EditExpenseView.swift`, `ExpenseRow.swift` — `@Query`/`modelContext`/`@Bindable` patterns; add/edit gain the category picker (D2-12)

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- **`Decimal.formattedINR()`** (`MyHomeApp/Support/Decimal+INR.swift`) — en-IN ₹ formatting for budget amounts and remaining figures.
- **`DecimalKeypadView`** (`MyHomeApp/Features/Expenses/DecimalKeypadView.swift`) — reuse for budget-amount entry (no system keyboard — Pitfall 6).
- **Sheet + `@Bindable` edit pattern** (`EditExpenseView.swift`) — template for category-edit / budget-edit sheets.
- **`@Query` + explicit `context.save()` write pattern** (`ExpenseListView.swift`, CR-01) — financial writes save explicitly; reuse for category/budget writes.
- **Date display helpers** (`MyHomeApp/Support/Date+Display.swift`) — extend for month-header / month-paging labels.

### Established Patterns (binding)
- **Views talk to SwiftData directly** via `@Query` + `@Environment(\.modelContext)` — **no repository layer.** Follow this; do not introduce one.
- **State:** `@Observable` / `@State` / `@Bindable` only — never `@StateObject` / `@ObservedObject` / `@Published` (Pitfall 5).
- **Schema versioning:** every `@Model` type nests inside a `VersionedSchema` enum; the `Expense` typealias hides the version. New models + relationship changes ⇒ new `SchemaV2` + migration stage (never edit `SchemaV1`).
- **8 CloudKit-readiness rules** are non-negotiable for `Category` (and any `Budget`) model: UUID PK, all fields optional/defaulted, no `@Attribute(.unique)`, optional + inverse relationships, `.nullify` delete rule, `Decimal` money, UTC dates, no stored enums.

### Integration Points
- `Expense` gains its category relationship; `Schema`, `AppMigrationPlan`, and the `Expense` typealias all flip to v2 in lockstep.
- `RootView` becomes the `TabView` host; `ExpenseListView` becomes the first tab.

</code_context>

<specifics>
## Specific Ideas

- The Budgets tab is the keystone surface: one screen delivers EXP-08 (progress bars) **and** EXP-09 (month-grouped by category + tap-through). Month paging selects the month context for both.
- Budget bar colors shift at 80% (warning) and 100% (over) — pair color with text, never color-only (accessibility, consistent with Phase 1 UI-SPEC).
- Leaving an expense uncategorized must stay frictionless; the category picker is optional and off the ≤3-tap fast path (preserve EXP-01).
- "Recurring monthly limit" means a category's budget is one number reused every month — not a per-month ledger.

</specifics>

<deferred>
## Deferred Ideas

- **Multi-select tags in the UI** → future (schema supports it via D2-02; v1 UI stays single-select).
- **Spend-by-category & spend-over-time charts** → Phase 4 (EXP-10, EXP-11).
- **Overview / home surface** (spend-vs-budget bar, top categories, pinned note) → Phase 4 (OVR-01..04).
- **Settings shell owning category + budget management** → Phase 5 (SET-02/03); Phase 2 hosts management inline on the Budgets surface.
- **Per-month (non-recurring) budgets / festival-month overrides** → not in v1 (D2-05 chose recurring); revisit if real usage demands it.
- **Budget-threshold notifications (80%/100%)** → v2 (NTF-V2-01).

</deferred>

---

*Phase: 2-Categories, Tags & Budgets*
*Context gathered: 2026-05-29*
