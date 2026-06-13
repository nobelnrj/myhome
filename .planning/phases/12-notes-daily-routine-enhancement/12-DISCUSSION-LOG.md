# Phase 12: Notes & Daily Routine Enhancement - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-06-13
**Phase:** 12-notes-daily-routine-enhancement
**Areas discussed:** Calendar appearance, Daily reminder, Streak & history, Toggle & reorder UX

---

## Calendar appearance (NOTE-01)

| Option | Description | Selected |
|--------|-------------|----------|
| Own 'Routines' section | Separate "Daily Routines" group atop each day's agenda; no dot badge for routines | ✓ |
| Mixed into reminders | Inline with day's reminders, no separation, no extra dots | |
| Mixed + dot every day | Inline AND every day cell gets a dot | |

**User's choice:** Own 'Routines' section (D-01/D-02/D-03)
**Notes:** Dots stay reserved for real reminders so the calendar isn't dotted on every day.

---

## Daily reminder (NOTE-03)

| Option | Description | Selected |
|--------|-------------|----------|
| Simple time-only picker | Dedicated time field; fires daily; re-schedule cancels prior (one pending) | ✓ |
| Reuse full reminder UI | ReminderEditView set to daily recurrence | |

**User's choice:** Simple time-only picker (D-04/D-05)
**Notes:** Always "every day at time X" — full date+recurrence editor is overkill.

---

## Streak & history (NOTE-05)

| Option | Description | Selected |
|--------|-------------|----------|
| All boxes; text-only = Done tap | All checklist items checked = complete; pure-text routine completed via "Done today" tap | ✓ |
| All checkboxes only | Only checklist routines can streak | |

**User's choice:** All boxes; text-only = Done tap (D-06)

| Option | Description | Selected |
|--------|-------------|----------|
| Holds until day ends | Incomplete today doesn't break streak; only a fully-missed day breaks it | ✓ |
| Zero until today done | Streak shows 0 until today completed | |

**User's choice:** Holds until day ends (D-07)

| Option | Description | Selected |
|--------|-------------|----------|
| All-time, scrollable | Keep/show every day indefinitely | |
| Last 90 days | Most recent 90 days | |
| Last 30 days | Most recent 30 days only | ✓ |

**User's choice:** Last 30 days (D-08)

| Option | Description | Selected |
|--------|-------------|----------|
| Both (compact + detail) | Compact 🔥 streak in editor + dedicated detail screen with full history | ✓ |
| Note editor only | Streak + short history inline only | |
| Detail screen only | Dedicated screen only | |

**User's choice:** Both (D-09)

---

## Toggle & reorder UX (NOTE-01 / NOTE-04)

| Option | Description | Selected |
|--------|-------------|----------|
| All checklist notes | Drag-reorder for every checklist note (routine or not) | ✓ |
| Routine notes only | Restrict reorder to routines per literal roadmap wording | |

**User's choice:** All checklist notes (D-11)
**Notes:** `NoteBlock.order` already exists — same code path either way.

---

## Claude's Discretion

- Toggle placement: confirmed to "Routine" section in `EditNoteView` (D-10).
- Completion-log schema shape / SchemaV9 migration stage / exact lifecycle recording point — deferred to research + planning.
- Routine-detail screen layout and streak/history visual treatment.

## Deferred Ideas

None — discussion stayed within phase scope.
