---
phase: 03-notes-checklists
plan: 04
subsystem: list-search
tags: [pure-function, notes, search, calendar, tdd, bdd, wave-3]

requires:
  - phase: 03-notes-checklists
    plan: 02
    provides: Note/NoteBlock @Models, ReminderValueTypes (RecurrenceType/ReminderRecurrence)
  - phase: 03-notes-checklists
    plan: 03
    provides: NotificationScheduler, ReminderInfo, ReminderValueTypes made public+Sendable

provides:
  - NoteListOrganizer: pure enum partitioning [Note] into Daily Routine / Pinned / Other (NOT-03/04, SC-R5)
  - NoteSearchFilter: pure enum with matches(_:query:) + filter(_:query:) using localizedCaseInsensitiveContains (NOT-06)
  - CalendarAggregator: pure enum with perDayCounts(for:) + progress(for:notes:) + DayProgress value type (SC-R4)
  - NoteListOrderingTests: 3/3 GREEN (sectionOrdering, pinMovesToPinnedSection, dailyRoutineFilter)
  - NoteSearchTests: 1/1 GREEN (matchesTitleAndBlockText)
  - CalendarAggregationTests: 1/1 GREEN (perDayCountsAndProgress)

affects: [03-05-ui, 03-06-notifications-calendar]

tech-stack:
  added: []
  patterns:
    - Pure static helper pattern (BudgetCalculator discipline): arrays in / values out, no SwiftData, no @Query
    - localizedCaseInsensitiveContains for type-safe in-memory search (no SQL injection surface)
    - Device-timezone startOfDay bucketing for calendar aggregation (Pitfall 5 mitigation)
    - noteIsChecked guard: note-level reminder "done" = all blocks checked (graceful nil fallback to false)

key-files:
  created:
    - MyHomeApp/Support/NoteListOrganizer.swift
    - MyHomeApp/Support/NoteSearchFilter.swift
    - MyHomeApp/Support/CalendarAggregator.swift
  modified:
    - MyHomeTests/NoteListOrderingTests.swift
    - MyHomeTests/NoteSearchTests.swift
    - MyHomeTests/CalendarAggregationTests.swift
    - MyHome.xcodeproj/project.pbxproj

key-decisions:
  - "Helpers are internal (not public) — Note/NoteBlock are internal SwiftData @Models; public access modifier would cause compiler errors referencing internal types from public API"
  - "Daily Routine filter checks note-level reminderRecurrenceData only — block-level recurrence does not affect section placement (per plan spec)"
  - "noteIsChecked for note-level calendar reminders = all blocks checked; gracefully returns false for notes with no blocks"
  - "DayProgress.fraction has zero-divide guard: returns 0.0 when total == 0"

metrics:
  duration: 20min
  completed: 2026-05-30
  tasks_completed: 2
  files_modified: 7
---

# Phase 03 Plan 04: NoteListOrganizer + NoteSearchFilter + CalendarAggregator Summary

**Three pure static helpers (BudgetCalculator discipline) for Notes list sectioning, full-text search, and calendar aggregation; NoteListOrderingTests (3), NoteSearchTests (1), CalendarAggregationTests (1) all GREEN**

## Performance

- **Duration:** ~20 min
- **Started:** 2026-05-30T17:38:00Z
- **Completed:** 2026-05-30T17:58:00Z
- **Tasks:** 2
- **Files modified:** 7 (3 created, 4 modified)

## Accomplishments

- Created `NoteListOrganizer.swift`: pure enum with `NoteListSections` value type and `organize(_ notes:)` static method; partitions [Note] into `dailyRoutine` (note-level recurrence == .daily), `pinned` (isPinned && not daily), `other` (rest, preserving input order)
- Created `NoteSearchFilter.swift`: pure enum with `matches(_:query:)` (title + all block text via `localizedCaseInsensitiveContains`) and `filter(_:query:)` convenience; empty query returns full array unchanged (no-filter state)
- Created `CalendarAggregator.swift`: pure enum with `DayProgress` value type, `perDayCounts(for:)` returning `[Date: Int]` keyed by device-timezone start-of-day, and `progress(for:notes:)` returning per-day done/total counts; handles both note-level and block-level reminders
- Implemented `NoteListOrderingTests` (3 tests: sectionOrdering, pinMovesToPinnedSection, dailyRoutineFilter) — all GREEN
- Implemented `NoteSearchTests` (1 test: matchesTitleAndBlockText) — GREEN
- Implemented `CalendarAggregationTests` (1 test: perDayCountsAndProgress) — GREEN
- All Phase 1/2 tests + NoteModelTests + MigrationTests + NotificationSchedulerTests + RecurrenceTests remain GREEN
- AutoSaveTests/debounceCommitsAfterQuiet still fails via Issue.record (intentional Wave 0 stub, resolves in plan 03-05)
- Wired all three new source files into MyHome app target in project.pbxproj

## Task Commits

1. **Task 1: GREEN NoteListOrganizer + NoteSearchFilter** — `4a99aa1` (feat)
2. **Task 2: GREEN CalendarAggregator** — `8ce0c09` (feat)

## TDD Gate Compliance

- RED gate: NoteListOrderingTests + NoteSearchTests + CalendarAggregationTests all failed via Issue.record before this plan (Wave 0 stubs from plan 03-01) — confirmed by pre-implementation test run
- GREEN gate: All 5 tests pass after implementation — tasks 4a99aa1, 8ce0c09
- No REFACTOR commit needed (no structural cleanup required after GREEN)

## Files Created/Modified

- `MyHomeApp/Support/NoteListOrganizer.swift` — `NoteListSections` struct + `NoteListOrganizer` enum with `organize(_:)` static method
- `MyHomeApp/Support/NoteSearchFilter.swift` — `NoteSearchFilter` enum with `matches(_:query:)` + `filter(_:query:)` static methods
- `MyHomeApp/Support/CalendarAggregator.swift` — `DayProgress` struct + `CalendarAggregator` enum with `perDayCounts(for:)` + `progress(for:notes:)` static methods
- `MyHomeTests/NoteListOrderingTests.swift` — 3 tests implemented (was Issue.record stubs)
- `MyHomeTests/NoteSearchTests.swift` — 1 test implemented (was Issue.record stub)
- `MyHomeTests/CalendarAggregationTests.swift` — 1 test implemented (was Issue.record stub)
- `MyHome.xcodeproj/project.pbxproj` — F142NLO/F143NSF/F144CA file refs + A142NLO/A143NSF/A144CA build files + G140 Support group entries + P001 Sources entries

## Decisions Made

- **Helpers are internal (not public)**: `Note` and `NoteBlock` are internal SwiftData @Model types. Declaring the helpers as `public enum` with parameters of type `Note` causes a Swift compiler error ("Property cannot be declared public because its type uses an internal type"). Changed all three helpers and `NoteListSections`/`DayProgress` to internal access (default, no modifier).
- **Daily Routine uses note-level recurrence only**: The spec says "notes whose reminderRecurrenceData decodes to .daily" — this is the note's own recurrence field, not block-level. Block-level recurrence is separate and does not affect section placement.
- **noteIsChecked semantics**: For note-level calendar reminders, "checked" state derives from blocks — if all blocks are checked, the reminder is done. If there are no blocks, returns false (cannot derive completion).

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] `public` access modifier incompatible with internal Note/NoteBlock types**
- **Found during:** Task 1 GREEN implementation — build error `Property cannot be declared public because its type uses an internal type`
- **Issue:** The plan's `<implementation>` description implied a public API; however, `Note` and `NoteBlock` are `internal` SwiftData @Model types. Declaring the helpers as `public` with `[Note]` parameters is a Swift compiler error.
- **Fix:** Removed `public` from `NoteListOrganizer`, `NoteListSections`, `NoteSearchFilter`, `CalendarAggregator`, and `DayProgress`. All remain accessible within the app module (internal is correct since all callers are in the same module).
- **Files modified:** NoteListOrganizer.swift, NoteSearchFilter.swift, CalendarAggregator.swift
- **Commit:** 4a99aa1

## Threat Surface Scan

No new network endpoints, auth paths, or file access patterns. T-03-08 mitigated: `NoteSearchFilter` uses Swift `localizedCaseInsensitiveContains` over fetched arrays — no raw query strings, no SQL injection surface. T-03-09 mitigated: `CalendarAggregator` and `NoteSearchFilter` return values only; no title/block content is logged.

## Known Stubs

None in this plan. All three helpers are fully implemented.

Remaining Wave 0 stub (other plan, intentional Issue.record scaffolding):

| File | Stub | Resolving Plan |
|------|------|---------------|
| AutoSaveTests.swift | debounceCommitsAfterQuiet | 03-05 |

## Self-Check: PASSED

- `MyHomeApp/Support/NoteListOrganizer.swift` — exists
- `MyHomeApp/Support/NoteSearchFilter.swift` — exists
- `MyHomeApp/Support/CalendarAggregator.swift` — exists
- NoteListOrderingTests: 3/3 PASS (sectionOrdering, pinMovesToPinnedSection, dailyRoutineFilter)
- NoteSearchTests: 1/1 PASS (matchesTitleAndBlockText)
- CalendarAggregationTests: 1/1 PASS (perDayCountsAndProgress)
- All Phase 1/2 + NoteModelTests + MigrationTests + NotificationSchedulerTests + RecurrenceTests: ALL PASS
- AutoSaveTests/debounceCommitsAfterQuiet: FAIL via Issue.record (correct — pending plan 03-05)
- Commits 4a99aa1, 8ce0c09 — exist

---
*Phase: 03-notes-checklists*
*Completed: 2026-05-30*
