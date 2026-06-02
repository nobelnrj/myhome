import Foundation

// MARK: - GmailFetchPort

/// Protocol seam that abstracts Gmail API calls for email retrieval and profile.
/// Mirrors GmailAuthPort pattern (D6-23). Injected into GmailSyncController.
/// The test double (SpyGmailFetch) lives in MyHomeTests/Support/SpyGmailFetch.swift.
public protocol GmailFetchPort: Sendable {
    func getProfile(accessToken: String) async throws -> GmailProfile
    func listMessageIDs(accessToken: String, q: String, maxResults: Int) async throws -> [String]
    func getRawMessage(accessToken: String, messageID: String) async throws -> String
}

// MARK: - GmailProfile

public struct GmailProfile: Decodable, Sendable {
    public let emailAddress: String

    public init(emailAddress: String) {
        self.emailAddress = emailAddress
    }
}

// MARK: - GmailFetchError

/// UI-facing error states for Gmail API fetch operations.
///
/// Mirrors GmailAuthError's wrapping style (D6-18/19).
public enum GmailFetchError: Error, Sendable {
    /// A network-level error occurred during the request.
    case networkError(Error)
    /// The JSON response could not be decoded into the expected type.
    case decodingError
    /// The server returned a non-2xx HTTP status code.
    case httpError(Int)
}

// MARK: - SystemGmailFetch

/// Production conformer that wraps URLSession for Gmail REST API calls.
///
/// Stubbed for plan 01 scaffold — real network calls are implemented in plan 05
/// against the Gmail REST endpoints. All methods currently throw or fatalError
/// to allow the project to compile while the interface is locked.
///
/// D6-23: Wrapped behind GmailFetchPort protocol seam (mirrors GmailAuthPort).
public final class SystemGmailFetch: GmailFetchPort, @unchecked Sendable {

    public init() {}

    /// Fetches the Gmail profile for the authenticated user.
    /// Stub — plan 05 implements against https://gmail.googleapis.com/gmail/v1/users/me/profile
    public func getProfile(accessToken: String) async throws -> GmailProfile {
        // plan 05: GET https://gmail.googleapis.com/gmail/v1/users/me/profile
        // Authorization: Bearer {accessToken}
        throw GmailFetchError.networkError(
            NSError(domain: "SystemGmailFetch", code: -1,
                    userInfo: [NSLocalizedDescriptionKey: "unimplemented — plan 05"])
        )
    }

    /// Lists message IDs matching a Gmail search query.
    /// Stub — plan 05 implements against https://gmail.googleapis.com/gmail/v1/users/me/messages
    public func listMessageIDs(accessToken: String, q: String, maxResults: Int) async throws -> [String] {
        // plan 05: GET https://gmail.googleapis.com/gmail/v1/users/me/messages?q={q}&maxResults={n}
        // Authorization: Bearer {accessToken}
        throw GmailFetchError.networkError(
            NSError(domain: "SystemGmailFetch", code: -1,
                    userInfo: [NSLocalizedDescriptionKey: "unimplemented — plan 05"])
        )
    }

    /// Fetches the raw RFC 2822 email body for a given message ID.
    /// Stub — plan 05 implements against https://gmail.googleapis.com/gmail/v1/users/me/messages/{id}?format=raw
    public func getRawMessage(accessToken: String, messageID: String) async throws -> String {
        // plan 05: GET https://gmail.googleapis.com/gmail/v1/users/me/messages/{messageID}?format=raw
        // Authorization: Bearer {accessToken}
        throw GmailFetchError.networkError(
            NSError(domain: "SystemGmailFetch", code: -1,
                    userInfo: [NSLocalizedDescriptionKey: "unimplemented — plan 05"])
        )
    }
}
