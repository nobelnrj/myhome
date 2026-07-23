import Foundation
import SwiftUI
import LocalAuthentication

// MARK: - LockAuthError

/// UI-facing lock error states mapped from LAError.
/// Each case maps to a recoverable action — never a dead end (SEC-02, D5-06).
public enum LockAuthError: Equatable {
    /// .authenticationFailed — "Authentication failed. Try again."
    case failed
    /// .biometryLockout — "Too many attempts. Use your device passcode."
    case biometryLocked
    /// .passcodeNotSet from canEvaluatePolicy — hard-block with guidance to set a passcode (D5-05).
    case noPasscode
    /// Unrecognized LAError — generic retry.
    case unknown
}

// MARK: - LockController

/// Observable gate-state controller for the Face ID lock feature.
///
/// Owned by RootView via `@State private var lockController = LockController()`.
/// Wraps `BiometricAuthPort` (defaulting to `SystemBiometricAuth`) for full unit testability
/// of every LAError path — including `.passcodeNotSet`, `.biometryLockout`, and `.systemCancel`
/// which the simulator cannot trigger natively.
///
/// Grace period: cold launch with lockEnabled always locks (D5-01). Foreground after > 180s
/// re-locks; foreground within 180s does not. A `now` closure is injectable for deterministic
/// testing without real sleeps.
@MainActor
@Observable
final class LockController {

    // MARK: - Persistent state (App Group UserDefaults)

    /// Whether the Face ID gate is enabled. Backed by App Group UserDefaults.
    /// Falls back to `.standard` when the suite is not available (simulator / free provisioning).
    var lockEnabled: Bool {
        get { defaults.bool(forKey: "lockEnabled") }
        set { defaults.set(newValue, forKey: "lockEnabled") }
    }

    // MARK: - Runtime state

    /// Whether the app content is currently locked (auth required).
    var isLocked: Bool = false

    /// Whether the privacy blur is active (app in background or inactive).
    var isBlurred: Bool = false

    /// The current UI-facing error after a failed authentication attempt, or nil.
    var authError: LockAuthError? = nil

    // MARK: - Grace period

    private var backgroundedAt: Date? = nil
    private let gracePeriod: TimeInterval = 180   // D5-01: 180s constant

    // MARK: - Dependencies

    private let auth: any BiometricAuthPort
    /// Provides the current time; injectable for deterministic grace-period tests.
    private let now: () -> Date
    /// Resolved once at init — consistent store for all reads and writes (CR-02).
    private let defaults: UserDefaults

    // MARK: - Init

    /// Creates a LockController with an injected auth port and optional time provider.
    /// - Parameters:
    ///   - auth: `BiometricAuthPort` conformer; defaults to `SystemBiometricAuth()` in production.
    ///   - now: Time provider; defaults to `Date.init` in production. Injectable for tests.
    init(auth: any BiometricAuthPort = SystemBiometricAuth(), now: @escaping () -> Date = Date.init) {
        self.auth = auth
        self.now = now
        // Resolve the App Group suite once — consistent store across all reads/writes (CR-02).
        self.defaults = UserDefaults(suiteName: "group.com.reojacob.myhome") ?? .standard
        // Cold launch: if lock is enabled, start locked (D5-01, Pitfall 4)
        if defaults.bool(forKey: "lockEnabled") { isLocked = true }
    }

    // MARK: - Scene phase hook (called from RootView .onChange)

    /// Call from `RootView.onChange(of: scenePhase)` to drive blur and grace-period re-lock.
    func scenePhaseChanged(_ phase: ScenePhase) {
        switch phase {
        case .active:
            isBlurred = false
            if lockEnabled, let bg = backgroundedAt {
                let elapsed = now().timeIntervalSince(bg)
                if elapsed > gracePeriod {
                    isLocked = true
                }
                backgroundedAt = nil
            }
        case .inactive, .background:
            // Blur on both inactive and background — iOS takes the app-switcher snapshot during
            // .inactive, before .background. Watching only .background is too late (Pitfall 1).
            isBlurred = true
            if backgroundedAt == nil {
                backgroundedAt = now()
            }
        @unknown default:
            break
        }
    }

    // MARK: - Test seam for grace period

    #if DEBUG
    /// Sets the backgroundedAt timestamp to a specific date.
    /// Used in unit tests to drive grace-period math without real elapsed time.
    /// Compiled only in DEBUG builds — compiles away in release (WR-02).
    func markBackgrounded(at date: Date) {
        backgroundedAt = date
    }
    #endif

    // MARK: - Authentication

    /// Attempts to authenticate the user via the injected BiometricAuthPort.
    ///
    /// Order of operations:
    /// 1. Call `canEvaluate` first — `.passcodeNotSet` is only detectable here (D5-05, Pitfall).
    /// 2. If canEvaluate fails with `.passcodeNotSet`, set `.noPasscode` hard-block and return.
    /// 3. Otherwise call `evaluate`. On success, clear isLocked. On failure, map the error.
    func authenticate() async {
        authError = nil

        // Step 1: Check if evaluation is possible (detects .passcodeNotSet — D5-05)
        let (canEval, canErr) = auth.canEvaluate(.deviceOwnerAuthentication)
        if !canEval {
            if let laErr = canErr as? LAError, laErr.code == .passcodeNotSet {
                authError = .noPasscode   // D5-05: hard-block with guidance
            } else {
                authError = .unknown      // CR-03: all other canEvaluate failures show guidance (D5-06)
            }
            return
        }

        // Step 2: Evaluate — this is the actual Face ID / passcode prompt
        let (success, error) = await auth.evaluate(
            .deviceOwnerAuthentication,
            reason: "Unlock MyHome to access your data."
        )
        if success {
            isLocked = false
            authError = nil
        } else {
            authError = mapError(error)   // D5-06: every error maps to a recoverable action
        }
    }

    // MARK: - Enable / Disable lock (D5-07a / D5-07b)

    /// Enables the Face ID lock gate after authenticating the user (D5-07a).
    /// Applies the same canEvaluate preflight as authenticate() to enforce D5-05.
    /// Only sets lockEnabled=true if authentication succeeds.
    func enableLock() async {
        // Preflight: enforce D5-05 (no-passcode escape path) — mirrors authenticate() (CR-01)
        let (canEval, canErr) = auth.canEvaluate(.deviceOwnerAuthentication)
        guard canEval else {
            if let laErr = canErr as? LAError, laErr.code == .passcodeNotSet {
                authError = .noPasscode
            } else {
                authError = .unknown
            }
            return
        }
        let (success, _) = await auth.evaluate(
            .deviceOwnerAuthentication,
            reason: "Verify your identity to enable the lock."
        )
        if success { lockEnabled = true }
    }

    /// Disables the Face ID lock gate after authenticating the user (D5-07b).
    /// Applies the same canEvaluate preflight as authenticate() to enforce D5-05.
    /// Only sets lockEnabled=false if authentication succeeds.
    func disableLock() async {
        // Preflight: enforce D5-05 (no-passcode escape path) — mirrors authenticate() (CR-01)
        let (canEval, canErr) = auth.canEvaluate(.deviceOwnerAuthentication)
        guard canEval else {
            if let laErr = canErr as? LAError, laErr.code == .passcodeNotSet {
                authError = .noPasscode
            } else {
                authError = .unknown
            }
            return
        }
        let (success, _) = await auth.evaluate(
            .deviceOwnerAuthentication,
            reason: "Verify your identity to disable the lock."
        )
        if success { lockEnabled = false }
    }

    // MARK: - Error mapping (SEC-02)

    /// Maps a raw LAError to a LockAuthError UI state.
    /// Every case returns a recoverable state (nil = stay on screen, no message; non-nil = show text).
    /// Never produces a dead end — SEC-02 / D5-06.
    private func mapError(_ error: Error?) -> LockAuthError? {
        guard let laError = error as? LAError else { return .unknown }
        switch laError.code {
        case .userCancel, .appCancel, .systemCancel:
            return nil         // User cancelled — stay on screen, no error message (D5-06)
        case .authenticationFailed:
            return .failed     // "Authentication failed. Try again."
        case .userFallback:
            return nil         // OS passcode prompt followed; no special UI needed
        case .biometryLockout:
            return .biometryLocked   // "Too many attempts. Use your device passcode."
        case .biometryNotAvailable, .biometryNotEnrolled:
            return nil         // deviceOwnerAuthentication auto-falls to passcode; silent (D5-04)
        case .passcodeNotSet:
            return .noPasscode  // Should be caught by canEvaluate path; handled defensively here
        default:
            return .unknown
        }
    }
}
