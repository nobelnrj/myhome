import CryptoKit
import Foundation
import Security

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
/// Implementation uses `SecRandomCopyBytes` (CSPRNG) per RFC 7636 + CryptoKit SHA256.
/// T-06-PKCE: Never use arc4random/drand48.
public struct PKCE: Sendable {
    /// The raw code verifier string (base64url-encoded random bytes, 43–128 characters).
    public let verifier: String
    /// The S256 code challenge (base64url-encoded SHA256 hash of the verifier).
    public let challenge: String

    /// Generates a new PKCE pair using `SecRandomCopyBytes` + `CryptoKit.SHA256`.
    ///
    /// - Throws: `PKCEError.failedToGenerateRandomBytes` if the OS CSPRNG fails.
    public static func generate() throws -> PKCE {
        // 32 random bytes → 43-char base64url verifier (well within RFC 7636 43-128 range)
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
            throw PKCEError.failedToGenerateRandomBytes
        }
        let verifier = Data(bytes).base64EncodedString()
            .replacingOccurrences(of: "=", with: "")
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")

        // SHA256 hash of ASCII bytes of the verifier → base64url (S256 method)
        guard let verifierData = verifier.data(using: .ascii) else {
            throw PKCEError.failedToGenerateRandomBytes
        }
        let digest = SHA256.hash(data: verifierData)
        let challenge = Data(digest).base64EncodedString()
            .replacingOccurrences(of: "=", with: "")
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")

        return PKCE(verifier: verifier, challenge: challenge)
    }
}
