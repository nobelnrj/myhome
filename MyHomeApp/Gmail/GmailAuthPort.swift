import Foundation
import AuthenticationServices

// MARK: - GmailAuthPort

/// Protocol seam that abstracts the three OAuth operations required by GmailSyncController.
/// Injecting this protocol lets unit tests run without touching the OS authentication stack
/// (SpyGmailAuth in MyHomeTests).
///
/// NOTE: This protocol is defined here for the production conformer.
/// The test double (SpyGmailAuth) in MyHomeTests/Support/SpyGmailAuth.swift also conforms.
/// SpyGmailAuth.swift declares `@testable import MyHome` — the protocol must be public.
///
/// D6-01: Use ASWebAuthenticationSession (no Google SignIn SDK).
/// D6-23: Wrap URLSession/OAuth behind a port/protocol (mirrors NotificationCenterPort).
public protocol GmailAuthPort: Sendable {
    /// Presents the OAuth browser and returns the authorization code on success.
    /// - Parameters:
    ///   - authURL: The full authorization URL (with PKCE challenge, state, etc.)
    ///   - callbackScheme: The custom URL scheme to register with ASWebAuthenticationSession
    /// - Returns: The authorization code extracted from the callback URL
    /// - Throws: `GmailAuthError` for cancellation, invalid callback, or missing code
    func authorize(authURL: URL, callbackScheme: String) async throws -> String

    /// Exchanges an authorization code for an access + refresh token pair.
    /// - Parameters:
    ///   - code: Authorization code returned from `authorize`
    ///   - verifier: PKCE code verifier (D6-02)
    ///   - clientID: OAuth client ID registered in Google Cloud Console
    ///   - redirectURI: Must match the redirect URI registered in Cloud Console (D6-04)
    /// - Returns: `TokenResponse` containing access_token, expires_in, refresh_token, etc.
    /// - Throws: `GmailAuthError.networkError` or `GmailAuthError.oauthError`
    func exchangeCode(_ code: String, verifier: String, clientID: String, redirectURI: String) async throws -> TokenResponse

    /// Exchanges a refresh token for a new access token.
    /// - Parameters:
    ///   - refreshToken: The stored refresh token from the initial exchange
    ///   - clientID: OAuth client ID
    /// - Returns: `RefreshResponse` containing the new access_token and expires_in
    /// - Throws: `GmailAuthError.networkError` or `GmailAuthError.oauthError`
    func refreshToken(_ refreshToken: String, clientID: String) async throws -> RefreshResponse
}

// MARK: - TokenResponse

/// Successful response from the OAuth token exchange endpoint.
///
/// D6-07: access_token stays in memory; refresh_token goes to Keychain (SEC-03).
public struct TokenResponse: Decodable, Sendable {
    public let access_token: String
    public let expires_in: Int
    public let refresh_token: String?
    public let token_type: String
    public let scope: String

    public init(access_token: String, expires_in: Int, refresh_token: String?, token_type: String, scope: String) {
        self.access_token = access_token
        self.expires_in = expires_in
        self.refresh_token = refresh_token
        self.token_type = token_type
        self.scope = scope
    }
}

// MARK: - RefreshResponse

/// Successful response from the OAuth token refresh endpoint.
public struct RefreshResponse: Decodable, Sendable {
    public let access_token: String
    public let expires_in: Int
    public let token_type: String

    public init(access_token: String, expires_in: Int, token_type: String) {
        self.access_token = access_token
        self.expires_in = expires_in
        self.token_type = token_type
    }
}

// MARK: - GmailAuthError

/// UI-facing error states for the Gmail OAuth flow.
///
/// D6-18: Network error → "Check your internet connection. [Retry]"
/// D6-19: OAuth error → display raw error message from Google (debug-friendly)
public enum GmailAuthError: Error, Sendable {
    /// User cancelled the ASWebAuthenticationSession OAuth prompt.
    case userCancelled
    /// The callback URL received from OAuth was not parseable.
    case callbackURLInvalid
    /// The callback URL contained no `code` query parameter.
    case noAuthCode
    /// A network-level error occurred during token exchange or refresh.
    case networkError(Error)
    /// The OAuth server returned an error response (e.g., invalid_grant).
    case oauthError(String)
}
