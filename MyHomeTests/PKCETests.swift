import Testing
import Foundation
@testable import MyHome

// Requirements: ING-01 (custom PKCE generation)
// Threat ref: T-6-PKCE (verifier randomness, challenge = SHA256(verifier))
// Validation command: xcodebuild test ... -only-testing:MyHomeTests/PKCETests
// Plan 06-01 — RED phase: tests compile only after PKCE struct exists (Task 1).
// Tests FAIL RED because PKCE.generate() is a fatalError stub.

/// PKCETests — unit tests for the PKCE value type.
///
/// ING-01: Custom PKCE — generate code_verifier (43–128 chars), compute SHA256
///         code_challenge, base64url-encode both.
struct PKCETests {

    // MARK: - ING-01: Verifier length

    @Test("verifierLength: generated verifier is 43-128 characters — ING-01")
    func verifierLength() throws {
        let pkce = try PKCE.generate()
        #expect(pkce.verifier.count >= 43, "PKCE verifier must be at least 43 characters (RFC 7636)")
        #expect(pkce.verifier.count <= 128, "PKCE verifier must be at most 128 characters (RFC 7636)")
    }

    // MARK: - ING-01: Challenge is non-empty and different from verifier

    @Test("challengeIsNonEmptyAndDiffersFromVerifier: challenge != verifier and challenge is non-empty — ING-01")
    func challengeIsNonEmptyAndDiffersFromVerifier() throws {
        let pkce = try PKCE.generate()
        #expect(!pkce.challenge.isEmpty, "PKCE challenge must not be empty")
        #expect(pkce.challenge != pkce.verifier, "PKCE challenge must differ from verifier (it is SHA256(verifier))")
    }

    // MARK: - ING-01: Two calls yield different verifiers

    @Test("twoCallsYieldDifferentVerifiers: generate() twice produces different verifiers — ING-01")
    func twoCallsYieldDifferentVerifiers() throws {
        let pkce1 = try PKCE.generate()
        let pkce2 = try PKCE.generate()
        #expect(pkce1.verifier != pkce2.verifier, "Two PKCE.generate() calls must produce different verifiers (random bytes per call)")
    }
}
