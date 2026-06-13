# Phase 12: Notes & Daily Routine Enhancement — Research

**Researched:** 2026-06-13
**Domain:** SwiftData schema migration (V8→V9), SwiftUI drag-to-reorder, UNCalendarNotificationTrigger daily scheduling, completion-streak algorithm, IST day-boundary math
**Confidence:** HIGH — all findings verified by direct codebase inspection; no external sources needed for this phase

---

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

**Calendar appearance (NOTE-01)**
- D-01: Routine notes render in their own "Daily Routines" section at the top of each day's agenda (DayAgendaView), above one-off reminders — visually separated, not mixed inline.
- D-02: Day cells do NOT get a dot badge just because a routine repeats. The existing dot badge stays reserved for real reminders only.
- D-03: A routine appears on every calendar day without requiring any recurring reminder to be configured — surfacing is driven purely off the `isDailyRoutine` flag.

**Daily reminder (NOTE-03)**
- D-04: The routine reminder is a simple time-only field (e.g. 7:00 AM) — NOT the full ReminderEditView editor. Optional.
- D-05: Exactly one pending notification per routine note. Re-scheduling must cancel-then-add. Use a stable per-note identifier.

**Streak & history (NOTE-05)**
- D-06: Complete = all checklist items checked. No-checklist routines complete via a "Done today" tap.
- D-07: Current streak = consecutive fully-completed days; incomplete today does NOT break the streak — only a fully-missed past day breaks it.
- D-08: Keep/show last 30 days of completion history; prune older entries.
- D-09: Streak + history in both the note editor (compact flame count) and a dedicated routine-detail screen (full scrollable history).

**Toggle & reorder UX (NOTE-01 / NOTE-04)**
- D-10: "Make this a daily routine" toggle lives in a new "Routine" section in EditNoteView; same section holds the daily reminder-time field and compact streak.
- D-11: Drag-to-reorder applies to ALL checklist notes, not just routines. New order must persist.

### Claude's Discretion
- Exact placement/label of the "Done today" affordance for text-only routines.
- Routine-detail screen layout and streak/history visual treatment.
- Completion-log schema shape (new model vs per-block field), migration stage (SchemaV9, additive), and where in the lifecycle a day's completion is recorded — these are research/planning decisions documented here.

### Deferred Ideas (OUT OF SCOPE)
None — discussion stayed within phase scope.
</user_constraints>

---

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| NOTE-01 | User can mark a note as a daily routine; it surfaces on every day in the calendar view automatically. | D-10 toggle in EditNoteView; DayAgendaView new "Daily Routines" section keyed off `isDailyRoutine`. No CalendarAggregator changes needed. |
| NOTE-03 | User can set an optional reminder time for a daily routine, delivering a local notification (reuses existing NotificationScheduler). | New `routineDailyReminderTime: Date?` on Note in SchemaV9; RoutineNotificationService wraps NotificationScheduler with stable identifier `"routine-\(note.id.uuidString)-daily"`. |
| NOTE-04 | User can reorder checklist items within a routine note (drag-to-reorder). | `NoteBlock.order` already exists. SwiftUI `List { ForEach(...) .onMove }` + `EditMode` + explicit re-index of `order` values + `context.save()`. |
| NOTE-05 | The app logs per-day routine completions and shows a streak/history view. | New `RoutineCompletion` @Model in SchemaV9 (date-keyed, noteID bare UUID). Streak algorithm over last-30-days completion records. Written at check-time (before RoutineResetService can wipe isChecked). |
</phase_requirements>

---

## Summary

Phase 12 adds four capabilities on top of the fully-functional RoutineResetService (Phase 9): a UI toggle to mark notes as routines, calendar surfacing in DayAgendaView, a daily time notification, drag-to-reorder checklist items, and a streak/completion-history log. The schema seam (`Note.isDailyRoutine`, `Note.routineLastResetDate`, `NoteBlock.order`) already exists in SchemaV8. The only new schema piece is a `RoutineCompletion` @Model (date-keyed per-note completion record) introduced in SchemaV9 — additive, no backfill, no `didMigrate` closure needed.

The most critical architectural concern is **completion-recording lifecycle**: `RoutineResetService.resetIfNeeded()` wipes `isChecked` to `false` on every new IST day before any UI opens, so a completion record MUST be written at the moment the last box is ticked (or "Done today" is tapped), not derived retrospectively after midnight. A `RoutineCompletion` row keyed by `(noteID, ISTdayStart)` is the cleanest way to achieve this; it survives the reset and is used by the streak algorithm.

The daily notification is straightforward: one `UNCalendarNotificationTrigger(dateMatching: [.hour, .minute], repeats: true)` per routine note, using stable identifier `"routine-\(note.id.uuidString)-daily"`, scheduled/cancelled entirely outside the existing `kReminderCategoryID` domain. Drag-to-reorder uses SwiftUI's standard `ForEach.onMove` pattern with an explicit re-index of `NoteBlock.order` values and an immediate save.

**Primary recommendation:** Implement SchemaV9 as a purely additive nil-closure migration, introduce `RoutineCompletion` as the single new @Model, write the completion record synchronously at check-time from EditNoteView and DayAgendaView, and express the streak algorithm as a pure function over the last-30-days records so it is trivially unit-testable.

---

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| Routine toggle + daily reminder time UI | EditNoteView (SwiftUI) | Note @Model (persistence) | Toggle and time picker mutate Note fields directly via @Bindable |
| Daily notification scheduling | RoutineNotificationService (new, local SwiftData-side) | NotificationScheduler (existing) | Wraps scheduler with stable identifier logic; called from EditNoteView on save |
| Calendar surfacing (daily routines section) | DayAgendaView (SwiftUI) | CalendarView (parent) | Reads `isDailyRoutine` from the notes array already passed into DayAgendaView |
| Dot-badge counts (unchanged) | CalendarAggregator (pure) | — | Routine items must NOT be added to perDayCounts; no changes needed here |
| Drag-to-reorder | EditNoteView (SwiftUI List) | NoteBlock @Model | .onMove + order re-index + context.save |
| Completion recording | EditNoteView.toggleCheck + DayAgendaView.toggleCompletion | RoutineResetService (interaction boundary) | Write RoutineCompletion at check-time, before midnight reset can wipe isChecked |
| Streak / history computation | StreakCalculator (new pure function/struct) | RoutineCompletion records | Pure algorithm, easily unit-tested without SwiftUI |
| Streak display (compact) | EditNoteView new "Routine" section | StreakCalculator | Reads completion records for the note |
| Streak display (full history) | RoutineDetailView (new screen) | StreakCalculator | Full 30-day scrollable view |

---

## Standard Stack

### Core (all already in project)
| Component | Version/Location | Purpose |
|-----------|-----------------|---------|
| SwiftData `@Model` | iOS 17+ / SchemaV9 | `RoutineCompletion` persistence |
| `UNCalendarNotificationTrigger` | UserNotifications / iOS 10+ | Daily time-only repeating notification |
| `NotificationScheduler` | `MyHomeApp/Support/NotificationScheduler.swift` | Wraps UNUserNotificationCenter with 64-cap enforcement |
| `NotificationCenterPort` | `MyHomeApp/Support/NotificationCenterPort.swift` | Protocol seam; production = SystemNotificationCenter |
| Swift Testing (`@Test`, `#expect`) | Xcode 26 | Unit test framework (already in use) |

### No new external packages
This phase introduces no new dependencies. All required machinery exists: NotificationScheduler, SchemaV migration pattern, in-memory ModelContainer test pattern.

### Package Legitimacy Audit
No external packages are installed in this phase.

---

## Architecture Patterns

### System Architecture Diagram

```
User taps checkbox / "Done today"
          |
          v
EditNoteView.toggleCheck(block) / "Done today" Button
          |
          |-- writes RoutineCompletion(noteID, istDayStart, completedAt=now)
          |    to ModelContext  <-- BEFORE midnight reset can clear isChecked
          |
          |-- calls context.save()
          |
          v
RoutineResetService.resetIfNeeded()  [on scenePhase .active, next IST morning]
    reads routineLastResetDate < startOfTodayIST
    sets block.isChecked = false (RoutineCompletion records SURVIVE this)
    stamps routineLastResetDate = today

StreakCalculator.streak(for: note, completions: [RoutineCompletion], today: Date)
    <-- pure function, no SwiftData access
    reads last 30 days from passed-in array
    returns (currentStreak: Int, history: [DayStatus])

DayAgendaView (sheet from CalendarView)
    receives notes: [Note]
    splits into:
      - routineNotes = notes.filter { $0.isDailyRoutine }   [section "Daily Routines"]
      - remindersOnDay = [existing AgendaReminderItem logic] [section "Reminders"]
    no CalendarAggregator changes needed (dot badge excludes routines per D-02)

RoutineNotificationService (new, called from EditNoteView on save)
    cancel: scheduler.cancel(reminderID: note.id, ..., stablePrefix: "routine-")
    add:    UNCalendarNotificationTrigger(dateMatching: [.hour,.minute], repeats: true)
    identifier: "routine-\(note.id.uuidString)-daily"
```

### Recommended Project Structure for New Files

```
MyHomeApp/
├── Persistence/
│   ├── Schema/
│   │   └── SchemaV9.swift              # new — RoutineCompletion + copied V8 models
│   └── Models/
│       └── RoutineCompletion.swift     # typealias RoutineCompletion = SchemaV9.RoutineCompletion
├── Features/Notes/
│   ├── RoutineNotificationService.swift # new — daily notification scheduling
│   ├── RoutineDetailView.swift          # new — full streak/history screen
│   └── StreakCalculator.swift           # new — pure streak algorithm
MyHomeTests/
├── SchemaV9MigrationTests.swift        # new — additive migration fixture test
├── StreakCalculatorTests.swift          # new — streak algorithm unit tests
└── RoutineNotificationServiceTests.swift # new — single-pending guarantee tests
```

---

## Research Question Answers

### RQ-1: Streak/Completion-Log Data Model (SchemaV9)

**Recommended shape for `RoutineCompletion`:**

```swift
// SchemaV9.swift — NEW @Model
@Model
final class RoutineCompletion {
    // No @Attribute(.unique) — CloudKit rule 2
    var id: UUID = UUID()                      // UUID primary key (rule 6)
    var noteID: UUID = UUID()                  // bare UUID back-ref to Note.id (NOT @Relationship — Pitfall 5/rule 7)
    var dayKey: Date = Date()                  // UTC; represents IST start-of-day (upsert key; no .unique)
    var completedAt: Date = Date()             // UTC; when the last box was ticked / "Done today" tapped
    var createdAt: Date = Date()               // UTC (rule 4)

    init(noteID: UUID, dayKey: Date, completedAt: Date = Date()) {
        self.id = UUID()
        self.noteID = noteID
        self.dayKey = dayKey
        self.completedAt = completedAt
        self.createdAt = Date()
    }
}
```

**Why bare UUID back-reference instead of @Relationship:**
`Note` already uses `@Relationship(deleteRule: .cascade, inverse: \SchemaV8.NoteBlock.note)` for its blocks. Adding a second inverse relationship for RoutineCompletion on the same side risks the circular macro expansion error documented in SchemaV8 (rule 7). Use `noteID: UUID` (bare FK) exactly as `Expense.accountID` uses a bare UUID back-ref to `Account.id`. App code fetches completions with `#Predicate { $0.noteID == note.id }`.

**`dayKey` semantics:** IST start-of-day converted to UTC. Same convention as `NetWorthSnapshot.date` and `RoutineResetService.routineLastResetDate`. Computed as:
```swift
var istCal = Calendar(identifier: .gregorian)
istCal.timeZone = TimeZone(identifier: "Asia/Kolkata")!
let dayKey = istCal.startOfDay(for: Date())  // UTC Date representing IST midnight
```

**CloudKit-readiness:** All fields optional/defaulted, no `.unique`, UUID primary key, UTC dates — compliant with the 8-point rule set in SchemaV8's header comment. [VERIFIED: SchemaV8.swift, lines 1-21]

**SchemaV9 migration steps:**

1. Create `MyHomeApp/Persistence/Schema/SchemaV9.swift` — copy all 10 models from SchemaV8 verbatim, append `RoutineCompletion` as the 11th model. Add `routineDailyReminderTime: Date? = nil` (new optional field) to `SchemaV9.Note`.
2. In `MigrationPlan.swift`:
   - Append `SchemaV9.self` to `AppMigrationPlan.schemas` array (never remove V1–V8).
   - Append `v8ToV9` stage: `.custom(fromVersion: SchemaV8.self, toVersion: SchemaV9.self, willMigrate: nil, didMigrate: nil)` — purely additive, no backfill needed, nil closures per FB13812722 pattern. [VERIFIED: MigrationPlan.swift lines 19-20, 127-132]
3. Flip ALL typealiases in `Persistence/Models/` atomically (same-commit rule — STAB-08):
   - `Category.swift`: `SchemaV8.Category` → `SchemaV9.Category`
   - `Contribution.swift`: `SchemaV8.Contribution` → `SchemaV9.Contribution`
   - `Account.swift`: `SchemaV8.Account` → `SchemaV9.Account`
   - `Asset.swift`: `SchemaV8.Asset` → `SchemaV9.Asset`
   - `Note.swift`: `SchemaV8.Note` → `SchemaV9.Note`
   - `NoteBlock.swift`: `SchemaV8.NoteBlock` → `SchemaV9.NoteBlock`
   - `Expense.swift`: `SchemaV8.Expense` → `SchemaV9.Expense`
   - `NetWorthSnapshot.swift`: `SchemaV8.NetWorthSnapshot` → `SchemaV9.NetWorthSnapshot`
   - `SIPAmountChange.swift`: `SchemaV8.SIPAmountChange` → `SchemaV9.SIPAmountChange`
   - `SIP.swift`: `SchemaV8.SIP` → `SchemaV9.SIP`
   - NEW `RoutineCompletion.swift`: `typealias RoutineCompletion = SchemaV9.RoutineCompletion`
4. Add `SchemaV9.RoutineCompletion.self` to `SchemaV9.models` array AND to `AppMigrationPlan.schemas` via `SchemaV9.self` (the schema auto-includes all models in its `models` array). [VERIFIED: SchemaV8 lines 25-39, MigrationPlan.swift line 11]
5. Add `RoutineCompletion.self` to the `ModelContainer` init in `ModelContainer+App.swift` (or wherever the container is built). [VERIFIED: ModelContainer+App.swift exists at `MyHomeApp/Persistence/ModelContainer+App.swift`]

**New field on `SchemaV9.Note`:** `routineDailyReminderTime: Date? = nil` — stores the user-selected daily fire time. `Date` but only the time components are used at scheduling; the date portion is irrelevant (treated as time-only, IST). nil = no daily reminder configured.

[VERIFIED: SchemaV8.swift — Note fields lines 142-180; MigrationPlan.swift — migration pattern lines 127-132; Note.swift typealias line 26]

---

### RQ-2: Streak Computation Algorithm

**Pure function shape (StreakCalculator):**

```swift
struct DayStatus {
    let dayKey: Date      // IST start-of-day (UTC)
    let isCompleted: Bool
}

struct StreakResult {
    let currentStreak: Int          // consecutive completed days ending at yesterday (or today if completed)
    let history: [DayStatus]        // last 30 days, newest first
}

enum StreakCalculator {
    static func compute(
        for noteID: UUID,
        completions: [RoutineCompletion],
        today: Date,           // inject for testability
        calendar: Calendar     // inject IST calendar
    ) -> StreakResult {
        // 1. Build set of completed dayKeys (from completions filtered to this note)
        let completedDays = Set(
            completions
                .filter { $0.noteID == noteID }
                .map { calendar.startOfDay(for: $0.dayKey) }
        )

        // 2. Build 30-day window ending TODAY (inclusive)
        var window: [DayStatus] = []
        for offset in 0..<30 {
            if let day = calendar.date(byAdding: .day, value: -offset, to: calendar.startOfDay(for: today)) {
                window.append(DayStatus(dayKey: day, isCompleted: completedDays.contains(day)))
            }
        }

        // 3. Compute streak: walk backwards from yesterday
        //    D-07: today-incomplete does NOT break — streak is "ending at yesterday's run"
        //          If today is already completed, it EXTENDS the streak by 1.
        var streak = 0
        // Start from yesterday unless today is already complete
        let todayKey = calendar.startOfDay(for: today)
        let todayCompleted = completedDays.contains(todayKey)
        let streakStart: Int = todayCompleted ? 0 : 1   // offset from today

        for offset in streakStart... {
            guard let day = calendar.date(byAdding: .day, value: -offset, to: todayKey) else { break }
            if completedDays.contains(day) {
                streak += 1
            } else {
                break   // first miss ends the streak
            }
            if offset >= 30 { break }  // cap at 30-day window
        }

        return StreakResult(currentStreak: streak, history: window)
    }
}
```

**D-07 semantics confirmed:** "incomplete today does NOT break the streak" means the streak counter reflects the run of consecutive completed days BEFORE today. If today is completed, it adds 1. If today is not yet completed, the streak shows yesterday's run. The streak only drops when a past (pre-today) day has no completion record. [VERIFIED: 12-CONTEXT.md D-07]

**IST calendar discipline:** StreakCalculator must receive the IST Gregorian calendar (`Calendar(identifier: .gregorian)` with `timeZone = TimeZone(identifier: "Asia/Kolkata")!`). Same pattern as RoutineResetService. [VERIFIED: RoutineResetService.swift lines 26-29]

---

### RQ-3: Completion Recording Lifecycle

**The critical constraint (from code):** `RoutineResetService.resetIfNeeded()` runs synchronously on `scenePhase .active` and wipes `block.isChecked = false` for all routine notes whose `routineLastResetDate < startOfTodayIST`. It runs before ANY user interaction on the new day. [VERIFIED: RoutineResetService.swift lines 25-58]

**Consequence:** A completion that was "all boxes checked" at 11:59 PM has its `isChecked` cleared at 12:00 AM IST. If the app queries `isChecked` to derive yesterday's completion after midnight, it sees all `false` — the record is lost.

**Solution: write at check-time.**

The completion record must be created (or idempotently upserted) at the exact moment the last box is ticked OR "Done today" is tapped — not derived retroactively.

**Write sites (both must be updated):**

**Site 1 — `EditNoteView.toggleCheck(_ block: NoteBlock)` (line 375):**
```swift
private func toggleCheck(_ block: NoteBlock) {
    block.isChecked.toggle()
    if block.isChecked && block.reminderEnabled {
        cancelBlockReminder(block)
    }
    // NEW: if this note is a routine, check if all boxes are now checked
    if note.isDailyRoutine && block.isChecked {
        checkAndRecordCompletion()
    }
    markDirty()
}

private func checkAndRecordCompletion() {
    let checkboxBlocks = (note.blocks ?? []).filter { $0.kindRaw == "checkbox" }
    guard !checkboxBlocks.isEmpty else { return }
    guard checkboxBlocks.allSatisfy(\.isChecked) else { return }
    recordTodayCompletion()
}
```

**Site 2 — `DayAgendaView.toggleCompletion(_ item: AgendaReminderItem)` (line 414):**
The existing `.note` case with blocks already calls `for block in blocks { block.isChecked = newChecked }`. Add the completion record write when `newChecked == true && note.isDailyRoutine`.

**Site 3 — "Done today" tap (new button in DayAgendaView routine section and/or EditNoteView):**
Text-only routine notes (no checklist blocks) are completed via a dedicated "Done today" button. Tapping it directly calls `recordTodayCompletion()`.

**Idempotency:** Before inserting, fetch existing records for `(noteID, dayKey)`. If one exists (user toggled last item off and back on in the same day), update `completedAt` rather than inserting a duplicate (since `.unique` is forbidden by CloudKit rule 2, dedup is in app code). Pattern mirrors `NetWorthSnapshotService`'s fetch-before-insert approach. [VERIFIED: CalendarAggregator.swift + MigrationPlan.swift comments about idempotency]

```swift
private func recordTodayCompletion() {
    var istCal = Calendar(identifier: .gregorian)
    istCal.timeZone = TimeZone(identifier: "Asia/Kolkata")!
    let dayKey = istCal.startOfDay(for: Date())
    let noteID = note.id
    // Fetch-before-insert for idempotency (no .unique allowed)
    let descriptor = FetchDescriptor<RoutineCompletion>(
        predicate: #Predicate { $0.noteID == noteID && $0.dayKey == dayKey }
    )
    if let existing = try? context.fetch(descriptor).first {
        existing.completedAt = Date()
    } else {
        let completion = RoutineCompletion(noteID: noteID, dayKey: dayKey)
        context.insert(completion)
    }
    // save is handled by the calling markDirty() / try? context.save() path
}
```

**Pruning:** Entries older than 30 days are pruned lazily. A good place is after `recordTodayCompletion()` writes, or in `RoutineResetService.resetIfNeeded()` as a secondary cleanup step. Pruning query: `#Predicate { $0.noteID == noteID && $0.dayKey < thirtyDaysAgoKey }`.

[VERIFIED: EditNoteView.swift line 375-382 (toggleCheck), DayAgendaView.swift line 414-451 (toggleCompletion), RoutineResetService.swift lines 25-58]

---

### RQ-4: Daily Time Notification (NOTE-03)

**New field on `SchemaV9.Note`:** `routineDailyReminderTime: Date? = nil` — nil means no daily reminder. Only the `.hour` and `.minute` DateComponents matter; the date portion is ignored at scheduling.

**New service: `RoutineNotificationService`**

Does NOT use `ReminderInfo` / `NotificationScheduler.buildRequests(for:)` — the existing scheduler is designed for dated one-shot and recurring reminders with lead-time alerts, end-rules, and weekday arrays. The routine daily notification is simpler: one repeating trigger with time-only components.

Uses the **SIPAccrualService pattern** (direct UNUserNotificationCenter via `NotificationCenterPort`) rather than `NotificationScheduler.schedule(_:)`. This keeps it out of the reminder domain's 64-cap budget tracking and category system.

```swift
// RoutineNotificationService.swift
struct RoutineNotificationService {
    private let center: any NotificationCenterPort

    init(center: any NotificationCenterPort = SystemNotificationCenter()) {
        self.center = center
    }

    // Stable identifier: distinct from kReminderCategoryID domain
    static func identifier(for noteID: UUID) -> String {
        "routine-daily-\(noteID.uuidString)"
    }

    /// Cancel-then-add: guarantees exactly one pending request (D-05).
    func schedule(noteID: UUID, title: String, time: Date) async {
        // 1. Cancel any existing request for this note
        cancel(noteID: noteID)

        // 2. Build time-only DateComponents in device timezone (Pitfall 5 in NotificationScheduler)
        var cal = Calendar.current
        cal.timeZone = TimeZone.current
        var comps = cal.dateComponents([.hour, .minute], from: time)
        // No .year/.month/.day — repeats daily at this time
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: true)

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = "Time for your daily routine"
        content.sound = .default
        // Use same category so Complete action is available (mirrors kReminderCategoryID pattern)
        content.categoryIdentifier = kReminderCategoryID
        content.userInfo = ["noteID": noteID.uuidString, "isRoutineReminder": "true"]

        let request = UNNotificationRequest(
            identifier: Self.identifier(for: noteID),
            content: content,
            trigger: trigger
        )
        try? await center.add(request)
    }

    func cancel(noteID: UUID) {
        center.removePendingNotificationRequests(withIdentifiers: [Self.identifier(for: noteID)])
    }
}
```

**Re-scheduling on save (D-05):** In `EditNoteView` where note is saved (or in a dedicated `onChange(of: note.routineDailyReminderTime)`), call:
```swift
Task {
    if let time = note.routineDailyReminderTime, note.isDailyRoutine {
        await RoutineNotificationService().schedule(noteID: note.id, title: note.title, time: time)
    } else {
        RoutineNotificationService().cancel(noteID: note.id)
    }
}
```

Also cancel when `isDailyRoutine` is toggled OFF, or when the note is deleted.

**Coexistence with existing reminder system:**
- `kReminderCategoryID = "com.myhome.reminder"` is used here so the Complete action appears on the notification banner — same as note/block reminders. [VERIFIED: NotificationActions.swift line 9]
- The stable identifier `"routine-daily-\(note.id)"` is entirely distinct from the `NotificationScheduler` identifier scheme (`"\(reminderID)-main"`, `"\(reminderID)-weekday-*"`, etc.). No collision risk.
- The 64-cap budget is shared but the routine daily notifications are simple 1-per-routine single requests, not lead-alert expanded sets.

**Time picker UI in EditNoteView "Routine" section:**
```swift
// D-04: simple time-only DatePicker — no full ReminderEditView
if note.isDailyRoutine {
    DatePicker(
        "Daily reminder",
        selection: Binding(
            get: { note.routineDailyReminderTime ?? Calendar.current.date(bySettingHour: 7, minute: 0, second: 0, of: Date())! },
            set: { note.routineDailyReminderTime = $0 }
        ),
        displayedComponents: .hourAndMinute
    )
}
```

[VERIFIED: SIPAccrualService.swift lines 485-512 (UNCalendarNotificationTrigger direct pattern); NotificationActions.swift line 9 (kReminderCategoryID); NotificationScheduler.swift lines 196-201 (time-only components for daily repeating)]

---

### RQ-5: Calendar Surfacing (NOTE-01, D-01/D-02/D-03)

**DayAgendaView integration point:** The view already receives `notes: [Note]` from `CalendarView` (which has `@Query private var notes: [Note]`). Adding the "Daily Routines" section requires no new query — just a computed property:

```swift
// DayAgendaView — new computed property
private var routineNotes: [Note] {
    notes.filter { note in
        guard note.modelContext != nil else { return false }  // STAB-01 guard
        return note.isDailyRoutine
    }
}
```

The `routineNotes` array appears in a new section ABOVE the existing reminders section. Order within the section: sort by `note.title` alphabetically (or creation order — left to planner/UI design).

**D-02: No dot badge for routines.** `CalendarAggregator.perDayCounts(for:)` — NO changes needed. It only counts `reminderEnabled == true` notes/blocks. Routine notes without a `reminderEnabled` reminder will not appear in `dayCounts`. If a routine note ALSO has a regular `reminderEnabled` reminder on a specific day, that day gets a dot (correct behavior — it has a timed reminder). [VERIFIED: CalendarAggregator.swift lines 68-94, 111-118]

**DayProgress / CalendarAggregator.progress:** The existing `DayProgress` tracks reminder completion. Routine completion is separate (streak model). No changes to `DayProgress` or `CalendarAggregator.progress(for:notes:)`.

**ContentUnavailableView interaction:** The current `DayAgendaView.body` shows `ContentUnavailableView("No Reminders", ...)` when `remindersOnDay.isEmpty`. With routines, a day could have routines but no reminders. The empty-state check must become `remindersOnDay.isEmpty && routineNotes.isEmpty`.

**Structural change to `DayAgendaView.body`:**

```swift
var body: some View {
    NavigationStack {
        Group {
            if remindersOnDay.isEmpty && routineNotes.isEmpty {
                ContentUnavailableView("Nothing Scheduled", ...)
            } else {
                List {
                    // Section 1: Daily Routines (new — D-01)
                    if !routineNotes.isEmpty {
                        Section("Daily Routines") {
                            ForEach(routineNotes) { note in
                                RoutineAgendaRow(note: note, ...)
                            }
                        }
                    }
                    // Progress header (existing — for reminders only)
                    // Section 2: Reminders (existing)
                    if !remindersOnDay.isEmpty { ... }
                }
            }
        }
    }
}
```

[VERIFIED: CalendarView.swift lines 282-479 (full DayAgendaView); CalendarAggregator.swift lines 68-94]

---

### RQ-6: Drag-to-Reorder (NOTE-04, D-11)

**What already exists:** `NoteBlock.order: Int = 0` is already in SchemaV8. `EditNoteView.sortedBlocks` sorts by `order` and then separates open/checked items. [VERIFIED: SchemaV8.swift line 194; EditNoteView.swift lines 300-306]

**The key challenge:** `sortedBlocks` currently places checked items LAST (open-above-checked). Drag-to-reorder in a `List` requires `EditMode` to be active, but EditMode-driven reorder conflicts with the open-above-checked split. The safest resolution (consistent with D-11 "ALL checklist notes") is:

- Drag-to-reorder operates on the **`order` field sequence**, not the display order (which puts checked items last).
- The user drags in a `List` that shows items in `order` sequence (no open/checked split while in edit mode).
- When `EditMode` is `.inactive`, the view reverts to the open-above-checked display sort.

**Recommended pattern:**

```swift
// EditNoteView — add state
@State private var editMode: EditMode = .inactive

// blockList — switch between display sort and edit sort
private var blocksForDisplay: [NoteBlock] {
    editMode.isEditing
        ? (note.blocks ?? []).sorted { $0.order < $1.order }   // raw order for reorder
        : sortedBlocks                                            // open-above-checked
}

private var blockList: some View {
    List {
        ForEach(blocksForDisplay) { block in
            blockRow(block)
        }
        .onMove { indices, newOffset in
            reorderBlocks(from: indices, to: newOffset)
        }
    }
    .environment(\.editMode, $editMode)
    // Toolbar button to toggle edit mode (reorder icon)
}
```

**`reorderBlocks` must persist new order values:**

```swift
private func reorderBlocks(from source: IndexSet, to destination: Int) {
    var ordered = (note.blocks ?? []).sorted { $0.order < $1.order }
    ordered.move(fromOffsets: source, toOffset: destination)
    for (idx, block) in ordered.enumerated() {
        block.order = idx  // re-index: 0, 1, 2, ...
    }
    markDirty()  // triggers debounced save
}
```

**SwiftData @Query ordering pitfall:** If `blockList` uses an `@Query` for blocks (it doesn't currently — blocks come via `note.blocks`), SwiftData would not automatically re-fetch on `order` mutation within the same context. The current code uses `note.blocks` (a live relationship array) + `sortedBlocks` computed property, which is correct — mutations to `block.order` propagate immediately in the live graph.

**`moveDisabled`:** Items whose `kindRaw == "text"` (non-checkbox) should still be reorderable per D-11. No `moveDisabled` needed unless the design team decides to lock text blocks. Left to planner.

[VERIFIED: EditNoteView.swift lines 173-306 (blockList, sortedBlocks); SchemaV8.swift line 194 (NoteBlock.order)]

---

### RQ-7: Routine Detail Screen + Editor Section

**EditNoteView "Routine" section (D-10):**

A new `routineSection` view builder appended to the `VStack` in `EditNoteView.body`, rendered only when `note.isDailyRoutine == true` or the toggle is visible:

```swift
// In the VStack after blockList + addBlockButtons:
routineSection
    .padding(.bottom, 16)

@ViewBuilder
private var routineSection: some View {
    GroupBox("Routine") {
        VStack(alignment: .leading, spacing: 12) {
            // Toggle
            Toggle("Daily Routine", isOn: $note.isDailyRoutine)
                .onChange(of: note.isDailyRoutine) { _, isOn in
                    if !isOn { note.routineDailyReminderTime = nil }
                    Task { await syncRoutineNotification() }
                    markDirty()
                }

            if note.isDailyRoutine {
                // Daily reminder time picker (D-04)
                Toggle("Daily Reminder", isOn: Binding(
                    get: { note.routineDailyReminderTime != nil },
                    set: { enabled in
                        note.routineDailyReminderTime = enabled
                            ? Calendar.current.date(bySettingHour: 7, minute: 0, second: 0, of: Date())
                            : nil
                        Task { await syncRoutineNotification() }
                        markDirty()
                    }
                ))
                if note.routineDailyReminderTime != nil {
                    DatePicker("Time", selection: Binding(...), displayedComponents: .hourAndMinute)
                }

                // "Done today" for text-only routines (D-06)
                if (note.blocks ?? []).filter({ $0.kindRaw == "checkbox" }).isEmpty {
                    Button("Done today") { recordTodayCompletion(); markDirty() }
                        .buttonStyle(.bordered)
                }

                // Compact streak (D-09)
                HStack {
                    Text("🔥 \(currentStreak) day streak")
                        .font(.subheadline)
                    Spacer()
                    NavigationLink("Details") {
                        RoutineDetailView(note: note)
                    }
                    .font(.subheadline)
                }
            }
        }
    }
}
```

**`currentStreak` in EditNoteView:** Fetched from a `@Query var completions: [RoutineCompletion]` filtered by `noteID`. Because `@Query` with a predicate on a relationship-less field is straightforward:

```swift
@Query private var allCompletions: [RoutineCompletion]
// filtered in computed property — avoids dynamic @Query predicate limitation
private var noteCompletions: [RoutineCompletion] {
    allCompletions.filter { $0.noteID == note.id }
}
```

Or use a separate `@Query` initialised with the note's ID in `init`. The simplest approach matching existing test patterns is a full `@Query` with a static predicate — but since `note.id` is known at init time, inject via init:

```swift
init(note: Note, ...) {
    self._allCompletions = Query(
        filter: #Predicate<RoutineCompletion> { $0.noteID == note.id },
        sort: [SortDescriptor(\.dayKey, order: .reverse)]
    )
}
```

**RoutineDetailView (new screen, D-09):**
- Shows note title + full 30-day scrollable history grid (e.g. 30 day cells, green = complete, gray = missed).
- Current streak at top (prominent).
- Accessed via NavigationLink from the compact routine section in EditNoteView.
- Receives `note: Note` + `completions: [RoutineCompletion]` (via `@Query` or passed in).

**"Done today" for DayAgendaView:** The new `RoutineAgendaRow` for text-only routines (no checkbox blocks) needs a "Done today" button inline in the routine section of DayAgendaView. Tapping it calls `recordTodayCompletion(note: note, context: context)`.

[VERIFIED: EditNoteView.swift lines 78-156 (body structure), 158-170 (titleField), 270-295 (addBlockButtons)]

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Daily repeating notification | Custom `Timer` or `BGTask` wakeup | `UNCalendarNotificationTrigger(dateMatching:repeats:true)` with time-only DateComponents | iOS delivers even when app is killed; background tasks unreliable for precise times |
| Per-day completion idempotency | `.unique` constraint on `(noteID, dayKey)` | Fetch-before-insert app code | `.unique` incompatible with CloudKit (rule 2) — proven pattern already in `NetWorthSnapshotService` |
| Streak derived from live `isChecked` | Query `isChecked` at streak-read time | `RoutineCompletion` records written at check-time | `RoutineResetService` wipes `isChecked` overnight; no post-midnight record would exist |
| Custom drag-to-reorder gesture | GestureRecognizer + CGPoint tracking | `List { ForEach.onMove }` + `EditMode` | Platform-native, accessibility-friendly, handles haptics, UIKit interop |
| Animate streak count | Custom particle/animation | SwiftUI `.contentTransition(.numericText())` or simple `Text` change | Sufficient; avoids UIKit interop complexity |

---

## Common Pitfalls

### Pitfall 1: Schema typealias footgun (STAB-08, project memory)
**What goes wrong:** Only some typealiases are flipped to SchemaV9 while others remain at SchemaV8. A Note created via `Note(...)` (which maps to SchemaV9.Note) cannot be saved to a context whose container was also initialised with SchemaV8.Note for a different typealias. Results in a SwiftData assertion crash on `context.save()` and empty `@Query` results.
**Why it happens:** Each model file has its own typealias. A partial flip leaves the container schema and the Swift type out of sync.
**How to avoid:** Flip ALL 11 typealiases (10 existing + new RoutineCompletion) in a SINGLE commit. Verified list: Category, Contribution, Account, Asset, Note, NoteBlock, Expense, NetWorthSnapshot, SIPAmountChange, SIP, + new RoutineCompletion.
**Warning signs:** `save() failed` assertion in debug, `@Query` returns 0 results for a model that has rows, `SwiftDataError.unknown` at container init.

### Pitfall 2: Completion recorded after midnight wipe
**What goes wrong:** A background thread or lazy derivation checks `isChecked` after `RoutineResetService.resetIfNeeded()` runs (on `scenePhase .active`). All boxes are `false`; yesterday's completion is invisible.
**Why it happens:** `RoutineResetService` runs synchronously on main thread during scene activation — before any view renders. If completion is derived on first render (e.g. in `.onAppear`), the state is already wiped.
**How to avoid:** Write `RoutineCompletion` synchronously at the moment the last checkbox is ticked or "Done today" is tapped. The record persists independently of `isChecked`.
**Warning signs:** Streak always shows 0 even though user completed routine yesterday; history grid is all gray.

### Pitfall 3: Duplicate daily notifications (D-05)
**What goes wrong:** The user changes the reminder time and saves. Two pending requests exist for the same routine note.
**Why it happens:** `center.add(request)` stacks requests with new identifiers if the stable ID is not used, or if cancel is async but the add starts before cancel completes.
**How to avoid:** Always call synchronous `center.removePendingNotificationRequests(withIdentifiers:)` BEFORE the async `center.add(request)`. The cancel method in `NotificationCenterPort` is synchronous; the add is async. This ordering is guaranteed.
**Warning signs:** User receives two notifications at old and new time after changing the routine time.

### Pitfall 4: @Query with dynamic predicate on NoteID
**What goes wrong:** Trying to pass `note.id` directly into a `#Predicate` closure at the `@Query` property wrapper call site in a `View.body` (not in `init`) fails — predicates must capture values known at init time, not computed at body evaluation.
**Why it happens:** SwiftData `@Query` predicates are compiled, not closures. They cannot capture `self` from a View.
**How to avoid:** Pass the predicate's captured value via the view's `init`. Pattern: `init(note: Note) { self._completions = Query(filter: #Predicate<RoutineCompletion> { $0.noteID == note.id }) }`.
**Warning signs:** Compile error "cannot capture dynamic value in @Query predicate."

### Pitfall 5: TOMBSTONE crash on DayAgendaView routine rows
**What goes wrong:** A note is deleted from another view while DayAgendaView is open. Accessing `note.isDailyRoutine` or iterating `note.blocks` on the tombstoned object crashes with EXC_BAD_ACCESS.
**Why it happens:** Same as STAB-01 — SwiftData model objects become tombstones after deletion; any property access faults.
**How to avoid:** Apply the established `guard note.modelContext != nil else { continue }` idiom (already in `remindersOnDay` at CalendarView.swift line 304) to the new `routineNotes` computed property.
**Warning signs:** EXC_BAD_ACCESS crash on deletion of a routine note while DayAgendaView is open.

### Pitfall 6: Xcode pbxproj not updated for new swift files (project memory)
**What goes wrong:** New `.swift` files (`SchemaV9.swift`, `RoutineCompletion.swift`, `RoutineNotificationService.swift`, `RoutineDetailView.swift`, `StreakCalculator.swift`, `SchemaV9MigrationTests.swift`, `StreakCalculatorTests.swift`, `RoutineNotificationServiceTests.swift`) are created but not added to the Xcode project. The app builds without them — no compile error, just missing functionality.
**Why it happens:** `project.pbxproj` has no synchronized groups. Each new file requires 4 manual edits: PBXBuildFile entry, PBXFileReference entry, PBXGroup membership, and PBXSourcesBuildPhase membership.
**How to avoid:** Each plan task that creates a new `.swift` file must include explicit `project.pbxproj` edits as a sub-step.
**Warning signs:** File exists in the filesystem but `@Query` over a new model returns nothing; service is never called.

---

## Code Examples

### Daily Repeating Notification (time-only) — Source: SIPAccrualService.swift lines 485-506 + NotificationScheduler.swift lines 196-201

```swift
// Build time-only DateComponents (device timezone — mirrors Pitfall 5 in NotificationScheduler)
var cal = Calendar.current
cal.timeZone = TimeZone.current
let comps = cal.dateComponents([.hour, .minute], from: reminderTime)
// repeats: true fires daily at this time indefinitely
let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: true)
let content = UNMutableNotificationContent()
content.title = note.title
content.sound = .default
content.categoryIdentifier = kReminderCategoryID     // enables Complete action
content.userInfo = ["noteID": note.id.uuidString, "isRoutineReminder": "true"]
let identifier = "routine-daily-\(note.id.uuidString)"
// Cancel first (synchronous — D-05)
center.removePendingNotificationRequests(withIdentifiers: [identifier])
// Then add (async)
let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
try? await center.add(request)
```

### IST Day Key — Source: RoutineResetService.swift lines 26-29

```swift
var istCal = Calendar(identifier: .gregorian)
istCal.timeZone = TimeZone(identifier: "Asia/Kolkata")!
let startOfTodayIST = istCal.startOfDay(for: Date())
```

### Additive Migration Stage (nil closures) — Source: MigrationPlan.swift lines 127-132

```swift
static let v8ToV9 = MigrationStage.custom(
    fromVersion: SchemaV8.self,
    toVersion: SchemaV9.self,
    willMigrate: nil,
    didMigrate: nil   // purely additive: RoutineCompletion is a new empty table
)
```

### ModelContainer test pattern for new model — Source: RoutineResetServiceTests.swift lines 18-21

```swift
private func makeContainer() throws -> ModelContainer {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    return try ModelContainer(
        for: Note.self, NoteBlock.self, RoutineCompletion.self,
        configurations: config
    )
}
```

### ForEach.onMove for drag-to-reorder — [ASSUMED] SwiftUI documentation pattern

```swift
List {
    ForEach(blocksInOrderSequence) { block in
        blockRow(block)
    }
    .onMove { source, destination in
        var ordered = blocksInOrderSequence
        ordered.move(fromOffsets: source, toOffset: destination)
        for (i, b) in ordered.enumerated() { b.order = i }
        markDirty()
    }
}
.environment(\.editMode, $editMode)
```

---

## Validation Architecture

> `nyquist_validation: true` in `.planning/config.json` — include this section.

### Test Framework
| Property | Value |
|----------|-------|
| Framework | Swift Testing (`import Testing`) — already in use throughout MyHomeTests |
| Config file | Xcode test target `MyHomeTests` — no separate config file |
| Quick run command | `xcodebuild test -scheme MyHome -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:MyHomeTests/<SuiteName>` |
| Full suite command | `xcodebuild test -scheme MyHome -destination 'platform=iOS Simulator,name=iPhone 17'` |

### Phase Requirements → Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| NOTE-01 | `isDailyRoutine` note surfaces in `DayAgendaView` routineNotes | unit | `…-only-testing:MyHomeTests/RoutineCalendarTests` | ❌ Wave 0 |
| NOTE-03 | Exactly one pending notification per routine note after re-schedule | unit | `…-only-testing:MyHomeTests/RoutineNotificationServiceTests` | ❌ Wave 0 |
| NOTE-03 | Cancel-then-add order guarantees single pending request | unit | `…-only-testing:MyHomeTests/RoutineNotificationServiceTests` | ❌ Wave 0 |
| NOTE-04 | `onMove` re-indexes `order` and persists across save | unit | `…-only-testing:MyHomeTests/NoteReorderTests` | ❌ Wave 0 |
| NOTE-05 | Streak = 0 when no completions | unit | `…-only-testing:MyHomeTests/StreakCalculatorTests` | ❌ Wave 0 |
| NOTE-05 | Streak continues through today-incomplete (D-07) | unit | `…-only-testing:MyHomeTests/StreakCalculatorTests` | ❌ Wave 0 |
| NOTE-05 | Streak breaks on fully-missed past day (D-07) | unit | `…-only-testing:MyHomeTests/StreakCalculatorTests` | ❌ Wave 0 |
| NOTE-05 | Today-completed extends streak by 1 (D-07) | unit | `…-only-testing:MyHomeTests/StreakCalculatorTests` | ❌ Wave 0 |
| NOTE-05 | Completion record idempotency: second tap on same day upserts, not inserts | unit | `…-only-testing:MyHomeTests/StreakCalculatorTests` | ❌ Wave 0 |
| NOTE-05 | RoutineCompletion survives RoutineResetService midnight wipe | unit | `…-only-testing:MyHomeTests/StreakCalculatorTests` | ❌ Wave 0 |
| NOTE-01 / NOTE-05 | SchemaV9 migration is additive (V8 store survives) | unit fixture | `…-only-testing:MyHomeTests/SchemaV9MigrationTests` | ❌ Wave 0 |
| NOTE-02 | Dot badge count unchanged by routines (D-02) | unit | extend `CalendarAggregationTests` | ✅ exists |
| NOTE-03 | Notification fires at correct time | simulator UAT | manual | manual |
| NOTE-01 | "Daily Routines" section visible in DayAgendaView on all days | simulator UAT | manual | manual |
| NOTE-05 | Drag-to-reorder gesture works, order persists on relaunch | simulator UAT | manual | manual |
| NOTE-05 | Streak/history accurate after midnight (cross-day test) | simulator UAT | manual | manual |

### Sampling Rate
- **Per task commit:** `xcodebuild test -scheme MyHome -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:MyHomeTests/<affected suite>`
- **Per wave merge:** Full suite green
- **Phase gate:** Full suite green before `/gsd-verify-work`

### Wave 0 Gaps
- [ ] `MyHomeTests/StreakCalculatorTests.swift` — covers NOTE-05 streak algorithm (6 test cases above)
- [ ] `MyHomeTests/RoutineNotificationServiceTests.swift` — covers NOTE-03 single-pending guarantee (uses SpyCenter)
- [ ] `MyHomeTests/NoteReorderTests.swift` — covers NOTE-04 order persistence
- [ ] `MyHomeTests/RoutineCalendarTests.swift` — covers NOTE-01 DayAgendaView routineNotes filtering
- [ ] `MyHomeTests/SchemaV9MigrationTests.swift` — covers additive V8→V9 migration fixture (BLOCKING before schema wave)

---

## Security Domain

> `security_enforcement: true` in `.planning/config.json`.

### Applicable ASVS Categories

| ASVS Category | Applies | Standard Control |
|---------------|---------|-----------------|
| V2 Authentication | no | — (local-only app, FaceID gate is in Phase 5) |
| V3 Session Management | no | — |
| V4 Access Control | no | — (single-user, local-only) |
| V5 Input Validation | yes | Note title and reminder time come from user; title already guarded by `trimmingCharacters` in EditNoteView; no SQL injection surface (SwiftData predicates are compiled, not string-interpolated) |
| V6 Cryptography | no | — (no secrets in this phase) |

### Known Threat Patterns for This Stack

| Pattern | STRIDE | Standard Mitigation |
|---------|--------|---------------------|
| Note body content in notification payload | Information Disclosure | `content.userInfo` must contain only `noteID` (UUID string) and `isRoutineReminder` flag — no note title or body text in userInfo beyond the display title (mirrors T-03-16 in NotificationScheduler.swift:404-418) |
| Notification spam (many routines, frequent saves) | Denial of Service | RoutineNotificationService cancel-then-add is synchronous cancel + async add; no loop risk. iOS 64-cap is separate domain from routine reminders (1 request per routine). |
| Orphaned notifications after note deletion | Information Disclosure | `deleteNote()` in EditNoteView must call `RoutineNotificationService().cancel(noteID: note.id)` before `context.delete(note)` — same pattern as `cancelBlockReminder`. |

---

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | `ForEach.onMove` + `EditMode` works correctly within a `ScrollView` (EditNoteView uses `ScrollView`, not `List` at the outer level) | RQ-6 (Drag-to-reorder) | May require wrapping the block list in a nested `List` rather than using `ScrollView`; EditNoteView's outer layout may need restructuring. Planner should verify. |
| A2 | `UNCalendarNotificationTrigger(dateMatching: [.hour, .minute], repeats: true)` fires reliably on the iPhone 17 simulator (Xcode 26) without background-mode entitlements | RQ-4 (Notification) | If simulator requires special entitlements for repeating triggers, the scheduled time may not fire in testing — human UAT is the verification gate. |
| A3 | `#Predicate { $0.noteID == noteID }` (comparing a captured `UUID` value) compiles correctly under SwiftData's predicate macro constraints | RQ-1 (Schema), RQ-7 (RoutineDetailView) | SwiftData #Predicate has restrictions on what Equatable types can be captured; UUID is Equatable but the macro may reject it. Workaround: compare `.uuidString`. |
| A4 | The "Done today" button for text-only routines is suitable as a `Button` in the DayAgendaView routine row (not a checkbox-style toggle) | RQ-3 + RQ-7 | If the user expects a checkbox even for text routines, the UX may be confusing. Exact treatment is Claude's discretion (CONTEXT.md). |

---

## Open Questions (RESOLVED during planning — Phase 12 plans)

> All three resolved by the plans: OQ-1 via the Wave-0 UUID-predicate compile/run test in 12-01 Task 2 (fallback to `.uuidString` if it fails); OQ-2 via 12-03 Task 2 (nested `List` for checklist blocks in edit mode, with always-`List` fallback); OQ-3 via 12-04 Task 1 (check all blocks AND write the completion record for checklist routines; record-only for text-only). Resolution outcomes are recorded in each plan's SUMMARY at execution time.

1. **@Query predicate on UUID field (A3)** — RESOLVED: 12-01 Task 2 Wave-0 test confirms/falls back.
   - What we know: `#Predicate { $0.noteID == noteID }` where `noteID: UUID` — UUID conforms to Equatable.
   - What's unclear: whether SwiftData's predicate macro allows UUID direct comparison or requires `.uuidString` workaround.
   - Recommendation: In Wave 0 test file, write a test that fetches `RoutineCompletion` by `noteID` with this predicate. If it fails to compile, switch to `$0.noteID.uuidString == noteID.uuidString`.

2. **`onMove` in ScrollView vs List (A1)**
   - What we know: `ForEach.onMove` is a `List`-specific modifier. EditNoteView currently uses `ScrollView > VStack > ForEach` for blocks — there is no outer `List`.
   - What's unclear: whether the planner should refactor the block editor to use a `List` for reorder support, or introduce a nested `List` only for checklist blocks.
   - Recommendation: Introduce a `List` wrapping only the checklist blocks when `editMode.isEditing == true`, keeping the `ScrollView + VStack` for the non-edit display. This avoids a full EditNoteView restructure.

3. **Completion recording from DayAgendaView routine rows**
   - What we know: DayAgendaView receives `notes: [Note]` and has a `@Environment(\.modelContext)`. It can write `RoutineCompletion` directly.
   - What's unclear: whether the "Done today" completion from DayAgendaView should also update `isChecked` on the note's blocks (to give consistent visual feedback) or just write the completion record.
   - Recommendation: For text-only routines, write the completion record only (no blocks to check). For checklist routines accessed via DayAgendaView, check all blocks AND write the completion record — consistent with the existing `toggleCompletion` note-level path in DayAgendaView.

---

## Environment Availability

> Step 2.6: All capabilities are code/SwiftData/notification changes within the existing iOS app. No external CLI tools, databases, or services required. SKIPPED — no new external dependencies.

---

## Sources

### Primary (HIGH confidence — direct codebase inspection)
- `MyHomeApp/Persistence/Schema/SchemaV8.swift` — all 10 existing @Model shapes, CloudKit-readiness rules (8 rules), typealias flip requirement
- `MyHomeApp/Persistence/Schema/MigrationPlan.swift` — FB13812722 `.custom` nil-closure pattern, migration chain, idempotency comments
- `MyHomeApp/Persistence/Models/Note.swift` + `NoteBlock.swift` + all other typealias files — current SchemaV8 targets, flip history
- `MyHomeApp/Features/Notes/RoutineResetService.swift` — IST reset logic, wipe-before-render proof
- `MyHomeApp/Features/Notes/CalendarView.swift` — DayAgendaView structure, remindersOnDay, toggleCompletion, STAB-01 guards
- `MyHomeApp/Features/Notes/EditNoteView.swift` — toggleCheck, sortedBlocks, addBlock, save lifecycle, debouncer
- `MyHomeApp/Support/NotificationScheduler.swift` — ReminderInfo, buildRequests, schedule/cancel, 64-cap, identifier scheme
- `MyHomeApp/Support/NotificationCenterPort.swift` — SystemNotificationCenter production conformer
- `MyHomeApp/Support/CalendarAggregator.swift` — perDayCounts, events() filtering (confirms routine exclusion)
- `MyHomeApp/Support/SIPAccrualService.swift` lines 485-512 — direct UNCalendarNotificationTrigger pattern
- `MyHomeApp/Support/NotificationActions.swift` lines 9, 83, 91 — `kReminderCategoryID` constant location
- `MyHomeTests/RoutineResetServiceTests.swift` — in-memory container pattern, IST day helpers
- `MyHomeTests/NoteModelTests.swift` — makeContainer() test helper pattern
- `MyHomeTests/SchemaV8MigrationTests.swift` — MigrationTestsPlan trimmed-plan pattern for fixture tests
- `.planning/phases/12-notes-daily-routine-enhancement/12-CONTEXT.md` — all locked decisions D-01 through D-11
- `.planning/phases/09-schemav6-accounts-management/09-CONTEXT.md` — D-11/D-12, reset mechanism reconciliation note
- `.planning/config.json` — `nyquist_validation: true`, `security_enforcement: true`

### Tertiary (LOW confidence — assumed from training, not verified in session)
- SwiftUI `ForEach.onMove` + `EditMode` works in a `List` context (A1) — verified pattern in general SwiftUI knowledge but NOT verified against EditNoteView's actual `ScrollView` structure. See Open Questions #2.
- `#Predicate { $0.noteID == noteID }` compiles for UUID comparison (A3) — standard SwiftData pattern but not tested in this codebase yet. See Open Questions #1.

---

## Metadata

**Confidence breakdown:**
- Schema shape (RoutineCompletion, SchemaV9): HIGH — directly mirrors existing @Model patterns from SchemaV8; all CloudKit-readiness rules verified
- Migration (nil-closure additive): HIGH — identical to v7ToV8 stage, verified in MigrationPlan.swift
- Typealias flip list: HIGH — all 10 existing typealiases read directly from Models/ files
- Notification (cancel-then-add, stable ID): HIGH — SIPAccrualService pattern verified; NotificationCenterPort/NotificationScheduler fully read
- Streak algorithm: HIGH — D-07 semantics are precisely specified; IST calendar discipline verified from RoutineResetService
- Completion lifecycle: HIGH — RoutineResetService wipe timing verified; write-at-check-time is the only safe approach
- Drag-to-reorder (onMove): MEDIUM — `NoteBlock.order` field verified; onMove pattern is standard SwiftUI but EditNoteView uses ScrollView not List (open question)
- Calendar surfacing: HIGH — DayAgendaView structure fully read; CalendarAggregator exclusion verified

**Research date:** 2026-06-13
**Valid until:** 2026-07-13 (stable framework; 30-day window)
