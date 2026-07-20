---
phase: 19-auto-sync-sync-ux-multipeer-bootstrap
plan: 03
subsystem: ui
tags: [swiftui, sync, multipeer, neumorphic, presentation-mapper, swift-testing]

requires:
  - phase: 19-02
    provides: SyncCoordinator (@Observable, syncNow()) + SyncStatusStore (PeerSyncStatus, lastSyncedAt, connectedPeerName, lastMergeStats)
  - phase: 18
    provides: MergeStats (inserted/updated/deleted/skipped/adopted)
provides:
  - "SyncStatusPresentation — pure, unit-tested mapper (status → label/symbol/tint, date → relative text, MergeStats → summary)"
  - "SyncStatusView — neumorphic Sync surface reachable from Settings → Sync"
  - "Settings Data-section Sync row with glanceable last-synced text"
  - "Manual 'Sync Now' affordance wired to SyncCoordinator.syncNow() (completes SYNC-04)"
affects: [19-04 bootstrap flow, sync UX polish]

tech-stack:
  added: []
  patterns:
    - "Pure presentation mapper (enum, no SwiftUI state) drives a thin view — all display logic unit-tested without rendering"
    - "TimelineView(.periodic by: 30) ages relative-time text without user interaction"
    - "DEBUG -openSync launch-arg screenshot hook (mirrors OverviewView -openAnalytics)"

key-files:
  created:
    - MyHomeApp/Features/Settings/SyncStatusView.swift
    - MyHomeTests/SyncStatusPresentationTests.swift
  modified:
    - MyHomeApp/Features/Settings/SettingsView.swift
    - MyHome.xcodeproj/project.pbxproj
    - .planning/REQUIREMENTS.md

key-decisions:
  - "Presentation lives in a pure enum (SyncStatusPresentation) so every string/symbol/tint is a tested function of store state; the view is a thin observer"
  - "tint(for:) returns EXISTING DesignTokens members only — zero color definitions, dark byte-identity preserved (DarkBitIdentityTests green)"
  - "relativeLastSynced has an explicit <60s → 'Just now' branch to avoid RelativeDateTimeFormatter 'in 0 seconds' weirdness; locale pinned en_US for determinism"
  - "SYNC-04 marked Complete (manual Sync-now UI wired to syncNow() is its last piece); SYNC-05 left Pending — this plan is only its surface half, bootstrap flow is Plan 19-04"

patterns-established:
  - "Pure mapper + thin view: SwiftUI-free presentation logic is fully unit-testable"
  - "Added a per-screen DEBUG launch-arg push hook (-openSync) for light/dark screenshot verification of navigation-pushed screens"

requirements-completed: [SYNC-04]

duration: 18 min
completed: 2026-07-21
---

# Phase 19 Plan 03: Sync Surface (SYNC-05 UI half) Summary

**A neumorphic Sync screen — reachable from Settings — that shows live status, connected-peer name, relative last-synced time, and last merge stats, with a 'Sync Now' CTA wired to SyncCoordinator.syncNow(); all display logic lives in the pure, unit-tested SyncStatusPresentation mapper.**

## Performance

- **Duration:** ~18 min
- **Tasks:** 2/2
- **Files created:** 2 (SyncStatusView.swift, SyncStatusPresentationTests.swift)
- **Files modified:** 3 (SettingsView.swift, project.pbxproj, REQUIREMENTS.md)

## Accomplishments

### Task 1 — SyncStatusPresentation (pure mapping + tests)
- `SyncStatusPresentation` enum with deterministic, SwiftUI-free functions:
  - `label(for:lastSyncedAt:)` — idle reads "Up to date"/"Not synced yet" by history; connecting/syncing transient labels; error passes the Plan-02 message through verbatim.
  - `systemImage(for:)` — checkmark.circle / dot.radiowaves / arrow.triangle.2.circlepath / exclamationmark.triangle.
  - `tint(for:)` — returns existing DesignTokens.positive / .label2 / .accentText / .negative (zero new colors).
  - `relativeLastSynced(_:now:)` — "Never synced" / "Just now" (<60s) / named relative string.
  - `mergeSummary(_:)` — nil → nil, zero-activity → "Nothing new — already in sync", else non-zero components joined ("3 added · 2 updated · 1 removed").
- `SyncStatusPresentationTests` (Swift Testing) — 12 tests covering every behavior bullet, all PASS.

### Task 2 — SyncStatusView + Settings entry
- `SyncStatusView` (`@Environment(SyncCoordinator.self)`): neumorphic `.raised` status card (status symbol in tint + label, connected-peer line "Connected to <name>" / "No phone nearby", relative last-synced wrapped in a 30s `TimelineView`), merge-results row, accent `NeuPrimaryButtonStyle` "Sync Now" button (calls `coordinator.syncNow()`, disabled while `.syncing`), foreground-only footer caption that appends the Local-Network privacy hint when an error implicates it.
- Settings Data section: `NavigationLink(destination: SyncStatusView())` row (icon `arrow.triangle.2.circlepath`, glanceable last-synced trailing text); SettingsView gains `@Environment(SyncCoordinator.self)`.
- Verified light + dark screenshots of the Sync screen (via new `-openSync` DEBUG hook) — neumorphic card + accent CTA render correctly in both themes, no clipping, legible tokens.

## Verification

- `SyncStatusPresentationTests` — all PASS.
- Full suite — `** TEST SUCCEEDED **`, including `DarkBitIdentityTests` (no token drift).
- Acceptance: `grep -c 'Color.adaptive\|Color(hex'` on SyncStatusView.swift = 0; `grep -c 'SyncStatusView'` in SettingsView.swift = 1.
- Light + dark screenshots captured and self-reviewed.

## Deviations from Plan

**[Rule 2 — missing critical functionality] Added a DEBUG `-openSync` launch-arg screenshot hook to SettingsView.**
- Found during: Task 2 (visual self-verify loop).
- Issue: The Sync screen is a navigation push unreachable via `-startTab`, and simctl has no tap/scroll primitive — the plan's mandated light+dark self-verify of the destination screen was otherwise impossible to automate.
- Fix: Added a `#if DEBUG` `-openSync` push hook mirroring the existing `OverviewView` `-openAnalytics` convention (DEBUG-only, zero release impact).
- Files modified: MyHomeApp/Features/Settings/SettingsView.swift
- Verification: light + dark Sync screenshots captured; full suite still green.
- Commit: Task 2 feat commit.

**Total deviations:** 1 auto-added (DEBUG-only tooling). **Impact:** none on shipped behavior.

## Requirements

- **SYNC-04 → Complete.** Auto-sync transport/coordinator (19-01/19-02) plus this plan's manual "Sync Now" UI wired to `coordinator.syncNow()` deliver the full requirement (auto-sync + always-works manual fallback).
- **SYNC-05 → still Pending.** This plan ships only SYNC-05's sync-surface half (last-synced time, live status, clear affordance). The "bootstrap this phone" first-install seeding half is Plan 19-04.

## Known Stubs

None — the surface reads live `SyncStatusStore` state through the coordinator; no hardcoded/placeholder data.

## Next

Ready for 19-04 (Multipeer bootstrap / first-install seeding — completes SYNC-05).


## Self-Check: PASSED

- Created files exist on disk (SyncStatusView.swift, SyncStatusPresentationTests.swift, 19-03-SUMMARY.md).
- Commits present: da252ba (test), 80e352a (feat mapper), 0ae646b (feat view).
- Full suite green including DarkBitIdentityTests; presentation tests all pass.
