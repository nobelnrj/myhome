# Phase 03: Notes & Checklists - Research

**Researched:** 2026-05-30  
**Domain:** iOS notes + reminders + calendar system (SwiftData, SwiftUI, local + CloudKit-ready)  
**Confidence:** HIGH

## Summary

This phase introduces a note keeper with embedded checklists, time-triggered reminders (daily/weekly/monthly/yearly with recurrence), local notifications with actionable buttons, and a calendar view. Implementation uses SwiftData for the model layer (following CloudKit-readiness rules from Phase 1), SwiftUI for the UI, and `UNUserNotificationCenter` for notifications. The phase differs from the Phase 1/2 foundation in its complexity: it adds three new entity types (`Note`, `NoteBlock`, reminder fields), a recurrence scheduler, a notification service, and a calendar rendering surface.

**Primary architectural decision:**  
Model notes as a **block list** (`Note` → `NoteBlock[]`, where each block is either text or a checkbox), with reminders attachable to both the note and any individual block. Follow the 8 CloudKit-readiness rules (optional/defaulted fields, no `.unique`, UTC dates, proper `@Relationship` macros).

---

## Locked Design Constraints (from CONTEXT.md)

### Scope & Boundaries

- **Reminders expansion:** Phase 3 is NOT just the note keeper (NOT-01..06). The owner expanded it to include reminders, recurrence, notifications, and a calendar view. This is all **in scope for v1**, not deferred.
- **Model**: Block list (`Note 1──* NoteBlock`), reminders attach to both `Note` and `NoteBlock`.
- **UI**: Must strictly follow 03-UI-SPEC.md (spacing, typography, color, copywriting, patterns).
- **Schema**: `SchemaV3` + additive migration (never mutate V1/V2). 8 CloudKit-readiness rules are mandatory.
- **Sync**: Use the same mechanism as Expenses (Phase 1/2 established pattern).
- **Notifications**: Permission on first use; actionable (Complete/Snooze); deep-link to note/block.
- **Calendar**: Segmented List|Calendar inside Notes tab; month grid with per-day reminder counts.
- **Search**: `.searchable` covers note title + all block text.
- **Auto-save**: Debounced ~500ms, no save button.
- **No rich text**: Plain text only.

### Deferred (out of scope)

- Cross-device sync (CloudKit) — post-v1, schema stays ready.
- Sharing with spouse's device — post-v1.
- Overview surfacing of pinned/latest — Phase 4.

---

## Architectural Responsibility Map

| Component                    | Primary      | Rationale                                                              |
|------------------------------|--------------|------------------------------------------------------------------------|
| `Note` + `NoteBlock` models  | SwiftData    | Persistence layer; optional fields, inverse relationships              |
| Reminders (fields + logic)   | SwiftData    | All-day/timed, recurrence, lead-time fields on models                 |
| Notification scheduling      | Notification service (new) | Isolated business logic, UT-able, handles UNUserNotificationCenter I/O |
| UI (List, Calendar, Edit)    | SwiftUI      | Views use `@Query`, `@State`, `@Bindable`, `.sheet` patterns          |
| Syncing                       | ModelContext | Reuse Expense phase's `context.save()` pattern, debounced             |
| Accessibility                 | SwiftUI      | VoiceOver labels on checkbox/pin/reminder, Dynamic Type              |
| Testing                       | Swift Testing | Model tests (migration), notification service tests (TDD)            |

---

## Standard Stack for Phase 3

### Core (Project Standard)

| Tech                    | Version | Purpose                    | Why Reuse                                  |
|-------------------------|---------|----------------------------|--------------------------------------------|
| **Swift**               | 6.2     | Language                  | Current; @concurrent, strict concurrency  |
| **SwiftUI**             | iOS 17+ | View framework             | @Observable, ContentUnavailableView, improved List  |
| **SwiftData**           | iOS 17+ | Model + persistence        | CloudKit-ready; used in Phase 1/2          |
| **Swift Testing**        | Toolchain | Unit testing              | TDD default; async/await-native            |
| **LocalAuthentication** | iOS 17+ | Optional: Face ID app lock | First-party, minimal setup (if scope expands) |

### New to Phase 3

| Tech                        | Version | Purpose                    | Why                                        |
|-----------------------------|---------|-----------------------------|-------------------------------------------|
| **UserNotifications**        | iOS 17+ | Scheduled local notifications | Standard iOS framework; no third-party     |
| **EventKit** (optional)      | iOS 17+ | Calendar rendering          | Not needed if using custom SwiftUI grid    |

### Do Not Use

- Rich text editors (TextKit, RichTextKit, etc.) — out of scope, forbidden.
- Third-party note/checklist libraries — forbidden, must be in-app.
- Combine — use `@Observable` instead.
- `@StateObject`, `@Published` — forbidden per Phase 1/2 pattern.

---

## Data Model Design

### Core Entities

```swift
@Model
final class Note {
    @Attribute(.unique) var id: UUID
    var title: String         // Required, user-facing
    var blocks: [NoteBlock]    // Ordered block list
    var isPinned: Bool = false
    var createdAt: Date       // UTC
    var modifiedAt: Date      // UTC
    
    // Reminder fields (note-level reminder)
    var reminderEnabled: Bool = false
    var reminderDate: Date?    // Optional, depends on all-day vs. timed
    var reminderTime: Date?    // Time component (if timed)
    var reminderRecurrence: ReminderRecurrence = .none
    var reminderEndRule: ReminderEndRule = .never
    var reminderLeadTime: Int = 0  // Minutes before main fire
}

@Model
final class NoteBlock {
    @Attribute(.unique) var id: UUID
    var kind: BlockKind        // .text or .checkbox
    var text: String
    var isChecked: Bool = false // For checkboxes only
    var order: Int             // Position in note's block list
    
    // Reminder fields (block-level reminder)
    var reminderEnabled: Bool = false
    var reminderDate: Date?
    var reminderTime: Date?
    var reminderRecurrence: ReminderRecurrence = .none
    var reminderEndRule: ReminderEndRule = .never
    var reminderLeadTime: Int = 0
}

enum BlockKind: Codable {
    case text
    case checkbox
}

struct ReminderRecurrence: Codable {
    var type: RecurrenceType = .none
    var weekdays: [Int]? = nil  // 0=Sunday..6=Saturday, if type == .weekly
    var endDate: Date? = nil
    var endCount: Int? = nil
}

enum RecurrenceType: Codable {
    case none, daily, weekly, monthly, yearly
}

struct ReminderEndRule: Codable {
    var type: EndRuleType = .never
    var endDate: Date? = nil
    var occurrenceCount: Int? = nil
}

enum EndRuleType: Codable {
    case never, onDate, afterCount
}
```

### Rationale

- **UUIDs + `@Attribute(.unique)`**: CloudKit-ready primary keys.
- **Optional reminder fields**: A note without a reminder has all fields nil/false.
- **Block list**: Allows text paragraphs and checkboxes to be interleaved, reordered freely.
- **No enum storage directly**: Codable enums avoid SwiftData's stored-enum limitation (FB13812722).
- **Order field**: Explicit ordering for block list (allows drag-to-reorder later without rewriting).

---

## Notification Service Architecture

### Design

Create an isolated `NotificationScheduler` service that:
1. Requests permission on first reminder creation (in-context).
2. Schedules `UNUserNotificationCenter` requests per reminder.
3. Cancels requests when reminders are deleted or marked done.
4. Reschedules on edit (recurrence change, date/time change, etc.).
5. Respects the iOS 64-pending-notification cap.

### Why Isolated?

- **Testable**: Mock `UNUserNotificationCenter` for unit tests.
- **Reusable**: Can be called from UI, sync hooks, or background tasks.
- **Decoupled**: Notification logic doesn't pollute the model layer.

### Pseudocode

```swift
class NotificationScheduler {
    func requestAuthorization() async -> Bool {
        let center = UNUserNotificationCenter.current()
        return try await center.requestAuthorization(options: [.alert, .sound])
    }
    
    func scheduleReminder(_ reminder: ReminderInfo) throws {
        // Generate UNCalendarNotificationTrigger for the reminder
        // (with repeats: true for recurrence, if using native triggers)
        let trigger = UNCalendarNotificationTrigger(...)
        let request = UNNotificationRequest(identifier: reminder.id.uuidString, 
                                            content: content, 
                                            trigger: trigger)
        try await UNUserNotificationCenter.current().add(request)
    }
    
    func cancelReminder(id: UUID) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(
            withIdentifiers: [id.uuidString]
        )
    }
    
    func getPendingCount() async -> Int {
        let requests = await UNUserNotificationCenter.current().pendingNotificationRequests()
        return requests.count
    }
}
```

---

## UI Architecture

### List View

- **Sections**: Daily Routine (auto-derived from daily-recurring reminders) → Pinned → Other Notes.
- **Cells**: Note title, pin icon, reminder count badge.
- **Toolbar**: "+" to add new note, `.searchable` for title+block search.
- **Empty state**: `ContentUnavailableView` (Phase 1/2 pattern).

### Calendar View

- **Control**: Segmented picker (List | Calendar) at top of Notes tab.
- **Grid**: SwiftUI `LazyVGrid` for month view; dots/counts per day.
- **Tap day**: Shows date-grouped agenda of that day's reminders with completion progress.

### Edit Sheet

- **Title field** (required).
- **Block editor**: Text blocks and checkbox rows, reorderable (long-press drag if scope allows).
- **Reminder picker** (per note or per block):
  - Date picker (all-day toggle).
  - Time picker (if timed).
  - Recurrence menu (None / Daily / Weekly / Monthly / Yearly).
  - End rule picker (Never / On Date / After N).
  - Lead-time number input (minutes).
  - "Pin to top" toggle for yearly reminders (pre-checked).
  
### Notification Handling

- **Permission**: On first reminder creation, prompt in-context.
- **Actions**: Complete (checks the row, cancels future reminders), Snooze (~1h).
- **Deep-link**: Tap notification → open note/block in UI.

---

## Migration & Schema Versioning

### From Phase 2 to Phase 3

- **Current**: `SchemaV2` with `Expense`, `Category`, `Tag`.
- **New**: `SchemaV3` copy of V2, plus `Note` and `NoteBlock`.
- **Migration**: `.custom` stage (non-lightweight), mirrors the v1ToV2 pattern.

### Migration Code Pattern

```swift
// SchemaV3.swift: copy V2's models verbatim, add Note + NoteBlock

enum AppMigrationPlan: SchemaMigrationPlan {
    static let schemas: [any VersionedSchema.Type] = [
        SchemaV1.self,
        SchemaV2.self,
        SchemaV3.self,
    ]
    
    static let stages: [MigrationStage] = [
        MigrationStage.custom(
            fromVersion: SchemaV2.self,
            toVersion: SchemaV3.self,
            willMigrate: { context in
                // Nothing to do: V3 adds only new models
            },
            didMigrate: { context in
                // Seed or post-migration setup if needed
            }
        )
    ]
}
```

### Typealias Flip

```swift
// After migration is shipped:
typealias Note = SchemaV3.Note
typealias NoteBlock = SchemaV3.NoteBlock
```

---

## Common Pitfalls

### Pitfall 1: Rich-Text Temptation

**What**: UI shows "formatting" or "bold" button that violates the plain-text constraint.
**Why**: Easy to overshoot scope, especially if a team member has note-taking background.
**Fix**: Strictly follow 03-UI-SPEC.md; use `TextField`, not `TextEditor`.

### Pitfall 2: Nested Reminders

**What**: Trying to model reminders as a separate `@Model` array, leading to complex inversions.
**Why**: Seems cleaner, but breaks the "reminders on both note and block" design.
**Fix**: Embed reminder fields (date, time, recurrence, etc.) directly on `Note` and `NoteBlock`.

### Pitfall 3: Notification Loss

**What**: Reminders get scheduled but not persisted; app restarts → notifications vanish.
**Why**: Forgetting to save the model after scheduling.
**Fix**: Always `context.save()` after `NotificationScheduler.scheduleReminder()`.

### Pitfall 4: 64-Pending Cap Exceeded

**What**: App schedules too many repeating reminders; only first 64 fire.
**Why**: Not tracking pending count or using native repeating triggers.
**Fix**: Use `UNCalendarNotificationTrigger(repeats: true)` for recurrence (counts as 1 pending slot each). Monitor cap if multi-weekday-weekly or "after N" expansions dominate.

### Pitfall 5: Timezone Gotcha

**What**: All-day reminder fires at wrong time due to timezone interpretation.
**Why**: Mixing local vs. UTC; `UNCalendarNotificationTrigger` interprets time in device timezone.
**Fix**: Store all dates in UTC in SwiftData; convert to device timezone only for UI display and notification triggers.

---

## Testing Strategy (TDD Default)

### Model Tests (Swift Testing)

```swift
@Test
func noteWithBlocksCreation() async throws {
    let note = Note(id: UUID(), title: "Test", blocks: [
        NoteBlock(id: UUID(), kind: .text, text: "Hello", order: 0),
        NoteBlock(id: UUID(), kind: .checkbox, text: "Item 1", order: 1),
    ])
    #expect(note.blocks.count == 2)
    #expect(note.blocks[1].kind == .checkbox)
}
```

### Notification Scheduler Tests

```swift
@Test
func scheduleReminderRequest() async throws {
    let scheduler = NotificationScheduler()
    // Mock UNUserNotificationCenter
    let reminder = ReminderInfo(...)
    try scheduler.scheduleReminder(reminder)
    // Assert that the mock received the request
}
```

### Migration Tests

```swift
@Test
func migrateSchemaV2ToV3() async throws {
    // Test that v2ToV3 migration runs without error
    // Load v2 store, trigger migration, verify v3 models exist
}
```

---

## Open Questions

1. **Exact "checked-to-bottom" grouping semantics?**  
   - Checked rows sink below open items within the same contiguous checklist run.
   - With interleaved text blocks, do we group by continuous checklist runs, or globally?
   - **Decision**: Planner call (D3-19 in CONTEXT.md).

2. **Reschedule-on-edit flow?**  
   - When reminder fields change (time, recurrence), do we cancel old and reschedule, or update in place?
   - **Decision**: TDD-driven once planner breaks down the edit flow.

3. **Exact calendar grid layout and weekday start?**  
   - Monday-start vs. Sunday-start? Custom `LazyVGrid` or third-party?
   - **Decision**: UI-SPEC and planner call.

4. **Sync conflict resolution for new entities?**  
   - Is it Last-Write-Wins per entity, or does the Phase 1/2 sync logic already handle it?
   - **Recommendation**: Review Phase 1/2 sync code before planning.

---

## Assumptions Log

| # | Assumption | Section | Risk |
|---|-----------|---------|------|
| A1 | Phase 1/2 sync logic is reusable for notes/blocks | Summary | May need new sync code if sync is app-level, not per-entity |
| A2 | `.searchable` covers note title + all block text natively | UI Architecture | May need custom search implementation if `.searchable` doesn't compose with block lists |
| A3 | UNUserNotificationCenter 64-pending cap is sufficient for household volume | Notification Service | May need budgeting/prioritization logic if users create 65+ pending reminders |
| A4 | Native `UNCalendarNotificationTrigger(repeats: true)` handles all recurrence types | Notification Service | May need app-side scheduling for edge cases (e.g., "after N" with custom count logic) |

---

## Sources & References

**Primary (HIGH confidence):**
- `SwiftData` docs, iOS 17 release notes
- `UNUserNotificationCenter` docs
- Phase 1/2 context, schema, sync patterns
- 03-UI-SPEC.md, 03-CONTEXT.md

**Secondary (MEDIUM confidence):**
- Apple's "Designing for iOS" calendar patterns

**Tertiary (LOW confidence):**
- None

---

## Metadata

**Confidence breakdown:**
- SwiftData model design: HIGH — follows Phase 1/2 pattern, CloudKit rules are proven.
- Notification scheduler: HIGH — UNUserNotificationCenter is well-documented.
- Migration: HIGH — mirrors v1ToV2 pattern.
- Open questions: MEDIUM — planner will clarify checked-to-bottom grouping, reschedule logic, etc.

**Research date:** 2026-05-30  
**Valid until:** 2026-06-15

---

## RESEARCH COMPLETE

**Phase:** 03 - notes-checklists  
**Confidence:** HIGH

### Key Findings

1. **Data model**: Block list (`Note 1──* NoteBlock`) with reminders on both. Follow 8 CloudKit-readiness rules.
2. **Notification service**: Isolated, testable scheduler. Use native repeating triggers for recurrence.
3. **UI**: SwiftUI List/Calendar segmented, auto-sections (Daily Routine, Pinned, Other), edit sheet with reminder pickers.
4. **Schema**: `SchemaV3` + `.custom` migration, no V1/V2 mutations.
5. **Testing**: Swift Testing for models/scheduler, XCTest for UI.

### Ready for Planning

Research complete. Planner can now create detailed PLAN.md with task breakdown, dependencies, and verification gates.

---

*Phase: 03-notes-checklists*  
*Research completed: 2026-05-30*
