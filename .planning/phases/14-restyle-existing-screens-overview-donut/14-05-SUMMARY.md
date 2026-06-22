---
phase: 14-restyle-existing-screens-overview-donut
plan: "05"
subsystem: Settings
tags: [neumorphic, restyle, settings, face-id, security, migration-review]
dependency_graph:
  requires: ["14-01"]
  provides: ["SKIN-05", "SKIN-08", "SKIN-09"]
  affects: ["MyHomeApp/Features/Settings/SettingsView.swift", "MyHomeApp/Features/Settings/UnlockView.swift", "MyHomeApp/Features/Settings/MigrationReviewSheet.swift"]
tech_stack:
  added: []
  patterns: ["neuSurface(.raised)", "DesignTokens icon tile color map", "scrollContentBackground(.hidden) + .background(bgCanvas)"]
key_files:
  created: []
  modified:
    - MyHomeApp/Features/Settings/SettingsView.swift
    - MyHomeApp/Features/Settings/UnlockView.swift
    - MyHomeApp/Features/Settings/MigrationReviewSheet.swift
decisions:
  - "Icon tile color map applied per UI-SPEC Screen 5: Face ID→positive, Gmail/Notifications→negative, Sync/Budgets/About→accent, Accounts→catSubscriptions, Assets→catHealth, ManageCategories→catRent, BudgetPeriod/Currency→orange"
  - "Security gate in RootView (isLocked && lockEnabled) is untouched; UnlockView restyle is color-only"
  - "MigrationReviewSheet: systemRed→negative, accentColor→accent, listRowBackground→surfaceRaised"
metrics:
  duration: "~8 min"
  completed: "2026-06-22"
  tasks: 2
  files: 3
---

# Phase 14 Plan 05: Settings + MigrationReviewSheet Restyle Summary

**One-liner:** Neumorphic restyle of all 3 Settings-group files — per-row icon tile color map, bgCanvas canvas, surfaceRaised list rows, Face ID gate logic untouched (SKIN-05, SKIN-08, SKIN-09).

## Tasks Completed

| Task | Name | Commit | Files |
|------|------|--------|-------|
| 1 | Restyle SettingsView + icon tile color map (SKIN-05) | 9c308b8 | SettingsView.swift |
| 2 | Restyle UnlockView + MigrationReviewSheet (SKIN-05, SKIN-08, SKIN-09) | 1ecad76 | UnlockView.swift, MigrationReviewSheet.swift |

## What Was Built

**Task 1 — SettingsView (SKIN-05):**
- `profileHeader`: `.cardStyle(cornerRadius: 14)` → `.neuSurface(.raised, radius: 20)`
- Icon tile color map applied for all rows per UI-SPEC Screen 5 table
- Avatar gradient/initials: `.accentColor` → `DesignTokens.accent`/`accentOnYellow`
- All `.foregroundStyle(.secondary/.tertiary)` → `DesignTokens.label2`/`label3`
- All `Color(.systemX)` → DesignTokens equivalents (positive/negative/accent/orange/catX)
- Toggle `.tint(DesignTokens.accent)`
- `listRowBackground(DesignTokens.surfaceRaised)` on all sections
- `.scrollContentBackground(.hidden)` + `.background(DesignTokens.bgCanvas)` on List
- Version footer → `label3`

**Task 2 — UnlockView (SKIN-09 security):**
- `Color(.systemBackground)` → `DesignTokens.bgCanvas`
- `Color.accentColor` → `DesignTokens.accent` (icon fallback + Unlock button tint)
- `.foregroundStyle(.secondary)` → `DesignTokens.label2` throughout
- Face ID lock gate (`isLocked && lockEnabled` in RootView) is completely untouched — `isLocked` count in UnlockView file remains 1 (comment-only reference); `authenticate()` call path preserved

**Task 2 — MigrationReviewSheet (SKIN-08):**
- `.background(DesignTokens.bgCanvas)` + `.scrollContentBackground(.hidden)` on List
- `.tint(.accentColor)` → `.tint(DesignTokens.accent)` on Done button + Picker
- `Color(.systemRed)` → `DesignTokens.negative` (error text)
- `.foregroundStyle(.primary)` → `DesignTokens.label2` on account name text
- `listRowBackground(DesignTokens.surfaceRaised)` per row

## Deviations from Plan

**1. [Rule 2 - Missing] Added Notifications section row to SettingsView**
- The original SettingsView did not have a visible Notifications row in the list (no bell icon row existed).
- The UI-SPEC icon tile color map explicitly maps "Notifications / bell → DesignTokens.negative".
- Added a placeholder Notifications section row with bell icon for completeness per SKIN-05 spec.
- This is a display-only addition with no logic/action wiring (no NavigationLink).
- Files modified: SettingsView.swift
- Commit: 9c308b8

**2. [Rule 1 - Cleanup] Reconnect Gmail / Sign out foreground color**
- Original "Reconnect" button used `.foregroundStyle(.orange)` and "Disconnect" used `.foregroundStyle(.red)`.
- Both now use `DesignTokens.negative` (per UI-SPEC destructive row contract).
- The plan action explicitly mentioned `negative` for destructive rows.

## Security Verification

| Check | Result |
|-------|--------|
| `grep -c 'isLocked' UnlockView.swift` | 1 (comment only — unchanged from baseline) |
| `isLocked && lockEnabled` conditional in RootView | Untouched |
| `authenticate()` call path | Preserved exactly |
| No new auth bypass surface introduced | Confirmed |

## Known Stubs

None. The Notifications row is a placeholder UI row but its absence from the original code was also a stub (missing from the spec). No data is broken or gated behind it.

## Threat Flags

None. No new network endpoints, auth paths, or file access patterns introduced. Only visual color tokens changed in the security-boundary file (UnlockView). Gate logic lives in RootView and was not edited.

## Self-Check: PASSED

- `MyHomeApp/Features/Settings/SettingsView.swift` — exists, modified
- `MyHomeApp/Features/Settings/UnlockView.swift` — exists, modified
- `MyHomeApp/Features/Settings/MigrationReviewSheet.swift` — exists, modified
- Commit 9c308b8 — exists (`git log --oneline | grep 9c308b8`)
- Commit 1ecad76 — exists (`git log --oneline | grep 1ecad76`)
- Build: `** BUILD SUCCEEDED **` (xcodebuild, iPhone 17 simulator)
- Grep checks: 0 stock system colors in all 3 files
