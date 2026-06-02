import Testing
import Foundation
@testable import MyHome

// Requirements: ING-06, ING-07, ING-08, ING-09
// Threat ref: none (parser tests run against fixture strings only)
// Validation command: xcodebuild test ... -only-testing:MyHomeTests/ICICIParserTests
// Plan 07-05 RED → GREEN: ICICIParser calibrated to the 07-04 confirmed corpus.

/// ICICIParserTests — unit tests for ICICIParser.
///
/// ING-06: Parser extracts amount, merchant, date from a well-formed bank email.
/// ING-07: Parser returns nil for emails that fail the pre-filter fingerprint.
/// ING-08: canHandle rejects OTP, promo, verification, statement emails and non-ICICI senders.
/// ING-09: Reversal / refund emails produce isReversal=true and a negative amount.
@MainActor
struct ICICIParserTests {

    // MARK: - ING-08: canHandle — confirmed ICICI sender + transaction subjects

    @Test("canHandle: accepts ICICI CC spend subject — ING-08")
    func canHandleAcceptsCCSpend() {
        let sut = ICICIParser()
        #expect(sut.canHandle(
            sender: "credit_cards@icici.bank.in",
            subject: "Transaction alert for your ICICI Bank Credit Card"))
    }

    @Test("canHandle: rejects ICICI statement subject — ING-08")
    func canHandleRejectsStatement() {
        let sut = ICICIParser()
        #expect(!sut.canHandle(
            sender: "credit_cards@icici.bank.in",
            subject: "Amazon Pay ICICI Bank Credit Card Statement for the period March 2026"))
    }

    @Test("canHandle: rejects OTP subject — ING-08")
    func canHandleRejectsOTP() {
        let sut = ICICIParser()
        #expect(!sut.canHandle(
            sender: "credit_cards@icici.bank.in",
            subject: "Your OTP is 123456"))
    }

    @Test("canHandle: rejects promotional subject — ING-08")
    func canHandleRejectsPromo() {
        let sut = ICICIParser()
        #expect(!sut.canHandle(
            sender: "credit_cards@icici.bank.in",
            subject: "Special offer: free credit card upgrade"))
    }

    @Test("canHandle: rejects verification code subject — ING-08")
    func canHandleRejectsVerification() {
        let sut = ICICIParser()
        #expect(!sut.canHandle(
            sender: "credit_cards@icici.bank.in",
            subject: "Verification code for your ICICI account"))
    }

    @Test("canHandle: rejects non-ICICI sender — ING-08")
    func canHandleRejectsNonICICISender() {
        let sut = ICICIParser()
        #expect(!sut.canHandle(
            sender: "alerts@hdfcbank.bank.in",
            subject: "Transaction alert for your ICICI Bank Credit Card"))
    }

    @Test("canHandle: rejects Amazon Pay sender — ING-08")
    func canHandleRejectsAmazonPaySender() {
        let sut = ICICIParser()
        #expect(!sut.canHandle(
            sender: "no-reply@amazonpay.in",
            subject: "Payment Reminder"))
    }

    // MARK: - ING-07: parse returns nil on fingerprint failure

    @Test("parse: returns nil when required fingerprint literals missing — ING-07")
    func parseReturnsNilOnFingerprintFailure() {
        let sut = ICICIParser()
        let result = sut.parse(rawEmail: "Hello, this is not a bank email.")
        #expect(result == nil)
    }

    // MARK: - ING-06: CC spend fixture 1 (AMAZON PAY, INR 833.00)

    @Test("parse: ICICI CC spend 1 → INR 833, AMAZON PAY IN E COMMERCE, not reversal — ING-06")
    func parsesCCSpend1() throws {
        let raw = try loadFixture("icici_cc_spend_1.eml")
        let sut = ICICIParser()
        let result = try #require(sut.parse(rawEmail: raw))
        #expect(result.amount == Decimal(string: "833.00"))
        #expect(result.rawMerchant == "AMAZON PAY IN E COMMERCE")
        #expect(!result.isReversal)
        #expect(!result.rawSourceLabel.isEmpty)
    }

    // MARK: - ING-06: CC spend fixture 2 (BOOKMYSHOW, INR 1791.28)

    @Test("parse: ICICI CC spend 2 → INR 1791.28, BOOKMYSHOW COM, not reversal — ING-06")
    func parsesCCSpend2() throws {
        let raw = try loadFixture("icici_cc_spend_2.eml")
        let sut = ICICIParser()
        let result = try #require(sut.parse(rawEmail: raw))
        #expect(result.amount == Decimal(string: "1791.28"))
        #expect(result.rawMerchant == "BOOKMYSHOW COM")
        #expect(!result.isReversal)
        #expect(!result.rawSourceLabel.isEmpty)
    }

    // MARK: - ING-08: Statement reject fixture (canHandle=false, parse=nil)

    @Test("parse: ICICI statement reject fixture → nil — ING-07/08")
    func parsesStatementRejectIsNil() throws {
        let raw = try loadFixture("icici_statement_reject_1.eml")
        let sut = ICICIParser()
        // Statement email: canHandle should return false;
        // parse is a secondary check — if called directly it should also return nil
        // (fingerprint "Your ICICI Bank Credit Card XX" not present in a statement)
        let result = sut.parse(rawEmail: raw)
        #expect(result == nil)
    }

    // MARK: - Scores

    @Test("parse: fingerprintScore and extractionScore are in [0,1] — ING-07")
    func scoresInRange() throws {
        let raw = try loadFixture("icici_cc_spend_1.eml")
        let sut = ICICIParser()
        let result = try #require(sut.parse(rawEmail: raw))
        #expect(result.fingerprintScore >= 0.0 && result.fingerprintScore <= 1.0)
        #expect(result.extractionScore >= 0.0 && result.extractionScore <= 1.0)
    }

    // MARK: - MerchantNormalizer integration

    @Test("parse: normalizedMerchant is populated — ING-15")
    func normalizedMerchantPopulated() throws {
        let raw = try loadFixture("icici_cc_spend_1.eml")
        let sut = ICICIParser()
        let result = try #require(sut.parse(rawEmail: raw))
        #expect(!result.normalizedMerchant.isEmpty)
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
