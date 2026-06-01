---
phase: 5
slug: face-id-gate-settings
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-06-02
---

# Phase 5 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | XCTest (Xcode 26.5) |
| **Config file** | `MyHome.xcodeproj` (scheme: `MyHome`, target: `MyHomeTests`) |
| **Quick run command** | `xcodebuild test -project MyHome.xcodeproj -scheme MyHome -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:MyHomeTests/LockStateTests` |
| **Full suite command** | `xcodebuild test -project MyHome.xcodeproj -scheme MyHome -destination 'platform=iOS Simulator,name=iPhone 17'` |
| **Estimated runtime** | ~60–120 seconds (simulator boot + build dominates) |

---

## Sampling Rate

- **After every task commit:** Run the quick command for the touched test file
- **After every plan wave:** Run the full suite command
- **Before `/gsd-verify-work`:** Full suite must be green
- **Max feedback latency:** ~120 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Threat Ref | Secure Behavior | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|------------|-----------------|-----------|-------------------|-------------|--------|
| 05-01-* | 01 | 0 | SEC-02 | T-05-01 | `BiometricAuthPort` protocol + `SpyBiometricAuth` double compile and inject | unit | full suite | ❌ W0 | ⬜ pending |
| 05-01-* | 01 | 1 | SEC-02 | T-05-01 | `evaluate()` maps every LAError case (.biometryNotAvailable/.biometryNotEnrolled/.biometryLockout/.userFallback/.userCancel/.appCancel/.systemCancel/.authenticationFailed) to a recoverable action; never a dead end | unit | `-only-testing:MyHomeTests/LockStateTests` | ❌ W0 | ⬜ pending |
| 05-01-* | 01 | 1 | SEC-02 | T-05-02 | `.passcodeNotSet` from `canEvaluatePolicy` → hard-block-with-escape; re-evaluates on next foreground (no lockout) | unit | `-only-testing:MyHomeTests/LockStateTests` | ❌ W0 | ⬜ pending |
| 05-01-* | 01 | 1 | SEC-01 | T-05-03 | Grace-elapsed math: cold launch locks; foreground after >180s locks; foreground within 180s does not | unit | `-only-testing:MyHomeTests/LockStateTests` | ❌ W0 | ⬜ pending |
| 05-02-* | 02 | 2 | SET-01 | T-05-03 | Enable requires auth-success before flag flips ON; disable requires auth first; flag persists to App Group UserDefaults `group.com.reojacob.myhome` key `lockEnabled` | unit | `-only-testing:MyHomeTests/LockSettingsTests` | ❌ W0 | ⬜ pending |
| 05-02-* | 02 | 2 | SET-02, SET-03 | — | Settings hosts category-management entry (reuses `ManageCategoriesView`) and Budgets deep-link sets `selectedTab = 2` | manual | see Manual-Only | N/A | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `MyHomeTests/LockStateTests.swift` — stubs for LAError→action mapping, grace math, passcode-not-set path (SEC-01, SEC-02)
- [ ] `MyHomeTests/Support/SpyBiometricAuth.swift` — test double conforming to `BiometricAuthPort` (mirror `SpyCenter.swift`)
- [ ] `MyHomeTests/LockSettingsTests.swift` — stubs for auth-to-enable / auth-to-disable + App Group persistence (SEC-01, SET-01)
- [ ] No framework install needed — XCTest target `MyHomeTests` already exists

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Face ID prompt appears on cold launch when lock enabled | SEC-01 | Biometric prompt requires a real device/simulator UI; `LAContext` is faked in unit tests | Enable lock in Settings, kill app, relaunch → unlock screen shows, Face ID/passcode prompt fires |
| Privacy blur in app-switcher snapshot | D5-02 | App-switcher screenshot is OS-level, not unit-testable | Background the app, open app switcher → content is blurred, no data leaks |
| `.userFallback` behavior under `deviceOwnerAuthentication` | SEC-02 | [ASSUMED in research — LOW confidence] combined-policy fallback not verified without device | On a real device, trigger fallback → confirm passcode path reachable, no dead end |
| Settings → Budgets deep-link switches tabs | SET-03 | Tab switch is a UI integration behavior | Tap Budgets row in Settings → app switches to Budgets tab (tag 2) |
| Category add/rename/delete from Settings | SET-02 | UI sheet presentation + SwiftData write | Open category entry from Settings → add/rename/delete a category, confirm persisted |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 120s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
