---
phase: 02-categories-tags-budgets
plan: "03"
subsystem: features-expenses
tags: [swiftui, category-picker, add-edit-sheets, optional-assignment, fast-path]
dependency_graph:
  requires: [02-01]
  provides: [CategoryPickerView, expense category assignment on add/edit]
  affects: [AddExpenseView, EditExpenseView, BudgetsView (downstream consumes assigned categories)]
tech_stack:
  added: [CategoryPickerView reusable sheet]
  patterns: ["@Binding selectedCategory: Category?", "@Query(sort: \\.sortOrder)", NavigationStack-in-sheet, None/Clear affordances, optional category row below Date]
key_files:
  created:
    - MyHomeApp/Features/Expenses/CategoryPickerView.swift
  modified:
    - MyHomeApp/Features/Expenses/AddExpenseView.swift
    - MyHomeApp/Features/Expenses/EditExpenseView.swift
    - MyHome.xcodeproj/project.pbxproj
decisions:
  - "Category is optional and placed in Section 2 below Date / above Note so the ≤4-tap fast-path add (amount → Save) is preserved unchanged (D2-12, EXP-01)"
  - "CategoryPickerView uses @Query(sort: \\.sortOrder) so the picker order matches the seeded taxonomy (Groceries first … Misc last)"
  - "None row sets selection nil and dismisses; Clear toolbar button (.destructiveAction, .systemRed) shows only when a selection exists"
  - "EditExpenseView.isDirty extended to compare category persistentModelID; saveExpense sets expense.updatedAt = Date() before context.save() (consistent with CR-01)"
  - "T-02-07: category name rendered as plain Text(category.name ?? \"\") — no markdown/link interpretation"
  - "Assignment wired as expense.categories = selectedCategory.map { [$0] } ?? [] before save (single-select UI over multi-capable schema)"
metrics:
  duration: "~1 session + checkpoint"
  completed: "2026-05-30"
  tasks: 3
  files: 4
  checkpoint: "human-verify — approved 2026-05-30"
---

# Phase 02 Plan 03: Category Picker in Add/Edit Sheets Summary

**One-liner:** Optional category assignment realized via a reusable `CategoryPickerView` sheet (None + Clear affordances) consumed by both the Add and Edit expense sheets, without regressing the ≤4-tap fast-path add.

## What Was Built

- **`CategoryPickerView.swift`** — reusable sheet with `@Binding var selectedCategory: Category?` and `@Query(sort: \Category.sortOrder)`. NavigationStack-in-sheet, a "None" top row (clears selection + dismisses), a `ForEach` over seeded categories with a checkmark on the selected one, and a "Clear" toolbar button (red, `.destructiveAction`, visible only when a selection exists). Category name rendered as plain `Text` (T-02-07).
- **`AddExpenseView.swift`** — added `selectedCategory` / `showCategoryPicker` `@State`, a Category row in Section 2 (below Date, above Note), a `.sheet` presenting the picker, and `expense.categories = selectedCategory.map { [$0] } ?? []` wired before `context.save()`.
- **`EditExpenseView.swift`** — same `@State` pair; `initializeFields()` pre-fills from `expense.categories.first`; `isDirty` extended with a `persistentModelID` compare; `saveExpense()` sets `expense.categories` and `expense.updatedAt = Date()` before save.

## Verification

**Checkpoint type:** human-verify — **APPROVED** (2026-05-30) on iPhone 17 simulator.

Confirmed by manual verification:
1. Build & run succeeds.
2. Fast-path add (amount → Save) remains ~3 taps, saves uncategorized — no regression (EXP-01 / D2-12).
3. Category assign (pick "Groceries") shows icon+name on the row and persists.
4. Edit pre-fills the existing category; Clear returns to "None" and persists.
5. Picker lists all 14 seeded categories in sort order with a checkmark on the selection.

## Threat Mitigations

- **T-02-07** (injection via category name): rendered as plain `Text`, no markdown/link interpretation.

## Self-Check: PASSED
