---
phase: 12-notes-daily-routine-enhancement
plan: "04"
subsystem: features/notes
tags: [routine-calendar, day-agenda, dot-badge-invariance, stab-01, completion-recording, d-01, d-02, d-03, d-06, note-01]
dependency_graph:
  requires: [12-01, 12-02, 12-03]
  provides: [DayAgendaView-daily-routines-section, RoutineAgendaRow, RoutineCalendarTests]
  affects: [CalendarView.swift, pbxproj]
tech_stack:
  added: []
  patterns: [stab-01-tombstone-guard, fetch-before-insert-idempotency, query-init-capture-pitfall4, ist-calendar]
key_files:
  created:
    - MyHomeTests/RoutineCalendarTests.swift
  modified:
    - MyHomeApp/Features/Notes/CalendarView.swift
    - MyHome.xcodeproj/project.pbxproj
decisions:
  - "RoutineAgendaRow uses @Query with init-captured predicate (Pitfall 4) for text-only completion state — avoids FetchDescriptor in computed property"
  - "CalendarAggregator.swift left UNCHANGED — D-02 proven by RoutineCalendarTests without any aggregator modification"
  - "Section('Daily Routines') rendered conditionally (only when routineNotes non-empty) to avoid empty section header when user has no routines"
  - "remindersOnDay section wrapped in if !remindersOnDay.isEmpty to keep layout clean when only routines exist (matches UI-SPEC Surface 3 'routines exist but no reminders' state)"
metrics:
  duration: "~20 minutes"
  completed: "2026-06-13"
  tasks_completed: 2
  tasks_total: 2
  files_created: 1
  files_modified: 2
---

# Phase 12 Plan 04: DayAgendaView Daily Routines Section + RoutineCalendarTests Summary

DayAgendaView gains a tombstone-safe "Daily Routines" section at the top of every day's agenda, with RoutineAgendaRow providing check-time completion recording (checklist and text-only), without inflating the dot badge — proven by 5 green RoutineCalendarTests.

## What Was Built

### Task 1: DayAgendaView "Daily Routines" section + RoutineAgendaRow — commit 4042e6b

**CalendarView.swift changes (DayAgendaView):**

- **`@State private var editingRoutineNote: Note? = nil`** — state for sheet-based routine note editing.

- **`routineNotes` computed property** — filters `notes` to `isDailyRoutine == true` with STAB-01 tombstone guard (`guard note.modelContext != nil else { return false }`), sorted alphabetically by title. Tombstone guard matches the established pattern in `remindersOnDay`. Routine notes appear on EVERY day, driven purely by the `isDailyRoutine` flag — NOT by any reminder.

- **Empty-state gate updated** — changed from `remindersOnDay.isEmpty` to `remindersOnDay.isEmpty && routineNotes.isEmpty`. ContentUnavailableView updated to "Nothing Scheduled" / `systemImage: "calendar"` / "No routines or reminders for this day." (per UI-SPEC).

- **Body restructured:**
  1. `Section("Daily Routines")` rendered first (above progress header and reminders) when `routineNotes` non-empty — D-01/D-03
  2. Progress header section — unchanged
  3. Reminders section — wrapped in `if !remindersOnDay.isEmpty` to cleanly handle routine-only days

- **`.sheet(item: $editingRoutineNote)`** — opens `EditNoteView(note:)` when a routine row is tapped.

- **CalendarAggregator.swift** — UNCHANGED (confirmed via `git diff`). Routines never inflate the dot badge (D-02).

**RoutineAgendaRow (new private struct in CalendarView.swift):**

- `@Query private var todayCompletions: [RoutineCompletion]` — captured in `init(note:onTap:)` via `#Predicate<RoutineCompletion> { $0.noteID == noteID && $0.dayKey == dayKey }` with IST `startOfDay` key (Pitfall 4 compliance).

- **`isCompleteToday`** — checklist routines: `checkboxBlocks.allSatisfy(\.isChecked)`; text-only routines: `!todayCompletions.isEmpty` (live @Query).

- **Row layout** — 44pt completion indicator Button (`circle` in accentColor / `checkmark.circle.fill` in `.secondary`), title with `.strikethrough(isCompleteToday)`, status subtitle ("Daily at {time}" or "Daily routine"), inline `Button("Done today")` for text-only incomplete routines (`.buttonStyle(.bordered)`, `.font(.caption)`). Row tap calls `onTap()`.

- **`toggleAllBlocks()`** — sets all checkbox blocks `isChecked`, calls `recordCompletion()` when completing; for text-only, calls `recordCompletion()` if not already complete. Calls `try? context.save()` (mirrors `DayAgendaView.toggleCompletion` line 451).

- **`recordCompletion()`** — IST `startOfDay` dayKey; `FetchDescriptor<RoutineCompletion>` fetch-before-insert idempotency: updates `completedAt` if record exists, inserts new `RoutineCompletion(noteID:dayKey:)` otherwise. Calls `try? context.save()`. Mirrors `recordTodayCompletion()` from EditNoteView (12-03).

- **T-12-10 compliance** — all strings via plain `Text(...)`. Grep confirms no `AttributedString` usage in new code (comment-only reference).

### Task 2: RoutineCalendarTests — 5 tests, all green — commit bc92228

**MyHomeTests/RoutineCalendarTests.swift (new file):**

`makeContainer()` includes `Note.self, NoteBlock.self, RoutineCompletion.self` (in-memory).

| Test | What it proves |
|------|---------------|
| `routineNoteIncludedInFilter()` | isDailyRoutine == true note appears in the DayAgendaView.routineNotes filter predicate — NOTE-01 |
| `normalNoteExcludedFromFilter()` | isDailyRoutine == false note is excluded from filter — NOTE-01 |
| `routineWithoutReminderDoesNotProduceDotCount()` | CalendarAggregator.perDayCounts returns empty for a routine-only note with no reminderEnabled — D-02 |
| `routineWithReminderStillProducesDot()` | CalendarAggregator.perDayCounts returns 1 for a routine note that also has reminderEnabled — D-02 correct existing behaviour |
| `completionIsIdempotentPerDay()` | Two fetch-before-insert writes for same (noteID, IST dayKey) → exactly 1 RoutineCompletion row — D-06/D-08 |

The filter tests apply the same predicate used by `DayAgendaView.routineNotes` directly over seeded notes (not the SwiftUI view), making the filter logic independently testable.

**pbxproj registration (4 edits):**
- `A1204RCT /* RoutineCalendarTests.swift in Sources */` — PBXBuildFile entry
- `F1204RCT /* RoutineCalendarTests.swift */` — PBXFileReference entry
- `F1204RCT` added to MyHomeTests group children
- `A1204RCT` added to MyHomeTests PBXSourcesBuildPhase

`grep -c RoutineCalendarTests.swift project.pbxproj` → 4 (verified)

## routineNotes Filter Testability

The `routineNotes` computed property is private to `DayAgendaView` (a SwiftUI struct). Rather than exposing it via a testable static helper (which would require changing the production code), RoutineCalendarTests directly applies the same predicate (`guard note.modelContext != nil; return note.isDailyRoutine`) over seeded in-memory containers. This tests the exact boolean logic without coupling tests to the SwiftUI view struct.

## CalendarAggregator Unchanged — D-02 Confirmed

`CalendarAggregator.swift` has zero diff from the prior commit. The dot-badge invariance (D-02) is proven by `routineWithoutReminderDoesNotProduceDotCount()` which calls the real `CalendarAggregator.perDayCounts(for:)` with a routine-only note and asserts an empty result. No aggregator modification was needed or made.

## Deviations from Plan

None — plan executed exactly as written.

## Threat Surface Scan

No new network endpoints, auth paths, or schema changes. Threat mitigations applied:
- **T-12-09** (tombstone crash): `routineNotes` applies `guard note.modelContext != nil` STAB-01 idiom. Deleting a routine while the agenda sheet is open cannot fault.
- **T-12-07** (completion lost to midnight reset): `RoutineAgendaRow.recordCompletion()` writes `RoutineCompletion` at the moment of user action (check-time), before `RoutineResetService` can wipe `isChecked`.
- **T-12-10** (markdown injection): All strings in `RoutineAgendaRow` use plain `Text(...)`. `grep "AttributedString" CalendarView.swift` returns only the security comment — no runtime usage.

## Known Stubs

None — all functionality fully implemented and wired to real data.

## Self-Check: PASSED

- `MyHomeApp/Features/Notes/CalendarView.swift`: FOUND — contains `routineNotes`, `RoutineAgendaRow`, `editingRoutineNote`, `Section("Daily Routines")`, `routineNotes.isEmpty && remindersOnDay.isEmpty`, `Nothing Scheduled`
- `MyHomeTests/RoutineCalendarTests.swift`: FOUND — contains all 5 test functions
- `grep -c RoutineCalendarTests.swift project.pbxproj` → 4: VERIFIED
- `CalendarAggregator.swift` unchanged: CONFIRMED (git diff returns empty)
- No `AttributedString` in new CalendarView code: CONFIRMED (comment-only)
- `xcodebuild build -scheme MyHome -destination 'platform=iOS Simulator,name=iPhone 17'` → BUILD SUCCEEDED
- `xcodebuild test ... -only-testing:MyHomeTests/RoutineCalendarTests` → TEST SUCCEEDED (5/5 passed)
- Commit 4042e6b (Task 1): FOUND
- Commit bc92228 (Task 2): FOUND
