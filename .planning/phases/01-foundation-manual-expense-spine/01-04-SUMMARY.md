---
phase: 01-foundation-manual-expense-spine
plan: 04
subsystem: migration-test-gate
tags: [swiftdata, migration, testing, fnd-05, seed-store, versioned-schema]
dependency_graph:
  requires:
    - swiftdata-schema (01-02, SchemaV1 + AppMigrationPlan)
    - expense-ui-screens (01-03, v1 schema in place)
  provides:
    - v1-seed-store (MyHomeTests/Resources/MyHomeV1Seed.store — bundled SQLite fixture)
    - migration-load-test (MigrationTests.v1StoreMigratesCleanly — FND-05 gate, green)
  affects:
    - Phase 2 (first real migration cannot fail silently — FND-05 gate is now active)
tech_stack:
  added:
    - SwiftData ModelContainer(for:migrationPlan:configurations:) over a real on-disk store
    - macOS SwiftData script (xcrun -sdk macosx swift) for deterministic seed store generation
  patterns:
    - "Seed store generated programmatically via SchemaV1+AppMigrationPlan mirrored in generator script"
    - "Bundle(for: MigrationTestsClass.self) to locate test bundle resources in Swift Testing context"
    - "Copy-to-temp before loading (store is read-only bundle resource; test needs a writable copy)"
    - "Store file force-added with git add -f (gitignore pattern excludes binary files by default)"
key_files:
  created:
    - MyHomeTests/Resources/MyHomeV1Seed.store
    - MyHomeTests/Resources/MyHomeV1Seed.store-shm
    - MyHomeTests/Resources/MyHomeV1Seed.store-wal
    - build/GenerateSeedStore.swift
  modified:
    - MyHomeTests/MigrationTests.swift
    - MyHome.xcodeproj/project.pbxproj
decisions:
  - "Seed store generated via macOS SwiftData script (xcrun -sdk macosx swift) rather than app run — deterministic, reproducible, no simulator required"
  - "Schema mirrored in generator using same VersionedSchema+SchemaMigrationPlan structure so entity name is 'Expense' (not generator class name) — confirmed via SQLite inspection"
  - "Bundle(for: MigrationTestsClass.self) used (concrete class) instead of Bundle(for: type(of: self)) on struct — more reliable in hosted Swift Testing context (Assumption A5)"
  - "Seed store -shm and -wal sidecar files committed alongside .store — SQLite WAL mode requires all three files for consistent state"
metrics:
  duration: 25
  completed_date: "2026-05-29"
  tasks_completed: 1
  files_created: 4
  files_modified: 2
---

# Phase 01 Plan 04: Migration-Load Test and V1 Seed Store Summary

**One-liner:** Bundled v1 SQLite seed store + real migration-load test via AppMigrationPlan closes the FND-05 gate, proving the VersionedSchema path survives a real on-disk store load.

## What Was Built

### Seed Store: MyHomeV1Seed.store

A real SQLite store generated programmatically using a macOS Swift script that mirrors SchemaV1 and AppMigrationPlan exactly. The store contains one seeded Expense row:
- `amount`: 100 (Decimal)
- `note`: "Seed"
- `currencyCode`: "INR"

The generator (`build/GenerateSeedStore.swift`) uses `xcrun -sdk macosx swift` — no simulator, no app run needed. The entity name in the SQLite tables is `ZEXPENSE`, matching what `ModelContainer(for: Schema(versionedSchema: SchemaV1.self))` expects.

### MigrationTests.swift: v1StoreMigratesCleanly (was RED stub)

The test:
1. Locates `MyHomeV1Seed.store` in the test bundle via `Bundle(for: MigrationTestsClass.self).url(forResource:withExtension:)`
2. Copies it to a unique temp URL (defer cleanup)
3. Opens it with `ModelContainer(for: schema, migrationPlan: AppMigrationPlan.self, configurations: [config])`
4. Fetches all `Expense` rows and asserts the result is non-empty
5. Asserts the seed values (amount=100, note="Seed", currencyCode="INR") survive intact

Missing store → explicit `Issue.record` failure (not silent skip) — this is the FND-05 gate.

### project.pbxproj Updates

- Added `F203 / A203` entries for `MyHomeV1Seed.store`
- Added `G210` Resources group inside the MyHomeTests group
- Added `A203` to `P004` (test target Copy Bundle Resources build phase)

## Verification Results

Full test suite on iPhone 17 simulator — all 5 tests green:

```
Test case 'ExpenseModelTests/expensePropertiesAreCloudKitReady()' passed (0.004 seconds)
Test case 'ExpenseModelTests/expenseCRUD()' passed (0.017 seconds)
Test case 'ExpenseModelTests/expenseUpdate()' passed (0.017 seconds)
Test case 'ExpenseModelTests/currencyFormatting()' passed (0.018 seconds)
Test case 'MigrationTests/v1StoreMigratesCleanly()' passed (0.018 seconds)
** TEST SUCCEEDED **
```

## Deviations from Plan

### Checkpoint Handling

The plan's first task was `type="checkpoint:human-action"` requiring manual app run + store extraction. Per the environment context, the executor was instructed to generate the seed store programmatically instead.

**Auto-resolved (deviation Rule 3):** The macOS SwiftData generator approach was used — write a Swift script mirroring SchemaV1+AppMigrationPlan, run it via `xcrun -sdk macosx swift`, producing an identical SQLite store structure without requiring a simulator session.

**Impact:** Zero impact on correctness. The resulting store was verified via `sqlite3` inspection (`ZEXPENSE` table, one row, correct column values) and confirmed loadable by the iOS test suite.

### Bundle Accessor Pattern

Assumption A5 in RESEARCH noted uncertainty about `Bundle(for: type(of: self))` in Swift Testing context (struct has no class type). Used `Bundle(for: MigrationTestsClass.self)` instead — a private concrete class defined in the test file solely for bundle resolution. This is the reliable cross-platform pattern.

## Known Stubs

None. The seed store is real (SQLite, verified) and the migration test is fully implemented and green.

## Threat Flags

None. The seed store contains only synthetic data (amount=100, note="Seed") — no real financial data. The T-01-08 threat was accepted per the threat model.

## Self-Check: PASSED

- `MyHomeTests/Resources/MyHomeV1Seed.store` exists: FOUND
- `MyHomeTests/MigrationTests.swift` contains `v1StoreMigratesCleanly`: FOUND
- Commit 33a81a5 exists: FOUND
- All 5 tests green on iPhone 17: CONFIRMED
