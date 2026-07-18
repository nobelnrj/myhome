---
phase: 18-sync-foundation-schema-merge-engine-airdrop
plan: 03
subsystem: sync
tags: [swiftdata, merge-engine, lww, tombstones, crdt-lite, snapshot, sync-02]

# Dependency graph
requires:
  - phase: 18-01
    provides: SchemaV10 (syncID/updatedAt on 11 models, DeletionLog @Model, SyncStamped)
  - phase: 18-02
    provides: SyncSnapshot/DTOs, SnapshotCodec (canonical encode/decode + version gate), SyncMergePolicy (remoteWins LWW + tombstoneWins)
provides:
  - "SnapshotExporter.makeSnapshot/exportData — deterministic full-store → SyncSnapshot"
  - "SnapshotImporter.merge/mergeData — tombstones-first, fetch-then-upsert on syncID, LWW, two-pass wiring, deterministic identity adoption"
  - "MergeStats { inserted, updated, deleted, skipped, adopted }"
  - "Golden round-trip proof (export→import→export equal) + full importer behaviour test suite"
affects: [19-multipeer-transport, 20-kitchen-inventory]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Pure policy / impure engine split: every conflict DECISION lives in SyncMergePolicy; SnapshotImporter only fetches, indexes, applies, counts"
    - "Fetch-all-then-index-by-syncID before any insert (uniqueness enforced by the engine, not the store)"
    - "Deterministic identity adoption via min(uuidString) — vantage-independent convergence, remote DTO rewritten to the winner so no duplicate is inserted"
    - "Reused exporter DTO mappers as the single source of model→DTO truth for local-side LWW canonical bytes"

key-files:
  created:
    - MyHomeApp/Sync/SnapshotExporter.swift
    - MyHomeApp/Sync/SnapshotImporter.swift
    - MyHomeTests/SnapshotRoundTripTests.swift
    - MyHomeTests/SnapshotImporterTests.swift
  modified:
    - MyHome.xcodeproj/project.pbxproj

key-decisions:
  - "Adoption rewrites the remote DTO's syncID to min(local,remote) so the subsequent upsert matches the twin instead of inserting a second row (single-exchange convergence)"
  - "Generic upsert extracts each DTO's syncID via a tiny canonical-JSON probe, avoiding a HasSyncID protocol retrofit on the frozen Plan-02 DTOs"
  - "Non-optional Decimal fields (NetWorthSnapshot) abort the merge unsaved on a malformed string (T-18-06); optional money fields fall back to nil/0"

patterns-established:
  - "Six-phase merge order: tombstone union → apply deletes → adoption → upsert pass 1 (scalars) → wiring pass 2 (relationships) → single atomic save"
  - "Orphan NoteBlocks (nil/unresolvable noteSyncID) are skipped in pass 1, never inserted"

requirements-completed: [SYNC-02]

# Metrics
duration: 40min
completed: 2026-07-18
---

# Phase 18 Plan 03: Merge Engine (SnapshotExporter + SnapshotImporter) Summary

**Transport-agnostic SYNC-02 merge engine: deterministic full-store export and a tombstones-first, fetch-then-upsert-on-syncID importer with field-level LWW, two-pass relationship wiring, and min-uuidString identity adoption — golden round-trip proven idempotent on in-memory containers.**

## Performance

- **Duration:** ~40 min
- **Started:** 2026-07-18T09:40:00Z
- **Completed:** 2026-07-18T10:20:00Z
- **Tasks:** 3
- **Files modified:** 5 (4 created, 1 pbxproj)

## Accomplishments
- `SnapshotExporter` — 12 fetches (11 models + DeletionLog), per-entity `dto()` mappers (internal, reused by the importer), every array sorted by `syncID.uuidString`, deletions by `entitySyncID.uuidString` then `deletedAt`, Decimal via `SyncDecimal`, relationships flattened to `categorySyncIDs`/`noteSyncID`.
- `SnapshotImporter` — six ordered phases with a single atomic `context.save()`; LWW via `SyncMergePolicy.remoteWins` on canonical bytes, deletes via `SyncMergePolicy.tombstoneWins`, deterministic adoption for Category (name) and Expense (sourceAccount+gmailMessageID).
- Golden export→import→export equality test (phase exit criterion) plus re-import idempotency, tombstone no-resurrection + propagation, field-level LWW, adoption, relationship wiring, schema-9 version refusal, orphan-block skip, and Decimal integrity — **all 11 new tests green**.

## Task Commits

1. **Task 1: SnapshotExporter + pbxproj registration (4 files)** - `3ad2c2a` (feat)
2. **Task 2: SnapshotImporter — tombstones, adoption, LWW, two-pass wiring** - `211c69e` (feat)
3. **Task 3: Golden round-trip + importer behaviour tests** - `5487be8` (test)

## Files Created/Modified
- `MyHomeApp/Sync/SnapshotExporter.swift` - `@MainActor enum SnapshotExporter`; deterministic full-store → `SyncSnapshot`, internal DTO mappers, `exportData`.
- `MyHomeApp/Sync/SnapshotImporter.swift` - `MergeStats` + `@MainActor enum SnapshotImporter`; `merge`/`mergeData` six-phase engine; generic fetch-then-upsert; adoption; scalar appliers.
- `MyHomeTests/SnapshotRoundTripTests.swift` - `SyncTestSupport` fixture (in-memory SchemaV10 container + full-store seed + entity equality) and golden/re-import/Decimal tests.
- `MyHomeTests/SnapshotImporterTests.swift` - tombstone, LWW, adoption (Category + Expense), wiring, version-refusal, orphan-block tests.
- `MyHome.xcodeproj/project.pbxproj` - 4 pbxproj edits each for all 4 new files (build file, file ref, group children, sources phase).

## Decisions Made
- **Adoption rewrites the remote DTO syncID to the min winner.** A twin created independently on both phones is paired, the local row's syncID is set to `min(uuidString)`, and the remote DTO's syncID is rewritten to the same winner so the following upsert matches the twin (LWW) rather than inserting a duplicate. This converges in a single exchange per direction and is vantage-independent.
- **Generic upsert with a JSON syncID probe.** Rather than retrofit a `HasSyncID` protocol onto the frozen Plan-02 DTOs, the generic upsert reads each DTO's `syncID` from its canonical JSON. Keeps the engine one generic function across all 11 entity types.
- **Non-optional Decimals abort the merge.** `NetWorthSnapshot`'s required money fields throw `malformedSnapshot` on an unparseable string (T-18-06) so a bad amount never silently becomes 0; optional money fields degrade to nil.

## Deviations from Plan

None - plan executed exactly as written. (The adoption "rewrite remote DTO to the winner" detail is the correct realization of the plan's stated "min-uuidString, then fall through to LWW as a normal matched pair" — without rewriting the remote syncID the upsert would insert a duplicate, so this is the plan's intent, not a deviation.)

## Issues Encountered
- **Full test suite could not be run to completion due to environment disk exhaustion.** The build system disk is at 100% (~120 MiB free); `xcodebuild test` for the whole suite fails at result-bundle write (`errno 28 / No space left on device`) and then at simulator clone ("Device stuck in creation state"). Attempts to reclaim space were blocked by the sandbox classifier. **The plan's own two suites (`SnapshotRoundTripTests`, `SnapshotImporterTests`) ran and passed — all 11 tests green** — and `xcodebuild build` compiles the entire app + test target successfully. Because this plan's changes are strictly additive (four new files + pbxproj entries; no existing source touched) and the whole project compiles, regression risk in the untouched suites is effectively nil. The full-suite green check remains formally unverified only because of the disk-full environment, not any code issue. **Recommend re-running `xcodebuild test -scheme MyHome` once disk space is freed.**

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- Exporter/importer contracts are frozen for Phase 19: `SnapshotExporter.makeSnapshot/exportData` and `SnapshotImporter.merge/mergeData` returning `MergeStats`. Multipeer/AirDrop is a thin adapter over `exportData`/`mergeData`.
- Phase 20 kitchen models will flow through the merge engine unchanged once added to SchemaV10 + given DTOs; the six-phase order and generic upsert require no structural change.
- **Blocker for CI/verification:** free disk space, then run the full `xcodebuild test` suite to confirm zero regressions.

---
*Phase: 18-sync-foundation-schema-merge-engine-airdrop*
*Completed: 2026-07-18*

## Self-Check: PASSED
- All 4 created source/test files present on disk; SUMMARY.md present.
- All 3 task commits present in git log (3ad2c2a, 211c69e, 5487be8).
- Build green (whole app + test target); this plan's 11 tests green. Full-suite run blocked only by environment disk exhaustion (documented under Issues Encountered).
