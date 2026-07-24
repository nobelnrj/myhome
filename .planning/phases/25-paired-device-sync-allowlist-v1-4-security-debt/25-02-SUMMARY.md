---
phase: 25-paired-device-sync-allowlist-v1-4-security-debt
plan: 02
subsystem: sync
tags: [security, multipeer, allowlist, pairing, information-disclosure]
requires:
  - PeerAllowlistPolicy.shouldConnect (25-01)
  - InstallIdentity.current (25-01)
  - PairedDevicesStore / PairedDevice (25-01)
provides:
  - SyncTransportEvent.pairingCandidate (distinct pre-trust event)
  - SyncTransport allowlist/isPairingMode/beginPairing/endPairing surface
  - PeerAllowlistPolicy.decodeIID (pure defensive invite-context decode)
  - MultipeerSyncTransport dual-gate enforcement (foundPeer + didReceiveInvitation)
  - SyncCoordinator .pairingCandidate no-push + applyAllowlist/beginPairing/endPairing forwarders + onPairingCandidate hook
affects:
  - MyHomeApp/Sync/SyncTransport.swift
  - MyHomeApp/Sync/MultipeerSyncTransport.swift
  - MyHomeApp/Sync/SyncCoordinator.swift
tech-stack:
  added: []
  patterns: [pure-defensive-decode, distinct-event-over-guard, additive-gate]
key-files:
  created: []
  modified:
    - MyHomeApp/Sync/SyncTransport.swift
    - MyHomeApp/Sync/MultipeerSyncTransport.swift
    - MyHomeApp/Sync/SyncCoordinator.swift
    - MyHomeTests/SyncCoordinatorTests.swift
    - MyHomeTests/SyncTransportTests.swift
decisions:
  - "Un-allowlisted pairing sessions surface as a DISTINCT .pairingCandidate event (not a guard on .connected) so SyncCoordinator's contract is unchanged and the auto-push can never fire at an untrusted peer."
  - "Defensive invite-context decode extracted to a PURE PeerAllowlistPolicy.decodeIID(_:) helper (nil/non-UTF8/empty/>64-byte ⇒ nil) so untrusted LAN input is unit-tested directly, not left as structural-grep only."
  - "The allowlist gate is ADDITIVE to the existing PeerInvitePolicy.shouldInvite dual-connect tie-break — both must pass before an invite is sent (locked decision preserved)."
  - "peerIIDByName map (displayName → claimed iid, learned pre-session from discoveryInfo/context, cleared in stop()) lets .connected distinguish a trusted peer from a pairing candidate without threading iid onto every event."
metrics:
  tasks: 2
  files_created: 0
  files_modified: 5
  completed: 2026-07-25
---

# Phase 25 Plan 02: MultipeerConnectivity Allowlist Enforcement + Pairing-Candidate Event Summary

Wired the Plan 01 pure allowlist gate into both MultipeerConnectivity trust callbacks so an un-allowlisted peer can never form a session, and closed the pairing-window auto-push hole with a distinct `.pairingCandidate` transport event — the actual security fix for #43 (SYNC-06), with the information-disclosure guards (defensive untrusted-input decode, allowlist off the wire) and no regression to the Phase 18/19 merge/LWW engine.

## What Was Built

**Task 1 — dual MC gate + `.pairingCandidate` emission (commit d7b1995):**
- `SyncTransport.swift`: added `SyncTransportEvent.pairingCandidate(peerName:peerIID:)`; extended the `SyncTransport` protocol with `var allowlist: Set<String>`, `var isPairingMode: Bool`, `func beginPairing()`, `func endPairing()`; added the pure `PeerAllowlistPolicy.decodeIID(_:) -> String?` (nil/non-UTF8/whitespace-only/`>64`-byte ⇒ `nil`, never force-unwraps).
- `MultipeerSyncTransport.swift`: advertiser now built with `discoveryInfo: ["iid": InstallIdentity.current()]` (kept tiny — Pitfall 2). `browser(foundPeer:)` records the peer's claimed `iid` and requires `PeerAllowlistPolicy.shouldConnect(...)` **in addition to** the existing `shouldInvite` tie-break before inviting, and passes `withContext: Data(InstallIdentity.current().utf8)`. `advertiser(didReceiveInvitationFromPeer:)` defensively decodes the context via `decodeIID`, gates on `shouldConnect`, and calls `invitationHandler(ok, ok ? session : nil)`. `session(didChange: .connected)` emits `.pairingCandidate` instead of `.connected` when the peer's iid is present, `isPairingMode`, and not in the allowlist. `beginPairing()`/`endPairing()` implement a 2-minute `Task.sleep` auto-cancel that also tears down any candidate session. `stop()` clears the learned-iid map. The cert callback is documented as NOT an identity gate (Pitfall 5).
- `SyncCoordinator.swift`: added the `.pairingCandidate` switch arm (no `.syncing`, no `pushLocalSnapshot`) + the `onPairingCandidate` hook — required for the module to compile once the enum case existed.

**Task 2 — coordinator forwarders + tests (commit 4e47bee):**
- `SyncCoordinator.swift`: thin `applyAllowlist(_:)`, `beginPairing()`, `endPairing()` forwarders so Plan 03's UI drives the transport without touching it directly.
- `SyncCoordinatorTests.swift`: `FakeSyncTransport` now conforms to the extended protocol (`allowlist`, `isPairingMode`, `beginPairing`/`endPairing`) and exposes `simulatePairingCandidate(peerName:peerIID:)`. New tests: `pairingCandidateNeverPushesSnapshot` (no `.snapshot` in `sentEnvelopes`, status never `.syncing`, candidate forwarded to hook), `trustedConnectedStillPushes` (SC-3 guard), and `allowlistNeverAppearsInSnapshot` (SC-5 — persists two `PairedDevice`s, exports a populated snapshot, asserts neither installID nor friendlyName appears in the bytes or any decoded field).
- `SyncTransportTests.swift`: five `decodeIID` unit tests (nil, valid UUID, whitespace-trim/empty, non-UTF8 garbage, oversized `>64` bytes).

## Verification

- App target builds clean for the iPhone 17 Pro Max simulator (`560D9A16-…`, Xcode 26.5).
- Task 1 acceptance greps: `case pairingCandidate` present; `discoveryInfo: ["iid"` present; `PeerAllowlistPolicy.shouldConnect` count = 2 (both gates); `withContext: Data(` present.
- Task 2 acceptance grep: `case .pairingCandidate` present in `SyncCoordinator.swift`.
- `SyncCoordinatorTests` — **TEST SUCCEEDED**, including the new pairing-hole + SC-5 tests AND the pre-existing loopback/echo/LWW/`expensesNeverCrossTheWire` tests (SC-3 no regression proven).
- `SyncTransportTests` — all green including the five new `decodeIID` cases and the 25-01 `shouldConnect`/`PairingCode`/`InstallIdentity` suite.

## Deviations from Plan

### Auto-added (Rule 2 — required by the plan's own critical constraints)

**1. [Rule 2 - Critical functionality] Added `decodeIID` unit tests to `SyncTransportTests.swift`**
- **Found during:** Task 1 (helper creation) / Task 2 (test placement).
- **Issue:** The plan's `<critical_constraints>` mandate a PURE `PeerAllowlistPolicy.decodeIID(_:)` helper "UNIT-TESTED directly with nil/garbage/oversized input — do not leave this as structural-grep only", but `files_modified` lists only `SyncCoordinatorTests.swift`.
- **Fix:** Placed the five `decodeIID` tests in `SyncTransportTests.swift`, the established home for `PeerAllowlistPolicy` pure-policy tests (25-01 put the `shouldConnect` matrix there). This keeps all `PeerAllowlistPolicy` coverage co-located.
- **Files modified:** MyHomeTests/SyncTransportTests.swift
- **Commit:** 4e47bee

### Task-boundary adjustment (no scope change)

**2. `SyncCoordinator.swift` split across both task commits**
- Adding `SyncTransportEvent.pairingCandidate` made `SyncCoordinator.handle(_:)`'s switch non-exhaustive, so the app target could not build at the end of Task 1 without the new arm. The `.pairingCandidate` arm + `onPairingCandidate` hook were therefore included in the Task 1 commit (compilation necessity); the thin `applyAllowlist`/`beginPairing`/`endPairing` forwarders landed with the Task 2 tests. No behavior differs from the plan; only the commit each line lands in.

## Notes for Downstream Plans

- Plan 03 (pairing UI) drives trust via `SyncCoordinator.applyAllowlist(store.allowlist)`, `beginPairing()`/`endPairing()`, and sets `onPairingCandidate` to derive `PairingCode.sixDigit(InstallIdentity.current(), peerIID)` for the "Codes match" sheet; on confirm it calls `PairedDevicesStore.add(...)` then `applyAllowlist(...)` + `endPairing()`. The next genuine reconnect then surfaces as a trusted `.connected` and the normal push runs safely.
- The transport's `allowlist` is currently only settable — nothing in this plan wires `PairedDevicesStore` into `MultipeerSyncTransport` at app bootstrap yet. Plan 03/04 must call `applyAllowlist` on start and whenever the store changes, and add the migration "paused / needs re-pair" banner (empty allowlist ∧ `lastSyncedAt≠nil`).
- The raw MC callback wiring (reading `discoveryInfo`, passing/decoding `context`, `.pairingCandidate` emission) is NOT reachable through `FakeSyncTransport` — the pure `PeerAllowlistPolicy`/`decodeIID` logic is fully unit-tested; the MC integration path itself still needs the on-device 3-device manual check (two phones pair via matching code; a seeded sim on the LAN never connects) at the phase gate.

## Self-Check: PASSED
- FOUND: MyHomeApp/Sync/SyncTransport.swift (case pairingCandidate, decodeIID, protocol surface)
- FOUND: MyHomeApp/Sync/MultipeerSyncTransport.swift (both gates, discoveryInfo iid, invite context)
- FOUND: MyHomeApp/Sync/SyncCoordinator.swift (.pairingCandidate arm, forwarders, onPairingCandidate)
- FOUND: commit d7b1995
- FOUND: commit 4e47bee
