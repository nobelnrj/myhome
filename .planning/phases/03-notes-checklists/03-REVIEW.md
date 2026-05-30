---
phase: 03-notes-checklists
reviewed: 2026-05-31T00:00:00Z
depth: standard
files_reviewed: 33
files_reviewed_list:
  - MyHomeApp/Features/Notes/AddNoteView.swift
  - MyHomeApp/Features/Notes/CalendarView.swift
  - MyHomeApp/Features/Notes/EditNoteView.swift
  - MyHomeApp/Features/Notes/NoteRow.swift
  - MyHomeApp/Features/Notes/NotesHomeView.swift
  - MyHomeApp/Features/Notes/NotesListView.swift
  - MyHomeApp/Features/Notes/ReminderEditView.swift
  - MyHomeApp/MyHomeApp.swift
  - MyHomeApp/Persistence/ModelContainer+App.swift
  - MyHomeApp/Persistence/Models/Category.swift
  - MyHomeApp/Persistence/Models/Expense.swift
  - MyHomeApp/Persistence/Models/Note.swift
  - MyHomeApp/Persistence/Models/NoteBlock.swift
  - MyHomeApp/Persistence/Models/ReminderValueTypes.swift
  - MyHomeApp/Persistence/Schema/MigrationPlan.swift
  - MyHomeApp/Persistence/Schema/SchemaV3.swift
  - MyHomeApp/RootView.swift
  - MyHomeApp/Support/CalendarAggregator.swift
  - MyHomeApp/Support/Date+Display.swift
  - MyHomeApp/Support/NoteListOrganizer.swift
  - MyHomeApp/Support/NoteSearchFilter.swift
  - MyHomeApp/Support/NotificationActions.swift
  - MyHomeApp/Support/NotificationCenterPort.swift
  - MyHomeApp/Support/NotificationScheduler.swift
  - MyHomeTests/AutoSaveTests.swift
  - MyHomeTests/CalendarAggregationTests.swift
  - MyHomeTests/MigrationTests.swift
  - MyHomeTests/NoteListOrderingTests.swift
  - MyHomeTests/NoteModelTests.swift
  - MyHomeTests/NoteSearchTests.swift
  - MyHomeTests/NotificationSchedulerTests.swift
  - MyHomeTests/RecurrenceTests.swift
  - MyHomeTests/Support/SpyCenter.swift
findings:
  critical: 4
  warning: 9
  info: 5
  total: 18
status: issues_found
---

# Phase 3: Code Review Report

**Reviewed:** 2026-05-31
**Depth:** standard
**Files Reviewed:** 33
**Status:** issues_found

## Summary

Reviewed the Phase 3 Notes + Reminders hub: SwiftData v3 schema/migration, the pure
NotificationScheduler + value types, the notification delegate (background ModelContext +
`@unchecked Sendable`), and the SwiftUI editor/calendar/agenda surfaces.

The architecture (protocol-seam scheduler, pure aggregators, deterministic identifier scheme)
is sound and well-tested for the happy path. However the adversarial pass surfaced several
real defects concentrated in the areas the prompt flagged: the 64-cap budgeting can silently
drop the *main* fire while keeping lead alerts; the snooze handler will crash/lose payload on
a `userInfo` cast; the deep-link `blockID` is posted but never consumed (block-level deep links
are dead); the notification delegate reads/writes SwiftData from a non-isolated `Task` on an
`@unchecked Sendable` object with no synchronization; and the "after N" / monthly-clamp logic
has correctness gaps that the tests do not actually exercise. Details below.

## Critical Issues

### CR-01: 64-cap trimming can drop the main fire while keeping lead alerts

**File:** `MyHomeApp/Support/NotificationScheduler.swift:220-232` (and builder ordering at `124-154`)
**Issue:** `schedule(_:)` admits `requests.prefix(budget)`. `buildRequests` appends the main fire
first, then lead alerts — so for a single reminder near the cap, `prefix` keeps the main fire,
which is fine. But the *cross-reminder* trimming in `schedule` operates per-call: each `schedule`
call recomputes `budget = cap - existing` and trims that single reminder's tail. The real bug is
ordering within a reminder under a tight budget: if `budget == 1` and a reminder has
`[main, lead-0, lead-1]`, only `main` survives (correct). But for a **weekly** reminder the array
is `[weekday-a, weekday-b, ...]` with no "main" — `prefix(budget)` keeps an arbitrary subset of
weekdays, silently dropping the others. The user gets a partial weekly schedule with no signal.
More importantly, lead alerts fire *before* the main; if budget pressure ever drops the main but
keeps an earlier-built request, the user gets the pre-alert but never the actual reminder. The
cap policy needs an explicit priority (main fire must never be trimmed before its own leads, and
dropped reminders should be surfaced), not blind `prefix`.
**Fix:**
```swift
// Prioritize the main fire, then leads; never admit a lead whose main was dropped.
let prioritized = requests.sorted { lhs, rhs in
    func rank(_ id: String) -> Int { id.hasSuffix("-main") ? 0 : 1 }
    return rank(lhs.identifier) < rank(rhs.identifier)
}
let admitted = Array(prioritized.prefix(budget))
// Optionally: if admitted.count < requests.count, set a flag the UI can surface.
```

### CR-02: Snooze handler force-loses userInfo via failed `as?` cast → broken deep-link + lost category routing

**File:** `MyHomeApp/Support/NotificationActions.swift:198-214`
**Issue:** `content.userInfo = userInfo as? [String: String] ?? [:]`. The incoming `userInfo`
is `[AnyHashable: Any]`. A bridged `[AnyHashable: Any]` does **not** cast to `[String: String]`
with `as?` — the cast fails and the whole payload is silently replaced with `[:]`. Result: every
snoozed reminder loses its `noteID`/`blockID`/`originalTitle`, so tapping the snoozed banner deep-links
nowhere and a subsequent snooze shows "Reminder" instead of the title. Also note the snooze request
re-uses the original `identifier` as a prefix (`"\(identifier)-snooze-..."`); these snooze identifiers
are never cancellable by `NotificationScheduler.cancel` (which only knows `-main`/`-lead`/`-weekday`),
so a snoozed-then-completed reminder still fires.
**Fix:**
```swift
var preserved: [String: String] = [:]
for (k, v) in userInfo {
    if let ks = k as? String, let vs = v as? String { preserved[k as! String] = vs }
}
content.userInfo = preserved
// And track snooze identifiers so cancel() can remove them, or reuse the deterministic
// "<reminderID>-main" identifier so an existing cancel path clears the snoozed copy.
```

### CR-03: Block-level deep links are dead — blockID is posted but never consumed

**File:** `MyHomeApp/Support/NotificationActions.swift:226-233`, `MyHomeApp/RootView.swift:41-46`, `MyHomeApp/Features/Notes/NotesListView.swift:89-95`
**Issue:** `handleDeepLink` posts `userInfo: ["noteID": noteID, "blockID": blockID as Any]`. But
`RootView.onReceive` reads only `noteID` and forwards only `deepLinkNoteID`. `NotesListView` opens
`EditNoteView(note:)` and ignores any block target entirely. So a tap on a **block-level** reminder
banner opens the note but never scrolls to / highlights the target row — the entire `blockID`
plumbing through `ReminderInfo`, `makeRequest`, and the post is wasted, and the documented
behavior ("optionally to the block row", `NotificationActions.swift:73-74`) is unmet.
Additionally `blockID as Any` stores `Optional(nil)` boxed as `Any` when nil; any future consumer
doing `userInfo["blockID"] as? UUID` is fine, but `as Any` for a nil optional is a code smell that
masks the missing consumer.
**Fix:** Thread a `deepLinkBlockID: UUID?` binding from `RootView` → `NotesHomeView` →
`NotesListView`, and have `EditNoteView` accept an optional target block to scroll/focus. At
minimum, only post `blockID` when non-nil and document that block deep-link is not yet wired so
it is not mistaken for working behavior.

### CR-04: NotificationActionDelegate mutates SwiftData from an unsynchronized `Task` on an `@unchecked Sendable` object

**File:** `MyHomeApp/Support/NotificationActions.swift:103-107, 147-194`
**Issue:** The delegate is `@unchecked Sendable` and `modelContainer` is a mutable `var` written
on the main actor at launch and read inside `handleComplete`'s detached `Task { ... }`. The comment
claims "written once on main actor at launch, read from callbacks on delegate queue" — but the read
happens inside an unstructured `Task` (line 154) that hops off the delegate queue, and there is **no
memory barrier / actor isolation** guaranteeing the launch-time write is visible to that Task's
thread. This is exactly the `@unchecked Sendable` data-race hazard the prompt called out. Worse,
`handleComplete` does `block.isChecked = true; ... try? context.save()` on a freshly created
`ModelContext(container)` while the main context may be editing the same `Note`/`NoteBlock`
concurrently — two contexts mutating the same objects with no coordination, last-writer-wins,
no merge policy set. The `try? context.save()` also swallows the error, so a failed completion is
silent (the banner action reports success to iOS via `completionHandler()` regardless).
**Fix:** Make the container access actor-isolated (e.g. store it in a `@MainActor`-isolated holder
or pass it through an `actor`), perform the fetch/mutate/save on a `@MainActor` task using the
container's `mainContext`, and surface save failures (at least `assertionFailure` in debug, as the
views do). Do not rely on `@unchecked Sendable` + bare `Task` for cross-thread model writes.

## Warnings

### WR-01: Monthly recurrence does not actually clamp day-31 → month-end; relies on undocumented UN behavior

**File:** `MyHomeApp/Support/NotificationScheduler.swift:181-192`
**Issue:** The comment says "Clamp day to last-valid-day (e.g. day-31 in April) — D3-14" and
"UNCalendarNotificationTrigger handles month-end clamping," but the code sets `comps.day = rawDay`
(e.g. 31) with **no clamping**. `UNCalendarNotificationTrigger` does **not** reliably fire on the
last day of months without that day — a day-31 monthly trigger simply does not fire in Feb/Apr/Jun/
Sep/Nov. The claimed behavior is unverified and likely wrong. There is no test covering monthly at
all (RecurrenceTests only covers daily after-N and end-on-date).
**Fix:** Either explicitly expand to per-month last-valid-day triggers, or document day-of-month >28
as unsupported and clamp to 28. Add a RecurrenceTests case for monthly day-29/30/31.

### WR-02: "After N" end rule is never enforced in production — occurrenceIndex is always 0

**File:** `MyHomeApp/Support/NotificationScheduler.swift:105-122`, `MyHomeApp/Features/Notes/ReminderEditView.swift:566`
**Issue:** `buildRequests` honors `occurrenceIndex >= count`, but `schedule(_:)` always calls
`buildRequests(for:)` with the default `occurrenceIndex = 0`, and there is no app-side occurrence
counter anywhere. For a `.daily` + `.afterCount(3)` reminder, `schedule` builds one repeating
trigger (`repeats: true`) that fires **forever** — the after-N rule has no effect at runtime. The
RecurrenceTests pass only because they call `buildRequests` directly with hand-supplied indices;
the real scheduling path never increments anything. This is the D3-11 "native repeating triggers do
not self-stop" pitfall, left unmitigated.
**Fix:** For `.afterCount` recurrence, do not emit a single infinite repeating trigger. Either
expand the first N occurrences into N non-repeating triggers, or persist an occurrence counter and
reschedule on each delivery. Add an integration test through `schedule`.

### WR-03: All-day daily/weekly reminders fire at midnight, not the chosen time, and silently diverge

**File:** `MyHomeApp/Support/NotificationScheduler.swift:277-284`
**Issue:** `timeComponents` returns `DateComponents(hour: 0, minute: 0)` for all-day repeating
reminders, so an all-day daily/weekly reminder always fires at 00:00 local regardless of
`reminderDate`. For a "birthday" yearly all-day reminder the user likely expects a morning alert,
not a midnight one. This is a behavior surprise with no UI affordance. (Yearly uses `dateComponents`
which keeps hour/minute, so all-day yearly fires at the picked time — inconsistent with daily/weekly.)
**Fix:** Pick a deliberate default all-day time (e.g. 9:00 local) and apply it consistently across
daily/weekly/monthly/yearly, or expose it. Document the chosen contract.

### WR-04: DayAgendaView note-without-blocks toggle is non-idempotent and can resurrect a reminder

**File:** `MyHomeApp/Features/Notes/CalendarView.swift:430-437`
**Issue:** For a note-level reminder with no blocks, `toggleCompletion` does: if `reminderEnabled`,
cancel + disable; else set `reminderEnabled = true`. But once disabled the item leaves the agenda
(it requires `reminderEnabled == true` to appear, see `295-319`), so the "else" branch
(`reminderEnabled = true`) is reachable only if the item is shown while disabled — which can happen
transiently before the agenda recomputes, re-enabling a reminder the user just completed and
re-adding it without rescheduling any notification. The reminder is now "enabled" with no pending
notifications. State and notifications are out of sync.
**Fix:** Make completion one-directional for block-less note reminders (complete = cancel + disable,
no re-enable path here), matching `NotificationActionDelegate.handleComplete`.

### WR-05: Reminder date in the past is accepted and scheduled into a no-op trigger

**File:** `MyHomeApp/Features/Notes/ReminderEditView.swift:469-580`
**Issue:** `saveReminder` never validates that `reminderDate` is in the future. A one-shot
(`.none`) reminder with a past date builds a `UNCalendarNotificationTrigger(repeats: false)` whose
matching components are in the past — it never fires, but the model shows `reminderEnabled = true`
with a bell badge and a calendar entry. The user believes a reminder is set when none will fire.
**Fix:** For non-recurring reminders, validate `reminderDate > Date()` before scheduling (or after
the auth grant); show inline copy if invalid. Lead alerts already silently produce past triggers too.

### WR-06: handleComplete fetches ALL NoteBlocks/Notes and linear-scans by id (correctness via fragile fallback)

**File:** `MyHomeApp/Support/NotificationActions.swift:157-192`
**Issue:** Instead of a predicate fetch by `id`, it fetches every `NoteBlock`, then every `Note`,
and does `first(where:)`. Beyond the (out-of-scope) perf cost, it is a correctness footgun: a
`reminderID` that matches neither still silently no-ops (acceptable), but because block lookup runs
first, if a Note and a NoteBlock ever shared a UUID the wrong entity would be completed. UUIDs are
generated independently per `@Model` with no global uniqueness, so collision is astronomically
unlikely but the design assumes uniqueness it does not enforce. The deterministic identifier scheme
in `reminderIDFromNotificationIdentifier` also cannot distinguish note-level vs block-level — the
`-main` suffix is shared by both.
**Fix:** Use `FetchDescriptor<NoteBlock>(predicate: #Predicate { $0.id == reminderID })` with
`fetchLimit = 1`; encode the target kind (note vs block) into the identifier or userInfo so the
delegate does not guess.

### WR-07: reminderIDFromNotificationIdentifier mis-parses UUIDs and yields a UUID for non-reminder identifiers

**File:** `MyHomeApp/Support/NotificationActions.swift:27-36`
**Issue:** It reconstructs the UUID from the first 5 hyphen-split components. A standard UUID is
`8-4-4-4-12`, so this works for `<uuid>-main`. But snooze re-fires create
`"<uuid>-main-snooze-<ts>"` (CR-02) — still parseable, so completing a *snoozed* notification
parses fine, yet `handleComplete` is only invoked for `kCompleteActionID`; snoozed notifications
keep the category so Complete is offered, and parsing yields the right UUID — OK. The real fragility:
any identifier with `< 5` hyphen groups returns nil silently, and any malformed UUID returns nil,
so a future identifier scheme change breaks completion with no diagnostic. Also `UUID(uuidString:)`
is case-sensitive about format but the join can reassemble a string that *looks* like a UUID from
unrelated parts.
**Fix:** Prefer reading the UUID from `userInfo` (`noteID`/`blockID`) which is already stamped,
rather than re-parsing the identifier; keep identifier parsing only as a fallback and add a unit test.

### WR-08: Yearly auto-pin only pins on yearly save, never unpins when recurrence changes away from yearly

**File:** `MyHomeApp/Features/Notes/ReminderEditView.swift:536-539`
**Issue:** `if recurrenceType == .yearly { note.isPinned = pinToTop }`. If a user edits an existing
yearly reminder down to, say, daily, the note stays pinned with no way to discover why (the pin
toggle UI only appears for yearly). Conversely the pin state is entangled with reminder editing in a
way that will surprise users who manually pinned/unpinned via `NoteRow`.
**Fix:** Only auto-pin on the *transition* into yearly, or leave manual pin control authoritative and
treat the yearly toggle as a one-time suggestion. Document the intended semantics.

### WR-09: Debounced auto-save can fire after the note is deleted / view dismissed

**File:** `MyHomeApp/Features/Notes/EditNoteView.swift:22-38, 274-281, 307-320`
**Issue:** `markDirty` schedules a 500ms debounced `saveIfDirty`. On Done/dismiss, `debouncer.cancel()`
+ `flushSave()` run; on delete, `deleteNote()` cancels the debouncer. But `handleDismiss` in
`onDisappear` calls `context.delete(note)` for empty titles — if a debounced save Task was already
in-flight on the main actor and resolves interleaved with the delete, `performSave` saves a context
that just deleted the note (or a half-applied state). The `[self] in` capture in the closure also
strongly retains the view struct's captured environment; for a value-type View this is benign, but
the Task captures `self` (the View) which is recreated frequently — `saveIfDirty` may run against a
stale copy whose `isDirty`/`context` differ from the live view.
**Fix:** Capture only the `ModelContext` and the model in the debounce closure, guard `note` is not
deleted before saving, and ensure `cancel()` is awaited/ordered before delete. Add a test for
delete-during-pending-debounce.

## Info

### IN-01: Stray `print` alongside assertionFailure leaks to release logs

**File:** `MyHomeApp/Features/Notes/NotesListView.swift:182-184`
**Issue:** `deleteNotes` calls `assertionFailure(...)` *and* `print("Failed to save after deleting
note: \(error)")`. The `print` ships in release builds and is the only `print` in the reviewed code;
inconsistent with the T-03-12/16 "no content in logs" discipline used everywhere else. The error
text here is generic so it is not a leak, but the pattern invites one.
**Fix:** Remove the `print`; rely on `assertionFailure` (debug-only) plus a user-facing alert like
`EditNoteView` does.

### IN-02: ReminderTarget value semantics comment is misleading

**File:** `MyHomeApp/Features/Notes/ReminderEditView.swift:151-153`
**Issue:** Comment says "Passed by value so the view works with both Note and NoteBlock without
SwiftData @Bindable coupling," but `ReminderTarget` wraps reference-type `@Model` instances, and the
`nonmutating set` accessors mutate the live model. It is not value semantics; mutations persist.
This is intended behavior (the agenda relies on it) but the comment misrepresents it.
**Fix:** Reword to clarify the enum is a thin reference wrapper whose setters mutate the live model.

### IN-03: `pinToTop` defaults to true but is overwritten in loadFields — dead initial value

**File:** `MyHomeApp/Features/Notes/ReminderEditView.swift:167, 461-464`
**Issue:** `@State private var pinToTop = true` then `loadFields` sets `pinToTop = note.isPinned`
unconditionally for any owning note. The `= true` initializer and the "pre-checked for yearly"
comment are dead — the actual default is the note's current pin state. Minor confusion.
**Fix:** Drop the misleading comment or set the yearly-suggested default explicitly when entering
yearly mode.

### IN-04: CalendarView.stepMonth redundantly re-sets timezone already set by deviceCal

**File:** `MyHomeApp/Features/Notes/CalendarView.swift:208-214`
**Issue:** `var cal = deviceCal; cal.timeZone = TimeZone.current` — `deviceCal` already set
`timeZone = TimeZone.current`. Harmless duplication / copy-paste residue.
**Fix:** Remove the redundant assignment.

### IN-05: gridDays leading-padding math assumes month start, fragile if viewedMonthStart is not first-of-month

**File:** `MyHomeApp/Features/Notes/CalendarView.swift:46-68`
**Issue:** `gridDays` computes leading nils from `firstWeekday` of `viewedMonthStart` and adds
`day - 1` days. This is correct only because `viewedMonthStart` is always normalized to the first of
the month (set in the initializer and `stepMonth` via `.month` addition). There is no guard; a future
change that seeds `viewedMonthStart` mid-month would misalign the entire grid silently.
**Fix:** Normalize to start-of-month inside `gridDays` (`dateComponents([.year,.month])` → `date(from:)`)
so the invariant is local, not assumed.

---

_Reviewed: 2026-05-31_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
