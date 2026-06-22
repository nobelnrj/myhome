---
phase: 14-restyle-existing-screens-overview-donut
plan: "08"
subsystem: design-system / build-gate
tags: [cleanup, build-gate, restyle, neumorphic, phase-close]
dependency_graph:
  requires: ["14-02", "14-03", "14-04", "14-05", "14-06", "14-07"]
  provides: ["SKIN-09 build gate passed", "deprecated shims deleted", "phase 14 complete"]
  affects: ["MyHome.xcodeproj/project.pbxproj"]
tech_stack:
  added: []
  patterns: ["pbxproj 8-edit removal (4 per file)", "STAB-08 test guard", "SKIN-09 color assertion"]
key_files:
  created: []
  modified:
    - MyHome.xcodeproj/project.pbxproj
    - MyHomeTests/NoteModelTests.swift
  deleted:
    - MyHomeApp/Features/Shared/CardStyle.swift
    - MyHomeApp/DesignSystem/NeuTabBar.swift
decisions:
  - "CardStyle.swift and NeuTabBar.swift deleted after confirming zero live call sites"
  - "NoteModelTests STAB-08 guard bumped from SchemaV8 to SchemaV9 (Rule 1 auto-fix)"
metrics:
  duration: 7
  completed: "2026-06-22"
  tasks_completed: 2
  tasks_total: 3
  files_changed: 4
---

# Phase 14 Plan 08: Close Phase - Delete Deprecated Shims + Build Gate Summary

**One-liner:** Deleted CardStyle.swift (D-03) and NeuTabBar.swift (D-02) with all 8 pbxproj removal edits; full clean build + 433 tests pass; zero stock system colors remain app-wide (SKIN-09).

## Status

**Checkpoint reached at Task 3** (end-of-phase human-verify). Tasks 1 and 2 are complete and committed. Awaiting human verification on the iPhone 17 simulator.

## Tasks Completed

| Task | Name | Commit | Files |
|------|------|--------|-------|
| 1 | Delete CardStyle.swift + NeuTabBar.swift with pbxproj removal edits (D-02, D-03) | fb5564d | project.pbxproj, CardStyle.swift (deleted), NeuTabBar.swift (deleted) |
| 2 | Full clean build + test gate + app-wide stock-color assertion (SKIN-09) | e44207b | NoteModelTests.swift |

## Task 3 (Checkpoint)

**Awaiting:** Human verification of neumorphic look + no-regression across all v1.1 flows on iPhone 17 simulator (dark mode).

## Key Results

### Task 1: File Deletion (D-02, D-03)

Pre-deletion grep confirmed zero live call sites:
- `grep -rn "cardStyle\|NeuTabBar" MyHomeApp/ | grep -v '//'` → 0 results
- `grep -c "CardStyle.swift" project.pbxproj` → 0
- `grep -c "NeuTabBar.swift" project.pbxproj` → 0

8 pbxproj removal edits applied (4 per file):
- **CardStyle.swift:** PBXBuildFile (line 88), PBXFileReference (line 389), PBXGroup children (Shared group), PBXSourcesBuildPhase entry
- **NeuTabBar.swift:** PBXBuildFile (line 204), PBXFileReference (line 419), PBXGroup children (DesignSystem group), PBXSourcesBuildPhase entry

### Task 2: Build + Test Gate

- `xcodebuild clean build` → **BUILD SUCCEEDED**
- `xcodebuild test -parallel-testing-enabled NO` → **433 tests in 63 suites — all PASS**
- SKIN-09 color gate: `grep -rnE 'Color\(\.(system...)' MyHomeApp/Features/ | grep -v '//' | wc -l` → **0**

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Fixed NoteModelTests STAB-08 guard using stale SchemaV8 version**
- **Found during:** Task 2 (test suite run)
- **Issue:** `noteSavesUnderProductionVersionedSchema` built its container with `Schema(versionedSchema: SchemaV8.self)` but the production container and all typealiases flipped to SchemaV9 in plan 12-01 (commit 23bfabc). SwiftData fatal crash: "Failed to cast model MyHome.SchemaV9.Note... to Note" because SchemaV8 container and SchemaV9 typealias don't match.
- **Fix:** Updated test comment + changed `SchemaV8.self` → `SchemaV9.self` in `NoteModelTests.swift:156`
- **Files modified:** `MyHomeTests/NoteModelTests.swift`
- **Commit:** e44207b
- **Note:** This is a pre-existing bug (introduced when 12-01 bumped schema but did not update the guard test). It was not caused by Plan 14-08 changes.

## Known Stubs

None. All deletions are clean; no stub patterns introduced.

## Threat Flags

None. No new network endpoints, auth paths, file access patterns, or schema changes introduced in this plan.

## Self-Check

To be completed after human verification.
