---
phase: 14-restyle-existing-screens-overview-donut
plan: "04"
subsystem: Notes
tags: [neumorphic, restyle, SKIN-04, SKIN-09, notes, calendar, reminders, routines]
dependency_graph:
  requires: ["14-01"]
  provides: ["Notes group neumorphic restyle"]
  affects: ["NotesHomeView", "NotesListView", "NoteRow", "AddNoteView", "EditNoteView", "CalendarView", "ReminderEditView", "RoutineDetailView"]
tech_stack:
  added: []
  patterns: ["neuSurface(.raised, isInteractive: true)", "DesignTokens.bgCanvas canvas background", "DesignTokens label tiers", "orange pin flag", "accent checked states"]
key_files:
  created: []
  modified:
    - MyHomeApp/Features/Notes/NotesHomeView.swift
    - MyHomeApp/Features/Notes/NotesListView.swift
    - MyHomeApp/Features/Notes/NoteRow.swift
    - MyHomeApp/Features/Notes/AddNoteView.swift
    - MyHomeApp/Features/Notes/EditNoteView.swift
    - MyHomeApp/Features/Notes/CalendarView.swift
    - MyHomeApp/Features/Notes/ReminderEditView.swift
    - MyHomeApp/Features/Notes/RoutineDetailView.swift
decisions:
  - "NoteRow card uses neuSurface(.raised, isInteractive: true) per UI-SPEC Screen 4 tappable contract"
  - "Pin flag uses DesignTokens.orange (not accent) per UI-SPEC Screen 4 component map"
  - "Checked checkbox icon uses DesignTokens.accent; unchecked uses label3 (not label2) to give clear contrast hierarchy"
  - "RoutineDetailView headerCard uses .padding(16).neuSurface(.raised) to supply its own padding matching the raised card pattern"
  - "Weekday picker selected text uses accentOnYellow (dark) over accent (yellow) bg for WCAG contrast"
metrics:
  duration: "~30 min"
  completed: "2026-06-22"
  tasks: 2
  files: 8
---

# Phase 14 Plan 04: Notes Group Neumorphic Restyle Summary

**One-liner:** Neumorphic restyle of all 8 Notes screen files — charcoal canvas, neuSurface cards, canary-yellow accent checked states, orange pin flags, and surfaceRaised list rows throughout the Notes/Calendar/Reminder/Routine group.

## Tasks Completed

| # | Task | Commit | Files |
|---|------|--------|-------|
| 1 | Restyle Notes home/list/row + editors (SKIN-04) | fe71e79 | NotesHomeView, NotesListView, NoteRow, AddNoteView, EditNoteView |
| 2 | Restyle calendar, reminder editor, routine detail (SKIN-04) | 7bc1cdd | CalendarView, ReminderEditView, RoutineDetailView |

## What Was Built

**Task 1 — Notes home/list/row/editors:**
- `NotesHomeView`: segmented header background `systemBackground` → `DesignTokens.bgCanvas`
- `NoteRow`: full card restyle — `.neuSurface(.raised, isInteractive: true)` wrapper; pin flag `DesignTokens.orange` at 16pt; title 16pt semibold `label`; checklist icon unchecked `label3` / checked `accent`; done text `label3` + strikethrough; preview body 14pt `label2`; reminder badge `accent` + 12% opacity bg capsule
- `NotesListView`: toolbar `+` button `accent`; section headers 13pt medium `label2` uppercased; list `scrollContentBackground(.hidden)` + `bgCanvas`; rows `listRowBackground(Color.clear)` + `listRowSeparator(.hidden)` with 6pt vertical insets
- `AddNoteView`: Add Note CTA `.tint(DesignTokens.accent)`
- `EditNoteView`: checkbox unchecked `label3` / checked `accent`; body text `label` / done `label3`; deep-link highlight `accent.opacity(0.15)`; ScrollView `.background(DesignTokens.bgCanvas)`; placeholder text `label2`

**Task 2 — Calendar/reminder/routine:**
- `RoutineDetailView`: `.cardStyle()` → `.padding(16).neuSurface(.raised)`; `systemGreen` → `positive` for completed checkmarks and "Done" label; secondary/primary → `label2`/`label`; list `scrollContentBackground(.hidden)` + `bgCanvas`; header row background → `surfaceRaised`
- `CalendarView`: today's day number `accent`; selected-day circle `accent.opacity(0.15)`; dot badge `accent`; weekday headers `label2`; main VStack `bgCanvas`; DayAgendaView progress bar `.tint(accent)`; reminder rows checked icon `accent`, unchecked `label3`; item title/date → `label`/`label2`; row backgrounds `surfaceRaised`; list `scrollContentBackground(.hidden)` + `bgCanvas`
- `RoutineAgendaRow`: complete icon `accent`; incomplete `label3`; title done/pending → `label3`/`label`; subtitle `label2`
- `ReminderEditView`: Save CTA `.tint(accent)`; date value → `accent`; end date value → `accent`; chevrons `label2`; "On days" label `label2`; weekday selected bg `accent` + text `accentOnYellow`; unselected bg `fillRecessed` + text `label`; list `scrollContentBackground(.hidden)` + `bgCanvas`

## Deviations from Plan

None — plan executed exactly as written. All acceptance criteria met.

## Verification

### Automated checks (both tasks)

```
grep -rnE 'Color\(\.(secondary|system|tertiary)|accentColor' [Task 1 files] | grep -v '//' | wc -l
→ 0

grep -rnE 'Color\(\.(secondary|system|tertiary)|accentColor|\.cardStyle\(' [Task 2 files] | grep -v '//' | wc -l
→ 0

grep -c 'neuSurface' NoteRow.swift
→ 1

grep -c 'neuSurface(.raised)' RoutineDetailView.swift
→ 1

xcodebuild build -scheme MyHome -destination 'platform=iOS Simulator,name=iPhone 17'
→ BUILD SUCCEEDED
```

### Threat model check (T-14-07)

`kOpenNoteNotification` deep-link: `NotesHomeView.onChange(of: deepLinkNoteID)` and `NotesListView.onChange(of: deepLinkNoteID/deepLinkBlockID)` are untouched. Only visual/color properties were modified — no logic, no observer, no navigation structure changed. SKIN-09 constraint satisfied.

## Known Stubs

None. All DesignToken color references are wired to the live token values from Phase 13's `DesignTokens.swift`.

## Threat Flags

None — presentational restyle only; no new network endpoints, auth paths, file access, or schema changes introduced.

## Self-Check: PASSED

- [x] NotesHomeView.swift modified
- [x] NoteRow.swift modified  
- [x] NotesListView.swift modified
- [x] AddNoteView.swift modified
- [x] EditNoteView.swift modified
- [x] CalendarView.swift modified
- [x] ReminderEditView.swift modified
- [x] RoutineDetailView.swift modified
- [x] Commits fe71e79 and 7bc1cdd exist
- [x] Zero stock system colors in all 8 files
- [x] Build succeeded
