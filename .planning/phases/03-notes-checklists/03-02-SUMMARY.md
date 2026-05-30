---
phase: 03-notes-checklists
plan: 02
subsystem: persistence
tags: [swiftdata, migration, schemaV3, note, noteblock, reminder, cloudkit-ready, tdd]

requires:
  - phase: 03-notes-checklists
    plan: 01
    provides: NoteModelTests + MigrationTests stubs (Wave 0), MyHomeV2Seed.store fixture

provides:
  - SchemaV3 VersionedSchema (v3.0.0): Expense + Category verbatim + Note + NoteBlock @Models
  - ReminderValueTypes: RecurrenceType, ReminderRecurrence, EndRuleType, ReminderEndRule Codable value types
  - Note typealias (SchemaV3.Note) + NoteBlock typealias (SchemaV3.NoteBlock)
  - v2ToV3 .custom migration stage appended to AppMigrationPlan
  - Container flipped to SchemaV3.self; Expense + Category typealiases flipped to V3

affects: [03-03-scheduler, 03-04-list-search, 03-05-ui, 03-06-notifications-calendar]

tech-stack:
  added: []
  patterns:
    - SchemaV3 additive superset pattern (V2 models copied verbatim + new models added)
    - Codable value types serialized to Data? for enums-in-SwiftData (CloudKit rule 8)
    - v2ToV3 .custom stage mirrors v1ToV2 (FB13812722 workaround; nil hooks for additive-only)
    - Typealias version-flip: Expense/Category/Note/NoteBlock all point to SchemaV3.*

key-files:
  created:
    - MyHomeApp/Persistence/Models/ReminderValueTypes.swift
    - MyHomeApp/Persistence/Schema/SchemaV3.swift
    - MyHomeApp/Persistence/Models/Note.swift
    - MyHomeApp/Persistence/Models/NoteBlock.swift
  modified:
    - MyHomeApp/Persistence/Schema/MigrationPlan.swift
    - MyHomeApp/Persistence/ModelContainer+App.swift
    - MyHomeApp/Persistence/Models/Expense.swift
    - MyHomeApp/Persistence/Models/Category.swift
    - MyHomeTests/NoteModelTests.swift
    - MyHomeTests/MigrationTests.swift
    - MyHome.xcodeproj/project.pbxproj

key-decisions:
  - "SchemaV3 copies V2 Expense+Category verbatim and adds Note+NoteBlock — additive superset pattern, never mutate V2"
  - "Expense + Category typealiases flipped from SchemaV2.* → SchemaV3.* (required when container top schema changes)"
  - "v1StoreMigratesCleanly updated to target SchemaV3 (AppMigrationPlan now chains V1→V2→V3)"
  - "NoteBlock.note declared as optional without inverse: (inverse declared only on Note.blocks per circular-macro caveat)"

metrics:
  duration: 35min
  completed: 2026-05-30
  tasks_completed: 2
  files_modified: 11
---

# Phase 03 Plan 02: SchemaV3 Data Layer Summary

**SchemaV3 additive superset (Expense+Category verbatim + Note+NoteBlock with reminder fields) + ReminderRecurrence/EndRule Codable value types + v2ToV3 migration stage + container+typealias flip; NoteModelTests + MigrationTests GREEN**

## Performance

- **Duration:** ~35 min
- **Started:** 2026-05-30T10:25:00Z
- **Completed:** 2026-05-30T11:00:00Z
- **Tasks:** 2
- **Files modified:** 11 (4 created, 7 modified)

## Accomplishments

- Created `ReminderValueTypes.swift` with `RecurrenceType`/`ReminderRecurrence`/`EndRuleType`/`ReminderEndRule` Codable value types — serialized to `Data?` on @Models (no stored enums, CloudKit rule 8)
- Created `SchemaV3.swift` as an additive superset of V2 (Expense + Category copied verbatim, Note + NoteBlock added) with all 8 CloudKit-readiness rules enforced; `@Relationship(deleteRule: .cascade, inverse: \NoteBlock.note)` on `Note.blocks`; inverse inferred on `NoteBlock.note`
- Created `Note.swift` and `NoteBlock.swift` typealiases pointing to `SchemaV3.Note` / `SchemaV3.NoteBlock`
- Updated `MigrationPlan.swift`: appended `SchemaV3.self` to schemas, added `v2ToV3 = MigrationStage.custom(fromVersion: SchemaV2.self, toVersion: SchemaV3.self, willMigrate: nil, didMigrate: nil)`
- Flipped `ModelContainer+App.swift` to `Schema(versionedSchema: SchemaV3.self)`; flipped `Expense.swift` and `Category.swift` typealiases from `SchemaV2.*` → `SchemaV3.*`
- Implemented NoteModelTests (4 tests: noteWithTitlePersists, blockListPreservesOrder, notePropertiesAreCloudKitReady, noteBlockPropertiesAreCloudKitReady) — all GREEN
- Removed `Issue.record` gate from `v2StoreMigratesToV3`; updated `v1StoreMigratesCleanly` to target SchemaV3 — both MigrationTests GREEN
- All Phase 1/2 tests remain GREEN; Wave 0 stubs still fail via Issue.record as designed

## Task Commits

1. **Task 1: SchemaV3 + Note/NoteBlock + ReminderValueTypes** — `9417150` (feat)
2. **Task 2: v2ToV3 migration stage + container flip + MigrationTests GREEN** — `93463bb` (feat)

## Files Created/Modified

- `MyHomeApp/Persistence/Models/ReminderValueTypes.swift` — RecurrenceType/ReminderRecurrence/EndRuleType/ReminderEndRule Codable value types
- `MyHomeApp/Persistence/Schema/SchemaV3.swift` — v3.0.0 VersionedSchema with 4 @Models, 8 CloudKit rules header, models array
- `MyHomeApp/Persistence/Models/Note.swift` — `typealias Note = SchemaV3.Note`
- `MyHomeApp/Persistence/Models/NoteBlock.swift` — `typealias NoteBlock = SchemaV3.NoteBlock`
- `MyHomeApp/Persistence/Schema/MigrationPlan.swift` — schemas list + v2ToV3 stage appended
- `MyHomeApp/Persistence/ModelContainer+App.swift` — schema flipped to SchemaV3.self (line 18)
- `MyHomeApp/Persistence/Models/Expense.swift` — typealias flipped SchemaV2 → SchemaV3
- `MyHomeApp/Persistence/Models/Category.swift` — typealias flipped SchemaV2 → SchemaV3
- `MyHomeTests/NoteModelTests.swift` — 4 tests implemented (was Issue.record stubs)
- `MyHomeTests/MigrationTests.swift` — v2StoreMigratesToV3 implemented; v1StoreMigratesCleanly targets SchemaV3
- `MyHome.xcodeproj/project.pbxproj` — SchemaV3.swift, ReminderValueTypes.swift, Note.swift, NoteBlock.swift wired into app target

## Decisions Made

- **Expense + Category typealiases flipped**: When `ModelContainer+App.swift` targets `SchemaV3.self`, `seedCategoriesIfNeeded` (which uses `FetchDescriptor<Category>()`) and all V2-era fetch operations must use `SchemaV3.*` types. Flipping `Expense` and `Category` typealiases to `SchemaV3` is the required companion to the container flip.
- **v1StoreMigratesCleanly updated to SchemaV3 target**: The test was opening against `SchemaV2.self`. With `AppMigrationPlan` now including `SchemaV3`, the V1 store must migrate all the way to V3. Updated the target schema to `SchemaV3.self` — test still asserts the same Expense survival invariant.
- **NoteBlock predicate workaround**: SwiftData `#Predicate` on `$0.note?.id == note.id` fails to type-check (optional-chain UUID comparison type mismatch). Fixed by fetching all NoteBlocks from the in-memory test container and relying on the test's isolation (only 2 blocks in that container). This is correct for an isolated in-memory test.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 2 - Missing Critical Functionality] Expense + Category typealias flip**
- **Found during:** Task 2 execution — app host crashed at launch with `assertionFailure` in `seedCategoriesIfNeeded`
- **Issue:** `FetchDescriptor<Category>()` resolved to `SchemaV2.Category` but the container now uses `SchemaV3`; `SchemaV2.Category` is not in the V3 model list → assertion failure
- **Fix:** Flipped `Category.swift` and `Expense.swift` typealiases from `SchemaV2.*` → `SchemaV3.*`
- **Files modified:** `Expense.swift`, `Category.swift`
- **Commit:** 93463bb

**2. [Rule 1 - Bug] v1StoreMigratesCleanly target schema mismatch**
- **Found during:** Task 2 — test failed after the Expense typealias flip
- **Issue:** Test opens container with `Schema(versionedSchema: SchemaV2.self)` then fetches `Expense` (now `SchemaV3.Expense`); type not in V2 schema
- **Fix:** Updated test to open with `Schema(versionedSchema: SchemaV3.self)` — correct because AppMigrationPlan now chains to V3
- **Files modified:** `MigrationTests.swift`
- **Commit:** 93463bb

## Threat Surface Scan

No new network endpoints, auth paths, or file access patterns. T-03-02 (migration data loss) mitigated: additive-only `v2ToV3` stage with nil hooks; `v2StoreMigratesToV3` asserts Expense survival. T-03-03 (CloudKit uniqueness violation) mitigated: no `@Attribute(.unique)` on Note/NoteBlock; schema reflection tests enforce it. T-03-04 (log disclosure): no title/block text logged — only `assertionFailure` strings without body content.

## Known Stubs

None in this plan — all production paths (schema, migration, container) are fully wired. Wave 0 test stubs in other test files remain as intentional Issue.record scaffolding per plan 03-01:

| File | Stub | Resolving Plan |
|------|------|---------------|
| NoteListOrderingTests.swift | All 3 tests | 03-04 |
| NoteSearchTests.swift | matchesTitleAndBlockText | 03-04 |
| AutoSaveTests.swift | debounceCommitsAfterQuiet | 03-05 |
| NotificationSchedulerTests.swift | All 3 tests | 03-03 |
| RecurrenceTests.swift | afterNStops, endOnDateStops | 03-03 |
| CalendarAggregationTests.swift | perDayCountsAndProgress | 03-04 |

## Self-Check: PASSED

- `MyHomeApp/Persistence/Schema/SchemaV3.swift` — exists
- `MyHomeApp/Persistence/Models/ReminderValueTypes.swift` — exists
- `MyHomeApp/Persistence/Models/Note.swift` — exists
- `MyHomeApp/Persistence/Models/NoteBlock.swift` — exists
- NoteModelTests: 4/4 PASS (noteWithTitlePersists, blockListPreservesOrder, notePropertiesAreCloudKitReady, noteBlockPropertiesAreCloudKitReady)
- MigrationTests: 2/2 PASS (v1StoreMigratesCleanly, v2StoreMigratesToV3)
- Phase 1/2 tests: ALL PASS (ExpenseModelTests, CategorySeedTests, CategoryCRUDTests, ExpenseCategoryTests, BudgetModelTests, BudgetCalculatorTests)
- Wave 0 stubs: still FAIL via Issue.record (correct — pending later plans)
- Commits 9417150, 93463bb — exist

---
*Phase: 03-notes-checklists*
*Completed: 2026-05-30*
