---
phase: 05-face-id-gate-settings
reviewed: 2026-06-02T00:00:00Z
depth: standard
files_reviewed: 8
files_reviewed_list:
  - MyHomeApp/Security/BiometricAuthPort.swift
  - MyHomeApp/Security/LockController.swift
  - MyHomeApp/Features/Settings/UnlockView.swift
  - MyHomeApp/Features/Settings/SettingsView.swift
  - MyHomeApp/RootView.swift
  - MyHomeTests/Support/SpyBiometricAuth.swift
  - MyHomeTests/LockStateTests.swift
  - MyHomeTests/LockSettingsTests.swift
findings:
  critical: 3
  warning: 4
  info: 2
  total: 9
status: issues_found
---

# Phase 05: Code Review Report

**Reviewed:** 2026-06-02  
**Depth:** standard  
**Files Reviewed:** 8  
**Status:** issues_found

## Summary

The Face ID gate implementation is structurally sound: the `@Observable`/`@State` ownership model is correct, the cold-lock invariant works, and the `canEvaluate` → `evaluate` two-step for the unlock path correctly handles `.passcodeNotSet`. However, three critical defects exist: (1) `enableLock()`/`disableLock()` skip the `canEvaluate` preflight entirely, meaning the D5-05 no-passcode escape path is unguarded on the enable/disable code paths; (2) the `defaults` property is computed rather than stored, producing non-deterministic store selection across calls; and (3) the `canEvaluate`-fails-for-non-passcode path silently returns with no authError, leaving the user staring at an Unlock button with no guidance. Four additional warnings cover the toggle flicker, a brittle test-seam leak, test isolation gaps, and a missing tamper-resistance test.

---

## Critical Issues

### CR-01: `enableLock()`/`disableLock()` bypass the `canEvaluate` / `.passcodeNotSet` preflight (D5-05 gap)

**File:** `MyHomeApp/Security/LockController.swift:155–171`  
**Issue:** `authenticate()` correctly calls `auth.canEvaluate` before `auth.evaluate` to detect `.passcodeNotSet` (D5-05). But `enableLock()` and `disableLock()` call `auth.evaluate` directly with no preflight. On a device with no passcode, `evaluate(.deviceOwnerAuthentication)` will fail with an error, `success` is `false`, and the flag is not changed — but `authError` is also never set and there is no UI feedback path wired into `enableLock`/`disableLock`. The user taps the toggle, the OS fails silently, and the toggle snaps back with zero explanation. More importantly, the D5-05 invariant ("hard-block with escape guidance") is not enforced on these two paths.

**Fix:**
```swift
func enableLock() async {
    // Respect the same canEvaluate guard as authenticate() (D5-05)
    let (canEval, canErr) = auth.canEvaluate(.deviceOwnerAuthentication)
    guard canEval else {
        if let laErr = canErr as? LAError, laErr.code == .passcodeNotSet {
            authError = .noPasscode
        }
        return
    }
    let (success, _) = await auth.evaluate(
        .deviceOwnerAuthentication,
        reason: "Verify your identity to enable the lock."
    )
    if success { lockEnabled = true }
}

// Same pattern for disableLock()
```

---

### CR-02: `defaults` is a computed property — non-deterministic store selection on every access

**File:** `MyHomeApp/Security/LockController.swift:67–69`  
**Issue:** `defaults` is computed, so `UserDefaults(suiteName: "group.com.reojacob.myhome")` is called on every read and write. The two calls inside `lockEnabled`'s getter and setter may resolve to different stores if the suite returns `nil` on one call and not the other (e.g., during a brief entitlement unavailability on first launch, or in tests without the entitlement). A write using the suite and a read falling back to `.standard` would cause `lockEnabled` to silently return the wrong value — meaning `isLocked` is not set at cold launch when it should be. This is a data-integrity bug.

**Fix:**
```swift
// Stored once at init — consistent store for all reads and writes
private let defaults: UserDefaults

init(auth: any BiometricAuthPort = SystemBiometricAuth(), now: @escaping () -> Date = Date.init) {
    self.auth = auth
    self.now = now
    self.defaults = UserDefaults(suiteName: "group.com.reojacob.myhome") ?? .standard
    // Cold launch: if lock is enabled, start locked (D5-01, Pitfall 4)
    if defaults.bool(forKey: "lockEnabled") { isLocked = true }
}
```
Remove the computed `defaults` property entirely.

---

### CR-03: `canEvaluate` failure for non-`.passcodeNotSet` errors returns silently with `authError = nil`

**File:** `MyHomeApp/Security/LockController.swift:131–136`  
**Issue:** When `canEvaluate` returns `false` and the error is anything other than `.passcodeNotSet` (e.g., `.biometryNotAvailable` before enrollment, `.notInteractive`, or a nil error), `authenticate()` returns at line 136 with `authError` still `nil`. The lock screen then shows no message — only the Unlock button — and tapping it again repeats the same outcome. The user is functionally stuck with no path to diagnosis. Per D5-06, every error must map to a recoverable action.

**Fix:**
```swift
let (canEval, canErr) = auth.canEvaluate(.deviceOwnerAuthentication)
if !canEval {
    if let laErr = canErr as? LAError, laErr.code == .passcodeNotSet {
        authError = .noPasscode
    } else {
        // All other canEvaluate failures: map to .unknown so UI shows guidance
        authError = .unknown
    }
    return
}
```

---

## Warnings

### WR-01: Toggle binding produces visible flicker when auth fails (SettingsView)

**File:** `MyHomeApp/Features/Settings/SettingsView.swift:29–40`  
**Issue:** SwiftUI `Toggle` with a custom `Binding` evaluates `get` for the initial render, then on tap it calls `set` and concurrently re-reads `get` for the next render. Because `set` dispatches an async `Task`, the toggle's visual state moves optimistically before auth completes. When auth fails (lockEnabled doesn't change), SwiftUI snaps the toggle back after the next observation cycle — producing a visible flicker. On a slow Face ID prompt this flicker is user-visible and misleading. This also violates the spirit of T-05-03: the toggle appearing to flip before auth completes is a UI lie.

**Fix:** Introduce a `@State private var isTogglingLock = false` flag, disable the toggle while auth is in flight, and update the binding's `get` to return a pending-state value, OR use a `.disabled(isTogglingLock)` modifier so the toggle never moves visually until auth completes:

```swift
@State private var isTogglingLock = false

Toggle("Face ID Lock", isOn: Binding(
    get: { lockController.lockEnabled },
    set: { newValue in
        guard !isTogglingLock else { return }
        isTogglingLock = true
        Task {
            if newValue { await lockController.enableLock() }
            else { await lockController.disableLock() }
            isTogglingLock = false
        }
    }
))
.disabled(isTogglingLock)
```

---

### WR-02: `markBackgrounded(at:)` is an internal test seam with no compile-time guard

**File:** `MyHomeApp/Security/LockController.swift:114–116`  
**Issue:** `markBackgrounded(at:)` exists solely to let tests inject a background timestamp without real time passing. It is `internal` (default), so any feature code in the module can call it and corrupt `backgroundedAt` state in production. This is a backdoor into a security-sensitive property.

**Fix:** Wrap in a `DEBUG` guard so it compiles away in release builds:

```swift
#if DEBUG
func markBackgrounded(at date: Date) {
    backgroundedAt = date
}
#endif
```
Tests already compile with `DEBUG` set.

---

### WR-03: Test isolation — several `LockStateTests` tests create `LockController` without resetting UserDefaults first

**File:** `MyHomeTests/LockStateTests.swift:61–156`  
**Issue:** `successUnlocks`, `cancelKeepsLocked`, `biometryLockoutMapped`, `authFailedMapped`, and `silentFallbacksMapped` all call `LockController(auth: spy)` without first resetting the `lockEnabled` key. If a prior test or a real device run left `lockEnabled = true` in the suite, the init sets `isLocked = true` unexpectedly — but these tests then set `controller.isLocked = true` manually anyway, so the isLocked assertions hold. The hidden risk is that `lockEnabled = true` causes `coldLaunchLocked`-style behavior that could mask failures in these tests if the implementation changes.

**Fix:** Add a `resetLockEnabled()` helper (like `LockSettingsTests` already has) and call it at the top of each test, with `defer { resetLockEnabled() }`. The pattern is already established in `LockStateTests` for the grace-period and D5-07 tests.

---

### WR-04: `SpyBiometricAuth.reset()` does not reset stub return values

**File:** `MyHomeTests/Support/SpyBiometricAuth.swift:51–54`  
**Issue:** `reset()` clears `evaluateCalls` and `canEvaluateCalls` but leaves `evaluateResult` and `canEvaluateResult` unchanged. A test that reuses a spy instance, calls `reset()`, and then relies on the defaults `(true, nil)` may be reading a dirty stub from the previous test. The method's name ("Clears all recorded state") implies a full reset.

**Fix:**
```swift
public func reset() {
    evaluateCalls = []
    canEvaluateCalls = []
    evaluateResult = (true, nil)       // restore defaults
    canEvaluateResult = (true, nil)    // restore defaults
}
```

---

## Info

### IN-01: `UnlockView` no-passcode guidance text is Face ID–specific

**File:** `MyHomeApp/Features/Settings/UnlockView.swift:47`  
**Issue:** The guidance string reads "Open the Settings app, then Face ID & Passcode". On Touch ID devices (older iPhones, iPads) this label reads "Touch ID & Passcode" in actual iOS Settings. The hardcoded string is inaccurate on those devices.

**Fix:** Detect biometry type at runtime or use a device-neutral string:

```swift
Text("Open the Settings app, then go to the passcode settings, and set a device passcode. Then return here.")
```

---

### IN-02: Missing `disableLockAuthFailure` test in `LockSettingsTests` (tamper-resistance gap)

**File:** `MyHomeTests/LockSettingsTests.swift`  
**Issue:** `LockSettingsTests` tests `enableLock` on both auth-success and auth-failure paths (SET-01, T-05-03), and tests `disableLock` on auth-success — but there is no test for `disableLock` with failed auth verifying `lockEnabled` stays `true`. The analogous tamper-resistance check exists for enable but not disable. `LockStateTests` covers this case but the `LockSettingsTests` ownership of T-05-03 is incomplete.

**Fix:** Add:
```swift
@Test("disableLockBlockedOnAuthFailure: disableLock() keeps lockEnabled=true when auth fails — SET-01, T-05-03")
func disableLockBlockedOnAuthFailure() async {
    defaults.set(true, forKey: "lockEnabled")
    defer { resetLockEnabled() }

    let spy = SpyBiometricAuth()
    spy.evaluateResult = (false, LAError(.userCancel))
    let controller = LockController(auth: spy)

    await controller.disableLock()

    #expect(controller.lockEnabled == true, "disableLock() must NOT clear lockEnabled when auth fails")
}
```

---

_Reviewed: 2026-06-02_  
_Reviewer: Claude (gsd-code-reviewer)_  
_Depth: standard_
