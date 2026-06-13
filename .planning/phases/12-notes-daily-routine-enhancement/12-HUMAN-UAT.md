---
status: pending
phase: 12-notes-daily-routine-enhancement
source: [12-05-PLAN.md, 12-VALIDATION.md]
started: 2026-06-13
updated: 2026-06-13
---

## Current Test

[awaiting human verification on the iPhone 17 simulator]

## Context

Phase 12 product code is complete and builds clean; all automated suites pass in
isolation (28 Phase-12 tests + every prior suite). These four behaviors are
runtime/lifecycle events that automated tests cannot cover. Run them on the
iPhone 17 simulator and record each outcome.

## Tests

### 1. NOTE-03 — daily notification fires exactly once (D-05)
steps: Open a note → toggle "Daily Routine" ON → enable "Daily Reminder" → set the time to ~2 minutes from now. Leave the editor and background the app. Then change the time and re-save.
expected: EXACTLY ONE banner arrives at the set time. After changing the time and re-saving, NO duplicate banner fires at the old time (single-pending guarantee).
result: pending

### 2. NOTE-04 — drag-to-reorder persists
steps: In a checklist note, tap the reorder toolbar button (arrow.up.arrow.down), drag items into a new order, tap Done to dismiss, reopen the note.
expected: The new checklist-item order holds after dismiss + reopen.
result: pending

### 3. NOTE-01 — every-day surfacing, no dot inflation (D-01/D-02)
steps: Mark a note as a Daily Routine. Open the calendar and tap several different days (past, today, future).
expected: The routine appears in a "Daily Routines" section on EVERY day. Day cells do NOT gain a new dot badge solely because of the routine.
result: pending

### 4. NOTE-05 — cross-midnight streak retention (D-07)
steps: Complete a routine today (tick all boxes, or tap "Done today"). Advance the simulator's date by one day. Reopen the app.
expected: Checkboxes reset for the new day, BUT the streak count and the RoutineDetailView 30-day history still show yesterday's completion (the completion record survived the reset).
result: pending

## Summary

total: 4
passed: 0
pending: 4

## Known caveat (not blocking these UAT items)

The *combined* full test suite (`xcodebuild test` over all suites in one process)
hits a non-deterministic SwiftData multi-`ModelContainer` cast crash
("Failed to cast model SchemaV9.Note/NoteBlock to Note/NoteBlock"). This is a
test-harness limitation exposed by adding the 9th versioned schema — NOT a product
defect (production runs exactly one container; every suite passes in isolation).
Tracked as a separate test-infrastructure follow-up. See
`.planning/todos/pending/test-isolation-swiftdata-multicontainer.md`.
