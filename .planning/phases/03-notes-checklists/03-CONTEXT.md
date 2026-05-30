# Phase 3: Notes & Checklists - Context

**Gathered:** 2026-05-30
**Status:** Ready for planning

<domain>
## Phase Boundary

> **⚠ SCOPE EXPANDED BY OWNER (2026-05-30).** The original ROADMAP scope for
> Phase 3 was a plain note keeper (NOT-01..06: notes, inline checklists, pin,
> search, auto-save). The owner deliberately expanded it — in one shot, **not
> deferred to a future phase** — into a **hybrid Notes + Reminders hub**: the
> note keeper PLUS time-triggered reminders, recurring repeats, birthdays, a
> calendar surface, and local notifications. Framing: *"a hybrid model that can
> support all kinds of reminders a couple need in life."*
>
> **ROADMAP.md Phase 3 + REQUIREMENTS.md must be updated to match this expanded
> scope** (new reminder/recurrence/notification/calendar requirements beyond
> NOT-01..06). Flagged for the planner — see "Action required" in canonical_refs.

Deliver the household's **note + reminder hub**, fully decoupled from expenses.
A note is a **block list** (interleaved text paragraphs and checkbox rows). Any
note or row can carry a **reminder** (all-day or timed, optionally recurring,
with optional advance lead-time alerts) that fires a **local notification**.
Notes surface in three places: a **List view** (Daily Routine → Pinned → Other),
a **Calendar view** (month grid + per-day agenda), and the iOS notification
system.

**In scope (note keeper — NOT-01..06):**
- Create/edit notes with a **required title** + free-form block body
- **Inline checkbox rows** embeddable anywhere in the body (block-list model)
- Manual **pin/unpin**; pinned-first then most-recent ordering
- **Auto-save** (debounced ~500ms), no save button
- **Search** across title + all block text via `.searchable`

**In scope (reminders hub — NEW, owner-expanded):**
- **Reminders** attachable to a whole note AND/OR any individual block/row
- **All-day or timed** reminders; optional **advance lead-time** alert(s)
- **Recurrence:** None / Daily / Weekly (with weekday picker) / Monthly / Yearly
- **End rules:** Never / On date / After N occurrences
- **Birthdays** = yearly all-day reminders (no special entity)
- **Daily Routine** auto-section (notes with a daily-recurring reminder)
- **Suggested auto-pin** (default-on toggle) when creating a yearly reminder
- **Local notifications** via `UNUserNotificationCenter`: permission on first
  reminder; actionable **Complete / Snooze**; tap deep-links into the note
- **Calendar view** (inside the Notes tab): month grid with per-day reminder
  counts → tap a day → date-grouped agenda with completion progress

**Out of scope (later phases / not v1):**
- Overview / home surface + Swift Charts (Phase 4 — OVR-01..04, EXP-10/11);
  the pinned-note/checklist surfacing on Overview is Phase 4's job
- Face ID gate + Settings shell (Phase 5)
- Gmail OAuth + ingestion (Phases 6–7)
- Any expense coupling — Notes is a fully independent feature
- Cross-device sync of reminders (CloudKit) — post-v1; schema stays CloudKit-ready
- Sharing reminders with the wife's device — post-v1 (single-user v1)

**Schema constraint:** Adding the `Note` (+ `NoteBlock` / reminder) models is a
**`SchemaV3` + additive, non-destructive migration stage** appended to
`AppMigrationPlan` — never mutate `SchemaV1`/`SchemaV2`, never a rewrite (D-08).
All new `@Model` types obey the **8 CloudKit-readiness rules**.

</domain>

<decisions>
## Implementation Decisions

### Content & checklist model (discussed)
- **D3-01:** A note is a **block list** — an ordered collection of blocks, each
  block being either a **text paragraph** or a **checkbox row**. This is the
  honest reading of NOT-02 ("checkboxes anywhere in the body"). Recommended
  shape: `Note 1──* NoteBlock` with `NoteBlock { order, kind (text|checkbox),
  text, isChecked, ...reminder fields }`. Final modeling mechanism is the
  planner's call provided it (a) honors the 8 CloudKit-readiness rules
  (optional/defaulted, no `.unique`, inverse + `.nullify` relationship, UTC
  dates) and (b) lets blocks be reordered/typed without a breaking migration.
- **D3-02:** A **reminder can attach to the whole note AND to any individual
  block/row** ("both"). Reminder fields therefore live on **both** `Note` and
  `NoteBlock`. Example: a "Mom's birthday" note has a yearly note-level reminder,
  while its "Buy gift" row has its own lead-time reminder.
- **D3-03:** **Required title.** A note must have a title to be a valid saved
  note. (Contrast: body blocks are optional.) *Discretion (D3-19):* a note left
  with an empty title is treated as a discardable draft on dismiss.
- **D3-04:** **Checking a row moves it below the open items** ("checked sinks to
  the bottom"), shown struck-through + dimmed; open items rise. Checking a row
  **cancels that row's pending reminder(s)** (including its advance alerts).
  *Discretion (D3-19):* exact "bottom" semantics with interleaved text blocks
  (whole-note vs within a contiguous checklist run) is a UI-SPEC/planner detail.

### Reminders & dates (discussed)
- **D3-05:** Each reminder is **all-day OR timed** (user picks per reminder).
  All-day = a date (birthdays, "sometime today"); timed = date + specific time
  (fires a notification at that moment).
- **D3-06:** Reminders support an **optional advance lead-time alert** ("also
  remind me N before"). Each lead alert is just another scheduled notification
  in addition to the main fire time. (Covers "buy gift 2 days before birthday".)
- **D3-07:** **Birthdays are not a special type** — a birthday is simply a
  yearly-recurring, all-day reminder (plus the D3-09 auto-pin suggestion). One
  reminder system handles everything; no dedicated birthday entity in v1.

### List & pin UX (discussed)
- **D3-08:** **Notes List layout, top → bottom:**
  1. **Daily Routine** — auto-filtered section: notes that have a
     **daily-recurring** reminder surface here automatically. (Weekly/monthly/
     yearly do NOT go here.)
  2. **Pinned** — notes the user **manually** pinned (NOT-04), above the rest.
  3. **Other notes** — everything else, **most-recent-first** (NOT-03).
- **D3-09:** Pinning stays a **manual** toggle (NOT-04), with one nudge: when a
  user creates a **yearly** reminder (typically a birthday/important date), show
  an inline **"Pin to top" toggle, pre-checked ON**, which they can uncheck.
  Suggestion, never forced.

### Recurrence (discussed)
- **D3-10:** Repeat options: **None / Daily / Weekly / Monthly / Yearly.**
  **Weekly includes a weekday picker** (e.g. Mon/Wed/Fri). Note: a multi-weekday
  weekly reminder maps to **one repeating notification trigger per selected day**
  — relevant to the 64-pending cap (D3-15).
- **D3-11:** **End rules: Never / On date / After N occurrences.** "After N"
  requires app-side **occurrence tracking** (native repeating calendar triggers
  do not self-stop) — the planner schedules/cancels accordingly. This is the one
  piece of extra recurrence logic; keep it isolated/testable.

### Notifications (discussed)
- **D3-12:** **Request notification permission on first reminder creation**
  (in-context), not upfront. If denied, show a gentle "enable in Settings" hint
  when the user next tries to set a reminder.
- **D3-13:** Delivered notifications are **actionable**: **Complete** (checks the
  target row per D3-04 and cancels its future advance alerts) and **Snooze**
  (refire in ~1h). **Tapping deep-links** into the relevant note/row.
- **D3-14:** Prefer **native repeating calendar triggers**
  (`UNCalendarNotificationTrigger(repeats: true)`) for recurrence so each repeat
  consumes a **single** pending-notification slot (not an expansion of many
  one-offs).
- **D3-15:** **Respect the iOS 64-pending-notification cap.** It is a *scheduling*
  limit, not a storage limit. With repeating triggers, normal household volume
  stays well under it; the watch-outs are multi-weekday weekly (D3-10) and
  "after N" expansions (D3-11). *Discretion (D3-19):* the exact budgeting/
  prioritization strategy if the cap is ever approached is the planner's call.

### Calendar surface (discussed)
- **D3-16:** Add a **Calendar view** showing a **month grid** with a dot/count of
  reminders due per day; **tapping a day** opens a **date-grouped agenda** of
  that day's reminders (across all notes) with a **completion progress** (e.g.
  2/5 done). All **derived live** from reminder records — **no extra stored
  data** (confirmed: storage cost is negligible; the real constraint is the
  notification cap, not disk).
- **D3-17:** The Calendar lives **inside the Notes tab** as a **segmented toggle
  (List | Calendar)**, NOT a separate top-level tab — keeps the tab bar lean
  before Overview (P4) and Settings (P5) arrive and risk the iOS 5-tab "More"
  overflow. *Discretion (D3-19):* the month grid is a custom SwiftUI
  `LazyVGrid` (no native SwiftUI calendar component).

### Search (from NOT-06)
- **D3-18:** `.searchable` spans **note title + all block text** (text blocks
  and checkbox-row labels alike) — since blocks ARE the body, search covers them.

### Claude's Discretion
- **D3-19:** Left to researcher/planner using standard SwiftData/SwiftUI/
  UserNotifications conventions: the exact `Note`/`NoteBlock` field sets and the
  reminder value-type/field modeling (subject to the 8 CloudKit rules + D3-01/02);
  the `SchemaV3` + `MigrationStage` wiring and `Note` typealias flip; the
  debounce mechanism for auto-save (~500ms); the empty/untitled-note **discard**
  rule on dismiss; "checked-to-bottom" grouping semantics with interleaved text
  (D3-04); the **reschedule-on-edit** flow (recompute a note's notifications when
  its reminders/recurrence change); the 64-cap budgeting strategy (D3-15); the
  custom calendar `LazyVGrid` layout; and all visual layout (owned by the Phase 3
  UI-SPEC, which must extend the Phase 1/2 design system).

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### ⚠ Action required (scope sync)
- `.planning/ROADMAP.md` §"Phase 3" — goal + success criteria currently describe
  ONLY the note keeper (NOT-01..06). **Update to reflect the owner-expanded
  Notes + Reminders hub** (reminders, recurrence, notifications, calendar).
- `.planning/REQUIREMENTS.md` — currently lists only NOT-01..06. **Add the new
  reminder/recurrence/notification/calendar requirements** so coverage tracking
  is honest. (Suggested new codes, e.g. NOT-07 reminders, NOT-08 recurrence,
  NOT-09 notifications, NOT-10 calendar — planner/roadmapper finalizes.)

### Project charter & scope
- `.planning/PROJECT.md` — "Notes = text body + optional checklists (single
  model)" key decision; performance/volume explicitly NOT a constraint; Face ID
  for financial data (Notes is non-financial); CloudKit-ready stance
- `.planning/REQUIREMENTS.md` — NOT-01..06 (original note-keeper requirement text)
- `.planning/ROADMAP.md` §"Phase 3" — original goal, success criteria, NOT-01..06

### Domain research (load-bearing)
- `.planning/research/ARCHITECTURE.md` — CloudKit-ready schema discipline, the 8
  `@Model` rules, VersionedSchema scaffolding
- `.planning/research/PITFALLS.md` — SwiftData + CloudKit landmines (no `.unique`,
  optional/defaulted fields, no stored enums, UTC dates; `@Observable`/`@Bindable`
  only — no `@StateObject`/`@Published`; no system keyboard for custom entry)
- `.planning/research/STACK.md` — Swift 6.2 / SwiftUI / SwiftData / iOS 17+ stack
- `.planning/research/FEATURES.md` — feature framing

### Prior phase context (binding patterns)
- `.planning/phases/01-foundation-manual-expense-spine/01-CONTEXT.md` — D-08
  (additive, non-destructive migration constraint), UTC timestamp discipline
- `.planning/phases/02-categories-tags-budgets/02-CONTEXT.md` — D2-10 (TabView
  shell), the established "no repository layer / `@Query` + `modelContext`"
  pattern, idempotent-seed pattern, SchemaV2 additive-migration precedent

### Source the phase builds on
- `MyHomeApp/Persistence/Schema/SchemaV2.swift` — current top schema; **`SchemaV3`
  copies V2's models verbatim and adds `Note`/`NoteBlock`** (follow the V2→V3
  pattern this file establishes; note its circular-`@Relationship` macro caveat)
- `MyHomeApp/Persistence/Schema/MigrationPlan.swift` — append `SchemaV3.self` +
  a `v2ToV3` `.custom` stage (mirrors the existing `v1ToV2` stage; the `.custom`
  vs `.lightweight` choice sidesteps FB13812722)
- `MyHomeApp/Persistence/Models/Expense.swift` — the `typealias` version-flip
  pattern to mirror for a `Note` typealias
- `MyHomeApp/Persistence/ModelContainer+App.swift` — `Schema(versionedSchema:)`
  wiring + seed-hook location
- `MyHomeApp/RootView.swift` — the `TabView` host (D2-10); **add a "Notes" tab**
  here (owns its own `NavigationStack`; List|Calendar segmented inside it)
- `MyHomeApp/Features/Expenses/ExpenseListView.swift` — reference for `@Query`
  sort/order, `.toolbar` "+", `ContentUnavailableView` empty state, `.sheet`
  edit pattern, and where `.searchable` attaches

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- **`Date+Display.swift`** (`MyHomeApp/Support/`) — extend for reminder date/time
  formatting and calendar day/month labels (local-time display of UTC dates).
- **Sheet + `@Bindable` edit pattern** (`EditExpenseView.swift`) — template for
  a reminder-edit sheet (date/time, recurrence, lead-time, end-rule pickers).
- **`@Query` + explicit `context.save()` write pattern** (`ExpenseListView.swift`)
  — reuse for note/block/reminder writes (debounced save for auto-save).
- **`ContentUnavailableView` empty state + `.toolbar` "+"** (`ExpenseListView`) —
  reuse for the empty notes list and "new note".
- **TabView shell** (`RootView.swift`) — slot the Notes tab in beside Expenses /
  Budgets (Overview P4, Settings P5 still to come — keep the bar lean, D3-17).

### Established Patterns (binding)
- **Views talk to SwiftData directly** via `@Query` + `@Environment(\.modelContext)`
  — **no repository layer.** Follow this; do not introduce one.
- **State:** `@Observable` / `@State` / `@Bindable` only — never `@StateObject` /
  `@ObservedObject` / `@Published` (PITFALLS).
- **Schema versioning:** every `@Model` nests inside a `VersionedSchema` enum; a
  typealias hides the version. New models ⇒ new `SchemaV3` + migration stage
  (never edit V1/V2). 8 CloudKit-readiness rules are non-negotiable.
- **`@Relationship` macro caveat** (SchemaV2.swift): declare `inverse:` on only
  ONE side to avoid the "circular reference resolving attached macro" error —
  applies to the `Note ↔ NoteBlock` relationship.

### Integration Points
- `Schema`, `AppMigrationPlan`, and a new `Note` typealias flip to V3 in lockstep
  (mirror the V2 wiring).
- `RootView` gains a **Notes tab** (List|Calendar segmented control inside).
- A **notification scheduling service** is new surface area (no existing analog):
  schedules/cancels `UNUserNotificationCenter` requests, handles permission,
  reschedule-on-edit, actionable categories (Complete/Snooze), and deep-link
  routing. Keep it isolated + unit-testable (TDD default) — pure scheduling logic
  separated from `UNUserNotificationCenter` I/O.

</code_context>

<specifics>
## Specific Ideas

- The note model is a **block list**, not a single text blob — checkboxes are
  first-class interleaved blocks (see D3-01 preview: text/checkbox rows in order).
- **Daily Routine** is the top "chore board" section, auto-derived from
  daily-recurring reminders — the user's framing of "pinned is daily chore",
  refined into: manual Pinned section + auto Daily Routine section, kept separate.
- **Calendar** = month grid with per-day reminder counts → tap a day → that day's
  reminders with an x/y completion progress. Derived live; stores nothing extra.
- Birthdays are "just" yearly all-day reminders with a suggested auto-pin — one
  reminder engine, no special-casing.
- Reminders prefer **native repeating triggers** (1 pending slot each); watch the
  **64-pending cap** for multi-weekday-weekly and "after N" cases.

</specifics>

<deferred>
## Deferred Ideas

- **Cross-device reminder sync (CloudKit)** → post-v1 (single-user v1). Schema
  stays CloudKit-ready so this is additive, not a rewrite.
- **Sharing reminders/notes with the wife's device** → post-v1 sharing phase
  (after the $99/yr Apple Developer decision).
- **Overview surfacing of the pinned note / latest checklist** → Phase 4
  (OVR-02) — Phase 3 owns the notes data; Phase 4 surfaces it on Home.
- **Smart/natural-language reminder parsing** ("remind me tomorrow at 6") → future;
  v1 uses explicit pickers.
- **Per-occurrence completion history / streaks for recurring chores** → future;
  v1 tracks current completion state, not a history ledger.
- **Location-based reminders** → out of charter for v1.

*(Note: the reminders/recurrence/notification/calendar capabilities themselves
are NO LONGER deferred — the owner pulled them into Phase 3, see Phase Boundary.)*

</deferred>

---

*Phase: 3-Notes & Checklists*
*Context gathered: 2026-05-30*
