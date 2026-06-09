---
phase: 08-stabilization
plan: "03"
subsystem: budgets/categories
tags: [category, sort-order, insertion-order, regression-test, STAB-03]
one_liner: "New custom categories now insert at the TOP (min(sortOrder)-1) per user direction, reversing locked decision D-05; regression test + defensive comment updated to match"
dependency_graph:
  requires: []
  provides: [top-insertion contract for new categories, STAB-03 regression test]
  affects: [ManageCategoriesView.swift, MyHomeTests/CategoryCRUDTests.swift, SchemaV5.swift]
tech_stack:
  added: []
  patterns: ["min(existing.sortOrder)-1 insertion", "@Query(sort:) ascending render", "lock-in regression test"]
key_files:
  created: []
  modified:
    - MyHomeApp/Features/Budgets/ManageCategoriesView.swift
    - MyHomeTests/CategoryCRUDTests.swift
    - MyHomeApp/Persistence/Schema/SchemaV5.swift
decisions:
  - "REVERSAL of D-05: user confirmed during the Task 3 human-verify checkpoint that new custom categories must surface at the TOP of the list, not the bottom. Production logic flipped from max(sortOrder)+1 to min(sortOrder)-1."
  - "Regression test renamed newCategoryAppendsAtBottom -> newCategoryPrependsAtTop; now asserts the new category is first with sortOrder == -1 after seeding 0..13."
  - "Category.init defensive comment reworded to the min-1 (top) contract; default value of 0 left unchanged (changing it would break the seed path and SchemaV5 identity)."
  - "STAB-03 became an actual production change, not the no-op the original plan assumed — the reported live symptom ('new category at top') was the DESIRED behavior, and the prior code (bottom) was the bug relative to user intent."
metrics:
  completed_date: "2026-06-09T10:15:00Z"
  tasks_completed: 3
  tasks_total: 3
  files_created: 0
  files_modified: 3
requirements: [STAB-03]
---

# Phase 08 Plan 03: Category Insertion Order Summary

New custom categories now insert at the TOP of the Manage Categories list (`min(existing.sortOrder)-1`), reversing locked decision D-05. The STAB-03 regression test and the `Category.init` defensive comment were updated to lock in and document the top-insertion contract.

## What Was Built

- **`MyHomeApp/Features/Budgets/ManageCategoriesView.swift`** (modified): `addCategory` now computes `let nextSortOrder = (all.map(\.sortOrder).min() ?? 0) - 1`, so each new custom category gets a sortOrder below all existing rows and renders first in the ascending `@Query(sort: \Category.sortOrder)` list.

- **`MyHomeTests/CategoryCRUDTests.swift`** (modified): `newCategoryPrependsAtTop()` (formerly `newCategoryAppendsAtBottom()`) seeds 14 categories (sortOrder 0..13), reproduces the `min(sortOrder)-1` insertion, and asserts `sorted.first?.name == "Custom"` and `sorted.first?.sortOrder == -1`. Locks in top-insertion so it cannot silently regress.

- **`MyHomeApp/Persistence/Schema/SchemaV5.swift`** (modified): The `Category.init(name:symbolName:sortOrder:)` defensive comment was reworded — callers MUST pass `min(existing.sortOrder)-1` to surface new categories at the top; the `sortOrder: Int = 0` default is left unchanged (changing it would break the seed path / SchemaV5 identity).

## Commits

| Task | Name | Commit | Files |
|------|------|--------|-------|
| 1 | Regression test — lock in insertion order | 4a45126 (initial, bottom) → c2b0e94 (reversed to top) | MyHomeTests/CategoryCRUDTests.swift |
| 2 | Defensive comment on Category.init sortOrder default | 49f2d7a (initial, bottom) → c2b0e94 (reversed to top) | MyHomeApp/Persistence/Schema/SchemaV5.swift |
| 3 | Confirm live-app insertion symptom (human-verify) | c2b0e94 (production fix) | MyHomeApp/Features/Budgets/ManageCategoriesView.swift |

> Tasks 1 & 2 were first committed assuming bottom-insertion (4a45126, 49f2d7a). At the Task 3 human-verify checkpoint the user stated the expected behavior is TOP, so all three files were reversed and re-committed together as `c2b0e94`.

## Deviations from Plan

### Locked-decision reversal (D-05 → top-insertion)

- **Found during:** Task 3 — the `checkpoint:human-verify` gate.
- **Plan assumption:** Research (HIGH/MEDIUM confidence) and decision D-05 / success criterion #3 asserted that new categories belong at the BOTTOM (`max+1`) and that the existing production path was already correct, making STAB-03 a test-plus-comment no-op.
- **What actually happened:** The user confirmed the **expected** behavior is that new categories appear at the **TOP** of the list. This reverses D-05. The previously "correct" `max+1` code was therefore the actual defect relative to user intent.
- **Resolution:** With explicit user authorization (AskUserQuestion → "Reverse to top — fix now"), flipped the production insertion logic to `min(sortOrder)-1`, flipped the regression test to assert top, and reworded the defensive comment. Build + `CategoryCRUDTests` green on iPhone 17.
- **Follow-up note:** Decision record D-05 in the phase context should be considered superseded by this execution-time reversal.

## Threat Flags

No new threat surface. STAB-03 remains internal ordering correctness (T-08-06); the defensive comment + regression test continue to lock the contract — now `min-1` instead of `max+1`.

## Self-Check

**Files exist / modified:**
- `MyHomeApp/Features/Budgets/ManageCategoriesView.swift` (min-1 insertion) — FOUND
- `MyHomeTests/CategoryCRUDTests.swift` (`newCategoryPrependsAtTop`) — FOUND
- `MyHomeApp/Persistence/Schema/SchemaV5.swift` (reworded comment) — FOUND

**Commits exist:**
- 4a45126 (Task 1 initial), 49f2d7a (Task 2 initial) — verified
- c2b0e94 (reversal: production fix + test flip + comment) — verified

**Tests:** `CategoryCRUDTests` suite green (5 tests passed, incl. `newCategoryPrependsAtTop`) — iPhone 17 simulator, Xcode 26.5.

## Self-Check: PASSED
