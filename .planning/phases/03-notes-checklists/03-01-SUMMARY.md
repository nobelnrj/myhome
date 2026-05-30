---
phase: 03-notes-checklists
plan: 01
subsystem: testing
tags: [swift-testing, swiftdata, usernotifications, wave-0, nyquist, test-scaffold, spy-pattern, migration-fixture]

requires:
  - phase: 02-expense-categories-budgets
    provides: MyHomeTests target, existing seed store pattern (MyHomeV1Seed.store), MigrationTests framework, BudgetCalculatorTests test style

provides:
  - NotificationCenterPort protocol seam (MyHomeTests/Support/SpyCenter.swift)
  - SpyCenter in-memory test double conforming to NotificationCenterPort
  - ReminderInfo placeholder struct (plan 03-03 will replace)
  - 7 Wave 0 failing test stubs (NoteModelTests, NoteListOrderingTests, NoteSearchTests, AutoSaveTests, NotificationSchedulerTests, RecurrenceTests, CalendarAggregationTests)
  - Extended MigrationTests with v2StoreMigratesToV3 stub
  - MyHomeV2Seed.store bundled in MyHomeTests Copy Bundle Resources
  - build/GenerateV2SeedStore.swift (gitignored) for regenerating the V2 fixture
  - All 8 test files wired into MyHomeTests target in project.pbxproj

affects: [03-02-model-schema, 03-03-scheduler, 03-04-list-search, 03-05-ui, 03-06-notifications-calendar]

tech-stack:
  added: [UserNotifications (test seam only — SpyCenter)]
  patterns:
    - NotificationCenterPort protocol-port + SpyCenter spy pattern for headless scheduler tests
    - Wave 0 Issue.record stubs — compile-pass/fail-by-design Nyquist baseline
    - GenerateV2SeedStore.swift macOS script pattern (mirrors GenerateSeedStore.swift)

key-files:
  created:
    - MyHomeTests/Support/SpyCenter.swift
    - MyHomeTests/NoteModelTests.swift
    - MyHomeTests/NoteListOrderingTests.swift
    - MyHomeTests/NoteSearchTests.swift
    - MyHomeTests/AutoSaveTests.swift
    - MyHomeTests/NotificationSchedulerTests.swift
    - MyHomeTests/RecurrenceTests.swift
    - MyHomeTests/CalendarAggregationTests.swift
    - MyHomeTests/Resources/MyHomeV2Seed.store
    - MyHomeTests/Resources/MyHomeV2Seed.store-shm
    - MyHomeTests/Resources/MyHomeV2Seed.store-wal
    - build/GenerateV2SeedStore.swift (gitignored)
  modified:
    - MyHomeTests/MigrationTests.swift
    - MyHome.xcodeproj/project.pbxproj

key-decisions:
  - "NotificationCenterPort defined in SpyCenter.swift (test file) for Wave 0; plan 03-06 produces the production conformer in Support/NotificationCenterPort.swift"
  - "ReminderInfo placeholder struct defined in SpyCenter.swift — plan 03-03 moves/replaces with Codable value types"
  - "Wave 0 stubs use Issue.record (not placeholder type declarations) so no throwaway types need removing in later waves"
  - "build/ is gitignored; GenerateV2SeedStore.swift is not tracked (same as GenerateSeedStore.swift precedent); generated .store files in MyHomeTests/Resources/ ARE tracked"

patterns-established:
  - "Wave 0 stub pattern: @Test body = Issue.record('not yet implemented — X pending plan YY')"
  - "SpyCenter spy pattern: records addedRequests + removedIdentifierSets, exposes addedIdentifiers convenience property"
  - "V2 seed store generator mirrors GenerateSeedStore.swift: xcrun -sdk macosx swift build/GenerateV2SeedStore.swift <output-dir>"

requirements-completed: [NOT-01, NOT-02, NOT-03, NOT-04, NOT-05, NOT-06, NOT-07, NOT-08, NOT-09, NOT-10]

duration: 45min
completed: 2026-05-30
---

# Phase 03 Plan 01: Wave 0 Test Scaffold Summary

**Nyquist Wave 0 baseline: 8 failing test stubs (NoteModelTests through CalendarAggregationTests) + NotificationCenterPort/SpyCenter seam + MyHomeV2Seed.store bundled fixture, all wired into MyHomeTests target**

## Performance

- **Duration:** ~45 min
- **Started:** 2026-05-30T10:15:00Z
- **Completed:** 2026-05-30T11:00:00Z
- **Tasks:** 3
- **Files modified:** 14 (11 created, 3 modified)

## Accomplishments

- Defined `NotificationCenterPort` protocol with the four scheduler-testable members; implemented `SpyCenter` in-memory double recording all `add` and `removePendingNotificationRequests` calls
- Created all 7 Wave 0 test suites (NoteModelTests, NoteListOrderingTests, NoteSearchTests, AutoSaveTests, NotificationSchedulerTests, RecurrenceTests, CalendarAggregationTests) with named tests matching VALIDATION.md verbatim, all failing via `Issue.record`
- Extended MigrationTests with `v2StoreMigratesToV3` stub; generated and bundled `MyHomeV2Seed.store` (Expense amount=100 + one Category seeded); v1 migration test remains green
- Wired all 8 new test files + seed store into MyHomeTests target in project.pbxproj (explicit membership — no file-system-synchronized groups)

## Task Commits

1. **Task 1: NotificationCenterPort seam + SpyCenter test double** - `decf85a` (feat)
2. **Task 2: Wave 0 failing test stubs** - `21017ac` (test)
3. **Task 3: MyHomeV2Seed.store + MigrationTests extension + bundle wiring** - `9477f4c` (feat)

## Files Created/Modified

- `MyHomeTests/Support/SpyCenter.swift` — NotificationCenterPort protocol + SpyCenter spy + ReminderInfo placeholder + fixture builders
- `MyHomeTests/NoteModelTests.swift` — NOT-01/02: noteWithTitlePersists, blockListPreservesOrder, CloudKit-readiness (stub)
- `MyHomeTests/NoteListOrderingTests.swift` — NOT-03/04/SC-R5: sectionOrdering, pinMovesToPinnedSection, dailyRoutineFilter (stub)
- `MyHomeTests/NoteSearchTests.swift` — NOT-06: matchesTitleAndBlockText (stub)
- `MyHomeTests/AutoSaveTests.swift` — NOT-05: debounceCommitsAfterQuiet (stub)
- `MyHomeTests/NotificationSchedulerTests.swift` — SC-R1/SC-R3a/64-cap: buildRequestsLeadAlerts, weeklyMultiWeekday, pendingCountUnderCap (stub)
- `MyHomeTests/RecurrenceTests.swift` — SC-R2: afterNStops, endOnDateStops (stub)
- `MyHomeTests/CalendarAggregationTests.swift` — SC-R4(a,b): perDayCountsAndProgress (stub)
- `MyHomeTests/MigrationTests.swift` — extended with v2StoreMigratesToV3 stub (fails; SchemaV3 pending plan 03-02)
- `MyHomeTests/Resources/MyHomeV2Seed.store` (+ -shm, -wal) — V2 fixture: 1 Expense (₹100 "Seed") + 1 Category
- `MyHome.xcodeproj/project.pbxproj` — G220 Support group, F301–F310 file refs, A301–A310 build files, P003 Sources + P004 Resources entries

## Decisions Made

- `NotificationCenterPort` placed in `SpyCenter.swift` for Wave 0 instead of its final location `Support/NotificationCenterPort.swift` — avoids creating a production file that plan 03-06 owns. Plan 03-06 will create the production file; the protocol definition will migrate there.
- Wave 0 stubs use `Issue.record("not yet implemented — ...")` bodies instead of placeholder type declarations — cleaner removal story for implementing plans, no stub types to chase.
- `build/GenerateV2SeedStore.swift` is gitignored (same policy as `GenerateSeedStore.swift`); the generated store files in `MyHomeTests/Resources/` are tracked.

## Deviations from Plan

None — plan executed exactly as written. The only structural decision not pre-specified was where to initially place the `NotificationCenterPort` protocol definition (documented above).

## Issues Encountered

- `v2StoreMigratesToV3` was initially placed outside the `MigrationTests` struct due to an edit that inserted after the closing `}`. Fixed immediately before the task commit (Rule 1 auto-fix: syntax error prevented compilation).

## Known Stubs

All stubs are intentional Wave 0 scaffolding — each has `Issue.record("not yet implemented — ... pending plan XX-YY")`. No production data paths are stubbed:

| File | Stub | Resolving Plan |
|------|------|---------------|
| NoteModelTests.swift | All 4 tests | 03-02 |
| NoteListOrderingTests.swift | All 3 tests | 03-02 + 03-04 |
| NoteSearchTests.swift | matchesTitleAndBlockText | 03-04 |
| AutoSaveTests.swift | debounceCommitsAfterQuiet | 03-05 |
| NotificationSchedulerTests.swift | All 3 tests | 03-03 |
| RecurrenceTests.swift | afterNStops, endOnDateStops | 03-03 |
| CalendarAggregationTests.swift | perDayCountsAndProgress | 03-04 |
| MigrationTests.swift | v2StoreMigratesToV3 | 03-02 |

## Threat Surface Scan

No new network endpoints, auth paths, file access patterns beyond the bundled fixture (first-party, script-generated). T-03-01 (SchemaV2/entity-name fidelity) mitigated: generator mirrors SchemaV2 verbatim. No threat flags.

## Self-Check: PASSED

- `MyHomeTests/Support/SpyCenter.swift` — exists
- `MyHomeTests/NoteModelTests.swift` — exists
- `MyHomeTests/NotificationSchedulerTests.swift` — exists (references SpyCenter)
- `MyHomeTests/MigrationTests.swift` — extended with v2StoreMigratesToV3
- `MyHomeTests/Resources/MyHomeV2Seed.store` — exists (86016 bytes)
- Commits decf85a, 21017ac, 9477f4c — exist
- Phase 1/2 tests: ALL PASS (no regression)
- Phase 3 Wave 0 stubs: ALL FAIL via Issue.record (not compile errors)

## Next Phase Readiness

- Plan 03-02 can now write `SchemaV3` + `Note` + `NoteBlock` models and turn `noteWithTitlePersists`, `blockListPreservesOrder`, `v2StoreMigratesToV3` green
- Plan 03-03 can write `NotificationScheduler.buildRequests` against the `NotificationCenterPort`/`SpyCenter` seam and turn the scheduler + recurrence stubs green
- Plan 03-04 can implement ordering/search/calendar helpers and turn those stubs green
- Plan 03-05 can implement UI + auto-save debounce and turn `debounceCommitsAfterQuiet` green

---
*Phase: 03-notes-checklists*
*Completed: 2026-05-30*
