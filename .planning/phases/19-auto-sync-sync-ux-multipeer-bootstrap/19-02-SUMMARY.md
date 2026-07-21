---
phase: 19-auto-sync-sync-ux-multipeer-bootstrap
plan: 02
subsystem: infra
tags: [sync, p2p, swiftdata, swift6-concurrency, observable, lww, multipeer, coordinator]

requires:
  - phase: 19-auto-sync-sync-ux-multipeer-bootstrap (plan 01)
    provides: SyncTransport @MainActor seam + SyncEnvelope wire format + MultipeerSyncTransport conformer
  - phase: 18-sync-foundation-schema-merge-engine-airdrop
    provides: SnapshotExporter.exportData / SnapshotImporter.mergeData (the merge engine reused unchanged)
provides:
  - SyncCoordinator — @MainActor @Observable orchestrator driving the SyncTransport seam (connect-triggered symmetric exchange, snapshotRequest reply, debounced local-change push with echo suppression, capped-backoff retry, manual syncNow)
  - SyncStatusStore — PeerSyncStatus enum + UserDefaults-persisted lastSyncedAt + connectedPeerName + lastMergeStats (the read surface for Plans 03/04)
  - FakeSyncTransport — pairable in-process test double proving all behaviors without two devices
  - MyHomeApp scenePhase wiring — foreground-only start/stop + .environment(syncCoordinator) injection
affects: [phase-19-plan-03, phase-19-plan-04, sync-ui, foreground-sync-bootstrap]

tech-stack:
  added: []
  patterns:
    - "Coordinator over an injected protocol seam (any SyncTransport) — unit-testable with a fake, zero MC/UIKit in the orchestrator"
    - "isMerging echo-loop guard with SYNCHRONOUS didSave delivery (queue: nil + MainActor.assumeIsolated) so the guard fires inside the merge's save"
    - "deviceName injected (UIDevice.current.name in prod, 'TestPhone' in tests) so the coordinator never imports UIKit"
    - "Merge engine reuse — coordinator NEVER re-implements merge/DTO logic (SnapshotImporter.mergeData only)"

key-files:
  created:
    - MyHomeApp/Sync/SyncStatusStore.swift
    - MyHomeApp/Sync/SyncCoordinator.swift
    - MyHomeTests/SyncCoordinatorTests.swift
  modified:
    - MyHomeApp/MyHomeApp.swift
    - MyHome.xcodeproj/project.pbxproj

key-decisions:
  - "Renamed the coordinator's status enum SyncStatus -> PeerSyncStatus to avoid an invalid-redeclaration collision with GmailSyncController.SyncStatus (both in module MyHome)"
  - "didSave observer registered with queue: nil (synchronous delivery) instead of queue: .main + Task hop, so the isMerging guard is observed while still true — otherwise the async hop defeats echo suppression"
  - "Deferred SyncCoordinatorTests.swift pbxproj registration to Task 2 (its creating task) per the project's interruption-safety rule, rather than registering it in Task 1 as the plan text said"

patterns-established:
  - "PeerSyncStatus is the P2P-sync status type; the Gmail pipeline's SyncStatus is unrelated — keep them distinct"
  - "Loopback FakeSyncTransport pair (peer + isConnected + synchronous delivery) proves multi-coordinator convergence in-process"

requirements-completed: []

duration: ~40 min
completed: 2026-07-21
---

# Phase 19 Plan 02: SyncCoordinator Orchestration Summary

**@MainActor @Observable `SyncCoordinator` that drives the 19-01 transport seam — connect-triggered symmetric snapshot exchange, `isMerging` echo-loop suppression, capped-backoff retry, and manual `syncNow` — reusing the Phase-18 merge engine verbatim and proven end-to-end with a paired `FakeSyncTransport` on in-memory SchemaV10 stores.**

## Performance

- **Duration:** ~40 min
- **Started:** 2026-07-21
- **Completed:** 2026-07-21
- **Tasks:** 3
- **Files modified:** 5 (3 created, 2 modified)

## Accomplishments
- `SyncCoordinator`: connect-triggered both-sides push (idempotent + LWW → one-round convergence), unconditional `snapshotRequest` reply, received-snapshot merge via `SnapshotImporter.mergeData`, debounced local-change push, capped exponential backoff retry (2s→30s), and manual `syncNow()` (connected → push + request; disconnected → force fresh discovery).
- `isMerging` echo-loop guard (T-19-05) made genuinely effective by switching the `ModelContext.didSave` observer to synchronous delivery — proven bounded by the `echoExchangeIsBounded` test (converged pair re-exchanging terminates, no ping-pong).
- `SyncStatusStore` with `PeerSyncStatus` (idle/connecting/syncing/error), UserDefaults-persisted `lastSyncedAt` (survives relaunch, "Never" until first sync), `connectedPeerName`, and `lastMergeStats`.
- `FakeSyncTransport` loopback double + 11 Swift Testing cases: change-on-A-appears-on-B, echo bound, request reply, syncNow (both paths), retry (active-only), foreground teardown, lastSyncedAt persistence, garbage-merge isolation (.error + store untouched), and newer-local-edit-survives (LWW, SYNC-05 proven early).
- MyHomeApp scenePhase wiring: `.active`→start, `.background`→stop + existing `scheduleBackgroundRefresh`, `.inactive`→untouched; `.onAppear` setContext+start; `.environment(syncCoordinator)` for descendant views.

## Task Commits

1. **Task 1: SyncStatusStore + SyncCoordinator (connect exchange, echo suppression, retry, syncNow)** — `62402ab` (feat)
2. **Task 2: FakeSyncTransport + SyncCoordinatorTests — loopback proof (11 cases)** — `6eb2592` (test)
3. **Task 3: Wire coordinator into MyHomeApp scenePhase (foreground-only + env inject)** — `25ec8bf` (feat)

_TDD note: Task 2 is marked `tdd="true"`, but the coordinator implementation already existed from Task 1; the test file (RED-that-was-GREEN) plus the one coordinator refinement it required (synchronous didSave delivery) were committed together as a single `test` commit — the tests genuinely exercise every `<behavior>` bullet and were verified green in isolation before the full suite._

## Files Created/Modified
- `MyHomeApp/Sync/SyncStatusStore.swift` — PeerSyncStatus + persisted lastSyncedAt + peer name + merge stats (Foundation only).
- `MyHomeApp/Sync/SyncCoordinator.swift` — the orchestrator (SwiftData + Foundation only; no MC, no UIKit).
- `MyHomeTests/SyncCoordinatorTests.swift` — FakeSyncTransport + 11 loopback behavior tests, `@Suite(.serialized)`.
- `MyHomeApp/MyHomeApp.swift` — scenePhase foreground-only lifecycle + coordinator env injection (+ `import UIKit`).
- `MyHome.xcodeproj/project.pbxproj` — 4 edits each for the two source files (Task 1) and the test file (Task 2).

## Decisions Made
- **PeerSyncStatus rename** (see deviations) — the plan's `enum SyncStatus` collides with the existing Gmail `SyncStatus`; a distinct name was mandatory to compile.
- **Synchronous didSave delivery** — `queue: nil` + `MainActor.assumeIsolated` so the merge's `context.save()` is observed inline while `isMerging` is still true; a `.main`/Task-hopped delivery runs after the `defer isMerging = false` and would let every merge schedule a push (the exact echo loop the guard exists to prevent). Valid because our production store is the MainActor mainContext.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Renamed `enum SyncStatus` → `PeerSyncStatus`**
- **Found during:** Task 1 (build)
- **Issue:** The plan specifies `enum SyncStatus`, but `GmailSyncController.swift` already declares `public enum SyncStatus` in the same `MyHome` module → `error: invalid redeclaration of 'SyncStatus'` + ambiguous type lookup.
- **Fix:** Named the P2P status type `PeerSyncStatus` (only referenced by name inside SyncStatusStore; the coordinator uses inferred member access, so no other call sites changed). Tests reference the store's `status` property, not the type name.
- **Files modified:** MyHomeApp/Sync/SyncStatusStore.swift
- **Verification:** App target BUILD SUCCEEDED; all status assertions green.
- **Committed in:** `62402ab` (Task 1)

**2. [Rule 1 - Bug] Echo guard was ineffective with async didSave delivery**
- **Found during:** Task 2 (writing the echo-suppression test)
- **Issue:** As first written, `setContext` used `queue: .main` + `Task { @MainActor in localStoreDidChange() }`. Both hops are asynchronous, so `localStoreDidChange` runs AFTER `handle`'s `defer { isMerging = false }` — meaning `isMerging` is already false and every merge-triggered save would schedule a push (defeats T-19-05).
- **Fix:** Switched the observer to `queue: nil` (synchronous inline delivery on the posting MainActor thread) and `MainActor.assumeIsolated`, so the guard is observed while `isMerging` is true.
- **Files modified:** MyHomeApp/Sync/SyncCoordinator.swift
- **Verification:** `echoExchangeIsBounded` and `mergeDoesNotEnqueuePush` pass; converged pairs terminate with no ping-pong.
- **Committed in:** `6eb2592` (Task 2)

**3. [Rule 3 - Blocking / interruption-safety] Deferred test-file pbxproj registration to Task 2**
- **Found during:** Task 1 (pbxproj registration step)
- **Issue:** The plan instructs registering `SyncCoordinatorTests.swift` (a Task-2 file) during Task 1. The project's interruption-safety rule forbids referencing a file in pbxproj before it exists.
- **Fix:** Registered the two source files in Task 1 (created there); registered the test file in Task 2, in the same commit that creates it. Mirrors the 19-01 precedent.
- **Files modified:** MyHome.xcodeproj/project.pbxproj
- **Verification:** Task 1 built with only the two source files; Task 2 built + full suite green after adding the test.
- **Committed in:** `62402ab` (Task 1), `6eb2592` (Task 2)

---

**Total deviations:** 3 auto-fixed (2 blocking, 1 bug). **Impact on plan:** No scope change — same three files ship. The rename and the synchronous-delivery fix were both required for correctness (compile + the guard's whole purpose); the pbxproj sequencing is strictly safer commit ordering.

## Issues Encountered
None beyond the deviations above. Disk held at ~15 GB free throughout; no ENOSPC. All builds and both full-suite runs completed cleanly.

## User Setup Required
None — no external service configuration. Real two-device discovery + the Local Network permission prompt remain a later human-verify concern (Plan 19-05), not exercisable on a single simulator.

## Next Phase Readiness
- The coordinator + status store are ready for Plan 19-03 (the Settings Sync surface reads `syncCoordinator.statusStore`) and Plan 19-04 (bootstrap drives `syncNow()` / start()).
- SYNC-04 is intentionally left PENDING in REQUIREMENTS.md — it spans 19-01..19-03 and completes only when the Sync-now UI lands in 19-03.
- SYNC-05 (no-data-loss / LWW) is proven early by `newerLocalEditSurvives`, ahead of its formal Plan-19-05 gate.

---
*Phase: 19-auto-sync-sync-ux-multipeer-bootstrap*
*Completed: 2026-07-21*

## Self-Check: PASSED
- FOUND: MyHomeApp/Sync/SyncStatusStore.swift
- FOUND: MyHomeApp/Sync/SyncCoordinator.swift
- FOUND: MyHomeTests/SyncCoordinatorTests.swift
- FOUND commit: 62402ab (Task 1)
- FOUND commit: 6eb2592 (Task 2)
- FOUND commit: 25ec8bf (Task 3)
- SyncCoordinatorTests: 11/11 passed; full suite: TEST SUCCEEDED (DarkBitIdentityTests green)
