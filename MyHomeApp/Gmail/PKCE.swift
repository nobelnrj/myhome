import Foundation

// MARK: - PKCEError

/// Errors that can occur during PKCE generation.
public enum PKCEError: Error, Sendable {
    /// The system's random-byte generator failed.
    case failedToGenerateRandomBytes
}

// MARK: - PKCE

/// Proof Key for Code Exchange (RFC 7636) value type.
///
/// D6-02: Custom PKCE — generate `code_verifier` (43–128 chars), compute SHA256 `code_challenge`,
/// base64url-encode both.
///
/// Wave 0 stub: `generate()` is intentionally unimplemented so tests that rely on real
/// PKCE math fail RED. Plan 02 will implement the CryptoKit SHA256 path.
public struct PKCE: Sendable {
    /// The raw code verifier string (base64url-encoded random bytes, 43–128 characters).
    public let verifier: String
    /// The S256 code challenge (base64url-encoded SHA256 hash of the verifier).
    public let challenge: String

    /// Generates a new PKCE pair.
    ///
    /// - Throws: `PKCEError.failedToGenerateRandomBytes` if the OS CSPRNG fails.
    /// - Note: **STUB** — not implemented until plan 02. Calling this in tests produces RED.
    public static func generate() throws -> PKCE {
        fatalError("PKCE.generate() is not yet implemented — plan 02 will provide the CryptoKit implementation")
    }
}
