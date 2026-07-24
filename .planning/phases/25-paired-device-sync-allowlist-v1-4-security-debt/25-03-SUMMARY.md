---
phase: 25-paired-device-sync-allowlist-v1-4-security-debt
plan: 03
subsystem: sync
tags: [security, pairing, migration, allowlist, ui, neumorphic]
requires:
  - PairedDevicesStore / PairedDevice (25-01)
  - PairingCode.sixDigit / InstallIdentity.current (25-01)
  - SyncCoordinator.applyAllowlist/beginPairing/endPairing + onPairingCandidate (25-02)
  - SyncTransportEvent.pairingCandidate (25-02)
provides:
  - SyncStatusStore.needsPairing (in-memory paused/re-pair flag)
  - SyncStatusPresentation.pairingBanner (pure SC-4 banner mapping)
  - PairDeviceView (code-confirmed pairing ceremony + paired list + unpair)
  - Launch-time migration detection + store⇄transport allowlist seeding (before start)
affects:
  - MyHomeApp/MyHomeApp.swift
  - MyHomeApp/Sync/SyncStatusStore.swift
  - MyHomeApp/Features/Settings/SyncStatusView.swift
  - MyHomeApp/Features/Settings/SettingsView.swift
tech-stack:
  added: []
  patterns: [pure-presentation-mapping, environment-injected-store, code-confirmed-trust, default-deny-migration]
key-files:
  created:
    - MyHomeApp/Features/Settings/PairDeviceView.swift
  modified:
    - MyHomeApp/Sync/SyncStatusStore.swift
    - MyHomeApp/Features/Settings/SyncStatusView.swift
    - MyHomeApp/Features/Settings/SettingsView.swift
    - MyHomeApp/MyHomeApp.swift
    - MyHomeTests/SyncStatusPresentationTests.swift
    - MyHome.xcodeproj/project.pbxproj
decisions:
  - "Allowlist is seeded into the transport gate BEFORE syncCoordinator.start() at launch (line 79 vs 103) so an un-paired peer is denied from the first advertise — no window where discovery runs with an empty gate that later fills."
  - "Migration detection lives in MyHomeApp.onAppear (empty allowlist AND lastSyncedAt != nil ⇒ needsPairing = true); it NEVER auto-adopts the connected peer. Empty allowlist ⇒ default-deny ⇒ sync is paused for free, so no separate pause flag is needed."
  - "needsPairing is in-memory only, recomputed every launch — once a device is paired the allowlist is non-empty so it recomputes to false and the banner clears without a persisted nag. A one-shot 'sync.pairingMigrationShown' UserDefaults marker is still written per the plan."
  - "PairedDevicesStore is injected via SwiftUI @Environment from MyHomeApp so both the pairing sheet and the launch wiring share one instance (single source of trust)."
  - "PairDeviceView captures the pre-trust candidate via coordinator.onPairingCandidate and only persists trust (store.add) AFTER the human 'Codes match' tap, then applyAllowlist + endPairing — trust is never granted on session formation alone."
metrics:
  tasks: 2
  files_created: 1
  files_modified: 5
  completed: 2026-07-25
---

# Phase 25 Plan 03: Pairing UI + Migration Banner Summary

The user-facing half of the paired-device allowlist: a code-confirmed pairing ceremony (Settings › Sync › Pair New Device), a paired-devices list with unpair, and a one-time guided re-pair banner for upgraded phones — with `PairedDevicesStore` now seeded into the transport gate at launch (before discovery starts) so persisted trust actually gates auto-sync and an upgraded phone stays safely paused until the user pairs.

## What Was Built

**Task 1 — needsPairing + pure banner + launch wiring (commit 2d45d12):**
- `SyncStatusStore.needsPairing: Bool` — in-memory, recomputed at launch.
- `SyncStatusPresentation.pairingBanner(needsPairing:)` — pure `true → "Pair your devices to resume sync…" / false → nil`; defines no color. Two new tests (true→non-nil/contains "pair", false→nil).
- `MyHomeApp.onAppear`: injects `@State PairedDevicesStore`, pushes `applyAllowlist(store.allowlist)` **before** `start()`, sets `needsPairing` only on the migration condition (empty allowlist AND `lastSyncedAt != nil`), writes the one-shot `sync.pairingMigrationShown` marker, and never auto-adopts. The `-seedSampleData` skip is untouched. Store injected into the SwiftUI environment.

**Task 2 — PairDeviceView + Sync surface banner/entry + pbxproj (commit 89df75d):**
- New `PairDeviceView.swift` (neumorphic, `NeuSurface`/`NeuPrimaryButtonStyle`/`DesignTokens`/`Haptics` only): "Pair New Device" → `beginPairing()`; `onPairingCandidate` captures `(peerName, peerIID)`; displays the grouped 6-digit `PairingCode.sixDigit(InstallIdentity.current(), peerIID)` ("042 178") next to the candidate name; "Codes match" → `store.add(...)` → `applyAllowlist(store.allowlist)` → `endPairing()`; "Not my device" declines without persisting; paired-devices list with relative `pairedAt` and an Unpair action (`store.remove` → `applyAllowlist`). `onDisappear` calls `endPairing()` and clears the hook.
- `SyncStatusView`: re-pair banner (rendered from `pairingBanner`) + "Pair New Device…" entry, both presenting `PairDeviceView` as a sheet.
- `SettingsView`: Sync row shows an accent warning glyph when `needsPairing`.
- 4 `project.pbxproj` refs for `PairDeviceView.swift` (`F25PDV`/`A25PDV`).

## Verification

- `SyncStatusPresentationTests` — all green including the two new SC-4 `pairingBanner` cases (iPhone 17 sim, Xcode 26.5).
- `DarkBitIdentityTests` — green (no new colors/tokens introduced).
- App target **BUILD SUCCEEDED** for the iPhone 17 simulator with the new view compiled in.
- Acceptance greps: `needsPairing` in SyncStatusStore; `func pairingBanner` in SyncStatusView; `applyAllowlist` at line 79 **before** `start()` at line 103 in MyHomeApp; `skipSyncForSeeding` preserved; `PairDeviceView.swift` exists with `PairingCode.sixDigit`; `grep -c PairDeviceView.swift project.pbxproj` = 4; `pairingBanner` wired into the surface; `store.add`/`store.remove` both followed by `applyAllowlist`.

## Deviations from Plan

None — plan executed as written. (SettingsView Sync-row badge, marked "optional" in the plan, was included.)

## Notes for Downstream Plans

- The full two-phone handshake (matching code on both, rogue seeded-sim rejection, unpair stops future connects) is the Plan 04 on-device checkpoint — the MC integration path is not reachable through `FakeSyncTransport`. This plan proves the pure banner mapping, the build, and the UI→allowlist wiring; the live ceremony is verified on real hardware in Plan 04.
- `needsPairing` clears automatically on the next launch after pairing (allowlist non-empty); it is also cleared eagerly in `PairDeviceView.confirm`.

## Self-Check: PASSED
