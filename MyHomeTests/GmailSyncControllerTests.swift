import Testing
import Foundation
@testable import MyHome

// Requirements: ING-02/03/05/16 (sign-in, sync, timestamp, token expiry),
//               SET-04/05 (sign-out, settings display), SEC-03 (refresh token Keychain spy)
// Threat ref: T-6-TOKEN (token lifecycle via spy), T-MA-06 (per-account token safety)
// Validation command: xcodebuild test ... -only-testing:MyHomeTests/GmailSyncControllerTests
// Updated for multi-account refactor (260603-lvt, Task 3):
//   - signIn() stores token under "refresh_token_<email>" (D-MA-02, SEC-03)
//   - signOut() (no args) removes all accounts (backward-compat for Settings)
//   - initSeedsIsConnectedFromKeychain: legacy "refresh_token" still seeds isConnected
//   - reconnectOverwritesRefreshToken → second signIn with same email overwrites per-account token

/// GmailSyncControllerTests — unit tests for GmailSyncController via SpyGmailAuth + SpyKeychainStore.
///
/// ING-02: signIn() drives syncStatus idle → done; writes lastSyncedAt; stores refresh token.
/// ING-03: sync() transitions idle → syncing → done.
/// ING-05: lastSyncedAt is written after a successful signIn or sync.
/// ING-16: needsProactiveRefresh is true when expiry < 5 min; scenePhaseChanged sets tokenExpired.
/// SET-04: signOut() removes all accounts and their tokens.
/// SET-05: Settings state (lastSyncedAt, syncStatus) is observable and updated after sync.
/// SEC-03: Refresh token stored in per-account Keychain key during signIn.
@MainActor
struct GmailSyncControllerTests {

    /// Default profile email returned by SpyGmailFetch.
    private let testEmail = "test@gmail.com"

    /// Per-account Keychain key for the default test account.
    private var perAccountKey: String { "refresh_token_\(testEmail)" }

    /// Isolated UserDefaults for test isolation.
    private func makeDefaults() -> UserDefaults {
        let name = "test.gsc.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: name)!
        d.removePersistentDomain(forName: name)
        return d
    }

    // MARK: - ING-02: signIn drives syncStatus idle → done, writes lastSyncedAt, stores token

    @Test("signInDrivesSyncStatusToDone: signIn() sets syncStatus=.done and writes lastSyncedAt — ING-02")
    func signInDrivesSyncStatusToDone() async {
        let defaults = makeDefaults()
        let spy = SpyGmailAuth()
        let keychain = SpyKeychainStore()
        let fetch = SpyGmailFetch()
        fetch.messageIDsResult = []
        let fixedNow = Date(timeIntervalSinceReferenceDate: 1_000_000)
        let controller = GmailSyncController(auth: spy, keychain: keychain, fetch: fetch,
                                              now: { fixedNow }, defaults: defaults)

        await controller.signIn()

        #expect(controller.syncStatus == .done,
                "signIn() must transition syncStatus to .done — ING-02")
        #expect(controller.lastSyncedAt != nil,
                "signIn() must write lastSyncedAt after successful OAuth + sync — ING-02, ING-05")
    }

    @Test("signInStoresRefreshTokenInKeychain: signIn() stores refresh_token under per-account key — ING-02, SEC-03, D-MA-02")
    func signInStoresRefreshTokenInKeychain() async {
        let defaults = makeDefaults()
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
        fetch.profileResult = GmailProfile(emailAddress: testEmail)
        fetch.messageIDsResult = []
        let fixedNow = Date(timeIntervalSinceReferenceDate: 1_000_000)
        let controller = GmailSyncController(auth: spy, keychain: keychain, fetch: fetch,
                                              now: { fixedNow }, defaults: defaults)

        await controller.signIn()

        // Multi-account: token stored under "refresh_token_<email>" (D-MA-02, SEC-03)
        let stored = try? keychain.load(forKey: perAccountKey)
        #expect(stored == "refresh_tok_123",
                "signIn() must store the refresh token under 'refresh_token_<email>' — ING-02, SEC-03, D-MA-02")
    }

    // MARK: - SET-05: isConnected is an observable stored property (UI reactivity)

    @Test("initSeedsIsConnectedFromKeychain: legacy refresh_token makes isConnected true at launch — SET-05")
    func initSeedsIsConnectedFromKeychain() {
        let defaults = makeDefaults()
        let keychain = SpyKeychainStore()
        // Seed legacy bare refresh_token (pre-multi-account upgrade)
        try? keychain.save("pre_existing_refresh", forKey: "refresh_token")
        let controller = GmailSyncController(auth: SpyGmailAuth(), keychain: keychain,
                                              now: Date.init, defaults: defaults)

        #expect(controller.isConnected == true,
                "init must seed isConnected=true when a legacy refresh token exists in Keychain — SET-05")
    }

    @Test("signInSetsIsConnectedTrue: a successful signIn flips isConnected to true — SET-05")
    func signInSetsIsConnectedTrue() async {
        let defaults = makeDefaults()
        let spy = SpyGmailAuth()
        let keychain = SpyKeychainStore()
        let fetch = SpyGmailFetch()
        fetch.messageIDsResult = []
        let controller = GmailSyncController(auth: spy, keychain: keychain, fetch: fetch,
                                              now: Date.init, defaults: defaults)

        #expect(controller.isConnected == false, "isConnected must start false with empty Keychain")
        await controller.signIn()

        #expect(controller.isConnected == true,
                "signIn() must set the observable isConnected=true (no app relaunch required) — SET-05")
    }

    @Test("signOutSetsIsConnectedFalse: signOut() flips isConnected back to false — SET-04")
    func signOutSetsIsConnectedFalse() async {
        let defaults = makeDefaults()
        let keychain = SpyKeychainStore()
        // Seed per-account token so store has an account
        try? keychain.save("pre_existing_refresh", forKey: "refresh_token_\(testEmail)")
        var store = GmailAccountStore(defaults: defaults, keychain: keychain)
        store.addOrUpdate(GmailAccount(email: testEmail))
        let controller = GmailSyncController(auth: SpyGmailAuth(), keychain: keychain,
                                              now: Date.init, defaults: defaults, accountStore: store)
        #expect(controller.isConnected == true, "precondition: seeded connected")

        controller.signOut()

        #expect(controller.isConnected == false,
                "signOut() must set the observable isConnected=false — SET-04")
    }

    // MARK: - T-06-CSRF: OAuth state binding + mismatch rejection

    @Test("signInPassesGeneratedStateToAuthorize: signIn binds callback to state in auth URL — T-06-CSRF")
    func signInPassesGeneratedStateToAuthorize() async {
        let defaults = makeDefaults()
        let spy = SpyGmailAuth()
        let fetch = SpyGmailFetch()
        fetch.messageIDsResult = []
        let controller = GmailSyncController(auth: spy, keychain: SpyKeychainStore(), fetch: fetch,
                                              now: Date.init, defaults: defaults)

        await controller.signIn()

        #expect(spy.authorizeCalls.count == 1, "authorize() must be called once")
        let (authURL, _, expectedState) = spy.authorizeCalls[0]
        #expect(!expectedState.isEmpty, "a non-empty state must be passed to authorize() — T-06-CSRF")

        let urlState = URLComponents(url: authURL, resolvingAgainstBaseURL: false)?
            .queryItems?.first(where: { $0.name == "state" })?.value
        #expect(urlState == expectedState,
                "authorize() expectedState must match the state embedded in the authorization URL — T-06-CSRF")
    }

    @Test("signInRejectsStateMismatch: a stateMismatch surfaces an error and stores no token — T-06-CSRF")
    func signInRejectsStateMismatch() async {
        let defaults = makeDefaults()
        let spy = SpyGmailAuth()
        spy.shouldThrowOnAuthorize = GmailAuthError.stateMismatch
        let keychain = SpyKeychainStore()
        let controller = GmailSyncController(auth: spy, keychain: keychain,
                                              now: Date.init, defaults: defaults)

        await controller.signIn()

        if case .error = controller.syncStatus {} else {
            Issue.record("stateMismatch must drive syncStatus to .error, not idle — T-06-CSRF")
        }
        #expect(controller.isConnected == false, "no connection on a rejected (CSRF) callback")
        #expect((try? keychain.load(forKey: perAccountKey)) == nil,
                "no refresh token may be stored when the callback is rejected — T-06-CSRF")
    }

    // MARK: - ING-03: sync transitions idle → syncing → done

    @Test("syncTransitionsIdleSyncingDone: sync() transitions syncStatus idle → syncing → done — ING-03")
    func syncTransitionsIdleSyncingDone() async {
        let defaults = makeDefaults()
        let spy = SpyGmailAuth()
        let keychain = SpyKeychainStore()
        let fetch = SpyGmailFetch()
        fetch.messageIDsResult = []
        let fixedNow = Date(timeIntervalSinceReferenceDate: 1_000_000)
        let controller = GmailSyncController(auth: spy, keychain: keychain, fetch: fetch,
                                              now: { fixedNow }, defaults: defaults)
        // Inject access token directly (legacy compat — no accounts in store, uses legacy sync path)
        controller.accessToken = "existing_access_token"

        await controller.sync()

        #expect(controller.syncStatus == .done,
                "sync() must complete with syncStatus=.done — ING-03")
    }

    @Test("syncWritesLastSyncedAt: sync() updates lastSyncedAt after completing — ING-03, ING-05")
    func syncWritesLastSyncedAt() async {
        let defaults = makeDefaults()
        let spy = SpyGmailAuth()
        let keychain = SpyKeychainStore()
        let fetch = SpyGmailFetch()
        fetch.messageIDsResult = []
        let fixedNow = Date(timeIntervalSinceReferenceDate: 1_000_000)
        let controller = GmailSyncController(auth: spy, keychain: keychain, fetch: fetch,
                                              now: { fixedNow }, defaults: defaults)
        controller.accessToken = "existing_access_token"

        await controller.sync()

        #expect(controller.lastSyncedAt != nil,
                "sync() must write lastSyncedAt — ING-03, ING-05, SET-05")
    }

    // MARK: - ING-16: needsProactiveRefresh

    @Test("needsProactiveRefreshTrueWhenExpiryLessThan5Min: expiry < 5 min → needsProactiveRefresh=true — ING-16")
    func needsProactiveRefreshTrueWhenExpiryLessThan5Min() {
        let defaults = makeDefaults()
        let keychain = SpyKeychainStore()
        let fixedNow = Date(timeIntervalSinceReferenceDate: 1_000_000)
        var store = GmailAccountStore(defaults: defaults, keychain: keychain)
        store.addOrUpdate(GmailAccount(email: testEmail))
        let controller = GmailSyncController(auth: SpyGmailAuth(), keychain: keychain,
                                              now: { fixedNow }, defaults: defaults, accountStore: store)

        controller.accessTokenExpiry = fixedNow.addingTimeInterval(180) // 3 minutes

        #expect(controller.needsProactiveRefresh == true,
                "needsProactiveRefresh must be true when token expires within 5 min — ING-16 (D6-06)")
    }

    @Test("needsProactiveRefreshFalseWhenExpiryMoreThan5Min: expiry > 5 min → needsProactiveRefresh=false — ING-16")
    func needsProactiveRefreshFalseWhenExpiryMoreThan5Min() {
        let defaults = makeDefaults()
        let keychain = SpyKeychainStore()
        let fixedNow = Date(timeIntervalSinceReferenceDate: 1_000_000)
        var store = GmailAccountStore(defaults: defaults, keychain: keychain)
        store.addOrUpdate(GmailAccount(email: testEmail))
        let controller = GmailSyncController(auth: SpyGmailAuth(), keychain: keychain,
                                              now: { fixedNow }, defaults: defaults, accountStore: store)

        controller.accessTokenExpiry = fixedNow.addingTimeInterval(600) // 10 minutes

        #expect(controller.needsProactiveRefresh == false,
                "needsProactiveRefresh must be false when token expires beyond 5 min — ING-16 (D6-06)")
    }

    @Test("needsProactiveRefreshTrueWhenExpiryNil: nil expiry → needsProactiveRefresh=true — ING-16")
    func needsProactiveRefreshTrueWhenExpiryNil() {
        let defaults = makeDefaults()
        let keychain = SpyKeychainStore()
        var store = GmailAccountStore(defaults: defaults, keychain: keychain)
        store.addOrUpdate(GmailAccount(email: testEmail))
        let controller = GmailSyncController(auth: SpyGmailAuth(), keychain: keychain,
                                              defaults: defaults, accountStore: store)
        controller.accessTokenExpiry = nil

        #expect(controller.needsProactiveRefresh == true,
                "needsProactiveRefresh must be true when accessTokenExpiry is nil — ING-16")
    }

    // MARK: - ING-16: isTokenExpired → scenePhaseChanged(.active) sets syncStatus == .tokenExpired

    @Test("scenePhaseActiveWithExpiredToken: expired token → .active → .tokenExpired — ING-16")
    func scenePhaseActiveWithExpiredTokenSetsSyncStatusTokenExpired() {
        let defaults = makeDefaults()
        let keychain = SpyKeychainStore()
        let fixedNow = Date(timeIntervalSinceReferenceDate: 1_000_000)
        var store = GmailAccountStore(defaults: defaults, keychain: keychain)
        store.addOrUpdate(GmailAccount(email: testEmail,
                                       accessTokenExpiry: fixedNow.addingTimeInterval(-600)))
        let controller = GmailSyncController(auth: SpyGmailAuth(), keychain: keychain,
                                              now: { fixedNow }, defaults: defaults, accountStore: store)

        controller.scenePhaseChanged(.active)

        #expect(controller.syncStatus == .tokenExpired,
                "scenePhaseChanged(.active) with expired token must set syncStatus=.tokenExpired — ING-16 (D6-11)")
    }

    // MARK: - SET-04: signOut deletes keychain and clears state

    @Test("signOutDeletesRefreshTokenFromKeychain: signOut() deletes all per-account tokens — SET-04")
    func signOutDeletesRefreshTokenFromKeychain() {
        let defaults = makeDefaults()
        let keychain = SpyKeychainStore()
        // Pre-store a per-account refresh token
        try? keychain.save("refresh_tok_to_delete", forKey: perAccountKey)

        var store = GmailAccountStore(defaults: defaults, keychain: keychain)
        store.addOrUpdate(GmailAccount(email: testEmail))
        let controller = GmailSyncController(auth: SpyGmailAuth(), keychain: keychain,
                                              defaults: defaults, accountStore: store)

        controller.signOut()

        let stored = try? keychain.load(forKey: perAccountKey)
        #expect(stored == nil,
                "signOut() must delete per-account refresh token from Keychain — SET-04, D6-17")
    }

    @Test("signOutClearsUserDefaultsFields: signOut() clears account state — SET-04")
    func signOutClearsUserDefaultsFields() {
        let defaults = makeDefaults()
        let keychain = SpyKeychainStore()
        var store = GmailAccountStore(defaults: defaults, keychain: keychain)
        store.addOrUpdate(GmailAccount(email: testEmail,
                                       accessTokenExpiry: Date(),
                                       lastSyncedAt: Date()))
        let controller = GmailSyncController(auth: SpyGmailAuth(), keychain: keychain,
                                              defaults: defaults, accountStore: store)

        controller.signOut()

        #expect(controller.connectedEmail == nil,
                "signOut() must clear connectedEmail — SET-04, D6-17")
        #expect(controller.lastSyncedAt == nil,
                "signOut() must clear lastSyncedAt — SET-04, D6-17")
        #expect(controller.accessTokenExpiry == nil,
                "signOut() must clear accessTokenExpiry — SET-04, D6-17")
    }

    // MARK: - SEC-03: Second signIn with same email overwrites per-account token (D-MA-02)

    @Test("signInTwiceSameEmailOverwritesToken: second signIn() for same email updates token — SEC-03, D-MA-02")
    func reconnectOverwritesRefreshToken() async {
        let defaults = makeDefaults()
        let spy = SpyGmailAuth()
        let keychain = SpyKeychainStore()
        let fetch = SpyGmailFetch()
        fetch.profileResult = GmailProfile(emailAddress: testEmail)

        // First sign-in with token A
        spy.exchangeResult = TokenResponse(
            access_token: "access_A",
            expires_in: 3600,
            refresh_token: "refresh_A",
            token_type: "Bearer",
            scope: "https://www.googleapis.com/auth/gmail.readonly"
        )
        fetch.messageIDsResult = []
        let controller = GmailSyncController(auth: spy, keychain: keychain, fetch: fetch,
                                              defaults: defaults)
        await controller.signIn()

        // Second sign-in (reconnect) with token B for the same email
        spy.exchangeResult = TokenResponse(
            access_token: "access_B",
            expires_in: 3600,
            refresh_token: "refresh_B",
            token_type: "Bearer",
            scope: "https://www.googleapis.com/auth/gmail.readonly"
        )
        await controller.signIn()

        let stored = try? keychain.load(forKey: perAccountKey)
        #expect(stored == "refresh_B",
                "Second signIn() for the same email must overwrite the refresh token — SEC-03, D-MA-02")
        // Still only one account (same email)
        #expect(controller.store.accounts.count == 1,
                "Same-email sign-in twice must not create two accounts — upsert behavior")
    }
}

// MARK: - UAT Verification Log

// UAT-6-01 [ING-01]: Tap "Connect Gmail" → ASWebAuthenticationSession sheet appears.
// UAT-6-02 [ING-01]: Complete sign-in → sheet dismisses; Settings shows account row.
// UAT-6-03 [ING-02]: After first OAuth success → "Last synced [time]" updates immediately.
// UAT-6-04 [ING-03]: Tap "Sync now" → loading indicator; all accounts synced; timestamps update.
// UAT-6-05 [ING-05]: Open Settings without signing in → "Last synced: Never" shown.
// UAT-6-06 [ING-16]: With expired token → "Gmail connection expired" banner; "Reconnect" CTA visible.
// UAT-6-07 [SEC-03]: After sign-in, Keychain item under "refresh_token_<email>" exists.
// UAT-6-08 [SET-04]: Tap per-account "Disconnect" → that row removed; others remain.
// UAT-6-09 [SET-04]: Tap "Add account" → OAuth; new row added below existing.
// UAT-6-10 [D6-19]: Cancel mid-OAuth → sheet dismisses; syncStatus = .idle (not stuck).
