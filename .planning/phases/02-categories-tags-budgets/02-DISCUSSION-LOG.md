# Phase 2: Categories, Tags & Budgets — Discussion Log

**Date:** 2026-05-29
**Purpose:** Human-reference record of the discuss-phase session. Not consumed by downstream agents (they read 02-CONTEXT.md).

---

## Areas Selected for Discussion

User selected all four presented gray areas:
1. Category & tag taxonomy
2. Budget recurrence & scope
3. Month view & navigation
4. Where budgets are set in Phase 2

---

## Area 1 — Category & tag taxonomy

**Question:** Are 'category' and 'tag' one taxonomy or two separate axes in v1?

**Options presented:**
- One unified taxonomy (one `Category` @Model; predefined + custom; single-select UI; to-many schema for future multi)
- Two separate axes (Category = budgetable; Tag = separate free-form entity)

**User selected:** One unified taxonomy.

**Notes:** Drives the schema — one model satisfies EXP-04/05/06. Captured as D2-01, D2-02.

---

## Area 2 — Budget recurrence & scope

**Question:** How should a per-category monthly budget behave?

**Options presented:**
- Recurring monthly limit (set once, applies every calendar month)
- Per-month budgets (set individually per specific month)

**User selected:** Recurring monthly limit.

**Notes:** Uncategorized spend counts in month totals but against no budget. Captured as D2-05..D2-08.

---

## Area 3 — Month view & navigation

**Question:** How should the month/by-category view and navigation be structured?

**Options presented:**
- Add TabView now (Expenses tab + Budgets tab; Budgets surface delivers EXP-08 + EXP-09)
- Toggle on Expenses screen (segmented control, no TabView yet)

**User selected:** Add TabView now.

**Notes:** Matches the `RootView.swift` "becomes a TabView" intent. Budgets tab is the keystone surface. Captured as D2-10.

---

## Area 4 — Where budgets are set in Phase 2

**Question:** Where does the user create/edit budgets & manage categories in Phase 2? (Settings-based management is Phase 5.)

**Options presented:**
- Inline on Budgets surface (edit-budget per card + Manage Categories entry)
- Minimal Settings shell now (pulls Phase 5 SET-02/03 forward)

**User selected:** Inline on Budgets surface.

**Notes:** No Settings shell in Phase 2; Phase 5 relocates the entry point. Captured as D2-11.

---

## Claude's Discretion (recorded, not asked)

- India-tuned predefined category list seeded idempotently on first launch (D2-03).
- Predefined and custom categories treated uniformly; delete nullifies expense links (D2-04).
- Recommended budget storage: `monthlyBudget: Decimal?` on `Category` (D2-06).
- Budget bar color thresholds at 80% / 100%, paired with text (D2-09).
- Add/edit sheets gain an optional category picker off the ≤3-tap path (D2-12).

## Deferred Ideas

- Multi-select tags in UI → future (schema-ready).
- Charts → Phase 4. Overview → Phase 4. Settings shell → Phase 5.
- Per-month/festival budget overrides → not in v1.
- Budget-threshold notifications → v2 (NTF-V2-01).

---

*Discussion completed: 2026-05-29*
