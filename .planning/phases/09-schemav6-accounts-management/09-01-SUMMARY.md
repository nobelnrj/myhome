---
phase: 09-schemav6-accounts-management
plan: 01
subsystem: persistence/migration
tags: [swiftdata, schema-migration, accounts, stab-08, tdd]
dependency_graph:
  requires: []
  provides: [SchemaV6, Account model, Asset model scaffold, v5ToV6 migration, ACCT-08 backfill]
  affects: [all plans in Phase 09, ModelContainer+App]
tech_stack:
  added: [SchemaV6.swift, Account.swift, Asset.swift]
  patterns: [versioned schema additive migration, non-nil didMigrate closure, STAB-08 atomic typealias flip]
key_files:
  created:
    - MyHomeApp/Persistence/Schema/SchemaV6.swift
    - MyHomeApp/Persistence/Models/Account.swift
    - MyHomeApp/Persistence/Models/Asset.swift
    - MyHomeTests/SchemaV6MigrationTests.swift
  modified:
    - MyHomeApp/Persistence/Schema/MigrationPlan.swift
    - MyHomeApp/Persistence/ModelContainer+App.swift
    - MyHomeApp/Persistence/Models/Expense.swift
    - MyHomeApp/Persistence/Models/Note.swift
    - MyHomeApp/Persistence/Models/NoteBlock.swift
    - MyHomeApp/Persistence/Models/Category.swift
    - MyHome.xcodeproj/project.pbxproj
    - MyHomeTests/MigrationTests.swift
    - MyHomeTests/NoteModelTests.swift
decisions:
  - "Account uses bare accountID: UUID? on Expense (not @Relationship) to avoid circular macro error (Pitfall 5)"
  - "All 6 typealiases + MigrationPlan.schemas + ModelContainer+App schema flipped atomically in one commit (STAB-08)"
  - "v5ToV6 uses .custom (not .lightweight) — FB13812722 workaround preserved; first non-nil didMigrate in codebase"
  - "inferAccountType: CC/credit/card keyword match → credit_card; else → savings (D-03)"
metrics:
  duration_minutes: 21
  completed_date: "2026-06-09"
  tasks_completed: 3
  files_changed: 9
---

# Phase 9 Plan 01: SchemaV6 Migration + Account/Asset Models Summary

SchemaV6 with Account and Asset models, additive Expense/Note fields, idempotent v5ToV6 backfill migration, atomic STAB-08 typealias flip, and passing BLOCKING migration fixture tests.

## Tasks Completed

| Task | Name | Commit | Key Files |
|------|------|--------|-----------|
| 1 | Write BLOCKING V5→V6 fixture test (RED) | d125bb1 | MyHomeTests/SchemaV6MigrationTests.swift |
| 2 | Define SchemaV6 (Account + Asset models, additive fields) | 6d1a72c | MyHomeApp/Persistence/Schema/SchemaV6.swift |
| 3 | Flip all 6 typealiases + v5ToV6 migration stage (GREEN / STAB-08 atomic) | 916c758 | Account.swift, Asset.swift, Expense.swift, Note.swift, NoteBlock.swift, Category.swift, MigrationPlan.swift, ModelContainer+App.swift, project.pbxproj |

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Missing `import Foundation` in MigrationPlan.swift**
- **Found during:** Task 3 (first compile attempt)
- **Issue:** `UserDefaults` is in Foundation; MigrationPlan.swift only imported SwiftData
- **Fix:** Added `import Foundation` to MigrationPlan.swift
- **Files modified:** MyHomeApp/Persistence/Schema/MigrationPlan.swift
- **Commit:** 916c758

**2. [Rule 3 - Blocking] ModelContainer+App.swift used SchemaV5.self with live SchemaV6 typealiases**
- **Found during:** Task 3 (test run: "signal trap" crash before bootstrapping)
- **Issue:** `appContainer()` built the container with `Schema(versionedSchema: SchemaV5.self)` but all `@Model` typealiases now point at `SchemaV6.*`. SwiftData requires the container's versionedSchema to match the active model types — the mismatch caused a fatal crash at app startup during tests.
- **Fix:** Updated `appContainer()` to use `Schema(versionedSchema: SchemaV6.self)`
- **Files modified:** MyHomeApp/Persistence/ModelContainer+App.swift
- **Commit:** 916c758

**3. [Rule 1 - Bug] Pre-existing migration tests used SchemaV5.self with AppMigrationPlan**
- **Found during:** Full suite run after Task 3
- **Issue:** `MigrationTests.swift` (V1 seed, V2 seed, V3→V4, V4→V5 tests) opened stores under `AppMigrationPlan` with `Schema(versionedSchema: SchemaV5.self)`. Now that `AppMigrationPlan` targets `SchemaV6.self`, CoreData returned NSCocoaErrorDomain 134100 ("Incompatible metadata after migration") because the schema passed to ModelContainer.init must match the plan's current target schema.
- **Fix:** Updated all 4 tests to use `SchemaV6.self` — they now exercise the full V1→V6 chain
- **Files modified:** MyHomeTests/MigrationTests.swift
- **Commit:** e8c5fac

**4. [Rule 1 - Bug] `noteSavesUnderProductionVersionedSchema` STAB-08 test used SchemaV5.self**
- **Found during:** Full suite run after Task 3
- **Issue:** `NoteModelTests.swift` test `noteSavesUnderProductionVersionedSchema` built a container with `Schema(versionedSchema: SchemaV5.self)`. After the typealias flip, `Note` is `SchemaV6.Note`, so SwiftData crashed with "Failed to cast model MyHome.SchemaV6.Note to Note" — exactly the STAB-08 pattern this test was designed to prevent.
- **Fix:** Updated the test to use `SchemaV6.self` (the container must match the current live schema)
- **Files modified:** MyHomeTests/NoteModelTests.swift
- **Commit:** e8c5fac

## Verification

- `xcodebuild test ... -only-testing:MyHomeTests/SchemaV6MigrationTests` — both tests PASSED
  - `v5StoreBackfillsAccountID`: 2 accounts created, HDFC CC → credit_card, ICICI → savings, sourceAccount retained, nil sourceLabel stays unassigned
  - `v5MigrationIsIdempotent`: re-opening V6 store creates no duplicate accounts
- `grep -rn "SchemaV5." MyHomeApp/Persistence/Models/` — no V5 typealias references (STAB-08 satisfied)
- Full test suite: TEST SUCCEEDED (all pre-existing tests continue to pass)

## Threat Surface Scan

No new unplanned threat surface introduced. The `Account` model's `expenses` relationship and the `didMigrate` backfill are covered by the plan's threat model (T-09-01 idempotency, T-09-02 sourceAccount retention, T-09-03 typealias atomicity). All mitigations were implemented.

## Known Stubs

None — this plan delivers schema-only work. No UI components were created; no placeholder data flows to UI rendering.

## Self-Check: PASSED

Created files exist:
- MyHomeApp/Persistence/Schema/SchemaV6.swift: FOUND
- MyHomeApp/Persistence/Models/Account.swift: FOUND
- MyHomeApp/Persistence/Models/Asset.swift: FOUND
- MyHomeTests/SchemaV6MigrationTests.swift: FOUND

Commits exist:
- d125bb1: FOUND (test(09-01): add failing V5→V6 migration fixture test)
- 6d1a72c: FOUND (feat(09-01): add SchemaV6)
- 916c758: FOUND (feat(09-01): flip all 6 typealiases + v5ToV6 migration stage)
- e8c5fac: FOUND (fix(09-01): update existing tests to target SchemaV6)
