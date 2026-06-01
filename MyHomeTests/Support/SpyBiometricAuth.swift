import Testing
import LocalAuthentication
@testable import MyHome

// ---------------------------------------------------------------------------
// SpyBiometricAuth — in-memory BiometricAuthPort test double.
//
// BiometricAuthPort is defined in MyHomeApp/Security/BiometricAuthPort.swift
// (production file, plan 05-01). This file provides the test double only.
//
// Mirrors SpyCenter.swift exactly in structure and naming conventions.
// ---------------------------------------------------------------------------

/// In-memory spy that returns canned (Bool, Error?) pairs so unit tests can
/// exercise every LAError path without touching the OS biometric stack.
public final class SpyBiometricAuth: BiometricAuthPort, @unchecked Sendable {

    // MARK: - Settable stubs

    /// Controls the return value of evaluate(_:reason:).
    public var evaluateResult: (Bool, Error?) = (true, nil)

    /// Controls the return value of canEvaluate(_:).
    public var canEvaluateResult: (Bool, Error?) = (true, nil)

    // MARK: - Recorded calls

    /// All policies passed to evaluate(_:reason:), in call order.
    public private(set) var evaluateCalls: [LAPolicy] = []

    /// All policies passed to canEvaluate(_:), in call order.
    public private(set) var canEvaluateCalls: [LAPolicy] = []

    public init() {}

    // MARK: - BiometricAuthPort

    public func evaluate(_ policy: LAPolicy, reason: String) async -> (Bool, Error?) {
        evaluateCalls.append(policy)
        return evaluateResult
    }

    public func canEvaluate(_ policy: LAPolicy) -> (Bool, Error?) {
        canEvaluateCalls.append(policy)
        return canEvaluateResult
    }

    // MARK: - Reset

    /// Clears all recorded state (useful between tests if the same SpyBiometricAuth is reused).
    public func reset() {
        evaluateCalls = []
        canEvaluateCalls = []
    }
}
