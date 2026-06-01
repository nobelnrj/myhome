---
phase: 05-face-id-gate-settings
plan: 01
subsystem: security/biometric-gate
tags: [tdd, biometrics, local-authentication, observable, unit-tests]
dependency_graph:
  requires: []
  provides:
    - BiometricAuthPort protocol + SystemBiometricAuth conformer
    - LockController @Observable gate controller
    - SpyBiometricAuth test double
    - LockStateTests full suite (12 tests, GREEN)
  affects:
    - Plan 05-02 (RootView wire-up + UI layer consumes LockController)
tech_stack:
  added:
    - LocalAuthentication.framework (import in BiometricAuthPort.swift, LockController.swift, SpyBiometricAuth.swift, LockStateTests.swift only)
  patterns:
    - BiometricAuthPort protocol-port seam (mirrors NotificationCenterPort pattern)
    - SpyBiometricAuth test double (mirrors SpyCenter pattern)
    - LockController @MainActor @Observable (mirrors Debouncer @MainActor final class pattern)
    - now-provider injectable closure for deterministic grace-period math
key_files:
  created:
    - MyHomeApp/Security/BiometricAuthPort.swift
    - MyHomeApp/Security/LockController.swift
    - MyHomeTests/Support/SpyBiometricAuth.swift
    - MyHomeTests/LockStateTests.swift
  modified:
    - MyHome.xcodeproj/project.pbxproj (added Security group + 4 files to build phases)
decisions:
  - "struct SystemBiometricAuth (not class) — stateless, creates fresh LAContext per call; matches Sendable without @unchecked"
  - "LockController marked @MainActor for Swift 6 strict concurrency safety when scenePhase .onChange mutates @Observable state (RESEARCH Pitfall 3)"
  - "now-provider injected as @escaping () -> Date closure — enables deterministic grace-period tests without real sleeps; markBackgrounded(at:) exposes the timestamp seam"
  - "canEvaluate called before evaluate in authenticate() — passcodeNotSet only detectable from canEvaluatePolicy, not evaluatePolicy (RESEARCH Pitfall/D5-05)"
  - "LAPolicy.deviceOwnerAuthentication used exclusively — never deviceOwnerAuthenticationWithBiometrics (auto-passcode fallback, SEC-02)"
  - "App Group UserDefaults suite group.com.reojacob.myhome with .standard fallback for test environments (matches ModelContainer+App.swift pattern)"
metrics:
  duration_minutes: 45
  completed_date: "2026-06-02"
  tasks_completed: 2
  files_created: 4
  files_modified: 1
---

# Phase 05 Plan 01: BiometricAuthPort + LockController (TDD) Summary

**One-liner:** Protocol-port test seam (BiometricAuthPort/SpyBiometricAuth) + @Observable @MainActor LockController with full LAError mapping, 180s grace period math, and auth-gated enable/disable — all 12 tests GREEN.

## What Was Built

**Task 1 (RED):** Created the `BiometricAuthPort` protocol and `SystemBiometricAuth` production conformer, the `SpyBiometricAuth` test double, and `LockStateTests` with 12 test cases covering all SEC-01/SEC-02/D5-01/D5-05/D5-06/D5-07 behaviors. Build failed as expected on `LockController`/`LockAuthError` not yet defined.

**Task 2 (GREEN):** Implemented `LockController` and `LockAuthError` to satisfy the test contract:
- `LockAuthError` enum: `failed`, `biometryLocked`, `noPasscode`, `unknown`
- `@MainActor @Observable final class LockController` with injected `auth: any BiometricAuthPort` and `now: () -> Date`
- Cold-launch lock: `if lockEnabled { isLocked = true }` in init
- Grace period: `scenePhaseChanged` stamps `backgroundedAt` on inactive/background; on active, compares elapsed to 180s
- `authenticate()`: calls `canEvaluate` first (catches `.passcodeNotSet` → `.noPasscode` hard-block); then `evaluate` with full `mapError` coverage
- `enableLock()` / `disableLock()`: both require auth success before mutating `lockEnabled`
- `lockEnabled`: computed property backed by `UserDefaults(suiteName: "group.com.reojacob.myhome") ?? .standard`
- `markBackgrounded(at:)`: test-injectable time-stamp seam for deterministic grace math

## Test Results

All 12 `LockStateTests` pass. Full suite (all prior tests) also green.

| Test | Requirement | Result |
|------|-------------|--------|
| lockEnabledPersists | SEC-01 | PASSED |
| coldLaunchLocked | D5-01 | PASSED |
| successUnlocks | SEC-02 | PASSED |
| passcodeNotSetHardBlock | D5-05, SEC-02 | PASSED |
| cancelKeepsLocked | D5-06 | PASSED |
| biometryLockoutMapped | D5-06 | PASSED |
| authFailedMapped | D5-06 | PASSED |
| silentFallbacksMapped | D5-04, D5-06 | PASSED |
| graceWindowNoRelock | D5-01 | PASSED |
| expiredGraceRelocks | D5-01 | PASSED |
| enableLockRequiresAuth | D5-07a | PASSED |
| enableLockAuthFailed | D5-07a | PASSED |
| disableLockRequiresAuth | D5-07b | PASSED |

## Deviations from Plan

None — plan executed exactly as written.

## Threat Coverage

| Threat | Mitigation | Test |
|--------|-----------|------|
| T-05-01: LAError DoS (infinite lock loop) | All 8 LAError cases map to recoverable action; cancel → nil | cancelKeepsLocked, silentFallbacksMapped, biometryLockoutMapped, authFailedMapped |
| T-05-02: passcodeNotSet DoS | canEvaluate check → .noPasscode hard-block-with-escape | passcodeNotSetHardBlock |
| T-05-03: EoP (cold launch bypass, grace bypass, enable without auth) | isLocked=true at init; >180s re-locks; enableLock/disableLock both gated | coldLaunchLocked, expiredGraceRelocks, enableLockRequiresAuth, enableLockAuthFailed, disableLockRequiresAuth |

## Threat Flags

None — no new network endpoints, auth paths, file access patterns, or schema changes outside the planned trust boundaries.

## Known Stubs

None — all behaviors fully implemented and verified by tests.

## TDD Gate Compliance

- RED commit: `dd29f01` — `test(05-01): add RED — BiometricAuthPort protocol, SpyBiometricAuth double, LockStateTests`
- GREEN commit: `2f0a3a8` — `feat(05-01): implement LockController + LockAuthError — LockStateTests GREEN`
- REFACTOR: not required (implementation is clean as written)

## Self-Check: PASSED

- `MyHomeApp/Security/BiometricAuthPort.swift` — EXISTS
- `MyHomeApp/Security/LockController.swift` — EXISTS
- `MyHomeTests/Support/SpyBiometricAuth.swift` — EXISTS
- `MyHomeTests/LockStateTests.swift` — EXISTS
- RED commit dd29f01 — EXISTS
- GREEN commit 2f0a3a8 — EXISTS
- All 12 LockStateTests PASSED
- Full suite PASSED
