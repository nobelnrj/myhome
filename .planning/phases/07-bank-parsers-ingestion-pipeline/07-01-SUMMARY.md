---
phase: 07-bank-parsers-ingestion-pipeline
plan: "01"
subsystem: ingestion-scaffold
tags: [swift, swiftdata, schema-migration, tdd, bank-parsers, gmail-fetch]
dependency_graph:
  requires: [06-04]
  provides: [SchemaV4, GmailFetchPort, BankEmailParser, ParsedExpense, SpyGmailFetch, red-test-suite]
  affects: [MigrationPlan, MigrationTests, pbxproj]
tech_stack:
  added: [SchemaV4 (VersionedSchema), GmailFetchPort (protocol), BankEmailParser (protocol), ParsedExpense (Sendable value type), SpyGmailFetch (test double)]
  patterns: [port-protocol seam (mirrors GmailAuthPort), pure-struct value type, CloudKit-safe optional fields, RED test stubs via Issue.record]
key_files:
  created:
    - MyHomeApp/Persistence/Schema/SchemaV4.swift
    - MyHomeApp/Gmail/GmailFetchPort.swift
    - MyHomeApp/Features/Ingestion/BankEmailParser.swift
    - MyHomeTests/Support/SpyGmailFetch.swift
    - MyHomeTests/HDFCParserTests.swift
    - MyHomeTests/ICICIParserTests.swift
    - MyHomeTests/ConfidenceScorerTests.swift
    - MyHomeTests/DedupCheckerTests.swift
    - MyHomeTests/MerchantNormalizerTests.swift
    - MyHomeTests/IngestionPipelineTests.swift
    - MyHomeTests/Resources/Fixtures/README.md
  modified:
    - MyHomeApp/Persistence/Schema/MigrationPlan.swift
    - MyHomeTests/MigrationTests.swift
    - MyHome.xcodeproj/project.pbxproj
decisions:
  - "MigrationTestsPlanV3 trimmed plan added to tests to decouple V3-targeting migration tests from AppMigrationPlan that now chains to V4; Expense typealias flip deferred to plan 07-02"
  - "SystemGmailFetch methods stub to throw GmailFetchError rather than fatalError so tests can exercise error paths without crashing"
  - "Fixtures dir placed at MyHomeTests/Resources/Fixtures so Xcode copies it as a bundle resource correctly (path relative to G210 group)"
metrics:
  duration: 17
  completed_date: "2026-06-02"
  tasks_completed: 3
  files_created: 11
  files_modified: 3
---

# Phase 7 Plan 01: Wave-0 Scaffold (SchemaV4 + Seams + RED Tests) Summary

SchemaV4 with 7 CloudKit-safe ingestion fields on Expense, V3→V4 migration stage, GmailFetchPort + BankEmailParser protocol seams, SpyGmailFetch test double, and six RED test files mapping every Phase 7 requirement — all compiled and registered in pbxproj.

## Tasks Completed

| Task | Name | Commit | Files |
|------|------|--------|-------|
| 1 | SchemaV4 + V3→V4 migration stage | 97b4f50 | SchemaV4.swift, MigrationPlan.swift, pbxproj |
| 2 | GmailFetchPort seam + BankEmailParser + ParsedExpense + SpyGmailFetch | feec4f8 | GmailFetchPort.swift, BankEmailParser.swift, SpyGmailFetch.swift, pbxproj |
| 3 | Six failing test files (RED) + Fixtures dir + pbxproj registration | 49fecdf | 6 test files, MigrationTests.swift, Fixtures/README.md, pbxproj |

## What Was Built

**SchemaV4** (`MyHomeApp/Persistence/Schema/SchemaV4.swift`): VersionedSchema v4.0.0 — an additive superset of SchemaV3 with 7 new optional/defaulted ingestion fields on Expense:
- `rawEmailBody: String?` (ING-10, D7-10) — raw email stored for audit
- `parserID: String?`, `parserVersion: String?` (ING-11, D7-11) — parser provenance
- `sourceLabel: String?` (D7-15) — human-readable source label
- `gmailMessageID: String?` (ING-14, D7-07) — dedup key
- `ingestionStateRaw: String?` (ING-12/13/14) — "autoSaved"|"needsReview"|"possibleDuplicate" (String not enum per CloudKit rule 8)
- `parseConfidence: Double?` (ING-12) — 0.0–1.0 ratio (Double not Decimal — not money)

All fields comply with all 8 CloudKit-readiness rules. Category, Note, NoteBlock copied verbatim from SchemaV3.

**MigrationPlan** updated: `SchemaV4.self` appended to `schemas` array; `v3ToV4` stage added using `.custom(willMigrate: nil, didMigrate: nil)` per FB13812722 pattern.

**GmailFetchPort** (`MyHomeApp/Gmail/GmailFetchPort.swift`): Protocol seam (`getProfile`, `listMessageIDs`, `getRawMessage`) + `GmailProfile` Decodable value type + `GmailFetchError` enum + `SystemGmailFetch` stub conformer (plan 05 fills network calls).

**BankEmailParser** (`MyHomeApp/Features/Ingestion/BankEmailParser.swift`): `ParsedExpense` Sendable value type (amount: Decimal, normalized/raw merchant, category hint, reversal flag, fingerprint/extraction scores) + `BankEmailParser` protocol (canHandle/parse).

**SpyGmailFetch** (`MyHomeTests/Support/SpyGmailFetch.swift`): Test double mirroring SpyGmailAuth exactly — settable stubs, per-method shouldThrow, recorded-call arrays, rawMessagesByID lookup, reset().

**Six RED test files**: Each `@MainActor struct` using Swift Testing, with `@Test` stubs that call `Issue.record("unimplemented — plan NN")`. Tests compile cleanly but fail at runtime (RED).

**Fixtures/README.md**: Documents the corpus gate (plan 04), `.eml` naming convention for HDFC + ICICI corpus, anonymization requirements, and bundle resource loading pattern.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] MigrationTests broken by SchemaV4 addition to AppMigrationPlan**
- **Found during:** Task 3 verification
- **Issue:** `MigrationTests.v1StoreMigratesCleanly()` and `v2StoreMigratesToV3()` use `Schema(versionedSchema: SchemaV3.self)` + `AppMigrationPlan.self`. After adding `SchemaV4.self` to AppMigrationPlan, SwiftData sees a mismatch between the plan's terminal schema (V4) and the requested container schema (V3), causing both tests to fail.
- **Fix:** Added `MigrationTestsPlanV3` enum in `MigrationTests.swift` — a trimmed migration plan (V1→V2→V3 only) decoupled from AppMigrationPlan. Updated both test methods to use this local plan until plan 07-02 flips the `Expense` typealias to `SchemaV4.Expense` and re-wires to full AppMigrationPlan.
- **Files modified:** `MyHomeTests/MigrationTests.swift`
- **Commit:** 49fecdf

**2. [Rule 3 - Blocking] Fixtures directory path mismatch**
- **Found during:** Task 3 verification build
- **Issue:** pbxproj's G210 Resources group has `path = Resources`, so adding Fixtures as a child resolved to `MyHomeTests/Resources/Fixtures`. Xcode tried to copy from that path; the directory was created at `MyHomeTests/Fixtures/`.
- **Fix:** Moved `MyHomeTests/Fixtures/` to `MyHomeTests/Resources/Fixtures/` to match the group-relative path expected by pbxproj.
- **Files modified:** `MyHomeTests/Resources/Fixtures/README.md` (re-created at correct path)
- **Commit:** 49fecdf

## Known Stubs

| Stub | File | Reason |
|------|------|--------|
| `SystemGmailFetch.getProfile/listMessageIDs/getRawMessage` | `GmailFetchPort.swift` | Production network calls deferred to plan 05 per plan spec |
| Six test `@Test` bodies | `*Tests.swift` | Intentional RED stubs; implementing plans 03/05/06 |

## Threat Surface

T-07-01 mitigated: `v3ToV4` uses `.custom(willMigrate: nil, didMigrate: nil)` to sidestep FB13812722.
T-07-03 mitigated: all new fields are optional/defaulted, no `@Attribute(.unique)`, no stored enums, Double only for ratio (not money).
T-07-02 accepted: `rawEmailBody` field defined but not populated in this plan; Face ID gate already in place.

## Self-Check: PASSED

All 11 created files exist on disk. All 3 task commits verified in git history.

| Check | Result |
|-------|--------|
| SchemaV4.swift exists | FOUND |
| GmailFetchPort.swift exists | FOUND |
| BankEmailParser.swift exists | FOUND |
| SpyGmailFetch.swift exists | FOUND |
| 6 test files exist | FOUND (all 6) |
| Fixtures/README.md exists | FOUND |
| Commit 97b4f50 (Task 1) | FOUND |
| Commit feec4f8 (Task 2) | FOUND |
| Commit 49fecdf (Task 3) | FOUND |
