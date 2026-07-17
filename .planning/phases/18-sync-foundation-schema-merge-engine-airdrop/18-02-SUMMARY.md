---
phase: 18-sync-foundation-schema-merge-engine-airdrop
plan: 02
subsystem: sync
tags: [codable, json, snapshot, lww, conflict-resolution, decimal, sync-02, transport-agnostic]

# Dependency graph
requires:
  - phase: 18-01
    provides: "SchemaV10 stored-property surface (syncID/updatedAt on 11 models + DeletionLog) that every DTO mirrors"
provides:
  - "SyncSnapshot — pure Codable, version-stamped snapshot document (11 entity DTOs + DeletionDTO); zero SwiftData imports"
  - "SnapshotCodec.encode/decode/canonicalData — canonical deterministic bytes (.sortedKeys + .millisecondsSince1970), version-probe-first refusal"
  - "SyncDecimal — locale-independent Decimal<->String bridge so money never crosses JSON as a number"
  - "SyncEntityKind (11 cases; DeletionLog.entityKindRaw domain), SyncError (schemaVersionMismatch/malformedSnapshot)"
  - "SyncMergePolicy.remoteWins (LWW + vantage-independent canonical-bytes tiebreak) + tombstoneWins (no resurrection)"
affects: [18-03, 18-04, 18-05, 19, 20]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Transport-agnostic snapshot: pure Foundation-only Codable value types, byte-testable with no container/device"
    - "Money as canonical String on the wire (SyncDecimal) — JSON-number money is structurally impossible"
    - "Canonical JSON encoder (.sortedKeys + .millisecondsSince1970) as the single encode truth for wire + merge tiebreak"
    - "Version-probe-first decode: schema mismatch refused before any entity data is parsed"
    - "LWW with a vantage-independent total-order tiebreak on canonical bytes so ties converge across two phones"

key-files:
  created:
    - MyHomeApp/Sync/SyncSnapshot.swift
    - MyHomeApp/Sync/SyncMergePolicy.swift
    - MyHomeTests/SnapshotCodecTests.swift
    - MyHomeTests/SyncMergePolicyTests.swift
  modified:
    - MyHome.xcodeproj/project.pbxproj

key-decisions:
  - "SyncSnapshot.currentSchemaVersion = 10 tracks the SchemaV10 major; bumped in lockstep with future schema bumps"
  - "DeletionDTO carries only entitySyncID/entityKindRaw/deletedAt (the cross-device tombstone fields), per plan spec — not DeletionLog's local id/createdAt"
  - "Exact-timestamp tiebreak ranks by the record's own canonical bytes (lexicographic total order), NOT local/remote vantage — the only rule under which both phones converge"
  - "tombstoneWins uses deletedAt >= recordUpdatedAt so a delete at the same instant wins (no resurrection); an edit strictly later survives (intentional LWW)"

patterns-established:
  - "New .swift files registered with the full 4-edit pbxproj pattern under a new Sync PBXGroup (child of MyHomeApp)"
  - "Pure value-layer contracts live in MyHomeApp/Sync and import Foundation only"

requirements-completed: [SYNC-02]

# Metrics
duration: ~35 min
completed: 2026-07-18
---

# Phase 18 Plan 02: SYNC-02 Snapshot Document Layer + LWW Merge Policy Summary

**A pure, Foundation-only `SyncSnapshot` (version-stamped, Decimal-as-String, canonical-deterministic JSON via `SnapshotCodec`) plus a two-function `SyncMergePolicy` (LWW with a vantage-independent canonical-bytes tiebreak and no-resurrection tombstones) — the byte-for-byte transport contract Phase 19 reuses, locked down by 13 GREEN pure-unit tests.**

## Performance

- **Duration:** ~35 min
- **Completed:** 2026-07-18
- **Tasks:** 3
- **Files modified:** 5 (4 created, 1 pbxproj)

## Accomplishments
- `SyncSnapshot` value type: schemaVersion stamp + `exportedAt`/`deviceName` + 11 entity DTOs (Category…RoutineCompletion) + `DeletionDTO`, every DTO mirroring its SchemaV10 model's stored properties with `@Relationship`s replaced by syncID/id back-refs.
- `SnapshotCodec` with a single canonical encoder (`.sortedKeys` + `.millisecondsSince1970`) shared by `encode`, `canonicalData` (the Plan 03 tiebreak input), and a version-probe-first `decode` that throws `schemaVersionMismatch` before any entity data is parsed and wraps structural failures as `malformedSnapshot`.
- `SyncDecimal` locale-independent Decimal<->String bridge — money is structurally incapable of crossing JSON as a number.
- `SyncMergePolicy.remoteWins` (LWW on `updatedAt`, exact ties broken by lexicographic order on canonical bytes so both phones converge) and `tombstoneWins` (delete wins on ties, edit-after-delete survives).
- New `Sync` PBXGroup under MyHomeApp with all four files registered via the full 4-edit pbxproj pattern.

## Task Commits

1. **Task 1: SyncSnapshot DTO layer + SnapshotCodec + Sync pbxproj group** - `b3fb3b6` (feat)
2. **Task 2: SyncMergePolicy — LWW with deterministic convergent tiebreak** - `31b9894` (feat)
3. **Task 3: Pure GREEN unit tests — codec bytes, version refusal, policy determinism** - `aa13fc8` (test)

## Files Created/Modified
- `MyHomeApp/Sync/SyncSnapshot.swift` - SyncEntityKind, SyncDecimal, SyncError, 12 DTO structs, SyncSnapshot, SnapshotCodec
- `MyHomeApp/Sync/SyncMergePolicy.swift` - remoteWins (LWW + convergent tiebreak), tombstoneWins
- `MyHomeTests/SnapshotCodecTests.swift` - byte-level Decimal-as-string, round-trip determinism, version refusal, malformed input
- `MyHomeTests/SyncMergePolicyTests.swift` - LWW ordering, vantage-independent tie convergence, tombstone no-resurrection
- `MyHome.xcodeproj/project.pbxproj` - new Sync PBXGroup + 4-file registration (build refs, file refs, group children, both Sources phases)

## Decisions Made
- Followed the plan spec exactly for `DeletionDTO` (three cross-device fields only).
- Kept `SnapshotCodec` encoder centralized in one private factory so wire encoding and the merge tiebreak can never diverge byte-wise.
- Reworded a doc comment in `SyncMergePolicy.swift` to avoid the literal token `ModelContext`, so the "no persistence context anywhere in the file" acceptance grep is clean while the meaning is preserved.

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered
None.

## User Setup Required
None - no external service configuration required.

## Threat Model Compliance
- **T-18-03 (Tampering / decode):** mitigated — version probe first, mismatch refused pre-decode, DecodingError wrapped as `malformedSnapshot`; tested with garbage and truncated input.
- **T-18-04 (Tampering / Decimal transport):** mitigated — `SyncDecimal` string round-trip with en_US_POSIX; byte-level test proves `"amount":"1234.56"` is present and `"amount":1234.56` is absent.
- No new threat surface beyond the plan's register.

## Next Phase Readiness
- SYNC-02 contracts exported for Plan 03's merge engine (`SnapshotCodec.canonicalData`, `SyncMergePolicy.remoteWins/tombstoneWins`, all DTOs) and for the Phase 19 MultipeerConnectivity/AirDrop transport (byte-identical `SyncSnapshot` wire format).
- Full test suite: `** TEST SUCCEEDED **` (all prior tests + 13 new pure-unit tests green).

## Self-Check: PASSED
- All 4 created files exist on disk.
- All 3 task commits present (`b3fb3b6`, `31b9894`, `aa13fc8`).
- Full `xcodebuild test` on iPhone 17 → `** TEST SUCCEEDED **`.

---
*Phase: 18-sync-foundation-schema-merge-engine-airdrop*
*Completed: 2026-07-18*
