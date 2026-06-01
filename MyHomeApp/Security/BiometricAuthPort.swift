import Foundation
import LocalAuthentication

// MARK: - BiometricAuthPort

/// Protocol seam that abstracts the two LAContext operations required by LockController.
/// Injecting this protocol lets unit tests run without touching the OS biometric stack
/// (SpyBiometricAuth in MyHomeTests).
///
/// NOTE: This protocol is defined here for the production conformer.
/// The test double (SpyBiometricAuth) in MyHomeTests/Support/SpyBiometricAuth.swift also conforms.
/// SpyBiometricAuth.swift declares `@testable import MyHome` — the protocol must be public.
public protocol BiometricAuthPort: Sendable {
    /// Evaluates the given policy and returns (success, error).
    /// Caller maps LAError to action; never throws.
    func evaluate(_ policy: LAPolicy, reason: String) async -> (Bool, Error?)
    /// Returns whether the policy can be evaluated right now.
    /// Sets error if not (e.g. passcodeNotSet fires from canEvaluatePolicy, not evaluatePolicy).
    func canEvaluate(_ policy: LAPolicy) -> (Bool, Error?)
}

// MARK: - SystemBiometricAuth

/// Production conformer that wraps LAContext.
///
/// This is the only type in the lock subsystem that touches the OS biometric stack.
/// All unit tests inject SpyBiometricAuth instead.
///
/// A fresh LAContext() is created inside each method — LAContext is single-use per evaluation
/// (Pitfall 2: reusing a context across calls causes silent failures on the second attempt).
public struct SystemBiometricAuth: BiometricAuthPort, Sendable {

    public init() {}

    public func evaluate(_ policy: LAPolicy, reason: String) async -> (Bool, Error?) {
        let context = LAContext()   // fresh per call — avoids Pitfall 2
        do {
            let ok = try await context.evaluatePolicy(policy, localizedReason: reason)
            return (ok, nil)
        } catch {
            return (false, error)
        }
    }

    public func canEvaluate(_ policy: LAPolicy) -> (Bool, Error?) {
        let context = LAContext()
        var error: NSError?
        let ok = context.canEvaluatePolicy(policy, error: &error)
        return (ok, error)
    }
}
