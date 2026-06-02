import Testing
import Foundation
@testable import MyHome

// Requirements: ING-06, ING-07, ING-08, ING-09
// Threat ref: none (parser tests run against fixture strings only)
// Validation command: xcodebuild test ... -only-testing:MyHomeTests/HDFCParserTests
// Plan 07-01 — RED phase: HDFCParser + corpus fixtures are unimplemented (plan 05, corpus-gated).
// Tests FAIL RED via Issue.record until plan 05 provides HDFCParser and the .eml corpus.

/// HDFCParserTests — unit tests for HDFCParser.
///
/// ING-06: Parser extracts amount, merchant, date from a well-formed bank email.
/// ING-07: Parser returns nil for emails that fail the pre-filter fingerprint.
/// ING-08: canHandle rejects OTP, promo, verification, statement emails and non-HDFC senders.
/// ING-09: Reversal / refund emails produce isReversal=true and a negative amount.
@MainActor
struct HDFCParserTests {

    // MARK: - ING-08: canHandle rejects non-bank / OTP / promo senders and subjects

    @Test("canHandle: rejects OTP subject — ING-08")
    func canHandleRejectsOTP() {
        Issue.record("HDFCParser + fixtures unimplemented — plan 05 (corpus-gated)")
        // let sut = HDFCParser()
        // #expect(!sut.canHandle(sender: "alerts@hdfcbank.com", subject: "Your HDFC Bank OTP is 123456"))
    }

    @Test("canHandle: rejects promotional subject — ING-08")
    func canHandleRejectsPromo() {
        Issue.record("HDFCParser + fixtures unimplemented — plan 05 (corpus-gated)")
        // let sut = HDFCParser()
        // #expect(!sut.canHandle(sender: "noreply@hdfcbank.com", subject: "Exclusive offer: 10% cashback"))
    }

    @Test("canHandle: rejects verification subject — ING-08")
    func canHandleRejectsVerification() {
        Issue.record("HDFCParser + fixtures unimplemented — plan 05 (corpus-gated)")
        // let sut = HDFCParser()
        // #expect(!sut.canHandle(sender: "alerts@hdfcbank.com", subject: "Verification code: 654321"))
    }

    @Test("canHandle: rejects statement subject — ING-08")
    func canHandleRejectsStatement() {
        Issue.record("HDFCParser + fixtures unimplemented — plan 05 (corpus-gated)")
        // let sut = HDFCParser()
        // #expect(!sut.canHandle(sender: "alerts@hdfcbank.com", subject: "HDFC Bank Credit Card Statement"))
    }

    @Test("canHandle: rejects non-HDFC sender — ING-08")
    func canHandleRejectsNonHDFCSender() {
        Issue.record("HDFCParser + fixtures unimplemented — plan 05 (corpus-gated)")
        // let sut = HDFCParser()
        // #expect(!sut.canHandle(sender: "alerts@icicibankmail.com", subject: "Transaction alert"))
    }

    // MARK: - ING-07: parse returns nil on fingerprint failure

    @Test("parse: returns nil when required fingerprint literals missing — ING-07")
    func parseReturnsNilOnFingerprintFailure() {
        Issue.record("HDFCParser + fixtures unimplemented — plan 05 (corpus-gated)")
        // let sut = HDFCParser()
        // let result = sut.parse(rawEmail: "Hello, this is not a bank email.")
        // #expect(result == nil)
    }

    // MARK: - ING-06/09: Fixture-driven parsing table

    @Test("parse: credit card spend fixture → expected amount + merchant — ING-06", arguments: [
        ("hdfc_cc_spend_1.eml", Decimal(1250), "Zomato", false),
        ("hdfc_upi_debit_1.eml", Decimal(500), "Swiggy", false),
        ("hdfc_refund_1.eml", Decimal(-450), "HPCL", true),
    ])
    func parsesKnownFixtures(filename: String, expectedAmount: Decimal,
                              expectedMerchant: String, isReversal: Bool) throws {
        Issue.record("HDFCParser + fixtures unimplemented — plan 05 (corpus-gated)")
        // let raw = try loadFixture(filename)
        // let sut = HDFCParser()
        // let result = try #require(sut.parse(rawEmail: raw))
        // #expect(result.amount == expectedAmount)
        // #expect(result.normalizedMerchant == expectedMerchant)
        // #expect(result.isReversal == isReversal)
    }

    // MARK: - Fixture loader helper

    /// Loads a raw .eml fixture from the test bundle's Fixtures directory.
    private func loadFixture(_ filename: String) throws -> String {
        let bundle = Bundle(for: type(of: SpyGmailFetch()))
        guard let url = bundle.url(forResource: (filename as NSString).deletingPathExtension,
                                    withExtension: (filename as NSString).pathExtension,
                                    subdirectory: "Fixtures") else {
            throw FixtureError.notFound(filename)
        }
        return try String(contentsOf: url, encoding: .utf8)
    }

    private enum FixtureError: Error {
        case notFound(String)
    }
}
