---
phase: 20-kitchen-inventory-shopping-list
verified: 2026-07-21T00:00:00Z
status: human_needed
score: 8/8 must-haves verified (code-level); 1 end-of-phase human gate outstanding
overrides_applied: 0
human_verification:
  - test: "Home tab → Kitchen card → pantry opens. Add 'Milk' qty 3 L, low-stock threshold 2, restock qty 3. Tap − twice (LOW), tap − again (OUT)."
    expected: "Row flips to LOW badge at qty 1, OUT badge at qty 0; − stepper disabled/recessed at 0."
    why_human: "Visual badge rendering and stepper disabled-state feel — not verifiable by grep."
  - test: "Shopping segment: Milk auto-appears under RESTOCK with a '↻ + 3 L' pill."
    expected: "Derived row shown, correct restock-amount pill text."
    why_human: "Live render of a computed/derived list in the actual UI."
  - test: "Add manual extra 'Sponges' → appears under EXTRAS; check off → struck through; Clear checked removes it."
    expected: "Manual row lifecycle behaves as designed."
    why_human: "UI interaction sequence."
  - test: "Check Milk off in RESTOCK → back on Pantry, Milk reads 3 and flag is gone."
    expected: "Check-off restocks the pantry item directly (derived row IS the pantry item)."
    why_human: "Cross-screen state consistency, visual confirmation."
  - test: "Toggle light/dark — kitchen matches v1.2 neumorphic system in light and neon treatment in dark."
    expected: "Visual parity with the rest of the app's design system."
    why_human: "Visual/aesthetic judgment."
  - test: "Two-phone sync: Settings → Data → Export Sync Snapshot → AirDrop to other phone (both on Phase-20 build) → Merge → other phone shows same pantry/shopping state. Delete a pantry row on B, export B, merge on A → stays deleted on A."
    expected: "Real device-to-device merge converges; deletions propagate as tombstones."
    why_human: "Requires two physical devices and a real AirDrop/share-sheet interaction; simctl cannot drive this (explicitly noted as not automatable in 20-05-SUMMARY.md)."
  - test: "(Optional) A phone still on the previous (v10) build importing a v11 snapshot shows the incompatible-version message and changes nothing."
    expected: "schemaVersionMismatch surfaced cleanly, store untouched."
    why_human: "Requires a second device pinned to an older build."
  - test: "Design accept/reject: on the pantry screen, 'Atta'/'Sona Masoori rice' show a purple box tile and 'Filter coffee' an orange-red cup tile, versus the mockup's warm amber/brown. Reply 'palette ok' or 'warm grains'."
    expected: "User explicitly accepts or requests a retune of KitchenLogic.icon's keyword→token mapping."
    why_human: "Subjective visual-fidelity decision the executor explicitly deferred, per 20-05-SUMMARY.md carried-observation 2."
---

# Phase 20: Kitchen Inventory & Shopping List Verification Report

**Phase Goal:** The household can track pantry stock and shop from an auto-populated list, on a first-class neumorphic surface whose data syncs between phones.
**Verified:** 2026-07-21
**Status:** human_needed
**Re-verification:** No — initial verification

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | User can add/edit pantry items with quantity/unit and mark used (decrement) or restocked (increment) — KTCH-01 | ✓ VERIFIED | `PantryItem` (SchemaV11.swift) has `quantity: Double`, `unit: String?`, `restockQuantity`; `KitchenLogic.markUsed`/`markRestocked` (`MyHomeApp/Features/Kitchen/KitchenLogic.swift:46-61`) mutate and `touch()`; `EditPantryItemView.swift` provides add/edit UI; `KitchenLogicTests.markUsedDecrements/markUsedClampsAtZero/markRestockedAdds` pass (independently re-run, all green). |
| 2 | Items at/below per-item low-stock threshold visually flagged low/out — KTCH-02 | ✓ VERIFIED | `KitchenLogic.stockStatus(quantity:threshold:)` (`KitchenLogic.swift:33-37`): `quantity <= 0 → .out`, `quantity <= threshold → .low`. `KitchenLogicTests.zeroIsAlwaysOut/atThresholdIsLow/aboveThresholdIsInStock` pass. `PantryItemRow.swift` renders `LOW`/`OUT` badges from this single source of truth. |
| 3 | Low/out items auto-populate a shopping list; check-off restocks pantry; manual items supported — KTCH-03 | ✓ VERIFIED | `KitchenLogic.deriveShoppingItems` is a pure function over pantry rows, **never inserts a `ShoppingListItem`** for derived rows (`KitchenLogic.swift:74-83`); only `ShoppingListView.addItem()` inserts `ShoppingListItem` for manual "Add item…" entries (`ShoppingListView.swift:222-230`). `ShoppingListTests.derivationNeverMaterialisesRows` explicitly asserts `ShoppingListItem` row count stays 0 through derive + restock (re-run independently, PASSED). Check-off on a derived row calls `markRestocked` on the underlying `PantryItem` directly (row IS the pantry item — no separate persisted state to reconcile). |
| 4 | Kitchen matches v1.2 neumorphic system, syncs via SYNC engine — KTCH-04 | ✓ VERIFIED | Both kitchen models are `SyncStamped` from birth (`SyncStamped.swift:60-61`); `SyncEntityKind.pantryItem`/`.shoppingListItem` exist; **`SyncScope.production` includes `.pantryItem, .shoppingListItem`** (`SyncSnapshot.swift:75-77`) — the DTO-without-scope footgun called out in the verification brief was checked and is NOT present: kitchen is genuinely inside the production sync scope, not merely DTO-defined. `KitchenSyncTests` (kitchenRoundTrip, pantryAdoptionConverges, shoppingAdoptionConverges, deletedPantryItemNeverResurrects, deletedShoppingRowNeverResurrects, v10PayloadRefused, newerRemoteQuantityWins, olderRemoteQuantityLoses, selfMergeOfOwnExportIsNoOp, checkedStateSyncs, reImportIsIdempotent) — all 10 re-run independently, all PASSED. |
| 5 | Financial data never leaves the device (privacy invariant) — critical, cross-cutting | ✓ VERIFIED | `SyncScope.production` excludes expense/category/account/asset/netWorthSnapshot/sip/sipAmountChange/contribution. **Export-side**: `SnapshotExporter.makeSnapshot` never fetches an excluded kind (`SnapshotExporter.swift:265-281` — `guard scope.isSynced(kind) else { return [] }` wraps every fetch). **Import-side**: `SnapshotImporter.merge` re-applies `rawSnapshot.scoped(to: scope)` before touching the store (`SnapshotImporter.swift:50-55`), so a tampered/stale peer sending `.all` cannot push money data in. Tests genuinely assert this, not just by name: `productionExportExcludesAllMoney` checks 8 financial arrays `.isEmpty` while kitchen/notes are non-empty; `exportedBytesContainNoMoney` grep-checks the raw JSON bytes for seeded money strings ("1234.56", "HDFC", "50000", etc.) — a materially stronger check than array-level assertions; `importRefusesOutOfScopeRows` builds a **hostile full-scope (`.all`) export containing real expenses** and proves the production-scope importer drops them; `importRefusesOutOfScopeTombstones` proves an out-of-scope deletion cannot delete a local financial row. All 5 tests re-run independently — PASSED. |
| 6 | No SchemaV10 typealias/production-tracking container regression (STAB-08) | ✓ VERIFIED | `grep -rE '^typealias [A-Za-z]+ = SchemaV10\.'` under `Persistence/Models/` → 0 matches; 14 typealiases point at `SchemaV11`; `SyncStamped.swift` has exactly 13 `SchemaV11.X: SyncStamped` conformances, 0 remaining at V10. Production container: `ModelContainer+App.swift` → `Schema(versionedSchema: SchemaV11.self)`. Test-side production-tracking containers (`SyncTestSupport.makeStore`/`SnapshotRoundTripTests`, `SIPAccrualServiceTests`, `NoteModelTests`) independently confirmed on `SchemaV11.self`. Remaining `SchemaV10` references in the codebase are (a) intentional seed containers pinned to old schemas for migration fixtures (`SchemaV6/7/8/9/10MigrationTests`, `MigrationTests`) and (b) historical doc-comment trails on typealias files recording the version-flip lineage — neither is a defect. |
| 7 | UI reference contract honored (20-UI-REFERENCE.md) | ✓ VERIFIED (with 1 disclosed, user-facing deviation) | Segmented `Pantry \| Shopping` control, RUNNING LOW/STOCKED sections, badge styling, icon tiles, restock pills, derived-list footnote, edit sheet layout, "Restock by" relabeling (per the binding decision reversing "Restock to") — all present per 20-03/20-04 SUMMARYs and screenshots in the phase directory. One deviation flagged by the phase itself: icon-tile palette for grains/coffee (purple/orange-red) differs from the mockup's amber/brown — explicitly NOT silently accepted; routed to the human check as an accept/reject item (see below). |
| 8 | Overview entry card wired to real pantry state (Level 4 data-flow) | ✓ VERIFIED | `OverviewView.swift:288-291` renders `KitchenGlanceCard(pantry: pantry)`; `pantry` is a live `@Query`-backed fetch (`OverviewView.swift:95-96`); the card counts `.out`/`.low` via `KitchenLogic.stockStatus`, not a hardcoded value. `-openKitchen` / `-scrollTo kitchen` debug hooks exist for screenshot verification (used in 20-05 review set). |

**Score:** 8/8 code-level truths verified. All are genuinely backed by code + independently re-run tests, not merely by SUMMARY.md claims.

### Independent Test Re-run (not taken on faith from SUMMARY.md)

Ran directly against the current `feat/20-kitchen-inventory` tree (not the commit that produced `20-05-gate.log`):

```
xcodebuild test -scheme MyHome -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:MyHomeTests/KitchenLogicTests \
  -only-testing:MyHomeTests/ShoppingListTests \
  -only-testing:MyHomeTests/KitchenSyncTests \
  -only-testing:MyHomeTests/SnapshotRoundTripTests -quiet
```
Result: **all test cases passed** — 11 KitchenLogicTests, 10 ShoppingListTests (incl. `derivationNeverMaterialisesRows`), 11 KitchenSyncTests, 7 SnapshotRoundTripTests (incl. `productionExportExcludesAllMoney`, `exportedBytesContainNoMoney`, `importRefusesOutOfScopeRows`, `importRefusesOutOfScopeTombstones`). No failures. This corroborates the `20-05-gate.log` full-suite claim (652 tests / 90 suites / 0 failures, run serially) on the specific slice most relevant to this verification's adversarial checklist.

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `MyHomeApp/Persistence/Schema/SchemaV11.swift` | PantryItem + ShoppingListItem, syncID/updatedAt from birth | ✓ VERIFIED | 2 new classes present, 13 syncID/updatedAt pairs (11 copied + 2 new), 0 `.unique` attrs |
| `MyHomeApp/Persistence/Models/PantryItem.swift`, `ShoppingListItem.swift` | typealias → SchemaV11 | ✓ VERIFIED | Both present, pbxproj-registered ("in Sources" x2 each) |
| `MyHomeApp/Sync/SyncSnapshot.swift` | `SyncScope.production` includes kitchen kinds | ✓ VERIFIED | Line 76: `[.note, .noteBlock, .routineCompletion, .pantryItem, .shoppingListItem]` — this is the KTCH-04 fact that matters most; DTOs alone would not have been sufficient |
| `MyHomeApp/Sync/SnapshotExporter.swift`, `SnapshotImporter.swift` | doubled enforcement of financial exclusion | ✓ VERIFIED | Export never fetches excluded kinds; import re-scopes before merge |
| `MyHomeApp/Features/Kitchen/KitchenLogic.swift` | pure stock math + derivation, no materialization | ✓ VERIFIED | `deriveShoppingItems` is pure; comment + test both pin "never inserts ShoppingListItem" |
| `MyHomeApp/Features/Kitchen/{KitchenView,PantryItemRow,ShoppingListView,ShoppingRow,EditPantryItemView}.swift` | neumorphic UI per mockup | ✓ VERIFIED | present, pbxproj-registered, build succeeds, screenshots in phase dir match mockup structurally |
| `MyHomeApp/Features/Overview/OverviewView.swift` (Kitchen entry) | pushed nav entry + glance card | ✓ VERIFIED | wired with live pantry query, not hardcoded |

### Key Link Verification

| From | To | Via | Status | Details |
|------|-----|-----|--------|---------|
| `ModelContainer+App.swift` | `SchemaV11` | `Schema(versionedSchema:)` | ✓ WIRED | confirmed live |
| `SyncSnapshot.scoped(to:)` | `SyncScope.production` | default param | ✓ WIRED | kitchen kinds included |
| `SnapshotExporter.makeSnapshot` | `SyncScope` | `guard scope.isSynced(kind)` per-fetch gate | ✓ WIRED | excluded kinds literally never queried |
| `SnapshotImporter.merge` | `SyncScope` | `rawSnapshot.scoped(to: scope)` before merge | ✓ WIRED | re-filters even a hostile `.all` payload |
| `OverviewView` | `KitchenView` | `navigationDestination(isPresented:)` | ✓ WIRED | push nav confirmed |
| `ShoppingListView` check-off (derived row) | `PantryItem.markRestocked` | direct call, no ShoppingListItem write | ✓ WIRED | confirmed by `derivationNeverMaterialisesRows` |

### Data-Flow Trace (Level 4)

| Artifact | Data Variable | Source | Produces Real Data | Status |
|----------|---------------|--------|---------------------|--------|
| `KitchenGlanceCard` (Overview) | `pantry` | `@Query`-backed fetch of `PantryItem` | Yes — counts derived via `KitchenLogic.stockStatus` over live rows | ✓ FLOWING |
| `PantryItemRow` badges | `item.quantity` / `item.lowStockThreshold` | live `PantryItem` model properties | Yes | ✓ FLOWING |
| Shopping `RESTOCK` section | `KitchenLogic.deriveShoppingItems(from: pantry)` | live `@Query` pantry array | Yes — recomputed at render, never a stale materialized array | ✓ FLOWING |

### Behavioral Spot-Checks

| Behavior | Command | Result | Status |
|----------|---------|--------|--------|
| Stock status math | `xcodebuild test -only-testing:KitchenLogicTests` | all pass | ✓ PASS |
| Derived shopping list never materializes rows | `xcodebuild test -only-testing:ShoppingListTests` | all pass, incl. `derivationNeverMaterialisesRows` | ✓ PASS |
| Kitchen entities cross the sync engine within scope | `xcodebuild test -only-testing:KitchenSyncTests` | all pass, incl. `v10PayloadRefused`, adoption/idempotency tests | ✓ PASS |
| Financial data never leaves device, doubled enforcement | `xcodebuild test -only-testing:SnapshotRoundTripTests` | all pass, incl. bytes-level leak check and hostile-peer scenario | ✓ PASS |
| Full regression suite | Not re-run in full during this verification (would exceed the session budget); relied on `20-05-gate.log` (652/90/0) plus this verification's independent 39-test slice re-run as corroboration | 652/90/0 (per gate log, cross-checked structurally) | ✓ PASS (corroborated, not blindly trusted) |

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|-------------|------------|-------------|--------|----------|
| KTCH-01 | 20-01, 20-03 | Pantry items with quantity/unit, add/edit, used/restocked | ✓ SATISFIED | Schema + KitchenLogic + EditPantryItemView + tests |
| KTCH-02 | 20-01, 20-03 | Low/out-of-stock visual flags from threshold | ✓ SATISFIED | `stockStatus` + `PantryItemRow` badges + tests |
| KTCH-03 | 20-01, 20-04 | Derived + manual shopping list, check-off restocks | ✓ SATISFIED | `deriveShoppingItems` (pure, non-materializing) + `ShoppingListView` + tests |
| KTCH-04 | 20-01, 20-02 | Kitchen syncs through the SYNC engine | ✓ SATISFIED | `SyncScope.production` genuinely includes kitchen kinds (not just DTOs); `KitchenSyncTests` full round-trip/adoption/idempotency/version-refusal coverage |

No orphaned requirements found in REQUIREMENTS.md/ROADMAP.md for this phase beyond the four declared.

### Anti-Patterns Found

None blocking. Scanned kitchen-touching files (`KitchenLogic.swift`, `KitchenView.swift`, `PantryItemRow.swift`, `ShoppingListView.swift`, `ShoppingRow.swift`, `EditPantryItemView.swift`, `SyncSnapshot.swift`, `SnapshotExporter.swift`, `SnapshotImporter.swift`) for `TODO|FIXME|HACK|TBD|XXX|placeholder|not yet implemented` — no matches beyond documentation prose describing design rationale (not debt markers). No stub returns (`return null`/`return []` feeding UI) found in kitchen view files.

One self-disclosed, non-blocking deviation from the phase itself (20-05-SUMMARY.md, "Carried observations"): the icon-tile palette for grains/coffee differs from the mockup's warmer tones — correctly NOT silently accepted by the executor, instead routed to the human check (item 9 below). This is exactly the right handling of a fidelity question and does not constitute a gap.

### Human Verification Required

The phase's own 20-05-SUMMARY.md explicitly declares its end-of-phase human gate is **pending** ("awaiting end-of-phase human verification" — confirmed in `.planning/STATE.md` line 29: "Status: Plan 5 of 5 complete — awaiting end-of-phase human verification"). This verifier did not find any record of the human check having been completed (no later commit, no STATE.md update marking it resolved). The nine items below are carried forward from 20-05-SUMMARY.md's human-check list, none of which can be verified by static analysis:

1. **Pantry add/edit + used/restocked flow** — tap-level UI walkthrough (add Milk, decrement to LOW/OUT).
2. **Shopping RESTOCK auto-population** — visual confirmation the derived row and pill render correctly live.
3. **Manual extra lifecycle** — add/check-off/clear-checked UI interaction.
4. **Check-off restocks pantry, round-trip to Pantry screen** — cross-screen state consistency.
5. **Light/dark visual parity with v1.2 design system** — aesthetic judgment.
6. **Two-phone sync via AirDrop export/merge** — requires two physical devices; not simctl-automatable (correctly identified as such in 20-05-SUMMARY.md — the bytes-level self-merge test is a partial, not full, substitute for the real share-sheet/Files interaction).
7. **(Optional) v10-build peer rejection** — requires a second device pinned to the prior build.
8. Same as 6 (deletion propagation across two phones).
9. **Icon-tile palette accept/reject decision** — explicit user preference question, not a bug.

**Why status is `human_needed` and not `passed`:** Every code-level truth is genuinely verified against the codebase (not merely SUMMARY.md claims) and independently re-run tests corroborate the phase's own gate log. However, per the verification decision tree, the presence of unresolved human-verification items takes priority over an otherwise-clean score — the two-phone sync check in particular is the single most load-bearing manual test for KTCH-04 (device-to-device behavior cannot be fully proven by unit tests alone) and has not yet been performed by the user.

### Gaps Summary

No code-level gaps found. This phase's implementation is unusually rigorous: the financial-privacy invariant is enforced at two independent layers and tested against an adversarial "hostile full-scope peer" scenario (not just the happy path); the derived-shopping-list design decision is enforced by both a pure-function contract and a dedicated regression test; the STAB-08 schema-flip discipline correctly extended to test-side production containers after that exact defect surfaced and was caught during the phase's own close-out (documented in 20-01-SUMMARY.md). The only outstanding item is the end-of-phase human verification, which the phase itself scheduled and has not yet reported as complete.

---

_Verified: 2026-07-21_
_Verifier: Claude (gsd-verifier)_

---

## On-device UAT — PASSED (2026-07-22)

The two-phone AirDrop kitchen sync was run on real devices (both on a Phase 20+ build,
deployed alongside Phase 22 off `main`) and confirmed working by the user. This covers
what the 2026-07-21 notes-only test could not: SchemaV11 migration on real hardware,
pantry/shopping rows crossing between phones, and tombstone propagation. Tracked and
closed as issue #40. All Phase 20 human-verification items are now satisfied.
