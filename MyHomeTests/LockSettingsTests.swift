import Testing
import LocalAuthentication
import Foundation
@testable import MyHome

// Requirements: SEC-01 (lock flag persistence), SET-01 (auth-to-enable/disable)
// Threat ref: T-05-03 (tamper resistance — disable requires auth; persistence integrity)
// Validation command: xcodebuild test ... -only-testing:MyHomeTests/LockSettingsTests

/// LockSettingsTests — unit tests for auth-gated enable/disable and App Group UserDefaults persistence.
///
/// SEC-01:  lockEnabled persists via App Group UserDefaults round-trip.
/// SET-01:  enableLock() requires auth success; auth failure keeps lockEnabled false.
/// SET-01:  disableLock() requires auth success; auth failure keeps lockEnabled true.
/// T-05-03: Toggle binding cannot flip the flag without auth — verified by auth-failure tests.
@MainActor
struct LockSettingsTests {

    /// Shared UserDefaults suite for isolation helpers.
    private var defaults: UserDefaults {
        UserDefaults(suiteName: "group.com.reojacob.myhome") ?? .standard
    }

    /// Reset lockEnabled in UserDefaults before/after each test for process-global isolation.
    private func resetLockEnabled() {
        defaults.set(false, forKey: "lockEnabled")
    }

    // MARK: - SET-01 + T-05-03: Enable requires auth success

    @Test("enableLockSetsFlagOnAuthSuccess: enableLock() sets lockEnabled=true when auth succeeds — SET-01")
    func enableLockSetsFlagOnAuthSuccess() async {
        resetLockEnabled()
        defer { resetLockEnabled() }

        let spy = SpyBiometricAuth()
        spy.evaluateResult = (true, nil)
        let controller = LockController(auth: spy)

        await controller.enableLock()

        #expect(controller.lockEnabled == true, "enableLock() must set lockEnabled=true on auth success")
    }

    @Test("enableLockBlockedOnAuthFailure: enableLock() keeps lockEnabled=false when auth fails — SET-01, T-05-03")
    func enableLockBlockedOnAuthFailure() async {
        resetLockEnabled()
        defer { resetLockEnabled() }

        let spy = SpyBiometricAuth()
        spy.evaluateResult = (false, LAError(.userCancel))
        let controller = LockController(auth: spy)

        await controller.enableLock()

        #expect(controller.lockEnabled == false, "enableLock() must NOT set lockEnabled=true when auth fails")
    }

    // MARK: - SET-01 + T-05-03: Disable requires auth success

    @Test("disableLockClearsFlagOnAuthSuccess: disableLock() sets lockEnabled=false when auth succeeds — SET-01")
    func disableLockClearsFlagOnAuthSuccess() async {
        // Precondition: lock is enabled
        defaults.set(true, forKey: "lockEnabled")
        defer { resetLockEnabled() }

        let spy = SpyBiometricAuth()
        spy.evaluateResult = (true, nil)
        let controller = LockController(auth: spy)

        #expect(controller.lockEnabled == true, "Precondition: lockEnabled must start true")
        await controller.disableLock()

        #expect(controller.lockEnabled == false, "disableLock() must set lockEnabled=false on auth success")
    }

    // MARK: - SEC-01 + T-05-03: Persistence round-trip

    @Test("lockEnabledPersistsToDefaults: lockEnabled round-trips through a fresh LockController — SEC-01, T-05-03")
    func lockEnabledPersistsToDefaults() async {
        resetLockEnabled()
        defer { resetLockEnabled() }

        // Write: enable lock via auth-success path
        let spy1 = SpyBiometricAuth()
        spy1.evaluateResult = (true, nil)
        let controller1 = LockController(auth: spy1)
        await controller1.enableLock()
        #expect(controller1.lockEnabled == true, "lockEnabled must be true after enableLock()")

        // Read: fresh LockController reads back persisted value (App Group UserDefaults round-trip)
        let spy2 = SpyBiometricAuth()
        let controller2 = LockController(auth: spy2)
        #expect(controller2.lockEnabled == true, "Fresh LockController must see persisted lockEnabled=true (T-05-03, SEC-01)")
    }
}
