---
phase: 18-sync-foundation-schema-merge-engine-airdrop
verified: 2026-07-18T10:35:18Z
status: passed
score: 5/5 must-haves verified
overrides_applied: 0
---

# Phase 18: Sync Foundation — Schema, Merge Engine & AirDrop Verification Report

**Phase Goal:** Two phones can exchange a full data snapshot device-to-device and merge it losslessly through a tested, transport-agnostic engine.
**Verified:** 2026-07-18T10:35:18Z
**Status:** passed
**Re-verification:** No — initial verification

**Note on test execution:** disk was ~289Mi free at verification time. Per explicit instruction, `xcodebuild test` was NOT re-run to avoid an ENOSPC loop; the full-suite green result (643+ tests, most recent run) is taken as given context. This report is a static goal-backward code review: every claimed invariant below is confirmed by reading the actual implementation and its unit tests, not by trusting SUMMARY.md prose. Where a claim could only be confirmed by running the app on real devices, human UAT (already approved by the user for 18-05 Task 3) is treated as sufficient evidence.

## Goal Achievement

### Observable Truths (Roadmap Success Criteria)

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | Every syncable record carries a stable `syncID` + `updatedAt` that survive an export→import round-trip; re-importing the same snapshot creates no duplicates | ✓ VERIFIED | `SyncStamped.swift` conforms all 11 SchemaV10 models (Expense, Category, Note, NoteBlock, Account, Asset, NetWorthSnapshot, SIP, SIPAmountChange, Contribution, RoutineCompletion). `SnapshotImporter.upsert` fetches-then-indexes by `syncID` before insert. `SnapshotRoundTripTests.reImportIsIdempotent` merges the same snapshot twice and asserts `inserted == 0`, row counts unchanged. |
| 2 | A record deleted on one phone stays deleted when the other phone's older snapshot arrives (tombstones/DeletionLog honored, no resurrection) | ✓ VERIFIED | `DeletionLog` model (SchemaV10) + `SyncMergePolicy.tombstoneWins(deletedAt:recordUpdatedAt:)` (deletedAt ≥ recordUpdatedAt wins). `SnapshotImporter.merge` applies tombstones (step 2) BEFORE any upsert (step 4), and `upsert` re-checks the tombstone per-DTO to block resurrection. `SnapshotImporterTests."No resurrection..."` and `DeletionTrackingTests."...flows through export→merge and removes the record on a peer"` assert this directly. |
| 3 | A snapshot exported on phone A and sent via share sheet/AirDrop opens on phone B and merges its data in — fully device-to-device, no cloud/third party | ✓ VERIFIED (code) + ✓ VERIFIED (human UAT, per task instructions) | `.myhomesnap` UTType declared exported (owner) in `Info.plist`, conforming to `public.json` — no entitlement required. Export: `SettingsView` → `SnapshotExporter.exportData` → temp file → `UIActivityViewController` (AirDrop is a share-sheet target). Import: `MyHomeApp.onOpenURL` (AirDrop accept/Files "open in") AND `.fileImporter` (Files picker) both route to `SnapshotImportSheet`, which decodes-then-previews-then-merges only on explicit "Merge" tap. Human two-phone AirDrop UAT (18-05 Task 3) already approved by the user per task instructions — not re-run here. |
| 4 | Export→import→export is idempotent (golden round-trip test passes) and all Decimal values survive as strings (never JSON-Double) | ✓ VERIFIED | `SyncDecimal.string(from:)`/`decimal(from:)` bridge every money field to/from `String` (locale-independent, POSIX). Every DTO (`CategoryDTO.monthlyBudget`, `ExpenseDTO.amount`, `AccountDTO.balanceBaseline`, `AssetDTO.units/costBasisPerUnit/currentNAV`, `NetWorthSnapshotDTO.*Value`, `SIPDTO.amount`, etc.) types money as `String`/`String?`, never a numeric JSON type. `SnapshotRoundTripTests.goldenRoundTrip` asserts `snapA == snapB` after export→import→export; `SnapshotCodecTests` separately assert "Decimal money encodes as a JSON string, never a JSON number" and "encode → decode → encode is byte-identical". |
| 5 | A snapshot stamped with a mismatched schema version is refused rather than corrupting the store | ✓ VERIFIED | `SnapshotCodec.decode` probes only `schemaVersion` first and throws `SyncError.schemaVersionMismatch` BEFORE decoding any entity data if it doesn't match `SyncSnapshot.currentSchemaVersion` (10). `SnapshotCodecTests."decode refuses a schemaVersion-9 snapshot before decoding entities"` and `SnapshotImporterTests."Version refusal: a schema-9 payload throws and leaves local counts untouched"` both assert this. |

**Score:** 5/5 truths verified

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `MyHomeApp/Persistence/Schema/SchemaV10.swift` | syncID+updatedAt on all 11 models + DeletionLog | ✓ VERIFIED | All 11 models declare `syncID: UUID` + `updatedAt: Date` (Expense's updatedAt predates this phase, reused); DeletionLog model present with `entitySyncID`/`entityKindRaw`/`deletedAt`. |
| `MyHomeApp/Persistence/Models/SyncStamped.swift` | Protocol + touch() + conformances | ✓ VERIFIED | Protocol with `touch()` default impl; empty conformance extensions for all 11 models. |
| `MyHomeApp/Sync/DeletionTracker.swift` | `deleteSynced` choke point | ✓ VERIFIED | `ModelContext.deleteSynced<T: PersistentModel & SyncStamped>` writes a `DeletionLog` then deletes; Note special-cases cascade-deleted blocks. |
| `MyHomeApp/Sync/SyncSnapshot.swift` | DTOs, SyncDecimal, SnapshotCodec, version gate | ✓ VERIFIED | Pure Foundation-only file; canonical `.sortedKeys` + `.millisecondsSince1970` encoder; version probe decoded first. |
| `MyHomeApp/Sync/SyncMergePolicy.swift` | Pure LWW + tombstone policy | ✓ VERIFIED | Two pure functions: `remoteWins` (LWW + byte-tiebreak) and `tombstoneWins`. |
| `MyHomeApp/Sync/SnapshotExporter.swift` | Full-store export | ✓ VERIFIED (exists, registered in pbxproj, used by tests + SettingsView) | |
| `MyHomeApp/Sync/SnapshotImporter.swift` | Merge engine | ✓ VERIFIED | fetch-then-upsert, tombstone-before-upsert, identity adoption, two-pass wiring, single atomic `save()`. |
| `MyHomeApp/Sync/SnapshotFileType.swift` | `.myhomesnap` UTType + temp-file writer | ✓ VERIFIED | `UTType(exportedAs: "com.reojacob.myhome.snapshot")`, matches `Info.plist`. |
| `MyHomeApp/Features/Settings/SyncSnapshotViews.swift` | Confirm-merge sheet | ✓ VERIFIED | `SnapshotImportSheet`: loading → preview → merge-on-tap → result phases; never mutates the store before explicit "Merge". |
| `MyHomeApp/MyHomeApp.swift` | `onOpenURL` routing | ✓ VERIFIED | Filters on `.myhomesnap` extension, sets `pendingImportURL`, presents `SnapshotImportSheet`. |
| `MyHomeApp/Info.plist` | UTExportedTypeDeclarations + CFBundleDocumentTypes | ✓ VERIFIED | Declared, conforming to `public.json`, extension `myhomesnap`. |

### Key Link Verification

| From | To | Via | Status | Details |
|------|-----|-----|--------|---------|
| Delete UI call sites (Expense/Note/Account/Asset/Category/NetWorthSnapshot) | `DeletionLog` | `context.deleteSynced(...)` | ✓ WIRED | Grep across `MyHomeApp/Features/**` finds every delete call site (`AccountsListView`, `EditExpenseView`, `ExpenseListView`, `ReviewInboxRow`, `NotesListView`, `EditNoteView`, `ManageCategoriesView`, `AssetsListView`, `EditAssetView`, `MergeAccountView`, `MigrationReviewSheet`, `NetWorthSnapshotService`, `DuplicateExpenseCleanup`) using `deleteSynced`, none using a bare `context.delete()` on a syncable model. |
| Edit UI call sites | `updatedAt` | `.touch()` | ✓ WIRED | 25 call sites across Settings/Notes/Budgets/Assets edit flows. |
| `SnapshotExporter` | `SyncSnapshot` | `makeSnapshot(context:deviceName:)` | ✓ WIRED | Used by `SettingsView` export flow and by all round-trip/importer tests. |
| `SnapshotImporter.merge` | Store | fetch-then-upsert, single `context.save()` | ✓ WIRED | Atomic: any thrown error aborts before save. |
| `SettingsView` | `SnapshotImportSheet` | `.fileImporter` + `.sheet(item:)` | ✓ WIRED | Files-picker import path present. |
| `MyHomeApp.onOpenURL` | `SnapshotImportSheet` | `pendingImportURL` + `.sheet(item:)` | ✓ WIRED | AirDrop-accept/Files-"open in" path present, gated by extension so OAuth callback URLs pass through untouched. |
| All Sync source + test files | Xcode build target | `project.pbxproj` explicit refs | ✓ WIRED | Confirmed 3 pbxproj references (PBXBuildFile/PBXFileReference/group) for every new Sync file and every new test file — the known "explicit file refs" footgun does not apply here; files will actually compile. |

### Data-Flow Trace (Level 4)

Not applicable in the traditional sense (no rendered dynamic-data component in this phase besides the confirm-merge sheet, which is exercised by the human UAT). The merge engine's "data flow" is proven directly by unit tests operating on real in-memory SwiftData containers seeded with one row of every syncable entity (`SyncTestSupport.seedFullStore`) — not stubbed/mocked data.

### Behavioral Spot-Checks

Skipped — build/test execution intentionally not re-run due to ~289Mi free disk (explicit instruction to avoid an ENOSPC loop). Static code review (above) is the evidence basis; the previously-reported full-suite green run (643+ tests) is accepted as given context per task instructions.

### Probe Execution

No `scripts/*/tests/probe-*.sh` found for this phase — not applicable.

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|--------------|-------------|--------------|--------|----------|
| SYNC-01 | 18-01, 18-04 | syncID/updatedAt/DeletionLog/deleteSynced/touch() | ✓ SATISFIED | See truths 1–2 and artifacts above. |
| SYNC-02 | 18-02, 18-03 | Merge engine: fetch-then-upsert, LWW, tombstone-before-upsert, two-pass wiring, Decimal-as-string, schema-version gate, golden round-trip | ✓ SATISFIED | See truths 1, 2, 4, 5 and `SnapshotImporter`/`SyncMergePolicy`/`SnapshotCodec`. |
| SYNC-03 | 18-05 | .myhomesnap export/import via share sheet + onOpenURL + fileImporter + confirm-merge sheet | ✓ SATISFIED | See truth 3 and artifacts. Human AirDrop UAT already approved per task instructions. |

No orphaned requirements found for Phase 18 in REQUIREMENTS.md.

### Anti-Patterns Found

None. Scanned all new/modified Sync files (`SyncStamped.swift`, `DeletionLog.swift`, `DeletionTracker.swift`, `SyncSnapshot.swift`, `SnapshotExporter.swift`, `SnapshotImporter.swift`, `SyncMergePolicy.swift`, `SnapshotFileType.swift`, `SyncSnapshotViews.swift`) for `TODO|FIXME|XXX|TBD|placeholder|not implemented` — zero matches.

### Human Verification Required

None outstanding. The one human-verify checkpoint this phase produced — two-phone AirDrop export/import/merge (18-05 Task 3) — has already been tested and approved by the user per the task instructions; it is recorded here as evidence, not re-requested.

### Gaps Summary

No gaps found. All 5 roadmap success criteria are backed by both a concrete code path and a targeted unit test (or, for the AirDrop transport itself, approved human UAT). Deletion, LWW, tombstone-before-upsert ordering, two-pass relationship wiring, Decimal-as-string, and the schema-version refusal gate are each independently exercised by the test suite using real in-memory SwiftData containers, not mocks. Every new source and test file is confirmed present in `project.pbxproj` (the codebase's known "silently doesn't compile" footgun), so there is no orphaned/unbuilt code risk. Debt-marker scan is clean.

---

_Verified: 2026-07-18T10:35:18Z_
_Verifier: Claude (gsd-verifier)_
