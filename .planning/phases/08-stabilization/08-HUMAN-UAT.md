---
status: partial
phase: 08-stabilization
source: [08-VERIFICATION.md]
started: 2026-06-09T10:30:00Z
updated: 2026-06-09T10:30:00Z
---

## Current Test

[awaiting human testing]

## Tests

### 1. STAB-01 — delete note/block while day-agenda is open (no crash)
expected: With the Notes calendar / day-agenda sheet open, deleting a note or a note block (from any view) does NOT crash. The row disappears live, and the empty state shows if it was the last item. (Reproduces the tombstoned `@Model` reference path that unit tests cannot.)
result: [pending]

### 2. STAB-04 — RoutineResetService call path fires on foreground
expected: Foregrounding the app prints `[RoutineResetService] resetIfNeeded: startOfToday IST = … No-op` to the console once per `.active` transition, with no crash and no model writes.
result: [pending]

### 3. STAB-03 — new category appears at TOP (smoke confirmation)
expected: In Manage Categories, adding a brand-new custom category makes it appear at the TOP of the list (per the reversed contract). Already unit-tested (`newCategoryPrependsAtTop`); this is a visual confirmation in the running app.
result: [pending]

## Summary

total: 3
passed: 0
issues: 1
pending: 3
skipped: 0
blocked: 0

## Gaps

### G-1 — Launch crash: ModelContainer fails on stale store ("unknown model version") [ROOT-CAUSED, dev-unblocked]
status: diagnosed
- **Symptom (user):** Opening the app crashes; crash log shows `_assertionFailure` in `NotesListView.notes` `@Query` materialization (SwiftData).
- **Actual root cause:** `ModelContainer` creation fatal-errors at `MyHomeApp.swift:14`:
  `CoreData: error: Cannot use staged migration with an unknown model version.` The on-disk store
  was created at a model version the current `AppMigrationPlan` no longer recognizes. The
  `NotesListView` `@Query` crash in the user's log is a downstream symptom of the same broken store.
- **Why:** `SchemaV5` was mutated in place — `Expense.sourceAccount` (commit `cc77f1a`, pre-Phase-8)
  was added to an already-persisted `SchemaV5`, changing its model hash so existing V5 stores became
  an "unknown version" with no migration stage to reach the current V5.
- **Verification:** Deleting the stale dev store (`MyHome.store*` in the AppGroup container) and
  relaunching → app launches and stays running, store recreated + seeded. Confirms the code is sound;
  the crash is purely the persisted store.
- **Immediate action taken:** Wiped the stale store on simulator `2F09365E…`; app now runs.
- **Proper fix (Phase 9 — SchemaV6 & migrations):** Introduce `SchemaV6` (do NOT mutate shipped
  schemas in place), add a real `v5ToV6` stage, and migrate `Expense.sourceAccount` there. Phase 9
  owns schema/migration, so this defect is routed to Phase 9 rather than back-patched in Phase 8.
- **Scope note:** This is a schema-versioning defect introduced before Phase 8 — NOT a STAB-01 gap.
  STAB-01 (calendar deletion crash) remains separately testable on the now-working app.
