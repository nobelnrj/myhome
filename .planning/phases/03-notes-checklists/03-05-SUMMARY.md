---
phase: 03-notes-checklists
plan: 05
subsystem: ui
tags: [swiftui, swiftdata, notes, auto-save, debounce, block-editor, searchable]

# Dependency graph
requires:
  - phase: 03-04
    provides: NoteListOrganizer, NoteSearchFilter, CalendarAggregator pure helpers
  - phase: 03-02
    provides: Note/NoteBlock @Models, SchemaV3, ModelContainer factory
provides:
  - Notes tab with List|Calendar segmented host (calendar placeholder wired for 03-06)
  - NotesListView: sectioned (Daily Routine → Pinned → Other) + .searchable + empty state
  - NoteRow: title, pin toggle, reminder-count badge, checked-row strikethrough+dimmed
  - AddNoteView + EditNoteView: block editor with debounced ~500ms auto-save, no save button
  - Discard-on-empty-title (context.delete on dismiss)
  - Date+Display.swift reminder date/time + calendar label formatters
  - RootView Notes tab slot
affects: [03-06, 04-01]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - Debouncer helper isolating 500ms auto-save debounce from SwiftUI view lifecycle
    - isDirty @State mirror gating saves (matches EditExpenseView pattern)
    - Parent-sheet-coordinated handoff replacing nested .sheet presentation to avoid blank-overlay bug
    - NoteListOrganizer consumed via computed property in @Query-driven list view

key-files:
  created:
    - MyHomeApp/Features/Notes/NotesHomeView.swift
    - MyHomeApp/Features/Notes/NotesListView.swift
    - MyHomeApp/Features/Notes/NoteRow.swift
    - MyHomeApp/Features/Notes/AddNoteView.swift
    - MyHomeApp/Features/Notes/EditNoteView.swift
  modified:
    - MyHomeApp/Support/Date+Display.swift
    - MyHomeApp/RootView.swift
    - MyHome.xcodeproj/project.pbxproj

key-decisions:
  - "Debouncer extracted into a small testable unit so AutoSaveTests/debounceCommitsAfterQuiet can run headlessly without SwiftUI view"
  - "AddNoteView inserts a Note immediately on confirm and passes it to EditNoteView via parent-coordinated sheet, avoiding the nested-sheet blank-overlay SwiftUI bug"
  - "In-memory NoteSearchFilter applied in a computed property on @Query results (no predicate push-down) per Open Q3 decision from research"
  - "Calendar segment left as ContentUnavailableView stub with a clearly-marked hook; filled in 03-06"

patterns-established:
  - "Parent-coordinated sheet handoff: parent creates the model and flips a Bool to present the editor sheet — avoids nested .sheet blank overlay"
  - "Debouncer unit: isolate debounce logic from SwiftUI so it is unit-testable without a view"

requirements-completed: [NOT-01, NOT-02, NOT-03, NOT-04, NOT-05, NOT-06]

# Metrics
duration: ~90min
completed: 2026-05-30
---

# Phase 3 Plan 05: Notes UI + Tab Wiring Summary

**SwiftUI Notes tab with sectioned searchable list, block editor, debounced auto-save, and discard-on-empty-title — NOT-01..06 now user-observable**

## Performance

- **Duration:** ~90 min
- **Started:** 2026-05-30T18:00:00Z
- **Completed:** 2026-05-30T20:00:00Z
- **Tasks:** 3 (plus 1 UAT bug fix)
- **Files modified:** 8

## Accomplishments

- Notes tab with List|Calendar segmented host lands in the TabView; calendar branch stubbed cleanly for 03-06
- Sectioned (Daily Routine → Pinned → Other) searchable list using NoteListOrganizer and NoteSearchFilter from 03-04
- Block editor (interleaved text + checkbox blocks) with debounced ~500ms auto-save, no save button; checked rows sink struck-through+dimmed
- Discard-on-empty-title: note deleted from context on dismiss if title is blank
- AutoSaveTests/debounceCommitsAfterQuiet GREEN; human UAT on iPhone 17 simulator APPROVED

## Task Commits

Each task was committed atomically:

1. **Task 1: NotesHomeView + NotesListView + NoteRow + RootView tab + Date+Display** - `f30b75a` (feat)
2. **Task 2: AddNoteView + EditNoteView — block editor, debounced auto-save, discard-on-empty-title** - `e6f098a` (feat + test GREEN)
3. **UAT Bug Fix: nested-sheet blank overlay** - `392fd19` (fix)
4. **Task 3: Manual UAT checkpoint** - verified on iPhone 17 simulator, APPROVED

**Plan metadata:** (this SUMMARY commit)

## Files Created/Modified

- `MyHomeApp/Features/Notes/NotesHomeView.swift` — Notes tab root: NavigationStack + List|Calendar segmented Picker; calendar branch stubs to ContentUnavailableView hook for 03-06
- `MyHomeApp/Features/Notes/NotesListView.swift` — @Query + NoteListOrganizer sections + .searchable (NoteSearchFilter) + toolbar + empty state
- `MyHomeApp/Features/Notes/NoteRow.swift` — Title headline, pin toggle (accent + explicit save), reminder-count badge, checked rows strikethrough+0.6 opacity
- `MyHomeApp/Features/Notes/AddNoteView.swift` — Creates Note immediately on confirm, passes to EditNoteView via parent-coordinated Bool; discard if title empty on cancel
- `MyHomeApp/Features/Notes/EditNoteView.swift` — @Bindable Note block editor; Debouncer unit ~500ms; isDirty gate; discard-on-empty-title; checkbox re-sort; reminder hook comment
- `MyHomeApp/Support/Date+Display.swift` — Extended with reminder date/time label + calendar day/month formatters (Calendar.current display, UTC stored)
- `MyHomeApp/RootView.swift` — Notes tab added: `NotesHomeView().tabItem { Label("Notes", systemImage: "note.text") }`
- `MyHome.xcodeproj/project.pbxproj` — All 5 new view files added to MyHome app target

## Decisions Made

- Debouncer extracted as a small testable struct/actor so AutoSaveTests can run without a view; mirrors the `isDirty` gating from EditExpenseView.
- In-memory NoteSearchFilter (not a SwiftData predicate) per Open Q3: title + block text filtering with Swift `contains` — acceptable at v1 note volumes.
- Calendar segment is a `ContentUnavailableView("No Reminders Yet")` stub with a `// HOOK(03-06): replace with CalendarView` comment; no partial implementation committed.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Fixed nested-sheet blank overlay in AddNoteView / NotesListView**
- **Found during:** Task 3 UAT — note-add flow showed a blank white overlay on the first tap of +
- **Issue:** AddNoteView presented EditNoteView as a `.sheet` from inside a `.sheet` already presented by NotesListView. SwiftUI does not support nested `.sheet` presentation reliably; the inner sheet appeared as a blank overlay, blocking interaction.
- **Fix:** Replaced the nested-sheet pattern with a parent-coordinated handoff: NotesListView owns a single `@State var noteToEdit: Note?` Bool pair; AddNoteView inserts the Note into the model context and signals the parent via a closure; the parent dismisses AddNoteView and immediately presents EditNoteView. Single active sheet at all times.
- **Files modified:** `MyHomeApp/Features/Notes/AddNoteView.swift`, `MyHomeApp/Features/Notes/NotesListView.swift`
- **Verification:** UAT step 2 re-verified — note-add flow opens correctly, block editor appears without blank overlay
- **Committed in:** `392fd19`

---

**Total deviations:** 1 auto-fixed (Rule 1 — bug)
**Impact on plan:** Fix was essential for note creation to work end-to-end. No scope creep; no new features added.

## Issues Encountered

- Nested `.sheet` blank overlay (see Deviations). Root cause: SwiftUI limitation — only one `.sheet` should be active on a given view hierarchy at a time. Resolved by parent-coordinated handoff pattern (now documented in `patterns-established`).

## User Setup Required

None — no external service configuration required.

## Next Phase Readiness

- 03-06 can wire `ReminderEditView` directly into the reminder hook comment left in `EditNoteView` and fill the Calendar segment hook in `NotesHomeView`.
- `Date+Display.swift` formatters for calendar day/month labels are already present.
- `NotificationScheduler` and `NotificationCenterPort` from 03-03 are ready to be called from 03-06's reminder flow.
- All NOT-01..06 requirements are observable; NOT-07..10 (reminders, recurrence, notifications, calendar) are gated on 03-06.

---
*Phase: 03-notes-checklists*
*Completed: 2026-05-30*
