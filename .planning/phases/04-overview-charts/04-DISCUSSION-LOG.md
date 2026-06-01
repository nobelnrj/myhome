# Phase 4: Overview & Charts - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-06-01
**Phase:** 4-Overview & Charts
**Areas discussed:** Home tab & landing, Spend-vs-budget bar, Charts placement, Spend-over-time ranges, Chart styles, Quick-add, Empty states

---

## Home tab & landing

| Option | Description | Selected |
|--------|-------------|----------|
| Leftmost + default | Overview becomes tag 0 (leftmost) and the app launches into it. Existing tabs shift right. Matches phase framing. | ✓ |
| Leftmost, keep Expenses default | Overview leftmost visually but app still launches into Expenses. | |
| Rightmost, default to it | Overview stays 4th/rightmost but is the launch tab. | |

**User's choice:** Leftmost + default
**Notes:** Tabs reorder to Overview(0) → Expenses(1) → Budgets(2) → Notes(3). Flagged that the existing Notes deep-link constant (`selectedTab = 2`) must be re-tagged to 3.

---

## Spend-vs-budget bar (OVR-01)

| Option | Description | Selected |
|--------|-------------|----------|
| Sum of category budgets + over-budget color | Total budget = sum of per-category budgets; reuse BudgetColor over-budget treatment. | ✓ |
| Sum of budgets, simple fill | Same total, plain bar, no threshold color states. | |
| Let planner mirror Budgets tab | Don't over-specify; planner/UI-SPEC reuses BudgetProgressData/BudgetColor. | |

**User's choice:** Sum of category budgets + over-budget color
**Notes:** Reuse BudgetCalculator math; visually consistent with Budgets tab.

---

## Charts placement

| Option | Description | Selected |
|--------|-------------|----------|
| On Overview, scrolled below | Both charts on Overview below the summary cards — one rich dashboard. | ✓ |
| Pushed detail screen | Overview lean launchpad; charts on a pushed detail screen. | |
| By-category on Overview, over-time pushed | Split — one inline, one pushed. | |

**User's choice:** On Overview, scrolled below

---

## Spend-over-time ranges (EXP-11)

| Option | Description | Selected |
|--------|-------------|----------|
| Month / 3M / 6M / Year | Four ranges, auto-bucketed. | |
| Week / Month / Year | Three coarse ranges; Week & Month daily, Year monthly. | ✓ |
| Month / 3M / Year + All time | Adds an All-time span. | |

**User's choice:** Week / Month / Year

---

## Chart styles

| Option | Description | Selected |
|--------|-------------|----------|
| Category=bars, over-time=line | BarMark for category ranking, LineMark for trend. | ✓ |
| Both bars | Both charts use BarMark. | |
| Category=donut/pie, over-time=line | SectorMark donut + line. | |

**User's choice:** Category=bars, over-time=line

---

## Quick-add (OVR-04)

| Option | Description | Selected |
|--------|-------------|----------|
| Reuse full Add Expense sheet | Opens the exact Add Expense sheet from Expenses tab. | ✓ |
| Stripped quick-entry | Minimal amount+category inline entry. | |
| Full sheet + secondary add-note action | Reuse sheet plus a pinned-note-card add-note action. | |

**User's choice:** Reuse full Add Expense sheet

---

## Empty states

| Option | Description | Selected |
|--------|-------------|----------|
| Inline prompts per card | Cards always visible; each nudges next action (Set a budget / No spend yet / Pin a note). | ✓ |
| Hide empty cards | Empty cards don't render. | |
| Planner/UI-SPEC decides per card | Lock graceful handling, defer copy/treatment. | |

**User's choice:** Inline prompts per card

---

## Claude's Discretion

- Overview tab icon + label (house/"Home" vs grid/"Overview").
- OVR-03 "or latest checklist" fallback ordering when no note is pinned.
- Top-3 tie-breaking, category chart colors/labels, chart axis ₹ formatting, accessibility labels.
- Aggregation structure (pure `Support/` helpers vs inline), Overview root container (ScrollView+LazyVStack vs List).

## Deferred Ideas

- All-time / multi-year spend-over-time range.
- Donut/pie share-of-spend chart for by-category.
- Additional charts (budget burn-down, per-tag, month-over-month).
- Quick-add note action from the pinned-note card.
- Dashboard card customization / reordering.
