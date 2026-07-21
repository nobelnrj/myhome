---
phase: 20-kitchen-inventory-shopping-list
plan: 02
subsystem: sync
tags: [sync, snapshot, dto, merge-engine, kitchen, pantry, shopping-list, schema-version, ktch-04]

# Dependency graph
requires:
  - phase: 18-sync-foundation-schema-merge-engine-airdrop
    provides: SyncSnapshot document layer, SnapshotExporter/SnapshotImporter, SyncMergePolicy, SyncScope, DeletionLog tombstones
  - phase: 20-kitchen-inventory-shopping-list
    plan: 01
    provides: SchemaV11 PantryItem/ShoppingListItem, SyncStamped conformances
provides:
  - "PantryItemDTO + ShoppingListItemDTO — full-fidelity wire mirrors of the SchemaV11 kitchen models"
  - "SyncEntityKind.pantryItem / .shoppingListItem — kitchen rows can be tombstoned by DeletionLog"
  - "SyncSnapshot.currentSchemaVersion = 11 — v10 phones refused cleanly by the existing version probe"
  - "SyncScope.production widened to notes + kitchen; financial kinds still excluded at export AND import"
  - "SnapshotImporter.adoptByName() — generic normalized-name + min(uuidString) adoption, now shared by Category and both kitchen types"
  - "Kitchen tombstone/adoption/LWW handling in the merge engine (no wiring pass — kitchen is relationship-free)"
affects: [20-03, 20-04, 20-05, 19-transport]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Kitchen quantities cross the wire as Double, never SyncDecimal — the money-as-String rule governs Decimal fields, and kitchen has none"
    - "Normalized-name adoption is now a generic helper, not a per-entity copy — one rule, one implementation, vantage-independent min(uuidString)"
    - "Widening SyncScope is the deliberate act that makes a new entity actually sync; adding DTOs alone is invisible in production"

key-files:
  created:
    - MyHomeTests/KitchenSyncTests.swift
  modified:
    - MyHomeApp/Sync/SyncSnapshot.swift
    - MyHomeApp/Sync/SnapshotExporter.swift
    - MyHomeApp/Sync/SnapshotImporter.swift
    - MyHomeTests/SnapshotCodecTests.swift
    - MyHomeTests/SnapshotImporterTests.swift
    - MyHomeTests/SnapshotRoundTripTests.swift
    - MyHome.xcodeproj/project.pbxproj

key-decisions:
  - "SyncScope.production widened to include .pantryItem/.shoppingListItem (deviation, Rule 2) — without it the DTOs would be dead code and KTCH-04 false on a real device"
  - "Category's adoption rule was generalised into adoptByName<Row, DTO> rather than copied twice — one implementation of the convergence rule"
  - "Kitchen DTO arrays are REQUIRED (not optional) like the existing 11: the version probe guarantees a v10 payload never reaches full decode"
  - "The pre-existing notes-only scope test was renamed to productionExportExcludesAllMoney and now asserts kitchen present + every financial array empty — the guarantee that matters is money exclusion, not notes exclusivity"

patterns-established:
  - "A new syncable entity is not done at the DTO layer: DTO + SyncEntityKind + exporter fetch + importer tombstone/adopt/upsert + SyncScope widening is the complete checklist"

requirements-completed: [KTCH-04]

# Metrics
duration: ~1h
completed: 2026-07-21
---

# Phase 20 Plan 02: Kitchen Sync Wiring Summary

**Wired PantryItem/ShoppingListItem into the Phase 18 merge engine end-to-end — full-fidelity DTOs, `SyncEntityKind` cases, `currentSchemaVersion` bumped 10→11 in lockstep with SchemaV11, exporter/importer support for tombstones, normalized-name adoption and LWW, and `SyncScope.production` widened to notes+kitchen — proven by 10 new `KitchenSyncTests` while every financial kind stays provably off the wire.**

## What shipped

- **SyncSnapshot.swift** — `PantryItemDTO` (id, syncID, updatedAt, name, quantity, unit, lowStockThreshold, restockQuantity, category, notes, createdAt) and `ShoppingListItemDTO` (…, isChecked, checkedAt) mirroring every SchemaV11 stored property; `SyncEntityKind.pantryItem`/`.shoppingListItem`; two new required snapshot arrays wired through `init` and `scoped(to:)`; `currentSchemaVersion = 11` with a comment explaining the v10-refusal consequence. The file remains a pure value layer (still zero `import SwiftData`).
- **SnapshotExporter.swift** — `dto(_: PantryItem)` / `dto(_: ShoppingListItem)` mappers (internal, so the importer reuses them for local-side canonical bytes in LWW ties); kitchen fetches in `makeSnapshot`, syncID-sorted like every other array. 13 entity fetches + DeletionLog.
- **SnapshotImporter.swift** — kitchen branches in the tombstone pass; adoption via a new generic `adoptByName<Row, DTO>` that extracts the Category rule verbatim (trimmed, case-folded, non-empty name; survivor takes `min(uuidString)`; remote DTO syncID rewritten so the upsert matches the twin instead of inserting); kitchen upserts through the same `SyncMergePolicy.remoteWins` path; wiring pass 2 carries a comment recording that kitchen's absence is intentional (zero `@Relationship` by 20-01 design). Still exactly one `try context.save()`.
- **KitchenSyncTests.swift** — 10 tests: round-trip fidelity + syncID preservation, idempotent re-import, pantry and shopping adoption convergence, v10 refusal with store-untouched assertion, no-resurrection for both kitchen types (including that the outgoing tombstone carries the right `entityKindRaw`), LWW newer-wins/older-loses in place, and checked-state propagation.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 2 - Missing critical functionality] `SyncScope.production` widened to include kitchen**

- **Found during:** Task 1
- **Issue:** The plan specified DTOs, exporter fetches and importer handling but never mentioned `SyncScope`. Since Phase 19's scope gate is applied at BOTH export and import, kitchen rows would have been silently filtered to empty arrays on a real device — every new test would still pass under `scope: .all`, while KTCH-04 ("kitchen data flows to the other phone") would have been false in production. This is exactly the class of stub the phase is meant to avoid.
- **Fix:** `SyncScope.production` now synces `[.note, .noteBlock, .routineCompletion, .pantryItem, .shoppingListItem]`, with a comment recording that the widening is strictly additive and the financial exclusions are unchanged. All KitchenSyncTests deliberately run under the DEFAULT (production) scope, so they fail if the scope is ever narrowed again.
- **Files modified:** `MyHomeApp/Sync/SyncSnapshot.swift`, `MyHomeTests/SnapshotRoundTripTests.swift`
- **Commits:** `e9d2227`, `bb06419`

**2. [Rule 2 - Test integrity] Notes-only scope tests updated deliberately, not weakened**

- **Found during:** Task 2
- **Issue:** `productionExportIsNotesOnly` asserted notes-exclusivity, which the (correct) scope widening invalidates. Deleting or loosening it would have silently dropped the financial-exclusion guarantee.
- **Fix:** Renamed to `productionExportExcludesAllMoney`; it now asserts kitchen arrays are POPULATED and every financial array (expenses, categories, accounts, assets, netWorthSnapshots, sips, sipAmountChanges, contributions) is empty. `exportedBytesContainNoMoney` (byte-level money-leak gate) and `importRefusesOutOfScopeRows` / `importRefusesOutOfScopeTombstones` are untouched, with the import test additionally asserting the kitchen row DID cross while expenses/accounts/assets did not.
- **Files modified:** `MyHomeTests/SnapshotRoundTripTests.swift`
- **Commit:** `bb06419`

### Environment note (not a code deviation)

The first two test runs failed with `Simulator device failed to launch … RequestDenied ("Application failed preflight checks")` — a transient CoreSimulator state, not a build failure. Resolved by `simctl shutdown all` and targeting the booted `iPhone 17` by UDID.

## Financial-exclusion proof (still intact)

| Guarantee | Test | Status |
|---|---|---|
| Money never fetched for export | `productionExportExcludesAllMoney` | PASS |
| Money never present in exported BYTES | `exportedBytesContainNoMoney` | PASS |
| Import refuses money a peer sends anyway | `importRefusesOutOfScopeRows` | PASS |
| Out-of-scope tombstone cannot delete local money rows | `importRefusesOutOfScopeTombstones` | PASS |
| Decimal integrity unchanged | `decimalIntegrity`, `SnapshotCodecTests` | PASS |

## Verification

- Acceptance criteria: `currentSchemaVersion = 11` count 1, `= 10` count 0; 2 kitchen DTO structs; `import SwiftData` count 0 in SyncSnapshot.swift; no `SyncDecimal` in kitchen mappings; `KitchenSyncTests.swift in Sources` present in pbxproj (all 4 edits); zero `expected: 10` pins left; zero `versionedSchema: SchemaV10.self` in the sync test files; exactly one real `try context.save()` in `merge()`.
- Targeted run (KitchenSync + Codec + Importer + RoundTrip): all passed.
- **Full suite serial (`-parallel-testing-enabled NO`): `✔ Test run with 630 tests in 88 suites passed` — 0 failures, no `Fatal error`, no `Restarting after unexpected exit`.**

## Known Stubs

None.

## Threat Flags

None — no new network endpoint, auth path, or file-access surface. The one new trust-boundary change (version stamp 10→11) is the mitigation for T-20-03 and is asserted by test.
