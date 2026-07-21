---
phase: 20-kitchen-inventory-shopping-list
plan: 01
subsystem: persistence
tags: [swiftdata, schema-migration, kitchen, pantry, shopping-list, sync, stab-08, cloudkit-ready]

# Dependency graph
requires:
  - phase: 18-sync-foundation-schema-merge-engine-airdrop
    provides: SchemaV10 versioned schema, SyncStamped contract, DeletionLog tombstones, .custom-stage discipline
provides:
  - "SchemaV11 VersionedSchema (version 11.0.0): all 12 SchemaV10 classes copied verbatim + PantryItem + ShoppingListItem"
  - "typealias PantryItem = SchemaV11.PantryItem (name, quantity, unit, lowStockThreshold, restockQuantity, category, notes) — the KTCH-01 data spine"
  - "typealias ShoppingListItem = SchemaV11.ShoppingListItem (manual rows only; isChecked/checkedAt sync) — KTCH-03"
  - "Both kitchen models carry syncID/updatedAt and conform to SyncStamped from birth — no backfill migration ever needed (KTCH-04)"
  - "v10ToV11 .custom migration stage; SchemaV11 appended to AppMigrationPlan.schemas (V1-V10 retained)"
  - "All 14 app-facing typealiases + 13 SyncStamped conformances + production container flipped to SchemaV11 atomically (STAB-08)"
affects: [20-02, 20-03, 20-04, 20-05]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Kitchen models are deliberately FLAT — zero @Relationship — so the sync importer needs no wiring pass for them"
    - "Pantry quantities are Double, not Decimal — pantry amounts are not money (precedent: parseConfidence: Double)"
    - "Shopping list is DERIVED + MANUAL: low/out-of-stock rows are computed from PantryItem state at render time and never materialized, so two phones cannot mint duplicate 'auto' rows for the merge engine to reconcile"

key-files:
  created:
    - MyHomeApp/Persistence/Schema/SchemaV11.swift
    - MyHomeApp/Persistence/Models/PantryItem.swift
    - MyHomeApp/Persistence/Models/ShoppingListItem.swift
    - MyHomeTests/SchemaV11MigrationTests.swift
  modified:
    - MyHomeApp/Persistence/Schema/MigrationPlan.swift
    - MyHomeApp/Persistence/ModelContainer+App.swift
    - MyHomeApp/Persistence/Models/SyncStamped.swift
    - MyHomeApp/Persistence/Models/{Expense,Category,Note,NoteBlock,Account,Asset,NetWorthSnapshot,SIP,SIPAmountChange,Contribution,RoutineCompletion,DeletionLog}.swift
    - MyHomeTests/{MigrationTests,NoteModelTests,SIPAccrualServiceTests,SnapshotRoundTripTests,SchemaV6MigrationTests,SchemaV7MigrationTests,SchemaV9MigrationTests,SchemaV10MigrationTests}.swift
    - MyHome.xcodeproj/project.pbxproj

key-decisions:
  - "Shopping list is derived + manual (not materialized) — recorded here, consumed by Plans 03/04"
  - "Quantities are Double; DTOs pass them through unchanged in Plan 02"
  - "No @Attribute(.unique) anywhere in SchemaV11 (CloudKit rule 2); real @Relationship declaration count is 4, identical to SchemaV10"
  - "Kitchen tables start empty, so the SwiftData constant-default footgun does not apply — no didMigrate syncID backfill needed for them"
  - "STAB-08 now provably extends to TEST containers, not just app typealiases (see below)"

patterns-established:
  - "The STAB-08 checklist must include every test-side production container, not only app typealiases — a V10 test container under V11 typealiases traps in ModelContext, not at compile time"
  - "Distinguish seed containers (pinned to an old schema on purpose) from production-tracking containers (must be bumped every schema phase)"

requirements-completed: [KTCH-01 (data spine), KTCH-04 (syncable from birth)]

# Metrics
duration: interrupted-and-resumed
completed: 2026-07-21
---

# Phase 20 Plan 01: SchemaV11 — Kitchen Persistence Spine Summary

**Authored SchemaV11 as an additive superset of SchemaV10 that copies all 12 existing classes verbatim and adds `PantryItem` and `ShoppingListItem` — both carrying `syncID`/`updatedAt` and conforming to `SyncStamped` from birth so they flow through the Phase 18 sync engine with no backfill — wired the `v10ToV11` migration stage, flipped all 14 typealiases + 13 conformances + the production container atomically (STAB-08), and proved it with fixture migration tests.**

## Execution note: interrupted mid-plan, resumed

The executor agent for this plan was terminated by a session usage limit partway
through Task 3. Tasks 1 and 2 were already committed (`80525b3`, `89e2174`); the
Task 3 test file was fully written and pbxproj-registered but never built, tested,
or committed. The resume path re-verified every Task 1/2 acceptance criterion
against the live tree, then completed Task 3 — which is what exposed the defect below.

## What shipped

- **SchemaV11.swift** — 14 classes: 12 copied verbatim from V10 (11 models + DeletionLog, with every field, default, `@Relationship` and footgun comment preserved, internal `SchemaV10.` refs rewritten to `SchemaV11.`) plus the two new kitchen models
- **PantryItem** — name, `quantity: Double`, unit, `lowStockThreshold` (KTCH-02 low/out logic), `restockQuantity` (drives the restock button and shopping check-off in Plans 03/04), category, notes, createdAt, syncID, updatedAt
- **ShoppingListItem** — name, quantity, unit, `isChecked`/`checkedAt` (checked state syncs so the other phone sees what was bought), createdAt, syncID, updatedAt
- **MigrationPlan.swift** — SchemaV11 appended to `schemas`; `v10ToV11` `.custom` stage (FB13812722 workaround discipline retained)
- **ModelContainer+App.swift** — production container flipped to `SchemaV11.self` (App-Group-only store setup untouched)
- **SyncStamped.swift + 14 typealias files** — flipped to V11 in the same commit as the container (STAB-08)
- **SchemaV11MigrationTests.swift** — seeds a genuine V10 store via `MigrationTestsPlanV10` (stages reused from `AppMigrationPlan`, not hand-copied, so the fixture cannot diverge from what a real device produces), then asserts existing data + syncIDs survive, kitchen tables exist/round-trip, kitchen models are sync-stamped, and the bare-typealias STAB-08 guard holds

## Defect found and fixed during close-out

The atomic flip covered app code but missed the **test-side production containers**,
which were still built with `Schema(versionedSchema: SchemaV10.self)`. Under V11
typealiases, any fetch through a bare typealias trapped at runtime:

```
SwiftData/ModelContext.swift:712: Fatal error: Failed to cast model
MyHome.SchemaV11.Expense for PersistentIdentifier(...) to Expense.
```

This crashed the test host process. Under the default parallel-clone runner it
presented as **654 phantom `0.000s` failures across unrelated suites** (parsers,
aggregators, net worth) with no error message — the failures were dead clones,
not real assertions. Running with `-parallel-testing-enabled NO` surfaced the
single real fatal error immediately.

Fixed in `92a72fa` by flipping the production-tracking containers to V11 —
`SyncTestSupport.makeStore` (the shared container behind every sync/bootstrap/
snapshot test), `SIPAccrualServiceTests`, `NoteModelTests`, and the migration
targets in `MigrationTests` / `SchemaV6/V7/V9/V10MigrationTests`. Genuine **seed**
containers were deliberately left on their original schema, including the V10 seed
in `SchemaV11MigrationTests`.

**Lesson (new, worth carrying forward):** the STAB-08 checklist is incomplete if it
only covers app typealiases. Every schema bump must also sweep test containers, and
the seed-vs-production-target distinction is the thing to reason about. When a
schema change lands, always run the suite serially at least once — parallel clones
convert one fatal error into hundreds of meaningless failures.

## Verification

- Acceptance criteria re-verified: syncID count 13, updatedAt count 13, kitchen classes 2, real `@Attribute(.unique)` declarations 0, real `@Relationship(` declarations 4 (identical to V10 — the raw grep counts of 19/18 are comment lines), container on `SchemaV11.self`, all 14 typealiases on V11, 13 SyncStamped conformances, all 4 new files pbxproj-registered "in Sources"
- `SchemaV11MigrationTests` in isolation: 7/7 passed
- **Full suite serial: `** TEST SUCCEEDED **` — 620 tests in 87 suites, 0 failures**
- **Full suite parallel: `** TEST SUCCEEDED **` — 0 failures, 0 fatal errors**
- KTCH-01 data spine and KTCH-04 syncable-from-birth delivered; Plan 02 can extend the sync DTOs with no schema work
