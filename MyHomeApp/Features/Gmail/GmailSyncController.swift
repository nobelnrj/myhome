import Foundation
import SwiftUI
import AuthenticationServices

// MARK: - SyncStatus

/// Observable sync state for the Gmail connection / ingestion pipeline.
///
/// ING-02: signIn transitions idle → done (via authorizing) on OAuth success.
/// ING-03: sync transitions idle → syncing → done.
/// ING-16: tokenExpired triggers the Reconnect CTA.
public enum SyncStatus: Equatable, Sendable {
    case idle
    case authorizing
    case syncing
    case done
    case tokenExpired
    case error(String)
}

// NOTE: GmailOAuthConfig is defined in MyHomeApp/Gmail/GmailOAuthConfig.swift (plan 04).
// The inline placeholder and Wave-0 stubs (_StubGmailAuth/_StubKeychain) have been removed.
// GmailSyncController.init now uses SystemGmailAuth() and SystemKeychainStore() as defaults.

// MARK: - GmailSyncController

/// Observable state controller for the Gmail sign-in, sync, and token management lifecycle.
///
/// Owned by RootView via `@State private var gmailSyncController = GmailSyncController()`.
/// Wraps `GmailAuthPort` (defaulting to `SystemGmailAuth()` in production) and
/// `KeychainPort` (defaulting to `SystemKeychainStore()` in production)
/// for full unit testability of every OAuth path.
///
/// All persistent metadata is backed by App Group UserDefaults.
/// access_token stays in-memory only (D6-07).
/// refresh_token lives in Keychain (SEC-03).
///
/// All async methods are @MainActor because they mutate @Observable state.
@MainActor
@Observable
final class GmailSyncController {

    // MARK: - Persistent state (App Group UserDefaults)

    /// Date of the last successful email sync (key: "gmail_last_synced_at").
    var lastSyncedAt: Date? {
        get { defaults.object(forKey: "gmail_last_synced_at") as? Date }
        set { defaults.set(newValue, forKey: "gmail_last_synced_at") }
    }

    /// Expiry date of the current access token (key: "gmail_access_token_expiry").
    /// D6-07: expiry in App Group UserDefaults; access_token in memory only.
    var accessTokenExpiry: Date? {
        get { defaults.object(forKey: "gmail_access_token_expiry") as? Date }
        set { defaults.set(newValue, forKey: "gmail_access_token_expiry") }
    }

    /// The email address of the connected Gmail account (key: "gmail_connected_email").
    var connectedEmail: String? {
        get { defaults.string(forKey: "gmail_connected_email") }
        set { defaults.set(newValue, forKey: "gmail_connected_email") }
    }

    // MARK: - In-memory state

    /// In-memory access token — NEVER persisted (D6-07).
    var accessToken: String? = nil

    /// Current sync pipeline state.
    var syncStatus: SyncStatus = .idle

    /// Last OAuth/Keychain error, or nil.
    var authError: GmailAuthError? = nil

    // MARK: - Derived state

    /// Whether a refresh token is currently stored in Keychain.
    ///
    /// Stored (not computed) so `@Observable` can track it: a computed property that reads
    /// the Keychain is invisible to SwiftUI, so the connect/connected UI never refreshed after
    /// `signIn()` saved the token (it required an app relaunch). Seeded from Keychain in `init`,
    /// then flipped by `signIn()` / `signOut()`.
    private(set) var isConnected: Bool = false

    /// Whether the access token has expired according to the stored expiry date.
    /// D6-06: Check expiry within 5 minutes before each sync.
    var isTokenExpired: Bool {
        guard let expiry = accessTokenExpiry else { return true }
        return expiry < now()
    }

    /// Whether the access token will expire within 5 minutes (triggers proactive refresh).
    /// D6-06: Returns true when no expiry date is stored (unknown freshness) or expiry is within 5 min.
    /// Returns false when expiry is stored and is more than 5 minutes away.
    var needsProactiveRefresh: Bool {
        guard let expiry = accessTokenExpiry else { return true }
        return expiry.timeIntervalSince(now()) < 300
    }

    // MARK: - Dependencies

    private let auth: any GmailAuthPort
    private let keychain: any KeychainPort
    /// Provides the current time; injectable for deterministic expiry tests.
    private let now: () -> Date

    private var defaults: UserDefaults {
        UserDefaults(suiteName: "group.com.reojacob.myhome") ?? .standard
    }

    // MARK: - Init

    /// Creates a GmailSyncController with injected ports and optional time provider.
    /// - Parameters:
    ///   - auth: `GmailAuthPort` conformer; defaults to `SystemGmailAuth()` in production.
    ///   - keychain: `KeychainPort` conformer; defaults to `SystemKeychainStore()` in production.
    ///   - now: Time provider; defaults to `Date.init` in production. Injectable for tests.
    init(
        auth: any GmailAuthPort = SystemGmailAuth(),
        keychain: any KeychainPort = SystemKeychainStore(),
        now: @escaping () -> Date = Date.init
    ) {
        self.auth = auth
        self.keychain = keychain
        self.now = now
        // Seed connection state from Keychain at launch so the UI reflects a prior sign-in.
        self.isConnected = (try? keychain.load(forKey: "refresh_token")) != nil
    }

    // MARK: - Scene phase hook (called from RootView/SettingsView .onChange)

    /// Drive proactive token expiry check on app foreground.
    /// D6-11: Check token validity on app foreground (Settings tab open).
    func scenePhaseChanged(_ phase: ScenePhase) {
        switch phase {
        case .active:
            if isTokenExpired {
                syncStatus = .tokenExpired
            }
        case .inactive, .background:
            break
        @unknown default:
            break
        }
    }

    // MARK: - OAuth sign-in

    /// Initiates the full OAuth + PKCE sign-in flow and performs the initial backfill sync.
    /// D6-08: Immediate first sync on OAuth success — `newer_than:30d`.
    /// ING-02: signIn drives syncStatus idle → done.
    func signIn() async {
        syncStatus = .authorizing
        authError = nil

        do {
            // Generate PKCE pair and build the authorization URL
            let pkce = try PKCE.generate()
            let state = UUID().uuidString
            guard let authURL = buildAuthorizationURL(
                clientID: GmailOAuthConfig.clientID,
                redirectURI: GmailOAuthConfig.redirectURI,
                pkce: pkce,
                state: state
            ) else {
                syncStatus = .error("Failed to build authorization URL")
                return
            }

            // Present the OAuth browser and await the authorization code
            let code = try await auth.authorize(
                authURL: authURL,
                callbackScheme: GmailOAuthConfig.callbackScheme
            )

            // Exchange the authorization code for tokens
            let tokenResponse = try await auth.exchangeCode(
                code,
                verifier: pkce.verifier,
                clientID: GmailOAuthConfig.clientID,
                redirectURI: GmailOAuthConfig.redirectURI
            )

            // Guard: Google must return a refresh_token (requires access_type=offline + prompt=consent)
            guard let refreshToken = tokenResponse.refresh_token else {
                syncStatus = .error("no refresh token — missing access_type=offline")
                return
            }

            // SEC-03: Store refresh token in Keychain (never in UserDefaults — T-06-TOKEN)
            try keychain.save(refreshToken, forKey: "refresh_token")

            // Flip observable connection state so SwiftUI re-renders into the connected view
            // immediately (no app relaunch required).
            isConnected = true

            // D6-07: access_token in memory only; expiry timestamp in UserDefaults
            accessToken = tokenResponse.access_token
            accessTokenExpiry = now().addingTimeInterval(TimeInterval(tokenResponse.expires_in))

            // D6-08: Immediately perform the first backfill sync (newer_than:30d)
            await sync()

        } catch let gmailError as GmailAuthError {
            // D6-19: Raw Google error message displayed directly (single-user private app)
            if case .oauthError(let msg) = gmailError {
                authError = gmailError
                syncStatus = .error(msg)
            } else {
                // userCancelled, callbackURLInvalid, noAuthCode — return to idle without error display
                syncStatus = .idle
            }
        } catch {
            syncStatus = .error(error.localizedDescription)
        }
    }

    // MARK: - Manual sync

    /// Triggers a manual sync of new bank emails.
    /// ING-03: "Sync now" button in Settings.
    func sync() async {
        // Proactive token refresh if needed (D6-06):
        // Refresh when no in-memory access token exists (e.g. app restart — D6-07) OR when
        // the stored expiry date shows the token will expire within 5 minutes.
        // Skip refresh when an in-memory token is present but no expiry is stored (tests / sign-in path).
        let shouldRefresh = accessToken == nil || (accessTokenExpiry != nil && needsProactiveRefresh)
        if shouldRefresh {
            guard let storedRefreshToken = try? keychain.load(forKey: "refresh_token") else {
                syncStatus = .tokenExpired
                return
            }
            do {
                let refreshResponse = try await auth.refreshToken(
                    storedRefreshToken,
                    clientID: GmailOAuthConfig.clientID
                )
                accessToken = refreshResponse.access_token
                accessTokenExpiry = now().addingTimeInterval(TimeInterval(refreshResponse.expires_in))
            } catch {
                // ING-16: invalid_grant or any refresh error → prompt user to reconnect
                syncStatus = .tokenExpired
                return
            }
        }

        // ING-03: Transition to .syncing before the fetch
        syncStatus = .syncing

        // D6-10: Compute query — newer_than:30d on first sync; newer_than:<days> since last sync
        let query: String
        if let last = lastSyncedAt {
            let daysSince = Int(now().timeIntervalSince(last) / 86400)
            query = "newer_than:\(max(1, daysSince))d"
        } else {
            query = "newer_than:30d"
        }

        // Phase 6 stub: the actual Gmail API listMessages call is wired in plan 04.
        // query is computed above and will be passed to the Gmail port in plan 04.
        _ = query

        // ING-05: Write lastSyncedAt on success
        lastSyncedAt = now()
        syncStatus = .done
    }

    // MARK: - Sign out

    /// Removes the refresh token from Keychain and clears all Gmail-related UserDefaults.
    /// D6-17: Sign out removes refresh token from Keychain, clears expiry from UserDefaults.
    /// SET-04: User can sign out of Gmail.
    func signOut() {
        // SEC-03 / T-06-TOKEN: Delete refresh token from Keychain
        try? keychain.delete(forKey: "refresh_token")

        // Flip observable connection state so the UI returns to the "Connect Gmail" view.
        isConnected = false

        // Clear in-memory token state
        accessToken = nil

        // Clear all gmail_* UserDefaults keys (D6-17)
        accessTokenExpiry = nil
        lastSyncedAt = nil
        connectedEmail = nil

        syncStatus = .idle
    }

    // MARK: - Authorization URL builder

    /// Constructs the OAuth authorization URL with all required query parameters.
    ///
    /// nonisolated because it is a pure function (no actor state mutation).
    /// D6-01: ASWebAuthenticationSession; D6-02: PKCE; D6-03: gmail.readonly scope.
    ///
    /// ING-01: The URL must contain client_id, redirect_uri, response_type=code,
    ///         scope=https://www.googleapis.com/auth/gmail.readonly, code_challenge,
    ///         code_challenge_method=S256, access_type=offline, state, prompt=consent.
    nonisolated func buildAuthorizationURL(
        clientID: String,
        redirectURI: String,
        pkce: PKCE,
        state: String
    ) -> URL? {
        var components = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")
        components?.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: "https://www.googleapis.com/auth/gmail.readonly"),
            URLQueryItem(name: "code_challenge", value: pkce.challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "access_type", value: "offline"),  // Required for refresh_token
            URLQueryItem(name: "state", value: state),            // CSRF protection (T-06-CSRF)
            URLQueryItem(name: "prompt", value: "consent"),       // Force consent on reconnect
        ]
        return components?.url
    }
}
