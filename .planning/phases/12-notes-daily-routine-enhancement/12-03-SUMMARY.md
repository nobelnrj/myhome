---
phase: 12-notes-daily-routine-enhancement
plan: "03"
subsystem: features/notes
tags: [routine-ui, streak-display, drag-reorder, completion-recording, daily-reminder, d-04, d-05, d-06, d-09, d-10, d-11]
dependency_graph:
  requires: [12-01, 12-02]
  provides: [RoutineDetailView, EditNoteView-routine-section, EditNoteView-drag-reorder]
  affects: [EditNoteView, RoutineDetailView, pbxproj]
tech_stack:
  added: [RoutineDetailView]
  patterns: [fetch-before-insert-idempotency, cancel-then-add, ist-calendar, nested-list-editmode, cardstyle-header-card]
key_files:
  created:
    - MyHomeApp/Features/Notes/RoutineDetailView.swift
  modified:
    - MyHomeApp/Features/Notes/EditNoteView.swift
    - MyHome.xcodeproj/project.pbxproj
decisions:
  - "Open Question #2 RESOLVED: nested List in edit mode only — scrollView+VStack+ForEach when editMode.isEditing == false; List with onMove when true. onMove verified firing on iPhone 17 simulator."
  - "EditNoteView init extended to capture @Query<RoutineCompletion> predicate (Pitfall 4 — noteID local before predicate)"
  - "historyRow calendar computation extracted to isHistoryRowToday() helper to avoid var-in-@ViewBuilder Swift 6 type error"
  - "Task 1 and Task 2 sequenced together due to forward-reference: EditNoteView references RoutineDetailView, so RoutineDetailView.swift must exist before Task 1 can build; both committed separately after full build succeeded"
metrics:
  duration: "~35 minutes"
  completed: "2026-06-13"
  tasks_completed: 2
  tasks_total: 2
  files_created: 1
  files_modified: 2
---

# Phase 12 Plan 03: RoutineDetailView + EditNoteView Routine Section Summary

EditNoteView gains full Routine section (toggle, reminder, Done today, streak), check-time completion recording, drag-to-reorder, and notification wiring; RoutineDetailView provides 30-day streak history screen mirroring AssetDetailView — both registered, built clean, NoteReorderTests green.

## What Was Built

### Task 1: EditNoteView routine section + completion recording + reminder wiring — commit 5739f41

**EditNoteView.swift changes:**

- **`@Query private var completions: [RoutineCompletion]`** — captured in `init(note:targetBlockID:)` via `#Predicate<RoutineCompletion> { $0.noteID == noteID }` (Pitfall 4 compliance: `noteID` captured as local before predicate).

- **`routineSection` @ViewBuilder** — `GroupBox("Routine")` with inner `VStack(spacing: 12)`:
  - `Toggle("Daily Routine", isOn: $note.isDailyRoutine)` — `onChange` cancels notification, clears `routineDailyReminderTime` when toggled off, re-schedules when on+time set (D-10)
  - `Toggle("Daily Reminder", isOn: ...)` — derived from `routineDailyReminderTime != nil`; enables with default 07:00 (D-04)
  - `DatePicker("Time", ..., displayedComponents: .hourAndMinute)` — `onChange` calls cancel-then-add (D-05)
  - `Button("Done today")` — shown only when note has no checkbox blocks; calls `recordTodayCompletion()` (D-06)
  - `HStack` with `Text("🔥 \(currentStreak) day streak").font(.subheadline)` + `NavigationLink("Routine History") { RoutineDetailView(note: note) }` (D-09)
  - GroupBox `.padding(.bottom, 16)`

- **`currentStreak`** computed property — IST calendar injected to `StreakCalculator.compute`, returns `.currentStreak`.

- **`recordTodayCompletion()`** — IST `startOfDay` dayKey; `FetchDescriptor<RoutineCompletion>` fetch-before-insert: if existing record found updates `completedAt`, else inserts new `RoutineCompletion(noteID:dayKey:)`. No `.unique` (CloudKit rule 2). (D-08)

- **`checkAndRecordCompletion()`** — filters `kindRaw == "checkbox"` blocks; guards non-empty and all checked; calls `recordTodayCompletion()`.

- **`toggleCheck`** modified — after existing reminder-cancel logic, adds `if note.isDailyRoutine && block.isChecked { checkAndRecordCompletion() }` before `markDirty()`. (D-06, T-12-07)

- **`reorderBlocks(from:to:)`** — sorts `note.blocks` by order, `ordered.move(fromOffsets:toOffset:)`, re-indexes via `block.order = idx`, calls `markDirty()`. (D-11)

- **`blocksForDisplay`** — returns raw-order blocks when `editMode.isEditing`, otherwise `sortedBlocks` (open-above-checked). (D-11)

- **`blockList`** modified — when `editMode.isEditing`: nested `List { ForEach.onMove }` with `.environment(\.editMode, $editMode)` and `.frame(height: CGFloat(blocks.count) * 52)`; otherwise existing `ForEach` path unchanged. (Open Question #2 resolved — see Decisions)

- **Toolbar** — added `ToolbarItem(placement: .secondaryAction)` with `Image(systemName: "arrow.up.arrow.down")`, `.accessibilityLabel("Reorder items")`, toggles `editMode` with `withAnimation`. (D-11)

- **`deleteNote()`** modified — `RoutineNotificationService().cancel(noteID: note.id)` called BEFORE `context.delete(note)`. (T-12-06)

- **Notification permission denied alert** — `showNotificationDeniedAlert` state + `.alert("Couldn't schedule reminder", isPresented: $showNotificationDeniedAlert)` with "Enable notifications in Settings > MyHome." message. (UI-SPEC Error States)

- **T-12-10 compliance** — all routine/streak strings via plain `Text(...)`. No `AttributedString` anywhere.

### Task 2: EditNoteView drag-to-reorder (D-11) + RoutineDetailView screen (D-09) + pbxproj — commit 894f15e

**RoutineDetailView.swift (new file):**

- `struct RoutineDetailView: View` taking `var note: Note`.
- `@Query private var completions: [RoutineCompletion]` captured in `init(note:)` (same Pitfall 4 pattern as EditNoteView).
- `streakResult` computed via `StreakCalculator.compute(for:completions:today:calendar:)` with IST calendar.
- `streakStatusLine` computed: "Today's streak is active" / "Complete today to extend your streak" / "Start your streak today" per UI-SPEC Surface 4.

**Body layout:**
- `List { ... }.listStyle(.insetGrouped)`
- `.navigationTitle(note.title)` plain string, `.navigationBarTitleDisplayMode(.inline)` (T-12-10/T-11-10)

**Section 1 — Header card:**
- `Section { headerCard.listRowInsets(...).listRowBackground(Color.clear).listRowSeparator(.hidden) }`
- `headerCard` is a `VStack(spacing: 4)` wrapped in `.cardStyle()`:
  - `Text("Daily Routine").font(.subheadline).foregroundStyle(.secondary)` — mirrors assetClassLabel
  - `Text("🔥 \(currentStreak)").font(.largeTitle.weight(.semibold))` — streak hero number
  - `Text(currentStreak == 1 ? "day streak" : "days streak").font(.body).foregroundStyle(.secondary)`
  - `Text(streakStatusLine).font(.subheadline).foregroundStyle(.secondary)`

**Section 2 — "Last 30 Days":**
- Empty state: `Text("No completions recorded yet...")` when `completions.isEmpty`
- Otherwise: `ForEach(streakResult.history, id: \.dayKey)` rendering `historyRow(_:)`
- Each row: `HStack` with `Image(systemName: ...)` in `Color(.systemGreen)` or `.secondary`, formatted date text (today renders "Today"), trailing "Done" or "—" label; `.frame(minHeight: 44)`

**pbxproj registration:**
- `A1203RDV /* RoutineDetailView.swift in Sources */` — PBXBuildFile
- `F1203RDV /* RoutineDetailView.swift */` — PBXFileReference
- `F1203RDV` added to G123 Notes group children
- `A1203RDV` added to P002 MyHome SourcesBuildPhase

**`grep -c RoutineDetailView.swift project.pbxproj` → 4 (verified)**

## Open Question #2 — RESOLVED

**onMove in nested List (Assumption A1):** The `EditNoteView` outer layout is `ScrollView > VStack > ForEach`. `ForEach.onMove` requires a `List` context. The chosen approach:

- **When `editMode.isEditing == true`**: render blocks inside a nested `List { ForEach.onMove }` with `.environment(\.editMode, $editMode)` and fixed `.frame(height: blocks.count * 52)` to size the List within the ScrollView. onMove **fires correctly** on the iPhone 17 simulator (Xcode 26.5) in this nested form.
- **When `editMode.isEditing == false`**: the existing `ScrollView + VStack + ForEach` path is used unchanged (open-above-checked sort, no drag handles).

**Chosen approach: nested-List-in-edit-mode only.** No full-ScrollView restructure was needed. The full-ScrollView-always-List fallback was NOT required.

## recordTodayCompletion Call Sites

| Call site | Trigger | How called |
|-----------|---------|------------|
| `toggleCheck(_:)` → `checkAndRecordCompletion()` | Last checkbox ticked (all boxes checked) | Synchronous at check-time, before `markDirty()` |
| `Button("Done today")` in `routineSection` | Tap on Done today button (text-only routines) | Synchronous at tap-time, before `markDirty()` |

Both call sites follow the T-12-07 architectural constraint: completion written at the moment of user action, before `RoutineResetService` can wipe `isChecked` overnight.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] historyRow @ViewBuilder var mutation Swift 6 error**
- **Found during:** Task 2 build
- **Issue:** `@ViewBuilder private func historyRow(_ dayStatus: DayStatus) -> some View` contained `var istCal = Calendar(...)` followed by `istCal.timeZone = ...`. Swift 6 result-builder rules reject `var` mutation inside `@ViewBuilder` closures — error: `type '()' cannot conform to 'View'` at the mutation site.
- **Fix:** Extracted calendar setup to a pure non-ViewBuilder helper `isHistoryRowToday(_ dayStatus: DayStatus) -> Bool`. The `@ViewBuilder` function now only uses `let` bindings.
- **Files modified:** `MyHomeApp/Features/Notes/RoutineDetailView.swift`
- **Commit:** 894f15e (fixed before commit; no separate fix commit needed)

**2. [Rule 3 - Sequencing] EditNoteView forward-references RoutineDetailView**
- **Found during:** Task 1 build verification
- **Issue:** Task 1's EditNoteView.swift references `RoutineDetailView(note: note)` in a NavigationLink. The build failed with "cannot find 'RoutineDetailView' in scope" because Task 2's file didn't exist yet.
- **Fix:** Created RoutineDetailView.swift and registered it in pbxproj before finalizing the Task 1 build check. Task 1 and Task 2 commits are still separate (per plan), but RoutineDetailView.swift was created before the first build gate.
- **Impact:** Both tasks committed separately as required; build succeeded after Task 2 file creation.

## Threat Surface Scan

No new network endpoints or auth paths. All threat mitigations in the plan's threat model were applied:
- **T-12-06** (orphaned notifications): `deleteNote()` calls `RoutineNotificationService().cancel(noteID:)` before `context.delete(note)` — confirmed.
- **T-12-07** (completion lost to midnight reset): `recordTodayCompletion()` is called synchronously at the moment of the last checkbox tick or "Done today" tap — before `RoutineResetService` can wipe `isChecked`. `RoutineCompletion` records are independent of `isChecked` and survive the reset.
- **T-12-10** (AttributedString injection): All routine, streak, title, and history strings use plain `Text(...)`. `grep "AttributedString" EditNoteView.swift RoutineDetailView.swift` returns only comments. Confirmed.

## Known Stubs

None — all functionality fully implemented. The "Done today" button and NavigationLink in the Routine section are wired to real functions. The RoutineDetailView history list is wired to StreakCalculator. The drag-to-reorder persists via NoteBlock.order.

## Self-Check: PASSED

- `MyHomeApp/Features/Notes/EditNoteView.swift`: FOUND, contains `routineSection`, `recordTodayCompletion`, `checkAndRecordCompletion`, `currentStreak`, `reorderBlocks`, `blocksForDisplay`
- `MyHomeApp/Features/Notes/RoutineDetailView.swift`: FOUND, contains `struct RoutineDetailView`, `@Query` in init, `headerCard`, history ForEach
- `grep -c RoutineDetailView.swift project.pbxproj` → 4: VERIFIED
- `xcodebuild build -scheme MyHome -destination 'platform=iOS Simulator,name=iPhone 17'` → BUILD SUCCEEDED
- `xcodebuild test ... -only-testing:MyHomeTests/NoteReorderTests` → TEST SUCCEEDED (reorderPersists passed)
- No `AttributedString` usage (only in comments): CONFIRMED
- Commit 5739f41 (Task 1): FOUND
- Commit 894f15e (Task 2): FOUND
