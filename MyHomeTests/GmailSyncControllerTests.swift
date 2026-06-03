import Testing
import Foundation
@testable import MyHome

// Requirements: ING-02/03/05/16 (sign-in, sync, timestamp, token expiry),
//               SET-04/05 (sign-out, settings display), SEC-03 (refresh token Keychain spy)
// Threat ref: T-6-TOKEN (token lifecycle via spy)
// Validation command: xcodebuild test ... -only-testing:MyHomeTests/GmailSyncControllerTests
// Plan 06-01 — RED phase: tests compile only after GmailSyncController + spies exist (Task 1).
// Tests FAIL RED because signIn/sync/signOut/scenePhaseChanged/buildAuthorizationURL are stubs.

/// GmailSyncControllerTests — unit tests for GmailSyncController via SpyGmailAuth + SpyKeychainStore seams.
///
/// ING-02: signIn() drives syncStatus idle → done; writes lastSyncedAt; stores refresh token; calls sync.
/// ING-03: sync() transitions idle → syncing → done.
/// ING-05: lastSyncedAt is written after a successful signIn or sync.
/// ING-16: needsProactiveRefresh is true when expiry < 5 min; scenePhaseChanged sets tokenExpired.
/// SET-04: signOut() calls keychain.delete for "refresh_token"; clears connectedEmail/lastSyncedAt/accessTokenExpiry.
/// SET-05: Settings state (lastSyncedAt, syncStatus) is observable and updated after sync.
/// SEC-03: Refresh token is stored in spy Keychain during signIn and overwritten on reconnect.
@MainActor
struct GmailSyncControllerTests {

    /// UserDefaults suite for test isolation cleanup.
    private var defaults: UserDefaults {
        UserDefaults(suiteName: "group.com.reojacob.myhome") ?? .standard
    }

    /// Resets App Group UserDefaults keys used by GmailSyncController.
    private func resetDefaults() {
        defaults.removeObject(forKey: "gmail_last_synced_at")
        defaults.removeObject(forKey: "gmail_access_token_expiry")
        defaults.removeObject(forKey: "gmail_connected_email")
    }

    // MARK: - ING-02: signIn drives syncStatus idle → done, writes lastSyncedAt, stores refresh token

    @Test("signInDrivesSyncStatusToDone: signIn() sets syncStatus=.done and writes lastSyncedAt — ING-02")
    func signInDrivesSyncStatusToDone() async {
        resetDefaults()
        defer { resetDefaults() }

        let spy = SpyGmailAuth()
        let keychain = SpyKeychainStore()
        let fetch = SpyGmailFetch()
        fetch.messageIDsResult = []
        let fixedNow = Date(timeIntervalSinceReferenceDate: 1_000_000)
        let controller = GmailSyncController(auth: spy, keychain: keychain, fetch: fetch, now: { fixedNow })

        await controller.signIn()

        #expect(controller.syncStatus == .done,
                "signIn() must transition syncStatus to .done — ING-02")
        #expect(controller.lastSyncedAt != nil,
                "signIn() must write lastSyncedAt after successful OAuth + sync — ING-02, ING-05")
    }

    @Test("signInStoresRefreshTokenInKeychain: signIn() stores refresh_token via keychain spy — ING-02, SEC-03")
    func signInStoresRefreshTokenInKeychain() async {
        resetDefaults()
        defer { resetDefaults() }

        let spy = SpyGmailAuth()
        spy.exchangeResult = TokenResponse(
            access_token: "access_tok",
            expires_in: 3600,
            refresh_token: "refresh_tok_123",
            token_type: "Bearer",
            scope: "https://www.googleapis.com/auth/gmail.readonly"
        )
        let keychain = SpyKeychainStore()
        let fetch = SpyGmailFetch()
        fetch.messageIDsResult = []
        let fixedNow = Date(timeIntervalSinceReferenceDate: 1_000_000)
        let controller = GmailSyncController(auth: spy, keychain: keychain, fetch: fetch, now: { fixedNow })

        await controller.signIn()

        let stored = try? keychain.load(forKey: "refresh_token")
        #expect(stored == "refresh_tok_123",
                "signIn() must store the refresh token from TokenResponse in Keychain — ING-02, SEC-03")
    }

    // MARK: - SET-05: isConnected is an observable stored property (UI reactivity)

    @Test("initSeedsIsConnectedFromKeychain: a refresh token already in Keychain makes isConnected true at launch — SET-05")
    func initSeedsIsConnectedFromKeychain() {
        resetDefaults()
        defer { resetDefaults() }

        let keychain = SpyKeychainStore()
        try? keychain.save("pre_existing_refresh", forKey: "refresh_token")
        let controller = GmailSyncController(auth: SpyGmailAuth(), keychain: keychain, now: Date.init)

        #expect(controller.isConnected == true,
                "init must seed isConnected=true when a refresh token exists in Keychain — SET-05")
    }

    @Test("signInSetsIsConnectedTrue: a successful signIn flips isConnected to true so the UI re-renders — SET-05")
    func signInSetsIsConnectedTrue() async {
        resetDefaults()
        defer { resetDefaults() }

        let spy = SpyGmailAuth()
        let keychain = SpyKeychainStore()
        let fetch = SpyGmailFetch()
        fetch.messageIDsResult = []
        let controller = GmailSyncController(auth: spy, keychain: keychain, fetch: fetch, now: Date.init)

        #expect(controller.isConnected == false, "isConnected must start false with empty Keychain")
        await controller.signIn()

        #expect(controller.isConnected == true,
                "signIn() must set the observable isConnected=true (no app relaunch required) — SET-05")
    }

    @Test("signOutSetsIsConnectedFalse: signOut flips isConnected back to false — SET-04")
    func signOutSetsIsConnectedFalse() async {
        resetDefaults()
        defer { resetDefaults() }

        let keychain = SpyKeychainStore()
        try? keychain.save("pre_existing_refresh", forKey: "refresh_token")
        let controller = GmailSyncController(auth: SpyGmailAuth(), keychain: keychain, now: Date.init)
        #expect(controller.isConnected == true, "precondition: seeded connected")

        controller.signOut()

        #expect(controller.isConnected == false,
                "signOut() must set the observable isConnected=false — SET-04")
    }

    // MARK: - T-06-CSRF: OAuth state binding + mismatch rejection

    @Test("signInPassesGeneratedStateToAuthorize: signIn binds the callback to the state placed in the auth URL — T-06-CSRF")
    func signInPassesGeneratedStateToAuthorize() async {
        resetDefaults()
        defer { resetDefaults() }

        let spy = SpyGmailAuth()
        let fetch = SpyGmailFetch()
        fetch.messageIDsResult = []
        let controller = GmailSyncController(auth: spy, keychain: SpyKeychainStore(), fetch: fetch, now: Date.init)

        await controller.signIn()

        #expect(spy.authorizeCalls.count == 1, "authorize() must be called once")
        let (authURL, _, expectedState) = spy.authorizeCalls[0]
        #expect(!expectedState.isEmpty, "a non-empty state must be passed to authorize() — T-06-CSRF")

        // The expectedState passed to authorize() must equal the `state` query item in the auth URL.
        let urlState = URLComponents(url: authURL, resolvingAgainstBaseURL: false)?
            .queryItems?.first(where: { $0.name == "state" })?.value
        #expect(urlState == expectedState,
                "authorize() expectedState must match the state embedded in the authorization URL — T-06-CSRF")
    }

    @Test("signInRejectsStateMismatch: a stateMismatch from authorize surfaces an error and stores no token — T-06-CSRF")
    func signInRejectsStateMismatch() async {
        resetDefaults()
        defer { resetDefaults() }

        let spy = SpyGmailAuth()
        spy.shouldThrowOnAuthorize = GmailAuthError.stateMismatch
        let keychain = SpyKeychainStore()
        let controller = GmailSyncController(auth: spy, keychain: keychain, now: Date.init)

        await controller.signIn()

        if case .error = controller.syncStatus {} else {
            Issue.record("stateMismatch must drive syncStatus to .error, not idle — T-06-CSRF")
        }
        #expect(controller.isConnected == false, "no connection on a rejected (CSRF) callback")
        #expect((try? keychain.load(forKey: "refresh_token")) == nil,
                "no refresh token may be stored when the callback is rejected — T-06-CSRF")
    }

    // MARK: - ING-03: sync transitions idle → syncing → done

    @Test("syncTransitionsIdleSyncingDone: sync() transitions syncStatus idle → syncing → done — ING-03")
    func syncTransitionsIdleSyncingDone() async {
        resetDefaults()
        defer { resetDefaults() }

        let spy = SpyGmailAuth()
        let keychain = SpyKeychainStore()
        let fetch = SpyGmailFetch()
        fetch.messageIDsResult = []  // no messages — pipeline runs but inserts nothing
        let fixedNow = Date(timeIntervalSinceReferenceDate: 1_000_000)
        let controller = GmailSyncController(auth: spy, keychain: keychain, fetch: fetch, now: { fixedNow })
        controller.accessToken = "existing_access_token"

        await controller.sync()

        #expect(controller.syncStatus == .done,
                "sync() must complete with syncStatus=.done — ING-03")
    }

    @Test("syncWritesLastSyncedAt: sync() updates lastSyncedAt after completing — ING-03, ING-05")
    func syncWritesLastSyncedAt() async {
        resetDefaults()
        defer { resetDefaults() }

        let spy = SpyGmailAuth()
        let keychain = SpyKeychainStore()
        let fetch = SpyGmailFetch()
        fetch.messageIDsResult = []
        let fixedNow = Date(timeIntervalSinceReferenceDate: 1_000_000)
        let controller = GmailSyncController(auth: spy, keychain: keychain, fetch: fetch, now: { fixedNow })
        controller.accessToken = "existing_access_token"

        await controller.sync()

        #expect(controller.lastSyncedAt != nil,
                "sync() must write lastSyncedAt — ING-03, ING-05, SET-05")
    }

    // MARK: - ING-16: needsProactiveRefresh

    @Test("needsProactiveRefreshTrueWhenExpiryLessThan5Min: expiry < 5 min from now → needsProactiveRefresh=true — ING-16")
    func needsProactiveRefreshTrueWhenExpiryLessThan5Min() {
        resetDefaults()
        defer { resetDefaults() }

        let spy = SpyGmailAuth()
        let keychain = SpyKeychainStore()
        let fixedNow = Date(timeIntervalSinceReferenceDate: 1_000_000)
        let controller = GmailSyncController(auth: spy, keychain: keychain, now: { fixedNow })

        // Set expiry to 3 minutes from now (< 5 min threshold)
        controller.accessTokenExpiry = fixedNow.addingTimeInterval(180) // 3 minutes

        #expect(controller.needsProactiveRefresh == true,
                "needsProactiveRefresh must be true when token expires within 5 min — ING-16 (D6-06)")
    }

    @Test("needsProactiveRefreshFalseWhenExpiryMoreThan5Min: expiry > 5 min from now → needsProactiveRefresh=false — ING-16")
    func needsProactiveRefreshFalseWhenExpiryMoreThan5Min() {
        resetDefaults()
        defer { resetDefaults() }

        let spy = SpyGmailAuth()
        let keychain = SpyKeychainStore()
        let fixedNow = Date(timeIntervalSinceReferenceDate: 1_000_000)
        let controller = GmailSyncController(auth: spy, keychain: keychain, now: { fixedNow })

        // Set expiry to 10 minutes from now (> 5 min threshold)
        controller.accessTokenExpiry = fixedNow.addingTimeInterval(600) // 10 minutes

        #expect(controller.needsProactiveRefresh == false,
                "needsProactiveRefresh must be false when token expires beyond 5 min — ING-16 (D6-06)")
    }

    @Test("needsProactiveRefreshTrueWhenExpiryNil: nil expiry → needsProactiveRefresh=true — ING-16")
    func needsProactiveRefreshTrueWhenExpiryNil() {
        resetDefaults()
        defer { resetDefaults() }

        let spy = SpyGmailAuth()
        let keychain = SpyKeychainStore()
        let controller = GmailSyncController(auth: spy, keychain: keychain)

        // Ensure nil expiry
        controller.accessTokenExpiry = nil

        #expect(controller.needsProactiveRefresh == true,
                "needsProactiveRefresh must be true when accessTokenExpiry is nil — ING-16")
    }

    // MARK: - ING-16: isTokenExpired → scenePhaseChanged(.active) sets syncStatus == .tokenExpired

    @Test("scenePhaseActiveWithExpiredTokenSetsSyncStatusTokenExpired: expired token → scenePhaseChanged(.active) → .tokenExpired — ING-16")
    func scenePhaseActiveWithExpiredTokenSetsSyncStatusTokenExpired() {
        resetDefaults()
        defer { resetDefaults() }

        let spy = SpyGmailAuth()
        let keychain = SpyKeychainStore()
        let fixedNow = Date(timeIntervalSinceReferenceDate: 1_000_000)
        let controller = GmailSyncController(auth: spy, keychain: keychain, now: { fixedNow })

        // Set expiry in the past (token is expired)
        controller.accessTokenExpiry = fixedNow.addingTimeInterval(-600) // 10 minutes ago

        controller.scenePhaseChanged(.active)

        #expect(controller.syncStatus == .tokenExpired,
                "scenePhaseChanged(.active) with expired token must set syncStatus=.tokenExpired — ING-16 (D6-11)")
    }

    // MARK: - SET-04: signOut deletes keychain and clears UserDefaults

    @Test("signOutDeletesRefreshTokenFromKeychain: signOut() calls keychain.delete for refresh_token — SET-04")
    func signOutDeletesRefreshTokenFromKeychain() {
        resetDefaults()
        defer { resetDefaults() }

        let spy = SpyGmailAuth()
        let keychain = SpyKeychainStore()
        // Pre-store a refresh token
        try? keychain.save("refresh_tok_to_delete", forKey: "refresh_token")

        let controller = GmailSyncController(auth: spy, keychain: keychain)
        controller.connectedEmail = "test@gmail.com"
        controller.lastSyncedAt = Date()
        controller.accessTokenExpiry = Date()

        controller.signOut()

        let stored = try? keychain.load(forKey: "refresh_token")
        #expect(stored == nil,
                "signOut() must delete refresh_token from Keychain — SET-04, D6-17")
    }

    @Test("signOutClearsUserDefaultsFields: signOut() clears connectedEmail, lastSyncedAt, accessTokenExpiry — SET-04")
    func signOutClearsUserDefaultsFields() {
        resetDefaults()
        defer { resetDefaults() }

        let spy = SpyGmailAuth()
        let keychain = SpyKeychainStore()
        let controller = GmailSyncController(auth: spy, keychain: keychain)
        controller.connectedEmail = "test@gmail.com"
        controller.lastSyncedAt = Date()
        controller.accessTokenExpiry = Date()

        controller.signOut()

        #expect(controller.connectedEmail == nil,
                "signOut() must clear connectedEmail — SET-04, D6-17")
        #expect(controller.lastSyncedAt == nil,
                "signOut() must clear lastSyncedAt — SET-04, D6-17")
        #expect(controller.accessTokenExpiry == nil,
                "signOut() must clear accessTokenExpiry — SET-04, D6-17")
    }

    // MARK: - SEC-03: Reconnect overwrites refresh token in Keychain

    @Test("reconnectOverwritesRefreshToken: second signIn() stores new refresh token, overwriting old — SEC-03, SET-04")
    func reconnectOverwritesRefreshToken() async {
        resetDefaults()
        defer { resetDefaults() }

        let spy = SpyGmailAuth()
        let keychain = SpyKeychainStore()

        // First sign-in with token A
        spy.exchangeResult = TokenResponse(
            access_token: "access_A",
            expires_in: 3600,
            refresh_token: "refresh_A",
            token_type: "Bearer",
            scope: "https://www.googleapis.com/auth/gmail.readonly"
        )
        let fetch = SpyGmailFetch()
        fetch.messageIDsResult = []
        let controller = GmailSyncController(auth: spy, keychain: keychain, fetch: fetch)
        await controller.signIn()

        // Second sign-in (reconnect) with token B
        spy.exchangeResult = TokenResponse(
            access_token: "access_B",
            expires_in: 3600,
            refresh_token: "refresh_B",
            token_type: "Bearer",
            scope: "https://www.googleapis.com/auth/gmail.readonly"
        )
        await controller.signIn()

        let stored = try? keychain.load(forKey: "refresh_token")
        #expect(stored == "refresh_B",
                "Second signIn() must overwrite the old refresh token with the new one — SEC-03, SET-04")
    }
}

// MARK: - UAT Verification Log

// These behaviors require real OAuth, browser interaction, and device-level Keychain access.
// They cannot be exercised in unit tests. Captured here for end-of-phase manual sign-off
// (06-VALIDATION.md, human_verify_mode = end-of-phase).

// UAT-6-01 [ING-01]: Tap "Connect Gmail" in Settings → ASWebAuthenticationSession sheet appears;
//          Google sign-in form loads. (Requires Google Cloud Console setup + real client_id.)

// UAT-6-02 [ING-01]: Complete sign-in in OAuth sheet → sheet dismisses; app returns to Settings
//          with "Connected as [email]" showing and syncStatus = .done.

// UAT-6-03 [ING-02]: After first OAuth success → "Last synced [time]" updates immediately;
//          sync runs in background; ingestion results visible in Expenses (Phase 7 will show these).

// UAT-6-04 [ING-03]: Tap "Sync now" in Settings → loading indicator shown; syncStatus transitions
//          .syncing → .done; "Last synced just now" updates.

// UAT-6-05 [ING-05]: Open Settings without ever signing in → "Last synced: Never" shown;
//          after sign-in → timestamp is always visible.

// UAT-6-06 [ING-16]: With a token about to expire (or after 7 days on real device) → open Settings;
//          "Gmail connection expired" banner appears; "Reconnect" CTA is visible.

// UAT-6-07 [SEC-03]: After sign-in on device, verify Keychain item exists:
//          use Instruments / Xcode debugger Keychain viewer or a debug menu to confirm
//          kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly attribute is set on the item.

// UAT-6-08 [SET-04]: Tap "Sign out" → confirm dialog → signed out; "Connect Gmail" button reappears.

// UAT-6-09 [SET-04]: After sign-out, tap "Connect Gmail" → OAuth re-initiates; new refresh token
//          written; "Connected as [email]" shows; sync runs.

// UAT-6-10 [D6-19]: Cancel mid-OAuth flow (tap Cancel in browser) → sheet dismisses; Settings shows
//          "Try again" or similar non-crash state; syncStatus = .idle (not stuck).
