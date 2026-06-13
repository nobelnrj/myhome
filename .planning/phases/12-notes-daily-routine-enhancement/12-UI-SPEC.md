---
phase: 12
slug: notes-daily-routine-enhancement
status: approved
reviewed_at: 2026-06-13T00:00:00Z
shadcn_initialized: false
preset: none
created: 2026-06-13
---

# Phase 12 — UI Design Contract: Notes & Daily Routine Enhancement

> Visual and interaction contract for Phase 12. This is an existing SwiftUI/SwiftData iOS app.
> The design system is already established — this spec documents how new surfaces conform to it.
> All values are derived from direct codebase inspection of existing Notes and Asset views.
> No new design tokens are introduced.

---

## Design System

| Property | Value |
|----------|-------|
| Tool | none (native SwiftUI — no shadcn, no Tailwind, no external component library) |
| Preset | not applicable |
| Component library | SwiftUI system components (List, Form, NavigationStack, Sheet, DatePicker) |
| Icon library | SF Symbols (system-provided) — plain Text + Image(systemName:) only |
| Font | SF Pro (system default via `.font(.body)` / `.font(.headline)` etc.) |

**Registry Safety:** Not applicable. This is a native iOS app. No third-party registries, no npm packages, no shadcn blocks.

---

## Spacing Scale

Derived from codebase inspection of EditNoteView, CalendarView, NoteRow, AssetDetailView, and CardStyle.

| Token | Value | Usage |
|-------|-------|-------|
| xs | 2pt | Block row vertical padding (`.padding(.vertical, 2)`) — pre-existing codebase value; tight block-row vertical padding, visual-only, not a grid gap. Not introduced by this phase. |
| sm | 4pt | Block row vertical padding in editor (`.padding(.vertical, 4)`), grid spacing, icon gap in blockRow HStack |
| md | 8pt | Button spacing in addBlockButtons HStack, calendar header vertical, weekday bottom padding |
| base | 12pt | NoteRow vertical padding, HStack spacing in reminder/agenda rows — pre-existing codebase value (multiple of 4, outside canonical {4,8,16,24,32,48,64} set); matches existing NoteRow row height. Not introduced by this phase. |
| lg | 16pt | Standard horizontal padding (`.padding(.horizontal, 16)`), section bottom padding, standard VStack spacing in editor, cardStyle inner padding |
| xl | 24pt | Section header top padding in NotesListView (`.padding(.top, 24)`) |
| 2xl | 32pt | — |

**Exceptions:**
- Minimum touch target: 44pt (`.frame(minWidth: 44, minHeight: 44)` / `.frame(width: 44, height: 44)`) — applies to all interactive buttons: checkboxes, pin buttons, nav arrows, "Done today" button.
- Calendar day cell height: 48pt (`.frame(maxWidth: .infinity, minHeight: 48)`).
- Calendar day number circle: 32pt width + height.
- Dot badge: 6pt circle — pre-existing visual decoration (circular reminder dot), not a layout gap. Not introduced by this phase.
- CardStyle corner radius: 16pt (`.continuous` style).

---

## Typography

Derived from codebase inspection. The app uses SwiftUI semantic text styles exclusively — no hard-coded point sizes. The mapping below reflects what iOS 17+ renders for those styles at default Dynamic Type.

| Role | SwiftUI Style | Weight | Usage in this phase |
|------|---------------|--------|---------------------|
| Display | `.largeTitle.weight(.semibold)` | Semibold | RoutineDetailView current streak number (mirrors AssetDetailView currentValue label) |
| Heading | `.title2` + `.fontWeight(.semibold)` | Semibold | EditNoteView title TextField (existing, unchanged) |
| Section header | `.headline` + `.fontWeight(.semibold)` | Semibold | "Daily Routines" section header in DayAgendaView; "Daily Routine" section header in NotesListView (existing pattern) |
| Body | `.body` | Regular | Agenda row titles, routine note title text, streak label in RoutineDetailView rows, "Done today" button label |
| Subheadline | `.subheadline` | Regular | Compact streak text ("🔥 N day streak") in EditNoteView Routine section; progress copy in DayAgendaView; reminder time display in Routine section; "Routine History" NavigationLink label |
| Caption | `.caption` | Regular | Reminder date/time subtitle in agenda rows; per-day status label in RoutineDetailView history list |
| Caption2 | `.caption2` | — | Weekday header labels in calendar grid (existing) |

**Line height:** System default — no override. All styles above use SwiftUI's system-managed line height for the semantic Dynamic Type style; this phase introduces no custom `.lineSpacing()`.

**Strikethrough rule (existing, applies to routine checklist items):** checked items render `.strikethrough(true)` + `.opacity(0.6)` + `.foregroundStyle(.secondary)`.

---

## Color

Derived from codebase inspection. The app uses iOS semantic system colors throughout.

| Role | SwiftUI Value | Usage |
|------|---------------|-------|
| Dominant (60%) | `Color(.systemBackground)` | Main view background, NavigationStack background, segmented header background |
| Secondary (30%) | `Color(.secondarySystemBackground)` | CardStyle backgrounds (header cards, GroupBox), List insetGrouped row backgrounds |
| Accent (10%) | `Color.accentColor` | See reserved list below |
| Positive semantic | `Color(.systemGreen)` | "Done today" confirmation state; completed day indicator in RoutineDetailView history (mirrors gainColor in AssetDetailView) |
| Negative semantic | `Color(.systemRed)` | Missed day indicator in RoutineDetailView history; destructive button roles |
| Secondary text | `.secondary` | Checked/completed item text, subtitle labels, metadata, date labels, empty-state descriptions |

**Accent reserved for:**
- Unchecked checkbox icons (`checkmark.square` / `circle` — before completion)
- Today's date number in calendar grid
- Selected day cell background tint (`.accentColor.opacity(0.15)`)
- Dot badge on calendar days with reminders
- Progress bar tint (`.tint(.accentColor)`)
- Pin icon when pinned
- "Add Note" toolbar button tint
- Reminder badge pill foreground + background tint
- The "Daily Reminder" toggle on state (system default Toggle tint)

**Accent NOT used for:**
- Completed/checked checkmarks (use `.secondary` — existing rule from EditNoteView line 196)
- Flame emoji in streak display (emoji is self-colored)
- Routine row completed state

---

## Copywriting Contract

### Primary CTAs

| Element | Copy |
|---------|------|
| Toggle label (EditNoteView Routine section) | "Daily Routine" |
| Reminder enable toggle label | "Daily Reminder" |
| Time picker label | "Time" |
| Compact streak label | "🔥 {N} day streak" — where N is the integer from StreakCalculator.currentStreak |
| Detail link label | "Routine History" (NavigationLink in Routine section) |
| "Done today" button (text-only routines) | "Done today" |
| Reorder affordance toolbar button accessibility label | "Reorder items" |

### Section Headers

| Location | Copy |
|----------|------|
| New section in DayAgendaView (above Reminders) | "Daily Routines" |
| New section in EditNoteView | "Routine" (rendered as GroupBox label or Form Section header) |
| RoutineDetailView navigation title | "{Note title}" (the note's title — mirrors AssetDetailView navigationTitle pattern) |
| RoutineDetailView history section header | "Last 30 Days" |

### Empty States

| Context | Heading | Body |
|---------|---------|------|
| DayAgendaView — no routines AND no reminders (new empty-state gate) | "Nothing Scheduled" | "No routines or reminders for this day." |
| DayAgendaView — routines exist but no reminders | No empty state shown — the "Daily Routines" section is visible, reminders section is omitted |
| RoutineDetailView — zero completions in last 30 days | (inline within history list) | "No completions recorded yet. Complete this routine to start your streak." |
| EditNoteView — no blocks, routine is new | "Tap below to add a note or checklist item." (existing copy, unchanged) |

### Streak Zero State

When `currentStreak == 0` the compact streak label reads: "🔥 0 day streak" — same format, no special copy. This avoids a conditional branch in the label and matches the "always show the count" pattern from the existing reminder badge.

### Error States

| Context | Copy |
|---------|------|
| Notification permission denied (routine reminder cannot be scheduled) | "Couldn't schedule reminder. Enable notifications in Settings > MyHome." — shown as an `.alert` (mirrors existing `saveError` alert pattern in EditNoteView) |
| Save failure on routine completion record write | "Couldn't save note. Please try again." (reuse existing saveError alert) |

### Destructive Actions

| Action | Trigger | Confirmation approach |
|--------|---------|----------------------|
| Toggle routine OFF (clears `routineDailyReminderTime`, cancels notification) | Toggle in Routine section | No confirmation — reversible toggle; notification is re-scheduled on toggle back ON. |
| Delete note (existing action, no change) | Trash toolbar button | Existing `.confirmationDialog("Delete Note?")` unchanged. |

**No new confirmation dialogs** are introduced in this phase. Toggling routine OFF is reversible and does not require confirmation (consistent with the existing pin toggle which has no confirmation).

---

## Surface Contracts

This section is the primary output for the executor. Each new or modified surface has an explicit contract below.

---

### Surface 1: EditNoteView — New "Routine" Section

**What it is:** A new section appended at the bottom of EditNoteView's ScrollView VStack, after `addBlockButtons`. Visible for ALL notes (the toggle is how the user opts in).

**Container:** `GroupBox("Routine")` — uses SwiftUI's system GroupBox, which renders with `Color(.secondarySystemBackground)` background (consistent with the CardStyle pattern). Inner VStack spacing: 12pt.

**Layout (vertical order within GroupBox):**

1. **Toggle row:** `Toggle("Daily Routine", isOn: $note.isDailyRoutine)` — full-width SwiftUI Toggle. Source: CONTEXT.md D-10.
2. **Conditional block (visible only when `note.isDailyRoutine == true`):**
   a. **Reminder enable toggle:** `Toggle("Daily Reminder", isOn: ...)` — boolean binding derived from `note.routineDailyReminderTime != nil`.
   b. **Time picker (visible when reminder is enabled):** `DatePicker("Time", selection: ..., displayedComponents: .hourAndMinute)` — `.hourAndMinute` only, no date component. Default time when first enabled: 07:00. Source: CONTEXT.md D-04, RESEARCH.md RQ-4.
   c. **"Done today" button (visible only when note has NO checkbox blocks):** `Button("Done today") { ... }` with `.buttonStyle(.bordered)`, `.frame(minHeight: 44)`. Source: CONTEXT.md D-06.
   d. **Compact streak + Details link row:** `HStack` with `Text("🔥 {N} day streak").font(.subheadline)` on the left, `NavigationLink("Routine History") { RoutineDetailView(note: note) }.font(.subheadline)` on the right. Source: CONTEXT.md D-09.

**Spacing:** GroupBox inner VStack spacing 12pt. GroupBox bottom padding 16pt (`.padding(.bottom, 16)`).

**Interaction — toggle ON:**
- `note.isDailyRoutine = true`
- Conditional block appears (animated by SwiftUI default transition)
- No notification scheduled yet — only scheduled when "Daily Reminder" toggle is also ON and a time is set
- Calls `markDirty()` → debounced save

**Interaction — toggle OFF:**
- `note.isDailyRoutine = false`
- `note.routineDailyReminderTime = nil` (clear the time)
- `RoutineNotificationService().cancel(noteID: note.id)` (cancel any pending daily notification)
- Calls `markDirty()` → debounced save

**Interaction — "Done today" tap:**
- Calls `recordTodayCompletion()` — writes/upserts a `RoutineCompletion` record (IST dayKey, completedAt = now)
- Calls `markDirty()` → debounced save
- No visual confirmation beyond the streak count incrementing (if today was not already complete)

**Interaction — time picker change:**
- `note.routineDailyReminderTime = newValue`
- Calls `RoutineNotificationService().schedule(...)` — cancel-then-add (D-05)
- Calls `markDirty()` → debounced save

**Security note:** No note body content in userInfo dict. Notification userInfo contains only `noteID` (UUID string) and `isRoutineReminder: "true"`. Source: RESEARCH.md Security Domain.

---

### Surface 2: EditNoteView — Drag-to-Reorder Checklist Items

**What it is:** An edit mode that allows the user to drag checklist blocks (and text blocks) to a new position. Applies to ALL checklist notes, not just routines. Source: CONTEXT.md D-11.

**Affordance:** A toolbar button in EditNoteView's NavigationStack toolbar (alongside the existing Done/trash/bell buttons) — `Image(systemName: "arrow.up.arrow.down")` with `.accessibilityLabel("Reorder items")`. Tapping toggles `editMode` between `.inactive` and `.active`. Placement: `.secondaryAction` or `.topBarTrailing` (consistent with existing toolbar item placement).

**Edit mode visual:**
- When `editMode == .active`: the block list renders as a SwiftUI `List` with `ForEach.onMove` enabled. Each row shows the system drag handle (three horizontal lines, `"line.3.horizontal"` visual, automatically provided by List in edit mode). The open/checked visual sort (open items above checked) is suspended — items render in their raw `order` field sequence so the drag-and-drop gesture reflects the persisted order.
- When `editMode == .inactive`: reverts to `ScrollView + VStack + ForEach` with open-above-checked display sort (existing behavior). The drag handles disappear.

**Drag handle:** System-provided by `List` in edit mode. No custom handle needed. Color: `.secondary` (system default).

**Touch target:** Drag handles are system-sized; rows must be at least 44pt tall to accommodate the system gesture recognizer. Existing `.padding(.vertical, 4)` on blockRow satisfies this when combined with font height.

**Persistence:** `onMove` handler re-indexes `NoteBlock.order` (0, 1, 2, ...) across the full blocks array, then calls `markDirty()` → debounced save. New order persists across dismiss. Source: RESEARCH.md RQ-6.

**Interaction when edit mode is active:** The "Add Text" / "Add Item" buttons (`addBlockButtons`) remain visible below the list. The bell and trash toolbar items remain. Tapping "Done" in the toolbar saves and dismisses (existing behavior).

---

### Surface 3: DayAgendaView — "Daily Routines" Section

**What it is:** A new `Section` rendered at the TOP of DayAgendaView's List, above the existing Reminders section and progress header. Appears on every day the sheet is opened (since routines repeat every day). Source: CONTEXT.md D-01.

**Section header:** `Section("Daily Routines")` — standard List section header, system font, `.secondary` foreground.

**Empty-state gate:** The existing `ContentUnavailableView("No Reminders", ...)` is replaced by `ContentUnavailableView("Nothing Scheduled", systemImage: "calendar", description: Text("No routines or reminders for this day."))` — shown only when BOTH `routineNotes.isEmpty && remindersOnDay.isEmpty`. Source: RESEARCH.md RQ-5.

**Routine row (RoutineAgendaRow — new view):**

Each row in the "Daily Routines" section represents one routine note. Layout:

```
[ Completion indicator ] [ Note title ]
                         [ Status subtitle ]
```

- **Completion indicator (left):** A button with a circle-based icon:
  - Incomplete: `Image(systemName: "circle")` in `Color.accentColor`, `.font(.body)`, `.frame(minWidth: 44, minHeight: 44)`
  - Complete (all blocks checked OR "Done today" was tapped today): `Image(systemName: "checkmark.circle.fill")` in `.secondary`, same size
  - For checklist routines, "complete" = all checkbox blocks `isChecked == true` (read from live model)
  - For text-only routines, "complete" = a `RoutineCompletion` record exists for today's IST dayKey
  - Tapping a checklist routine's indicator checks/unchecks all blocks AND writes/upserts the RoutineCompletion record when completing
  - Accessibility label: "Mark routine complete" / "Mark routine incomplete"

- **Note title:** `Text(note.title).font(.body)`, `.strikethrough(isComplete)`, `.foregroundStyle(isComplete ? .secondary : .primary)`

- **Status subtitle:**
  - If routine has a daily reminder time set: `Text("Daily at {time}").font(.caption).foregroundStyle(.secondary)` (e.g. "Daily at 7:00 AM")
  - If no reminder time: `Text("Daily routine").font(.caption).foregroundStyle(.secondary)`

- **"Done today" button for text-only routines:** Shown INLINE in the row (replacing the completion indicator or rendered below the title) when the routine has no checkbox blocks AND is not yet complete today. Use a `Button("Done today")` with `.buttonStyle(.bordered)` and `.font(.caption)`. When tapped: writes RoutineCompletion record, saves context, row transitions to completed state. Source: CONTEXT.md D-06, RESEARCH.md Open Question #3 recommendation.

- **Row tap action:** Tapping anywhere on the row (excluding the completion indicator button) navigates to the note's `EditNoteView`. Use `NavigationLink` or a sheet (consistent with NotesListView's `editingNote` sheet pattern — prefer sheet since DayAgendaView is already a sheet). Implementation: add `@State private var editingRoutineNote: Note?` and a `.sheet(item: $editingRoutineNote)`.

- **Row padding:** `.padding(.vertical, 2)` (matches existing remindersOnDay rows).

**List style:** `.listStyle(.insetGrouped)` (existing, unchanged).

**Section ordering in DayAgendaView body:**
1. "Daily Routines" section (new — always first when non-empty)
2. Progress header section (existing — counts only reminders, not routines; source: CONTEXT.md D-02)
3. Reminder items section (existing)

**Dot badge rule (unchanged):** `CalendarAggregator.perDayCounts` is NOT modified. Routine notes without a `reminderEnabled` reminder do not produce a dot badge. If a routine note also has a standard `reminderEnabled` reminder on a specific day, that day's dot badge correctly appears. Source: CONTEXT.md D-02, RESEARCH.md RQ-5.

---

### Surface 4: RoutineDetailView (New Screen)

**What it is:** A dedicated detail screen for a routine note showing the current streak prominently and a scrollable 30-day completion history. Accessed via `NavigationLink("Routine History")` from EditNoteView's Routine section. Source: CONTEXT.md D-09.

**Navigation:** Pushed onto the NavigationStack from EditNoteView (NavigationLink, not a sheet). NavigationTitle: `note.title` (plain string). `.navigationBarTitleDisplayMode(.inline)`.

**Layout — List with two sections (mirrors AssetDetailView header-card + detail-rows pattern):**

**Section 1: Header card**
- Rendered with `.listRowBackground(Color.clear)` + `.listRowSeparator(.hidden)` + `.listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))` — same as AssetDetailView headerCard.
- Wrapped in `.cardStyle()` (corner radius 16pt, inner padding 16pt, `Color(.secondarySystemBackground)`, shadow).
- Contents (VStack, spacing 4pt):
  - `Text("Daily Routine").font(.subheadline).foregroundStyle(.secondary)` — category label (mirrors assetClassLabel)
  - `Text("🔥 \(currentStreak)").font(.largeTitle.weight(.semibold)).foregroundStyle(.primary)` — the streak count as the hero number
  - `Text(currentStreak == 1 ? "day streak" : "days streak").font(.body).foregroundStyle(.secondary)` — unit label
  - `Text(streakStatusLine).font(.subheadline).foregroundStyle(.secondary)` — e.g. "Complete today to keep your streak" (when today is not yet done) or "Streak active" (when today is done). See copywriting below.

**Section 2: "Last 30 Days" history**
- Section header: `Text("Last 30 Days")`
- ForEach over `StreakCalculator.compute(...)`.history (30 DayStatus entries, newest first)
- Each row is a `HStack`:
  - Left: `Image(systemName: isCompleted ? "checkmark.circle.fill" : "circle")` — `.foregroundStyle(isCompleted ? Color(.systemGreen) : .secondary)`, `.font(.body)`, `.frame(minWidth: 44, minHeight: 44)` (touch target, non-interactive but consistent sizing)
  - Middle: `Text(dayKey.formatted(.dateTime.weekday(.wide).day().month(.abbreviated))).font(.body).foregroundStyle(.primary)` — e.g. "Monday, 9 Jun"
  - Right: `Text(isCompleted ? "Done" : "—").font(.caption).foregroundStyle(isCompleted ? Color(.systemGreen) : .secondary)`
- `.frame(minHeight: 44)` on each row
- Today's row: `Text` renders the date as "Today" using `.relative` or a conditional format

- **Empty state within section (zero completions):** A single non-interactive row: `Text("No completions recorded yet. Complete this routine to start your streak.").font(.body).foregroundStyle(.secondary).padding(.vertical, 8)`

**List style:** `.listStyle(.insetGrouped)`

**Streak status line copy:**
- Today completed: "Today's streak is active"
- Today not yet completed, streak > 0: "Complete today to extend your streak"
- Today not yet completed, streak == 0: "Start your streak today"

---

### Surface 5: NotesListView — "Daily Routine" Section (Existing, Confirmed Unchanged)

The `NoteListOrganizer.organize()` already partitions notes into `dailyRoutine`, `pinned`, and `other` sections. The "Daily Routine" section header already renders as `.headline + .fontWeight(.semibold)` with `.padding(.top, 24)`. No visual changes needed here — Phase 12 only adds the `isDailyRoutine` toggle to EditNoteView, which causes notes to start appearing in this section automatically. This surface is specified here for completeness; the executor must verify the section header is correct but must NOT modify it.

---

## Interaction States Summary

| State | Visual treatment |
|-------|-----------------|
| Routine toggle ON, no blocks | "Done today" button visible in Routine section |
| Routine toggle ON, has blocks | "Done today" button hidden; completion via last checkbox |
| Today complete (checklist) | All checkboxes show `checkmark.square.fill` in `.secondary`; text strikethrough + 0.6 opacity |
| Today complete (text-only, "Done today" tapped) | DayAgendaView row shows `checkmark.circle.fill` in `.secondary`; "Done today" button hidden |
| Today incomplete, streak > 0 | Streak label shows yesterday's count; streak detail shows "Complete today to extend" |
| Reorder mode inactive | ScrollView + VStack display, open-above-checked sort, no drag handles |
| Reorder mode active | List with onMove enabled, raw order sort, system drag handles visible |
| History day: completed | Green `checkmark.circle.fill`, "Done" label in systemGreen |
| History day: missed | Gray `circle`, "—" label in .secondary |
| History day: today (incomplete) | Gray `circle`, date label reads "Today" |

---

## Accessibility

All interactive elements have `.accessibilityLabel(...)` set explicitly. Minimum touch targets are 44pt on all buttons (checkbox, "Done today", completion indicator in DayAgendaView). Color is never the only signal for state — icons change between `circle` and `checkmark.circle.fill`, strikethrough applies to completed text, explicit +/- or "Done"/"—" text accompanies color changes in RoutineDetailView history. Source: existing codebase pattern from NoteRow, DayAgendaView, AssetDetailView.

**Dynamic Type:** All font references use SwiftUI semantic styles (`.body`, `.headline`, etc.) which scale automatically. No hard-coded point sizes.

**VoiceOver labels for new elements:**
- Routine toggle: default Toggle VoiceOver (label + "on/off" state)
- "Done today" button: "Done today, double-tap to mark routine complete"
- Completion indicator in DayAgendaView: "Mark routine complete" / "Routine complete, double-tap to undo"
- Drag handle rows: system-provided "Reorder {item text}" label

---

## Security Rules (carried from RESEARCH.md)

- **No AttributedString:** All text rendered via plain `Text(string)`. Never `Text(AttributedString(markdown:))`. Source: existing codebase comment in AssetDetailView ("T-11-10: plain Text — no AttributedString").
- **No body content in notification userInfo:** Notification `userInfo` contains only `noteID` (UUID string) and `isRoutineReminder: "true"`. The note title IS placed in `content.title` (that is its purpose) but NOT in `userInfo`.
- **No body content in logs/errors:** Error copy is generic ("Couldn't save note. Please try again."). No note title or body text in `assertionFailure` messages.

---

## Registry Safety

| Registry | Blocks Used | Safety Gate |
|----------|-------------|-------------|
| None (native iOS app) | n/a | Not applicable |

No external package registries, no shadcn, no npm. All components are SwiftUI system components.

---

## Checker Sign-Off

- [ ] Dimension 1 Copywriting: PASS
- [ ] Dimension 2 Visuals: PASS
- [ ] Dimension 3 Color: PASS
- [ ] Dimension 4 Typography: PASS
- [ ] Dimension 5 Spacing: PASS
- [ ] Dimension 6 Registry Safety: PASS

**Approval:** pending

---

## Pre-Population Sources

| Section | Source |
|---------|--------|
| Design system (SwiftUI, SF Symbols) | RESEARCH.md Standard Stack + codebase inspection |
| Spacing scale | EditNoteView.swift, CalendarView.swift, NoteRow.swift, CardStyle.swift |
| Typography styles | NoteRow.swift, EditNoteView.swift, AssetDetailView.swift |
| Color system | CalendarView.swift (accentColor, secondary), AssetDetailView.swift (systemGreen/systemRed), CardStyle.swift (secondarySystemBackground) |
| Routine section layout | CONTEXT.md D-04/D-06/D-09/D-10, RESEARCH.md RQ-7 |
| DayAgendaView section placement | CONTEXT.md D-01/D-02, RESEARCH.md RQ-5 |
| RoutineDetailView header card | AssetDetailView.swift headerCard pattern |
| Drag-to-reorder affordance | CONTEXT.md D-11, RESEARCH.md RQ-6 |
| Copywriting | CONTEXT.md D-06/D-07/D-08/D-09 + existing view copy patterns |
| Empty states | DayAgendaView.swift (existing ContentUnavailableView), RESEARCH.md RQ-5 |
| Accessibility patterns | NoteRow.swift, DayAgendaView.swift, CalendarView.swift |
| Security rules | AssetDetailView.swift comments, RESEARCH.md Security Domain |

| Source | Decisions Used |
|--------|---------------|
| CONTEXT.md | 11 (D-01 through D-11) |
| RESEARCH.md | 7 (RQ-1 through RQ-7 visual elements) |
| Codebase (EditNoteView) | Spacing, typography, toolbar pattern, blockRow layout, auto-save |
| Codebase (CalendarView/DayAgendaView) | Section structure, list style, checkbox icon pair, progress row |
| Codebase (AssetDetailView) | Header card pattern, detail row pattern, cardStyle usage |
| Codebase (CardStyle.swift) | Corner radius, inner padding, background color, shadow |
| Codebase (NoteRow.swift) | Reminder badge pill, block preview, touch target sizing |
| Codebase (NotesListView.swift) | Section header font/weight/padding, list style |
| User input | 0 (non-interactive subagent; all decisions derived from upstream artifacts) |
