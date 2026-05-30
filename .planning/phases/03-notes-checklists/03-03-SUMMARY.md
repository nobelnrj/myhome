---
phase: 03-notes-checklists
plan: 03
subsystem: notifications
tags: [usernotifications, scheduler, recurrence, tdd, pure-function, protocol-port, 64-cap, wave-2]

requires:
  - phase: 03-notes-checklists
    plan: 01
    provides: NotificationCenterPort protocol seam + SpyCenter test double + NotificationSchedulerTests/RecurrenceTests stubs
  - phase: 03-notes-checklists
    plan: 02
    provides: ReminderValueTypes (RecurrenceType/ReminderRecurrence/EndRuleType/ReminderEndRule)

provides:
  - NotificationCenterPort protocol (public) in MyHomeApp/Support/NotificationCenterPort.swift
  - SystemNotificationCenter production conformer wrapping UNUserNotificationCenter.current()
  - NotificationScheduler struct with pure buildRequests(for:occurrenceIndex:) + schedule/cancel/pendingCount
  - ReminderInfo public Sendable value type (replaces placeholder from plan 03-01)
  - All ReminderValueTypes now public+Sendable (RecurrenceType/ReminderRecurrence/EndRuleType/ReminderEndRule)
  - NotificationSchedulerTests: 3/3 GREEN (buildRequestsLeadAlerts, weeklyMultiWeekday, pendingCountUnderCap)
  - RecurrenceTests: 2/2 GREEN (afterNStops, endOnDateStops)

affects: [03-04-list-search, 03-05-ui, 03-06-notifications-calendar]

tech-stack:
  added: []
  patterns:
    - Pure buildRequests pattern: no async/OS I/O in the core function, deterministic identifiers, fully testable via SpyCenter
    - 64-cap budget enforcement in schedule(): count existing pending before admitting new requests
    - Deterministic identifier scheme: <uuid>-main, <uuid>-lead-N, <uuid>-weekday-N for exact cancel-by-identifier
    - End-rule guards at top of buildRequests: onDate (date > endDate → []), afterCount (occurrenceIndex >= count → [])
    - Device-timezone DateComponents: converts UTC date via Calendar.current with TimeZone.current (Pitfall 5)

key-files:
  created:
    - MyHomeApp/Support/NotificationCenterPort.swift
    - MyHomeApp/Support/NotificationScheduler.swift
  modified:
    - MyHomeApp/Persistence/Models/ReminderValueTypes.swift
    - MyHomeTests/Support/SpyCenter.swift
    - MyHomeTests/NotificationSchedulerTests.swift
    - MyHomeTests/RecurrenceTests.swift
    - MyHome.xcodeproj/project.pbxproj

key-decisions:
  - "NotificationCenterPort protocol moved to production file (NotificationCenterPort.swift); SpyCenter.swift now imports it via @testable import MyHome instead of redeclaring"
  - "ReminderInfo defined in NotificationScheduler.swift (not in test file) — final Codable shape with ReminderRecurrence + ReminderEndRule fields"
  - "ReminderValueTypes types made public+Sendable — required because NotificationScheduler (public struct in app module) references them in its public API"
  - "buildRequests is pure (no async, no UNUserNotificationCenter access) — asserted directly in tests without SpyCenter for the pure-logic tests"
  - "64-cap budget: schedule() counts existing pending via pendingCount() before adding new requests, admitting at most (64 - existing) requests"

metrics:
  duration: 35min
  completed: 2026-05-30
  tasks_completed: 1
  files_modified: 7
---

# Phase 03 Plan 03: NotificationScheduler + NotificationCenterPort Summary

**Pure buildRequests(for:) with recurrence expansion, end-rule guards, lead-time alerts, 64-cap budget, and deterministic cancel identifiers; SystemNotificationCenter production conformer; all 5 scheduler+recurrence tests GREEN**

## Performance

- **Duration:** ~35 min
- **Started:** 2026-05-30T10:37:26Z
- **Completed:** 2026-05-30T11:12:00Z
- **Tasks:** 1
- **Files modified:** 7 (2 created, 5 modified)

## Accomplishments

- Created `NotificationCenterPort.swift` with the public `NotificationCenterPort` protocol (moved from SpyCenter test file) and `SystemNotificationCenter` final class wrapping `UNUserNotificationCenter.current()` for all four members (`requestAuthorization`, `add`, `removePendingNotificationRequests`, `pendingNotificationRequests`)
- Created `NotificationScheduler.swift` as a `struct` holding `let center: any NotificationCenterPort`; defined `ReminderInfo` public Sendable value type with decoded `ReminderRecurrence` + `ReminderEndRule` fields and `leadMinutes: [Int]`
- Implemented pure `buildRequests(for:occurrenceIndex:) throws -> [UNNotificationRequest]`: end-rule guards (onDate, afterCount), all-day vs timed DateComponents (device timezone), recurrence expansion (none=one-shot, daily, weekly-multiweekday=one trigger per weekday, monthly, yearly), lead-time alerts for one-shot reminders, deterministic identifier scheme
- Implemented `schedule(_:)` with 64-cap budget enforcement, `cancel(reminderID:leadCount:weekdays:)` using deterministic identifier set, and `pendingCount()` delegating to port
- Updated `ReminderValueTypes.swift`: all four types now `public` + `Sendable` (required for cross-module reference from public NotificationScheduler)
- Updated `SpyCenter.swift`: removed duplicate `NotificationCenterPort` protocol definition, updated `ReminderInfo` fixture builders to use finalized Codable shape
- Implemented `NotificationSchedulerTests` (3 tests) and `RecurrenceTests` (2 tests) — all 5 GREEN; all prior tests remain GREEN (Phase 1+2 + NoteModelTests + MigrationTests)

## Task Commits

1. **Task 1: GREEN NotificationScheduler + NotificationCenterPort** — `6c9c04f` (feat)

## TDD Gate Compliance

- RED gate: All 5 tests failed via `Issue.record` before this plan (Wave 0 stubs from plan 03-01) — confirmed by pre-implementation test run
- GREEN gate: All 5 tests pass after implementation — `6c9c04f`
- No REFACTOR commit needed (no structural cleanup required after GREEN)

## Files Created/Modified

- `MyHomeApp/Support/NotificationCenterPort.swift` — `NotificationCenterPort` public protocol + `SystemNotificationCenter` production conformer
- `MyHomeApp/Support/NotificationScheduler.swift` — `ReminderInfo` value type + `NotificationScheduler` struct (pure buildRequests + schedule/cancel/pendingCount)
- `MyHomeApp/Persistence/Models/ReminderValueTypes.swift` — all types made `public` + `Sendable`; explicit memberwise inits added
- `MyHomeTests/Support/SpyCenter.swift` — removed duplicate protocol; updated ReminderInfo fixture builders to use finalized shape
- `MyHomeTests/NotificationSchedulerTests.swift` — 3 tests implemented (buildRequestsLeadAlerts, weeklyMultiWeekday, pendingCountUnderCap)
- `MyHomeTests/RecurrenceTests.swift` — 2 tests implemented (afterNStops, endOnDateStops)
- `MyHome.xcodeproj/project.pbxproj` — F140NCP/F141NS file refs + A140NCP/A141NS build files + G140 Support group entries + P001 Sources entries

## Decisions Made

- **Protocol moved to production file**: The `NotificationCenterPort` protocol was in `SpyCenter.swift` (test file) as a Wave 0 placeholder per plan 03-01's decision. Plan 03-03 moves it to `NotificationCenterPort.swift` in the app target so `SystemNotificationCenter` can conform in the same module. `SpyCenter.swift` now imports it via `@testable import MyHome`.
- **ReminderValueTypes made public**: The plan's `ReminderInfo` is a `public struct` in the app module; its stored properties reference `ReminderRecurrence` and `ReminderEndRule`. Swift 6 strict concurrency requires these types to be `public` + `Sendable` for cross-module `Sendable`-conforming structs. All four types in `ReminderValueTypes.swift` updated.
- **Explicit memberwise inits added**: Swift synthesizes memberwise inits as `internal`; adding explicit `public init(...)` is required for types used in the public API surface.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 2 - Missing Critical Functionality] ReminderValueTypes visibility**
- **Found during:** Task 1 GREEN implementation — build error `struct 'ReminderRecurrence' is internal and cannot be referenced from a default argument value`
- **Issue:** `NotificationScheduler` and `ReminderInfo` are public; their stored property types (`ReminderRecurrence`, `ReminderEndRule`, `RecurrenceType`, `EndRuleType`) were internal. Swift 6 strict concurrency also requires `Sendable` for all stored properties of a `Sendable` struct.
- **Fix:** Added `public` + `Sendable` conformances to all four types in `ReminderValueTypes.swift`; added explicit `public init(...)` to `ReminderRecurrence` and `ReminderEndRule`
- **Files modified:** `ReminderValueTypes.swift`
- **Commit:** 6c9c04f

**2. [Rule 1 - Bug] `var comps` unused-mutation warning (daily case)**
- **Found during:** Task 1 — Swift compiler warning on `var comps` that was never mutated in the `.daily` recurrence case
- **Fix:** Changed `var comps` to `let comps`
- **Files modified:** `NotificationScheduler.swift`
- **Commit:** 6c9c04f

## Known Stubs

No stubs in this plan. All production scheduler logic is fully implemented.

Remaining Wave 0 stubs (other plans, intentional Issue.record scaffolding):

| File | Stub | Resolving Plan |
|------|------|---------------|
| NoteListOrderingTests.swift | sectionOrdering, pinMovesToPinnedSection, dailyRoutineFilter | 03-04 |
| NoteSearchTests.swift | matchesTitleAndBlockText | 03-04 |
| AutoSaveTests.swift | debounceCommitsAfterQuiet | 03-05 |
| CalendarAggregationTests.swift | perDayCountsAndProgress | 03-04 |

## Threat Surface Scan

No new network endpoints or auth paths. T-03-05 (cap exhaustion) mitigated: `schedule()` enforces 64-cap budget; `pendingCountUnderCap` test asserts ≤ 64 under load. T-03-06 (orphaned requests) mitigated: deterministic identifier scheme used in `cancel()`. T-03-07 (info disclosure) mitigated: `makeRequest()` logs identifier/count only; note body text is never included in notification content here.

## Self-Check: PASSED

- `MyHomeApp/Support/NotificationCenterPort.swift` — exists
- `MyHomeApp/Support/NotificationScheduler.swift` — exists
- NotificationSchedulerTests: 3/3 PASS (buildRequestsLeadAlerts, weeklyMultiWeekday, pendingCountUnderCap)
- RecurrenceTests: 2/2 PASS (afterNStops, endOnDateStops)
- Phase 1/2 tests + NoteModelTests + MigrationTests: ALL PASS (no regression)
- Wave 0 stubs (NoteListOrderingTests, NoteSearchTests, AutoSaveTests, CalendarAggregationTests): still FAIL via Issue.record (correct — pending plans 03-04/05)
- Commit 6c9c04f — exists

---
*Phase: 03-notes-checklists*
*Completed: 2026-05-30*
