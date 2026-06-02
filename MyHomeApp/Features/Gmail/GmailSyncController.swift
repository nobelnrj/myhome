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

// MARK: - Wave-0 stub dependencies (replaced by System* types in plan 04)

/// Temporary stub satisfying GmailAuthPort default for Wave 0 compilation.
/// Plan 04 replaces with SystemGmailAuth.
private struct _StubGmailAuth: GmailAuthPort {
    func authorize(authURL: URL, callbackScheme: String) async throws -> String {
        throw GmailAuthError.userCancelled
    }
    func exchangeCode(_ code: String, verifier: String, clientID: String, redirectURI: String) async throws -> TokenResponse {
        throw GmailAuthError.userCancelled
    }
    func refreshToken(_ refreshToken: String, clientID: String) async throws -> RefreshResponse {
        throw GmailAuthError.userCancelled
    }
}

/// Temporary stub satisfying KeychainPort default for Wave 0 compilation.
/// Plan 04 replaces with SystemKeychainStore.
private struct _StubKeychain: KeychainPort {
    func save(_ value: String, forKey key: String) throws {}
    func load(forKey key: String) throws -> String? { nil }
    func delete(forKey key: String) throws {}
}

// MARK: - GmailSyncController

/// Observable state controller for the Gmail sign-in, sync, and token management lifecycle.
///
/// Owned by the Settings tab (or RootView) via `@State private var gmailSync = GmailSyncController()`.
/// Wraps `GmailAuthPort` (defaulting to `_StubGmailAuth` in Wave 0, `SystemGmailAuth` in plan 04)
/// and `KeychainPort` (defaulting to `_StubKeychain` in Wave 0, `SystemKeychainStore` in plan 04)
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
    var isConnected: Bool {
        (try? keychain.load(forKey: "refresh_token")) != nil
    }

    /// Whether the access token has expired according to the stored expiry date.
    /// D6-06: Check expiry within 5 minutes before each sync.
    var isTokenExpired: Bool {
        guard let expiry = accessTokenExpiry else { return true }
        return expiry < now()
    }

    /// Whether the access token will expire within 5 minutes (triggers proactive refresh).
    /// D6-06: Proactive access-token refresh: check expiry within 5 minutes before each sync request.
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
    ///   - auth: `GmailAuthPort` conformer; defaults to `_StubGmailAuth()` in Wave 0
    ///           (plan 04 swaps for `SystemGmailAuth()`).
    ///   - keychain: `KeychainPort` conformer; defaults to `_StubKeychain()` in Wave 0
    ///               (plan 04 swaps for `SystemKeychainStore()`).
    ///   - now: Time provider; defaults to `Date.init` in production. Injectable for tests.
    init(
        auth: any GmailAuthPort = _StubGmailAuth(),
        keychain: any KeychainPort = _StubKeychain(),
        now: @escaping () -> Date = Date.init
    ) {
        self.auth = auth
        self.keychain = keychain
        self.now = now
    }

    // MARK: - Scene phase hook (called from RootView/SettingsView .onChange)

    /// Drive proactive token expiry check on app foreground.
    /// D6-11: Check token validity on app foreground (Settings tab open).
    func scenePhaseChanged(_ phase: ScenePhase) {
        // STUB — plan 02 implements; test asserts tokenExpired when expired
        _ = phase
    }

    // MARK: - OAuth sign-in

    /// Initiates the full OAuth + PKCE sign-in flow and performs the initial backfill sync.
    /// D6-08: Immediate first sync on OAuth success — `newer_than:30d`.
    /// ING-02: signIn drives syncStatus idle → done.
    func signIn() async {
        // STUB — plan 02 implements; GmailSyncControllerTests asserts RED
        syncStatus = .idle
    }

    // MARK: - Manual sync

    /// Triggers a manual sync of new bank emails.
    /// ING-03: "Sync now" button in Settings.
    func sync() async {
        // STUB — plan 02 implements; GmailSyncControllerTests asserts RED
    }

    // MARK: - Sign out

    /// Removes the refresh token from Keychain and clears all Gmail-related UserDefaults.
    /// D6-17: Sign out removes refresh token from Keychain, clears expiry from UserDefaults.
    /// SET-04: User can sign out of Gmail.
    func signOut() {
        // STUB — plan 02 implements; GmailSyncControllerTests asserts RED
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
        // STUB — plan 02 implements; GmailAuthURLTests asserts RED
        return nil
    }
}
