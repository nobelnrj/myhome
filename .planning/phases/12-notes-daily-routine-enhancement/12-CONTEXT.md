# Phase 12: Notes & Daily Routine Enhancement - Context

**Gathered:** 2026-06-13
**Status:** Ready for planning

<domain>
## Phase Boundary

Turn any existing note into a **daily routine**. A routine note:
1. Surfaces automatically on **every** day in the calendar (NOTE-01) — no separately-configured recurring reminder.
2. Can carry **one optional daily reminder time** that fires once per day (NOTE-03), with exactly one pending notification at any time.
3. Supports **drag-to-reorder** of its checklist items (NOTE-04).
4. Tracks a **completion streak** and a per-day completion **history** (NOTE-05).

The data seam already exists from Phase 9 (`Note.isDailyRoutine`, `Note.routineLastResetDate`, `NoteBlock.order`); `RoutineResetService` already unchecks a routine's boxes each IST morning. This phase adds the **UI toggle**, the **calendar surfacing**, the **daily reminder**, the **reorder gesture**, and the **completion log + streak/history** (the one new schema piece deferred from Phase 9).

**Not in scope:** any change to one-off / recurring *reminder* semantics beyond the new routine daily-time field; expense/account/asset features; notes search/organization changes.
</domain>

<decisions>
## Implementation Decisions

### Calendar appearance (NOTE-01)
- **D-01:** Routine notes render in their **own "Daily Routines" section at the top of each day's agenda** (DayAgendaView), above one-off reminders — visually separated, not mixed inline.
- **D-02:** Day cells do **NOT** get a dot badge just because a routine repeats (that would dot every single day). The existing dot badge stays reserved for real reminders only.
- **D-03:** A routine appears on every calendar day **without** requiring any recurring reminder to be configured — surfacing is driven purely off the `isDailyRoutine` flag, independent of the reminder time in D-04.

### Daily reminder (NOTE-03)
- **D-04:** The routine reminder is a **simple time-only field** (e.g. 7:00 AM) on the routine — NOT the full date+recurrence reminder editor (`ReminderEditView`). It fires daily at that time. Optional (a routine can have no reminder).
- **D-05:** **Exactly one pending notification per routine note.** Re-scheduling (changing the time, or re-saving) must **cancel the prior pending request before adding the new one** — never stack duplicates. Use a stable per-note identifier so re-schedule is idempotent.

### Streak & history (NOTE-05)
- **D-06:** A day counts as **complete** when **all checklist items are checked**. A routine with **no checklist items** (pure text/habit) is completed via a single **"Done today" tap**. Both routine shapes can build a streak.
- **D-07:** **Current streak** = consecutive fully-completed days, and an **incomplete _today_ does NOT break the streak** — it still shows yesterday's run; completing today extends it. The streak only breaks once a day passes **fully missed**. (Most forgiving rule.)
- **D-08:** Completion history is kept and shown for the **last 30 days only**; older entries are pruned.
- **D-09:** Streak + history are surfaced in **both** places — a **compact 🔥 streak count inside the note editor's routine section**, and a **dedicated routine detail screen** with the full scrollable per-day history.

### Toggle & reorder UX (NOTE-01 / NOTE-04)
- **D-10:** The **"make this a daily routine" toggle** lives in the **note editor (`EditNoteView`)** as a dedicated **"Routine" section** — the same section that holds the daily reminder-time field (D-04) and the compact streak (D-09). (Claude's discretion, confirmed by user.)
- **D-11:** **Drag-to-reorder applies to ALL checklist notes** (routine and normal), not just routines — the `NoteBlock.order` field already exists so it's the same code path, and reordering is generally useful. New order must persist after the view is dismissed.

### Claude's Discretion
- Exact placement/label of the "Done today" affordance for text-only routines, the routine-detail screen layout, and the streak/history visual treatment are left to UI design + planning.
- The new completion-log schema shape (new model vs per-block field), migration stage (SchemaV9, additive), and where in the lifecycle a day's completion is *recorded* are planning/research decisions — see the planner flag below.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Roadmap & requirements
- `.planning/ROADMAP.md` §"Phase 12: Notes & Daily Routine Enhancement" — goal + 4 success criteria (authoritative scope).
- `.planning/REQUIREMENTS.md` — NOTE-01, NOTE-03, NOTE-04, NOTE-05 (NOTE-02 already complete in Phase 9).

### Prior-phase decisions that constrain this phase
- `.planning/phases/09-schemav6-accounts-management/09-CONTEXT.md` §D-11/D-12 and the "Reset-mechanism reconciliation" note — explains the note-level `routineLastResetDate` reset model and explicitly **defers per-day completion logging (for streak/history) to Phase 12**. The new completion log added here must coexist with this reset mechanism.
- `.planning/phases/08-stabilization/08-CONTEXT.md` — original `RoutineResetService` scaffold + IST start-of-today seam + live-binding constraint.

No external (non-`.planning`) specs/ADRs exist for this phase.

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `MyHomeApp/Persistence/Schema/SchemaV8.swift` — `Note.isDailyRoutine: Bool`, `Note.routineLastResetDate: Date?`, `NoteBlock.order: Int`, `NoteBlock.isChecked: Bool` already exist. The routine flag and reorder field are ready; only the **completion log** is a new field/model (→ SchemaV9, additive).
- `MyHomeApp/Features/Notes/RoutineResetService.swift` — already fetches `isDailyRoutine` notes and unchecks boxes each IST morning. **Critical interaction:** this wipes `isChecked` at IST midnight, so a day's completion must be **logged at check-time (when the last box is ticked / "Done today" tapped), not derived after the reset**, or the record is lost.
- `MyHomeApp/Features/Notes/CalendarView.swift` — `CalendarView` (`@Query notes`), `DayAgendaView`, `AgendaReminderItem`, `remindersOnDay`, dot-badge logic in `dayCell`. The "Daily Routines" section (D-01/D-02) plugs into `DayAgendaView`.
- `MyHomeApp/Support/CalendarAggregator.swift` — per-day reminder counts feeding the dot badge (leave routine items OUT of this per D-02).
- `MyHomeApp/Features/Notes/EditNoteView.swift` — host for the new "Routine" section (toggle + reminder time + compact streak), D-10.
- `NotificationScheduler` (used by `ReminderEditView.swift` / note reminders) — reuse for the daily time notification; stable per-note identifier enforces the single-pending guarantee (D-05). Note `NotificationScheduler.maxSafeMonthlyDay` pattern as precedent for safe recurring triggers.

### Established Patterns
- Additive SwiftData migrations via `MigrationPlan.swift` (V6→V7→V8 are additive lightweight stages). The completion-log addition should follow as **SchemaV9, additive** (all fields optional/defaulted, CloudKit-ready, IST/UTC date discipline).
- ⚠ **Schema typealias footgun** (project memory): when bumping to SchemaV9, flip **all** `Note`/`NoteBlock`/new-model typealiases together to the new version, or save/query crashes.
- IST start-of-day discipline (RoutineResetService, SIPAccrualService) — streak/day-boundary math must use the same IST Gregorian calendar.

### Integration Points
- New completion log ← written from the checklist toggle path in the note editor / day-agenda (where `isChecked` is mutated) and the "Done today" tap.
- Streak/history reads ← compact view in `EditNoteView`, full view in the new routine-detail screen.
- Calendar surfacing ← `DayAgendaView` new "Daily Routines" section.
- Xcode pbxproj: new `.swift` files need manual `project.pbxproj` file refs (no synchronized groups — project memory) or they silently don't compile.

</code_context>

<specifics>
## Specific Ideas

- "Holds until day ends" streak feel (D-07) was a deliberate choice for a forgiving personal-habit tracker — don't reset to 0 mid-day.
- Both checklist-style and pure-text "habit" routines must be first-class (the "Done today" tap, D-06).

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope.

</deferred>

---

*Phase: 12-notes-daily-routine-enhancement*
*Context gathered: 2026-06-13*
