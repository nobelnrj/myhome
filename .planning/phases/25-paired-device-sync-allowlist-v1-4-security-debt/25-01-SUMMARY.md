---
phase: 25-paired-device-sync-allowlist-v1-4-security-debt
plan: 01
subsystem: sync
tags: [security, multipeer, allowlist, cryptokit, pure-policy]
requires: []
provides:
  - InstallIdentity.current (shared sync.installID source of truth)
  - PairingCode.sixDigit (deterministic 6-digit confirmation code)
  - PeerAllowlistPolicy.shouldConnect (pure default-deny gate)
  - PairedDevicesStore / PairedDevice (local-only Codable allowlist)
affects:
  - MyHomeApp/Sync/SyncTransport.swift
  - MyHomeApp/Sync/PairedDevicesStore.swift
tech-stack:
  added: [CryptoKit (SHA-256, already in-repo via Gmail/PKCE.swift)]
  patterns: [pure-policy-type, "@MainActor @Observable UserDefaults store", default-deny]
key-files:
  created:
    - MyHomeApp/Sync/PairedDevicesStore.swift
    - MyHomeTests/PairedDevicesStoreTests.swift
  modified:
    - MyHomeApp/Sync/SyncTransport.swift
    - MyHomeTests/SyncTransportTests.swift
    - MyHome.xcodeproj/project.pbxproj
decisions:
  - "PairingCode uses CryptoKit SHA-256 over the two SORTED installIDs — never the stdlib string hasher (per-process randomized → different codes per phone). Golden vector 773804 pinned in test."
  - "sync.installID UserDefaults key reused verbatim (InstallIdentity.key) — rotating it would orphan the two already-paired phones."
  - "PairedDevicesStore is a plain @Observable UserDefaults store, deliberately NOT a @Model and not a SyncSnapshot field — structural exclusion keeps the allowlist off the wire."
  - "PeerAllowlistPolicy is default-deny: nil/empty peerIID ⇒ false; empty allowlist in normal mode ⇒ false; pairingMode relaxes only for a non-empty iid."
metrics:
  tasks: 2
  files_created: 2
  files_modified: 3
  completed: 2026-07-25
---

# Phase 25 Plan 01: Trust Primitives + Allowlist Store Summary

Deterministic CryptoKit pairing-code derivation, a pure default-deny allowlist gate, a shared installID source of truth, and a never-synced local `PairedDevicesStore` — all Foundation/CryptoKit-only pure logic, fully unit-tested with zero MultipeerConnectivity, as the contracts Plans 02/03 wire into the transport.

## What Was Built

**Task 1 — pure trust primitives (`SyncTransport.swift`, commit f4c0f8d):**
- `InstallIdentity.current(_:)` — reads/mints the `sync.installID` UUID (key unchanged from `MultipeerSyncTransport`), injectable `UserDefaults` for tests.
- `PairingCode.sixDigit(_:_:)` — `min`/`max`-sorted IDs joined as `"lo|hi"`, SHA-256'd, leading 4 digest bytes folded into a `UInt32`, `% 1_000_000` zero-padded to 6 digits. Order-independent and cross-device/cross-launch stable.
- `PeerAllowlistPolicy.shouldConnect(peerIID:allowlist:pairingMode:)` — guards non-nil/non-empty peerIID then returns `pairingMode || allowlist.contains(peerIID)`. Additive to `PeerInvitePolicy`, never a replacement.
- Extended `SyncTransportTests` with order-independence, 6-digit, golden-vector (`773804`), the full `shouldConnect` matrix, and `InstallIdentity` existing/mint cases.

**Task 2 — local-only allowlist store (`PairedDevicesStore.swift`, commit 7756a3a):**
- `PairedDevice: Codable, Equatable, Sendable { installID, friendlyName, pairedAt }`.
- `@MainActor @Observable final class PairedDevicesStore` over one `UserDefaults` key `sync.pairedDevices`: decode-on-init (failure ⇒ empty ⇒ default-deny), `isPaired`, upsert-by-installID `add`, `remove`, and `allowlist: Set<String>`. Injectable `UserDefaults` for test isolation.
- New `PairedDevicesStoreTests`: Codable round-trip, fresh-empty, add/upsert-not-duplicate, remove→isPaired-false, allowlist set, and persistence across re-instantiation.
- 4 `project.pbxproj` refs each for both new `.swift` files (this project has no synchronized groups).

## Verification

- `SyncTransportTests` — 25 tests green (iPhone 17 Pro Max sim, Xcode 26.5).
- `PairedDevicesStoreTests` — 9 tests green.
- App target links successfully, proving `PairedDevicesStore.swift` is in the app Sources phase.
- `grep -c "PairedDevicesStore.swift"` = 4; `grep -c "PairedDevicesStoreTests.swift"` = 4.
- `grep -c "Hasher\|hashValue" SyncTransport.swift` = 0 (no forbidden hasher, including comments).

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] `#expect(code.allSatisfy(\.isNumber))` failed to compile**
- **Found during:** Task 1 first test build.
- **Issue:** `Collection.allSatisfy` is `rethrows`; inside Swift Testing's `#expect` autoclosure the compiler demanded `try` ("call can throw, but it is not marked with 'try'"), failing the link.
- **Fix:** Hoisted the check to a local `let allDigits = code.allSatisfy { $0.isNumber }` then `#expect(allDigits)` in both `pairingCodeIsAlwaysSixDecimalDigits` and `pairingCodeZeroPadsShortValues`.
- **Files modified:** MyHomeTests/SyncTransportTests.swift
- **Commit:** f4c0f8d

**2. [Rule 3 - Blocking] Doc comment tripped the `Hasher`/`hashValue` == 0 acceptance grep**
- **Found during:** Task 1 acceptance check.
- **Issue:** A "NEVER use `Hasher`/`hashValue`" doc comment made `grep -c "Hasher\|hashValue"` return 1 instead of the required 0.
- **Fix:** Reworded the comment to "the Swift standard-library string hasher" — semantics preserved, grep now returns 0.
- **Files modified:** MyHomeApp/Sync/SyncTransport.swift
- **Commit:** f4c0f8d

## Notes for Downstream Plans

- Plan 02 wires `discoveryInfo["iid"]` / invite `context` in `MultipeerSyncTransport` to `PeerAllowlistPolicy.shouldConnect`, and must add the bytes-don't-contain snapshot test (T-25-04) proving `PairedDevice` never serializes.
- The `.pairingCandidate` transport event and pairing-mode flag (RESEARCH) are NOT in this plan — they land with the transport wiring.

## Self-Check: PASSED
- FOUND: MyHomeApp/Sync/PairedDevicesStore.swift
- FOUND: MyHomeTests/PairedDevicesStoreTests.swift
- FOUND: commit f4c0f8d
- FOUND: commit 7756a3a
