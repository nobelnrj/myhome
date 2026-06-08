# Phase 8: Stabilization - Pattern Map

**Mapped:** 2026-06-08
**Files analyzed:** 9 (6 modify/create targets + 3 test files)
**Analogs found:** 9 / 9

---

## File Classification

| New/Modified File | Role | Data Flow | Closest Analog | Match Quality |
|---|---|---|---|---|
| `MyHomeApp/Features/Notes/CalendarView.swift` | view | event-driven (SwiftData @Query live-binding) | `MyHomeApp/Features/Notes/EditNoteView.swift` (tombstone guard pattern, line 332) | role-match (guard idiom) |
| `MyHomeApp/Features/Gmail/GmailSyncController.swift` | service | request-response + batch | `MyHomeApp/Features/Gmail/GmailSyncController.swift` (existing — self-refactor) | exact (same file) |
| `MyHomeApp/Features/Notes/RoutineResetService.swift` | service | event-driven (scenePhase) | `MyHomeApp/Security/LockController.swift` | exact (`@MainActor @Observable final class` + scenePhase hook) |
| `MyHomeApp/RootView.swift` | view / wiring | event-driven (scenePhase) | `MyHomeApp/RootView.swift` (existing — self-modification) | exact (same file) |
| `MyHomeApp/Features/Budgets/ManageCategoriesView.swift` | view + action | CRUD | self (already correct); regression only | exact |
| `MyHomeTests/CalendarAggregationTests.swift` | test | unit | `MyHomeTests/CalendarAggregationTests.swift` (existing suite) | exact |
| `MyHomeTests/GmailSyncControllerTests.swift` | test | unit (async) | `MyHomeTests/MultiAccountGmailTests.swift` (injected-context pattern, line 369) | exact |
| `MyHomeTests/CategoryCRUDTests.swift` | test | unit | `MyHomeTests/CategoryCRUDTests.swift` (existing suite) | exact |

---

## Pattern Assignments

### `MyHomeApp/Features/Notes/CalendarView.swift` — STAB-01 (view, event-driven)

**Analog:** `MyHomeApp/Features/Notes/EditNoteView.swift` line 332

**Tombstone guard pattern** (EditNoteView.swift lines 329–342):
```swift
private func performSave() {
    // WR-09: never save once the note has been deleted/discarded (a debounced save may
    // resolve after delete on the same run loop).
    guard !noteRemoved, note.modelContext != nil else { return }
    // T-03-12: no note body content in error strings
    do {
        try context.save()
        isDirty = false
    } catch {
        assertionFailure("Failed to save note: \(error)")
        saveError = true
    }
}
```

**Apply to `remindersOnDay`** — the crash surface (CalendarView.swift lines 295–319). Currently:
```swift
// CURRENT (CalendarView.swift lines 295–319) — NO tombstone guard:
private var remindersOnDay: [AgendaReminderItem] {
    var items: [AgendaReminderItem] = []
    let cal = Calendar.current
    for note in notes {
        if note.reminderEnabled,
           let date = note.reminderDate,
           cal.isDate(date, inSameDayAs: day) {
            items.append(AgendaReminderItem(
                target: ReminderTarget.note(note),
                date: date
            ))
        }
        for block in note.blocks ?? [] {
            if block.reminderEnabled,
               let date = block.reminderDate,
               cal.isDate(date, inSameDayAs: day) {
                items.append(AgendaReminderItem(
                    target: ReminderTarget.block(block),
                    date: date
                ))
            }
        }
    }
    return items.sorted { $0.date < $1.date }
}
```

**Copy pattern:** Insert `guard note.modelContext != nil else { continue }` after `for note in notes {` and `guard block.modelContext != nil else { continue }` after `for block in note.blocks ?? [] {`. This is the `note.modelContext != nil` idiom from EditNoteView.swift:332.

**Empty-state behavior** (CalendarView.swift lines 322–329) — already correct, no change needed:
```swift
if remindersOnDay.isEmpty {
    ContentUnavailableView(
        "No Reminders",
        systemImage: "calendar",
        description: Text("No reminders scheduled for this day.")
    )
}
```
When the last tombstoned item is filtered out, `remindersOnDay.isEmpty` becomes `true` and the existing `ContentUnavailableView` activates automatically (D-01 satisfied without new code).

**`AgendaReminderItem` computed properties** (CalendarView.swift lines 246–270) — safe once construction is guarded in `remindersOnDay`. No change needed. `AgendaReminderItem` wraps live `ReminderTarget` references; since `remindersOnDay` is the only construction site, any item in the `ForEach` is guaranteed non-tombstoned.

**`CalendarAggregator.events(from:)`** — same tombstone guard pattern must be applied. The same `note.modelContext != nil` / `block.modelContext != nil` guards are needed there.

---

### `MyHomeApp/Features/Gmail/GmailSyncController.swift` — STAB-02 (service, batch)

**Analog:** Self-refactor. Both `syncAccount` (lines 421–545) and `legacySingleAccountSync` (lines 547–686) are modified.

**Imports pattern** (GmailSyncController.swift lines 1–4) — unchanged:
```swift
import Foundation
import SwiftUI
import SwiftData
import AuthenticationServices
```

**Current offending `syncAccount` pattern** (lines 479–534) — two bugs:
```swift
// Bug 1: categories fetched ONCE before the loop — reference may stale after await
var categoriesByName: [String: Category] = [:]
if let ctx = modelContext {
    for cat in (try? ctx.fetch(FetchDescriptor<Category>())) ?? [] {
        if let name = cat.name { categoriesByName[name] = cat }   // captures @Model reference
    }
}

// Bug 2: ctx.save() inside per-message loop (N saves instead of 1)
if let ctx = modelContext {
    ctx.insert(expense)
    try ctx.save()   // line 533 — INSIDE loop
}
```

**Current offending `legacySingleAccountSync` pattern** (lines 616–669):
```swift
// Same bug 1: pre-loop category capture
var categoriesByName: [String: Category] = [:]
if let ctx = modelContext {
    for cat in (try? ctx.fetch(FetchDescriptor<Category>())) ?? [] {
        if let name = cat.name { categoriesByName[name] = cat }
    }
}

// Same bug 2: ctx.save() inside loop (line 668)
if let ctx = modelContext {
    ctx.insert(expense)
    try ctx.save()   // line 668 — INSIDE loop
}
```

**Fixed pattern — PersistentIdentifier-keyed map (to replace both `categoriesByName` blocks):**
```swift
// Capture PersistentIdentifier values before the loop — value type, Sendable, safe across await
var categoryIDsByName: [String: PersistentIdentifier] = [:]
if let ctx = modelContext {
    for cat in (try? ctx.fetch(FetchDescriptor<Category>())) ?? [] {
        if let name = cat.name { categoryIDsByName[name] = cat.persistentModelID }
    }
}
```

**Fixed pattern — post-await category re-resolve (to replace `categoriesByName[hint]` lookup):**
```swift
// After each await getRawMessage — re-resolve category from context by PersistentIdentifier
if let hint = parsed.categoryHint,
   let catID = categoryIDsByName[hint],
   let ctx = modelContext,
   let cat = ctx.model(for: catID) as? Category {
    expense.categories = [cat]
}
// D-03: if re-fetch fails (cat deleted mid-sync), skip category assignment; continue processing
```

**Fixed pattern — single batched save (replace in-loop save in both methods):**
```swift
// Remove try ctx.save() from INSIDE the per-message loop.
// Insert only, no save inside the loop:
if let ctx = modelContext {
    ctx.insert(expense)
    // no save here
}

// After the loop ends, single batched save:
if let ctx = modelContext {
    try ctx.save()
}
```

**Per-message skip on parse failure** — existing `guard let parsed = parser.parse(rawEmail:)` pattern (lines 499, 634) already implements D-03 for parse failures. The new guard for category re-fetch failure is the `if let cat = ctx.model(for: catID) as? Category` optional binding — failure path skips category assignment and `continue`s to the next iteration.

---

### `MyHomeApp/Features/Notes/RoutineResetService.swift` — STAB-04 (new file, service)

**Analog:** `MyHomeApp/Security/LockController.swift` — exact clone of class declaration pattern.

**Class declaration pattern** (LockController.swift lines 32–34):
```swift
@MainActor
@Observable
final class LockController {
```

**Scene-phase hook pattern** (LockController.swift lines 87–108):
```swift
/// Call from `RootView.onChange(of: scenePhase)` to drive blur and grace-period re-lock.
func scenePhaseChanged(_ phase: ScenePhase) {
    switch phase {
    case .active:
        isBlurred = false
        // ... action on active
    case .inactive, .background:
        isBlurred = true
        // ...
    @unknown default:
        break
    }
}
```

**New file imports** — no SwiftUI or SwiftData needed for Phase 8 scaffold (synchronous, no model writes):
```swift
import Foundation
```

**Full scaffold to create at `MyHomeApp/Features/Notes/RoutineResetService.swift`:**
```swift
import Foundation

// MARK: - RoutineResetService

/// Routine-reset coordinator: resets routine NoteBlock completion state on each new IST day.
///
/// Phase 8 scaffold: no model writes this phase (NoteBlock.lastCheckedDate does not exist
/// until SchemaV6 / Phase 9). The call path is fully wired; Phase 9 fills the body.
///
/// Owned by RootView via `@State private var routineResetService = RoutineResetService()`
/// and called synchronously from `.onChange(of: scenePhase)` on `.active`.
@MainActor
@Observable
final class RoutineResetService {

    func resetIfNeeded() {
        // STAB-04: logged scaffold only. Phase 9 adds NoteBlock.lastCheckedDate comparison
        // once SchemaV6 lands.
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Kolkata")!   // IST — household timezone
        let todayIST = cal.startOfDay(for: Date())
        // Phase 9 implementation:
        //   fetch all NoteBlocks where note.isRoutine == true
        //   for each block where lastCheckedDate < todayIST: reset isChecked = false, update lastCheckedDate
        // WARNING: sortOrder defaults to 0 — any Category creation without explicit sortOrder will sort to top
        print("[RoutineResetService] resetIfNeeded: startOfToday IST = \(todayIST). No-op (Phase 8 scaffold).")
    }
}
```

---

### `MyHomeApp/RootView.swift` — STAB-04 wiring (view, event-driven)

**Analog:** Self-modification. Existing `scenePhase` handler (RootView.swift lines 106–114).

**Existing scenePhase observer** (RootView.swift lines 106–114):
```swift
.onChange(of: scenePhase) { _, newPhase in
    lockController.scenePhaseChanged(newPhase)
    gmailSyncController.scenePhaseChanged(newPhase)
    // Auto-trigger auth on foreground when locked (banking-app feel — D5-02, D5-01)
    // Pitfall: never call async directly in onChange; always wrap in Task
    if newPhase == .active && lockController.isLocked && lockController.lockEnabled {
        Task { await lockController.authenticate() }
    }
}
```

**Existing @State property declaration** (RootView.swift line 40):
```swift
/// Face ID gate state — @Observable owned via @State, never @StateObject (PITFALLS.md Pitfall 10)
@State private var lockController = LockController()
```

**New @State property to add** (slot in alongside line 40, after `lockController`):
```swift
@State private var routineResetService = RoutineResetService()
```

**onChange block — add one line** after `gmailSyncController.scenePhaseChanged(newPhase)`:
```swift
if newPhase == .active {
    routineResetService.resetIfNeeded()   // synchronous — no Task needed (D-07)
}
```

**Swift 6 / concurrency note:** `resetIfNeeded()` is `@MainActor`-isolated (class annotation). `onChange(of:)` runs on the main actor. Synchronous call is correct — no `Task` wrapper needed, matching the existing `lockController.scenePhaseChanged(newPhase)` call style.

---

### `MyHomeApp/Features/Budgets/ManageCategoriesView.swift` — STAB-03 (view + action, CRUD)

**Analog:** Self — the `addCategory` function is already correct. No code change required.

**Canonical sort-insertion pattern** (ManageCategoriesView.swift lines 175–203):
```swift
private func addCategory(name: String) {
    let trimmed = name.trimmingCharacters(in: .whitespaces)
    guard !trimmed.isEmpty else {
        nameError = "Category name cannot be empty."
        return
    }
    let lower = trimmed.lowercased()
    do {
        let all = try context.fetch(FetchDescriptor<Category>())
        let duplicate = all.first { ($0.name ?? "").lowercased() == lower }
        guard duplicate == nil else {
            nameError = "A category with that name already exists."
            return
        }
        // Append after the highest existing sortOrder so deletions don't cause collisions.
        let nextSortOrder = (all.map(\.sortOrder).max() ?? 999) + 1
        let category = Category(name: trimmed, symbolName: "tag", sortOrder: nextSortOrder)
        context.insert(category)
        try context.save()  // CR-01: explicit save
        nameError = nil
        newCategoryName = ""
        showAddField = false
    } catch {
        assertionFailure("Failed to save new category: \(error)")
    }
}
```

**STAB-03 action:** Add a `// WARNING: sortOrder defaults to 0` comment on `Category.init` (wherever that is defined) as a latent-footgun guard. No production path is broken. Fix is a regression test only.

---

## Test Pattern Assignments

### `MyHomeTests/CalendarAggregationTests.swift` — STAB-01 regression test

**Analog:** Existing `CalendarAggregationTests` suite — add a new `@Test` case.

**Test harness pattern** (CalendarAggregationTests.swift lines 17–27):
```swift
@MainActor
struct CalendarAggregationTests {

    @Test("perDayCountsAndProgress: ...")
    func perDayCountsAndProgress() throws {
        let container = try ModelContainer(for: Note.self, NoteBlock.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let ctx = container.mainContext

        // build fixtures, insert, ctx.save()
        // call CalendarAggregator pure function directly
        // #expect(...)
    }
}
```

**New test to add** — delete-and-check pattern:
```swift
@Test("tombstonedNoteIsFilteredFromRemindersOnDay: deleted note does not appear in remindersOnDay — STAB-01")
func tombstonedNoteIsFilteredFromRemindersOnDay() throws {
    let container = try ModelContainer(for: Note.self, NoteBlock.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    let ctx = container.mainContext

    var cal = Calendar.current
    let today = cal.startOfDay(for: Date())
    let nineAM = cal.date(byAdding: .hour, value: 9, to: today)!

    let note = Note(title: "To delete")
    note.reminderEnabled = true
    note.reminderDate = nineAM
    ctx.insert(note)
    try ctx.save()

    // Delete the note — simulates STAB-01 scenario
    ctx.delete(note)
    try ctx.save()

    // After delete, CalendarAggregator must skip the tombstoned note
    let allNotes = try ctx.fetch(FetchDescriptor<Note>())
    // allNotes should be empty after delete+save; perDayCounts should return [:]
    let counts = CalendarAggregator.perDayCounts(for: allNotes)
    #expect(counts.isEmpty, "Deleted note must not appear in per-day counts (STAB-01)")
}
```

**Tombstoned-block variant** — same pattern but delete a `NoteBlock` while keeping the parent `Note`, assert it doesn't appear in `remindersOnDay`.

---

### `MyHomeTests/GmailSyncControllerTests.swift` — STAB-02 regression test

**Analog:** `MyHomeTests/MultiAccountGmailTests.swift` — `controller.setContext(container.mainContext)` injected-context pattern (line 369).

**Injected-context test pattern** (MultiAccountGmailTests.swift lines 365–378):
```swift
let controller = GmailSyncController(
    auth: spy, keychain: keychain, fetch: fetch,
    defaults: defaults, accountStore: store
)
controller.setContext(container.mainContext)
await controller.sync()

let expenses = try container.mainContext.fetch(FetchDescriptor<Expense>())
#expect(expenses.count == 2, "...")
```

**In-memory container helper** (MultiAccountGmailTests.swift lines 43–47):
```swift
private func makeContainer() throws -> ModelContainer {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    return try ModelContainer(for: Expense.self, Category.self, Note.self, NoteBlock.self,
                              configurations: config)
}
```

**Isolated UserDefaults helper** (GmailSyncControllerTests.swift lines 34–39):
```swift
private func makeDefaults() -> UserDefaults {
    let name = "test.gsc.\(UUID().uuidString)"
    let d = UserDefaults(suiteName: name)!
    d.removePersistentDomain(forName: name)
    return d
}
```

**SpyGmailFetch configuration** (GmailSyncControllerTests.swift lines 49–53):
```swift
let fetch = SpyGmailFetch()
fetch.messageIDsResult = []
// fetch.profileResult = GmailProfile(emailAddress: testEmail)
// fetch.rawMessagesByID = ["msg-001": rawEmailString]
```

**New test to add** — STAB-02: category re-fetch across await suspension + single batched save:
```swift
@Test("syncWithCategoryResolvesByPersistentID: category assigned via PersistentIdentifier after await — STAB-02")
func syncWithCategoryResolvesByPersistentID() async throws {
    let defaults = makeDefaults()
    let spy = SpyGmailAuth()
    let keychain = SpyKeychainStore()
    let fetch = SpyGmailFetch()

    let container = try makeContainer()
    let ctx = container.mainContext

    // Pre-seed a Category so the sync path has something to resolve
    let cat = Category(name: "Food", symbolName: "fork.knife", sortOrder: 0)
    ctx.insert(cat)
    try ctx.save()

    // Configure SpyGmailFetch to return one parseable message with categoryHint = "Food"
    fetch.profileResult = GmailProfile(emailAddress: testEmail)
    fetch.messageIDsResult = ["msg-stab02"]
    fetch.rawMessagesByID = ["msg-stab02": /* ICICI-format raw email string */]

    let controller = GmailSyncController(auth: spy, keychain: keychain, fetch: fetch,
                                          defaults: defaults)
    controller.setContext(ctx)
    await controller.sync()

    let expenses = try ctx.fetch(FetchDescriptor<Expense>())
    #expect(expenses.count == 1, "One expense must be ingested — STAB-02")
    #expect(expenses.first?.categories.isEmpty == false,
            "Category must be resolved by PersistentIdentifier and assigned — STAB-02")
}
```

---

### `MyHomeTests/CategoryCRUDTests.swift` — STAB-03 regression test

**Analog:** Existing `CategoryCRUDTests` suite — add one new `@Test` case.

**Existing `makeContainer` helper** (CategoryCRUDTests.swift lines 15–18):
```swift
private func makeContainer() throws -> ModelContainer {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    return try ModelContainer(for: Expense.self, Cat.self, configurations: config)
}
```

**Existing insert pattern** (CategoryCRUDTests.swift lines 21–32):
```swift
@Test("Category can be inserted and fetched")
func addCategory() throws {
    let container = try makeContainer()
    let context = container.mainContext
    let cat = Cat(name: "Groceries", symbolName: "cart", sortOrder: 0)
    context.insert(cat)
    try context.save()
    let fetched = try context.fetch(FetchDescriptor<Cat>())
    #expect(fetched.count == 1)
    #expect(fetched.first?.name == "Groceries")
}
```

**New test to add** — STAB-03 sort order regression:
```swift
@Test("newCategoryAppendsAtBottom: custom category appended at max(sortOrder)+1 — STAB-03")
func newCategoryAppendsAtBottom() throws {
    let container = try makeContainer()
    let context = container.mainContext

    // Seed 14 categories (orders 0–13, matching ModelContainer+App seedCategoriesIfNeeded)
    for i in 0..<14 {
        let cat = Cat(name: "Seed\(i)", symbolName: nil, sortOrder: i)
        context.insert(cat)
    }
    try context.save()

    // Simulate ManageCategoriesView.addCategory logic
    let all = try context.fetch(FetchDescriptor<Cat>())
    let nextSortOrder = (all.map(\.sortOrder).max() ?? 999) + 1
    let newCat = Cat(name: "Custom", symbolName: "tag", sortOrder: nextSortOrder)
    context.insert(newCat)
    try context.save()

    // Fetch sorted ascending — new category must be last
    let sorted = try context.fetch(FetchDescriptor<Cat>(sortBy: [SortDescriptor(\.sortOrder)]))
    #expect(sorted.last?.name == "Custom",
            "Custom category must appear at the bottom of the sorted list (STAB-03)")
    #expect(sorted.last?.sortOrder == 14,
            "New category sortOrder must be max(existing)+1 = 14 (STAB-03)")
}
```

---

## Shared Patterns

### `@MainActor @Observable final class` service pattern
**Source:** `MyHomeApp/Security/LockController.swift` lines 32–34
**Apply to:** `RoutineResetService.swift` (new file)
```swift
@MainActor
@Observable
final class LockController {
```

### `@State` ownership (not `@StateObject`)
**Source:** `MyHomeApp/RootView.swift` line 40
**Apply to:** `RoutineResetService` declaration in `RootView`
```swift
/// Face ID gate state — @Observable owned via @State, never @StateObject (PITFALLS.md Pitfall 10)
@State private var lockController = LockController()
```

### `scenePhase` observer — synchronous call style
**Source:** `MyHomeApp/RootView.swift` lines 106–114
**Apply to:** `RoutineResetService.resetIfNeeded()` wiring. Synchronous calls go directly in the `onChange` closure; async calls are wrapped in `Task { await ... }`.
```swift
.onChange(of: scenePhase) { _, newPhase in
    lockController.scenePhaseChanged(newPhase)
    gmailSyncController.scenePhaseChanged(newPhase)
    // Pitfall: never call async directly in onChange; always wrap in Task
    if newPhase == .active && lockController.isLocked && lockController.lockEnabled {
        Task { await lockController.authenticate() }
    }
}
```

### Tombstone guard (`modelContext != nil`)
**Source:** `MyHomeApp/Features/Notes/EditNoteView.swift` line 332
**Apply to:** `CalendarView.swift` `remindersOnDay` (for both `note` and `block` iterations), and `CalendarAggregator.events(from:)` / `perDayCounts(for:)`
```swift
guard !noteRemoved, note.modelContext != nil else { return }
```

### In-memory test container
**Source:** `MyHomeTests/CalendarAggregationTests.swift` lines 25–26
**Apply to:** All three new test cases (CalendarAggregationTests, GmailSyncControllerTests, CategoryCRUDTests)
```swift
let container = try ModelContainer(for: Note.self, NoteBlock.self,
    configurations: ModelConfiguration(isStoredInMemoryOnly: true))
```

### GmailSyncController injected context for tests
**Source:** `MyHomeTests/MultiAccountGmailTests.swift` line 369
**Apply to:** STAB-02 test in `GmailSyncControllerTests.swift`
```swift
controller.setContext(container.mainContext)
```

### Isolated UserDefaults per test
**Source:** `MyHomeTests/GmailSyncControllerTests.swift` lines 34–39
**Apply to:** STAB-02 test (needs `GmailSyncController` with fresh defaults per test run)
```swift
private func makeDefaults() -> UserDefaults {
    let name = "test.gsc.\(UUID().uuidString)"
    let d = UserDefaults(suiteName: name)!
    d.removePersistentDomain(forName: name)
    return d
}
```

### `@MainActor struct` + `@Test` suite declaration
**Source:** `MyHomeTests/CalendarAggregationTests.swift` lines 17–18
**Apply to:** All test additions (they go inside existing `@MainActor struct` bodies)
```swift
@MainActor
struct CalendarAggregationTests {
```

---

## No Analog Found

All files have close analogs. No entries in this section.

---

## Metadata

**Analog search scope:** `MyHomeApp/`, `MyHomeTests/`
**Files read:** 11 (LockController, RootView, EditNoteView, CalendarView, GmailSyncController, ManageCategoriesView, CalendarAggregationTests, CategoryCRUDTests, GmailSyncControllerTests, MultiAccountGmailTests, CONTEXT.md + RESEARCH.md)
**Pattern extraction date:** 2026-06-08
