---
phase: 06-gmail-sign-in-client
plan: "01"
subsystem: gmail
tags: [tdd, scaffold, protocols, wave-0, red-phase]
dependency_graph:
  requires: []
  provides:
    - GmailAuthPort protocol seam (Wave 0 type surface)
    - KeychainPort protocol seam (Wave 0 type surface)
    - PKCE stub (plan 02 will implement real CryptoKit logic)
    - GmailSyncController stub (plan 02 will implement real OAuth logic)
    - SpyGmailAuth test double
    - SpyKeychainStore test double
    - Five RED test files: PKCETests, GmailAuthURLTests, KeychainPortTests, GmailSyncControllerTests, RelativeTimestampTests
  affects:
    - MyHome.xcodeproj/project.pbxproj (11 new files registered)
    - MyHomeApp/Support/Date+Display.swift (relativeToNow stub added)
tech_stack:
  added: []
  patterns:
    - Protocol port seam (mirrors BiometricAuthPort/NotificationCenterPort)
    - "@MainActor @Observable controller (mirrors LockController)"
    - In-memory spy test doubles (mirrors SpyBiometricAuth/SpyCenter)
    - Wave-0 Nyquist gate scaffold (fail RED, pass GREEN as plans implement)
key_files:
  created:
    - MyHomeApp/Gmail/GmailAuthPort.swift
    - MyHomeApp/Gmail/KeychainPort.swift
    - MyHomeApp/Gmail/PKCE.swift
    - MyHomeApp/Features/Gmail/GmailSyncController.swift
    - MyHomeTests/Support/SpyGmailAuth.swift
    - MyHomeTests/Support/SpyKeychainStore.swift
    - MyHomeTests/PKCETests.swift
    - MyHomeTests/GmailAuthURLTests.swift
    - MyHomeTests/KeychainPortTests.swift
    - MyHomeTests/GmailSyncControllerTests.swift
    - MyHomeTests/RelativeTimestampTests.swift
  modified:
    - MyHome.xcodeproj/project.pbxproj
    - MyHomeApp/Support/Date+Display.swift
decisions:
  - "Wave-0 stub defaults use _StubGmailAuth/_StubKeychain (private structs in GmailSyncController.swift) instead of SystemGmailAuth/SystemKeychainStore which don't exist until plan 04"
  - "Date.relativeToNow stub added to Date+Display.swift returning empty string so RelativeTimestampTests compiles RED; plan 02 will replace with real RelativeDateTimeFormatter impl"
  - "GmailAuthURLTests uses PKCE(verifier:challenge:) direct initializer since generate() is a fatalError stub; tests still fail RED because buildAuthorizationURL returns nil"
metrics:
  duration: 45
  completed: "2026-06-02"
  tasks: 2
  files: 13
---

# Phase 06 Plan 01: Gmail Wave-0 Scaffold Summary

Wave-0 Nyquist gate: 11 new files (4 production stubs + 2 test doubles + 5 RED test files) registered in pbxproj; full suite compiles; Phase 6 tests fail RED because production logic is stubbed.

## What Was Built

**Task 1 — Production compile surface (commit 6ac6842):**
- `GmailAuthPort.swift`: `public protocol GmailAuthPort: Sendable` with three async throwing methods; `TokenResponse`, `RefreshResponse`, `GmailAuthError` value types
- `KeychainPort.swift`: `public protocol KeychainPort: Sendable` with three sync throwing methods; `KeychainError` enum
- `PKCE.swift`: `struct PKCE` with `verifier`/`challenge`; `static func generate() throws -> PKCE` as `fatalError` stub; `PKCEError`
- `GmailSyncController.swift`: `@MainActor @Observable final class GmailSyncController` mirroring `LockController` exactly — App Group UserDefaults persistence, in-memory `accessToken`, derived `isConnected`/`isTokenExpired`/`needsProactiveRefresh`, injected ports via `_StubGmailAuth`/`_StubKeychain` Wave-0 defaults, `SyncStatus` enum, stub methods for all six entry points

**Task 2 — Test doubles + RED test suite + pbxproj (commit 46d7242):**
- `SpyGmailAuth.swift`: `public final class SpyGmailAuth: GmailAuthPort, @unchecked Sendable` with settable stubs and recorded calls arrays + `reset()`
- `SpyKeychainStore.swift`: `public final class SpyKeychainStore: KeychainPort, @unchecked Sendable` with in-memory dict store + error stubs + `reset()`
- `PKCETests.swift`: 3 tests covering ING-01 (verifier length, challenge differs from verifier, randomness) — all FAIL RED (fatalError stub)
- `GmailAuthURLTests.swift`: 8 tests covering ING-01 (all required auth URL query params) — all FAIL RED (buildAuthorizationURL returns nil)
- `KeychainPortTests.swift`: 5 tests covering SEC-03 (SpyKeychainStore round-trips) — PASS GREEN (spy is fully implemented)
- `RelativeTimestampTests.swift`: 3 tests covering ING-05/SET-05 (relativeToNow) — FAIL RED (stub returns "")
- `GmailSyncControllerTests.swift`: 12 tests covering ING-02/03/05/16, SET-04/05, SEC-03 — 9 FAIL RED (stub methods), 3 pass (pure derived props that don't need plan 02)
- `project.pbxproj`: all 11 files registered with PBXBuildFile + PBXFileReference + PBXGroup (G160 Gmail app group, G126 Features/Gmail group) + Sources build phase entries
- `Date+Display.swift`: `relativeToNow` stub added returning `""` so `RelativeTimestampTests` compiles

## Verification Results

- `xcodebuild build` — BUILD SUCCEEDED
- `xcodebuild test -only-testing:MyHomeTests/PKCETests -only-testing:MyHomeTests/GmailSyncControllerTests` — BUILD SUCCEEDED; tests FAIL RED as intended
- All 11 filenames appear in `project.pbxproj` (grep loop exit 0)

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 2 - Missing Functionality] Added Date.relativeToNow stub to Date+Display.swift**
- **Found during:** Task 2 — `RelativeTimestampTests.swift` references `Date.relativeToNow` which doesn't exist until plan 02
- **Issue:** Tests would fail to compile (not just fail RED) without a stub definition
- **Fix:** Added `var relativeToNow: String { return "" }` stub to `Date+Display.swift` so tests compile but fail RED
- **Files modified:** `MyHomeApp/Support/Date+Display.swift`
- **Commit:** 46d7242

**2. [Rule 2 - Missing Functionality] Wave-0 stub dependencies in GmailSyncController**
- **Found during:** Task 1 — `init` default args reference `SystemGmailAuth()`/`SystemKeychainStore()` which don't exist until plan 04
- **Fix:** Added private `_StubGmailAuth` and `_StubKeychain` structs in `GmailSyncController.swift`; these are replaced by real System* conformers in plan 04
- **Files modified:** `MyHomeApp/Features/Gmail/GmailSyncController.swift`
- **Commit:** 6ac6842

## Known Stubs

| Stub | File | Line | Reason |
|------|------|------|--------|
| `PKCE.generate()` body is `fatalError(...)` | `MyHomeApp/Gmail/PKCE.swift` | ~30 | Plan 02 implements CryptoKit SHA256 logic |
| `GmailSyncController.signIn()` sets `syncStatus = .idle` only | `MyHomeApp/Features/Gmail/GmailSyncController.swift` | ~155 | Plan 02 implements full OAuth flow |
| `GmailSyncController.sync()` is empty | `MyHomeApp/Features/Gmail/GmailSyncController.swift` | ~163 | Plan 02 implements Gmail API fetch |
| `GmailSyncController.signOut()` is empty | `MyHomeApp/Features/Gmail/GmailSyncController.swift` | ~171 | Plan 02 implements Keychain + defaults cleanup |
| `GmailSyncController.scenePhaseChanged()` is a no-op | `MyHomeApp/Features/Gmail/GmailSyncController.swift` | ~148 | Plan 02 implements token expiry check |
| `GmailSyncController.buildAuthorizationURL()` returns `nil` | `MyHomeApp/Features/Gmail/GmailSyncController.swift` | ~180 | Plan 02 implements URLComponents URL builder |
| `Date.relativeToNow` returns `""` | `MyHomeApp/Support/Date+Display.swift` | ~115 | Plan 02 implements RelativeDateTimeFormatter |
| `_StubGmailAuth` / `_StubKeychain` as default args | `MyHomeApp/Features/Gmail/GmailSyncController.swift` | ~120 | Plan 04 replaces with SystemGmailAuth/SystemKeychainStore |

## Threat Flags

No new threat surface beyond what was in the threat model. Wave 0 has no real tokens, no network calls, no real Keychain access.

## Self-Check: PASSED

Files exist:
- MyHomeApp/Gmail/GmailAuthPort.swift: FOUND
- MyHomeApp/Gmail/KeychainPort.swift: FOUND
- MyHomeApp/Gmail/PKCE.swift: FOUND
- MyHomeApp/Features/Gmail/GmailSyncController.swift: FOUND
- MyHomeTests/Support/SpyGmailAuth.swift: FOUND
- MyHomeTests/Support/SpyKeychainStore.swift: FOUND
- MyHomeTests/PKCETests.swift: FOUND
- MyHomeTests/GmailAuthURLTests.swift: FOUND
- MyHomeTests/KeychainPortTests.swift: FOUND
- MyHomeTests/GmailSyncControllerTests.swift: FOUND
- MyHomeTests/RelativeTimestampTests.swift: FOUND

Commits exist:
- 6ac6842: feat(06-01): add production compile surface
- 46d7242: test(06-01): add test doubles + five failing RED test files + pbxproj registration
