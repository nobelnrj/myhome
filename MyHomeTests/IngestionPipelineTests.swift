import Testing
import SwiftData
import Foundation
@testable import MyHome

// Requirements: ING-10, ING-11, ING-12, ING-13, ING-14, UAT-6-05
// Threat ref: T-07-02 (rawEmailBody PII stored locally — Face ID gate already in place)
// Validation command: xcodebuild test ... -only-testing:MyHomeTests/IngestionPipelineTests
// Plan 07-06 — GREEN phase: real pipeline wired in GmailSyncController.sync().

// Disambiguate from the Objective-C runtime's `Category` typedef.
private typealias Cat = MyHome.Category

/// IngestionPipelineTests — integration tests for the end-to-end ingestion pipeline.
///
/// ING-10: rawEmailBody stored on the persisted Expense.
/// ING-11: parserID + parserVersion stored on the persisted Expense.
/// ING-12: confidence ≥ 0.85 → ingestionStateRaw = "autoSaved"; < 0.85 → "needsReview".
/// ING-13: needsReview expenses surface in the Review Inbox for one-tap correction.
/// ING-14: Duplicate detection prevents inserting the same expense twice.
/// UAT-6-05: After sync, connectedEmail is populated via SpyGmailFetch.getProfile.
///
/// .serialized: These tests share App Group UserDefaults (gmail_connected_email etc.) —
/// running them in parallel causes race conditions. Serialize to prevent interference.
@MainActor
@Suite(.serialized)
struct IngestionPipelineTests {

    private func makeContainer() throws -> ModelContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: Expense.self, Cat.self, Note.self, NoteBlock.self,
                                  configurations: config)
    }

    /// Per-test-instance isolated UserDefaults suite.
    ///
    /// Each test method runs on a fresh struct instance, so each gets its own suite. Injecting this
    /// into the controller (instead of the live App Group suite) prevents cross-suite races: previously
    /// a parallel GmailSyncControllerTests test could clear `gmail_connected_email` mid-sync — during
    /// `sync()`'s `listMessageIDs` await — flaking `connectedEmailPopulated` (UAT-6-05).
    private let defaults: UserDefaults = {
        let suiteName = "test.ingestion.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: suiteName)!
        d.removePersistentDomain(forName: suiteName)
        return d
    }()

    private func resetDefaults() {
        defaults.removeObject(forKey: "gmail_last_synced_at")
        defaults.removeObject(forKey: "gmail_access_token_expiry")
        defaults.removeObject(forKey: "gmail_connected_email")
    }

    // MARK: - Helpers

    /// Builds a minimal raw ICICI CC-spend email string that ICICIParser can parse.
    ///
    /// Uses the confirmed corpus pattern from 07-04:
    /// sender: credit_cards@icici.bank.in, subject: "ICICI Bank Credit Card Transaction"
    /// body: "Your ICICI Bank Credit Card XX9001 has been used for a transaction of INR 1,250.00
    ///       on Jun 02, 2026. Info: Zomato."
    private func makeICICIEmail(amount: String = "1,250.00", merchant: String = "Zomato",
                                 cardLast4: String = "9001") -> String {
        return """
        From: credit_cards@icici.bank.in
        To: test@gmail.com
        Subject: ICICI Bank Credit Card Transaction
        Date: Tue, 02 Jun 2026 10:00:00 +0530
        MIME-Version: 1.0
        Content-Type: text/html; charset=UTF-8

        <html><body>
        <p>Your ICICI Bank Credit Card XX\(cardLast4) has been used for a transaction of INR \(amount) on Jun 02, 2026. Info: \(merchant).</p>
        </body></html>
        """
    }

    /// Builds a raw HDFC UPI-debit email string that HDFCParser can parse.
    ///
    /// Uses the confirmed corpus pattern: sender: alerts@hdfcbank.bank.in
    /// body pattern: "Rs.<amount> is debited from your HDFC Bank Debit Card ending <NNNN> at <MERCHANT> on 02 Jun, 2026"
    private func makeHDFCDebitCardEmail(amount: String = "500.00", merchant: String = "Amazon") -> String {
        return """
        From: alerts@hdfcbank.bank.in
        To: test@gmail.com
        Subject: HDFC Bank Debit Card Transaction
        Date: Tue, 02 Jun 2026 10:00:00 +0530
        MIME-Version: 1.0
        Content-Type: text/html; charset=UTF-8

        <html><body>
        <p>Rs.\(amount) is debited from your HDFC Bank Debit Card ending 1234 at \(merchant) on 02 Jun, 2026</p>
        </body></html>
        """
    }

    // MARK: - UAT-6-05: connectedEmail populated from getProfile

    @Test("sync: connectedEmail is populated via getProfile after successful sync — UAT-6-05")
    func connectedEmailPopulated() async throws {
        let container = try makeContainer()
        resetDefaults()
        defer { resetDefaults() }

        let spy = SpyGmailAuth()
        let keychain = SpyKeychainStore()
        let fetch = SpyGmailFetch()
        fetch.profileResult = GmailProfile(emailAddress: "user@gmail.com")
        fetch.messageIDsResult = []

        let controller = GmailSyncController(auth: spy, keychain: keychain, fetch: fetch, defaults: defaults)
        controller.accessToken = "access_tok"
        controller.setContext(container.mainContext)

        await controller.sync()

        #expect(controller.connectedEmail == "user@gmail.com",
                "connectedEmail must be populated via fetch.getProfile — UAT-6-05")
        #expect(fetch.getProfileCalls.count >= 1, "getProfile must be called during sync")
    }

    // MARK: - ING-10/11: Ingested expense stores rawEmailBody, parserID, parserVersion

    @Test("pipeline: ingested ICICI expense stores rawEmailBody, parserID, parserVersion — ING-10, ING-11")
    func ingestedExpenseStoresMetadata() async throws {
        let container = try makeContainer()
        resetDefaults()
        defer { resetDefaults() }

        let spy = SpyGmailAuth()
        let keychain = SpyKeychainStore()
        let fetch = SpyGmailFetch()
        fetch.profileResult = GmailProfile(emailAddress: "user@gmail.com")
        fetch.messageIDsResult = ["msg-001"]
        fetch.rawMessagesByID = ["msg-001": makeICICIEmail()]

        let controller = GmailSyncController(auth: spy, keychain: keychain, fetch: fetch, defaults: defaults)
        controller.accessToken = "access_tok"
        controller.setContext(container.mainContext)

        await controller.sync()

        let expenses = try container.mainContext.fetch(FetchDescriptor<Expense>())
        let e = try #require(expenses.first, "At least one expense must be persisted")
        #expect(e.rawEmailBody != nil, "rawEmailBody must be stored — ING-10")
        #expect(e.parserID != nil, "parserID must be stored — ING-11")
        #expect(e.parserVersion != nil, "parserVersion must be stored — ING-11")
        #expect(e.gmailMessageID == "msg-001", "gmailMessageID must be stored — ING-14")
        #expect(e.sourceLabel != nil, "sourceLabel must be stored — D7-15")
    }

    // MARK: - ING-12: High confidence → autoSaved

    @Test("pipeline: high-confidence ICICI parse → ingestionStateRaw = autoSaved — ING-12")
    func highConfidenceAutoSaved() async throws {
        let container = try makeContainer()
        resetDefaults()
        defer { resetDefaults() }

        let fetch = SpyGmailFetch()
        fetch.profileResult = GmailProfile(emailAddress: "user@gmail.com")
        fetch.messageIDsResult = ["msg-hc"]
        fetch.rawMessagesByID = ["msg-hc": makeICICIEmail()]

        let controller = GmailSyncController(auth: SpyGmailAuth(), keychain: SpyKeychainStore(), fetch: fetch, defaults: defaults)
        controller.accessToken = "access_tok"
        controller.setContext(container.mainContext)

        await controller.sync()

        let expenses = try container.mainContext.fetch(FetchDescriptor<Expense>())
        let e = try #require(expenses.first)
        #expect(e.ingestionStateRaw == "autoSaved",
                "High-confidence parse must set ingestionStateRaw=autoSaved — ING-12")
    }

    // MARK: - ING-12: parseConfidence stored on ingested expense

    @Test("pipeline: parseConfidence is stored on ingested expense; ingestionStateRaw is set — ING-12")
    func parseConfidenceStored() async throws {
        let container = try makeContainer()
        resetDefaults()
        defer { resetDefaults() }

        // The current parsers (HDFCParser/ICICIParser) always produce high extractionScore + fingerprintScore
        // (both 1.0 for corpus-matching emails), so ingested expenses land in autoSaved.
        // This test verifies: (1) parseConfidence is persisted, (2) ingestionStateRaw is set.
        // A genuine needsReview path requires a custom low-score parser — deferred to v2 calibration
        // once real-corpus data confirms per-template confidence distributions (D7-03).
        let fetch = SpyGmailFetch()
        fetch.profileResult = GmailProfile(emailAddress: "user@gmail.com")
        fetch.messageIDsResult = ["msg-conf"]
        fetch.rawMessagesByID = ["msg-conf": makeICICIEmail()]

        let controller = GmailSyncController(auth: SpyGmailAuth(), keychain: SpyKeychainStore(), fetch: fetch, defaults: defaults)
        controller.accessToken = "access_tok"
        controller.setContext(container.mainContext)

        await controller.sync()

        let expenses = try container.mainContext.fetch(FetchDescriptor<Expense>())
        let e = try #require(expenses.first)
        #expect(e.parseConfidence != nil,
                "parseConfidence must be stored on every ingested expense — ING-12")
        #expect(e.ingestionStateRaw != nil,
                "ingestionStateRaw must be set on every ingested expense — ING-12")
        // Current parsers always produce high-confidence results → autoSaved
        #expect(e.ingestionStateRaw == "autoSaved",
                "High-confidence ICICI parse must produce autoSaved — ING-12")
        let confidence = try #require(e.parseConfidence)
        #expect(confidence >= 0.85,
                "Stored confidence must be ≥ 0.85 for autoSaved — ING-12")
    }

    // MARK: - ING-14: Duplicate prevention via possibleDuplicate state

    @Test("pipeline: message already in DismissedMessageStore is skipped — D7-07")
    func dismissedMessageSkipped() async throws {
        let container = try makeContainer()
        resetDefaults()
        defer {
            resetDefaults()
            DismissedMessageStore.undismiss("msg-dismissed")
        }

        DismissedMessageStore.dismiss("msg-dismissed")

        let fetch = SpyGmailFetch()
        fetch.profileResult = GmailProfile(emailAddress: "user@gmail.com")
        fetch.messageIDsResult = ["msg-dismissed"]
        fetch.rawMessagesByID = ["msg-dismissed": makeICICIEmail()]

        let controller = GmailSyncController(auth: SpyGmailAuth(), keychain: SpyKeychainStore(), fetch: fetch, defaults: defaults)
        controller.accessToken = "access_tok"
        controller.setContext(container.mainContext)

        await controller.sync()

        let expenses = try container.mainContext.fetch(FetchDescriptor<Expense>())
        #expect(expenses.isEmpty, "Dismissed message must not produce an Expense — D7-07")
    }

    // MARK: - ING-14: Possible-duplicate routes to possibleDuplicate state

    @Test("pipeline: expense matching existing → ingestionStateRaw = possibleDuplicate — ING-14")
    func duplicateEmailPossibleDuplicate() async throws {
        let container = try makeContainer()
        resetDefaults()
        defer { resetDefaults() }

        // Pre-insert an existing expense that matches the incoming email.
        // Pin the date to the email's transaction date (Jun 02, 2026) rather than Date():
        // DedupChecker's match window is ±1 day, and the incoming email date is fixed, so using
        // the wall clock made this test flake once real time drifted >24h past the hardcoded email.
        var dupComps = DateComponents()
        dupComps.year = 2026; dupComps.month = 6; dupComps.day = 2
        let existingDate = Calendar.current.date(from: dupComps) ?? Date()
        let existing = Expense(amount: Decimal(string: "1250") ?? 0, date: existingDate, note: "Zomato")
        container.mainContext.insert(existing)
        try container.mainContext.save()

        let fetch = SpyGmailFetch()
        fetch.profileResult = GmailProfile(emailAddress: "user@gmail.com")
        fetch.messageIDsResult = ["msg-dup"]
        fetch.rawMessagesByID = ["msg-dup": makeICICIEmail(amount: "1,250.00", merchant: "Zomato")]

        let controller = GmailSyncController(auth: SpyGmailAuth(), keychain: SpyKeychainStore(), fetch: fetch, defaults: defaults)
        controller.accessToken = "access_tok"
        controller.setContext(container.mainContext)

        await controller.sync()

        let descriptor = FetchDescriptor<Expense>()
        let allExpenses = try container.mainContext.fetch(descriptor)
        // 2 total: the pre-existing + the new ingested one
        #expect(allExpenses.count == 2, "Both existing + ingested expense should exist")
        let ingested = allExpenses.first { $0.gmailMessageID == "msg-dup" }
        let e = try #require(ingested)
        #expect(e.ingestionStateRaw == "possibleDuplicate",
                "Duplicate match must set ingestionStateRaw=possibleDuplicate — ING-14")
    }
}
