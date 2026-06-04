import Testing
import Foundation
import SwiftData
@testable import MyHome

// Requirements: D-MA-01, D-MA-02, D-MA-03, D-MA-06(a), T-MA-06
// Validation command: xcodebuild test ... -only-testing:MyHomeTests/MultiAccountGmailTests
// Plan 260603-lvt Task 2 — GmailAccountStore behaviors.
// Plan 260603-lvt Task 3 — Multi-account GmailSyncController behaviors (appended by Task 3).

/// MultiAccountGmailTests — unit tests for GmailAccountStore + multi-account GmailSyncController.
///
/// GmailAccountStore behaviors (Task 2):
///   MA-01: addOrUpdate for two different emails → accounts.count == 2 (no clobber).
///   MA-02: remove(email:) deletes only that account's metadata; other accounts remain.
///   MA-03: Per-account expiry/lastSynced/needsReconnect round-trip through Codable dict.
///   MA-04: migrateLegacyIfNeeded migrates legacy state once (T-MA-06 safety, D-MA-06a backfill).
///   MA-05: migrateLegacyIfNeeded is a no-op when already ran or no legacy email.
///
/// GmailSyncController multi-account behaviors (Task 3 — added to this file in Task 3):
///   MA-06: signIn() adds an account without clobbering the first.
///   MA-07: sync() loops all accounts with account-scoped dedup.
///   MA-08: One expired account does not abort sync for others.
///   MA-09: signOut(email:) removes only one account.
@MainActor
@Suite(.serialized)
struct MultiAccountGmailTests {

    // MARK: - Helpers

    /// Creates an isolated UserDefaults suite for each test.
    private func makeDefaults() -> UserDefaults {
        let name = "test.multiacct.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: name)!
        d.removePersistentDomain(forName: name)
        return d
    }

    private func makeStore(defaults: UserDefaults, keychain: SpyKeychainStore) -> GmailAccountStore {
        GmailAccountStore(defaults: defaults, keychain: keychain)
    }

    private func makeContainer() throws -> ModelContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: Expense.self, Category.self, Note.self, NoteBlock.self,
                                  configurations: config)
    }

    private func makeICICIEmail(amount: String = "1,250.00", merchant: String = "Zomato") -> String {
        """
        From: credit_cards@icici.bank.in
        To: test@gmail.com
        Subject: ICICI Bank Credit Card Transaction
        Date: Tue, 02 Jun 2026 10:00:00 +0530
        MIME-Version: 1.0
        Content-Type: text/html; charset=UTF-8

        <html><body>
        <p>Your ICICI Bank Credit Card XX9001 has been used for a transaction of INR \(amount) on Jun 02, 2026. Info: \(merchant).</p>
        </body></html>
        """
    }

    // MARK: - MA-01: addOrUpdate two emails → accounts.count == 2

    @Test("MA-01: addOrUpdate two different emails results in accounts.count == 2 — no clobber (D-MA-02)")
    func addTwoDifferentAccountsNoClobber() {
        let defaults = makeDefaults()
        let keychain = SpyKeychainStore()
        var store = makeStore(defaults: defaults, keychain: keychain)

        store.addOrUpdate(GmailAccount(email: "alice@gmail.com"))
        store.addOrUpdate(GmailAccount(email: "bob@gmail.com"))

        #expect(store.accounts.count == 2,
                "Two different emails must result in accounts.count == 2 — no clobber (D-MA-02)")
        let emails = store.accounts.map { $0.email }
        #expect(emails.contains("alice@gmail.com"), "alice must be in accounts")
        #expect(emails.contains("bob@gmail.com"), "bob must be in accounts")
    }

    @Test("MA-01b: addOrUpdate the same email twice results in accounts.count == 1 (upsert)")
    func addSameEmailTwiceIsUpsert() {
        let defaults = makeDefaults()
        let keychain = SpyKeychainStore()
        var store = makeStore(defaults: defaults, keychain: keychain)

        store.addOrUpdate(GmailAccount(email: "alice@gmail.com", needsReconnect: false))
        store.addOrUpdate(GmailAccount(email: "alice@gmail.com", needsReconnect: true))

        #expect(store.accounts.count == 1, "Same email added twice must not create duplicates")
        #expect(store.accounts.first?.needsReconnect == true, "Second add must overwrite the first")
    }

    @Test("MA-01c: emails are lowercased — D-MA-01")
    func emailsAreNormalized() {
        let defaults = makeDefaults()
        let keychain = SpyKeychainStore()
        var store = makeStore(defaults: defaults, keychain: keychain)

        store.addOrUpdate(GmailAccount(email: "Alice@Gmail.COM"))
        store.addOrUpdate(GmailAccount(email: "alice@gmail.com"))

        #expect(store.accounts.count == 1, "Mixed-case and lowercase same email must be de-duped (D-MA-01)")
        #expect(store.accounts.first?.email == "alice@gmail.com", "Email must be lowercased (D-MA-01)")
    }

    // MARK: - MA-02: remove(email:) deletes only that account's metadata

    @Test("MA-02: remove(email:) deletes only the named account, others remain (D-MA-02)")
    func removeDeletesOnlyNamedAccount() {
        let defaults = makeDefaults()
        let keychain = SpyKeychainStore()
        try? keychain.save("tok_alice", forKey: "refresh_token_alice@gmail.com")
        try? keychain.save("tok_bob", forKey: "refresh_token_bob@gmail.com")

        var store = makeStore(defaults: defaults, keychain: keychain)
        store.addOrUpdate(GmailAccount(email: "alice@gmail.com"))
        store.addOrUpdate(GmailAccount(email: "bob@gmail.com"))
        #expect(store.accounts.count == 2, "precondition: two accounts")

        store.remove(email: "alice@gmail.com")

        #expect(store.accounts.count == 1, "remove must delete only alice")
        #expect(store.accounts.first?.email == "bob@gmail.com", "bob must remain")
        // Alice's Keychain token must be deleted
        #expect((try? keychain.load(forKey: "refresh_token_alice@gmail.com")) == nil,
                "remove must delete the per-account Keychain token (SEC-03)")
        // Bob's Keychain token must remain
        #expect((try? keychain.load(forKey: "refresh_token_bob@gmail.com")) == "tok_bob",
                "remove must NOT delete other accounts' tokens")
    }

    // MARK: - MA-03: Per-account metadata round-trips through Codable dictionary

    @Test("MA-03: accessTokenExpiry, lastSyncedAt, needsReconnect round-trip through UserDefaults — D-MA-02")
    func metadataRoundTrips() {
        let defaults = makeDefaults()
        let keychain = SpyKeychainStore()
        var store = makeStore(defaults: defaults, keychain: keychain)

        let expiry = Date(timeIntervalSinceReferenceDate: 1_000_000)
        let lastSync = Date(timeIntervalSinceReferenceDate: 900_000)
        let account = GmailAccount(
            email: "charlie@gmail.com",
            accessTokenExpiry: expiry,
            lastSyncedAt: lastSync,
            needsReconnect: true
        )
        store.addOrUpdate(account)

        // Re-read from a fresh store using the same defaults
        let store2 = makeStore(defaults: defaults, keychain: keychain)
        let loaded = store2.accounts.first { $0.email == "charlie@gmail.com" }

        #expect(loaded != nil, "Account must persist to UserDefaults")
        if let loaded = loaded {
            // Dates round-trip via JSON encoder/decoder; compare to within 1 second
            #expect(abs(loaded.accessTokenExpiry!.timeIntervalSince(expiry)) < 1,
                    "accessTokenExpiry must round-trip through UserDefaults")
            #expect(abs(loaded.lastSyncedAt!.timeIntervalSince(lastSync)) < 1,
                    "lastSyncedAt must round-trip through UserDefaults")
            #expect(loaded.needsReconnect == true,
                    "needsReconnect must round-trip through UserDefaults")
        }
    }

    // MARK: - MA-04: migrateLegacyIfNeeded migrates single-account state

    @Test("MA-04: migrateLegacyIfNeeded migrates legacy gmail_connected_email + refresh_token (T-MA-06, D-MA-06a)")
    func migrateLegacyIfNeededMigratesSuccessfully() {
        let defaults = makeDefaults()
        let keychain = SpyKeychainStore()

        // Seed legacy state
        defaults.set("legacy@gmail.com", forKey: "gmail_connected_email")
        defaults.set(Date(timeIntervalSinceReferenceDate: 900_000), forKey: "gmail_last_synced_at")
        defaults.set(Date(timeIntervalSinceReferenceDate: 1_000_000), forKey: "gmail_access_token_expiry")
        try? keychain.save("legacy_refresh_token", forKey: "refresh_token")

        var store = makeStore(defaults: defaults, keychain: keychain)
        let migratedEmail = store.migrateLegacyIfNeeded(keychain: keychain)

        // Email returned
        #expect(migratedEmail == "legacy@gmail.com", "migrateLegacyIfNeeded must return the migrated email")

        // Account seeded in store
        #expect(store.accounts.count == 1, "One account must be seeded after migration")
        #expect(store.accounts.first?.email == "legacy@gmail.com", "Migrated account email must match legacy email")

        // Per-account Keychain token exists
        let perAccountToken = try? keychain.load(forKey: "refresh_token_legacy@gmail.com")
        #expect(perAccountToken == "legacy_refresh_token",
                "Per-account Keychain key must exist after migration (SEC-03, D-MA-02)")

        // Legacy email key cleared
        #expect(defaults.string(forKey: "gmail_connected_email") == nil,
                "Legacy gmail_connected_email must be cleared after migration")

        // One-shot flag set
        #expect(defaults.bool(forKey: "gmail_multiacct_migrated_v2") == true,
                "One-shot migration flag must be set after migration")

        // Legacy refresh_token deleted (safe: per-account copy confirmed)
        #expect((try? keychain.load(forKey: "refresh_token")) == nil,
                "Legacy refresh_token must be deleted after per-account copy is confirmed (T-MA-06)")
    }

    @Test("MA-04b: legacy token is NOT deleted if per-account copy cannot be confirmed (T-MA-06 safety)")
    func migrateLegacyTokenIsPreservedIfCopyFails() {
        let defaults = makeDefaults()

        // Seed legacy state
        defaults.set("legacy@gmail.com", forKey: "gmail_connected_email")

        // Use a keychain that fails on save
        let failKeychain = SpyKeychainStore()
        try? failKeychain.save("legacy_token", forKey: "refresh_token")
        failKeychain.shouldThrowOnSave = KeychainError.unexpectedStatus(-1)

        var store = GmailAccountStore(defaults: defaults, keychain: failKeychain)
        let result = store.migrateLegacyIfNeeded(keychain: failKeychain)

        // Migration should have been aborted
        #expect(result == nil, "Migration must abort if per-account copy fails")
        // Legacy token must still be in keychain
        failKeychain.shouldThrowOnSave = nil  // unblock load
        #expect((try? failKeychain.load(forKey: "refresh_token")) == "legacy_token",
                "Legacy refresh_token must NOT be deleted if per-account copy fails (T-MA-06)")
    }

    // MARK: - MA-05: migrateLegacyIfNeeded is a no-op when already ran or no legacy email

    @Test("MA-05a: migrateLegacyIfNeeded is a no-op when migration flag is already set")
    func migrateLegacyIsNoOpWhenAlreadyMigrated() {
        let defaults = makeDefaults()
        let keychain = SpyKeychainStore()

        // Set the one-shot flag to simulate already-migrated state
        defaults.set(true, forKey: "gmail_multiacct_migrated_v2")
        // Seed legacy state (which should be ignored)
        defaults.set("should_be_ignored@gmail.com", forKey: "gmail_connected_email")
        try? keychain.save("old_token", forKey: "refresh_token")

        var store = makeStore(defaults: defaults, keychain: keychain)
        let result = store.migrateLegacyIfNeeded(keychain: keychain)

        #expect(result == nil, "migrateLegacyIfNeeded must be a no-op when migration flag is already set")
        #expect(store.accounts.isEmpty, "No accounts should be added when migration is a no-op")
    }

    @Test("MA-05b: migrateLegacyIfNeeded is a no-op when no legacy email exists (clean install)")
    func migrateLegacyIsNoOpWithNoLegacyEmail() {
        let defaults = makeDefaults()
        let keychain = SpyKeychainStore()

        // No legacy state seeded
        var store = makeStore(defaults: defaults, keychain: keychain)
        let result = store.migrateLegacyIfNeeded(keychain: keychain)

        #expect(result == nil, "migrateLegacyIfNeeded must be a no-op on clean install")
        #expect(store.accounts.isEmpty, "No accounts should be added on clean install")
    }

    @Test("MA-05c: migrateLegacyIfNeeded running twice does not duplicate accounts")
    func migrateLegacyIsIdempotent() {
        let defaults = makeDefaults()
        let keychain = SpyKeychainStore()

        defaults.set("idempotent@gmail.com", forKey: "gmail_connected_email")
        try? keychain.save("tok", forKey: "refresh_token")

        var store = makeStore(defaults: defaults, keychain: keychain)
        _ = store.migrateLegacyIfNeeded(keychain: keychain)
        _ = store.migrateLegacyIfNeeded(keychain: keychain)  // second call must be no-op

        #expect(store.accounts.count == 1, "Second migrateLegacyIfNeeded call must not add a duplicate")
    }

    // MARK: - MA-06: GmailSyncController.signIn adds account without clobbering (Task 3)

    @Test("MA-06: signIn() for a second email preserves the first account — two per-account Keychain keys (D-MA-02)")
    func signInSecondAccountPreservesFirst() async {
        let defaults = makeDefaults()
        let keychain = SpyKeychainStore()

        let spy = SpyGmailAuth()
        let fetch = SpyGmailFetch()
        fetch.messageIDsResult = []

        // First sign-in as alice
        spy.exchangeResult = TokenResponse(
            access_token: "access_alice",
            expires_in: 3600,
            refresh_token: "refresh_alice",
            token_type: "Bearer",
            scope: "https://www.googleapis.com/auth/gmail.readonly"
        )
        fetch.profileResult = GmailProfile(emailAddress: "alice@gmail.com")
        let controller = GmailSyncController(auth: spy, keychain: keychain, fetch: fetch, defaults: defaults)
        await controller.signIn()

        let aliceToken = try? keychain.load(forKey: "refresh_token_alice@gmail.com")
        #expect(aliceToken == "refresh_alice", "First account's token must be in Keychain")

        // Second sign-in as bob
        spy.exchangeResult = TokenResponse(
            access_token: "access_bob",
            expires_in: 3600,
            refresh_token: "refresh_bob",
            token_type: "Bearer",
            scope: "https://www.googleapis.com/auth/gmail.readonly"
        )
        fetch.profileResult = GmailProfile(emailAddress: "bob@gmail.com")
        fetch.messageIDsResult = []
        await controller.signIn()

        // Both tokens must exist
        let aliceTokenAfter = try? keychain.load(forKey: "refresh_token_alice@gmail.com")
        let bobToken = try? keychain.load(forKey: "refresh_token_bob@gmail.com")
        #expect(aliceTokenAfter == "refresh_alice",
                "First account's token must NOT be deleted when second is added (D-MA-02)")
        #expect(bobToken == "refresh_bob",
                "Second account's token must be saved under per-account key (D-MA-02)")
        #expect(controller.isConnected == true, "isConnected must remain true")
        #expect(controller.store.accounts.count == 2, "Two distinct accounts must be in the store")
    }

    // MARK: - MA-07: account-scoped dedup — same messageID from two accounts both ingested

    @Test("MA-07: account-scoped dedup — same messageID from two accounts produces two expenses (T-MA-05)")
    func accountScopedDedupAllowsSameMessageIDFromTwoAccounts() async throws {
        let defaults = makeDefaults()
        let keychain = SpyKeychainStore()

        // Pre-seed both account tokens (refresh tokens)
        try keychain.save("refresh_alice", forKey: "refresh_token_alice@gmail.com")
        try keychain.save("refresh_bob", forKey: "refresh_token_bob@gmail.com")

        var store = makeStore(defaults: defaults, keychain: keychain)
        store.addOrUpdate(GmailAccount(email: "alice@gmail.com"))
        store.addOrUpdate(GmailAccount(email: "bob@gmail.com"))

        let container = try makeContainer()
        let spy = SpyGmailAuth()
        let fetch = SpyGmailFetch()

        // Both accounts return the same messageID
        fetch.messageIDsResult = ["msg-001"]
        fetch.rawMessageResult = makeICICIEmail()

        // Per-refresh-token responses
        spy.refreshResultForKey = [
            "refresh_alice": TokenResponse(access_token: "access_alice", expires_in: 3600,
                                           refresh_token: nil, token_type: "Bearer", scope: ""),
            "refresh_bob": TokenResponse(access_token: "access_bob", expires_in: 3600,
                                         refresh_token: nil, token_type: "Bearer", scope: ""),
        ]
        // Per-access-token profiles
        fetch.profileResultsByToken = [
            "access_alice": GmailProfile(emailAddress: "alice@gmail.com"),
            "access_bob": GmailProfile(emailAddress: "bob@gmail.com"),
        ]

        let controller = GmailSyncController(
            auth: spy, keychain: keychain, fetch: fetch,
            defaults: defaults, accountStore: store
        )
        controller.setContext(container.mainContext)
        await controller.sync()

        let expenses = try container.mainContext.fetch(FetchDescriptor<Expense>())
        // Both accounts ingest "msg-001" → two expenses (one per account)
        #expect(expenses.count == 2,
                "Same messageID from two accounts must produce two distinct expenses (T-MA-05)")
        let sourceAccounts = Set(expenses.compactMap { $0.sourceAccount })
        #expect(sourceAccounts.contains("alice@gmail.com"), "alice's expense must have sourceAccount = alice")
        #expect(sourceAccounts.contains("bob@gmail.com"), "bob's expense must have sourceAccount = bob")
    }

    // MARK: - MA-08: One expired account does not abort sync for others

    @Test("MA-08: One expired account does not abort sync for the remaining accounts (T-MA-04)")
    func oneExpiredAccountDoesNotAbortSync() async throws {
        let defaults = makeDefaults()
        let keychain = SpyKeychainStore()

        // Only bob has a valid refresh token; alice has none (simulate expired/missing)
        try keychain.save("refresh_bob", forKey: "refresh_token_bob@gmail.com")

        var store = makeStore(defaults: defaults, keychain: keychain)
        store.addOrUpdate(GmailAccount(email: "alice@gmail.com"))
        store.addOrUpdate(GmailAccount(email: "bob@gmail.com"))

        let container = try makeContainer()
        let spy = SpyGmailAuth()
        let fetch = SpyGmailFetch()

        // Bob produces a message
        fetch.rawMessageResult = makeICICIEmail()
        spy.refreshResultForKey = [
            "refresh_bob": TokenResponse(access_token: "access_bob", expires_in: 3600,
                                         refresh_token: nil, token_type: "Bearer", scope: ""),
        ]
        fetch.profileResultsByToken = [
            "access_bob": GmailProfile(emailAddress: "bob@gmail.com"),
        ]
        fetch.messageIDsResult = ["msg-bob-001"]

        let controller = GmailSyncController(
            auth: spy, keychain: keychain, fetch: fetch,
            defaults: defaults, accountStore: store
        )
        controller.setContext(container.mainContext)
        await controller.sync()

        // Bob's expense must be persisted despite alice's failure
        let expenses = try container.mainContext.fetch(FetchDescriptor<Expense>())
        #expect(expenses.count >= 1,
                "Bob's sync must complete even though alice has no refresh token (T-MA-04)")

        // Alice must be marked needsReconnect
        let aliceAccount = controller.store.accounts.first { $0.email == "alice@gmail.com" }
        #expect(aliceAccount?.needsReconnect == true,
                "Alice must be marked needsReconnect after token failure (T-MA-04)")

        // Overall status must be .done (at least one account synced)
        #expect(controller.syncStatus == .done,
                "syncStatus must be .done when at least one account synced successfully")
    }

    // MARK: - MA-09: signOut(email:) removes only one account

    @Test("MA-09: signOut(email:) removes only the named account; others remain connected (D-MA-05)")
    func signOutEmailRemovesOnlyNamedAccount() {
        let defaults = makeDefaults()
        let keychain = SpyKeychainStore()

        try? keychain.save("refresh_alice", forKey: "refresh_token_alice@gmail.com")
        try? keychain.save("refresh_bob", forKey: "refresh_token_bob@gmail.com")

        var store = makeStore(defaults: defaults, keychain: keychain)
        store.addOrUpdate(GmailAccount(email: "alice@gmail.com"))
        store.addOrUpdate(GmailAccount(email: "bob@gmail.com"))

        let spy = SpyGmailAuth()
        let fetch = SpyGmailFetch()
        let controller = GmailSyncController(
            auth: spy, keychain: keychain, fetch: fetch,
            defaults: defaults, accountStore: store
        )
        #expect(controller.store.accounts.count == 2, "precondition: two accounts")

        controller.signOut(email: "alice@gmail.com")

        // Alice's token deleted
        #expect((try? keychain.load(forKey: "refresh_token_alice@gmail.com")) == nil,
                "signOut(email:) must delete alice's Keychain token")
        // Bob's token preserved
        #expect((try? keychain.load(forKey: "refresh_token_bob@gmail.com")) == "refresh_bob",
                "signOut(email:) must NOT delete bob's Keychain token")
        // isConnected still true (bob is connected)
        #expect(controller.isConnected == true,
                "isConnected must remain true when one account is still connected")
        // Controller's store no longer has alice
        #expect(!controller.store.accounts.map({ $0.email }).contains("alice@gmail.com"),
                "alice must be removed from the store after signOut(email:)")
        #expect(controller.store.accounts.map({ $0.email }).contains("bob@gmail.com"),
                "bob must remain in the store after signOut(email:) for alice")
    }
}
