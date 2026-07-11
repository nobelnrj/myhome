import Testing
import LocalAuthentication
import Foundation
@testable import MyHome

// Requirements: SEC-01 (lock flag persistence), SEC-02 (all LAError cases handled),
//               D5-01 (cold launch, grace period), D5-05 (passcode-not-set hard-block),
//               D5-06 (error → action mapping), D5-07 (enable/disable gated on auth)
// Validation command: xcodebuild test ... -only-testing:MyHomeTests/LockStateTests
// Plan 05-01 — RED phase: tests compile only after LockController + LockAuthError exist (Task 2).

/// LockStateTests — unit tests for LockController via SpyBiometricAuth seam.
///
/// SEC-01:  lockEnabled persists via App Group UserDefaults.
/// SEC-02:  Every LAError case maps to a recoverable action — never a dead end.
/// D5-01:   Cold launch with lockEnabled locks; grace window prevents re-lock; expired grace re-locks.
/// D5-05:   passcodeNotSet → hard-block-with-escape (authError = .noPasscode), isLocked stays true.
/// D5-06:   cancel errors → authError = nil; lockout/failed → mapped error states.
/// D5-07a:  enableLock() requires auth success; auth failure keeps lockEnabled false.
/// D5-07b:  disableLock() requires auth success.
///
/// `.serialized`: every test mutates the same process-global App Group `UserDefaults` key
/// (`lockEnabled`, suite `group.com.reojacob.myhome`). Swift Testing runs tests in parallel by
/// default, so without this a sibling test flips the flag between another test's reset and its
/// assertion. `LockSettingsTests` shares the same key and is likewise serialized.
@MainActor
@Suite(.serialized)
struct LockStateTests {

    // MARK: - SEC-01: Persistence

    @Test("lockEnabledPersists: setting lockEnabled writes to UserDefaults and reads back — SEC-01")
    func lockEnabledPersists() async {
        let spy = SpyBiometricAuth()
        let controller = LockController(auth: spy)

        // Reset state for test isolation
        let suite = UserDefaults(suiteName: "group.com.reojacob.myhome") ?? UserDefaults.standard
        suite.set(false, forKey: "lockEnabled")

        controller.lockEnabled = true
        let readBack = suite.bool(forKey: "lockEnabled")
        #expect(readBack == true, "lockEnabled=true should persist to UserDefaults")

        controller.lockEnabled = false
        let readBack2 = suite.bool(forKey: "lockEnabled")
        #expect(readBack2 == false, "lockEnabled=false should persist to UserDefaults")
    }

    // MARK: - D5-01: Cold launch

    @Test("coldLaunchLocked: LockController with lockEnabled=true is locked at init — D5-01")
    func coldLaunchLocked() {
        let suite = UserDefaults(suiteName: "group.com.reojacob.myhome") ?? UserDefaults.standard
        suite.set(true, forKey: "lockEnabled")
        defer { suite.set(false, forKey: "lockEnabled") }

        let spy = SpyBiometricAuth()
        let controller = LockController(auth: spy)

        #expect(controller.isLocked == true, "Cold launch with lockEnabled=true must start locked")
    }

    // MARK: - SEC-02: Success path

    @Test("successUnlocks: successful auth clears isLocked and authError — SEC-02")
    func successUnlocks() async {
        let spy = SpyBiometricAuth()
        spy.canEvaluateResult = (true, nil)
        spy.evaluateResult = (true, nil)
        let controller = LockController(auth: spy)
        controller.isLocked = true

        await controller.authenticate()

        #expect(controller.isLocked == false, "Successful auth must clear isLocked")
        #expect(controller.authError == nil, "Successful auth must clear authError")
    }

    // MARK: - D5-05: passcodeNotSet hard-block

    @Test("passcodeNotSetHardBlock: canEvaluate passcodeNotSet → authError=.noPasscode, isLocked stays true — D5-05, SEC-02")
    func passcodeNotSetHardBlock() async {
        let spy = SpyBiometricAuth()
        spy.canEvaluateResult = (false, LAError(.passcodeNotSet))
        let controller = LockController(auth: spy)
        controller.isLocked = true

        await controller.authenticate()

        #expect(controller.authError == .noPasscode, "passcodeNotSet must produce .noPasscode error")
        #expect(controller.isLocked == true, "isLocked must stay true on passcodeNotSet hard-block")
    }

    // MARK: - D5-06: Cancel errors → nil authError

    @Test("cancelKeepsLocked: userCancel/appCancel/systemCancel → authError=nil AND isLocked stays true — D5-06")
    func cancelKeepsLocked() async {
        let cancelErrors: [LAError.Code] = [.userCancel, .appCancel, .systemCancel]
        for code in cancelErrors {
            let spy = SpyBiometricAuth()
            spy.canEvaluateResult = (true, nil)
            spy.evaluateResult = (false, LAError(code))
            let controller = LockController(auth: spy)
            controller.isLocked = true

            await controller.authenticate()

            #expect(controller.authError == nil, ".\(code) must produce nil authError (silent cancel)")
            #expect(controller.isLocked == true, "isLocked must stay true after cancel — code: \(code)")
        }
    }

    // MARK: - D5-06: Biometry lockout

    @Test("biometryLockoutMapped: biometryLockout → authError=.biometryLocked — D5-06")
    func biometryLockoutMapped() async {
        let spy = SpyBiometricAuth()
        spy.canEvaluateResult = (true, nil)
        spy.evaluateResult = (false, LAError(.biometryLockout))
        let controller = LockController(auth: spy)
        controller.isLocked = true

        await controller.authenticate()

        #expect(controller.authError == .biometryLocked, "biometryLockout must map to .biometryLocked")
        #expect(controller.isLocked == true, "isLocked must stay true after biometryLockout")
    }

    // MARK: - D5-06: Authentication failed

    @Test("authFailedMapped: authenticationFailed → authError=.failed — D5-06")
    func authFailedMapped() async {
        let spy = SpyBiometricAuth()
        spy.canEvaluateResult = (true, nil)
        spy.evaluateResult = (false, LAError(.authenticationFailed))
        let controller = LockController(auth: spy)
        controller.isLocked = true

        await controller.authenticate()

        #expect(controller.authError == .failed, "authenticationFailed must map to .failed")
        #expect(controller.isLocked == true, "isLocked must stay true after authenticationFailed")
    }

    // MARK: - D5-06: Silent fallbacks (biometryNotAvailable, biometryNotEnrolled, userFallback)

    @Test("silentFallbacksMapped: biometryNotAvailable/biometryNotEnrolled/userFallback → authError=nil — D5-04, D5-06")
    func silentFallbacksMapped() async {
        let silentCodes: [LAError.Code] = [.biometryNotAvailable, .biometryNotEnrolled, .userFallback]
        for code in silentCodes {
            let spy = SpyBiometricAuth()
            spy.canEvaluateResult = (true, nil)
            spy.evaluateResult = (false, LAError(code))
            let controller = LockController(auth: spy)
            controller.isLocked = true

            await controller.authenticate()

            #expect(controller.authError == nil, ".\(code) must produce nil authError (silent fallback)")
        }
    }

    // MARK: - D5-01: Grace window — no re-lock

    @Test("graceWindowNoRelock: backgrounded then foregrounded within 180s → isLocked stays false — D5-01")
    func graceWindowNoRelock() {
        let suite = UserDefaults(suiteName: "group.com.reojacob.myhome") ?? UserDefaults.standard
        suite.set(true, forKey: "lockEnabled")
        defer { suite.set(false, forKey: "lockEnabled") }

        let spy = SpyBiometricAuth()
        // now-provider: returns a fixed base time, then 90s later (within grace)
        var callCount = 0
        let baseTime = Date(timeIntervalSinceReferenceDate: 1_000_000)
        let controller = LockController(auth: spy, now: {
            callCount += 1
            if callCount <= 2 { return baseTime }            // stamp time
            return baseTime.addingTimeInterval(90)            // 90s elapsed — within 180s grace
        })

        controller.isLocked = false  // already unlocked
        // Simulate going to background
        controller.markBackgrounded(at: baseTime)
        // Simulate foreground within grace
        controller.scenePhaseChanged(.active)

        #expect(controller.isLocked == false, "Foreground within 180s grace must NOT re-lock")
    }

    // MARK: - D5-01: Expired grace — re-lock

    @Test("expiredGraceRelocks: backgrounded then foregrounded after >180s → isLocked=true — D5-01")
    func expiredGraceRelocks() {
        let suite = UserDefaults(suiteName: "group.com.reojacob.myhome") ?? UserDefaults.standard
        suite.set(true, forKey: "lockEnabled")
        defer { suite.set(false, forKey: "lockEnabled") }

        let spy = SpyBiometricAuth()
        let baseTime = Date(timeIntervalSinceReferenceDate: 1_000_000)
        let controller = LockController(auth: spy, now: {
            baseTime.addingTimeInterval(200)   // 200s elapsed — past 180s grace
        })

        controller.isLocked = false  // already unlocked
        controller.markBackgrounded(at: baseTime)
        controller.scenePhaseChanged(.active)

        #expect(controller.isLocked == true, "Foreground after >180s grace must re-lock")
    }

    // MARK: - D5-07a: Enable lock requires auth

    @Test("enableLockRequiresAuth: enableLock() with successful auth sets lockEnabled=true — D5-07a")
    func enableLockRequiresAuth() async {
        let suite = UserDefaults(suiteName: "group.com.reojacob.myhome") ?? UserDefaults.standard
        suite.set(false, forKey: "lockEnabled")
        defer { suite.set(false, forKey: "lockEnabled") }

        let spy = SpyBiometricAuth()
        spy.evaluateResult = (true, nil)
        let controller = LockController(auth: spy)

        await controller.enableLock()

        #expect(controller.lockEnabled == true, "enableLock() with auth success must set lockEnabled=true")
    }

    @Test("enableLockAuthFailed: enableLock() with failed auth keeps lockEnabled false — D5-07a")
    func enableLockAuthFailed() async {
        let suite = UserDefaults(suiteName: "group.com.reojacob.myhome") ?? UserDefaults.standard
        suite.set(false, forKey: "lockEnabled")
        defer { suite.set(false, forKey: "lockEnabled") }

        let spy = SpyBiometricAuth()
        spy.evaluateResult = (false, LAError(.authenticationFailed))
        let controller = LockController(auth: spy)

        await controller.enableLock()

        #expect(controller.lockEnabled == false, "enableLock() with auth failure must NOT enable lock")
    }

    // MARK: - D5-07b: Disable lock requires auth

    @Test("disableLockRequiresAuth: disableLock() with successful auth sets lockEnabled=false — D5-07b")
    func disableLockRequiresAuth() async {
        let suite = UserDefaults(suiteName: "group.com.reojacob.myhome") ?? UserDefaults.standard
        suite.set(true, forKey: "lockEnabled")
        defer { suite.set(false, forKey: "lockEnabled") }

        let spy = SpyBiometricAuth()
        spy.evaluateResult = (true, nil)
        let controller = LockController(auth: spy)

        await controller.disableLock()

        #expect(controller.lockEnabled == false, "disableLock() with auth success must set lockEnabled=false")
    }
}
