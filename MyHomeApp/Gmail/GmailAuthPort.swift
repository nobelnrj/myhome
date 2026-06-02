import Foundation
import AuthenticationServices
import UIKit

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
    ///   - expectedState: The `state` value that was placed in `authURL`; the callback's
    ///     returned `state` MUST equal this or the response is rejected (T-06-CSRF / T-06-04-CALLBACK).
    /// - Returns: The authorization code extracted from the callback URL
    /// - Throws: `GmailAuthError` for cancellation, invalid callback, missing code, or state mismatch
    func authorize(authURL: URL, callbackScheme: String, expectedState: String) async throws -> String

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
    /// The callback's `state` did not match the value sent in the authorization request
    /// — possible CSRF / response injection (T-06-CSRF / T-06-04-CALLBACK).
    case stateMismatch
    /// A network-level error occurred during token exchange or refresh.
    case networkError(Error)
    /// The OAuth server returned an error response (e.g., invalid_grant).
    case oauthError(String)
}

// MARK: - SceneContextProvider

/// Provides a presentation anchor for ASWebAuthenticationSession.
/// iOS 17+: picks the first connected UIWindowScene's keyWindow.
/// Nonisolated conformance; UIApplication access is via the SceneDelegate/UIWindowScene API.
private final class SceneContextProvider: NSObject, ASWebAuthenticationPresentationContextProviding, @unchecked Sendable {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        return UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first?.keyWindow ?? UIWindow()
    }
}

// MARK: - SystemGmailAuth

/// Production conformer that wraps ASWebAuthenticationSession + URLSession.
///
/// This is the only type in the Gmail subsystem that touches the OS authentication
/// stack and the network for OAuth. All unit tests inject SpyGmailAuth instead.
///
/// D6-01: ASWebAuthenticationSession (no Google SignIn SDK).
/// D6-23: Wrapped behind GmailAuthPort protocol seam (mirrors NotificationCenterPort).
/// D6-24: 60s URLSession timeout for the token endpoint.
///
/// ING-01: authorize() is @MainActor — ASWebAuthenticationSession must present UI on main thread.
/// The continuation is resumed exactly once per branch (RESEARCH Pitfall 4 guard pattern).
public final class SystemGmailAuth: GmailAuthPort, @unchecked Sendable {

    // Session is kept as an instance property so it stays retained until the callback fires.
    // (RESEARCH Pitfall: session must not be deallocated before the callback.)
    private var activeSession: ASWebAuthenticationSession?

    public init() {}

    /// Presents the OAuth browser sheet and returns the authorization code.
    /// Must be called on the main actor because ASWebAuthenticationSession presents UI.
    @MainActor
    public func authorize(authURL: URL, callbackScheme: String, expectedState: String) async throws -> String {
        return try await withCheckedThrowingContinuation { continuation in
            let contextProvider = SceneContextProvider()
            let session = ASWebAuthenticationSession(
                url: authURL,
                callbackURLScheme: callbackScheme
            ) { [weak self] callbackURL, error in
                defer { self?.activeSession = nil }

                if let error = error {
                    let nsError = error as NSError
                    if nsError.domain == ASWebAuthenticationSessionErrorDomain,
                       nsError.code == ASWebAuthenticationSessionError.canceledLogin.rawValue {
                        continuation.resume(throwing: GmailAuthError.userCancelled)
                    } else {
                        continuation.resume(throwing: GmailAuthError.networkError(error))
                    }
                    return
                }

                guard let url = callbackURL,
                      let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
                else {
                    continuation.resume(throwing: GmailAuthError.callbackURLInvalid)
                    return
                }

                // D6-19: extract "error" query param first — OAuth server error takes priority
                if let oauthError = components.queryItems?.first(where: { $0.name == "error" })?.value {
                    continuation.resume(throwing: GmailAuthError.oauthError(oauthError))
                    return
                }

                // T-06-CSRF / T-06-04-CALLBACK: the returned state MUST match the value we sent.
                // A missing or mismatched state means a forged/injected callback — reject it.
                let returnedState = components.queryItems?.first(where: { $0.name == "state" })?.value
                guard returnedState == expectedState else {
                    continuation.resume(throwing: GmailAuthError.stateMismatch)
                    return
                }

                guard let code = components.queryItems?.first(where: { $0.name == "code" })?.value else {
                    continuation.resume(throwing: GmailAuthError.noAuthCode)
                    return
                }

                continuation.resume(returning: code)
            }
            session.presentationContextProvider = contextProvider
            session.prefersEphemeralWebBrowserSession = false  // reuse browser cookies for faster re-auth
            activeSession = session  // retain until callback fires
            session.start()
        }
    }

    /// Exchanges an authorization code for access + refresh tokens via URLSession POST.
    /// D6-24: 60s timeout.
    public func exchangeCode(_ code: String, verifier: String, clientID: String, redirectURI: String) async throws -> TokenResponse {
        let url = URL(string: "https://oauth2.googleapis.com/token")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 60
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let bodyParams: [String: String] = [
            "client_id": clientID,
            "code": code,
            "code_verifier": verifier,
            "grant_type": "authorization_code",
            "redirect_uri": redirectURI,
        ]
        request.httpBody = bodyParams
            .map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")" }
            .sorted()  // stable ordering for reproducibility
            .joined(separator: "&")
            .data(using: .utf8)

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 400 {
                // ING-16: 400 invalid_grant → decode and surface as oauthError so controller
                // treats it as token expiry / re-auth required
                if let body = try? JSONDecoder().decode([String: String].self, from: data),
                   let errorMsg = body["error"] {
                    throw GmailAuthError.oauthError(errorMsg)
                }
            }
            return try JSONDecoder().decode(TokenResponse.self, from: data)
        } catch let gmailError as GmailAuthError {
            throw gmailError
        } catch {
            throw GmailAuthError.networkError(error)
        }
    }

    /// Exchanges a refresh token for a new access token via URLSession POST.
    /// D6-24: 60s timeout. Maps 400 invalid_grant to oauthError (ING-16).
    public func refreshToken(_ refreshToken: String, clientID: String) async throws -> RefreshResponse {
        let url = URL(string: "https://oauth2.googleapis.com/token")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 60
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let bodyParams: [String: String] = [
            "client_id": clientID,
            "refresh_token": refreshToken,
            "grant_type": "refresh_token",
        ]
        request.httpBody = bodyParams
            .map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")" }
            .sorted()
            .joined(separator: "&")
            .data(using: .utf8)

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 400 {
                if let body = try? JSONDecoder().decode([String: String].self, from: data),
                   let errorMsg = body["error"] {
                    throw GmailAuthError.oauthError(errorMsg)
                }
            }
            return try JSONDecoder().decode(RefreshResponse.self, from: data)
        } catch let gmailError as GmailAuthError {
            throw gmailError
        } catch {
            throw GmailAuthError.networkError(error)
        }
    }
}
