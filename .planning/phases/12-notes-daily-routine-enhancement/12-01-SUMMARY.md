---
phase: 12-notes-daily-routine-enhancement
plan: "01"
subsystem: persistence/schema
tags: [schema-migration, swiftdata, typealias-flip, test-fixture]
dependency_graph:
  requires: []
  provides: [SchemaV9, RoutineCompletion, v8ToV9-migration]
  affects: [all-model-typealiases, migration-plan, model-container]
tech_stack:
  added: [SchemaV9.RoutineCompletion]
  patterns: [additive-migration, nil-closure-stage, bare-uuid-backref, fetch-before-insert]
key_files:
  created:
    - MyHomeApp/Persistence/Schema/SchemaV9.swift
    - MyHomeApp/Persistence/Models/RoutineCompletion.swift
    - MyHomeTests/SchemaV9MigrationTests.swift
    - MyHomeTests/StreakCalculatorTests.swift
    - MyHomeTests/RoutineNotificationServiceTests.swift
    - MyHomeTests/NoteReorderTests.swift
  modified:
    - MyHomeApp/Persistence/Schema/MigrationPlan.swift
    - MyHomeApp/Persistence/ModelContainer+App.swift
    - MyHomeApp/Persistence/Models/Note.swift
    - MyHomeApp/Persistence/Models/NoteBlock.swift
    - MyHomeApp/Persistence/Models/Category.swift
    - MyHomeApp/Persistence/Models/Account.swift
    - MyHomeApp/Persistence/Models/Asset.swift
    - MyHomeApp/Persistence/Models/Expense.swift
    - MyHomeApp/Persistence/Models/NetWorthSnapshot.swift
    - MyHomeApp/Persistence/Models/SIPAmountChange.swift
    - MyHomeApp/Persistence/Models/SIP.swift
    - MyHomeApp/Persistence/Models/Contribution.swift
    - MyHomeTests/SIPAccrualServiceTests.swift
    - MyHome.xcodeproj/project.pbxproj
decisions:
  - "OQ-1 RESOLVED: #Predicate<RoutineCompletion> { $0.noteID == capturedNoteID } with captured UUID compiles and passes — direct UUID equality works in SwiftData predicate macro (no .uuidString fallback needed)"
  - "RoutineCompletion uses bare UUID noteID back-ref (NOT @Relationship) per Pitfall 5 / CloudKit rule 7 — same pattern as Expense.accountID"
  - "v8ToV9 migration stage uses .custom with nil closures (FB13812722 workaround) — purely additive, no backfill"
  - "All 11 typealiases flipped atomically in single commit (STAB-08 compliance)"
metrics:
  duration: "~35 minutes"
  completed: "2026-06-13"
  tasks_completed: 2
  tasks_total: 2
  files_created: 6
  files_modified: 8
---

# Phase 12 Plan 01: SchemaV9 Schema Foundation Summary

SchemaV9 additive migration — RoutineCompletion @Model, routineDailyReminderTime on Note, all 11 model typealiases atomically flipped, v8ToV9 nil-closure stage, BLOCKING migration fixture green.

## What Was Built

### Task 1: SchemaV9 + RoutineCompletion + Atomic Typealias Flip [BLOCKING] — commit 23bfabc

- **SchemaV9.swift**: 10 copied V8 models (verbatim) + new `routineDailyReminderTime: Date? = nil` on Note (D-04) + new 11th `@Model RoutineCompletion` (D-06). No `@Attribute(.unique)` anywhere (CloudKit rule 2). `noteID: UUID` is a bare UUID back-ref (NOT @Relationship — Pitfall 5/CloudKit rule 7).
- **MigrationPlan.swift**: `SchemaV9.self` appended to `schemas` array; `v8ToV9` appended to `stages` array; `v8ToV9` is `.custom(fromVersion: SchemaV8.self, toVersion: SchemaV9.self, willMigrate: nil, didMigrate: nil)` (purely additive; FB13812722 rationale preserved).
- **ModelContainer+App.swift**: Changed `Schema(versionedSchema: SchemaV8.self)` → `Schema(versionedSchema: SchemaV9.self)`. RoutineCompletion is auto-included via `SchemaV9.models`.
- **11 typealias files flipped atomically** (STAB-08): Note, NoteBlock, Category, Account, Asset, Expense, NetWorthSnapshot, SIP, SIPAmountChange, Contribution (all existing 10) + new RoutineCompletion.swift. All `typealias X = SchemaV8.X` → `typealias X = SchemaV9.X`.
- **project.pbxproj**: 4 entries each for SchemaV9.swift (Schema group, MyHome target) and RoutineCompletion.swift (Models group, MyHome target).
- **Build gate**: `xcodebuild build ... BUILD SUCCEEDED`

### Task 2: Wave-0 Test Scaffolds — commit 66a74ca

- **SchemaV9MigrationTests.swift** (BLOCKING — 2 tests GREEN):
  - `v8StoreNoteSurvivesWithNilReminderTime`: builds genuine V8 store via MigrationTestsPlanV8 (trimmed plan stopping at V8), copies store, opens under SchemaV9 + AppMigrationPlan, asserts notes.count == 1 and routineDailyReminderTime == nil. PASSED.
  - `routineCompletionQueryableAfterMigration`: asserts `FetchDescriptor<RoutineCompletion>()` returns [] (not crash) post-migration. PASSED.
  - `MigrationTestsPlanV8` trimmed migration plan included in file (mirrors MigrationTestsPlanV7 pattern from SchemaV8MigrationTests).
- **NoteReorderTests.swift** (GREEN): `reorderPersists()` — seeds 3 NoteBlocks [A,B,C], moves index 2 (C) to 0, re-indexes, saves, refetches sorted by order, asserts ["C","A","B"]. PASSED.
- **StreakCalculatorTests.swift** (compiling; OQ-1 GREEN): `uuidPredicateFetchCompiles` — inserts RoutineCompletion and fetches via `#Predicate<RoutineCompletion> { $0.noteID == capturedNoteID }` — **PASSED** (OQ-1 resolved, UUID direct comparison works). Streak algorithm cases (5 stubs) use `Issue.record("pending 12-02")` — compile and emit issues.
- **RoutineNotificationServiceTests.swift** (compiling; stubs): 3 test cases use SpyCenter directly as placeholders (RoutineNotificationService created in 12-02). All compile and emit pending issues.
- **project.pbxproj**: 4 entries each for all 4 new test files (PBXBuildFile, PBXFileReference, G200 group membership, P003 SourcesBuildPhase membership).

## Open Question #1 — RESOLVED

**UUID predicate form**: `#Predicate<RoutineCompletion> { $0.noteID == capturedNoteID }` where `capturedNoteID: UUID` **compiles and works correctly** in SwiftData on iOS 26 / Xcode 26.5. The `.uuidString` fallback is NOT needed. Direct UUID equality in `#Predicate` is supported.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] SIPAccrualServiceTests.swift broke after typealias flip**
- **Found during:** Task 2 — first test build attempt
- **Issue:** `SIPAccrualServiceTests.swift` used `SchemaV8.SIP(...)`, `SchemaV8.SIPAmountChange(...)`, `SchemaV8.Asset()` explicitly as constructor prefixes, and the `makeContainer()` function used `Schema(versionedSchema: SchemaV8.self)`. After the typealias flip, service functions expecting `SIP` (now `SchemaV9.SIP`) received `SchemaV8.SIP` objects — type mismatch.
- **Fix:** Replaced all `SchemaV8.SIP(` → `SIP(`, `SchemaV8.SIPAmountChange(` → `SIPAmountChange(`, `SchemaV8.Asset()` → `Asset()` in `SIPAccrualServiceTests.swift`. Updated `makeContainer()` to `Schema(versionedSchema: SchemaV9.self)`.
- **Files modified:** `MyHomeTests/SIPAccrualServiceTests.swift`
- **Commit:** 66a74ca

## pbxproj Edits Made

### App target (MyHome) — Task 1
| File | PBXBuildFile | PBXFileReference | PBXGroup | SourcesBuildPhase |
|------|-------------|-----------------|----------|-------------------|
| SchemaV9.swift | A1201SV9 | F1201SV9 | G131 (Schema) | P002 |
| RoutineCompletion.swift | A1201RC | F1201RC | G132 (Models) | P002 |

### Test target (MyHomeTests) — Task 2
| File | PBXBuildFile | PBXFileReference | PBXGroup | SourcesBuildPhase |
|------|-------------|-----------------|----------|-------------------|
| SchemaV9MigrationTests.swift | A1201SV9MT | F1201SV9MT | G200 | P003 |
| StreakCalculatorTests.swift | A1201SCT | F1201SCT | G200 | P003 |
| RoutineNotificationServiceTests.swift | A1201RNST | F1201RNST | G200 | P003 |
| NoteReorderTests.swift | A1201NRT | F1201NRT | G200 | P003 |

## Threat Surface Scan

No new network endpoints, auth paths, or trust-boundary schema changes beyond what's in the plan's threat model. T-12-01 (additive migration), T-12-02 (typealias partial flip), and T-12-03 (pbxproj registration) were all mitigated as planned.

## Known Stubs

The following test cases in StreakCalculatorTests.swift and RoutineNotificationServiceTests.swift are intentional Wave-0 stubs:
- `streakIsZeroWithNoCompletions` — pending 12-02 (StreakCalculator not implemented)
- `incompleteToday_doesNotBreakStreak` — pending 12-02
- `streakBreaksOnMissedDay` — pending 12-02
- `completingTodayExtendsStreak` — pending 12-02
- `rescheduleIsAtomicCancelThenAdd` — pending 12-02 (RoutineNotificationService not implemented)
- `exactlyOnePendingRequest` — pending 12-02
- `cancelRemovesPendingRequest` — pending 12-02

These stubs compile and emit `Issue.record("pending 12-02")` — they will go green when StreakCalculator and RoutineNotificationService are created in plan 12-02.

## Self-Check: PASSED

- SchemaV9.swift: FOUND
- RoutineCompletion.swift: FOUND
- SchemaV9MigrationTests.swift: FOUND
- StreakCalculatorTests.swift: FOUND
- RoutineNotificationServiceTests.swift: FOUND
- NoteReorderTests.swift: FOUND
- Commit 23bfabc: FOUND
- Commit 66a74ca: FOUND
