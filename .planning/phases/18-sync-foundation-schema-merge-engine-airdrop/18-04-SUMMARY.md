---
phase: 18-sync-foundation-schema-merge-engine-airdrop
plan: 04
subsystem: sync
tags: [swiftdata, tombstones, deletion-log, lww, updatedAt, sync-01, sync-02, deleteSynced, touch]

# Dependency graph
requires:
  - phase: 18-01
    provides: SchemaV10 (syncID/updatedAt on 11 models, DeletionLog @Model, SyncStamped.touch())
  - phase: 18-02
    provides: SyncEntityKind rawValues, DeletionDTO / SyncSnapshot wire format
  - phase: 18-03
    provides: SnapshotExporter (tombstones exported) + SnapshotImporter (tombstones-first LWW merge)
provides:
  - "ModelContext.deleteSynced(_:kind:) — tombstone-then-delete choke point for all syncable deletes"
  - "ModelContext.deleteAppliedTombstone(_:) — engine-only raw delete used by the importer (no re-tombstoning)"
  - "All 14 live model-delete call sites converted to deleteSynced (DeletionLog is now written by real deletes, not just fixtures)"
  - "touch() stamping at user-edit save paths across Notes/Categories/Accounts/Assets so LWW resolves on honest clocks"
  - "DeletionTrackingTests — tombstone-on-delete, note-cascade tombstones, idempotent-safe, end-to-end propagation through the Plan-03 engine"
affects: [19-multipeer-transport, 20-kitchen-inventory]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Single delete choke point: user-initiated syncable deletes go ONLY through deleteSynced; a bare context.delete() on a @Model is now a grep-gated defect"
    - "Cascade-aware tombstoning: deleting a Note tombstones its cascade-deleted NoteBlocks first so a peer never re-imports them as orphans"
    - "Engine deletes are distinct from user deletes: deleteAppliedTombstone applies an already-recorded tombstone without forging a fresher deletedAt"
    - "touch() at the true mutation site (not the view file) — stamping lives where the field actually changes (AccountMerger, NoteRow, CalendarView, ReminderTarget)"

key-files:
  created:
    - MyHomeApp/Sync/DeletionTracker.swift
    - MyHomeTests/DeletionTrackingTests.swift
  modified:
    - MyHomeApp/Sync/SnapshotImporter.swift
    - MyHomeApp/Features/Expenses/ExpenseListView.swift
    - MyHomeApp/Features/Expenses/EditExpenseView.swift
    - MyHomeApp/Features/Expenses/ReviewInboxRow.swift
    - MyHomeApp/Features/Notes/EditNoteView.swift
    - MyHomeApp/Features/Notes/NotesListView.swift
    - MyHomeApp/Features/Notes/NoteRow.swift
    - MyHomeApp/Features/Notes/CalendarView.swift
    - MyHomeApp/Features/Notes/RoutineResetService.swift
    - MyHomeApp/Features/Notes/ReminderEditView.swift
    - MyHomeApp/Features/Budgets/ManageCategoriesView.swift
    - MyHomeApp/Features/Budgets/EditBudgetSheet.swift
    - MyHomeApp/Features/Settings/AccountsListView.swift
    - MyHomeApp/Features/Settings/MergeAccountView.swift
    - MyHomeApp/Features/Settings/MigrationReviewSheet.swift
    - MyHomeApp/Features/Settings/EditAccountView.swift
    - MyHomeApp/Features/Assets/AssetsListView.swift
    - MyHomeApp/Features/Assets/EditAssetView.swift
    - MyHomeApp/Features/Assets/ReconcileView.swift
    - MyHomeApp/Features/Ingestion/DuplicateExpenseCleanup.swift
    - MyHomeApp/Support/NetWorthSnapshotService.swift
    - MyHomeApp/Support/AccountMerger.swift
    - MyHome.xcodeproj/project.pbxproj

key-decisions:
  - "Added deleteAppliedTombstone for the importer's tombstone-application delete so the grep gate holds without re-tombstoning (a fresh deletedAt would forge the LWW clock and churn every merge)"
  - "touch() applied at the real mutation site rather than the plan's assumed view file: pin/checkbox toggles live in NoteRow.swift/CalendarView.swift (not NotesListView), and survivor/expense stamping lives in AccountMerger.swift (not MergeAccountView)"
  - "Swept beyond the plan's named sites to also stamp EditBudgetSheet (budget set/clear), ReminderEditView (reminder set/remove), ReconcileView (units), and RoutineResetService (daily unchecks) — all genuine user/state-change edits"

patterns-established:
  - "Grep gate: zero bare context.delete( on @Model instances outside DeletionTracker.swift is a permanent CI-style invariant"
  - "New-record creation paths are NOT stamped (updatedAt defaults to Date() at init); the importer is NOT stamped (copies remote clock verbatim)"

requirements-completed: [SYNC-01, SYNC-02]

# Metrics
duration: 40min
completed: 2026-07-18
---

# Phase 18 Plan 04: Live Sync Write Paths (deleteSynced + touch) Summary

**Wired the sync model into live writes: every syncable delete now routes through `ModelContext.deleteSynced` (tombstone-then-delete, cascade-tombstoning Note blocks), and user edits stamp `updatedAt` via `touch()` so the Plan-03 LWW engine resolves on honest human clocks instead of migration backfill.**

## Performance

- **Duration:** ~40 min
- **Started:** 2026-07-18T15:20:00Z
- **Completed:** 2026-07-18T16:00:00Z
- **Tasks:** 2
- **Files modified:** 24 (2 created, 22 modified incl. pbxproj)

## Accomplishments
- `ModelContext.deleteSynced(_:kind:)` — inserts a `DeletionLog(entitySyncID:entityKindRaw:)` then deletes the row, in the same context; Note deletes tombstone every block with `.noteBlock` before the store cascade so a peer never resurrects orphan blocks.
- Converted all 14 live model-delete call sites (expenses ×4, notes ×3, category, accounts ×3, assets ×2, net-worth dedup, merge-absorbed, dedup victims) — the grep gate `context.delete(` on a @Model is now **0** outside DeletionTracker.swift.
- `deleteAppliedTombstone` added for the importer's tombstone-application step, keeping the engine's already-recorded deletes distinct from user deletes (no clock forging).
- `touch()` stamping at 12 user-edit files across Notes, Categories, Accounts, and Assets; new-record creation and the importer are deliberately left unstamped.
- `DeletionTrackingTests` (4 tests) green: tombstone-on-delete, note-cascade (1 note + 2 blocks = 3 tombstones), idempotent-safe double-tombstone, and end-to-end propagation (deleteSynced → exportData → mergeData removes the record on a peer that still holds it).
- Full suite **`** TEST SUCCEEDED **`** on iPhone 17 simulator.

## Task Commits

Each task was committed atomically:

1. **Task 1: DeletionTracker + convert all delete call sites + tests** - `48c236a` (feat)
2. **Task 2: Stamp updatedAt at user-edit save paths (touch())** - `e0242ee` (feat)

**Plan metadata:** committed with this SUMMARY.

_Task 1 is a tdd task; DeletionTracker + tests were authored together and verified in one green run (compile-gated Swift TDD — see Deviations)._

## Files Created/Modified
- `MyHomeApp/Sync/DeletionTracker.swift` — `deleteSynced` (tombstone-then-delete, Note cascade) + `deleteAppliedTombstone` (engine-only), with the "ALL syncable deletes MUST go through this" doc flag.
- `MyHomeTests/DeletionTrackingTests.swift` — 4 @MainActor Swift Testing tests on in-memory SchemaV10 containers.
- `MyHomeApp/Sync/SnapshotImporter.swift` — tombstone-application delete now calls `deleteAppliedTombstone`.
- 14 feature/support files — `context.delete(x)` → `context.deleteSynced(x, kind:)`.
- 12 feature/support files — `touch()` at user-edit save paths (see key-files.modified).
- `MyHomeApp/Support/AccountMerger.swift` — touch survivor + each re-pointed expense inside the merge.
- `MyHome.xcodeproj/project.pbxproj` — 4 edits each for the 2 new files (Sync group + test group).

## Decisions Made
- **`deleteAppliedTombstone` vs routing the importer through `deleteSynced`.** The importer applies a tombstone already unioned into the local log; calling `deleteSynced` there would (a) require a `SyncStamped` constraint the generic `Row` lacks, and (b) write a NEW `DeletionLog` with `deletedAt = now`, forging a fresher clock and churning every subsequent merge. A dedicated engine-only helper keeps the grep gate satisfied and the semantics honest.
- **touch() at the true mutation site.** The plan named `NotesListView` (pin/checkbox) and `MergeAccountView` (survivor/expense stamping), but in this codebase those mutations live in `NoteRow.swift` + `CalendarView.swift` and `AccountMerger.swift` respectively. Stamping was applied where the field actually changes — the plan's intent, at the correct location.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Importer's bare `context.delete(row)` would trip the Task-1 grep gate**
- **Found during:** Task 1
- **Issue:** `SnapshotImporter.applyTombstones` did a bare `context.delete(row)` (line ~292). The plan's acceptance grep counts every `context.delete(` on a @Model outside `DeletionTracker.swift` — the importer would have kept the count at 1 (non-zero), failing the gate. Routing it through `deleteSynced` was wrong (generic `Row` is not `SyncStamped`, and it would forge a fresh tombstone clock).
- **Fix:** Added `ModelContext.deleteAppliedTombstone(_:)` in `DeletionTracker.swift` (grep-excluded, documented as engine-only) and called it from the importer.
- **Files modified:** MyHomeApp/Sync/DeletionTracker.swift, MyHomeApp/Sync/SnapshotImporter.swift
- **Verification:** grep gate = 0; DeletionTrackingTests end-to-end test still deletes on the peer; full suite green.
- **Committed in:** `48c236a` (Task 1 commit)

**2. [Rule 1 - Implementation location] Plan's assumed touch() files did not host the mutation**
- **Found during:** Task 2
- **Issue:** Plan required `.touch()` in `NotesListView` (pin/checkbox toggles) and `MergeAccountView` (survivor stamping), but `NotesListView` only holds the (now `deleteSynced`) delete — the pin toggle lives in `NoteRow.swift`, agenda check toggles in `CalendarView.swift`, and the survivor/expense mutation in `AccountMerger.swift`.
- **Fix:** Applied `touch()` at those true mutation sites instead of adding dead stamps to the named view files.
- **Files modified:** MyHomeApp/Features/Notes/NoteRow.swift, MyHomeApp/Features/Notes/CalendarView.swift, MyHomeApp/Support/AccountMerger.swift
- **Verification:** full suite green; every user-edit surface named by the plan is covered behaviorally.
- **Committed in:** `e0242ee` (Task 2 commit)

---

**Total deviations:** 2 (1 blocking, 1 implementation-location). No scope creep — both preserve the plan's exact intent (zero bare deletes; honest LWW clocks at every user edit).
**Impact on plan:** Behavior fully matches the plan; only the file that hosts a given `touch()` differs from the plan's guess.

## Skipped / Ambiguous Sites (for Phase 19 re-audit)
- **EditExpenseView (`updatedAt = Date()`) and TransferPairRow (both legs `updatedAt = Date()`)** — already stamp explicitly; left as-is per plan (equivalent to `touch()`), NOT converted.
- **New-record creation** (AddExpenseView, AddNoteView, AddTransferView, SIPSetupView create paths, EditAccountView/EditAssetView new-target branch) — not stamped; `updatedAt` defaults to `Date()` at init. The shared EditAccount/EditAsset save path touches unconditionally (harmless re-stamp on new).
- **SIP / Contribution / accrual system paths** (SIPAccrualService, AMFINavService, NPSNavService, NetWorthSnapshotService recompute) — system-driven recomputes, not user edits; intentionally not stamped. Phase 19 should confirm whether NAV refreshes should carry an LWW bump.

## Issues Encountered
- Sandbox blocks `sed`/`awk`; used `grep -B/-A` and the Read tool for line inspection. No impact on output.
- Disk at ~2.4 GB free (flagged tight). The full `xcodebuild test` completed without ENOSPC this run (unlike Plan 03's environment) — `** TEST SUCCEEDED **`.
- Compile-gated Swift TDD: a test referencing `deleteSynced` cannot compile before the helper exists, so RED-as-a-failing-run is not achievable without a throwaway stub. DeletionTracker + tests were authored together and verified in a single green run; the four tests assert the specified behaviors directly.

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- SYNC-01 is live: `DeletionLog` is written by every real delete path, so "deleted stays deleted" holds on real data. Phase 19/20 code must delete syncable records ONLY through `context.deleteSynced(_:kind:)`.
- SYNC-02 inputs are truthful: user edits bump `updatedAt`; the importer and new-record paths do not forge clocks.
- Phase 19 (Multipeer/AirDrop transport) can now drive real end-to-end sync — exporter carries tombstones, importer applies them, and live edits produce honest LWW clocks. Recommend Phase 19's verification pass re-audit the ambiguous system-path stamping listed above.

---
*Phase: 18-sync-foundation-schema-merge-engine-airdrop*
*Completed: 2026-07-18*

## Self-Check: PASSED
- Both created files present on disk (DeletionTracker.swift, DeletionTrackingTests.swift); SUMMARY.md present.
- Both task commits present in git log (48c236a, e0242ee).
- Grep gate = 0 bare context.delete( on @Model outside DeletionTracker.swift; full suite ** TEST SUCCEEDED **.
