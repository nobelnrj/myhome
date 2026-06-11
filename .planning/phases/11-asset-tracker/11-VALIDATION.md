---
phase: 11
slug: asset-tracker
status: draft
nyquist_compliant: true
wave_0_complete: false
created: 2026-06-11
---

# Phase 11 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | XCTest / Swift Testing (`import Testing`) via `xcodebuild test` |
| **Config file** | none — existing MyHome.xcodeproj scheme `MyHome` / target `MyHomeTests` |
| **Quick run command** | `xcodebuild test -scheme MyHome -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:MyHomeTests/<Suite>` |
| **Full suite command** | `xcodebuild test -scheme MyHome -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:MyHomeTests` |
| **Estimated runtime** | ~90 seconds (simulator boot + build + suite) |

---

## Sampling Rate

- **After every task commit:** Run the task's `-only-testing:MyHomeTests/<Suite>` quick command (build-only tasks: `xcodebuild build`)
- **After every plan wave:** Run the full `MyHomeTests` suite
- **Before `/gsd-verify-work`:** Full suite must be green
- **Max feedback latency:** 120 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Threat Ref | Secure Behavior | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|------------|-----------------|-----------|-------------------|-------------|--------|
| 11-01-01 | 01 | 1 | ASSET-01, ASSET-08 | T-11-01 / T-11-03 | SchemaV7 additive, no `.unique`, CloudKit-ready | build | `xcodebuild build -scheme MyHome -destination 'platform=iOS Simulator,name=iPhone 17'` | ❌ W0 | ⬜ pending |
| 11-01-02 | 01 | 1 | ASSET-01, ASSET-08 | T-11-02 | Atomic typealias flip (no partial-flip crash) | build | `xcodebuild build -scheme MyHome -destination 'platform=iOS Simulator,name=iPhone 17'` | ❌ W0 | ⬜ pending |
| 11-01-03 | 01 | 1 | ASSET-01, ASSET-02, ASSET-04, ASSET-08 | T-11-01 | Migration does not throw; manual NAV preserved | unit | `xcodebuild test ... -only-testing:MyHomeTests/SchemaV7MigrationTests -only-testing:MyHomeTests/AssetCRUDTests -only-testing:MyHomeTests/AssetValueTests` | ❌ W0 | ⬜ pending |
| 11-02-01 | 02 | 2 | ASSET-03 | T-11-04 / T-11-05 | Malformed-row skip; HTTPS-only; silent failure | unit | `xcodebuild test ... -only-testing:MyHomeTests/AMFINavServiceTests` | ❌ W0 | ⬜ pending |
| 11-02-02 | 02 | 2 | ASSET-05, ASSET-08 | T-11-07 | CC sign convention via AccountBalance.compute; one snapshot/day | unit | `xcodebuild test ... -only-testing:MyHomeTests/NetWorthAggregationTests -only-testing:MyHomeTests/NetWorthSnapshotTests` | ❌ W0 | ⬜ pending |
| 11-02-03 | 02 | 2 | ASSET-03, ASSET-08 | T-11-08 | Services fired off-main on scenePhase .active | build | `xcodebuild build -scheme MyHome -destination 'platform=iOS Simulator,name=iPhone 17'` | ❌ W0 | ⬜ pending |
| 11-03-01 | 03 | 3 | ASSET-06, ASSET-09 | T-11-11 | Zero-cost-basis returns nil % (no divide-by-zero) | unit | `xcodebuild test ... -only-testing:MyHomeTests/StalenessBadgeTests -only-testing:MyHomeTests/AssetGainLossTests` | ❌ W0 | ⬜ pending |
| 11-03-02 | 03 | 3 | ASSET-01, ASSET-02, ASSET-04 | T-11-09 / T-11-10 | Units/cost bounds; plain `Text` (no markdown) | build | `xcodebuild build -scheme MyHome -destination 'platform=iOS Simulator,name=iPhone 17'` | ❌ W0 | ⬜ pending |
| 11-03-03 | 03 | 3 | ASSET-02, ASSET-06 | T-11-11 | Reuses tested gain/loss helper; "—" on nil % | build | `xcodebuild build -scheme MyHome -destination 'platform=iOS Simulator,name=iPhone 17'` | ❌ W0 | ⬜ pending |
| 11-04-01 | 04 | 4 | ASSET-07 | T-11-12 / T-11-13 | Negative cash clamped; Decimal→Double at boundary | unit | `xcodebuild test ... -only-testing:MyHomeTests/AllocationSegmentTests` | ❌ W0 | ⬜ pending |
| 11-04-02 | 04 | 4 | ASSET-05, ASSET-07, ASSET-08 | T-11-12 | Card suppressed when no data; no empty card | build | `xcodebuild build -scheme MyHome -destination 'platform=iOS Simulator,name=iPhone 17'` | ❌ W0 | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

*Checkpoint (human-verify) tasks — 11-03 Task 4 and 11-04 Task 3 — are covered by the Manual-Only Verifications below, not the automated map.*

---

## Wave 0 Requirements

Test files created within the phase plans (no separate framework install — XCTest/Swift Testing ships with the project):

- [ ] `MyHomeTests/SchemaV7MigrationTests.swift` — BLOCKING V6→V7 migration fixture (Plan 01)
- [ ] `MyHomeTests/AssetCRUDTests.swift` — ASSET-01 / ASSET-04 CRUD + manual-NAV preservation (Plan 01)
- [ ] `MyHomeTests/AssetValueTests.swift` — ASSET-02 currentValue = units × currentNAV derivation (Plan 01)
- [ ] `MyHomeTests/NetWorthSnapshotTests.swift` — ASSET-08 snapshot persistence (Plan 01 stubs → Plan 02 upsert)
- [ ] `MyHomeTests/AMFINavServiceTests.swift` — ASSET-03 parse guards + IST gate (Plan 02)
- [ ] `MyHomeTests/NetWorthAggregationTests.swift` — ASSET-05 sign convention (Plan 02)
- [ ] `MyHomeTests/AssetGainLossTests.swift` — ASSET-06 gain/loss + zero-cost-basis (Plan 03)
- [ ] `MyHomeTests/StalenessBadgeTests.swift` — ASSET-09 staleness IST calendar-day rule (Plan 03)
- [ ] `MyHomeTests/AllocationSegmentTests.swift` — ASSET-07 donut segment clamp (Plan 04)

*Shared fixtures: in-memory `ModelContainer(... isStoredInMemoryOnly: true)` mirroring AccountCRUDTests; no separate conftest needed.*

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Holdings CRUD + AMFI picker + detail + pull-to-refresh live flow | ASSET-01, ASSET-02, ASSET-04, ASSET-06, ASSET-09 | SwiftUI navigation/sheet/picker interaction + live network fetch not unit-testable | Plan 03 Task 4 checkpoint: add MF via searchable picker, stock via manual price, edit/swipe-delete, view detail gain/loss + staleness, pull-to-refresh |
| Overview net-worth card placement, donut/legend, trend, suppression, negative-net | ASSET-05, ASSET-07, ASSET-08 | Visual layout, chart rendering, and suppression behavior require on-device inspection | Plan 04 Task 3 checkpoint: verify card appears only with data, donut colors/legend, trend chart, tap navigation, negative-net renders without crash |

---

## Validation Sign-Off

- [x] All tasks have `<automated>` verify or Wave 0 dependencies
- [x] Sampling continuity: no 3 consecutive tasks without automated verify
- [x] Wave 0 covers all MISSING references
- [x] No watch-mode flags
- [x] Feedback latency < 120s
- [x] `nyquist_compliant: true` set in frontmatter

**Approval:** approved 2026-06-11
