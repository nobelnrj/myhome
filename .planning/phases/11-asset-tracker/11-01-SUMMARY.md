---
phase: 11-asset-tracker
plan: "01"
subsystem: persistence
tags: [schema-migration, swiftdata, schemaV7, asset-tracker, net-worth, tdd]
dependency_graph:
  requires: []
  provides: [SchemaV7, NetWorthSnapshot, Asset.amfiSchemeCode, v6ToV7MigrationStage]
  affects: [all @Model typealiases, ModelContainer, AppMigrationPlan, Wave-2-plans]
tech_stack:
  added: []
  patterns:
    - SwiftData VersionedSchema additive migration (FB13812722 .custom stage)
    - Atomic STAB-08 typealias flip (all 7 typealiases in one commit)
    - In-memory ModelContainer Swift Testing (AccountCRUDTests mirror pattern)
    - On-disk fixture migration test (SchemaV6MigrationTests mirror pattern)
key_files:
  created:
    - MyHomeApp/Persistence/Schema/SchemaV7.swift
    - MyHomeApp/Persistence/Models/NetWorthSnapshot.swift
    - MyHomeTests/SchemaV7MigrationTests.swift
    - MyHomeTests/AssetCRUDTests.swift
    - MyHomeTests/AssetValueTests.swift
    - MyHomeTests/NetWorthSnapshotTests.swift
  modified:
    - MyHomeApp/Persistence/Models/Asset.swift
    - MyHomeApp/Persistence/Models/Account.swift
    - MyHomeApp/Persistence/Models/Expense.swift
    - MyHomeApp/Persistence/Models/Category.swift
    - MyHomeApp/Persistence/Models/Note.swift
    - MyHomeApp/Persistence/Models/NoteBlock.swift
    - MyHomeApp/Persistence/Schema/MigrationPlan.swift
    - MyHomeApp/Persistence/ModelContainer+App.swift
decisions:
  - "MigrationTestsPlanV6 helper added to SchemaV7MigrationTests to seed genuine V6 stores without triggering V7 migration — mirrors MigrationTestsPlanV5 pattern from SchemaV6MigrationTests.swift"
  - "NetWorthSnapshot sub-totals stored as separate Decimal fields (mfValue/stockValue/npsValue/cashValue) per RESEARCH.md recommendation — simpler to query than a Codable blob, CloudKit supports multiple Decimal fields"
  - "NetWorthSnapshotTests service-upsert tests kept as named stubs (trivially-true assertions) rather than omitted — they serve as a named checklist for the Wave 2 planner (Plan 02)"
  - "ModelContainer+App.swift had only 1 occurrence of Schema(versionedSchema:), not 2 as the plan AC stated — the one occurrence was flipped correctly; the plan AC was off by one"
metrics:
  duration_minutes: 35
  completed_date: "2026-06-11"
  tasks_completed: 3
  files_changed: 14
---

# Phase 11 Plan 01: SchemaV7 Migration — amfiSchemeCode + NetWorthSnapshot Summary

**One-liner:** SchemaV7 additive migration ships amfiSchemeCode on Asset and a new NetWorthSnapshot @Model in one atomic commit, with all STAB-08 typealias flips and four Wave-0 test scaffolds green on iPhone 17 Pro.

---

## What Was Built

### Task 1+2 (committed atomically — STAB-08 requirement): SchemaV7 schema + typealias flip + migration stage + container bump

**Commit:** `6ea396f`

`SchemaV7.swift` copies all six SchemaV6 @Models verbatim and makes two additive changes only:
1. `Asset.amfiSchemeCode: String? = nil` appended after all V6 Asset fields (D-01)
2. New `NetWorthSnapshot` @Model with 8 fields: id, date, totalNetWorth, mfValue, stockValue, npsValue, cashValue, createdAt — all Decimal money fields, no `@Attribute(.unique)`, CloudKit-ready

All 7 model typealiases flipped from `SchemaV6.X` to `SchemaV7.X` in the same commit (STAB-08 prevention):
- Asset, Account, Expense, Category, Note, NoteBlock (modified)
- NetWorthSnapshot (new file)

`MigrationPlan.swift`: SchemaV7.self appended to schemas array; v6ToV7 stage appended; v6ToV7 uses `.custom(willMigrate: nil, didMigrate: nil)` — additive-only, no backfill needed (FB13812722 compliance).

`ModelContainer+App.swift`: `Schema(versionedSchema: SchemaV6.self)` → `Schema(versionedSchema: SchemaV7.self)`.

Build: SUCCEEDED on iPhone 17 Pro simulator.

### Task 3: Wave-0 test scaffolds

**Commit:** `38ccf9f`

**SchemaV7MigrationTests.swift (BLOCKING)**
- `v6StoreAssetAmfiSchemeCodeIsNilAfterMigration`: Seeds a genuine V6 on-disk store with one Asset row; migrates via AppMigrationPlan; asserts amfiSchemeCode == nil on the migrated row (D-03)
- `netWorthSnapshotQueryableAfterMigration`: V6 store migrates to V7; FetchDescriptor<NetWorthSnapshot> returns empty array (not crash)
- `MigrationTestsPlanV6` helper enum mirrors MigrationTestsPlanV5 pattern

**AssetCRUDTests.swift (ASSET-01, ASSET-04)**
- Insert: 1 Asset persisted with name/assetClassRaw/units/costBasisPerUnit
- Edit: currentNAV updated and reflected on re-fetch
- Delete: store empty after delete
- ASSET-04 manual NAV: stock/NPS currentNAV persists unchanged across fetch cycles
- amfiSchemeCode persistence: stores and queries correctly

**AssetValueTests.swift (ASSET-02)**
- `currentValue = units × currentNAV` exact Decimal equality (10 × 12.50 == 125.00)
- Large holding (1000 × 234.56 == 234560.00)
- nil units → 0 (no crash)
- nil currentNAV → 0 (no crash)
- both nil → 0 (no crash)

**NetWorthSnapshotTests.swift (ASSET-08 model layer)**
- Model-level persistence: all 5 Decimal sub-total fields persist exactly
- Defaults: all Decimal fields default to 0
- Negative cashValue (CC debt) persists without clamping at model layer (D-11)
- createdAt and UUID auto-populated in init
- Stub tests for service-upsert behavior (Plan 02 fills these in)

Test results: ALL GREEN on iPhone 17 Pro simulator.

---

## Deviations from Plan

### Auto-fixed Issues

None — plan executed exactly as written with one minor note:

**Note: ModelContainer+App.swift had 1 `Schema(versionedSchema:)` site, not 2**
- The plan acceptance criteria stated `grep -c 'versionedSchema: SchemaV7'` should return 2
- The file had only one `Schema(versionedSchema: SchemaV6.self)` call in the original
- That one call was correctly flipped to `SchemaV7.self`
- The `ModelContainer(for: schema, ...)` line reuses the `schema` variable — it is not a second `Schema(versionedSchema:)` call
- Functional behavior is identical; acceptance criteria was slightly inaccurate

---

## Known Stubs

| Stub | File | Lines | Reason |
|------|------|-------|--------|
| `stubUpsertSameDayProducesOneRow` | `NetWorthSnapshotTests.swift` | ~90-98 | Requires NetWorthSnapshotService (Plan 02); trivially-true assertion for now |
| `stubUpsertNewDayProducesSecondRow` | `NetWorthSnapshotTests.swift` | ~100-108 | Requires NetWorthSnapshotService (Plan 02); trivially-true assertion for now |

These stubs are intentional — Plan 02's scope explicitly includes the upsert service. They do not prevent Plan 01's goal (SchemaV7 migration foundation) from being achieved.

---

## Threat Surface Scan

No new security surface introduced. All changes are persistence-layer only:
- `SchemaV7.swift` adds no network endpoints, no auth paths, no file I/O beyond the SwiftData store
- T-11-01 (migration correctness): mitigated — BLOCKING migration test green
- T-11-02 (STAB-08 partial flip): mitigated — grep confirms zero SchemaV6 typealiases remain
- T-11-03 (@Attribute(.unique) CloudKit breakage): mitigated — grep confirms 0 `@Attribute(.unique)` in non-comment lines of SchemaV7.swift

---

## Self-Check: PASSED

| Item | Status |
|------|--------|
| SchemaV7.swift | FOUND |
| NetWorthSnapshot.swift (typealias) | FOUND |
| SchemaV7MigrationTests.swift | FOUND |
| AssetCRUDTests.swift | FOUND |
| AssetValueTests.swift | FOUND |
| NetWorthSnapshotTests.swift | FOUND |
| 11-01-SUMMARY.md | FOUND |
| Commit 6ea396f (Tasks 1+2) | FOUND |
| Commit 38ccf9f (Task 3) | FOUND |
| SchemaV6 typealiases remaining | 0 |
| @Attribute(.unique) in SchemaV7 non-comments | 0 |
