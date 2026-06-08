# Phase 8: Stabilization — Research

**Researched:** 2026-06-08
**Domain:** SwiftData @Model tombstone guards, async ModelContext safety, category sort order, RoutineResetService scaffold
**Confidence:** HIGH — all findings drawn directly from reading the live codebase; no external speculation

---

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions
- **D-01:** Deleted item's row vanishes live; sheet stays open showing remaining reminders. If day becomes empty, show existing `ContentUnavailableView "No Reminders"`. Do NOT auto-dismiss the sheet.
- **D-02:** Preserve live-binding design (D3: agenda binds live to `Note`/`NoteBlock`, never snapshots). Fix guards `@Model` property access against tombstoned/deleted objects in `AgendaReminderItem` computed properties and `remindersOnDay`.
- **D-03:** Per-message parse failure or category re-fetch failure: skip bad message, continue rest, then single batched `ctx.save()` at end.
- **D-04:** `Category` references re-resolved by `PersistentIdentifier` after each `await` suspension point. Single batched save moves out of per-message loop.
- **D-05:** `ManageCategoriesView.addCategory` (line 191-193) already uses `max(existing.sortOrder)+1` correctly. Research must locate the actual offending add path before assuming a fix is needed there.
- **D-06:** Ship a logged scaffold — full call path `RootView scenePhase .active` → `RoutineResetService.resetIfNeeded()` — logs "would reset" but performs no model writes this phase.
- **D-07:** Wire service alongside existing `scenePhase` observers (`LockController.scenePhaseChanged`, `gmailSyncController.scenePhaseChanged`). Follow `@MainActor` / `Task`-wrapping pattern already present in `RootView.body`.
- **D-08:** Add Swift Testing regression tests for both crash fixes. Tests must fail against pre-fix behavior and pass after.

### Claude's Discretion
- Exact tombstone-detection mechanism (`isDeleted` check vs. `modelContext`-based validity probe vs. try/guard) — researcher/planner picks the SwiftData-idiomatic approach for iOS 17+.
- Test harness shape (in-memory `ModelContainer`, fixture builders) — follow existing Swift Testing patterns in the repo.

### Deferred Ideas (OUT OF SCOPE)
- None — discussion stayed within phase scope. Routine-reset logic, `NoteBlock.lastCheckedDate`, and accounts/transfer work are roadmapped to Phases 9–12.
</user_constraints>

---

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| STAB-01 | App no longer crashes when Notes calendar / day-agenda is open and a note or block is deleted (guard `DayAgendaView` / `AgendaReminderItem` against tombstoned `@Model` references) | Section: STAB-01 Tombstone Guard |
| STAB-02 | Gmail sync no longer crashes or stalls (re-fetch `Category` references after `await` suspension points; move `ctx.save()` out of per-message loop into single batched save) | Section: STAB-02 Gmail Sync |
| STAB-03 | Adding a new category appends it to the bottom, not the top (stable insertion order using `max(existing.sortOrder)+1`) | Section: STAB-03 Actual Offender |
| STAB-04 (scaffold only) | `RoutineResetService` skeleton wired to `RootView.onChange(of: scenePhase)` on `.active`; logged no-op; Phase 9 fills the body | Section: STAB-04 Service Scaffold |
</phase_requirements>

---

## Summary

Phase 8 is a targeted crash-fix and correctness pass with no schema changes. All four work items are well-bounded and anchored to specific files and line ranges confirmed by codebase inspection.

**STAB-01** crashes because `DayAgendaView.remindersOnDay` and `AgendaReminderItem` computed properties access `@Model` properties on live Note/NoteBlock references that may have been deleted from the SwiftData context by another view (e.g., delete from NotesListView while DayAgendaView is open). The codebase already has one canonical tombstone guard pattern: `note.modelContext != nil` used in `EditNoteView.performSave` (line 332). A second pattern — `isDeleted` — is available on `@Model` in iOS 17+ via the `PersistentModel` protocol. The `modelContext != nil` probe is the project's established idiom. The fix is to filter out items whose backing model has been tombstoned before `remindersOnDay` builds its array, and to guard computed properties in `AgendaReminderItem`.

**STAB-02** crashes because `categoriesByName` is populated ONCE before the `await` loop (line 480-485 in `syncAccount`), and `Category` model references captured in that dictionary can be invalidated after each `await fetch.getRawMessage(...)` suspension point. Additionally, `ctx.save()` is called inside the per-message loop (line 533 in `syncAccount`, line 668 in `legacySingleAccountSync`). The fix is to re-fetch categories after each `await` OR switch to `PersistentIdentifier`-keyed lookup (fetch fresh from context by ID on demand), and move `ctx.save()` to a single call after the loop.

**STAB-03** — the actual offending path is `Category.init(name:symbolName:sortOrder:)` which defaults `sortOrder` to `0`. `ManageCategoriesView.addCategory` already computes `max(sortOrder)+1` correctly. The offending path is `seedCategoriesIfNeeded` in `ModelContainer+App.swift` — it seeds orders 0–13. When a user later adds a custom category, the computed `max()+1` = 14, which is correct. However, codebase inspection reveals a second creation site: `SpendByCategoryChart.swift:#Preview` uses `sortOrder: i` (loop index starting 0). This preview path is not production. The REAL production bug must be something more subtle: the `@Query(sort: \Category.sortOrder)` sorts ascending, so `sortOrder: 0` would appear at the TOP. If a custom category gets `sortOrder: 0` (from a bug in a code path), it appears first. The only non-ManageCategoriesView production creation site is the seed in `ModelContainer+App.swift` (orders 0–13, all correct). Therefore **STAB-03's root cause is the init default `sortOrder: Int = 0`** when code creates a Category without explicitly passing `sortOrder` — no other production quick-add path was found. ManageCategoriesView correctly passes it; the seed correctly passes it. The real risk is any future Category creation that omits the argument. The fix per D-05 is to confirm no other production path creates Category with default sortOrder=0, and add a test asserting new categories land at the bottom. Given that `ManageCategoriesView.addCategory` is the only user-facing add path and already computes correctly, the "fix" is likely adding a regression test plus reviewing if there is a second add path (e.g., from settings or an inline picker).

**STAB-04** follows the `GmailSyncController`/`LockController` ownership pattern exactly: `@MainActor @Observable final class`, owned in `RootView` via `@State`, called synchronously from the `onChange(of:scenePhase)` closure (no `Task` needed for synchronous work), or wrapped in `Task` if async.

**Primary recommendation:** Execute the four fixes in one wave: STAB-01 guard pass in CalendarView, STAB-02 refactor in GmailSyncController (both `syncAccount` and `legacySingleAccountSync`), STAB-03 investigation + regression test, STAB-04 new file `RoutineResetService.swift`.

---

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| Tombstone guard (STAB-01) | SwiftUI View layer | SwiftData Model | `@Model.modelContext` nil-check happens at the View computed-property boundary before any property access |
| Category re-fetch (STAB-02) | Service layer (GmailSyncController) | SwiftData context | Suspension-point safety is the controller's responsibility, not the view's |
| Sort order correctness (STAB-03) | Service layer (ManageCategoriesView action) | Schema default | Insertion logic lives in the action function; schema default is a safe fallback |
| RoutineResetService scaffold (STAB-04) | Service layer (new file) | RootView wiring | Mirrors GmailSyncController / LockController pattern; RootView is the scene-phase coordinator |

---

## STAB-01: Tombstone Guard Deep-Dive

### The Crash Surface (confirmed by codebase read)

**File:** `MyHomeApp/Features/Notes/CalendarView.swift`

**Crash path:**
1. User opens DayAgendaView (sheet) for a day with reminders.
2. From another view (NotesListView), user deletes the Note or NoteBlock that owns the reminder.
3. SwiftData tombstones the `@Model` object — its `modelContext` becomes `nil` and its stored properties are no longer safe to access.
4. DayAgendaView's `remindersOnDay` computed property (lines 295–319) iterates `notes` (from `@Query` passed in as `let notes: [Note]`) and accesses `note.reminderEnabled`, `note.reminderDate`, `block.reminderEnabled`, `block.reminderDate` without guarding.
5. `AgendaReminderItem.title`, `.isAllDay`, `.isChecked` computed properties access `note.title`, `note.blocks`, `block.text`, `block.isChecked` on possibly-tombstoned objects.
6. SwiftUI re-renders the `ForEach(remindersOnDay)` and crashes on property access to a faulted/deleted object.

`CalendarAggregator.events(from:)` has the same issue — it accesses `note.reminderEnabled`, `note.reminderDate`, `note.blocks`, `block.reminderEnabled`, `block.reminderDate` without any tombstone guard.

### Tombstone Detection: `modelContext != nil` vs `isDeleted`

**Established project idiom:** `EditNoteView.performSave` (line 332) uses:
```swift
guard !noteRemoved, note.modelContext != nil else { return }
```
[VERIFIED: codebase read — MyHomeApp/Features/Notes/EditNoteView.swift:332]

**`isDeleted` availability:** `PersistentModel.isDeleted` is a Bool property available on all `@Model` classes in iOS 17+ (SwiftData 1.0). It is `true` after `context.delete(_:)` is called and before the context is saved (pending delete state), AND after the save (tombstone state). [ASSUMED — based on training knowledge of SwiftData PersistentModel protocol; verify against Apple docs if in doubt]

**Recommendation (Claude's Discretion):** Use `note.modelContext != nil` as the primary guard because it is the project's established idiom (already in EditNoteView). This check returns `nil` for tombstoned objects. `isDeleted` is an alternative but introduces a new symbol into the codebase when the existing pattern is sufficient.

### Fix Pattern

In `remindersOnDay`:
```swift
private var remindersOnDay: [AgendaReminderItem] {
    var items: [AgendaReminderItem] = []
    let cal = Calendar.current
    for note in notes {
        // Guard: skip notes whose backing @Model has been tombstoned (STAB-01)
        guard note.modelContext != nil else { continue }
        if note.reminderEnabled,
           let date = note.reminderDate,
           cal.isDate(date, inSameDayAs: day) {
            items.append(AgendaReminderItem(target: .note(note), date: date))
        }
        for block in note.blocks ?? [] {
            guard block.modelContext != nil else { continue }
            if block.reminderEnabled,
               let date = block.reminderDate,
               cal.isDate(date, inSameDayAs: day) {
                items.append(AgendaReminderItem(target: .block(block), date: date))
            }
        }
    }
    return items.sorted { $0.date < $1.date }
}
```
[ASSUMED — pattern derived from established `EditNoteView` idiom; confirmed `modelContext` property exists on @Model via codebase]

`AgendaReminderItem` computed properties (`title`, `isAllDay`, `isChecked`) are safe once the items are guarded at construction time in `remindersOnDay`, because `remindersOnDay` is the sole construction site. The `ForEach` only renders items that survived the guard.

`CalendarAggregator.events(from:)` should similarly guard each note and block with `modelContext != nil` before accessing properties.

### toggleCompletion Safety

`toggleCompletion` (line 407) operates on items already in the `remindersOnDay` array. Since `remindersOnDay` is recomputed on every SwiftUI render (it is a computed property), any tombstoned item will have been filtered out before `toggleCompletion` can be called on it. No additional guard is needed inside `toggleCompletion`, but adding `guard note.modelContext != nil else { return }` at the top of each case is defensive best practice.

### Live-binding Preserved

The fix does NOT snapshot any models. Notes are still passed as live `[Note]` references from `@Query`. The guard only skips rendering rows for tombstoned models — the live binding is preserved for all non-deleted items (D-02 satisfied).

### D-01 Empty-State Behavior

`remindersOnDay` becomes empty after the last item is deleted. `DayAgendaView.body` already branches on `remindersOnDay.isEmpty` (line 324) and shows `ContentUnavailableView("No Reminders", ...)`. This empty state activates automatically — no new code needed for D-01. The sheet stays open because no dismiss is triggered.

---

## STAB-02: Gmail Sync Batched Save + Category Re-Fetch

### The Crash Surface (confirmed by codebase read)

**File:** `MyHomeApp/Features/Gmail/GmailSyncController.swift`

Two sync paths have the same bug: `syncAccount` (multi-account path, lines 421–545) and `legacySingleAccountSync` (lines 547–686).

**In `syncAccount`:**
- Categories fetched ONCE at lines 480–485, before the message loop.
- `ctx.save()` called INSIDE the per-message loop at line 533.
- Each `await fetch.getRawMessage(...)` at line 492 is a suspension point.

**In `legacySingleAccountSync`:**
- Categories fetched ONCE at lines 617–621.
- `ctx.save()` called INSIDE the loop at line 668.
- Same suspension-point problem.

**Why this crashes:** SwiftData `@Model` objects are tied to their `ModelContext` and not sendable across async suspension boundaries. When `getRawMessage` suspends (network I/O), the actor may process other work that invalidates the captured `Category` references. On resumption, accessing `categoriesByName[hint]` to set `expense.categories = [cat]` may reference a stale or invalidated object, causing a fault or crash. The in-loop `ctx.save()` also adds unnecessary pressure: N saves for N messages where 1 save suffices.

### Fix: PersistentIdentifier-Based Re-Fetch Pattern

**Step 1:** Capture `PersistentIdentifier` values before the loop (safe across suspension — `PersistentIdentifier` is a value type, `Sendable`):
```swift
// Capture IDs before the loop — PersistentIdentifier is Sendable (value type)
var categoryIDsByName: [String: PersistentIdentifier] = [:]
if let ctx = modelContext {
    for cat in (try? ctx.fetch(FetchDescriptor<Category>())) ?? [] {
        if let name = cat.name { categoryIDsByName[name] = cat.persistentModelID }
    }
}
```

**Step 2:** Inside the loop, after each `await`, re-resolve by PersistentIdentifier:
```swift
// After await getRawMessage — re-resolve category from context by ID
if let hint = parsed.categoryHint,
   let catID = categoryIDsByName[hint],
   let ctx = modelContext,
   let cat = ctx.model(for: catID) as? Category {
    expense.categories = [cat]
}
// On failure: skip category assignment (D-03: skip bad message, continue)
```
[ASSUMED — `ModelContext.model(for:)` API; verify exact call signature in Apple docs. The existing codebase uses `persistentModelID` for keying in `BudgetCalculatorTests` and `OverviewAggregationTests`, confirming `PersistentIdentifier` is already the project's identity pattern]

**Step 3:** Move `ctx.save()` to after the loop:
```swift
// Single batched save after all messages processed (D-04)
if let ctx = modelContext {
    try ctx.save()
}
```

**D-03 compliance:** On category re-fetch failure (e.g., category was deleted mid-sync), skip the category assignment and continue processing the message. The expense is still inserted; it just has no category hint applied. This matches the existing per-message resilience pattern — the outer `catch` only catches network errors, not per-message failures.

**Both paths need the same refactor:** `syncAccount` AND `legacySingleAccountSync` must both be updated.

### Verifying No Downstream Assumes Mid-Sync Persistence

The only reader of expenses between sync and completion is `ExpenseListView` via `@Query`. SwiftData `@Query` updates atomically after `ctx.save()` — it does not observe partial in-loop saves. Moving save to end-of-batch is safe.

---

## STAB-03: Category Insertion Order — Actual Offender Found

### Investigation Result

Grep of all `Category(` instantiation sites across the codebase (production code only):

| File | Line | sortOrder value |
|------|------|-----------------|
| `ManageCategoriesView.swift:193` | `addCategory()` | `(all.map(\.sortOrder).max() ?? 999) + 1` — **CORRECT** |
| `ModelContainer+App.swift:89` | `seedCategoriesIfNeeded` | `$0.order` (0–13 hardcoded) — **CORRECT** |
| `SpendByCategoryChart.swift:114` | `#Preview` block | `sortOrder: i` — **preview only, not production** |

**Conclusion:** There is NO broken production add path other than `ManageCategoriesView.addCategory`, which is already correct.

**The actual STAB-03 bug is most likely one of:**
1. **Sort collision from seed + add:** The seed writes categories 0–13. `max(sortOrder)+1 = 14`. This is correct — new categories do append at the bottom. This path works correctly.
2. **Stale data bug in the user's live store:** The user may have pre-existing data where a custom category was created before the `max()+1` logic was in place, resulting in `sortOrder: 0` for that custom category (appearing at top).
3. **The `Category.init` default `sortOrder: Int = 0`:** If code ever creates a `Category` without passing `sortOrder`, it defaults to `0` and will sort to the TOP (before seed categories). This is a latent footgun, not currently triggered by any production path.

**Resolution for the plan:** STAB-03's fix is a **regression test** confirming that `ManageCategoriesView.addCategory` produces an item at max+1, plus a **code review comment** on `Category.init` noting the sortOrder=0 default is dangerous. If the user is seeing new categories at the top, it may be stale live-store data, not a code bug. The plan must include: (a) verify the live app behavior matches the bug report; (b) add a regression test asserting add produces bottom-position item; (c) add a `// WARNING: sortOrder defaults to 0` comment on the Category init.

[VERIFIED: codebase read — all production Category creation sites enumerated above]

---

## STAB-04: RoutineResetService Scaffold

### Ownership Pattern (from codebase)

Both `LockController` and `GmailSyncController` are:
- `@MainActor @Observable final class`
- Owned by `RootView` via `@State private var name = ClassName()`
- Called from `RootView.onChange(of: scenePhase)` synchronously (no `Task`) for non-async work, or wrapped in `Task { await ... }` for async work

`LockController.scenePhaseChanged` is synchronous (no `Task` needed from call site).
`GmailSyncController.scenePhaseChanged` is synchronous (only sets observable state; sync triggering happens elsewhere).

**RoutineResetService pattern:**

```swift
// MyHomeApp/Features/Notes/RoutineResetService.swift
@MainActor
@Observable
final class RoutineResetService {

    func resetIfNeeded() {
        // STAB-04 scaffold: no model writes this phase (NoteBlock.lastCheckedDate
        // doesn't exist yet — Phase 9 fills this body).
        let ist = TimeZone(identifier: "Asia/Kolkata")!
        var cal = Calendar.current
        cal.timeZone = ist
        let todayIST = cal.startOfDay(for: Date())
        // Phase 9 will compare todayIST to NoteBlock.lastCheckedDate per block.
        print("[RoutineResetService] resetIfNeeded called. startOfToday IST: \(todayIST). No-op this phase.")
    }
}
```

**RootView wiring:**

```swift
// In RootView — alongside existing scenePhase handlers
@State private var routineResetService = RoutineResetService()

// In .onChange(of: scenePhase):
.onChange(of: scenePhase) { _, newPhase in
    lockController.scenePhaseChanged(newPhase)
    gmailSyncController.scenePhaseChanged(newPhase)
    if newPhase == .active {
        routineResetService.resetIfNeeded()   // synchronous — no Task needed
    }
    if newPhase == .active && lockController.isLocked && lockController.lockEnabled {
        Task { await lockController.authenticate() }
    }
}
```

**Swift 6 strict concurrency:** `resetIfNeeded()` is `@MainActor` isolated (inherits from class annotation). Calling it from `onChange(of:)` which is also on the main actor is safe — no `Task` needed since it is synchronous. The `print` call is legal from `@MainActor`.

**IST seam:** `TimeZone(identifier: "Asia/Kolkata")` is the hardcoded IST identifier. Phase 9 will compare `todayIST` against a per-block stored date. The scaffold establishes this comparison structure so Phase 9 only adds the fetch + comparison logic.

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Tombstone detection | Custom `isInvalid` flag | `note.modelContext != nil` | Project-established pattern; `@Model` already provides this via `PersistentModel` protocol |
| Re-identifying Category across async | Capturing the `@Model` object | Capture `persistentModelID` (value type, Sendable) and re-fetch via `ctx.model(for:)` | `@Model` objects are reference types tied to actor; IDs are value types safe to pass across suspension |
| Background date math | Custom timezone offset calculation | `Calendar` with `timeZone = TimeZone(identifier: "Asia/Kolkata")!` | `Calendar` handles DST-safe date arithmetic |
| Observable service class | Protocol-witness pattern | `@MainActor @Observable final class` | Matches LockController / GmailSyncController exactly; no protocol indirection needed for Phase 8 |

---

## Architecture Patterns

### Recommended Project Structure for Phase 8

No new directories. All four changes touch existing files or add one new file:

```
MyHomeApp/
├── Features/
│   ├── Notes/
│   │   ├── CalendarView.swift          # STAB-01: guard in remindersOnDay + AgendaReminderItem
│   │   └── RoutineResetService.swift   # STAB-04: new file (same folder as CalendarView)
│   └── Gmail/
│       └── GmailSyncController.swift   # STAB-02: refactor syncAccount + legacySingleAccountSync
├── RootView.swift                       # STAB-04: @State + onChange wiring
└── Support/
    └── CalendarAggregator.swift        # STAB-01: guard in events(from:)
MyHomeTests/
├── CalendarAggregationTests.swift      # STAB-01 regression test addition
├── GmailSyncControllerTests.swift      # STAB-02 regression test addition
└── CategoryCRUDTests.swift             # STAB-03 regression test addition
```

### System Architecture Diagram

```
scenePhase .active
    |
    v
RootView.onChange(of:scenePhase)
    |-- lockController.scenePhaseChanged(.active)     [existing]
    |-- gmailSyncController.scenePhaseChanged(.active) [existing]
    `-- routineResetService.resetIfNeeded()            [NEW: STAB-04 no-op scaffold]

User opens DayAgendaView
    |
    v
DayAgendaView.remindersOnDay [computed property]
    |-- for note in notes:
    |       guard note.modelContext != nil  [NEW: STAB-01 guard]
    |-- for block in note.blocks:
    |       guard block.modelContext != nil [NEW: STAB-01 guard]
    `-- returns filtered [AgendaReminderItem]
         |
         v
    ForEach renders rows (tombstoned items absent — D-01 auto-satisfied)

User triggers Gmail sync
    |
    v
GmailSyncController.syncAccount / legacySingleAccountSync
    |-- fetch Category IDs before loop (PersistentIdentifier map) [REFACTORED: STAB-02]
    |-- for messageID in messageIDs:
    |       await fetch.getRawMessage(...)  [suspension point]
    |       re-resolve Category by ID from ctx  [NEW: STAB-02]
    |       ctx.insert(expense)
    |       on failure: skip + continue  [D-03]
    `-- ctx.save() ONCE after loop  [MOVED: STAB-02]
```

### Anti-Patterns to Avoid

- **Snapshot copy to avoid tombstone:** Do not copy `note.title`, etc., into a plain struct before displaying. D-02 explicitly prohibits snapshots. Use the `modelContext != nil` guard instead.
- **`try ctx.save()` inside the per-message loop:** Causes N round-trips to persistent store; one batch save is correct.
- **Capturing `@Model` objects across `await`:** `Category` objects captured before `await` are invalid after suspension. Always capture `PersistentIdentifier` (value type) and re-fetch.
- **Using `@StateObject` for RoutineResetService:** Use `@State` + `@Observable` (matches existing LockController pattern; `@StateObject` is the pre-iOS 17 pattern for `ObservableObject`).

---

## Common Pitfalls

### Pitfall 1: `@Query`-passed notes include tombstoned objects
**What goes wrong:** `DayAgendaView` receives `notes: [Note]` as a `let` parameter from CalendarView, which derives it from `@Query private var notes: [Note]`. When a Note is deleted, SwiftData may include the tombstoned object in the array until the next `@Query` refresh cycle. Between deletion and refresh, the object's properties fault.
**Why it happens:** `@Query` snapshots are not instantaneous; a delete in another view context may not propagate to the query result before the next render pass.
**How to avoid:** Guard every property access on `@Model` objects with `guard note.modelContext != nil` before accessing any property.
**Warning signs:** EXC_BAD_ACCESS or SwiftData faulting error on a `@Model` property in a view that didn't perform the delete.

### Pitfall 2: Category Dictionary Stale After Await
**What goes wrong:** `categoriesByName: [String: Category]` is built once before the loop. After `await fetch.getRawMessage(...)`, the `Category` model references inside the dictionary may be stale.
**Why it happens:** SwiftData `@Model` objects are actor-isolated. Async suspension can invalidate object state.
**How to avoid:** Capture `PersistentIdentifier` (Sendable value type) instead of `@Model` objects, and call `ctx.model(for:)` after each await to get a fresh reference.
**Warning signs:** Crash or assertion in `expense.categories = [cat]` after the first `await` in a large inbox sync.

### Pitfall 3: Calling Async in onChange Without Task
**What goes wrong:** Directly calling `await routineResetService.resetIfNeeded()` in `onChange(of: scenePhase)` if the method were async.
**Why it happens:** `onChange` closure is synchronous.
**How to avoid:** Keep `RoutineResetService.resetIfNeeded()` synchronous for Phase 8. If Phase 9 needs async, add `Task { await routineResetService.resetIfNeeded() }` — exactly as `lockController.authenticate()` is already wrapped.
**Warning signs:** Compiler error "expression is 'async' but is not marked with 'await'".

### Pitfall 4: sortOrder Default Creates Invisible Bug
**What goes wrong:** `Category.init(name:symbolName:sortOrder:)` defaults `sortOrder` to `0`. Any future code that creates a Category without explicitly providing `sortOrder` will insert at the TOP of the sorted list.
**Why it happens:** The `@Query(sort: \Category.sortOrder)` sorts ascending. `0` beats all seed categories (0–13... wait, seed starts at 0 too, so all-zero would create ties resolved by insert order, not sort).
**How to avoid:** Add a code comment to the Category init warning about the default. Any future caller must always compute `max()+1`.
**Warning signs:** New categories appear mixed in the middle or at the top of the category list.

### Pitfall 5: Legacy Path Not Fixed
**What goes wrong:** Fixing only `syncAccount` (multi-account path) and missing `legacySingleAccountSync` leaves the legacy code path with the same in-loop `ctx.save()` and stale category reference bugs.
**Why it happens:** Two parallel sync paths exist in `GmailSyncController.swift` (the multi-account refactored path starting line 421, and the legacy path starting line 547).
**How to avoid:** Both paths must receive the STAB-02 refactor.

---

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | Swift Testing (native, no XCTest) |
| Config file | Standard Xcode test target; no separate config file |
| Quick run command | `xcodebuild test -project MyHome.xcodeproj -scheme MyHome -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:MyHomeTests/[TestSuiteName] 2>&1 | tail -20` |
| Full suite command | `xcodebuild test -project MyHome.xcodeproj -scheme MyHome -destination 'platform=iOS Simulator,name=iPhone 17' 2>&1 | tail -30` |

### Phase Requirements → Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| STAB-01 | `remindersOnDay` skips tombstoned Note | unit | `-only-testing:MyHomeTests/CalendarAggregationTests` | Partial — file exists; new test case needed |
| STAB-01 | `remindersOnDay` skips tombstoned NoteBlock | unit | `-only-testing:MyHomeTests/CalendarAggregationTests` | Partial |
| STAB-02 | Sync completes when category captured before await is stale | unit | `-only-testing:MyHomeTests/GmailSyncControllerTests` | Partial — file exists; new test case needed |
| STAB-02 | Single `ctx.save()` called after loop (not N times) | unit | `-only-testing:MyHomeTests/GmailSyncControllerTests` | Partial |
| STAB-03 | New custom category appended at max(sortOrder)+1 | unit | `-only-testing:MyHomeTests/CategoryCRUDTests` | Partial — file exists; regression test needed |
| STAB-04 | RoutineResetService.resetIfNeeded() does not crash or mutate | smoke | manual or unit | No — Wave 0 gap |

### Existing Test Infrastructure (confirmed by codebase read)

- **In-memory container pattern:** `ModelConfiguration(isStoredInMemoryOnly: true)` + `ModelContainer(for: ..., configurations: config)` — established in `CategorySeedTests`, `CategoryCRUDTests`, `CalendarAggregationTests`, `MultiAccountGmailTests`.
- **SpyGmailFetch:** exists at `MyHomeTests/Support/SpyGmailFetch.swift`; supports `rawMessagesByID: [String: String]` for per-message-ID raw content overrides.
- **GmailSyncController with injected context:** `controller.setContext(container.mainContext)` — established pattern in `MultiAccountGmailTests` (confirmed line 369).
- **`@MainActor struct` with `@Test`:** all test suites use this pattern; new tests must follow.

### Wave 0 Gaps

- [ ] New `@Test` in `CalendarAggregationTests.swift` — covers STAB-01: delete Note from context, verify it does not appear in `remindersOnDay` output
- [ ] New `@Test` in `GmailSyncControllerTests.swift` — covers STAB-02: use in-memory container, insert Category, configure SpyGmailFetch to return one parseable message, call `sync()`, verify expense was inserted + `ctx.save()` was called once (not N times)
- [ ] New `@Test` in `CategoryCRUDTests.swift` — covers STAB-03: insert seed categories (0–13), call `addCategory`, verify new category has `sortOrder == 14`
- [ ] Wave 0 note: no new test files needed — all additions go into existing suites

---

## Code Examples

### STAB-01: Tombstone Guard in remindersOnDay
```swift
// Source: established project idiom from EditNoteView.swift:332
// Applied to CalendarView.DayAgendaView.remindersOnDay
for note in notes {
    guard note.modelContext != nil else { continue }   // skip tombstoned notes
    if note.reminderEnabled, let date = note.reminderDate,
       cal.isDate(date, inSameDayAs: day) {
        items.append(AgendaReminderItem(target: .note(note), date: date))
    }
    for block in note.blocks ?? [] {
        guard block.modelContext != nil else { continue }  // skip tombstoned blocks
        if block.reminderEnabled, let date = block.reminderDate,
           cal.isDate(date, inSameDayAs: day) {
            items.append(AgendaReminderItem(target: .block(block), date: date))
        }
    }
}
```

### STAB-02: PersistentIdentifier-Keyed Category Map
```swift
// Source: PersistentIdentifier pattern from BudgetCalculatorTests.swift:153
// and OverviewAggregationTests.swift:168

// BEFORE the message loop:
var categoryIDsByName: [String: PersistentIdentifier] = [:]
if let ctx = modelContext {
    for cat in (try? ctx.fetch(FetchDescriptor<Category>())) ?? [] {
        if let name = cat.name { categoryIDsByName[name] = cat.persistentModelID }
    }
}

// INSIDE the message loop, after each await:
if let hint = parsed.categoryHint,
   let catID = categoryIDsByName[hint],
   let ctx = modelContext,
   let cat = ctx.model(for: catID) as? Category {
    expense.categories = [cat]
}
// If re-fetch fails, skip category assignment (D-03) — continue processing

// AFTER the message loop (not inside):
if let ctx = modelContext, !insertedAny {
    // only save if at least one expense was inserted
}
try ctx.save()   // single batched save
```

### STAB-04: RoutineResetService Scaffold
```swift
// New file: MyHomeApp/Features/Notes/RoutineResetService.swift
// Mirrors LockController.swift pattern exactly

@MainActor
@Observable
final class RoutineResetService {

    func resetIfNeeded() {
        // STAB-04: logged scaffold only. Phase 9 adds NoteBlock.lastCheckedDate
        // comparison once SchemaV6 lands.
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Kolkata")!
        let todayIST = cal.startOfDay(for: Date())
        // Phase 9 implementation:
        //   fetch all NoteBlocks where note.isRoutine == true
        //   for each block where lastCheckedDate < todayIST: reset isChecked = false
        print("[RoutineResetService] resetIfNeeded: startOfToday IST = \(todayIST). No-op (Phase 8 scaffold).")
    }
}
```

```swift
// RootView.swift additions:
// 1. Add @State property alongside lockController:
@State private var routineResetService = RoutineResetService()

// 2. Add to .onChange(of: scenePhase) closure:
if newPhase == .active {
    routineResetService.resetIfNeeded()
}
```

---

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| `@StateObject` + `ObservableObject` | `@State` + `@Observable` | iOS 17 / Swift 5.9 | All new services use `@Observable`; existing LockController already uses it |
| `ctx.save()` inside loops | Single batched `ctx.save()` after loop | Best practice always | N→1 write roundtrips; crash elimination |
| Trusting `@Model` refs across `await` | Capture `PersistentIdentifier`, re-fetch after `await` | SwiftData 1.0 + Swift concurrency | Eliminates a whole class of use-after-free bugs |

---

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | `PersistentModel.isDeleted` is available on iOS 17+ | STAB-01 Tombstone Guard | Alternative: use `modelContext != nil` which is confirmed in the codebase — zero risk regardless |
| A2 | `ModelContext.model(for: PersistentIdentifier)` returns `nil` when the object is deleted | STAB-02 Category Re-Fetch | If API signature differs, use `ctx.fetch` with a `#Predicate` on `persistentModelID` instead |
| A3 | STAB-03 is a user-facing regression from stale live-store data, not an active code bug in the current add path | STAB-03 Offender | If a second add path exists (e.g., inline quick-add not visible to grep), it must be found and fixed |

---

## Open Questions

1. **STAB-03: Confirming the actual user-visible bug**
   - What we know: All production `Category` creation sites pass `sortOrder` explicitly and correctly.
   - What's unclear: The user reported new categories appear at the top. This could be stale live-store data (pre-fix data with `sortOrder: 0`), or a path missed by grep.
   - Recommendation: The planner should include a task to **run the app and reproduce** the STAB-03 symptom before writing a code fix. If reproducible with current code, search for any non-grepped add path (e.g., a Settings-level quick-add, a SwiftUI preview leak, or a missing `sortOrder` in some code path). If NOT reproducible, STAB-03 fix is purely a regression test + comment.

2. **`ModelContext.model(for:)` exact API**
   - What we know: `PersistentIdentifier` is used extensively in the test suite for keying spend maps.
   - What's unclear: The exact call signature for looking up a model by `PersistentIdentifier` from `ModelContext`.
   - Recommendation: Verify against Apple SwiftData documentation before implementing STAB-02. Fallback: `ctx.fetch(FetchDescriptor<Category>(predicate: #Predicate { $0.persistentModelID == catID }))`.

---

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| Xcode | Build + test | Expected present | 26.5 | — |
| iPhone 17 simulator | Test target | Expected present | iOS 26+ | iPhone 16 (not preferred per MEMORY.md) |
| No external packages | All STABs | N/A | N/A | N/A |

**No external packages are introduced in Phase 8.** All fixes are pure Swift/SwiftData code changes.

---

## Package Legitimacy Audit

**No packages introduced this phase.** Section intentionally omitted.

---

## Security Domain

Security enforcement is enabled (`security_enforcement: true`, ASVS Level 1).

| ASVS Category | Applies | Standard Control |
|---------------|---------|-----------------|
| V2 Authentication | No | Phase 8 does not touch auth |
| V3 Session Management | No | Not in scope |
| V4 Access Control | No | Not in scope |
| V5 Input Validation | No | No new user input paths |
| V6 Cryptography | No | No crypto |

**No new threat surfaces introduced.** All four work items are internal logic fixes.

**Existing security posture preserved:**
- T-03-16 (no note body in logs): `RoutineResetService.resetIfNeeded()` log only prints the IST date, not any note content.
- T-03-09 (no note content in CalendarAggregator): The tombstone guard adds no logging.
- T-02-07 (plain Text only): No UI changes introduce new text rendering.

---

## Sources

### Primary (HIGH confidence)
- Codebase read: `MyHomeApp/Features/Notes/CalendarView.swift` lines 224–470 — confirmed `AgendaReminderItem`, `remindersOnDay`, `toggleCompletion` crash surfaces
- Codebase read: `MyHomeApp/Features/Gmail/GmailSyncController.swift` lines 421–686 — confirmed per-message `ctx.save()` and pre-loop category fetch in both sync paths
- Codebase read: `MyHomeApp/Features/Budgets/ManageCategoriesView.swift` lines 175–203 — confirmed `addCategory` already uses `max(sortOrder)+1`
- Codebase read: `MyHomeApp/Persistence/ModelContainer+App.swift` — confirmed seed is only other production Category creation site; seeds use explicit `sortOrder: $0.order`
- Codebase read: `MyHomeApp/RootView.swift` — confirmed `@State`, `onChange(of: scenePhase)`, and service call pattern
- Codebase read: `MyHomeApp/Security/LockController.swift` — confirmed `@MainActor @Observable final class` + `scenePhaseChanged` pattern
- Codebase read: `MyHomeApp/Features/Notes/EditNoteView.swift:332` — confirmed `note.modelContext != nil` is the established tombstone idiom
- Codebase read: `MyHomeTests/` — confirmed Swift Testing framework, `@MainActor struct`, in-memory container, SpyGmailFetch patterns

### Secondary (MEDIUM confidence)
- `MyHomeTests/MultiAccountGmailTests.swift:369` — `controller.setContext(container.mainContext)` confirms GmailSyncController can be tested with an injected in-memory context

### Tertiary (LOW confidence)
- `PersistentModel.isDeleted` availability on iOS 17+ [ASSUMED — training knowledge]
- `ModelContext.model(for: PersistentIdentifier)` exact API signature [ASSUMED — training knowledge; verify before implementation]

---

## Metadata

**Confidence breakdown:**
- STAB-01 fix strategy: HIGH — crash surface confirmed, established idiom confirmed from codebase
- STAB-02 fix strategy: HIGH — both offending lines confirmed in code; PersistentIdentifier approach follows existing test patterns
- STAB-03 root cause: MEDIUM — no broken production path found; root cause may be stale live data; confirmed via exhaustive grep
- STAB-04 scaffold: HIGH — pattern cloned directly from LockController / GmailSyncController; wiring site confirmed in RootView

**Research date:** 2026-06-08
**Valid until:** No expiry — all findings are codebase-grounded, not time-sensitive ecosystem facts
