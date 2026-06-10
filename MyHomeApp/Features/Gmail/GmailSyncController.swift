import Foundation
import SwiftUI
import SwiftData
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

// MARK: - GmailSyncController

/// Observable state controller for multi-account Gmail sign-in, sync, and token management.
///
/// Owned by RootView via `@State private var gmailSyncController = GmailSyncController()`.
///
/// Multi-account design (D-MA-01..06, 260603-lvt):
/// - Account identity = lowercased Gmail address from GmailFetchPort.getProfile (D-MA-01).
/// - Per-account refresh token in Keychain under `refresh_token_<email>` (SEC-03, D-MA-02).
/// - Per-account non-secret metadata in GmailAccountStore → UserDefaults `gmail_accounts_v2` (D-MA-02).
/// - Access tokens in-memory only in `accessTokenMap[email]` (D6-07, D-MA-04).
/// - signIn() is an "add account" operation — does NOT clobber existing accounts.
/// - sync() loops all connected accounts; one expired account is isolated (T-MA-04).
/// - signOut(email:) removes a single account; signOutAll() removes all.
///
/// Legacy compatibility (upgrade from single-account build):
/// - init calls store.migrateLegacyIfNeeded so the already-connected account survives with no re-auth.
/// - `accessToken` property provides backward-compat for tests that inject a token directly.
///
/// All async methods are @MainActor because they mutate @Observable state.
@MainActor
@Observable
final class GmailSyncController {

    // MARK: - Per-account state (GmailAccountStore → UserDefaults)

    /// The GmailAccountStore managing connected accounts metadata.
    /// Exposed as `internal(set)` so tests can read `store.accounts`.
    private(set) var store: GmailAccountStore

    // MARK: - In-memory state

    /// Per-account in-memory access tokens — NEVER persisted (D6-07, D-MA-04).
    /// Keyed by lowercased email address.
    private var accessTokenMap: [String: String] = [:]

    /// Legacy/test-compat in-memory access token — used when no accounts are in the store.
    /// Setting this injects a token for the single-account legacy sync path (tests).
    var accessToken: String? = nil

    /// Current sync pipeline state.
    var syncStatus: SyncStatus = .idle

    /// Last OAuth/Keychain error, or nil.
    var authError: GmailAuthError? = nil

    // MARK: - Derived state

    /// Whether any refresh token is stored (i.e., at least one account is connected).
    ///
    /// Derived from the store's account count so it stays observable through @Observable.
    private(set) var isConnected: Bool = false

    /// Whether the access token has expired according to the stored expiry date.
    /// Checks the first connected account's expiry (legacy compat for single-account views).
    /// D6-06: Check expiry within 5 minutes before each sync.
    var isTokenExpired: Bool {
        guard let expiry = accessTokenExpiry else { return true }
        return expiry < now()
    }

    /// Whether the access token will expire within 5 minutes (triggers proactive refresh).
    /// D6-06: Returns true when no expiry date is stored (unknown freshness) or expiry is within 5 min.
    var needsProactiveRefresh: Bool {
        guard let expiry = accessTokenExpiry else { return true }
        return expiry.timeIntervalSince(now()) < 300
    }

    // MARK: - Legacy/compat computed properties
    // These read from the first connected account's metadata for backward compatibility
    // with single-account views and tests. They delegate to the store on get and update
    // the primary account's metadata on set.

    /// Email address of the first connected account (or nil if no accounts connected).
    /// D-MA-01: Set from GmailFetchPort.getProfile; lowercased.
    var connectedEmail: String? {
        get { store.accounts.first?.email }
        set {
            // Legacy setter: if an account exists with that email, it's already there.
            // If newValue is nil (signOut), do nothing here — handled by signOut(email:).
            // No-op for backwards compatibility with tests that assign connectedEmail directly.
            if let email = newValue {
                let acct = store.accounts.first { $0.email == email } ?? GmailAccount(email: email)
                store.addOrUpdate(acct)
            }
        }
    }

    /// Last-synced date of the first connected account (legacy compat).
    var lastSyncedAt: Date? {
        get { store.accounts.first?.lastSyncedAt }
        set {
            if let first = store.accounts.first {
                store.update(email: first.email) { $0.lastSyncedAt = newValue }
            }
        }
    }

    /// Access token expiry of the first connected account (legacy compat).
    var accessTokenExpiry: Date? {
        get { store.accounts.first?.accessTokenExpiry }
        set {
            if let first = store.accounts.first {
                store.update(email: first.email) { $0.accessTokenExpiry = newValue }
            }
        }
    }

    // MARK: - Dependencies

    private let auth: any GmailAuthPort
    private let keychain: any KeychainPort
    private let fetch: any GmailFetchPort
    /// Provides the current time; injectable for deterministic expiry tests.
    private let now: () -> Date

    /// ModelContext for persisting ingested expenses.
    var modelContext: ModelContext? = nil

    /// Transfer scan service injected by RootView — called after each sync to score new pairs (D-08).
    /// Optional so tests that don't need transfer detection stay unaffected.
    var transferScanService: TransferScanService? = nil

    /// App Group UserDefaults backing all persistent metadata.
    private let defaults: UserDefaults

    // MARK: - Pipeline components

    private let parsers: [any BankEmailParser] = [HDFCParser(), ICICIParser(), CUBParser()]
    private static let bankSenderFilter = "from:(hdfcbank.bank.in OR icici.bank.in OR cityunionbank.org)"
    private static let initialBackfillDays = 120
    static let autoSaveThreshold: Double = ConfidenceScorer.autoSaveThreshold

    // MARK: - Init

    /// Creates a GmailSyncController with injected ports and optional dependencies.
    ///
    /// - Parameters:
    ///   - auth: GmailAuthPort conformer; defaults to SystemGmailAuth() in production.
    ///   - keychain: KeychainPort conformer; defaults to SystemKeychainStore() in production.
    ///   - fetch: GmailFetchPort conformer; defaults to SystemGmailFetch() in production.
    ///   - now: Time provider; defaults to Date.init. Injectable for tests.
    ///   - defaults: Backing UserDefaults; defaults to App Group suite. Injectable for isolation.
    ///   - accountStore: Pre-built GmailAccountStore; if nil, one is created from defaults+keychain.
    init(
        auth: any GmailAuthPort = SystemGmailAuth(),
        keychain: any KeychainPort = SystemKeychainStore(),
        fetch: any GmailFetchPort = SystemGmailFetch(),
        now: @escaping () -> Date = Date.init,
        defaults: UserDefaults = UserDefaults(suiteName: "group.com.reojacob.myhome") ?? .standard,
        accountStore: GmailAccountStore? = nil
    ) {
        self.auth = auth
        self.keychain = keychain
        self.fetch = fetch
        self.now = now
        self.defaults = defaults

        // Build or use the provided store
        let builtStore = accountStore ?? GmailAccountStore(defaults: defaults, keychain: keychain)
        self.store = builtStore

        // Seed connection state from store
        self.isConnected = !builtStore.accounts.isEmpty

        // Legacy: also check for a bare `refresh_token` Keychain item (pre-migration installs)
        if !self.isConnected {
            self.isConnected = (try? keychain.load(forKey: "refresh_token")) != nil
        }
    }

    /// Runs the legacy forward-migration after the modelContext is available (D-MA-06(a)).
    ///
    /// Called from setContext if the store has not yet migrated.
    private func runMigrationIfNeeded() {
        let migrationDone = defaults.bool(forKey: GmailAccountStore.migrationDoneKey)
        if !migrationDone {
            let migratedEmail = store.migrateLegacyIfNeeded(keychain: keychain, modelContext: modelContext)
            if migratedEmail != nil {
                updateIsConnected()
            }
        }
    }

    /// Injects the ModelContext for ingestion persistence.
    func setContext(_ context: ModelContext) {
        self.modelContext = context
        // Run migration now that context is available (D-MA-06(a) deferred backfill)
        runMigrationIfNeeded()
        // If already migrated but backfill wasn't run (context was nil at init), do it now.
        // The backfill is idempotent (only affects expenses with nil sourceAccount).
        if let firstAccount = store.accounts.first,
           defaults.bool(forKey: GmailAccountStore.migrationDoneKey) {
            // Migration already ran — check if backfill needs to run (deferred case)
            store.backfillSourceAccount(email: firstAccount.email, modelContext: context)
        }
    }

    private func updateIsConnected() {
        isConnected = !store.accounts.isEmpty || (try? keychain.load(forKey: "refresh_token")) != nil
    }

    // MARK: - Scene phase hook

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

    // MARK: - OAuth sign-in (add account)

    /// Initiates the full OAuth + PKCE sign-in flow and adds the resulting account.
    ///
    /// Multi-account: calling signIn() when already connected adds a SECOND account;
    /// it does NOT disconnect the first account (no clobber). D-MA-02.
    ///
    /// D6-08: Immediate first sync on OAuth success (for the new account only).
    /// ING-02: signIn drives syncStatus idle → done.
    func signIn() async {
        syncStatus = .authorizing
        authError = nil

        do {
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

            let code = try await auth.authorize(
                authURL: authURL,
                callbackScheme: GmailOAuthConfig.callbackScheme,
                expectedState: state
            )

            let tokenResponse = try await auth.exchangeCode(
                code,
                verifier: pkce.verifier,
                clientID: GmailOAuthConfig.clientID,
                redirectURI: GmailOAuthConfig.redirectURI
            )

            guard let refreshToken = tokenResponse.refresh_token else {
                syncStatus = .error("no refresh token — missing access_type=offline")
                return
            }

            // D-MA-01: obtain the email before storing under the per-account key
            let profile = try await fetch.getProfile(accessToken: tokenResponse.access_token)
            let email = profile.emailAddress.lowercased()

            // SEC-03: Store refresh token in Keychain under per-account key (D-MA-02)
            try keychain.save(refreshToken, forKey: store.refreshTokenKey(for: email))

            // D6-07: access_token in memory only; expiry in UserDefaults
            accessTokenMap[email] = tokenResponse.access_token
            let expiry = now().addingTimeInterval(TimeInterval(tokenResponse.expires_in))

            // Seed/update account in store
            store.addOrUpdate(GmailAccount(
                email: email,
                accessTokenExpiry: expiry,
                lastSyncedAt: nil,
                needsReconnect: false
            ))
            isConnected = true

            // D6-08: Perform initial sync for this account
            let syncSuccess = await syncAccount(email: email, accessToken: tokenResponse.access_token)
            if syncSuccess {
                store.update(email: email) { acct in
                    acct.lastSyncedAt = now()
                    acct.needsReconnect = false
                }
            }

            syncStatus = .done

        } catch let gmailError as GmailAuthError {
            switch gmailError {
            case .oauthError(let msg):
                authError = gmailError
                syncStatus = .error(msg)
            case .stateMismatch:
                authError = gmailError
                syncStatus = .error("Sign-in rejected: response did not match the request. Please try again.")
            default:
                syncStatus = .idle
            }
        } catch {
            syncStatus = .error(error.localizedDescription)
        }
    }

    // MARK: - Multi-account sync

    /// Syncs all connected accounts. One expired account does not abort the others (T-MA-04).
    ///
    /// ING-03: sync transitions idle → syncing → done.
    func sync() async {
        // Refresh the store's account list
        let connectedAccounts = store.accounts

        // Legacy / test compat: if no accounts in store but accessToken is set directly,
        // run a single-account sync using the legacy path.
        if connectedAccounts.isEmpty {
            await legacySingleAccountSync()
            return
        }

        syncStatus = .syncing
        var anySuccess = false

        for account in connectedAccounts {
            let accountEmail = account.email

            // Proactive refresh for this account
            let tokenKey = store.refreshTokenKey(for: accountEmail)
            let currentToken: String?

            if let inMemToken = accessTokenMap[accountEmail] {
                // Use existing in-memory token unless it's expiring soon
                if let expiry = account.accessTokenExpiry,
                   expiry.timeIntervalSince(now()) > 300 {
                    currentToken = inMemToken
                } else {
                    // Refresh
                    currentToken = await refreshAccessToken(forKey: tokenKey, accountEmail: accountEmail)
                }
            } else {
                // No in-memory token — always refresh
                currentToken = await refreshAccessToken(forKey: tokenKey, accountEmail: accountEmail)
            }

            guard let token = currentToken else {
                // Refresh failed (e.g. invalid_grant) — mark needsReconnect, continue other accounts
                store.update(email: accountEmail) { acct in
                    acct.needsReconnect = true
                }
                continue
            }

            let success = await syncAccount(email: accountEmail, accessToken: token)
            if success {
                anySuccess = true
                store.update(email: accountEmail) { acct in
                    acct.lastSyncedAt = now()
                    acct.needsReconnect = false
                }
            }
        }

        syncStatus = anySuccess ? .done : .tokenExpired
    }

    /// Refreshes the access token for the given keychain key.
    /// Returns the new access token, or nil if refresh failed (marks needsReconnect).
    private func refreshAccessToken(forKey tokenKey: String, accountEmail: String) async -> String? {
        // load() returns String? and throws; try? makes it String?? — flatten with ?? nil
        let storedRefreshTokenOpt: String? = (try? keychain.load(forKey: tokenKey)) ?? nil
        guard let storedRefreshToken = storedRefreshTokenOpt else {
            // No stored refresh token for this account
            store.update(email: accountEmail) { $0.needsReconnect = true }
            return nil
        }
        do {
            let refreshResponse = try await auth.refreshToken(
                storedRefreshToken,
                clientID: GmailOAuthConfig.clientID
            )
            accessTokenMap[accountEmail] = refreshResponse.access_token
            let expiry = now().addingTimeInterval(TimeInterval(refreshResponse.expires_in))
            store.update(email: accountEmail) { $0.accessTokenExpiry = expiry }
            return refreshResponse.access_token
        } catch {
            let errMsg = error.localizedDescription.lowercased()
            if errMsg.contains("invalid_grant") || errMsg.contains("401") || errMsg.contains("unauthorized") {
                store.update(email: accountEmail) { $0.needsReconnect = true }
            }
            return nil
        }
    }

    // MARK: - Per-account sync body

    /// Syncs a single account: fetch → parse → dedup → ingest.
    /// Returns true on success, false if a recoverable or non-fatal error occurred.
    ///
    /// The idempotency guard is (sourceAccount, gmailMessageID)-scoped (D-MA-03, T-MA-05).
    /// D-MA-06(b): nil-sourceAccount expenses match ANY account for their messageID (legacy fallback).
    private func syncAccount(email: String, accessToken: String) async -> Bool {
        // D6-10: Compute query window
        let accountLastSync = store.accounts.first { $0.email == email }?.lastSyncedAt
        let query: String
        if let last = accountLastSync {
            let daysSince = Int(now().timeIntervalSince(last) / 86400)
            query = "\(GmailSyncController.bankSenderFilter) newer_than:\(max(1, daysSince))d"
        } else {
            query = "\(GmailSyncController.bankSenderFilter) newer_than:\(GmailSyncController.initialBackfillDays)d"
        }

        do {
            // Step 1: getProfile → confirm email (D-MA-01, UAT-6-05)
            let profile = try await fetch.getProfile(accessToken: accessToken)
            let confirmedEmail = profile.emailAddress.lowercased()

            // Update connectedEmail for the primary account (legacy compat for Settings display)
            // If this is the only account or the first account, also update the store email if needed
            if confirmedEmail != email {
                // The confirmed email differs from what we thought — use confirmed email
                // (this can happen if the token was obtained for a different account)
                accessTokenMap[confirmedEmail] = accessTokenMap[email]
                accessTokenMap.removeValue(forKey: email)
                store.addOrUpdate(GmailAccount(email: confirmedEmail))
            }

            // Step 2: list message IDs
            let messageIDs = try await fetch.listMessageIDs(
                accessToken: accessToken, q: query, maxResults: 50
            )

            // Step 3: Fetch existing expenses for dedup
            let existingExpenses: [Expense]
            if let ctx = modelContext {
                existingExpenses = (try? ctx.fetch(FetchDescriptor<Expense>())) ?? []
            } else {
                existingExpenses = []
            }

            // D-MA-03 + D-MA-06(b): Build account-scoped idempotency set.
            // Exact match on (sourceAccount, gmailMessageID) for expenses with a sourceAccount.
            // For expenses with nil sourceAccount (legacy), match on messageID alone (fallback).
            let accountMessageIDs: Set<String> = Set(existingExpenses.compactMap { expense -> String? in
                guard let msgID = expense.gmailMessageID else { return nil }
                if let src = expense.sourceAccount {
                    // Exact account-scoped match: only skip if SAME account
                    return src == confirmedEmail ? msgID : nil
                } else {
                    // D-MA-06(b): nil-sourceAccount → match any account (legacy fallback)
                    return msgID
                }
            })

            // Step 4: Capture category PersistentIdentifiers once (D-04: Sendable value types,
            // safe across await suspension — replaces captured [String: Category] @Model refs).
            var categoryIDsByName: [String: PersistentIdentifier] = [:]
            if let ctx = modelContext {
                for cat in (try? ctx.fetch(FetchDescriptor<Category>())) ?? [] {
                    if let name = cat.name { categoryIDsByName[name] = cat.persistentModelID }
                }
            }

            // D-05 / STAB-02: Capture account UUID map once before the per-message loop.
            // Plain [String: UUID] — no @Model refs held across await (mirrors categoryIDsByName).
            // Archived accounts excluded (T-09-09 / Pitfall 6).
            let accountIDsByLabel: [String: UUID]
            if let ctx = modelContext {
                let allAccounts = (try? ctx.fetch(FetchDescriptor<Account>())) ?? []
                accountIDsByLabel = AccountAttributionHelper.buildAccountIDsByLabel(from: allAccounts)
            } else {
                accountIDsByLabel = [:]
            }

            // Step 5: Process each message
            for messageID in messageIDs {
                if DismissedMessageStore.isDismissed(messageID) { continue }
                if accountMessageIDs.contains(messageID) { continue }

                let rawEmail = try await fetch.getRawMessage(accessToken: accessToken, messageID: messageID)
                let sender = emailAddress(from: extractHeader("From", from: rawEmail))
                let subject = extractHeader("Subject", from: rawEmail)

                guard let parser = parsers.first(where: { $0.canHandle(sender: sender, subject: subject) }) else {
                    continue
                }
                guard let parsed = parser.parse(rawEmail: rawEmail) else { continue }

                let confidence = ConfidenceScorer.score(parsed)
                let duplicate = DedupChecker.findDuplicate(of: parsed, in: existingExpenses)

                let ingestionState: String
                if duplicate != nil {
                    ingestionState = "possibleDuplicate"
                } else if confidence >= GmailSyncController.autoSaveThreshold {
                    ingestionState = "autoSaved"
                } else {
                    ingestionState = "needsReview"
                }

                let expense = Expense(
                    amount: parsed.isReversal ? -abs(parsed.amount) : parsed.amount,
                    date: parsed.date,
                    note: parsed.normalizedMerchant.isEmpty ? parsed.rawMerchant : parsed.normalizedMerchant
                )
                expense.rawEmailBody = rawEmail
                expense.parserID = parser.parserID
                expense.parserVersion = parser.parserVersion
                expense.sourceLabel = parsed.rawSourceLabel
                expense.gmailMessageID = messageID
                expense.parseConfidence = confidence
                expense.ingestionStateRaw = ingestionState
                expense.sourceAccount = confirmedEmail    // D-MA-03: stamp owning account

                // D-05: Auto-attribute to matching active account by sourceLabel.
                // Uses pre-loop UUID map — no @Model refs across await (STAB-02).
                // No match → accountID stays nil (Unassigned).
                expense.accountID = AccountAttributionHelper.accountID(
                    forSourceLabel: parsed.rawSourceLabel,
                    in: accountIDsByLabel
                )

                // D-04: Re-resolve Category by PersistentIdentifier after the await suspension.
                // On failed re-fetch (nil, deleted), skip category assignment and continue (D-03).
                if let hint = parsed.categoryHint,
                   let catID = categoryIDsByName[hint],
                   let ctx = modelContext,
                   let cat = ctx.model(for: catID) as? Category {
                    expense.categories = [cat]
                }

                if let ctx = modelContext {
                    ctx.insert(expense)
                }
            }

            // D-04: Single batched save after the loop (not inside the per-message loop).
            if let ctx = modelContext {
                try ctx.save()
            }
            // D-08: run transfer scorer after each sync (synchronous @MainActor call — no STAB-02 risk)
            transferScanService?.scan()
            return true

        } catch {
            let errMsg = error.localizedDescription.lowercased()
            if errMsg.contains("401") || errMsg.contains("unauthorized") || errMsg.contains("invalid_grant") {
                store.update(email: email) { $0.needsReconnect = true }
            }
            return false
        }
    }

    // MARK: - Legacy single-account sync (test compat + no-accounts path)

    /// Single-account sync path: used when no accounts are in the store but an
    /// `accessToken` was injected directly (test compat) or legacy state exists.
    private func legacySingleAccountSync() async {
        let shouldRefresh = accessToken == nil || (accessTokenExpiry != nil && needsProactiveRefresh)
        if shouldRefresh {
            // load() returns String?; try? makes it String?? — flatten with ?? nil
            let legacyTokenOpt: String? = (try? keychain.load(forKey: "refresh_token")) ?? nil
            guard let storedRefreshToken = legacyTokenOpt else {
                syncStatus = .tokenExpired
                return
            }
            do {
                let refreshResponse = try await auth.refreshToken(
                    storedRefreshToken,
                    clientID: GmailOAuthConfig.clientID
                )
                accessToken = refreshResponse.access_token
                // Update expiry on the first account if one exists, else use a local var
                let expiry = now().addingTimeInterval(TimeInterval(refreshResponse.expires_in))
                if let first = store.accounts.first {
                    store.update(email: first.email) { $0.accessTokenExpiry = expiry }
                }
            } catch {
                syncStatus = .tokenExpired
                return
            }
        }

        syncStatus = .syncing

        guard let token = accessToken else {
            syncStatus = .tokenExpired
            return
        }

        // D6-10: query window
        let lastSync = store.accounts.first?.lastSyncedAt
        let query: String
        if let last = lastSync {
            let daysSince = Int(now().timeIntervalSince(last) / 86400)
            query = "\(GmailSyncController.bankSenderFilter) newer_than:\(max(1, daysSince))d"
        } else {
            query = "\(GmailSyncController.bankSenderFilter) newer_than:\(GmailSyncController.initialBackfillDays)d"
        }

        do {
            let profile = try await fetch.getProfile(accessToken: token)
            let email = profile.emailAddress.lowercased()

            // Update or seed the account in the store for legacy compat
            if store.accounts.first(where: { $0.email == email }) == nil {
                store.addOrUpdate(GmailAccount(email: email))
                isConnected = true
            }

            let messageIDs = try await fetch.listMessageIDs(accessToken: token, q: query, maxResults: 50)

            let existingExpenses: [Expense]
            if let ctx = modelContext {
                existingExpenses = (try? ctx.fetch(FetchDescriptor<Expense>())) ?? []
            } else {
                existingExpenses = []
            }

            // Legacy single-account dedup (messageID only — no sourceAccount context)
            let ingestedMessageIDs = Set(existingExpenses.compactMap { $0.gmailMessageID })

            // D-04: Capture category PersistentIdentifiers once (Sendable value types,
            // safe across the await suspension — replaces captured [String: Category] @Model refs).
            var categoryIDsByName: [String: PersistentIdentifier] = [:]
            if let ctx = modelContext {
                for cat in (try? ctx.fetch(FetchDescriptor<Category>())) ?? [] {
                    if let name = cat.name { categoryIDsByName[name] = cat.persistentModelID }
                }
            }

            for messageID in messageIDs {
                if DismissedMessageStore.isDismissed(messageID) { continue }
                if ingestedMessageIDs.contains(messageID) { continue }

                let rawEmail = try await fetch.getRawMessage(accessToken: token, messageID: messageID)
                let sender = emailAddress(from: extractHeader("From", from: rawEmail))
                let subject = extractHeader("Subject", from: rawEmail)

                guard let parser = parsers.first(where: { $0.canHandle(sender: sender, subject: subject) }) else {
                    continue
                }
                guard let parsed = parser.parse(rawEmail: rawEmail) else { continue }

                let confidence = ConfidenceScorer.score(parsed)
                let duplicate = DedupChecker.findDuplicate(of: parsed, in: existingExpenses)

                let ingestionState: String
                if duplicate != nil {
                    ingestionState = "possibleDuplicate"
                } else if confidence >= GmailSyncController.autoSaveThreshold {
                    ingestionState = "autoSaved"
                } else {
                    ingestionState = "needsReview"
                }

                let expense = Expense(
                    amount: parsed.isReversal ? -abs(parsed.amount) : parsed.amount,
                    date: parsed.date,
                    note: parsed.normalizedMerchant.isEmpty ? parsed.rawMerchant : parsed.normalizedMerchant
                )
                expense.rawEmailBody = rawEmail
                expense.parserID = parser.parserID
                expense.parserVersion = parser.parserVersion
                expense.sourceLabel = parsed.rawSourceLabel
                expense.gmailMessageID = messageID
                expense.parseConfidence = confidence
                expense.ingestionStateRaw = ingestionState
                expense.sourceAccount = email    // stamp account even in legacy path

                // D-04: Re-resolve Category by PersistentIdentifier after the await suspension.
                // On failed re-fetch (nil, deleted), skip category assignment and continue (D-03).
                if let hint = parsed.categoryHint,
                   let catID = categoryIDsByName[hint],
                   let ctx = modelContext,
                   let cat = ctx.model(for: catID) as? Category {
                    expense.categories = [cat]
                }

                if let ctx = modelContext {
                    ctx.insert(expense)
                }
            }

            // D-04: Single batched save after the loop (not inside the per-message loop).
            if let ctx = modelContext {
                try ctx.save()
            }
            // D-08: run transfer scorer after the legacy sync too (CR-02 — the legacy path
            // previously skipped this hook, silently non-detecting for pre-migration users).
            transferScanService?.scan()
        } catch {
            let errMsg = error.localizedDescription.lowercased()
            if errMsg.contains("401") || errMsg.contains("unauthorized") || errMsg.contains("invalid_grant") {
                syncStatus = .tokenExpired
                return
            }
            syncStatus = .error(error.localizedDescription)
            return
        }

        // Update lastSyncedAt on the first account (or the account we just seeded)
        if let first = store.accounts.first {
            store.update(email: first.email) { $0.lastSyncedAt = now() }
        }
        syncStatus = .done
    }

    // MARK: - Sign out

    /// Removes a specific Gmail account: deletes its Keychain refresh token and store metadata.
    /// If no accounts remain, isConnected becomes false.
    ///
    /// D-MA-05: UI calls signOut(email:) for per-account disconnect.
    func signOut(email: String) {
        store.remove(email: email)
        accessTokenMap.removeValue(forKey: email.lowercased())
        updateIsConnected()
        if store.accounts.isEmpty {
            syncStatus = .idle
        }
    }

    /// Removes all Gmail accounts and clears all Gmail-related state.
    ///
    /// D6-17: Sign out removes refresh tokens from Keychain, clears UserDefaults.
    /// SET-04: User can sign out of Gmail.
    func signOut() {
        // Remove all accounts
        for account in store.accounts {
            store.remove(email: account.email)
            accessTokenMap.removeValue(forKey: account.email)
        }
        // Legacy: also delete the bare refresh_token if it exists
        try? keychain.delete(forKey: "refresh_token")
        // Clear legacy UserDefaults keys
        defaults.removeObject(forKey: "gmail_connected_email")
        defaults.removeObject(forKey: "gmail_last_synced_at")
        defaults.removeObject(forKey: "gmail_access_token_expiry")
        accessToken = nil
        isConnected = false
        syncStatus = .idle
    }

    // MARK: - Authorization URL builder

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
            URLQueryItem(name: "access_type", value: "offline"),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "prompt", value: "consent"),
        ]
        return components?.url
    }

    // MARK: - Private helpers

    private nonisolated func extractHeader(_ name: String, from rawEmail: String) -> String {
        let lines = rawEmail.components(separatedBy: "\n")
        let prefix = "\(name):"
        for (idx, line) in lines.enumerated() {
            if line.hasPrefix(prefix) {
                var value = String(line.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
                var nextIdx = idx + 1
                while nextIdx < lines.count {
                    let next = lines[nextIdx]
                    if next.first == " " || next.first == "\t" {
                        value += " " + next.trimmingCharacters(in: .whitespacesAndNewlines)
                        nextIdx += 1
                    } else {
                        break
                    }
                }
                return value
            }
        }
        return ""
    }

    private nonisolated func emailAddress(from headerValue: String) -> String {
        if let open = headerValue.lastIndex(of: "<"),
           let close = headerValue.lastIndex(of: ">"),
           open < close {
            let inner = headerValue[headerValue.index(after: open)..<close]
            return inner.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return headerValue.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
