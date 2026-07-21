---
phase: 19-auto-sync-sync-ux-multipeer-bootstrap
plan: 04
subsystem: sync
tags: [swiftui, sync, multipeer, bootstrap, neumorphic, swift-testing, tdd]

requires:
  - phase: 18
    provides: SnapshotExporter/SnapshotImporter merge engine (idempotent, LWW, no-clobber), MergeStats
  - phase: 19-02
    provides: SyncCoordinator (@Observable, start()/syncNow()) + SyncStatusStore (PeerSyncStatus, lastSyncedAt, connectedPeerName, lastMergeStats)
  - phase: 19-03
    provides: SyncStatusView (Settings → Sync) + SyncStatusPresentation mappers
provides:
  - "BootstrapAdvisor — pure emptiness detection (6 user entities via fetchCount; Categories/RoutineCompletion/DeletionLog excluded) + one-shot shouldOfferBootstrap gate + DEBUG launch-arg suppression"
  - "SyncBootstrapView — first-run 'Set up from your other phone' sheet driving the existing snapshot exchange (start()+syncNow()), live status, completion summary, never-clobber user copy"
  - "First-run bootstrap presentation from RootView (one-shot, gated) + manual entry row on the Sync surface"
affects: [SYNC-05 complete, Phase 19 bootstrap criterion]

tech-stack:
  added: []
  patterns:
    - "Advisor pattern: pure MainActor enum that only ADVISES (fetchCount reads) — the coordinator owns all sync; bootstrap is a guided window onto the existing exchange, not a second sync path"
    - "One-shot resolved flag (UserDefaults 'sync.bootstrapResolved') written on complete/Set-up-later/swipe-dismiss; DEBUG launch-arg suppression keeps screenshot/UI-verify loops unblocked"
    - "Completion detected as a transition of statusStore.lastMergeStats away from an onAppear-captured baseline (.onChange), so the sheet is never a dead spinner"

key-files:
  created:
    - MyHomeApp/Sync/BootstrapAdvisor.swift
    - MyHomeApp/Features/Settings/SyncBootstrapView.swift
    - MyHomeTests/BootstrapAdvisorTests.swift
  modified:
    - MyHomeApp/RootView.swift
    - MyHomeApp/Features/Settings/SyncStatusView.swift
    - MyHome.xcodeproj/project.pbxproj
    - .planning/REQUIREMENTS.md

key-decisions:
  - "BootstrapAdvisor is a pure advisor (fetchCount only) — zero mergeData/exportData references; the never-clobber guarantee is proven by a loopback test over the real coordinator exchange, not by bootstrap-specific merge logic"
  - "Emptiness = zero user-entered entities (Expense/Note/Account/Asset/SIP/NetWorthSnapshot); seeded Categories + derived RoutineCompletion/DeletionLog are deliberately ignored so both phones' first-launch seed doesn't count as 'has data'"
  - "Bootstrap has NO wipe/replace path — it reuses coordinator.start()+syncNow(); a non-empty store merges (LWW), so local edits are never silently lost (T-19-11 mitigated + tested)"
  - "One-shot flag covers complete/Set-up-later/swipe-dismiss (T-19-13); swipe handled via .onDisappear guarded by a didResolve flag so it writes exactly once"
  - "SYNC-05 marked Complete — 19-03 shipped the sync-surface half, this plan ships the bootstrap/first-install seeding half"

patterns-established:
  - "Advisor + coordinator split: presentation/decision logic stays pure and unit-testable; the sheet only calls coordinator lifecycle APIs and reads the status store"

requirements-completed: [SYNC-05]

duration: 35 min
completed: 2026-07-21
---

# Phase 19 Plan 04: Multipeer Bootstrap / First-Install Seeding Summary

**A first-run "Set up from your other phone" sheet that seeds a fresh install with a full copy of the other phone's data over the EXISTING Phase-18 snapshot exchange — a pure BootstrapAdvisor gates the one-shot prompt on genuine store-emptiness, and a loopback test pins the never-clobber guarantee (a non-empty store merges via LWW, never wipes).**

## Performance

- **Duration:** ~35 min
- **Tasks:** 2/2
- **Files created:** 3 (BootstrapAdvisor.swift, SyncBootstrapView.swift, BootstrapAdvisorTests.swift)
- **Files modified:** 4 (RootView.swift, SyncStatusView.swift, project.pbxproj, REQUIREMENTS.md)

## Accomplishments

### Task 1 — BootstrapAdvisor (TDD: emptiness + gate + never-clobber proof)
- `@MainActor enum BootstrapAdvisor`:
  - `isStoreEffectivelyEmpty(context:)` — `fetchCount` across Expense/Note/Account/Asset/SIP/NetWorthSnapshot; Categories, RoutineCompletion, and DeletionLog excluded (seeded/derived).
  - `shouldOfferBootstrap(context:defaults:)` — `!resolvedFlag && isStoreEffectivelyEmpty`.
  - `markResolved(defaults:)` — persists `sync.bootstrapResolved`.
  - `isSuppressedByLaunchArguments` — DEBUG true for `-seedSampleData`/`-suppressBootstrapPrompt`, release false.
- `BootstrapAdvisorTests` (`@Suite(.serialized)`, dedicated `UserDefaults(suiteName:)`): brand-new empty, seeded-Categories-still-empty, parameterized "any user entity → non-empty", the three gate cases, and the **never-clobber loopback** (FakeSyncTransport pair + two SchemaV10 containers: B's newer note edit survives, B gains A's expense it lacked, no row deleted). All PASS.

### Task 2 — SyncBootstrapView + first-run presentation + manual entry
- `SyncBootstrapView`: neumorphic sheet (existing DesignTokens only). Header with accent phone-radiowaves icon + never-clobber copy ("Anything already on this phone is kept and merged, never deleted"); live progress driven by `SyncStatusStore` (`Looking for your other phone… / Connected to <peer> / Copying data…` — never a dead spinner); completion card (`Done — <mergeSummary>`, `Imported from <peer>`, `Start using MyHome`); error `Try Again`. `onAppear` runs `coordinator.start()` + `coordinator.syncNow()` ONLY — zero direct transport/engine calls. One-shot resolve on complete / Set-up-later / swipe-dismiss.
- `RootView`: `shouldOfferBootstrap` gate in `onAppear` (DEBUG suppression guard) → one-time `.sheet` presentation; Face ID overlay/blur modifier order untouched.
- `SyncStatusView`: quiet "Set up from your other phone…" manual-entry row → same sheet (merges on non-empty stores).

## Verification

- Task 1 automated: `BootstrapAdvisorTests` — all PASS including `bootstrapMergesNeverClobbers`.
- Task 2 automated: `grep -c 'SyncBootstrapView'` = RootView 3 / SyncStatusView 1; full suite `** TEST SUCCEEDED **` including `DarkBitIdentityTests` (no token drift).
- Acceptance: `grep -cE 'mergeData|exportData' BootstrapAdvisor.swift` = 0 (advisor only advises); emptiness uses `fetchCount` (7 call sites) and ignores Category/DeletionLog.
- Simulator self-verify (iPhone 17): fresh empty install → bootstrap sheet auto-presents (light + dark screenshots captured — neumorphic surfaces + accent icon render correctly in both themes, live "Looking for your other phone…" progress, not a dead spinner); launch with `-seedSampleData` → sheet suppressed, app opens straight to Overview.

## Deviations from Plan

None - plan executed exactly as written.

## Requirements

- **SYNC-05 → Complete.** 19-03 shipped the sync-surface half (last-synced time, live status, clear affordance); this plan ships the bootstrap/first-install seeding half (fresh install seedable from the other phone via the snapshot path; non-empty stores merge; local edits never silently lost — proven by the never-clobber loopback test). Both halves done → requirement complete.

## Known Stubs

None — SyncBootstrapView reads live `SyncStatusStore` state through the coordinator and drives the real exchange; no hardcoded/placeholder data.

## Threat Flags

None — no new network endpoints, auth paths, or schema changes. Bootstrap reuses the accepted T-19-02 household-trust link and the T-19-11 never-clobber merge (both mitigations tested).

## Next

Phase 19 bootstrap criterion delivered. Ready for the phase-level checkpoint / verification pass.

## Self-Check: PASSED

- Created files exist on disk (BootstrapAdvisor.swift, SyncBootstrapView.swift, BootstrapAdvisorTests.swift, 19-04-SUMMARY.md).
- Commits present: 7a82389 (feat Task 1 + tests), 69a8103 (feat Task 2).
- Full suite green including DarkBitIdentityTests; BootstrapAdvisorTests all pass; light+dark + suppression screenshots self-reviewed.
