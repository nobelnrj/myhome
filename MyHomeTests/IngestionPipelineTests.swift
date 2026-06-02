import Testing
import SwiftData
import Foundation
@testable import MyHome

// Requirements: ING-10, ING-11, ING-12, ING-13, ING-14, UAT-6-05
// Threat ref: T-07-02 (rawEmailBody PII stored locally — Face ID gate already in place)
// Validation command: xcodebuild test ... -only-testing:MyHomeTests/IngestionPipelineTests
// Plan 07-01 — RED phase: Ingestion pipeline is unimplemented (plan 06).
// Tests FAIL RED via Issue.record until plan 06 provides the ingestion pipeline.

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
@MainActor
struct IngestionPipelineTests {

    private func makeContainer() throws -> ModelContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: Expense.self, Cat.self, Note.self, NoteBlock.self,
                                  configurations: config)
    }

    private var defaults: UserDefaults {
        UserDefaults(suiteName: "group.com.reojacob.myhome") ?? .standard
    }

    private func resetDefaults() {
        defaults.removeObject(forKey: "gmail_last_synced_at")
        defaults.removeObject(forKey: "gmail_access_token_expiry")
        defaults.removeObject(forKey: "gmail_connected_email")
    }

    // MARK: - ING-10/11: Ingested expense stores rawEmailBody, parserID, parserVersion

    @Test("pipeline: ingested expense stores rawEmailBody, parserID, parserVersion — ING-10, ING-11")
    func ingestedExpenseStoresMetadata() async throws {
        Issue.record("Ingestion pipeline unimplemented — plan 06")
        // let container = try makeContainer()
        // resetDefaults()
        // defer { resetDefaults() }
        //
        // let spy = SpyGmailAuth()
        // let keychain = SpyKeychainStore()
        // let fetch = SpyGmailFetch()
        // fetch.messageIDsResult = ["msg-001"]
        // fetch.rawMessagesByID = ["msg-001": "<simulated HDFC email>"]
        //
        // let controller = GmailSyncController(auth: spy, keychain: keychain, fetch: fetch)
        // // After pipeline implementation (plan 06), call controller.sync() and assert:
        // // let expenses = try container.mainContext.fetch(FetchDescriptor<Expense>())
        // // let e = try #require(expenses.first)
        // // Note: SchemaV4.Expense has rawEmailBody/parserID/parserVersion — flip typealias in plan 02
        // // #expect(e.rawEmailBody != nil, "rawEmailBody must be stored — ING-10")
        // // #expect(e.parserID != nil, "parserID must be stored — ING-11")
        // // #expect(e.parserVersion != nil, "parserVersion must be stored — ING-11")
    }

    // MARK: - ING-12: High confidence → autoSaved

    @Test("pipeline: confidence ≥ 0.85 → ingestionStateRaw = autoSaved — ING-12")
    func highConfidenceAutoSaved() async throws {
        Issue.record("Ingestion pipeline unimplemented — plan 06")
        // When pipeline exists:
        // #expect(expense.ingestionStateRaw == "autoSaved")
    }

    // MARK: - ING-12: Low confidence → needsReview

    @Test("pipeline: confidence < 0.85 → ingestionStateRaw = needsReview — ING-12")
    func lowConfidenceNeedsReview() async throws {
        Issue.record("Ingestion pipeline unimplemented — plan 06")
        // When pipeline exists:
        // #expect(expense.ingestionStateRaw == "needsReview")
    }

    // MARK: - ING-14: Duplicate prevention

    @Test("pipeline: duplicate email does not insert a second expense — ING-14")
    func duplicateEmailNotInserted() async throws {
        Issue.record("Ingestion pipeline unimplemented — plan 06")
        // When DedupChecker is wired in (plan 03/06):
        // Run sync twice with the same message ID
        // #expect(expenses.count == 1, "Duplicate should not be inserted — ING-14")
    }

    // MARK: - UAT-6-05: connectedEmail populated from getProfile

    @Test("sync: connectedEmail is populated via getProfile after successful sync — UAT-6-05")
    func connectedEmailPopulated() async {
        Issue.record("Ingestion pipeline unimplemented — plan 06")
        // resetDefaults()
        // defer { resetDefaults() }
        //
        // let spy = SpyGmailAuth()
        // let keychain = SpyKeychainStore()
        // let fetch = SpyGmailFetch()
        // fetch.profileResult = GmailProfile(emailAddress: "user@gmail.com")
        //
        // let controller = GmailSyncController(auth: spy, keychain: keychain, fetch: fetch)
        // await controller.sync()
        //
        // #expect(controller.connectedEmail == "user@gmail.com",
        //         "connectedEmail must be populated via fetch.getProfile — UAT-6-05")
        // #expect(fetch.getProfileCalls.count >= 1, "getProfile must be called during sync")
    }
}
