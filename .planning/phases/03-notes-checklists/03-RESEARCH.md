# Phase 03: Notes & Checklists - Research

**Researched:** 2026-05-30 (refreshed)
**Domain:** iOS notes + reminders + calendar system (SwiftData, SwiftUI, local + CloudKit-ready)
**Confidence:** HIGH

> **Refresh note (2026-05-30):** This research was refreshed to add a formal
> `## Validation Architecture` section (Nyquist Dimension 8) so a VALIDATION.md can
> be generated, plus a `## Security Domain` section (ASVS L1, security_enforcement=true),
> a `## Phase Requirements` map, and a `## User Constraints` block. All prior content
> (stack, data model, notification architecture, UI architecture, migration, pitfalls,
> testing strategy) is preserved and refined — nothing was discarded.

---

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

- **D3-01 — Block-list model.** A note is an ordered collection of blocks; each block is either a text paragraph or a checkbox row. Shape: `Note 1──* NoteBlock` with `NoteBlock { order, kind (text|checkbox), text, isChecked, ...reminder fields }`. Final mechanism is the planner's call, provided it honors the 8 CloudKit rules and lets blocks be reordered/typed without a breaking migration.
- **D3-02 — Reminders on both note AND block.** Reminder fields live on both `Note` and `NoteBlock`.
- **D3-03 — Required title.** A note must have a title; body blocks are optional. Empty-title note is a discardable draft on dismiss.
- **D3-04 — Checked sinks to bottom.** Checking a row moves it below open items (struck-through + dimmed) and cancels that row's pending reminder(s) including advance alerts.
- **D3-05 — All-day OR timed** per reminder (user picks).
- **D3-06 — Optional advance lead-time alert** ("also remind me N before") — each lead alert is an additional scheduled notification.
- **D3-07 — Birthdays are not a special type** — a yearly-recurring all-day reminder + the D3-09 auto-pin suggestion.
- **D3-08 — List layout:** Daily Routine (auto: daily-recurring reminders) → Pinned (manual) → Other (most-recent-first).
- **D3-09 — Manual pin** with one nudge: creating a yearly reminder shows an inline "Pin to top" toggle, pre-checked ON, uncheckable.
- **D3-10 — Recurrence:** None / Daily / Weekly (with weekday picker) / Monthly / Yearly. Multi-weekday weekly = one repeating trigger per selected day (relevant to 64-cap).
- **D3-11 — End rules:** Never / On date / After N. "After N" requires app-side occurrence tracking (native triggers do not self-stop). Keep isolated/testable.
- **D3-12 — Permission on first reminder creation** (in-context); denial shows gentle "enable in Settings" hint.
- **D3-13 — Actionable notifications:** Complete (checks the row per D3-04, cancels future advance alerts) + Snooze (~1h). Tap deep-links into the note/row.
- **D3-14 — Prefer native repeating calendar triggers** (`UNCalendarNotificationTrigger(repeats: true)`) so each repeat is one pending slot.
- **D3-15 — Respect the iOS 64-pending-notification cap** (scheduling limit, not storage). Watch-outs: multi-weekday weekly + "after N".
- **D3-16 — Calendar view:** month grid with per-day reminder counts → tap a day → date-grouped agenda with completion progress (e.g. 2/5). Derived live from reminder records; stores nothing extra.
- **D3-17 — Calendar lives inside the Notes tab** as a segmented (List | Calendar) toggle, NOT a separate top-level tab. Month grid is a custom SwiftUI `LazyVGrid`.
- **D3-18 — Search:** `.searchable` spans note title + all block text.
- **Schema:** `SchemaV3` + additive, non-destructive migration stage; never mutate V1/V2 (D-08). 8 CloudKit-readiness rules mandatory.
- **No rich text:** plain text only (`TextField`, not `TextEditor`).
- **No repository layer:** views talk to SwiftData via `@Query` + `@Environment(\.modelContext)`.
- **State:** `@Observable` / `@State` / `@Bindable` only — never `@StateObject` / `@ObservedObject` / `@Published`.

### Claude's Discretion (D3-19)

Exact `Note`/`NoteBlock` field sets and reminder value-type modeling (subject to 8 rules + D3-01/02); `SchemaV3` + `MigrationStage` wiring and `Note` typealias flip; the ~500ms debounce mechanism; the empty/untitled-note discard rule; "checked-to-bottom" semantics with interleaved text; the reschedule-on-edit flow; 64-cap budgeting strategy; the custom calendar `LazyVGrid` layout; all visual layout (owned by 03-UI-SPEC.md).

### Deferred Ideas (OUT OF SCOPE)

- Cross-device reminder sync (CloudKit) → post-v1. Schema stays ready.
- Sharing reminders/notes with the wife's device → post-v1.
- Overview surfacing of the pinned note / latest checklist → Phase 4 (OVR-02/03).
- Smart / natural-language reminder parsing → future; v1 uses explicit pickers.
- Per-occurrence completion history / streaks → future; v1 tracks current state only.
- Location-based reminders → out of charter.
</user_constraints>

---

<phase_requirements>
## Phase Requirements

> NOT-01..06 are the canonical requirements. The owner expanded Phase 3 (see CONTEXT.md
> Phase Boundary) to also cover reminders / recurrence / notifications / calendar — captured
> below as the owner-expanded success criteria (SC-R1..R5) pending REQUIREMENTS.md code
> assignment (suggested NOT-07..10). Both the requirement IDs and the expanded criteria are
> in scope for v1 and validated in `## Validation Architecture`.

| ID | Description | Research Support |
|----|-------------|------------------|
| NOT-01 | Create a note with title + free-form body | Data Model (`Note` required title, `NoteBlock[]`); Edit Sheet |
| NOT-02 | Embed inline checklist rows anywhere in the body | Block-list model (`NoteBlock.kind = .checkbox`, `order`) |
| NOT-03 | List shows pinned first, then most-recent-first | UI List View sections + `@Query` sort (Daily Routine → Pinned → Other) |
| NOT-04 | Pin / unpin notes | `Note.isPinned` toggle; List section ordering |
| NOT-05 | Auto-save while editing (debounced ~500ms), no save button | Auto-save debounce (D3-19); `context.save()` write pattern |
| NOT-06 | Search note title + body via `.searchable` | `.searchable` spanning title + all block text (D3-18) |
| SC-R1 (→NOT-07) | Reminder on whole note or any row; all-day or timed; optional lead-time | Reminder fields on `Note` + `NoteBlock`; `NotificationScheduler` |
| SC-R2 (→NOT-08) | Recurrence none/daily/weekly-weekdays/monthly/yearly + end rule never/on-date/after-N | `ReminderRecurrence` / `ReminderEndRule` value types; repeating triggers; app-side "after N" tracking |
| SC-R3 (→NOT-09) | Local notifications, permission on first reminder, deep-link, Complete/Snooze | `NotificationScheduler` + actionable categories + deep-link routing |
| SC-R4 (→NOT-10) | Calendar view: per-day reminder counts → tap day → agenda with progress | Calendar View (`LazyVGrid`), derived live from reminder records |
| SC-R5 | Daily Routine auto-section + yearly auto-pin suggestion | List View Daily Routine filter; D3-09 pin nudge |
</phase_requirements>

---

## Summary

This phase introduces a note keeper with embedded checklists, time-triggered reminders (daily/weekly/monthly/yearly with recurrence), local notifications with actionable buttons, and a calendar view. Implementation uses SwiftData for the model layer (following CloudKit-readiness rules from Phase 1), SwiftUI for the UI, and `UNUserNotificationCenter` for notifications. The phase differs from the Phase 1/2 foundation in its complexity: it adds new entity types (`Note`, `NoteBlock`, reminder fields), a recurrence scheduler, a notification service, and a calendar rendering surface.

**Primary architectural decision:**
Model notes as a **block list** (`Note` → `NoteBlock[]`, where each block is either text or a checkbox), with reminders attachable to both the note and any individual block. Follow the 8 CloudKit-readiness rules (optional/defaulted fields, no `.unique`, UTC dates, proper `@Relationship` macros).

**Primary recommendation:** Build an isolated, unit-testable `NotificationScheduler` (pure scheduling logic separated from `UNUserNotificationCenter` I/O) and drive the model + scheduler + migration with Swift Testing; verify notification delivery, the system permission prompt, deep-link, and the calendar UI via manual UAT on the iPhone 17 simulator (Xcode 26.5, scheme/module `MyHome`).

---

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| `Note` + `NoteBlock` persistence | Database / Storage (SwiftData) | — | Optional/defaulted fields, inverse relationships, UTC dates |
| Reminder data (all-day/timed, recurrence, lead-time, end rule) | Database / Storage (SwiftData) | — | Fields embedded on models (D3-02) |
| Notification scheduling / cancellation / reschedule | App service (`NotificationScheduler`, new) | OS (`UNUserNotificationCenter`) | Isolated, mockable business logic separated from system I/O |
| Notification delivery + system permission prompt | OS (UserNotifications) | App service | OS owns delivery; app owns request + content/category |
| List / Calendar / Edit UI | Client (SwiftUI) | Database (`@Query`) | Views use `@Query`, `@State`, `@Bindable`, `.sheet` |
| Auto-save debounce | Client (SwiftUI) | Database (`context.save()`) | Debounce in view layer; persistence via modelContext |
| Search | Client (`.searchable`) | Database (`@Query` filter) | Native composition over title + block text |
| Calendar aggregation (per-day counts, completion) | Client (derived) | Database (`@Query`) | Derived live; no extra stored data (D3-16) |
| Accessibility | Client (SwiftUI) | — | VoiceOver labels, Dynamic Type |
| Testing | Test target (`MyHomeTests`, Swift Testing) | — | Model + scheduler + migration tests |

---

## Standard Stack for Phase 3

### Core (Project Standard)

| Tech | Version | Purpose | Why Reuse |
|------|---------|---------|-----------|
| **Swift** | 6.2 | Language | Current; strict concurrency |
| **SwiftUI** | iOS 17+ | View framework | `@Observable`, `ContentUnavailableView`, improved List |
| **SwiftData** | iOS 17+ | Model + persistence | CloudKit-ready; used in Phase 1/2 |
| **Swift Testing** | Xcode 26.5 toolchain | Unit testing | TDD default; async/await-native; in `MyHomeTests` |
| **UserNotifications** | iOS 17+ | Scheduled local notifications | First-party; no third-party `[CITED: developer.apple.com/documentation/usernotifications]` |

### New to Phase 3

| Tech | Version | Purpose | Why |
|------|---------|---------|-----|
| **UserNotifications** | iOS 17+ | Local notifications, actionable categories, calendar triggers | Standard framework, no dependency |
| **EventKit** | iOS 17+ | (Optional) calendar data | NOT needed — calendar is a custom SwiftUI `LazyVGrid` over reminder records (D3-17) |

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| Custom `LazyVGrid` calendar | Native/3rd-party calendar component | SwiftUI ships no calendar grid; 3rd-party violates the no-dependency rule. Custom grid is the locked choice (D3-17). |
| Embedded reminder fields | Separate `Reminder` `@Model` | Separate entity adds relationship inversions and breaks "reminders on both note and block" cleanly (D3-02). Embedded fields chosen. |
| `UNTimeIntervalNotificationTrigger` | `UNCalendarNotificationTrigger(repeats:true)` | Calendar trigger = one pending slot per recurrence; time-interval expands. Calendar trigger chosen (D3-14). |

**No packages installed:** This phase adds zero external dependencies — all frameworks are first-party Apple SDKs. The Package Legitimacy Audit and Environment Availability registry checks are therefore N/A (see those sections).

### Do Not Use

- Rich text editors (TextKit, RichTextKit) — out of scope, forbidden. Use `TextField`, not `TextEditor`.
- Third-party note/checklist/calendar libraries — forbidden, must be in-app.
- Combine — use `@Observable`.
- `@StateObject`, `@Published`, `@ObservedObject` — forbidden per Phase 1/2 pattern.
- A repository layer — views use `@Query` + `modelContext` directly.

---

## Package Legitimacy Audit

**N/A — this phase installs no external packages.** All technologies are first-party Apple
frameworks (SwiftUI, SwiftData, UserNotifications, Swift Testing) bundled with the Xcode 26.5
toolchain. There is no npm/PyPI/crates surface to audit, and no slopcheck/registry verification
is applicable. Should any task introduce a third-party Swift package, that violates the locked
"no third-party libraries" constraint and must be rejected at plan-check rather than audited here.

---

## Data Model Design

### Core Entities

```swift
@Model
final class Note {
    var id: UUID = UUID()          // CloudKit-ready PK (NO @Attribute(.unique))
    var title: String = ""         // Required at the UX layer; defaulted for CloudKit
    @Relationship(deleteRule: .cascade, inverse: \NoteBlock.note)
    var blocks: [NoteBlock]? = []  // Ordered block list (optional per rule)
    var isPinned: Bool = false
    var createdAt: Date = Date()   // UTC
    var modifiedAt: Date = Date()  // UTC

    // Reminder fields (note-level reminder)
    var reminderEnabled: Bool = false
    var reminderDate: Date?        // UTC; nil if no reminder
    var reminderIsAllDay: Bool = false
    var reminderRecurrenceData: Data?  // encoded ReminderRecurrence (Codable value type)
    var reminderEndRuleData: Data?     // encoded ReminderEndRule
    var reminderLeadMinutes: Int = 0   // 0 = no advance alert
}

@Model
final class NoteBlock {
    var id: UUID = UUID()
    var kindRaw: String = "text"   // "text" | "checkbox" — stored as String, NOT a stored enum
    var text: String = ""
    var isChecked: Bool = false    // checkboxes only
    var order: Int = 0             // position in note's block list
    var note: Note?                // inverse declared on ONE side only

    // Reminder fields (block-level reminder)
    var reminderEnabled: Bool = false
    var reminderDate: Date?
    var reminderIsAllDay: Bool = false
    var reminderRecurrenceData: Data?
    var reminderEndRuleData: Data?
    var reminderLeadMinutes: Int = 0
}

// Codable value types — encoded to Data, NOT stored as SwiftData enums (rule 5)
enum RecurrenceType: String, Codable { case none, daily, weekly, monthly, yearly }
struct ReminderRecurrence: Codable {
    var type: RecurrenceType = .none
    var weekdays: [Int]? = nil     // 1=Sun..7=Sat (Calendar component convention) if .weekly
}
enum EndRuleType: String, Codable { case never, onDate, afterCount }
struct ReminderEndRule: Codable {
    var type: EndRuleType = .never
    var endDate: Date? = nil
    var occurrenceCount: Int? = nil
}
```

### Rationale (refined for the 8 CloudKit rules)

- **No `@Attribute(.unique)`** on `id` — `.unique` is forbidden under CloudKit (rule 3). Use a defaulted `UUID`.
- **All fields optional or defaulted** (rule 2) — a reminder-less note has `reminderEnabled = false`, dates nil.
- **`@Relationship(inverse:)` on ONE side only** — declared on `Note.blocks`, not on `NoteBlock.note`, to avoid the "circular reference resolving attached macro" error noted in SchemaV2.swift (rule 4).
- **No stored enums** (rule 5, FB13812722) — `kindRaw` is a `String`; recurrence/end-rule are Codable value types serialized to `Data?` (queryable structure not needed on them).
- **UTC dates** (rule 6) — all stored dates UTC; convert to device timezone only for display and trigger construction.
- **`order: Int`** — explicit ordering allows drag-to-reorder later without a breaking migration.

> The exact field set is the planner's call (D3-19) provided the 8 rules hold. The shape above is the recommended, rule-compliant baseline.

---

## Notification Service Architecture

### Design

Create an isolated `NotificationScheduler` service that:
1. Requests permission on first reminder creation (in-context, D3-12).
2. Schedules `UNUserNotificationCenter` requests per reminder.
3. Cancels requests when reminders are deleted or rows are checked (D3-04).
4. Reschedules on edit (recurrence/date/time change) — the reschedule-on-edit flow (D3-19).
5. Tracks "after N" occurrence counts app-side (native repeating triggers do not self-stop, D3-11).
6. Respects the iOS 64-pending-notification cap (D3-15).

### Why Isolated?

- **Testable**: the pure scheduling/recurrence-expansion logic is separated from `UNUserNotificationCenter` I/O behind a protocol, so it is unit-testable without a live notification center (see Validation Architecture L1).
- **Reusable**: callable from UI, edit flows, and notification action handlers.
- **Decoupled**: notification logic does not pollute the model layer.

### Recommended seam (for testability)

```swift
protocol NotificationCenterPort {
    func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool
    func add(_ request: UNNotificationRequest) async throws
    func removePendingNotificationRequests(withIdentifiers ids: [String])
    func pendingNotificationRequests() async -> [UNNotificationRequest]
}
// Production conformer wraps UNUserNotificationCenter.current().
// Test conformer is an in-memory spy → unit tests assert on requests/identifiers
// without touching the OS notification center.

struct NotificationScheduler {
    let center: NotificationCenterPort

    func buildRequests(for reminder: ReminderInfo) throws -> [UNNotificationRequest] {
        // PURE function: main fire + each lead-time alert + recurrence trigger.
        // Unit-tested directly — no OS, no async required.
    }
    func schedule(_ reminder: ReminderInfo) async throws { /* center.add per request */ }
    func cancel(reminderID: UUID, leadCount: Int) { /* removePending by identifier set */ }
    func pendingCount() async -> Int { await center.pendingNotificationRequests().count }
}
```

The key insight: keep `buildRequests` **pure** so the request set (identifiers, triggers, lead alerts, recurrence) can be asserted in unit tests; only `schedule`/`cancel` touch the `center` port.

---

## UI Architecture

### List View

- **Sections**: Daily Routine (auto-derived from daily-recurring reminders) → Pinned → Other Notes (most-recent-first).
- **Cells**: Note title, pin icon, reminder count badge.
- **Toolbar**: "+" to add a new note; `.searchable` for title + block search.
- **Empty state**: `ContentUnavailableView` ("No Notes Yet" / "Tap + to capture…", per UI-SPEC).

### Calendar View

- **Control**: Segmented picker (List | Calendar) at the top of the Notes tab (D3-17).
- **Grid**: custom SwiftUI `LazyVGrid` month view; dot/count per day, derived live from reminder records.
- **Tap day**: date-grouped agenda of that day's reminders with completion progress (e.g. 2/5).
- **Empty state**: "No Reminders" / "Scheduled reminders will appear here."

### Edit Sheet

- **Title field** (required; untitled-on-dismiss = discard).
- **Block editor**: interleaved text blocks + checkbox rows, reorderable.
- **Reminder picker** (per note or per block): all-day toggle, date/time, recurrence menu (None/Daily/Weekly+weekdays/Monthly/Yearly), end-rule picker (Never/On Date/After N), lead-time minutes, and a pre-checked "Pin to top" toggle for yearly reminders (D3-09).

### Notification Handling

- **Permission**: prompted in-context on first reminder creation; denial → gentle Settings hint.
- **Actions**: Complete (checks the row per D3-04, cancels future advance alerts), Snooze (~1h).
- **Deep-link**: tapping a notification opens the relevant note/row.

---

## Migration & Schema Versioning

### From Phase 2 to Phase 3

- **Current**: `SchemaV2` with `Expense`, `Category`, `Tag` (top schema in `ModelContainer+App.swift`).
- **New**: `SchemaV3` copies V2's models verbatim and adds `Note` + `NoteBlock`.
- **Migration**: append a `v2ToV3` `.custom` stage to `AppMigrationPlan` (mirrors the existing `v1ToV2` stage; `.custom` over `.lightweight` sidesteps FB13812722).

### Migration Code Pattern

```swift
// SchemaV3.swift: copy V2's models verbatim, add Note + NoteBlock
enum AppMigrationPlan: SchemaMigrationPlan {
    static let schemas: [any VersionedSchema.Type] = [
        SchemaV1.self, SchemaV2.self, SchemaV3.self,
    ]
    static let stages: [MigrationStage] = [
        /* existing v1ToV2 stage */,
        MigrationStage.custom(
            fromVersion: SchemaV2.self,
            toVersion: SchemaV3.self,
            willMigrate: { _ in /* nothing: V3 adds only new models */ },
            didMigrate: { _ in /* seed/post-migration if needed */ }
        ),
    ]
}
```

### Typealias Flip

```swift
// After migration is wired: flip the top schema to SchemaV3 in ModelContainer+App.swift
typealias Note = SchemaV3.Note
typealias NoteBlock = SchemaV3.NoteBlock
```

---

## Common Pitfalls

### Pitfall 1: Rich-Text Temptation
**What goes wrong:** A "bold/formatting" affordance appears, violating the plain-text constraint.
**Why it happens:** Easy to overshoot scope.
**How to avoid:** Use `TextField`, never `TextEditor`/rich text; follow 03-UI-SPEC.md strictly.
**Warning signs:** Any `AttributedString` editing or formatting toolbar in the edit sheet.

### Pitfall 2: Nested Reminder Entity
**What goes wrong:** Modeling reminders as a separate `@Model` array, creating complex inversions.
**Why it happens:** Seems cleaner, but breaks "reminders on both note and block" (D3-02).
**How to avoid:** Embed reminder fields directly on `Note` and `NoteBlock`.
**Warning signs:** A `Reminder` `@Model` with two-way relationships to both `Note` and `NoteBlock`.

### Pitfall 3: Notification Loss
**What goes wrong:** Reminders scheduled but the model isn't saved; app restart → notifications vanish (or orphaned requests linger).
**Why it happens:** Forgetting `context.save()` after scheduling, or not cancelling on delete.
**How to avoid:** Always `context.save()` after `NotificationScheduler.schedule()`; cancel on row-check/delete.
**Warning signs:** Pending-request count drifting from enabled-reminder count.

### Pitfall 4: 64-Pending Cap Exceeded
**What goes wrong:** Too many repeating reminders; only the first 64 fire.
**Why it happens:** Multi-weekday weekly (one trigger per day, D3-10) and "after N" expansions.
**How to avoid:** Use `UNCalendarNotificationTrigger(repeats: true)` (one slot per recurrence); monitor `pendingCount()`; budget if the cap is approached.
**Warning signs:** Newly-scheduled reminders silently not firing.

### Pitfall 5: Timezone Gotcha
**What goes wrong:** All-day reminder fires at the wrong time due to UTC/local mixing.
**Why it happens:** `UNCalendarNotificationTrigger` interprets `DateComponents` in the device timezone.
**How to avoid:** Store dates UTC in SwiftData; convert to device timezone only when building the trigger and for UI display.
**Warning signs:** Reminders off by the device's UTC offset.

### Pitfall 6: Stored-Enum / `.unique` CloudKit Violation
**What goes wrong:** `@Attribute(.unique)` on `id` or a directly-stored enum breaks the additive migration / CloudKit readiness.
**Why it happens:** Habit from non-CloudKit Core Data.
**How to avoid:** Defaulted `UUID` PK (no `.unique`); store `kindRaw` as String, recurrence/end-rule as Codable `Data?`.
**Warning signs:** Migration fails or schema diverges from the 8 rules.

---

## Testing Strategy (TDD Default)

> This strategy is the implementation-facing companion to `## Validation Architecture` below.
> The Testing Strategy says *how we write the tests*; Validation Architecture maps each
> requirement/success-criterion to *the signal that proves it works and the layer that proves it*.

### Model Tests (Swift Testing, `MyHomeTests`)

Use a fresh in-memory `ModelContainer(isStoredInMemoryOnly: true)` per test (FND-06, the existing `ExpenseModelTests` pattern):

```swift
@Test("Note with interleaved blocks persists and preserves order")
func noteWithBlocksCreation() throws {
    let container = try ModelContainer(for: Note.self, NoteBlock.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    let ctx = container.mainContext
    let note = Note(title: "Test")
    note.blocks = [NoteBlock(kindRaw: "text", text: "Hello", order: 0),
                   NoteBlock(kindRaw: "checkbox", text: "Item 1", order: 1)]
    ctx.insert(note); try ctx.save()
    let fetched = try ctx.fetch(FetchDescriptor<Note>()).first
    #expect(fetched?.blocks?.count == 2)
    #expect(fetched?.blocks?.sorted{ $0.order < $1.order }[1].kindRaw == "checkbox")
}
```

### Notification Scheduler Tests (pure logic via the port)

```swift
@Test("Timed reminder with 2 lead alerts builds 3 requests")
func buildRequestsLeadAlerts() throws {
    let scheduler = NotificationScheduler(center: SpyCenter())
    let reqs = try scheduler.buildRequests(for: timedReminder(leadMinutes: [60, 1440]))
    #expect(reqs.count == 3)  // main + 2 advance
}

@Test("Weekly Mon/Wed/Fri yields one repeating trigger per weekday")
func weeklyMultiWeekday() throws { /* #expect 3 calendar triggers, repeats:true */ }

@Test("Checking a row cancels its pending requests")
func completeCancels() { /* SpyCenter records removed identifier set */ }
```

### Migration Test (mirrors existing `MigrationTests` load pattern)

```swift
@Test("v2 store loads cleanly under AppMigrationPlan with SchemaV3 target")
func v2StoreMigratesToV3() throws {
    // Bundle a MyHomeV2Seed.store; open with Schema(versionedSchema: SchemaV3.self);
    // assert it loads and pre-existing Expense rows survive.
}
```

### Recurrence / "After N" Tracking Tests (pure logic)

```swift
@Test("After-N end rule stops after the Nth occurrence")
func afterNStops() { /* app-side occurrence counter reaches N → no further reschedule */ }
```

---

## Validation Architecture

> **Nyquist Dimension 8.** This section maps every Phase 3 success criterion / requirement to
> (a) the observable signal that proves it works, (b) the validation layer, and (c) for anything
> that cannot run headless in CI, the explicit manual-UAT step. It reinforces — does not duplicate —
> the Testing Strategy above: Testing Strategy = how tests are written; this = what each requirement's
> proof-of-correctness is and where it lives.

### Test Framework

| Property | Value |
|----------|-------|
| Framework | Swift Testing (Xcode 26.5 toolchain), `import Testing` |
| Test target | `MyHomeTests` (existing; hosted, `@testable import MyHome`) |
| UI test target | None exists — UI/system-prompt/notification-delivery proof is **manual UAT** on simulator |
| Fixture pattern | In-memory `ModelContainer(isStoredInMemoryOnly: true)` per test (FND-06) |
| Migration fixture | Bundled seed `.store` copied to temp, opened under `AppMigrationPlan` (existing `MigrationTests` pattern) |
| Simulator | iPhone 17, Xcode 26.5, scheme/module `MyHome` (per MEMORY: use iPhone 17, **not** iPhone 16) |

### Layers

- **L1 — Unit (Swift Testing, headless, fast):** model persistence/order, pure scheduler `buildRequests`, recurrence expansion, "after N" tracking, search predicate, list ordering/sectioning logic, calendar aggregation (per-day counts + completion math).
- **L2 — Migration-load (Swift Testing, on-disk fixture):** V2→V3 additive migration opens cleanly; pre-existing Expense data survives.
- **L3 — Manual UAT (iPhone 17 simulator):** anything the OS owns or that is purely visual — the system permission prompt, actual notification **delivery**, Complete/Snooze action handling, deep-link routing, and the calendar/edit UI interactions. CI cannot assert these headlessly.

### Quick run / Full suite commands

```bash
# Full unit + migration suite (L1 + L2) on the iPhone 17 simulator:
xcodebuild test \
  -project MyHome.xcodeproj \
  -scheme MyHome \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  | xcbeautify   # or: | xcpretty  (pipe optional)

# Quick run of just the Notes/Reminders suites during a task loop:
xcodebuild test \
  -project MyHome.xcodeproj -scheme MyHome \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:MyHomeTests/NoteModelTests \
  -only-testing:MyHomeTests/NotificationSchedulerTests
```

### Requirement → Test Map

| Req / SC | Observable signal (proof) | Layer | Command / Manual step |
|----------|---------------------------|-------|-----------------------|
| NOT-01 | Note with title + blocks persists and refetches with title intact | L1 | `-only-testing:MyHomeTests/NoteModelTests/noteWithTitlePersists` |
| NOT-02 | Interleaved text + checkbox blocks persist and preserve `order` | L1 | `NoteModelTests/blockListPreservesOrder` |
| NOT-03 | List ordering = Daily Routine → Pinned → Other(recent-first); section/sort logic returns expected ordering | L1 (logic) + L3 (visual) | `NoteListOrderingTests/sectionOrdering`; **UAT:** create pinned + unpinned + daily-recurring notes, confirm section order on screen |
| NOT-04 | Toggling `isPinned` moves the note into the Pinned section | L1 + L3 | `NoteListOrderingTests/pinMovesToPinnedSection`; **UAT:** tap pin, confirm reorder |
| NOT-05 | Debounced auto-save commits ~500ms after last edit; no save button; reopen shows edits | L1 (debounce unit) + L3 (no-button + persistence) | `AutoSaveTests/debounceCommitsAfterQuiet`; **UAT:** edit, wait, kill+reopen, confirm persisted; confirm no save button |
| NOT-06 | `.searchable` predicate matches title + block text; non-matches excluded | L1 (predicate) + L3 (UI) | `NoteSearchTests/matchesTitleAndBlockText`; **UAT:** type query, confirm filtered list |
| SC-R1 (reminders) | Reminder fields persist on Note AND NoteBlock; all-day vs timed flag honored; lead-time adds extra requests | L1 | `NotificationSchedulerTests/buildRequestsLeadAlerts`, `ReminderModelTests/reminderOnNoteAndBlock` |
| SC-R2 (recurrence) | Daily/Weekly(weekdays)/Monthly/Yearly produce correct repeating triggers; "after N" stops at N; end-on-date stops | L1 | `NotificationSchedulerTests/weeklyMultiWeekday`, `RecurrenceTests/afterNStops`, `RecurrenceTests/endOnDateStops` |
| SC-R3 (notifications) | (a) Scheduler emits correct requests/identifiers/categories; (b) permission prompt appears on **first** reminder; (c) notification actually **fires**; (d) Complete checks row + cancels future; (e) Snooze refires ~1h; (f) tap deep-links | L1 (a,d-cancel) + **L3** (b,c,e,f) | `NotificationSchedulerTests/*` for (a)(d); **UAT (mandatory):** set a 1-min timed reminder → confirm prompt on first use → confirm banner fires → tap Complete (row checks, future alert cancelled) → tap Snooze (refires) → tap banner (opens note/row) |
| SC-R4 (calendar) | (a) Per-day count aggregation correct; (b) tapped-day agenda + completion progress correct; (c) grid renders | L1 (a,b math) + **L3** (c grid + tap) | `CalendarAggregationTests/perDayCountsAndProgress`; **UAT:** open Calendar segment, confirm day dots/counts, tap a day, confirm agenda + x/y progress |
| SC-R5 (Daily Routine + auto-pin) | Daily-recurring notes appear in Daily Routine; yearly reminder shows pre-checked "Pin to top" toggle | L1 (filter) + L3 (toggle UI) | `NoteListOrderingTests/dailyRoutineFilter`; **UAT:** create yearly reminder → confirm pre-checked pin toggle; create daily-recurring → confirm Daily Routine placement |
| Migration | V2→V3 store opens under `AppMigrationPlan`; Expense rows survive | L2 | `MigrationTests/v2StoreMigratesToV3` |
| 64-cap (D3-15) | `pendingCount()` stays ≤ 64 under multi-weekday-weekly + after-N load; budgeting kicks in if approached | L1 | `NotificationSchedulerTests/pendingCountUnderCap` |

### Manual UAT Checklist (L3 — cannot be automated in CI)

Run on iPhone 17 simulator (notification **delivery** and the system permission prompt do work in the simulator; record pass/fail in VERIFICATION.md):

- [ ] **First-reminder permission prompt** appears in-context (not on launch); denying shows the Settings hint.
- [ ] A **timed reminder fires** a banner at the set time (use a 1–2 min offset).
- [ ] **Complete** action checks the target row (D3-04) and cancels its future advance alerts.
- [ ] **Snooze** action re-fires ~1h later.
- [ ] **Tapping** a delivered notification deep-links into the correct note/row.
- [ ] **Calendar** segment shows correct per-day counts; tapping a day shows the agenda + completion progress.
- [ ] **Auto-save**: edit, wait ~1s, force-quit, reopen — edits persisted; **no save button** anywhere.
- [ ] **VoiceOver** labels present on checkbox, pin, and reminder controls; Dynamic Type scales text.

### Sampling Rate

- **Per task commit:** quick `-only-testing:` run of the touched suite (L1).
- **Per wave merge:** full `xcodebuild test` (L1 + L2) green.
- **Phase gate:** full suite green AND the Manual UAT Checklist completed/recorded before `/gsd-verify-work`.

### Wave 0 Gaps (test infra to create before implementation)

- [ ] `MyHomeTests/NoteModelTests.swift` — NOT-01, NOT-02 (persistence + order)
- [ ] `MyHomeTests/NoteListOrderingTests.swift` — NOT-03, NOT-04, SC-R5 (sectioning/sort/Daily Routine)
- [ ] `MyHomeTests/NoteSearchTests.swift` — NOT-06 (search predicate)
- [ ] `MyHomeTests/AutoSaveTests.swift` — NOT-05 (debounce unit)
- [ ] `MyHomeTests/NotificationSchedulerTests.swift` — SC-R1, SC-R3(a,d), 64-cap; requires the `NotificationCenterPort` + `SpyCenter` seam
- [ ] `MyHomeTests/RecurrenceTests.swift` — SC-R2 ("after N", end-on-date, weekly weekdays)
- [ ] `MyHomeTests/CalendarAggregationTests.swift` — SC-R4(a,b) (per-day counts + completion math)
- [ ] `MyHomeTests/MigrationTests.swift` — extend existing file with `v2StoreMigratesToV3`; **add a bundled `MyHomeV2Seed.store`** to the `MyHomeTests` Copy-Bundle-Resources phase (mirror the existing `MyHomeV1Seed.store` setup)
- [ ] Shared test helper: `SpyCenter` conforming to `NotificationCenterPort` + reminder fixture builders

*(Framework install: none — Swift Testing + `MyHomeTests` already exist from Phase 1/2.)*

---

## Security Domain

> `security_enforcement: true`, `security_asvs_level: 1`, `security_block_on: high`.
> Notes are explicitly **non-financial** (per PROJECT.md: Face ID protects financial data; the
> app-level Face ID gate is Phase 5, SEC-01). This phase is single-user, local-only, no network,
> no auth surface, no third-party code. The applicable ASVS L1 surface is therefore narrow.

### Applicable ASVS Categories (L1)

| ASVS Category | Applies | Standard Control |
|---------------|---------|-----------------|
| V2 Authentication | No | No auth in this phase; app-lock is Phase 5 (SEC-01/02) |
| V3 Session Management | No | No sessions/network |
| V4 Access Control | No | Single-user local app; no multi-user authz |
| V5 Input Validation | Yes (light) | Title/block text is free-form plain text persisted via SwiftData (parameterized; no SQL string-building, no injection surface). Validate only: non-empty title rule (D3-03), bounded lead-time/occurrence integers (reject negatives), and weekday set within 1–7 |
| V6 Cryptography | No | No secrets, no encryption in scope (per-note encryption is explicitly out of charter) |
| V7 Error Handling / Logging | Yes (light) | Surface save/permission failures via UI copy (UI-SPEC error states); do **not** log note body content to console/telemetry (zero-telemetry charter) |
| V10/V12 Files/Resources | No | No file uploads/imports in scope |
| V13 API / Notifications | Yes (light) | Notification **content** should avoid leaking sensitive body text on the lock screen if a row is sensitive — acceptable for v1 (household, single device); note as a v2 consideration |

### Known Threat Patterns for this stack

| Pattern | STRIDE | Standard Mitigation |
|---------|--------|---------------------|
| SQL/predicate injection via search/text | Tampering | SwiftData `#Predicate` / `FetchDescriptor` are type-safe — never build raw query strings |
| Unbounded integer inputs (lead-time, "after N") | Tampering / DoS (64-cap exhaustion) | Validate/clamp lead-minutes and occurrence counts; enforce the 64-cap budget (D3-15) |
| Sensitive note text on lock-screen notification | Information Disclosure | Acceptable for single-device v1; flag lock-screen content redaction for v2 |
| Notification content/PII in logs | Information Disclosure | No logging of note body; zero telemetry (charter) |

**Block-on-high assessment:** No HIGH-severity findings for this phase. Recommended controls (input clamping, no body logging) are LOW/MEDIUM and fold into normal task implementation — no security blocker for planning.

---

## Runtime State Inventory

> This is an **additive greenfield feature** (new `Note`/`NoteBlock` models, new tab), NOT a rename/
> refactor/migration of existing strings. The only "migration" is the additive `SchemaV2→V3` stage,
> covered above. Inventory included for completeness because the phase touches schema + the OS
> notification registry.

| Category | Items Found | Action Required |
|----------|-------------|------------------|
| Stored data | New `Note`/`NoteBlock` SwiftData entities only. No existing stored string is renamed. Existing `Expense`/`Category`/`Tag` rows are untouched and must survive V3 migration. | Additive migration + migration-load test (L2). No data migration of existing records. |
| Live service config | None — no external services, no UI/DB-only config to reconcile. | None — verified: app is local-only, no n8n/Datadog/etc. |
| OS-registered state | `UNUserNotificationCenter` pending requests + the registered actionable category (Complete/Snooze). These are created at runtime by `NotificationScheduler`, not pre-registered. Stale requests can orphan if not cancelled on delete/check. | Register the notification category at launch; cancel-on-delete/check; reconcile on reschedule-on-edit. |
| Secrets / env vars | None — no secrets, tokens, or env var names referenced (Gmail/Keychain is Phase 6). | None — verified. |
| Build artifacts | `SchemaV3.swift`, extended `MigrationPlan.swift`, new `Note`/`NoteBlock` typealiases; the `MyHomeTests` target needs a new bundled `MyHomeV2Seed.store` resource. | Add seed store to Copy-Bundle-Resources; flip top schema to V3. |

---

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| `@StateObject`/`ObservableObject`/Combine | `@Observable`/`@State`/`@Bindable` | iOS 17 / Swift 5.9+ | Project standard; forbidden to regress (PITFALLS) |
| XCTest for everything | Swift Testing for unit/model; XCTest only for UI | Swift Testing GA (Xcode 16+) | `MyHomeTests` uses Swift Testing (FND-06) |
| Stored SwiftData enums | Codable value types → `Data?` / raw String | FB13812722 workaround | `kindRaw: String`, recurrence as `Data?` |
| One-off per-occurrence notifications | `UNCalendarNotificationTrigger(repeats:true)` (1 slot/recurrence) | UserNotifications best practice | Keeps under the 64-cap (D3-14/15) |

**Deprecated/outdated for this phase:** UIKit, Core Data, third-party note/calendar libraries — all out of charter.

---

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | Phase 1/2 local persistence pattern (`@Query` + `context.save()`) is reusable as-is for notes/blocks/reminders `[ASSUMED]` | Summary / UI | Low — pattern is established; sync is deferred (local-only v1) |
| A2 | `.searchable` composes natively over title + a derived/block-text predicate `[ASSUMED]` | UI / NOT-06 | Medium — may need a custom in-memory filter if `#Predicate` can't reach into the block relationship text |
| A3 | The 64-pending cap is sufficient for household reminder volume `[CITED: developer.apple.com — 64 pending limit]` | Notification Service | Low-Medium — budgeting needed only at multi-weekday-weekly + after-N extremes |
| A4 | `UNCalendarNotificationTrigger(repeats:true)` covers daily/weekly/monthly/yearly; only "after N" needs app-side stop logic `[ASSUMED]` | Notification Service | Medium — verify monthly/yearly edge cases (e.g. Feb 29, day-31 months) during implementation |
| A5 | Notification delivery + the permission prompt are exercisable on the iPhone 17 simulator for UAT `[ASSUMED]` | Validation Architecture | Low — if simulator delivery is unreliable, UAT moves to a physical device |
| A6 | Suggested expanded requirement codes (NOT-07..10) are placeholders; roadmapper/planner finalizes `[ASSUMED]` | Phase Requirements | Low — traceability bookkeeping only |

---

## Open Questions

1. **Checked-to-bottom grouping with interleaved text (D3-04/D3-19).** Do checked rows sink within a contiguous checklist run, or globally to the note's end past text blocks? — *Recommendation:* sink within the contiguous checklist run (preserves text/checkbox interleaving); planner + UI-SPEC confirm.
2. **Reschedule-on-edit (D3-19).** Cancel-all-and-rebuild vs. diff-and-patch the pending requests on reminder edit? — *Recommendation:* cancel-by-identifier-set then rebuild (simpler, fewer drift bugs); unit-test the rebuilt request set.
3. **`.searchable` reach into block text (A2).** Can a SwiftData `#Predicate` filter on related `NoteBlock.text`, or is an in-memory filter needed? — *Recommendation:* verify during Wave 0; have the in-memory filter ready as fallback.
4. **Monthly/yearly recurrence edge cases (A4).** Behavior for day-31 in short months and Feb-29 yearly. — *Recommendation:* decide a clamp rule (last-valid-day) and unit-test it.

---

## Environment Availability

> Phase 3 has **no external (non-Apple) dependencies** — no CLIs, services, runtimes, or packages
> beyond the Xcode toolchain and iOS SDK already in use since Phase 1. Registry/availability probing
> (npm/pip/cargo) is N/A.

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| Xcode | Build + test | ✓ (assumed per MEMORY) | 26.5 | — |
| iOS Simulator — iPhone 17 | L1/L2 tests + L3 UAT | ✓ (assumed) | iOS 17+ | iPhone 17 mandated by MEMORY (not iPhone 16); physical device if notification UAT unreliable |
| SwiftData / SwiftUI / UserNotifications / Swift Testing | All | ✓ (first-party, in toolchain) | iOS 17+ | — |

**Missing dependencies with no fallback:** None.
**Missing dependencies with fallback:** Notification-delivery UAT → physical device if simulator delivery proves unreliable (A5).

---

## Sources & References

**Primary (HIGH confidence):**
- `[CITED: developer.apple.com/documentation/swiftdata]` — SwiftData models, migration, `@Relationship`
- `[CITED: developer.apple.com/documentation/usernotifications]` — `UNUserNotificationCenter`, `UNCalendarNotificationTrigger`, actionable categories, 64-pending limit
- `[VERIFIED: codebase grep]` — existing `MyHomeTests` (Swift Testing, in-memory container, bundled-seed migration-load pattern), `Persistence/Schema/{SchemaV1,SchemaV2,MigrationPlan}.swift`, target names `MyHome` + `MyHomeTests`
- Phase 1/2 CONTEXT, 03-CONTEXT.md, 03-UI-SPEC.md, REQUIREMENTS.md, ROADMAP.md, STATE.md, MEMORY (iPhone 17 / Xcode 26.5)

**Secondary (MEDIUM confidence):**
- Apple HIG calendar/list patterns

**Tertiary (LOW confidence):**
- None

---

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — first-party only, follows Phase 1/2.
- Architecture: HIGH — block-list + isolated scheduler are proven patterns.
- Migration: HIGH — mirrors verified v1ToV2 + existing migration-load test.
- Validation Architecture: HIGH — commands grounded in the real `MyHome`/`MyHomeTests` setup; L3 split is honest about CI limits.
- Pitfalls / Security: HIGH — narrow, non-financial, local-only surface.
- Open questions: MEDIUM — checked-to-bottom semantics, search predicate reach, recurrence edge cases.

**Research date:** 2026-05-30 (refreshed)
**Valid until:** 2026-06-15

---

## RESEARCH COMPLETE

**Phase:** 03 - notes-checklists
**Confidence:** HIGH

### Key Findings

1. **Validation Architecture added** (Nyquist D8): three layers — L1 unit (model/scheduler/recurrence/calendar math via a `NotificationCenterPort` + `SpyCenter` seam), L2 migration-load (V2→V3 with a bundled `MyHomeV2Seed.store`), L3 manual UAT (permission prompt, notification delivery, Complete/Snooze, deep-link, calendar/auto-save UI) on the **iPhone 17** simulator. Every NOT-01..06 + SC-R1..R5 maps to a concrete signal, layer, and command/UAT step.
2. **Data model** refined to be strictly 8-rule compliant: no `.unique`, defaulted `UUID`, `kindRaw: String` (no stored enum), recurrence/end-rule as Codable `Data?`, inverse on one side only.
3. **Notification scheduler** designed around a pure `buildRequests` + a `NotificationCenterPort` so scheduling logic is unit-testable without the OS; only delivery/permission are UAT.
4. **Security (ASVS L1)** assessed: non-financial, local-only, no network/auth — only light input-validation + no-body-logging controls; no HIGH findings, no blocker.
5. **No external packages / dependencies** — first-party Apple frameworks only; Package Legitimacy Audit and registry probing are N/A.

### File Created
`.planning/phases/03-notes-checklists/03-RESEARCH.md`

### Ready for Planning
Research complete and Nyquist-ready. A VALIDATION.md can now be generated from the Validation Architecture section.

---

*Phase: 03-notes-checklists*
*Research refreshed: 2026-05-30*
