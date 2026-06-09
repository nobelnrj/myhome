---
phase: 08-stabilization
plan: "04"
subsystem: notes/routine-reset
tags: [scaffold, service, scene-phase, IST, STAB-04]
one_liner: "RoutineResetService @MainActor @Observable scaffold wired to scenePhase .active with IST date seam (no model writes this phase)"
dependency_graph:
  requires: []
  provides: [RoutineResetService call path, IST startOfDay seam]
  affects: [RootView.swift, MyHomeApp/Features/Notes/RoutineResetService.swift]
tech_stack:
  added: []
  patterns: ["@MainActor @Observable final class (mirroring LockController)", "@State ownership in RootView", "synchronous onChange call (no Task wrap)"]
key_files:
  created:
    - MyHomeApp/Features/Notes/RoutineResetService.swift
  modified:
    - MyHomeApp/RootView.swift
    - MyHome.xcodeproj/project.pbxproj
decisions:
  - "Scaffold is a logged no-op (print only) — performs zero model writes until Phase 9 adds NoteBlock.lastCheckedDate (SchemaV6)"
  - "IST seam uses Calendar(identifier: .gregorian) + Asia/Kolkata timezone + startOfDay(for: Date()) — ready for Phase 9 comparison"
  - "Added RoutineResetService.swift to Xcode project (PBXBuildFile F158RRS/A158RRS, Notes group) as a deviation — required for build"
metrics:
  duration_minutes: 2
  completed_date: "2026-06-09T08:58:54Z"
  tasks_completed: 2
  tasks_total: 2
  files_created: 1
  files_modified: 2
requirements: [STAB-04]
---

# Phase 08 Plan 04: RoutineResetService Scaffold Summary

RoutineResetService @MainActor @Observable scaffold wired to scenePhase .active with IST date seam (no model writes this phase).

## What Was Built

- **`MyHomeApp/Features/Notes/RoutineResetService.swift`** (new): `@MainActor @Observable final class RoutineResetService` with a single synchronous `resetIfNeeded()` method. Establishes the IST date seam (`Calendar(identifier: .gregorian)` + `Asia/Kolkata` timezone + `startOfDay(for: Date())`). Logs a "would reset" message. Performs no model writes. Phase 9 placeholder comments document where `NoteBlock.lastCheckedDate` comparison will go once SchemaV6 lands.

- **`MyHomeApp/RootView.swift`** (modified): Added `@State private var routineResetService = RoutineResetService()` alongside `lockController`. Inside the existing `.onChange(of: scenePhase)` closure, added `if newPhase == .active { routineResetService.resetIfNeeded() }` after `gmailSyncController.scenePhaseChanged(newPhase)`. Called synchronously — no `Task` wrap — matching the existing `lockController.scenePhaseChanged` call style (D-07).

- **`MyHome.xcodeproj/project.pbxproj`** (modified): Added `PBXBuildFile` (`A158RRS`), `PBXFileReference` (`F158RRS`), Notes group child, and Sources build phase entry for `RoutineResetService.swift`.

## Commits

| Task | Name | Commit | Files |
|------|------|--------|-------|
| 1 | Create RoutineResetService.swift scaffold | eec743f | MyHomeApp/Features/Notes/RoutineResetService.swift (new) |
| 2 | Wire RoutineResetService into RootView scenePhase | 8884f39 | MyHomeApp/RootView.swift, MyHome.xcodeproj/project.pbxproj |

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Added RoutineResetService.swift to Xcode project**
- **Found during:** Task 2 build verification
- **Issue:** `RoutineResetService.swift` was created on disk but not registered in `MyHome.xcodeproj/project.pbxproj`. The compiler reported "cannot find 'RoutineResetService' in scope" because Xcode only compiles files tracked in the project.
- **Fix:** Added `PBXBuildFile` (A158RRS), `PBXFileReference` (F158RRS), Notes group child entry, and Sources build phase entry following the identical pattern used by existing Notes files (e.g., CalendarView.swift → F157CV/A157CV).
- **Files modified:** `MyHome.xcodeproj/project.pbxproj`
- **Commit:** 8884f39

## Threat Flags

No new threat surface beyond what the plan's threat model covers. The `print()` log line in `resetIfNeeded()` outputs only the IST date (no note content), preserving the T-03-16 posture documented in T-08-07.

## Known Stubs

`RoutineResetService.resetIfNeeded()` is intentionally a no-op scaffold for Phase 8. Phase 9 will fill the body once `NoteBlock.lastCheckedDate` (SchemaV6) is available. This stub does not prevent Phase 8's goal (establishing the wiring/call path before SchemaV6).

## Self-Check

**Files exist:**
- `MyHomeApp/Features/Notes/RoutineResetService.swift` — FOUND
- `MyHomeApp/RootView.swift` (modified) — FOUND

**Commits exist:**
- eec743f (Task 1) — verified
- 8884f39 (Task 2) — verified

**Build:** SUCCEEDED (iPhone 17 simulator, Xcode 26.5)

## Self-Check: PASSED
