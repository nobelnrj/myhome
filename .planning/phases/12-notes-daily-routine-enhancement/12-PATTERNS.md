# Phase 12: Notes & Daily Routine Enhancement — Pattern Map

**Mapped:** 2026-06-13
**Files analyzed:** 16 (8 new, 8 modified)
**Analogs found:** 16 / 16

---

## File Classification

| New/Modified File | Role | Data Flow | Closest Analog | Match Quality |
|---|---|---|---|---|
| `MyHomeApp/Persistence/Schema/SchemaV9.swift` | schema | batch (additive model copy + new model) | `MyHomeApp/Persistence/Schema/SchemaV8.swift` | exact |
| `MyHomeApp/Persistence/Schema/MigrationPlan.swift` _(modify)_ | config | batch (append schema + nil-closure stage) | `MyHomeApp/Persistence/Schema/MigrationPlan.swift` lines 123–132 | exact |
| `MyHomeApp/Persistence/Models/RoutineCompletion.swift` _(new typealias)_ | model | CRUD | `MyHomeApp/Persistence/Models/Contribution.swift` + `SIP.swift` | exact |
| `MyHomeApp/Persistence/Models/Note.swift` _(flip typealias)_ | model | CRUD | itself — same flip pattern as prior schema bumps | exact |
| `MyHomeApp/Persistence/Models/NoteBlock.swift` _(flip typealias)_ | model | CRUD | same as Note.swift flip | exact |
| `MyHomeApp/Persistence/Models/Category.swift` _(flip typealias)_ | model | CRUD | same flip pattern | exact |
| `MyHomeApp/Persistence/Models/Account.swift` _(flip typealias)_ | model | CRUD | same flip pattern | exact |
| `MyHomeApp/Persistence/Models/Asset.swift` _(flip typealias)_ | model | CRUD | same flip pattern | exact |
| `MyHomeApp/Persistence/Models/Expense.swift` _(flip typealias)_ | model | CRUD | same flip pattern | exact |
| `MyHomeApp/Persistence/Models/NetWorthSnapshot.swift` _(flip typealias)_ | model | CRUD | same flip pattern | exact |
| `MyHomeApp/Persistence/Models/SIPAmountChange.swift` _(flip typealias)_ | model | CRUD | same flip pattern | exact |
| `MyHomeApp/Persistence/Models/SIP.swift` _(flip typealias)_ | model | CRUD | same flip pattern | exact |
| `MyHomeApp/Persistence/ModelContainer+App.swift` _(modify)_ | config | CRUD | itself — add SchemaV9 + RoutineCompletion | exact |
| `MyHomeApp/Features/Notes/RoutineNotificationService.swift` _(new)_ | service | request-response (async UNCalendarNotificationTrigger) | `MyHomeApp/Support/SIPAccrualService.swift` lines 483–512 | exact |
| `MyHomeApp/Features/Notes/StreakCalculator.swift` _(new)_ | utility | transform (pure function over [RoutineCompletion]) | `MyHomeApp/Features/Notes/RoutineResetService.swift` (IST calendar + day-boundary math) | role-match |
| `MyHomeApp/Features/Notes/RoutineDetailView.swift` _(new)_ | component | request-response | `MyHomeApp/Features/Assets/AssetDetailView.swift` (header card + insetGrouped List) | exact |
| `MyHomeApp/Features/Notes/EditNoteView.swift` _(modify: Routine section + drag-reorder + toggleCheck)_ | component | CRUD | itself (existing `groupBox`, `blockList`, `toggleCheck`, `markDirty`) | exact |
| `MyHomeApp/Features/Notes/CalendarView.swift` _(modify: DayAgendaView "Daily Routines" section)_ | component | CRUD | itself (existing `remindersOnDay`, `toggleCompletion`, `Section` structure) | exact |
| `MyHomeTests/SchemaV9MigrationTests.swift` _(new)_ | test | batch | `MyHomeTests/SchemaV8MigrationTests.swift` | exact |
| `MyHomeTests/StreakCalculatorTests.swift` _(new)_ | test | transform | `MyHomeTests/RoutineResetServiceTests.swift` (in-memory container, IST helpers) | role-match |
| `MyHomeTests/RoutineNotificationServiceTests.swift` _(new)_ | test | request-response | `MyHomeTests/RoutineResetServiceTests.swift` + SpyCenter pattern | role-match |
| `MyHomeTests/NoteReorderTests.swift` _(new)_ | test | CRUD | `MyHomeTests/RoutineResetServiceTests.swift` (makeContainer, NoteBlock seed) | role-match |

---

## Pattern Assignments

### `MyHomeApp/Persistence/Schema/SchemaV9.swift` (schema, additive)

**Analog:** `MyHomeApp/Persistence/Schema/SchemaV8.swift`

**File header and enum declaration** (SchemaV8.swift lines 1–39):
```swift
import SwiftData
import Foundation

/// VersionedSchema v9.0.0 — copies V8's models verbatim, adds routineDailyReminderTime
/// to Note, and introduces the new RoutineCompletion @Model (D-04, D-06, Phase 12).
///
/// Rules: (copy all 8 CloudKit-readiness rules verbatim from V8 header)
enum SchemaV9: VersionedSchema {
    static let versionIdentifier = Schema.Version(9, 0, 0)

    static var models: [any PersistentModel.Type] {
        [
            SchemaV9.Expense.self,
            SchemaV9.Category.self,
            SchemaV9.Note.self,
            SchemaV9.NoteBlock.self,
            SchemaV9.Account.self,
            SchemaV9.Asset.self,
            SchemaV9.NetWorthSnapshot.self,
            SchemaV9.SIP.self,
            SchemaV9.SIPAmountChange.self,
            SchemaV9.Contribution.self,
            // NEW in V9:
            SchemaV9.RoutineCompletion.self,
        ]
    }
```

**New field on SchemaV9.Note** (append after `routineLastResetDate` at SchemaV8.swift line 173):
```swift
// --- NEW in SchemaV9: daily routine notification time (D-04, Phase 12) ---
// Append AFTER all V8 Note fields (additive only — never reorder/remove existing fields).
// nil = no daily reminder configured. Date value; only .hour and .minute components used at scheduling.
var routineDailyReminderTime: Date? = nil   // D-04: optional daily fire time; nil = no reminder
```

**New RoutineCompletion @Model** (append as the 11th model, after Contribution):
```swift
// MARK: - RoutineCompletion @Model (NEW in SchemaV9 — D-06, D-08, Phase 12)

/// One completion record per routine note per IST day.
/// Bare UUID back-reference (NOT @Relationship) per Pitfall 5 / CloudKit rule 7.
/// dayKey stores IST start-of-day as UTC (same convention as NetWorthSnapshot.date).
/// No @Attribute(.unique) — CloudKit rule 2; idempotency via fetch-before-insert (D-06).
@Model
final class RoutineCompletion {
    // No @Attribute(.unique) — CloudKit rule 2.
    var id: UUID = UUID()                      // UUID primary key (rule 6)
    var noteID: UUID = UUID()                  // bare UUID back-ref to Note.id (NOT @Relationship — Pitfall 5/rule 7)
    var dayKey: Date = Date()                  // UTC; represents IST start-of-day (upsert key)
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

**Copy source for all other V9 models:** copy SchemaV8 models verbatim (Category, Expense, Note + new field, NoteBlock, Account, Asset, NetWorthSnapshot, SIP, SIPAmountChange, Contribution), replacing every `SchemaV8.` prefix with `SchemaV9.`.

---

### `MyHomeApp/Persistence/Schema/MigrationPlan.swift` (config, append stage)

**Analog:** `MyHomeApp/Persistence/Schema/MigrationPlan.swift` lines 11, 14, 123–132

**Schemas array** (line 11 — append SchemaV9):
```swift
static var schemas: [any VersionedSchema.Type] {
    [SchemaV1.self, SchemaV2.self, SchemaV3.self, SchemaV4.self, SchemaV5.self,
     SchemaV6.self, SchemaV7.self, SchemaV8.self, SchemaV9.self]  // append V9 — never remove V1–V8
}
```

**Stages array** (line 15 — append v8ToV9):
```swift
static var stages: [MigrationStage] {
    [v1ToV2, v2ToV3, v3ToV4, v4ToV5, v5ToV6, v6ToV7, v7ToV8, v8ToV9]
}
```

**New v8ToV9 stage** (mirror of `v7ToV8` at lines 127–132):
```swift
// V9 adds routineDailyReminderTime to Note and introduces RoutineCompletion @Model (D-04, D-06, Phase 12).
// Purely additive: routineDailyReminderTime defaults nil; RoutineCompletion is a new empty table.
// willMigrate/didMigrate are nil — no backfill needed.
// .custom over .lightweight: FB13812722 workaround preserved for all stages.
static let v8ToV9 = MigrationStage.custom(
    fromVersion: SchemaV8.self,
    toVersion: SchemaV9.self,
    willMigrate: nil,
    didMigrate: nil   // routineDailyReminderTime defaults nil; RoutineCompletion is new — no backfill
)
```

---

### Typealias Files — ALL 11 flipped atomically (STAB-08 footgun)

**Analog:** `MyHomeApp/Persistence/Models/Note.swift` (lines 1–27), `Contribution.swift` (lines 1–15), `SIP.swift` (lines 1–17)

**Pattern for existing typealias flip** (Note.swift lines 1–27 — copy this comment structure for all 10 existing files):
```swift
import SwiftData

/// Convenience typealias so views and tests use bare `Note` without the version prefix.
///
/// [... preserve full flip history comment ...]
/// Flipped from SchemaV8.Note → SchemaV9.Note in Phase 12 (plan 12-XX): the production
/// container is built with `Schema(versionedSchema: SchemaV9.self)`. SchemaV9.Note is an
/// additive superset of SchemaV8.Note — adds routineDailyReminderTime field (D-04), no removals.
/// All views and tests that use `Note` continue to compile unchanged.
///
/// STAB-08 lesson: this typealias was flipped atomically with all other model typealiases
/// and MigrationPlan.swift in one commit.
typealias Note = SchemaV9.Note      // was SchemaV8.Note
```

**Pattern for NEW RoutineCompletion.swift** (mirror of `Contribution.swift` lines 1–15):
```swift
import SwiftData

/// Convenience typealias for the Phase 12 RoutineCompletion model.
///
/// New in Phase 12 (plan 12-XX, SchemaV9). Records one completion per routine note per IST day
/// (D-06, NOTE-05). Written at check-time, before RoutineResetService can wipe isChecked overnight.
///
/// STAB-08 lesson: flip ALL typealiases together in the same commit that updates
/// AppMigrationPlan.schemas to include SchemaV9.self.
///
/// Usage:
///   let completion = RoutineCompletion(noteID: note.id, dayKey: dayKey)
///   @Query var completions: [RoutineCompletion]
typealias RoutineCompletion = SchemaV9.RoutineCompletion
```

**All 10 existing typealias changes (one-liner each):**
- `Category.swift` line 27: `SchemaV8.Category` → `SchemaV9.Category`
- `Contribution.swift` line 14: `SchemaV8.Contribution` → `SchemaV9.Contribution`
- `Account.swift`: `SchemaV8.Account` → `SchemaV9.Account`
- `Asset.swift`: `SchemaV8.Asset` → `SchemaV9.Asset`
- `Note.swift` line 26: `SchemaV8.Note` → `SchemaV9.Note`
- `NoteBlock.swift`: `SchemaV8.NoteBlock` → `SchemaV9.NoteBlock`
- `Expense.swift`: `SchemaV8.Expense` → `SchemaV9.Expense`
- `NetWorthSnapshot.swift`: `SchemaV8.NetWorthSnapshot` → `SchemaV9.NetWorthSnapshot`
- `SIPAmountChange.swift`: `SchemaV8.SIPAmountChange` → `SchemaV9.SIPAmountChange`
- `SIP.swift` line 16: `SchemaV8.SIP` → `SchemaV9.SIP`

---

### `MyHomeApp/Persistence/ModelContainer+App.swift` (config, modify)

**Analog:** itself — `MyHomeApp/Persistence/ModelContainer+App.swift` lines 17–45

**Two changes required:**
1. Line 18: `Schema(versionedSchema: SchemaV8.self)` → `Schema(versionedSchema: SchemaV9.self)`
2. The `ModelContainer(for: schema, ...)` call already uses `schema` (derived from `SchemaV9.self`), so `RoutineCompletion.self` is included automatically via `SchemaV9.models`. No additional `for:` argument needed.

**Save pattern** (lines 40–45 — unchanged):
```swift
let container = try ModelContainer(
    for: schema,
    migrationPlan: AppMigrationPlan.self,
    configurations: [config]
)
```

---

### `MyHomeApp/Features/Notes/RoutineNotificationService.swift` (service, request-response)

**Analog:** `MyHomeApp/Support/SIPAccrualService.swift` lines 483–512

**Imports pattern** (SIPAccrualService pattern — lines 483–506):
```swift
import Foundation
import UserNotifications
import SwiftData
```

**Core pattern — cancel-then-add with stable identifier** (SIPAccrualService lines 490–512):
```swift
struct RoutineNotificationService {
    private let center: any NotificationCenterPort

    init(center: any NotificationCenterPort = SystemNotificationCenter()) {
        self.center = center
    }

    // Stable identifier: distinct from kReminderCategoryID domain and SIP reconcile domain.
    static func identifier(for noteID: UUID) -> String {
        "routine-daily-\(noteID.uuidString)"
    }

    /// Cancel-then-add: guarantees exactly one pending request (D-05).
    /// CRITICAL: cancel is synchronous; add is async. Always cancel BEFORE awaiting add.
    func schedule(noteID: UUID, title: String, time: Date) async {
        // 1. Cancel synchronously first (D-05 — Pitfall 3 in RESEARCH)
        cancel(noteID: noteID)

        // 2. Build time-only DateComponents (mirrors SIPAccrualService lines 494-497)
        var cal = Calendar.current
        cal.timeZone = TimeZone.current
        let comps = cal.dateComponents([.hour, .minute], from: time)
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: true)

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = "Time for your daily routine"
        content.sound = .default
        content.categoryIdentifier = kReminderCategoryID  // enables Complete action (NotificationActions.swift line 9)
        // T-12-XX: userInfo contains ONLY noteID + isRoutineReminder flag — no note body text
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

**Re-schedule on save (call from EditNoteView onChange/onDismiss):**
```swift
Task {
    if let time = note.routineDailyReminderTime, note.isDailyRoutine {
        await RoutineNotificationService().schedule(noteID: note.id, title: note.title, time: time)
    } else {
        RoutineNotificationService().cancel(noteID: note.id)
    }
}
```

**Also cancel on note deletion** (mirrors `cancelBlockReminder` in EditNoteView.swift lines 384–402):
```swift
// In deleteNote(), before context.delete(note):
RoutineNotificationService().cancel(noteID: note.id)
```

---

### `MyHomeApp/Features/Notes/StreakCalculator.swift` (utility, transform)

**Analog:** `MyHomeApp/Features/Notes/RoutineResetService.swift` lines 25–29 (IST calendar discipline), `MyHomeApp/Persistence/Schema/SchemaV8.swift` lines 282–300 (NetWorthSnapshot — date-keyed upsert pattern)

**IST calendar** (RoutineResetService.swift lines 26–29 — copy exactly):
```swift
var istCal = Calendar(identifier: .gregorian)
istCal.timeZone = TimeZone(identifier: "Asia/Kolkata")!
let startOfTodayIST = istCal.startOfDay(for: Date())
```

**Core pattern — pure enum with static compute function:**
```swift
struct DayStatus {
    let dayKey: Date      // IST start-of-day (UTC)
    let isCompleted: Bool
}

struct StreakResult {
    let currentStreak: Int      // D-07: consecutive completed days; today-incomplete does not break it
    let history: [DayStatus]    // last 30 days, newest first
}

enum StreakCalculator {
    static func compute(
        for noteID: UUID,
        completions: [RoutineCompletion],
        today: Date,        // injected for testability — do not call Date() internally
        calendar: Calendar  // inject IST calendar from caller
    ) -> StreakResult {
        // 1. Build completed dayKey set
        let completedDays = Set(
            completions
                .filter { $0.noteID == noteID }
                .map { calendar.startOfDay(for: $0.dayKey) }
        )
        // 2. Build 30-day window ending today
        var window: [DayStatus] = []
        for offset in 0..<30 {
            guard let day = calendar.date(byAdding: .day, value: -offset, to: calendar.startOfDay(for: today)) else { continue }
            window.append(DayStatus(dayKey: day, isCompleted: completedDays.contains(day)))
        }
        // 3. Streak walk — D-07: incomplete today does NOT break
        let todayKey = calendar.startOfDay(for: today)
        let todayCompleted = completedDays.contains(todayKey)
        let startOffset: Int = todayCompleted ? 0 : 1
        var streak = 0
        for offset in startOffset... {
            guard offset < 30,
                  let day = calendar.date(byAdding: .day, value: -offset, to: todayKey) else { break }
            if completedDays.contains(day) { streak += 1 } else { break }
        }
        return StreakResult(currentStreak: streak, history: window)
    }
}
```

---

### `MyHomeApp/Features/Notes/RoutineDetailView.swift` (component, request-response)

**Analog:** `MyHomeApp/Features/Assets/AssetDetailView.swift` lines 1–155

**Imports + struct declaration** (AssetDetailView.swift lines 1–17):
```swift
import SwiftUI
import SwiftData

/// Per-routine detail view — current streak, 30-day history.
///
/// Mirrors AssetDetailView: header card (cardStyle()) + detail List (.insetGrouped).
/// Plain Text() only — never AttributedString (T-11-10 pattern).
struct RoutineDetailView: View {
    var note: Note

    // @Query predicate captured via init (Pitfall 4 in RESEARCH.md)
    @Query private var completions: [RoutineCompletion]

    init(note: Note) {
        self.note = note
        let noteID = note.id
        self._completions = Query(
            filter: #Predicate<RoutineCompletion> { $0.noteID == noteID },
            sort: [SortDescriptor(\.dayKey, order: .reverse)]
        )
    }
```

**Header card section** (AssetDetailView.swift lines 67–74):
```swift
var body: some View {
    List {
        // Header card — mirrors AssetDetailView.swift lines 67-74
        Section {
            headerCard
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
        }
        // History section
        Section("Last 30 Days") {
            // ForEach over streakResult.history
        }
    }
    .listStyle(.insetGrouped)
    .navigationTitle(note.title)   // T-11-10 pattern: plain string access
    .navigationBarTitleDisplayMode(.inline)
}
```

**Header card content** (mirrors AssetDetailView.swift lines 119–151):
```swift
private var headerCard: some View {
    VStack(alignment: .leading, spacing: 4) {
        Text("Daily Routine")
            .font(.subheadline)
            .foregroundStyle(.secondary)

        Text("🔥 \(streakResult.currentStreak)")
            .font(.largeTitle.weight(.semibold))
            .foregroundStyle(.primary)

        Text(streakResult.currentStreak == 1 ? "day streak" : "days streak")
            .font(.body)
            .foregroundStyle(.secondary)

        Text(streakStatusLine)
            .font(.subheadline)
            .foregroundStyle(.secondary)
    }
    .cardStyle()   // Corner 16pt, secondarySystemBackground, shadow — mirrors AssetDetailView
}
```

**Gain color pattern for completion state** (AssetDetailView.swift lines 49–53):
```swift
// Completed days: Color(.systemGreen); missed days: .secondary
// — mirrors gainColor: Color(.systemGreen) / Color(.systemRed) pattern
```

---

### `MyHomeApp/Features/Notes/EditNoteView.swift` (component, CRUD — modify)

**Analog:** itself. All modifications extend existing patterns.

**State additions** (after existing `@State` block, lines 60–74):
```swift
@State private var editMode: EditMode = .inactive  // NOTE-04: drag-to-reorder

// @Query for completions (Pitfall 4: captured in init, not body)
@Query private var completions: [RoutineCompletion]

// NOTE: EditNoteView already receives `note: Note` in the existing signature.
// Add to init: self._completions = Query(filter: #Predicate { $0.noteID == note.id })
```

**Modified sortedBlocks / blocksForDisplay** (existing `sortedBlocks` at lines 300–306):
```swift
// NEW: switch between edit-mode raw order and display open-above-checked order
private var blocksForDisplay: [NoteBlock] {
    editMode.isEditing
        ? (note.blocks ?? []).sorted { $0.order < $1.order }  // raw order for reorder drag
        : sortedBlocks                                          // open-above-checked (existing)
}
```

**Modified blockList with onMove** (existing `blockList` at lines 173–185):
```swift
@ViewBuilder
private var blockList: some View {
    let blocks = blocksForDisplay   // was: sortedBlocks
    if blocks.isEmpty {
        Text("Tap below to add a note or checklist item.")  // unchanged
            .font(.body).foregroundStyle(.secondary)
    } else if editMode.isEditing {
        // List required for .onMove — wrapped only in edit mode (Open Question #2)
        List {
            ForEach(blocks) { block in blockRow(block) }
                .onMove { source, destination in
                    reorderBlocks(from: source, to: destination)
                }
        }
        .environment(\.editMode, $editMode)
        .frame(height: CGFloat(blocks.count) * 52)  // approx row height to size nested List
    } else {
        ForEach(blocks) { block in blockRow(block) }  // existing path unchanged
    }
}
```

**New reorderBlocks method** (append after `toggleCheck` at line 382):
```swift
private func reorderBlocks(from source: IndexSet, to destination: Int) {
    var ordered = (note.blocks ?? []).sorted { $0.order < $1.order }
    ordered.move(fromOffsets: source, toOffset: destination)
    for (idx, block) in ordered.enumerated() {
        block.order = idx   // re-index: 0, 1, 2, ...
    }
    markDirty()   // triggers debounced save — same as toggleCheck (line 382)
}
```

**Modified toggleCheck** (existing lines 375–382 — add completion-recording branch):
```swift
private func toggleCheck(_ block: NoteBlock) {
    block.isChecked.toggle()
    if block.isChecked && block.reminderEnabled {
        cancelBlockReminder(block)
    }
    // NEW: if this note is a routine, check if all boxes are now checked → record completion
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

**New recordTodayCompletion** (fetch-before-insert pattern — mirrors NetWorthSnapshotService):
```swift
private func recordTodayCompletion() {
    // IST day key — mirrors RoutineResetService.swift lines 26-29
    var istCal = Calendar(identifier: .gregorian)
    istCal.timeZone = TimeZone(identifier: "Asia/Kolkata")!
    let dayKey = istCal.startOfDay(for: Date())
    let noteID = note.id
    // Fetch-before-insert for idempotency (no .unique allowed — CloudKit rule 2)
    let descriptor = FetchDescriptor<RoutineCompletion>(
        predicate: #Predicate { $0.noteID == noteID && $0.dayKey == dayKey }
    )
    if let existing = try? context.fetch(descriptor).first {
        existing.completedAt = Date()
    } else {
        let completion = RoutineCompletion(noteID: noteID, dayKey: dayKey)
        context.insert(completion)
    }
    // Save is handled by markDirty() → debounced save (same path as toggleCheck)
}
```

**New routineSection ViewBuilder** (append to body VStack after `addBlockButtons`):
```swift
@ViewBuilder
private var routineSection: some View {
    GroupBox("Routine") {
        VStack(alignment: .leading, spacing: 12) {
            Toggle("Daily Routine", isOn: $note.isDailyRoutine)
                .onChange(of: note.isDailyRoutine) { _, isOn in
                    if !isOn { note.routineDailyReminderTime = nil }
                    RoutineNotificationService().cancel(noteID: note.id)  // always cancel first
                    if isOn, let time = note.routineDailyReminderTime {
                        Task { await RoutineNotificationService().schedule(noteID: note.id, title: note.title, time: time) }
                    }
                    markDirty()
                }

            if note.isDailyRoutine {
                // D-04: Daily reminder toggle + time picker
                Toggle("Daily Reminder", isOn: Binding(
                    get: { note.routineDailyReminderTime != nil },
                    set: { enabled in
                        note.routineDailyReminderTime = enabled
                            ? Calendar.current.date(bySettingHour: 7, minute: 0, second: 0, of: Date())
                            : nil
                        if !enabled { RoutineNotificationService().cancel(noteID: note.id) }
                        markDirty()
                    }
                ))
                if let _ = note.routineDailyReminderTime {
                    DatePicker(
                        "Time",
                        selection: Binding(
                            get: { note.routineDailyReminderTime! },
                            set: { newTime in
                                note.routineDailyReminderTime = newTime
                                Task { await RoutineNotificationService().schedule(noteID: note.id, title: note.title, time: newTime) }
                                markDirty()
                            }
                        ),
                        displayedComponents: .hourAndMinute
                    )
                }

                // D-06: "Done today" for text-only routines (no checkbox blocks)
                if (note.blocks ?? []).filter({ $0.kindRaw == "checkbox" }).isEmpty {
                    Button("Done today") {
                        recordTodayCompletion()
                        markDirty()
                    }
                    .buttonStyle(.bordered)
                    .frame(minHeight: 44)
                }

                // D-09: Compact streak + NavigationLink to RoutineDetailView
                HStack {
                    Text("🔥 \(currentStreak) day streak")
                        .font(.subheadline)
                    Spacer()
                    NavigationLink("Routine History") {
                        RoutineDetailView(note: note)
                    }
                    .font(.subheadline)
                }
            }
        }
    }
    .padding(.bottom, 16)
}

private var currentStreak: Int {
    var istCal = Calendar(identifier: .gregorian)
    istCal.timeZone = TimeZone(identifier: "Asia/Kolkata")!
    return StreakCalculator.compute(
        for: note.id,
        completions: completions,
        today: Date(),
        calendar: istCal
    ).currentStreak
}
```

**Toolbar reorder button** (append to existing `.toolbar` block, lines 100–127):
```swift
ToolbarItem(placement: .secondaryAction) {
    Button {
        withAnimation { editMode = editMode.isEditing ? .inactive : .active }
    } label: {
        Image(systemName: "arrow.up.arrow.down")
    }
    .accessibilityLabel("Reorder items")
}
```

**Modified deleteNote** (existing lines 404–414 — add notification cancel before delete):
```swift
private func deleteNote() {
    debouncer.cancel()
    noteRemoved = true
    RoutineNotificationService().cancel(noteID: note.id)  // NEW: cancel routine notification
    context.delete(note)
    // ... rest unchanged
}
```

---

### `MyHomeApp/Features/Notes/CalendarView.swift` — DayAgendaView (component, CRUD — modify)

**Analog:** itself. `DayAgendaView` struct starts at line 282.

**New routineNotes computed property** (insert after `remindersOnDay`, after line 326):
```swift
/// All routine notes — surfaced on every day (D-01/D-03).
/// STAB-01: guard against tombstoned @Model objects (same pattern as remindersOnDay at line 304).
private var routineNotes: [Note] {
    notes.filter { note in
        guard note.modelContext != nil else { return false }  // STAB-01: skip tombstoned notes
        return note.isDailyRoutine
    }
    .sorted { ($0.title) < ($1.title) }  // alphabetical within section
}
```

**@State addition for routine note editing** (after existing `@Environment` lines):
```swift
@State private var editingRoutineNote: Note? = nil
```

**Modified body empty-state gate** (existing line 331 — `if remindersOnDay.isEmpty`):
```swift
if remindersOnDay.isEmpty && routineNotes.isEmpty {   // was: remindersOnDay.isEmpty
    ContentUnavailableView(
        "Nothing Scheduled",           // was: "No Reminders"
        systemImage: "calendar",
        description: Text("No routines or reminders for this day.")  // was different copy
    )
} else {
    List {
        // Section 1: Daily Routines (NEW — D-01, above existing progress/reminders)
        if !routineNotes.isEmpty {
            Section("Daily Routines") {
                ForEach(routineNotes) { note in
                    RoutineAgendaRow(note: note, onTap: { editingRoutineNote = note })
                }
            }
        }

        // Progress header (existing — unchanged)
        if progress.total > 0 { /* ... existing ... */ }

        // Reminders section (existing — unchanged)
        if !remindersOnDay.isEmpty {
            Section {
                ForEach(remindersOnDay) { item in /* ... existing ... */ }
            }
        }
    }
    .listStyle(.insetGrouped)   // unchanged
}
```

**Sheet for routine note editing** (append alongside existing `.toolbar`):
```swift
.sheet(item: $editingRoutineNote) { note in
    EditNoteView(note: note)
}
```

**RoutineAgendaRow** (new sub-view within CalendarView.swift file, mirrors `AgendaReminderItem` row at lines 358–386):
```swift
struct RoutineAgendaRow: View {
    var note: Note
    var onTap: () -> Void

    @Environment(\.modelContext) private var context

    private var isCompleteToday: Bool {
        // For checklist routines: all checkbox blocks are checked
        let checkboxBlocks = (note.blocks ?? []).filter { $0.kindRaw == "checkbox" }
        if !checkboxBlocks.isEmpty { return checkboxBlocks.allSatisfy(\.isChecked) }
        // For text-only routines: checked via RoutineCompletion record — handled in parent
        return false
    }

    var body: some View {
        HStack(spacing: 12) {
            Button {
                toggleAllBlocks()
            } label: {
                Image(systemName: isCompleteToday ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isCompleteToday ? .secondary : Color.accentColor)
                    .font(.body)
                    .frame(minWidth: 44, minHeight: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isCompleteToday ? "Routine complete" : "Mark routine complete")

            VStack(alignment: .leading, spacing: 2) {
                Text(note.title)
                    .font(.body)
                    .strikethrough(isCompleteToday)
                    .foregroundStyle(isCompleteToday ? .secondary : .primary)

                // Status subtitle
                if let time = note.routineDailyReminderTime {
                    Text("Daily at \(time.formatted(.dateTime.hour().minute()))")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    Text("Daily routine")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { onTap() }
        }
        .padding(.vertical, 2)  // matches existing remindersOnDay rows at line 383
    }

    private func toggleAllBlocks() {
        let checkboxBlocks = (note.blocks ?? []).filter { $0.kindRaw == "checkbox" }
        guard !checkboxBlocks.isEmpty else { return }
        let newChecked = !checkboxBlocks.allSatisfy(\.isChecked)
        for block in checkboxBlocks { block.isChecked = newChecked }
        // Write completion record if completing
        if newChecked && note.isDailyRoutine {
            // mirrors recordTodayCompletion() from EditNoteView
            var istCal = Calendar(identifier: .gregorian)
            istCal.timeZone = TimeZone(identifier: "Asia/Kolkata")!
            let dayKey = istCal.startOfDay(for: Date())
            let noteID = note.id
            let descriptor = FetchDescriptor<RoutineCompletion>(
                predicate: #Predicate { $0.noteID == noteID && $0.dayKey == dayKey }
            )
            if let existing = try? context.fetch(descriptor).first {
                existing.completedAt = Date()
            } else {
                context.insert(RoutineCompletion(noteID: noteID, dayKey: dayKey))
            }
        }
        try? context.save()   // mirrors DayAgendaView.toggleCompletion line 451
    }
}
```

---

## Test File Patterns

### `MyHomeTests/SchemaV9MigrationTests.swift` (test, batch)

**Analog:** `MyHomeTests/SchemaV8MigrationTests.swift` lines 1–248

**File header and MigrationTestsPlanV8** (mirror of `MigrationTestsPlanV7` at lines 256–301):
```swift
import Testing
import SwiftData
import Foundation
@testable import MyHome

@MainActor
struct SchemaV9MigrationTests { ... }

// MigrationTestsPlanV8 — trimmed plan stopping at SchemaV8 (mirrors MigrationTestsPlanV7 pattern)
enum MigrationTestsPlanV8: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [SchemaV1.self, ..., SchemaV8.self]  // stops at V8
    }
    static var stages: [MigrationStage] {
        [v1ToV2, ..., v7ToV8]  // does NOT include v8ToV9
    }
    // ... all stages with nil closures (or minimal didMigrate for v5ToV6)
}
```

**Test structure** (mirror of `v7StoreAssetNpsSchemeCodeIsNilAfterMigration` at lines 24–98):
```swift
@Test("V8→V9: existing Note rows survive migration with routineDailyReminderTime == nil")
func v8StoreNoteSurvivesWithNilReminderTime() throws {
    // 1. Build genuine V8 store using MigrationTestsPlanV8
    // 2. Copy seed → migrate URL
    // 3. Open under V9 (Schema(versionedSchema: SchemaV9.self) + AppMigrationPlan)
    // 4. Assert: notes.count == 1, note.routineDailyReminderTime == nil
}

@Test("V8→V9: RoutineCompletion entity queryable after migration")
func routineCompletionQueryableAfterMigration() throws {
    // mirrors newEntitiesQueryableAfterMigration() at lines 102-152
    // Assert: context.fetch(FetchDescriptor<RoutineCompletion>()) returns [] (not crash)
}
```

---

### `MyHomeTests/StreakCalculatorTests.swift` (test, transform)

**Analog:** `MyHomeTests/RoutineResetServiceTests.swift` lines 1–181

**makeContainer helper** (lines 18–21 — extend to include RoutineCompletion):
```swift
private func makeContainer() throws -> ModelContainer {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    return try ModelContainer(for: Note.self, NoteBlock.self, RoutineCompletion.self, configurations: config)
}

private func istStartOfToday() -> Date {
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = TimeZone(identifier: "Asia/Kolkata")!
    return cal.startOfDay(for: Date())
}

private var istCalendar: Calendar {
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = TimeZone(identifier: "Asia/Kolkata")!
    return cal
}
```

**Test shape** (mirrors `resetsRoutineNoteCrossingMidnight` at lines 40–77):
```swift
@Test("streak is 0 when no completions exist")
func streakIsZeroWithNoCompletions() { ... }

@Test("D-07: incomplete today does NOT break streak — shows yesterday's run")
func incompleteToday_doesNotBreakStreak() { ... }

@Test("D-07: streak breaks on fully-missed past day")
func streakBreaksOnMissedDay() { ... }

@Test("D-07: completing today extends streak by 1")
func completingTodayExtendsStreak() { ... }

@Test("D-08: idempotent — second tap on same day upserts, not inserts")
func idempotentCompletion() { ... }
```

---

### `MyHomeTests/RoutineNotificationServiceTests.swift` (test, request-response)

**Analog:** `MyHomeTests/RoutineResetServiceTests.swift` + SpyCenter pattern (`MyHomeTests/Support/SpyCenter.swift`)

**Setup pattern:**
```swift
import Testing
@testable import MyHome
import UserNotifications

@MainActor
struct RoutineNotificationServiceTests {

    private func makeSpy() -> SpyCenter { SpyCenter() }

    @Test("D-05: re-scheduling cancels prior request before adding new one")
    func rescheduleIsAtomicCancelThenAdd() async { ... }

    @Test("D-05: exactly one pending request per routine note after multiple schedules")
    func exactlyOnePendingRequest() async { ... }

    @Test("cancel removes pending request")
    func cancelRemovesPendingRequest() async { ... }
}
```

---

### `MyHomeTests/NoteReorderTests.swift` (test, CRUD)

**Analog:** `MyHomeTests/RoutineResetServiceTests.swift` lines 18–21 (makeContainer + seed blocks)

**Core test shape:**
```swift
@Test("onMove re-indexes order and persists across save")
func reorderPersists() throws {
    let container = try makeContainer()
    let context = container.mainContext

    let note = Note(title: "Checklist")
    note.isDailyRoutine = false
    context.insert(note)

    let b0 = NoteBlock(kindRaw: "checkbox", text: "A", order: 0); b0.note = note; context.insert(b0)
    let b1 = NoteBlock(kindRaw: "checkbox", text: "B", order: 1); b1.note = note; context.insert(b1)
    let b2 = NoteBlock(kindRaw: "checkbox", text: "C", order: 2); b2.note = note; context.insert(b2)
    try context.save()

    // Simulate onMove: move index 2 to index 0
    var ordered = [b0, b1, b2]
    ordered.move(fromOffsets: IndexSet(integer: 2), toOffset: 0)
    for (idx, b) in ordered.enumerated() { b.order = idx }
    try context.save()

    let refetched = try context.fetch(FetchDescriptor<NoteBlock>(sortBy: [SortDescriptor(\.order)]))
    #expect(refetched.map(\.text) == ["C", "A", "B"])
}
```

---

## Shared Patterns

### IST Day Key
**Source:** `MyHomeApp/Features/Notes/RoutineResetService.swift` lines 26–29
**Apply to:** `RoutineCompletion` insertion (EditNoteView, DayAgendaView), `StreakCalculator`, `StreakCalculatorTests`
```swift
var istCal = Calendar(identifier: .gregorian)
istCal.timeZone = TimeZone(identifier: "Asia/Kolkata")!
let startOfTodayIST = istCal.startOfDay(for: Date())
```

### STAB-01 Tombstone Guard
**Source:** `MyHomeApp/Features/Notes/CalendarView.swift` line 304
**Apply to:** every loop/filter that accesses Note fields in DayAgendaView (`routineNotes`, `RoutineAgendaRow`)
```swift
guard note.modelContext != nil else { continue }  // STAB-01: skip tombstoned notes
```

### Fetch-Before-Insert Idempotency
**Source:** `MyHomeApp/Persistence/Schema/MigrationPlan.swift` lines 76–79 + RESEARCH.md RQ-3
**Apply to:** `recordTodayCompletion()` in EditNoteView and DayAgendaView completion paths
```swift
let descriptor = FetchDescriptor<RoutineCompletion>(
    predicate: #Predicate { $0.noteID == noteID && $0.dayKey == dayKey }
)
if let existing = try? context.fetch(descriptor).first {
    existing.completedAt = Date()
} else {
    context.insert(RoutineCompletion(noteID: noteID, dayKey: dayKey))
}
```

### markDirty / Debounced Save
**Source:** `MyHomeApp/Features/Notes/EditNoteView.swift` lines 310–342
**Apply to:** all new mutation paths in EditNoteView (toggleCheck extension, reorderBlocks, routineSection toggles, "Done today")
```swift
private func markDirty() {
    isDirty = true
    note.modifiedAt = Date()
    debouncer.schedule { [self] in saveIfDirty() }
}
```

### Explicit try? context.save()
**Source:** `MyHomeApp/Features/Notes/CalendarView.swift` line 451
**Apply to:** `RoutineAgendaRow.toggleAllBlocks()` and any completion writes in DayAgendaView
```swift
try? context.save()
```

### UNCalendarNotificationTrigger (time-only, repeating)
**Source:** `MyHomeApp/Support/SIPAccrualService.swift` lines 493–505
**Apply to:** `RoutineNotificationService.schedule()`
```swift
var comps = DateComponents()
comps.hour = hour; comps.minute = minute
let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: true)
let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
try? await center.add(request)
```

### CardStyle Header Card
**Source:** `MyHomeApp/Features/Assets/AssetDetailView.swift` lines 67–74
**Apply to:** `RoutineDetailView.headerCard`
```swift
Section {
    headerCard
        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
}
```

### saveError Alert
**Source:** `MyHomeApp/Features/Notes/EditNoteView.swift` line 140
**Apply to:** Notification permission denied alert in EditNoteView (same `.alert` style)
```swift
.alert("Couldn't save note. Please try again.", isPresented: $saveError) {
    Button("OK", role: .cancel) {}
}
```

### @Query Predicate Captured via init (Pitfall 4)
**Source:** RESEARCH.md RQ-7, Pitfall 4 — no codebase analog exists yet (first instance)
**Apply to:** `RoutineDetailView.init(note:)` and optionally `EditNoteView.init(note:)`
```swift
init(note: Note) {
    self.note = note
    let noteID = note.id
    self._completions = Query(
        filter: #Predicate<RoutineCompletion> { $0.noteID == noteID },
        sort: [SortDescriptor(\.dayKey, order: .reverse)]
    )
}
```

---

## No Analog Found

All files have analogs in the existing codebase. No entries in this section.

---

## Xcode pbxproj — New Files Requiring Manual Registration

Per project memory (Xcode explicit file refs, `xcodeproj-explicit-file-refs.md`):

Every new `.swift` file requires **4 manual `project.pbxproj` edits** (PBXBuildFile entry, PBXFileReference entry, PBXGroup membership, PBXSourcesBuildPhase membership). The planner MUST include these as explicit sub-steps in each task that creates a new file.

**New files requiring pbxproj registration:**

| File | Target | Group |
|------|--------|-------|
| `MyHomeApp/Persistence/Schema/SchemaV9.swift` | MyHome | Persistence/Schema |
| `MyHomeApp/Persistence/Models/RoutineCompletion.swift` | MyHome | Persistence/Models |
| `MyHomeApp/Features/Notes/RoutineNotificationService.swift` | MyHome | Features/Notes |
| `MyHomeApp/Features/Notes/RoutineDetailView.swift` | MyHome | Features/Notes |
| `MyHomeApp/Features/Notes/StreakCalculator.swift` | MyHome | Features/Notes |
| `MyHomeTests/SchemaV9MigrationTests.swift` | MyHomeTests | MyHomeTests |
| `MyHomeTests/StreakCalculatorTests.swift` | MyHomeTests | MyHomeTests |
| `MyHomeTests/RoutineNotificationServiceTests.swift` | MyHomeTests | MyHomeTests |
| `MyHomeTests/NoteReorderTests.swift` | MyHomeTests | MyHomeTests |

---

## Metadata

**Analog search scope:** `MyHomeApp/Persistence/Schema/`, `MyHomeApp/Persistence/Models/`, `MyHomeApp/Features/Notes/`, `MyHomeApp/Features/Assets/`, `MyHomeApp/Support/`, `MyHomeTests/`
**Files scanned:** 18
**Pattern extraction date:** 2026-06-13
