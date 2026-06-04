import Foundation
import SwiftData

// MARK: - GmailAccount

/// Per-account persistent metadata stored in UserDefaults under `gmail_accounts_v2`.
///
/// Identity: email address (lowercased — D-MA-01).
/// Secrets (refresh token) are stored in Keychain under `refresh_token_<email>` (SEC-03, D-MA-02).
/// Non-secret metadata (expiry, lastSynced, needsReconnect) goes in this Codable struct.
public struct GmailAccount: Codable, Equatable, Sendable {
    /// Lowercased Gmail address — primary key (D-MA-01).
    public let email: String
    /// Expiry date of the current access token; nil = unknown (treat as expired).
    public var accessTokenExpiry: Date?
    /// Date of last successful sync for this account; nil = never synced.
    public var lastSyncedAt: Date?
    /// Whether this account needs user re-authentication (invalid_grant received).
    public var needsReconnect: Bool

    public init(
        email: String,
        accessTokenExpiry: Date? = nil,
        lastSyncedAt: Date? = nil,
        needsReconnect: Bool = false
    ) {
        self.email = email.lowercased()
        self.accessTokenExpiry = accessTokenExpiry
        self.lastSyncedAt = lastSyncedAt
        self.needsReconnect = needsReconnect
    }
}

// MARK: - GmailAccountStore

/// Manages the set of connected Gmail accounts.
///
/// Persistence: a `[String: GmailAccount]` dictionary JSON-encoded and stored in UserDefaults
/// under `gmail_accounts_v2` (D-MA-02). The list of connected emails is derived from the
/// dictionary's keys; refresh tokens are NOT stored here (Keychain only — SEC-03).
///
/// All operations normalize emails with `.lowercased()` (D-MA-01).
/// Injectable UserDefaults + KeychainPort for full unit testability.
public struct GmailAccountStore {

    // MARK: - UserDefaults keys

    /// Key for the accounts dictionary (JSON-encoded `[String: GmailAccount]`).
    public static let accountsDictKey = "gmail_accounts_v2"

    /// One-shot migration flag — set when the single-account legacy state has been
    /// forward-migrated into the per-account scheme. Guards against re-running migration.
    public static let migrationDoneKey = "gmail_multiacct_migrated_v2"

    // MARK: - Legacy UserDefaults keys (cleared after migration)

    private static let legacyEmailKey = "gmail_connected_email"
    private static let legacyLastSyncedKey = "gmail_last_synced_at"
    private static let legacyTokenExpiryKey = "gmail_access_token_expiry"
    private static let legacyRefreshTokenKey = "refresh_token"

    // MARK: - Dependencies

    private let defaults: UserDefaults
    private let keychain: any KeychainPort

    // MARK: - Init

    public init(
        defaults: UserDefaults = UserDefaults(suiteName: "group.com.reojacob.myhome") ?? .standard,
        keychain: any KeychainPort = SystemKeychainStore()
    ) {
        self.defaults = defaults
        self.keychain = keychain
    }

    // MARK: - Derived key helpers

    /// Keychain key for a given email's refresh token (D-MA-02).
    public func refreshTokenKey(for email: String) -> String {
        "refresh_token_\(email.lowercased())"
    }

    // MARK: - Accounts access

    /// All connected accounts, sorted by email for stable UI ordering.
    public var accounts: [GmailAccount] {
        loadAccountsDict().values.sorted { $0.email < $1.email }
    }

    // MARK: - CRUD operations

    /// Adds a new account or replaces it if it already exists (by email).
    /// The account's email is lowercased before storage (D-MA-01).
    public mutating func addOrUpdate(_ account: GmailAccount) {
        var dict = loadAccountsDict()
        let key = account.email.lowercased()
        dict[key] = GmailAccount(
            email: key,
            accessTokenExpiry: account.accessTokenExpiry,
            lastSyncedAt: account.lastSyncedAt,
            needsReconnect: account.needsReconnect
        )
        saveAccountsDict(dict)
    }

    /// Mutates an existing account in place via a closure.
    /// No-op if the account does not exist.
    public mutating func update(email: String, mutate: (inout GmailAccount) -> Void) {
        let key = email.lowercased()
        var dict = loadAccountsDict()
        guard var account = dict[key] else { return }
        mutate(&account)
        dict[key] = account
        saveAccountsDict(dict)
    }

    /// Removes an account and its Keychain refresh token.
    /// No-op if the account does not exist.
    public mutating func remove(email: String) {
        let key = email.lowercased()
        var dict = loadAccountsDict()
        dict.removeValue(forKey: key)
        saveAccountsDict(dict)
        // Also delete the per-account refresh token from Keychain (SEC-03).
        try? keychain.delete(forKey: refreshTokenKey(for: key))
    }

    // MARK: - Legacy forward-migration (D-MA-02, D-MA-06(a), T-MA-06)

    /// Migrates the single-account legacy state (pre-multi-account) into the per-account scheme.
    ///
    /// Guarded by the one-shot `gmail_multiacct_migrated_v2` flag. If migration already ran,
    /// or there is no legacy email/token, this is a no-op.
    ///
    /// Migration steps (T-MA-06 — no window where the user loses their token):
    ///   1. Read legacy `gmail_connected_email` + `refresh_token` from Keychain.
    ///   2. Copy the refresh token to `refresh_token_<email>` (per-account key).
    ///   3. CONFIRM the per-account token was written (load it back).
    ///   4. Seed a GmailAccount from legacy expiry/lastSynced metadata.
    ///   5. Clear the three legacy `gmail_*` singular UserDefaults keys.
    ///   6. Delete the legacy `refresh_token` Keychain item.
    ///   7. Set the one-shot migration-done flag.
    ///
    /// D-MA-06(a): After seeding the migrated account, backfill `sourceAccount` on all
    /// existing Expenses with a non-nil `gmailMessageID` and nil `sourceAccount`.
    /// If no ModelContext is available at init time, the backfill is deferred to the first
    /// `syncAccount` run for the migrated email (guard with the migrated flag).
    ///
    /// - Parameters:
    ///   - keychain: KeychainPort used to read/write/delete tokens (injectable for tests).
    ///   - modelContext: Optional SwiftData context for D-MA-06(a) backfill. May be nil.
    /// - Returns: The email of the migrated account, or nil if migration was skipped.
    @discardableResult
    public mutating func migrateLegacyIfNeeded(
        keychain: any KeychainPort,
        modelContext: ModelContext? = nil
    ) -> String? {
        // Guard 1: skip if migration already ran
        guard !defaults.bool(forKey: GmailAccountStore.migrationDoneKey) else { return nil }

        // Guard 2: legacy email must exist
        guard let legacyEmail = defaults.string(forKey: GmailAccountStore.legacyEmailKey),
              !legacyEmail.isEmpty else {
            // No legacy email → set flag and exit (clean install, no migration needed)
            defaults.set(true, forKey: GmailAccountStore.migrationDoneKey)
            return nil
        }

        let normalizedEmail = legacyEmail.lowercased()

        // Guard 3: legacy refresh token must exist in Keychain
        // load() returns String? and throws; try? wraps in another optional → String??
        // Flatten with ?? nil to get String?
        let loadedToken: String? = (try? keychain.load(forKey: GmailAccountStore.legacyRefreshTokenKey)) ?? nil
        guard let legacyToken = loadedToken else {
            // No legacy token → set flag and exit
            defaults.set(true, forKey: GmailAccountStore.migrationDoneKey)
            return nil
        }

        let perAccountKey = refreshTokenKey(for: normalizedEmail)

        // Step 2: Copy token to per-account Keychain key
        do {
            try keychain.save(legacyToken, forKey: perAccountKey)
        } catch {
            // If we can't write the per-account token, abort to avoid losing the legacy token
            return nil
        }

        // Step 3: Confirm the per-account token was written
        guard let confirmedToken = try? keychain.load(forKey: perAccountKey),
              confirmedToken == legacyToken else {
            // Token not confirmed — do NOT delete the legacy token; abort migration
            return nil
        }

        // Step 4: Seed a GmailAccount from legacy metadata
        let legacyExpiry = defaults.object(forKey: GmailAccountStore.legacyTokenExpiryKey) as? Date
        let legacyLastSynced = defaults.object(forKey: GmailAccountStore.legacyLastSyncedKey) as? Date
        let account = GmailAccount(
            email: normalizedEmail,
            accessTokenExpiry: legacyExpiry,
            lastSyncedAt: legacyLastSynced,
            needsReconnect: false
        )
        addOrUpdate(account)

        // Step 5: Clear legacy UserDefaults keys
        defaults.removeObject(forKey: GmailAccountStore.legacyEmailKey)
        defaults.removeObject(forKey: GmailAccountStore.legacyLastSyncedKey)
        defaults.removeObject(forKey: GmailAccountStore.legacyTokenExpiryKey)

        // Step 6: Delete legacy refresh_token from Keychain
        // (safe: per-account copy is confirmed in step 3)
        try? keychain.delete(forKey: GmailAccountStore.legacyRefreshTokenKey)

        // Step 7: Set the one-shot migration-done flag
        defaults.set(true, forKey: GmailAccountStore.migrationDoneKey)

        // D-MA-06(a): Backfill sourceAccount on legacy expenses (if context available)
        if let ctx = modelContext {
            backfillSourceAccount(email: normalizedEmail, modelContext: ctx)
        }
        // If no context is available, the backfill is deferred to the first syncAccount run
        // for this email (GmailSyncController checks the migrated flag and runs it there).

        return normalizedEmail
    }

    // MARK: - D-MA-06(a): Legacy expense backfill

    /// Backfills `sourceAccount = email` on all existing Expenses that have a non-nil
    /// `gmailMessageID` and a nil `sourceAccount`.
    ///
    /// Called after migrateLegacyIfNeeded when a ModelContext is available.
    /// Also callable from GmailSyncController.syncAccount on first sync if context was nil at init.
    public func backfillSourceAccount(email: String, modelContext: ModelContext) {
        let key = email.lowercased()
        do {
            let descriptor = FetchDescriptor<Expense>()
            let expenses = try modelContext.fetch(descriptor)
            var changed = false
            for expense in expenses {
                if expense.gmailMessageID != nil && expense.sourceAccount == nil {
                    expense.sourceAccount = key
                    changed = true
                }
            }
            if changed {
                try? modelContext.save()
            }
        } catch {
            // Best-effort backfill; errors are non-fatal
        }
    }

    // MARK: - Private helpers

    private func loadAccountsDict() -> [String: GmailAccount] {
        guard let data = defaults.data(forKey: GmailAccountStore.accountsDictKey) else { return [:] }
        return (try? JSONDecoder().decode([String: GmailAccount].self, from: data)) ?? [:]
    }

    private func saveAccountsDict(_ dict: [String: GmailAccount]) {
        if let data = try? JSONEncoder().encode(dict) {
            defaults.set(data, forKey: GmailAccountStore.accountsDictKey)
        }
    }
}
