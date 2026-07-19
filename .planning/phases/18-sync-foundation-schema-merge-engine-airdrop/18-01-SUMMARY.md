---
phase: 18-sync-foundation-schema-merge-engine-airdrop
plan: 01
subsystem: persistence
tags: [swiftdata, schema-migration, sync, syncid, updatedat, deletionlog, stab-08, cloudkit-ready]

# Dependency graph
requires:
  - phase: 09-schemav6-accounts-management
    provides: SchemaV9 versioned schema + AppMigrationPlan .custom-stage discipline
provides:
  - "SchemaV10 VersionedSchema (version 10.0.0): 11 models carry syncID: UUID + updatedAt: Date (all additive/defaulted, no .unique) + new DeletionLog tombstone @Model"
  - "SyncStamped protocol (syncID/updatedAt + touch()) conformed by all 11 models — the sync identity contract Plans 02-05 and Phases 19/20 build on"
  - "typealias DeletionLog = SchemaV10.DeletionLog (entitySyncID/entityKindRaw/deletedAt, queryable)"
  - "v9ToV10 .custom migration stage with didMigrate per-row syncID/updatedAt backfill (defeats the SwiftData constant-default footgun)"
  - "All 12 app-facing typealiases flipped to SchemaV10 atomically (STAB-08) + production container on SchemaV10.self"
affects: [18-02, 18-03, 18-04, 18-05, 19, 20]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Sync identity: syncID (cross-device key) + updatedAt (LWW clock) appended additively to every syncable @Model"
    - "Constant-default footgun defeated in didMigrate: Set<UUID>-tracked per-row reassignment so migrated rows get DISTINCT syncIDs (idempotent on re-run)"
    - "Tombstones via DeletionLog @Model (entitySyncID + String entityKindRaw, no stored enum) instead of hard deletes"

key-files:
  created:
    - MyHomeApp/Persistence/Schema/SchemaV10.swift
    - MyHomeApp/Persistence/Models/SyncStamped.swift
    - MyHomeApp/Persistence/Models/DeletionLog.swift
    - MyHomeTests/SchemaV10MigrationTests.swift
  modified:
    - MyHomeApp/Persistence/Schema/MigrationPlan.swift
    - MyHomeApp/Persistence/ModelContainer+App.swift
    - MyHomeApp/Persistence/Models/{Expense,Category,Note,NoteBlock,Account,Asset,NetWorthSnapshot,SIP,SIPAmountChange,Contribution,RoutineCompletion}.swift
    - MyHome.xcodeproj/project.pbxproj

key-decisions:
  - "Expense keeps its pre-existing V4 updatedAt — NOT re-added and NOT touched in backfill; the other 10 models get updatedAt appended"
  - "updatedAt backfill sources: Note ← modifiedAt, NoteBlock ← note?.modifiedAt ?? Date(), all others ← createdAt"
  - "No @Attribute(.unique) anywhere (CloudKit rule 2); uniqueness/dedup is merge-engine fetch-then-upsert logic (Plan 03)"
  - "STAB-08: all 12 typealiases + container flipped in ONE commit — partial flip crashes at save/query time"

patterns-established:
  - "SyncStamped is the single exported contract every syncable model conforms to; touch() bumps updatedAt"
  - "Migration didMigrate closures backfill new identity fields per-row (never rely on a UUID()/Date() default expression — evaluated once)"

requirements-completed: [SYNC-01]

# Metrics
duration: prior-session
completed: 2026-07-17
---

# Phase 18 Plan 01: SchemaV10 — syncID/updatedAt + DeletionLog Summary

**Authored SchemaV10 as an additive superset of SchemaV9 that stamps every one of the 11 persisted models with `syncID: UUID` + `updatedAt: Date`, introduced the `DeletionLog` tombstone @Model, wired a `v9ToV10` migration stage whose `didMigrate` backfills per-row distinct syncIDs (defeating the SwiftData constant-default footgun), flipped all 12 typealiases + the production container to V10 atomically (STAB-08), and proved it with fixture migration tests.**

## Retroactive close-out note

This plan's production commits (`4d5c16b`, `fd4e306`, `834a48c`, `d8b9969`, `dabfaad`) landed in a prior session but the SUMMARY.md was never written, so the SDK still listed 18-01 as incomplete. This session re-verified every acceptance criterion against the live tree before writing this summary (safe-resume recovery path):

- syncID count = 11, updatedAt count = 11, DeletionLog class = 1
- `@Attribute(.unique)` declarations = 0 (the 17 grep hits are all "No @Attribute(.unique)" comment lines)
- SyncStamped conformances = 11; V9 typealiases remaining = 0; V10 typealiases = 12; container on SchemaV10.self = 1
- All 4 new files pbxproj-registered (SchemaV10, SyncStamped, DeletionLog, SchemaV10MigrationTests — "in Sources")
- **Full build + test suite: `** TEST SUCCEEDED **`, 619 tests passed, 0 failures**, including all 5 SchemaV10MigrationTests (distinctSyncIDsAcrossAllRows, updatedAtBackfillPerModel, deletionLogQueryableAndRoundTrips, syncIDsStableAcrossReopen, bareTypealiasRoundTripsUnderProductionPlan)

## What shipped

- **SchemaV10.swift** — 11 models copied verbatim from V9 with syncID/updatedAt appended + DeletionLog tombstone model
- **SyncStamped.swift** — protocol + touch() + 11 conformance extensions (the phase's first exported contract)
- **DeletionLog.swift** — typealias to SchemaV10.DeletionLog
- **MigrationPlan.swift** — SchemaV10 appended to schemas; v9ToV10 custom stage with per-row idempotent syncID/updatedAt backfill ending in explicit `try context.save()`
- **ModelContainer+App.swift** — container flipped to SchemaV10.self (App-Group store setup untouched)
- **All 11 model typealias files** — flipped SchemaV9.X → SchemaV10.X in the same commit set
- **SchemaV10MigrationTests.swift** — seeds a genuine V9 store via trimmed MigrationTestsPlanV9, migrates under the full AppMigrationPlan, asserts distinct syncIDs, updatedAt backfill sources, DeletionLog round-trip, and the STAB-08 bare-typealias guard

## Verification

- `xcodebuild build/test -scheme MyHome -destination 'platform=iOS Simulator,name=iPhone 17'` → **TEST SUCCEEDED**, 619 passed
- SYNC-01 delivered: every model syncable; DeletionLog queryable; SyncStamped exported for downstream plans/phases
