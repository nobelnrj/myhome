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
    private let fetch: any GmailFetchPort
    /// Provides the current time; injectable for deterministic expiry tests.
    private let now: () -> Date

    /// ModelContext for persisting ingested expenses. Injected by RootView (foreground) or
    /// set from MyHomeApp's BGTask handler (background — uses a fresh container).
    var modelContext: ModelContext? = nil

    /// App Group UserDefaults backing all persistent metadata (lastSyncedAt, expiry, connectedEmail).
    /// Injectable so tests can isolate state — sharing the live App Group suite across parallel test
    /// suites caused a race where one suite cleared `gmail_connected_email` mid-sync (UAT-6-05 flake).
    private let defaults: UserDefaults

    // MARK: - Pipeline components

    /// The bank email parsers registered for ingestion (HDFC, ICICI — ING-06/07/08/09).
    private let parsers: [any BankEmailParser] = [HDFCParser(), ICICIParser()]

    /// Confirmed bank sender domains used to build the Gmail query filter (T-07-09).
    private static let bankSenderFilter = "from:(hdfcbank.bank.in OR icici.bank.in)"

    /// First-sync backfill window in days. D6-08 originally used 30d; widened to 120d (~4 months)
    /// so the initial sync captures a meaningful spend history. Incremental syncs still use the
    /// days-since-last-sync window.
    private static let initialBackfillDays = 120

    /// Minimum confidence score for auto-saving an expense without review (ING-12, D7-03).
    ///
    /// Exposed as a named constant — tunable, pending real-usage calibration (D7-03).
    static let autoSaveThreshold: Double = ConfidenceScorer.autoSaveThreshold

    // MARK: - Init

    /// Creates a GmailSyncController with injected ports and optional time provider.
    /// - Parameters:
    ///   - auth: `GmailAuthPort` conformer; defaults to `SystemGmailAuth()` in production.
    ///   - keychain: `KeychainPort` conformer; defaults to `SystemKeychainStore()` in production.
    ///   - fetch: `GmailFetchPort` conformer; defaults to `SystemGmailFetch()` in production.
    ///   - now: Time provider; defaults to `Date.init` in production. Injectable for tests.
    ///   - defaults: Backing `UserDefaults`; defaults to the App Group suite. Injectable for test isolation.
    init(
        auth: any GmailAuthPort = SystemGmailAuth(),
        keychain: any KeychainPort = SystemKeychainStore(),
        fetch: any GmailFetchPort = SystemGmailFetch(),
        now: @escaping () -> Date = Date.init,
        defaults: UserDefaults = UserDefaults(suiteName: "group.com.reojacob.myhome") ?? .standard
    ) {
        self.auth = auth
        self.keychain = keychain
        self.fetch = fetch
        self.now = now
        self.defaults = defaults
        // Seed connection state from Keychain at launch so the UI reflects a prior sign-in.
        self.isConnected = (try? keychain.load(forKey: "refresh_token")) != nil
    }

    /// Injects the ModelContext for ingestion persistence.
    ///
    /// Called by RootView on appear (foreground path) and by the BGTask handler
    /// using a fresh container (background path — Open Question 3).
    func setContext(_ context: ModelContext) {
        self.modelContext = context
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

            // Present the OAuth browser and await the authorization code.
            // expectedState binds the callback to this request (T-06-CSRF): the conformer
            // rejects any callback whose `state` doesn't match the value we put in authURL.
            let code = try await auth.authorize(
                authURL: authURL,
                callbackScheme: GmailOAuthConfig.callbackScheme,
                expectedState: state
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
            switch gmailError {
            case .oauthError(let msg):
                authError = gmailError
                syncStatus = .error(msg)
            case .stateMismatch:
                // T-06-CSRF: a mismatched callback state is a security rejection, not a benign
                // cancel — surface it so the user/owner knows the sign-in was refused.
                authError = gmailError
                syncStatus = .error("Sign-in rejected: response did not match the request. Please try again.")
            default:
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

        // D6-10: Compute query — initial backfill window on first sync (no watermark);
        // newer_than:<days-since-last-sync> on incremental syncs.
        let query: String
        if let last = lastSyncedAt {
            let daysSince = Int(now().timeIntervalSince(last) / 86400)
            let bankFilter = GmailSyncController.bankSenderFilter
            query = "\(bankFilter) newer_than:\(max(1, daysSince))d"
        } else {
            query = "\(GmailSyncController.bankSenderFilter) newer_than:\(GmailSyncController.initialBackfillDays)d"
        }

        // Run the full ingestion pipeline (ING-12/13/14, UAT-6-05).
        // Any fetch/parse error sets .error or .tokenExpired — Phase 6 token mitigations intact.
        do {
            guard let token = accessToken else {
                syncStatus = .tokenExpired
                return
            }

            // Step 1: getProfile → connectedEmail (UAT-6-05)
            let profile = try await fetch.getProfile(accessToken: token)
            connectedEmail = profile.emailAddress

            // Step 2: list message IDs matching the bank sender + time filter (T-07-09)
            let messageIDs = try await fetch.listMessageIDs(accessToken: token, q: query, maxResults: 50)

            // Step 3: Fetch existing expenses for dedup (caller supplies array — DedupChecker pattern)
            let existingExpenses: [Expense]
            if let ctx = modelContext {
                existingExpenses = (try? ctx.fetch(FetchDescriptor<Expense>())) ?? []
            } else {
                existingExpenses = []
            }

            // ING-14: message IDs already ingested — re-sync must be idempotent. The DedupChecker
            // (amount+merchant+date) flags matches against *other* emails / manual expenses; this
            // gmailMessageID guard prevents re-inserting the *same* email on every sync.
            let ingestedMessageIDs = Set(existingExpenses.compactMap { $0.gmailMessageID })

            // D7-09/D7-12/ING-15: resolve the parser's category hint to a seeded Category by name.
            // Fetched once (the seed is ~14 categories). Unknown merchants have a nil hint → the
            // expense stays uncategorised (Uncategorized fallback — D7-09).
            var categoriesByName: [String: Category] = [:]
            if let ctx = modelContext {
                for cat in (try? ctx.fetch(FetchDescriptor<Category>())) ?? [] {
                    if let name = cat.name { categoriesByName[name] = cat }
                }
            }

            // Step 4: Process each message through the pipeline
            for messageID in messageIDs {
                // D7-07: Skip already-dismissed message IDs
                if DismissedMessageStore.isDismissed(messageID) {
                    continue
                }

                // ING-14: Skip emails already ingested in a prior sync (idempotent re-sync)
                if ingestedMessageIDs.contains(messageID) {
                    continue
                }

                // Fetch the raw email
                let rawEmail = try await fetch.getRawMessage(accessToken: token, messageID: messageID)

                // Extract sender and subject from raw headers.
                // Normalize the From value to a bare address (unwrap `Display <addr>`) so the
                // parsers' host-suffix match works against real-world headers.
                let sender = emailAddress(from: extractHeader("From", from: rawEmail))
                let subject = extractHeader("Subject", from: rawEmail)

                // Pick the parser whose canHandle returns true
                guard let parser = parsers.first(where: { $0.canHandle(sender: sender, subject: subject) }) else {
                    continue
                }

                // Parse the email (fingerprint fail → skip)
                guard let parsed = parser.parse(rawEmail: rawEmail) else {
                    continue
                }

                // Triage: score + dedup
                let confidence = ConfidenceScorer.score(parsed)
                let duplicate = DedupChecker.findDuplicate(of: parsed, in: existingExpenses)

                // Build the ingestion state
                let ingestionState: String
                if duplicate != nil {
                    ingestionState = "possibleDuplicate"
                } else if confidence >= GmailSyncController.autoSaveThreshold {
                    ingestionState = "autoSaved"
                } else {
                    ingestionState = "needsReview"
                }

                // Persist the Expense (ING-10/11/12/13/14 — SchemaV4 fields)
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

                // D7-09/D7-12/ING-15: auto-categorise via the merchant→category hint.
                if let hint = parsed.categoryHint, let cat = categoriesByName[hint] {
                    expense.categories = [cat]
                }

                // Insert into SwiftData context if available
                if let ctx = modelContext {
                    ctx.insert(expense)
                    try ctx.save()
                }
            }
        } catch {
            // Token-expiry variants from fetch layer
            let errMsg = error.localizedDescription.lowercased()
            if errMsg.contains("401") || errMsg.contains("unauthorized") || errMsg.contains("invalid_grant") {
                syncStatus = .tokenExpired
                return
            }
            syncStatus = .error(error.localizedDescription)
            return
        }

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

    // MARK: - Private helpers

    /// Extracts a named email header value from a raw RFC 2822 email string.
    ///
    /// Handles folded headers (whitespace continuation lines). Real Gmail RAW emails use CRLF line
    /// endings, so values are trimmed with `.whitespacesAndNewlines` to strip the trailing `\r` —
    /// otherwise a sender like `credit_cards@icici.bank.in\r` fails the parser's host suffix match.
    /// Returns an empty string if the header is not found.
    private nonisolated func extractHeader(_ name: String, from rawEmail: String) -> String {
        let lines = rawEmail.components(separatedBy: "\n")
        let prefix = "\(name):"
        for (idx, line) in lines.enumerated() {
            if line.hasPrefix(prefix) {
                var value = String(line.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
                // Handle folded header continuation lines (RFC 2822: starts with whitespace)
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

    /// Normalizes a `From` header value to a bare email address for sender matching.
    ///
    /// Real `From` headers come in several forms: `addr@host`, `<addr@host>`, and
    /// `Display Name <addr@host>`. The bank parsers' `canHandle` matches on a host suffix
    /// (`@host` / `.host`), so the angle-bracketed address must be unwrapped first — otherwise a
    /// value ending in `>` (or carrying a display name) fails the match and a valid alert is dropped.
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
