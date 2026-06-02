---
phase: 07-bank-parsers-ingestion-pipeline
plan: "02"
subsystem: schema-migration
tags: [swift, swiftdata, schema-migration, typealias-flip, schemaV4, migration-test]
dependency_graph:
  requires:
    - phase: 07-01
      provides: SchemaV4 definition, AppMigrationPlan v3ToV4 stage
  provides:
    - typealias Expense = SchemaV4.Expense (live model)
    - typealias Category = SchemaV4.Category
    - typealias Note = SchemaV4.Note
    - typealias NoteBlock = SchemaV4.NoteBlock
    - ModelContainer wired to SchemaV4 + AppMigrationPlan
    - V3→V4 migration test green (T-07-04)
  affects: [07-03, 07-04, 07-05, 07-06]
tech_stack:
  added: []
  patterns: [typealias version flip (mirrors Phase 2/3 pattern), scoped container for WAL flush before copy]
key_files:
  created: []
  modified:
    - MyHomeApp/Persistence/Models/Expense.swift
    - MyHomeApp/Persistence/Models/Category.swift
    - MyHomeApp/Persistence/Models/Note.swift
    - MyHomeApp/Persistence/Models/NoteBlock.swift
    - MyHomeApp/Persistence/ModelContainer+App.swift
    - MyHomeTests/MigrationTests.swift
key_decisions:
  - "MigrationTestsPlanV3 retained as a local test helper for seeding V3 stores in v3StoreMigratesToV4; not removed since it's needed to construct a valid V3 seed store before exercising the V3→V4 migration hop"
  - "V3 seed container scoped in a closure to ensure WAL checkpoint/flush before file copy — prevents empty-store migration failure when reusing the same temp file"
  - "Existing V1/V2 migration tests updated from SchemaV3+MigrationTestsPlanV3 to SchemaV4+AppMigrationPlan — now test the full V1→V4 and V2→V4 chains matching the live app configuration"
requirements-completed: [ING-10, ING-11, ING-12, ING-15]
duration: 25
completed: "2026-06-02"
---

# Phase 7 Plan 02: SchemaV4 Activation (Typealias Flip + Migration Test) Summary

SchemaV4 is now the live model: four typealiases flipped to V4, ModelContainer wired to SchemaV4+AppMigrationPlan, and a V3→V4 migration test proves existing rows survive with all 7 ingestion fields defaulting nil.

## Performance

- **Duration:** ~25 min
- **Completed:** 2026-06-02
- **Tasks:** 2 completed
- **Files modified:** 6

## Accomplishments

- Live `Expense` model now carries all 7 ingestion fields (rawEmailBody, parserID, parserVersion, sourceLabel, gmailMessageID, ingestionStateRaw, parseConfidence) — plans 03/05/06 can write to them immediately
- Full build succeeds with all existing views/tests unchanged (typealias absorbs the version bump transparently)
- T-07-04 threat mitigated: V3→V4 migration verified additive-only; no data loss on schema flip

## Task Commits

1. **Task 1: Flip typealiases + ModelContainer to SchemaV4** - `9bf0fda` (feat)
2. **Task 2: V3→V4 migration test green** - `e6e31cd` (test)

## Files Created/Modified

- `MyHomeApp/Persistence/Models/Expense.swift` — typealias flipped to SchemaV4.Expense; history comment updated
- `MyHomeApp/Persistence/Models/Category.swift` — typealias flipped to SchemaV4.Category
- `MyHomeApp/Persistence/Models/Note.swift` — typealias flipped to SchemaV4.Note
- `MyHomeApp/Persistence/Models/NoteBlock.swift` — typealias flipped to SchemaV4.NoteBlock
- `MyHomeApp/Persistence/ModelContainer+App.swift` — Schema(versionedSchema: SchemaV4.self); AppMigrationPlan.self unchanged
- `MyHomeTests/MigrationTests.swift` — new v3StoreMigratesToV4 test; existing V1/V2 tests updated to use SchemaV4+AppMigrationPlan

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] V3 seed container must be released before file copy to avoid empty-store migration**
- **Found during:** Task 2 verification (first run of v3StoreMigratesToV4)
- **Issue:** `expenses.isEmpty == true` after migration — the V3 seed store file had no committed data because the container's WAL had not been checkpointed to the main store file before the `FileManager.copyItem` call.
- **Fix:** Wrapped the seed-container creation, insert, and save calls in a closure (`try { ... }()`) so the container is fully released and its WAL flushed to the main store file before copying.
- **Files modified:** `MyHomeTests/MigrationTests.swift`
- **Commit:** e6e31cd

## Known Stubs

None — this plan activates schema fields only; no data is populated (population in plan 07-06).

## Threat Surface

T-07-04 mitigated: V3→V4 migration test asserts all 7 new ingestion fields default to nil on existing rows. No data loss on the schema flip confirmed.
T-07-02 accepted: rawEmailBody field is now on the live model but not yet populated (population in plan 07-06, Face ID gate already in place from Phase 5).

## Self-Check: PASSED

| Check | Result |
|-------|--------|
| Expense.swift contains `typealias Expense = SchemaV4.Expense` | FOUND |
| Category.swift contains `typealias Category = SchemaV4.Category` | FOUND |
| Note.swift contains `typealias Note = SchemaV4.Note` | FOUND |
| NoteBlock.swift contains `typealias NoteBlock = SchemaV4.NoteBlock` | FOUND |
| ModelContainer+App.swift contains `Schema(versionedSchema: SchemaV4.self)` | FOUND |
| ModelContainer+App.swift still references `AppMigrationPlan.self` | FOUND |
| v3StoreMigratesToV4 test exists in MigrationTests.swift | FOUND |
| Task 1 commit 9bf0fda | FOUND |
| Task 2 commit e6e31cd | FOUND |
| BUILD SUCCEEDED | CONFIRMED |
| MigrationTests TEST SUCCEEDED (3/3 passing) | CONFIRMED |
