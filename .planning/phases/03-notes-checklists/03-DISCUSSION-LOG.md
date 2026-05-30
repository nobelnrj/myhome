# Phase 3: Notes & Checklists - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-05-30
**Phase:** 3-Notes & Checklists
**Areas discussed:** Scope decision, Content & checklist model, Reminder & date model, Recurrence rules, Notifications behavior, Calendar surface

---

## Scope decision (owner-initiated)

The owner first selected all four note-keeper gray areas, then in free-text
described a much larger vision: notes-as-reminder-hub with time-triggered
notifications, recurring (daily/weekly cron) reminders, and birthdays.

| Option | Description | Selected |
|--------|-------------|----------|
| Defer + design for it | Keep Phase 3 = note keeper; capture vision as deferred; design schema additive-ready | (initially) |
| Defer, decide schema later | Keep tight; no special schema accommodation | |
| Add roadmap phase now | Pause and insert a Reminders phase first | |

**Initial choice:** "Defer + design for it" — then **reversed**.
**Final user instruction:** *"I want to complete the note as one shot. Dont defer and make future phase."* → Phase 3 expanded to the full Notes + Reminders hub in one phase.
**Notes:** ROADMAP/REQUIREMENTS flagged for update to match expanded scope.

---

## Content & checklist model

| Option | Description | Selected |
|--------|-------------|----------|
| Block list | Ordered list of text/checkbox blocks; reminder can attach to any block | ✓ |
| Markdown body | Single body string with `- [ ]` lines | |
| Body + checklist | Title + body + separate checklist section | |

**User's choice:** Block list (`Note 1──* NoteBlock`).

| Reminder attaches to | Selected |
|----------------------|----------|
| Both note & rows | ✓ |
| Whole-note only | |
| Rows only | |

| On check | Selected |
|----------|----------|
| Strikethrough in place | |
| Move checked to bottom | ✓ |

| Title | Selected |
|-------|----------|
| Optional, derive if blank | |
| Required title | ✓ |
| Title only, no derive | |

**Notes:** Reminder fields live on both `Note` and `NoteBlock`. Checking a row sinks it below open items and cancels its reminders.

---

## Reminder & date model

| Granularity | Selected |
|-------------|----------|
| Both all-day & timed | ✓ |
| Timed only | |
| Date only | |

**Pin vs due-today (clarified by user, not a menu pick):** User specified a top
**Daily Routine** auto-section (daily-recurring notes), then **manual Pinned**,
then **Other**. Plus: suggest auto-pin when creating yearly reminders.

| Daily Routine feed | Selected |
|--------------------|----------|
| Daily-recurring only | ✓ |
| Daily + weekly | |
| User-flagged routine | |

| Auto-pin suggestion | Selected |
|---------------------|----------|
| Suggest, default-on toggle | ✓ |
| Silently auto-pin | |
| No suggestion | |

| Lead time | Selected |
|-----------|----------|
| Optional lead time | ✓ |
| Fire at moment only | |

| Birthdays | Selected |
|-----------|----------|
| Just yearly all-day | ✓ |
| First-class birthday type | |

---

## Recurrence rules

| Repeats | Selected |
|---------|----------|
| Daily/Weekly/Monthly/Yearly | |
| Above + weekly weekday picker | ✓ |
| Daily/Weekly/Yearly only | |

| End rule | Selected |
|----------|----------|
| Forever, or until a date | |
| Forever only | |
| Never / On date / After N times | ✓ |

**Notes:** Multi-weekday weekly = multiple repeating triggers (64-cap relevance).
"After N" needs app-side occurrence tracking (native triggers don't self-stop).

---

## Notifications behavior

| Permission timing | Selected |
|-------------------|----------|
| On first reminder | ✓ |
| Upfront on first launch | |
| Pre-prompt then ask | |

| Notification actions | Selected |
|----------------------|----------|
| Tap opens + Complete/Snooze | ✓ |
| Tap opens note only | |
| Plain alert | |

---

## Calendar surface (user-added)

User asked for date-grouping + a calendar view of total reminders per day, and
asked whether storing this data costs anything. Answered: storage cost is
negligible (derived live, no extra tables); real limit is the 64-pending
notification cap, not disk.

| Calendar shape | Selected |
|----------------|----------|
| Month grid → day agenda | ✓ |
| Day agenda only (no grid) | |
| Month grid only | |

| Placement | Selected |
|-----------|----------|
| Inside Notes tab (segmented List/Calendar) | ✓ |
| Its own Calendar tab | |

---

## Claude's Discretion

- `Note`/`NoteBlock` field sets + reminder field modeling (within 8 CloudKit rules)
- `SchemaV3` + `MigrationStage` wiring + `Note` typealias flip
- Auto-save debounce (~500ms) mechanism
- Empty/untitled-note discard rule on dismiss
- "Checked-to-bottom" grouping semantics with interleaved text blocks
- Reschedule-on-edit flow + 64-pending-cap budgeting strategy
- Custom calendar `LazyVGrid` layout
- All visual layout (Phase 3 UI-SPEC, extending Phase 1/2 design system)

## Deferred Ideas

- Cross-device reminder sync (CloudKit) → post-v1
- Sharing notes/reminders with wife's device → post-v1
- Overview surfacing of pinned note / latest checklist → Phase 4 (OVR-02)
- Natural-language reminder parsing → future
- Per-occurrence completion history / streaks → future
- Location-based reminders → out of charter
