import Testing
import AuthenticationServices
@testable import MyHome

// ---------------------------------------------------------------------------
// SpyGmailAuth — in-memory GmailAuthPort test double.
//
// GmailAuthPort is defined in MyHomeApp/Gmail/GmailAuthPort.swift
// (production file, plan 06-01). This file provides the test double only.
//
// Mirrors SpyBiometricAuth.swift exactly in structure and naming conventions.
// ---------------------------------------------------------------------------

/// In-memory spy that returns canned results so unit tests can exercise every
/// OAuth path without touching the OS browser or network stack.
public final class SpyGmailAuth: GmailAuthPort, @unchecked Sendable {

    // MARK: - Settable stubs

    /// Controls the return value of authorize(authURL:callbackScheme:).
    public var authorizeResult: String = "stub_code"

    /// Controls the return value of exchangeCode(_:verifier:clientID:redirectURI:).
    public var exchangeResult: TokenResponse = TokenResponse(
        access_token: "stub_access_token",
        expires_in: 3600,
        refresh_token: "stub_refresh_token",
        token_type: "Bearer",
        scope: "https://www.googleapis.com/auth/gmail.readonly"
    )

    /// Controls the return value of refreshToken(_:clientID:).
    public var refreshResult: RefreshResponse = RefreshResponse(
        access_token: "stub_refreshed_access_token",
        expires_in: 3600,
        token_type: "Bearer"
    )

    /// When non-nil, authorize() throws this error instead of returning authorizeResult.
    public var shouldThrowOnAuthorize: Error? = nil

    /// When non-nil, exchangeCode() throws this error instead of returning exchangeResult.
    public var shouldThrowOnExchange: Error? = nil

    /// When non-nil, refreshToken() throws this error instead of returning refreshResult.
    public var shouldThrowOnRefresh: Error? = nil

    // MARK: - Recorded calls

    /// All (authURL, callbackScheme) pairs passed to authorize(), in call order.
    public private(set) var authorizeCalls: [(URL, String)] = []

    /// All (code, verifier, clientID, redirectURI) tuples passed to exchangeCode(), in call order.
    public private(set) var exchangeCalls: [(String, String, String, String)] = []

    /// All (refreshToken, clientID) pairs passed to refreshToken(), in call order.
    public private(set) var refreshCalls: [(String, String)] = []

    public init() {}

    // MARK: - GmailAuthPort

    public func authorize(authURL: URL, callbackScheme: String) async throws -> String {
        authorizeCalls.append((authURL, callbackScheme))
        if let error = shouldThrowOnAuthorize { throw error }
        return authorizeResult
    }

    public func exchangeCode(_ code: String, verifier: String, clientID: String, redirectURI: String) async throws -> TokenResponse {
        exchangeCalls.append((code, verifier, clientID, redirectURI))
        if let error = shouldThrowOnExchange { throw error }
        return exchangeResult
    }

    public func refreshToken(_ refreshToken: String, clientID: String) async throws -> RefreshResponse {
        refreshCalls.append((refreshToken, clientID))
        if let error = shouldThrowOnRefresh { throw error }
        return refreshResult
    }

    // MARK: - Reset

    /// Clears all recorded calls and resets error stubs to nil.
    /// Useful between tests if the same SpyGmailAuth is reused.
    public func reset() {
        authorizeCalls = []
        exchangeCalls = []
        refreshCalls = []
        shouldThrowOnAuthorize = nil
        shouldThrowOnExchange = nil
        shouldThrowOnRefresh = nil
    }
}
