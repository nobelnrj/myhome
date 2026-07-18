---
phase: 18-sync-foundation-schema-merge-engine-airdrop
plan: 05
subsystem: sync
tags: [airdrop, uttype, uniformtypeidentifiers, sharesheet, onopenurl, fileimporter, swiftui, swiftdata]

requires:
  - phase: 18-01
    provides: SchemaV10 syncID/updatedAt + SyncSnapshot.currentSchemaVersion (version gate)
  - phase: 18-02
    provides: SnapshotCodec.decode (version refusal) + SyncMergePolicy
  - phase: 18-03
    provides: SnapshotExporter.exportData / SnapshotImporter.mergeData (transport-agnostic engine)
  - phase: 18-04
    provides: deleteSynced tombstones + touch stamping (deletions honored on merge)
provides:
  - "UTType.myHomeSnapshot (exportedAs com.reojacob.myhome.snapshot) + Info.plist UTExportedTypeDeclarations/CFBundleDocumentTypes for .myhomesnap"
  - "SnapshotFile.writeTemporary — snapshot bytes → shareable temp .myhomesnap file"
  - "Export flow: Settings → Data → Export Sync Snapshot → UIActivityViewController (AirDrop / Save to Files)"
  - "Import flow: onOpenURL(.myhomesnap) + .fileImporter → SnapshotImportSheet (decode-then-confirm → explicit Merge → MergeStats)"
affects: [phase-19-multipeer-transport, sync]

tech-stack:
  added: [UniformTypeIdentifiers (UTType exportedAs), UIActivityViewController share sheet, SwiftUI .fileImporter, SwiftUI .onOpenURL]
  patterns:
    - "Exported custom UTType (com.reojacob.myhome.snapshot / .myhomesnap) conforming to public.json — free-tier AirDrop transport, no entitlement"
    - "onOpenURL extension guard (pathExtension == myhomesnap) so OAuth callback URLs are never claimed"
    - "Decode-then-confirm import: SnapshotCodec.decode for preview WITHOUT merge; store untouched until explicit Merge tap (T-18-11)"
    - "IdentifiableURL wrapper for .sheet(item:) — avoids retroactive URL: Identifiable conformance"

key-files:
  created:
    - MyHomeApp/Sync/SnapshotFileType.swift
    - MyHomeApp/Features/Settings/SyncSnapshotViews.swift
  modified:
    - MyHomeApp/Info.plist
    - MyHomeApp/MyHomeApp.swift
    - MyHomeApp/Features/Settings/SettingsView.swift
    - MyHome.xcodeproj/project.pbxproj

key-decisions:
  - "Custom UTType declared exportedAs (owner) conforming to public.json — .myhomesnap becomes an AirDrop/Files document with no entitlement, satisfying SYNC-03 on the free tier"
  - "LSSupportsOpeningDocumentsInPlace=false so received files are copied to the app Inbox and onOpenURL fires with a readable copy"
  - "IdentifiableURL wrapper instead of retroactive URL:Identifiable to drive .sheet(item:) safely"
  - "Import reads bytes security-scoped, decodes for preview, and only calls SnapshotImporter.mergeData on an explicit Merge tap — refused/malformed files never reach the store (T-18-11/T-18-13)"

patterns-established:
  - "Pattern: exported UTType + CFBundleDocumentTypes is the device-to-device transport primitive reused by Phase 19 Multipeer"
  - "Pattern: consent-gated merge UI (decode → preview counts → Merge → MergeStats)"

requirements-completed: [SYNC-03]

duration: 10min
completed: 2026-07-18
---

# Phase 18 Plan 05: Snapshot AirDrop Transport Summary

**Device-to-device `.myhomesnap` exchange: an exported custom UTType makes AirDrop/Files carry snapshots with no entitlement, exported from Settings via the share sheet and imported through onOpenURL/.fileImporter into a decode-then-confirm merge sheet backed by the Phase-18 engine.**

## Performance

- **Duration:** 10 min (code); human UAT pending
- **Started:** 2026-07-18T10:12:54Z
- **Completed (code):** 2026-07-18T10:23:19Z
- **Tasks:** 2 of 3 (Task 3 is a blocking human-verify checkpoint — see below)
- **Files modified:** 6 (2 created, 4 modified)

## Accomplishments
- Declared the exported UTType `com.reojacob.myhome.snapshot` (`.myhomesnap`, conforms to `public.json`) plus `CFBundleDocumentTypes` so the system recognizes snapshot documents — AirDrop appears as a plain share-sheet target with zero entitlement.
- `SnapshotFile.writeTemporary` writes snapshot bytes to a sanitized `MyHome-<device>-<timestamp>.myhomesnap` temp file for sharing.
- Export row (Settings → Data) runs `SnapshotExporter.exportData` and presents `UIActivityViewController` (AirDrop / Save to Files).
- Import path via both `onOpenURL` (AirDrop accept / Files "open in") and `.fileImporter` (Files picker filtered to the custom UTType) → `SnapshotImportSheet`.
- `SnapshotImportSheet` decodes WITHOUT merging, previews source device / export time / per-entity counts, and only calls `SnapshotImporter.mergeData` on an explicit **Merge** tap; then renders `MergeStats`. Version-mismatch and malformed files get distinct user-readable messages and never touch the store.
- `onOpenURL` guard filters on the `myhomesnap` extension so Google OAuth callback URLs are untouched.

## Task Commits

1. **Task 1: UTType + Info.plist document types + onOpenURL routing** - `f106b81` (feat)
2. **Task 2: Settings export/import UI + confirm-merge sheet** - `2e8a416` (feat)
3. **Task 3: human-verify checkpoint** - PENDING (blocking manual UAT, not committable)

## Files Created/Modified
- `MyHomeApp/Sync/SnapshotFileType.swift` - `UTType.myHomeSnapshot` (exportedAs), `SnapshotFile.writeTemporary`, `IdentifiableURL` wrapper
- `MyHomeApp/Features/Settings/SyncSnapshotViews.swift` - `ActivityShareSheet` + `SnapshotImportSheet` (decode-then-confirm merge) + `SnapshotPreview`
- `MyHomeApp/Info.plist` - `UTExportedTypeDeclarations` + `CFBundleDocumentTypes` for `.myhomesnap`, `LSSupportsOpeningDocumentsInPlace=false`; OAuth `CFBundleURLTypes` byte-identical
- `MyHomeApp/MyHomeApp.swift` - `pendingImportURL` state, `onOpenURL` guard, `.sheet(item:)` → `SnapshotImportSheet`
- `MyHomeApp/Features/Settings/SettingsView.swift` - Export/Import rows + share sheet, `.fileImporter`, export error alert, `exportSnapshot()`
- `MyHome.xcodeproj/project.pbxproj` - registered both new .swift files (4 edits each)

## Decisions Made
- Exported (owner) UTType conforming to `public.json` — the free-tier AirDrop transport with no entitlement.
- `LSSupportsOpeningDocumentsInPlace=false` so received files copy to the Inbox and `onOpenURL` gets a readable copy.
- `IdentifiableURL` wrapper for `.sheet(item:)` rather than a retroactive `URL: Identifiable` conformance (avoids a future SDK collision).
- Consent-gated merge: decode for preview, store untouched until an explicit Merge tap.

## Deviations from Plan

None - plan executed exactly as written.

The plan intentionally directed registering both new files in the pbxproj during Task 1 (so Task 1's `MyHomeApp.swift` reference to `SnapshotImportSheet` resolves). `SyncSnapshotViews.swift` was therefore created before the shared build/test verification; both tasks were still committed atomically (Task 1 = file type + plist + onOpenURL + pbxproj; Task 2 = the views + Settings rows).

## Verification Results
- **Build:** `xcodebuild build -scheme MyHome -destination 'platform=iOS Simulator,name=iPhone 17'` — succeeded (only a pre-existing `SIPAccrualService` warning, out of scope).
- **Full test suite:** `xcodebuild test` — `** TEST SUCCEEDED **`, including `DarkBitIdentityTests` (dark byte-identity intact — no token/dark-branch edits).
- **PlistBuddy:** `:UTExportedTypeDeclarations:0:UTTypeIdentifier` = `com.reojacob.myhome.snapshot`; `CFBundleDocumentTypes` present; OAuth `com.googleusercontent.apps` grep = 1 (untouched).
- **onOpenURL** guard present, filters on `myhomesnap` extension.
- **Simulator self-check:** built, installed, launched with `-seedSampleData -startTab 4` — Settings renders cleanly, Data section reached (share-sheet/file-open interaction is human-only).

## Threat Notes (from plan threat_model)
- **T-18-12 (Information Disclosure, accepted):** exported `.myhomesnap` files contain the household's full financial data (incl. `rawEmailBody`) as JSON. They are user-controlled and transient (temp dir / Files). **Users should delete stray snapshot files.** At-rest encryption is deferred to Phase 19 if Multipeer persists payloads.
- T-18-11 (unsolicited import) mitigated by decode-then-confirm + explicit Merge tap.
- T-18-13 (crafted file) mitigated by `SnapshotCodec` strict decode + version refusal; store untouched on any decode failure (UI error paths).

## Issues Encountered
None.

## User Setup Required
None - no external service configuration required (AirDrop/Files/UIKit/SwiftUI are all first-party; no entitlement).

## HUMAN VERIFICATION REQUIRED (blocking — Task 3)

Task 3 is a `checkpoint:human-verify` gate that cannot be automated (share-sheet interaction, Files app, and two-phone AirDrop). The code is complete, committed, and the full suite is green. A human must confirm:

**Simulator loop (single device):**
1. Settings → Data → **Export Sync Snapshot** → share sheet appears → **Save to Files** (On My iPhone).
2. Settings → Data → **Import Snapshot…** → pick the saved file → confirm sheet shows device name, timestamp, plausible entity counts → **Merge into this phone** → stats show **0 inserted / 0 deleted** (self-merge is a no-op — idempotency visible).
3. Files app → long-press the `.myhomesnap` → Share → open in MyHome → the same confirm sheet appears via `onOpenURL`.

**Two-phone AirDrop (the real SYNC-03 criterion, when both phones available):**
4. Export on phone A → AirDrop to phone B → accept → MyHome opens the confirm sheet → Merge → B shows A's records.
5. Delete a record on B → export B → AirDrop to A → merge → the record is gone on A too (tombstone honored).

**Resume signal:** reply "approved" or describe issues (share sheet missing, file won't open into the app, wrong counts, merge stats look wrong).

## Next Phase Readiness
- SYNC-03 code path is complete and green: export via share sheet/AirDrop, receive via onOpenURL/.fileImporter, merge through the SYNC-02 engine — fully device-to-device, no cloud, consent-gated.
- **Blocker:** phase-level success criterion 3 requires the human UAT above (at minimum the simulator loop; ideally the two-phone AirDrop) before the phase is demonstrably complete.
- Phase 19 (Multipeer transport) reuses this exact UTType + SnapshotCodec bytes on the wire.

## Self-Check: PASSED
- `MyHomeApp/Sync/SnapshotFileType.swift` — FOUND
- `MyHomeApp/Features/Settings/SyncSnapshotViews.swift` — FOUND
- Commit `f106b81` — FOUND
- Commit `2e8a416` — FOUND

---
*Phase: 18-sync-foundation-schema-merge-engine-airdrop*
*Completed (code): 2026-07-18*
