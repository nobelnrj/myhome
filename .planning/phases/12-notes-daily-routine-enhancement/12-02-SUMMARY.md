---
phase: 12-notes-daily-routine-enhancement
plan: "02"
subsystem: features/notes
tags: [streak-algorithm, notifications, pure-function, daily-routine, d-07, d-05]
dependency_graph:
  requires: [12-01]
  provides: [StreakCalculator, RoutineNotificationService]
  affects: [wave-3-ui-plans, EditNoteView, RoutineDetailView]
tech_stack:
  added: [StreakCalculator, RoutineNotificationService]
  patterns: [pure-injectable-function, cancel-then-add, stable-notification-id, ist-calendar-injection]
key_files:
  created:
    - MyHomeApp/Features/Notes/StreakCalculator.swift
    - MyHomeApp/Features/Notes/RoutineNotificationService.swift
  modified:
    - MyHomeTests/StreakCalculatorTests.swift
    - MyHomeTests/RoutineNotificationServiceTests.swift
    - MyHome.xcodeproj/project.pbxproj
decisions:
  - "StreakCalculator.compute injects today + IST calendar — no Date() call internally; deterministic in tests"
  - "D-07 forgiving streak: startOffset = todayCompleted ? 0 : 1; first miss breaks streak; cap at 30"
  - "RoutineNotificationService uses cancel-then-add ordering (synchronous cancel, async add) per D-05 Pitfall 3"
  - "Stable identifier 'routine-daily-{uuidString}' avoids collision with NotificationScheduler and SIP domains"
  - "T-12-05: userInfo carries only noteID + isRoutineReminder — no note body text leaked to lock screen"
metrics:
  duration: "~25 minutes"
  completed: "2026-06-13"
  tasks_completed: 2
  tasks_total: 2
  files_created: 2
  files_modified: 3
---

# Phase 12 Plan 02: StreakCalculator + RoutineNotificationService Summary

StreakCalculator pure D-07 forgiving streak algorithm (injectable IST calendar + today) and RoutineNotificationService daily notification with cancel-then-add D-05 single-pending guarantee — both implemented, pbxproj registered, all tests green.

## What Was Built

### Task 1: StreakCalculator pure algorithm (D-07) — commit bfa386f

- **StreakCalculator.swift**: `enum StreakCalculator` with `static func compute(for:completions:today:calendar:) -> StreakResult`.
  - `struct DayStatus { let dayKey: Date; let isCompleted: Bool }` — one entry per day in the 30-day window.
  - `struct StreakResult { let currentStreak: Int; let history: [DayStatus] }` — 30 entries, newest first.
  - D-07 forgiving rule: `startOffset = todayCompleted ? 0 : 1` — incomplete today does not break the streak; only a fully-missed past day breaks it.
  - Filters completions to `noteID` before building the completed-days Set — cross-note records ignored.
  - `today` and `calendar` injected as parameters; no `Date()` call internally.
  - 30-day history window built using `calendar.date(byAdding: .day, value: -offset, to: todayKey)`.
  - Streak walk capped at offset < 30.
- **StreakCalculatorTests.swift**: 8 test cases all GREEN:
  - `streakIsZeroWithNoCompletions` — baseline: empty completions → streak 0, all history false
  - `incompleteToday_doesNotBreakStreak` — D-07: today not completed, yesterday+day-before → streak 2
  - `streakBreaksOnMissedDay` — D-07: gap at -2 → streak only 1 (yesterday only)
  - `completingTodayExtendsStreak` — D-07: today+yesterday+day-before → streak 3
  - `idempotentCompletion` — D-08: second upsert on same day produces 1 row, not 2
  - `crossNoteCompletionsIgnored` — only `otherNoteID` completions → streak 0 for queried noteID
  - `historyAlwaysHas30Entries` — history.count == 30 in all cases
  - `uuidPredicateFetchCompiles` — OQ-1 confirmed green from 12-01
- **project.pbxproj**: 4 entries each for StreakCalculator.swift and RoutineNotificationService.swift added in this commit (PBXBuildFile, PBXFileReference, G123 Notes group, P001 SourcesBuildPhase).

### Task 2: RoutineNotificationService daily notification (D-05) — commit 75ca11e

- **RoutineNotificationService.swift**: `struct RoutineNotificationService` with injectable `NotificationCenterPort`.
  - `static func identifier(for noteID: UUID) -> String` → `"routine-daily-\(noteID.uuidString)"`.
  - `func schedule(noteID:title:time:) async`: synchronous `cancel(noteID:)` first, then builds time-only `DateComponents([.hour, .minute])` from `time`, creates `UNCalendarNotificationTrigger(dateMatching: comps, repeats: true)`, sets `content.categoryIdentifier = kReminderCategoryID`, `content.userInfo = ["noteID": ..., "isRoutineReminder": "true"]` (T-12-05 — no note body), and `try? await center.add(request)`.
  - `func cancel(noteID:)`: `center.removePendingNotificationRequests(withIdentifiers: [Self.identifier(for: noteID)])`.
- **RoutineNotificationServiceTests.swift**: 8 test cases all GREEN:
  - `identifierHasCorrectPrefix` — stable "routine-daily-" prefix
  - `rescheduleIsAtomicCancelThenAdd` — cancel called before add; 2 cancels after 2 schedules; 1 pending
  - `exactlyOnePendingRequest` — 3 schedules → exactly 1 pending (D-05 no stacking)
  - `cancelRemovesPendingRequest` — after schedule + cancel → 0 pending
  - `cancelIsNoteSpecific` — cancelling note1 does not affect note2's pending request
  - `userInfoHasExactlyNoteIDAndRoutineFlag` — 2 keys only: noteID + isRoutineReminder (T-12-05)
  - `categoryIdentifierIsReminder` — `content.categoryIdentifier == kReminderCategoryID`
  - `triggerIsCalendarRepeating` — trigger is `UNCalendarNotificationTrigger` with `repeats: true`

## Public Signatures (for Wave-3 UI wiring)

```swift
// StreakCalculator.swift
struct DayStatus { let dayKey: Date; let isCompleted: Bool }
struct StreakResult { let currentStreak: Int; let history: [DayStatus] }

enum StreakCalculator {
    static func compute(
        for noteID: UUID,
        completions: [RoutineCompletion],
        today: Date,
        calendar: Calendar
    ) -> StreakResult
}

// Usage in a SwiftUI view (inject IST calendar):
var istCal = Calendar(identifier: .gregorian)
istCal.timeZone = TimeZone(identifier: "Asia/Kolkata")!
let result = StreakCalculator.compute(for: note.id, completions: completions, today: Date(), calendar: istCal)
// result.currentStreak — Int, display as "🔥 \(result.currentStreak) day streak"
// result.history       — [DayStatus], 30 entries newest-first

// RoutineNotificationService.swift
struct RoutineNotificationService {
    init(center: any NotificationCenterPort = SystemNotificationCenter())
    static func identifier(for noteID: UUID) -> String   // "routine-daily-{uuidString}"
    func schedule(noteID: UUID, title: String, time: Date) async
    func cancel(noteID: UUID)
}

// Usage:
await RoutineNotificationService().schedule(noteID: note.id, title: note.title, time: time)
RoutineNotificationService().cancel(noteID: note.id)
```

## Deviations from Plan

### Deviation: RoutineNotificationService created in Task 1 context

**Context:** Both app files (StreakCalculator.swift and RoutineNotificationService.swift) were registered in pbxproj in a single edit block (Task 1). Since the build requires both referenced files to exist, RoutineNotificationService.swift was created as a minimal placeholder before running the Task 1 test suite, then its test stubs were filled and committed in Task 2. This is a sequencing adjustment with no semantic impact — both tasks were committed individually as required.

None — plan executed exactly as written otherwise.

## Threat Surface Scan

No new network endpoints or auth paths. T-12-04 (D-05 duplicate notifications) is mitigated by the cancel-then-add pattern and confirmed by `exactlyOnePendingRequest` test. T-12-05 (notification userInfo payload) is mitigated by the 2-key-only userInfo and confirmed by `userInfoHasExactlyNoteIDAndRoutineFlag` test.

## Known Stubs

None — all test cases are fully implemented and passing.

## Self-Check: PASSED

- StreakCalculator.swift: FOUND at MyHomeApp/Features/Notes/StreakCalculator.swift
- RoutineNotificationService.swift: FOUND at MyHomeApp/Features/Notes/RoutineNotificationService.swift
- StreakCalculatorTests.swift (updated): FOUND
- RoutineNotificationServiceTests.swift (updated): FOUND
- Commit bfa386f (Task 1): FOUND
- Commit 75ca11e (Task 2): FOUND
- grep -c StreakCalculator.swift project.pbxproj: 4 (verified)
- grep -c RoutineNotificationService.swift project.pbxproj: 4 (verified)
- xcodebuild build: BUILD SUCCEEDED
- StreakCalculatorTests: 8/8 PASSED
- RoutineNotificationServiceTests: 8/8 PASSED
