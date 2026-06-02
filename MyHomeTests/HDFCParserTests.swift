import Testing
import Foundation
@testable import MyHome

// Requirements: ING-06, ING-07, ING-08, ING-09
// Threat ref: none (parser tests run against fixture strings only)
// Validation command: xcodebuild test ... -only-testing:MyHomeTests/HDFCParserTests
// Plan 07-05 RED → GREEN: HDFCParser calibrated to the 07-04 confirmed corpus.

/// HDFCParserTests — unit tests for HDFCParser.
///
/// ING-06: Parser extracts amount, merchant, date from a well-formed bank email.
/// ING-07: Parser returns nil for emails that fail the pre-filter fingerprint.
/// ING-08: canHandle rejects OTP, promo, verification, statement emails and non-HDFC senders.
/// ING-09: Reversal / refund emails produce isReversal=true and a negative amount.
@MainActor
struct HDFCParserTests {

    // MARK: - ING-08: canHandle — confirmed HDFC sender + transaction subjects

    @Test("canHandle: accepts HDFC UPI debit subject — ING-08")
    func canHandleAcceptsUPIDebit() {
        let sut = HDFCParser()
        // Subject is RFC2047 encoded in the real email; parser receives the decoded subject
        #expect(sut.canHandle(
            sender: "alerts@hdfcbank.bank.in",
            subject: "❗ You have done a UPI txn. Check details!"))
    }

    @Test("canHandle: accepts HDFC debit-card subject — ING-08")
    func canHandleAcceptsDebitCard() {
        let sut = HDFCParser()
        #expect(sut.canHandle(
            sender: "alerts@hdfcbank.bank.in",
            subject: "Rs.537.00 debited via Debit Card **5610"))
    }

    @Test("canHandle: accepts HDFC account-update subject (refund/credit) — ING-08")
    func canHandleAcceptsAccountUpdate() {
        let sut = HDFCParser()
        #expect(sut.canHandle(
            sender: "alerts@hdfcbank.bank.in",
            subject: "View: Account update for your HDFC Bank A/c"))
    }

    @Test("canHandle: rejects OTP subject — ING-08")
    func canHandleRejectsOTP() {
        let sut = HDFCParser()
        #expect(!sut.canHandle(
            sender: "alerts@hdfcbank.bank.in",
            subject: "Your HDFC Bank OTP is 123456"))
    }

    @Test("canHandle: rejects one time password subject — ING-08")
    func canHandleRejectsOneTimePassword() {
        let sut = HDFCParser()
        #expect(!sut.canHandle(
            sender: "alerts@hdfcbank.bank.in",
            subject: "Your one time password for login"))
    }

    @Test("canHandle: rejects promotional subject — ING-08")
    func canHandleRejectsPromo() {
        let sut = HDFCParser()
        #expect(!sut.canHandle(
            sender: "alerts@hdfcbank.bank.in",
            subject: "Exclusive offer: 10% cashback on shopping"))
    }

    @Test("canHandle: rejects verification code subject — ING-08")
    func canHandleRejectsVerification() {
        let sut = HDFCParser()
        #expect(!sut.canHandle(
            sender: "alerts@hdfcbank.bank.in",
            subject: "Verification code: 654321"))
    }

    @Test("canHandle: rejects statement subject — ING-08")
    func canHandleRejectsStatement() {
        let sut = HDFCParser()
        #expect(!sut.canHandle(
            sender: "alerts@hdfcbank.bank.in",
            subject: "HDFC Bank Credit Card Statement for March 2026"))
    }

    @Test("canHandle: rejects non-HDFC sender — ING-08")
    func canHandleRejectsNonHDFCSender() {
        let sut = HDFCParser()
        #expect(!sut.canHandle(
            sender: "credit_cards@icici.bank.in",
            subject: "Transaction alert for your ICICI Bank Credit Card"))
    }

    @Test("canHandle: rejects Amazon Pay sender — ING-08")
    func canHandleRejectsAmazonPaySender() {
        let sut = HDFCParser()
        #expect(!sut.canHandle(
            sender: "no-reply@amazonpay.in",
            subject: "Payment Reminder"))
    }

    // MARK: - ING-07: parse returns nil on fingerprint failure

    @Test("parse: returns nil when required fingerprint literals missing — ING-07")
    func parseReturnsNilOnFingerprintFailure() {
        let sut = HDFCParser()
        let result = sut.parse(rawEmail: "Hello, this is not a bank email.")
        #expect(result == nil)
    }

    // MARK: - ING-06/09: UPI debit fixture

    @Test("parse: HDFC UPI debit fixture → INR 1500, FRESHALICIOUS SUPER BAZAAR, not reversal — ING-06")
    func parsesUPIDebit() throws {
        let raw = try loadFixture("hdfc_upi_debit_1.eml")
        let sut = HDFCParser()
        let result = try #require(sut.parse(rawEmail: raw))
        #expect(result.amount == Decimal(string: "1500.00"))
        #expect(result.rawMerchant == "FRESHALICIOUS SUPER BAZAAR")
        #expect(!result.isReversal)
        #expect(!result.rawSourceLabel.isEmpty)
    }

    // MARK: - ING-06/09: Debit-card fixture

    @Test("parse: HDFC debit-card fixture → INR 537, Delightful Gourmet Pvt, not reversal — ING-06")
    func parsesDebitCard() throws {
        let raw = try loadFixture("hdfc_debit_card_1.eml")
        let sut = HDFCParser()
        let result = try #require(sut.parse(rawEmail: raw))
        #expect(result.amount == Decimal(string: "537.00"))
        #expect(result.rawMerchant == "Delightful Gourmet Pvt")
        #expect(!result.isReversal)
        #expect(!result.rawSourceLabel.isEmpty)
    }

    // MARK: - ING-06/09: Refund fixture

    @Test("parse: HDFC refund fixture → INR -167, Google India Digital Services Pvt Ltd, isReversal=true — ING-09")
    func parsesRefund() throws {
        let raw = try loadFixture("hdfc_refund_1.eml")
        let sut = HDFCParser()
        let result = try #require(sut.parse(rawEmail: raw))
        #expect(result.amount == Decimal(string: "-167.00"))
        #expect(result.rawMerchant == "Google India Digital Services Pvt Ltd")
        #expect(result.isReversal)
        #expect(!result.rawSourceLabel.isEmpty)
    }

    // MARK: - ING-06: UPI credit (P2P) — must return nil (skip, not an expense)

    @Test("parse: HDFC UPI credit (P2P) → nil — must skip, not an expense — ING-06")
    func parsesUPICreditSkip() throws {
        let raw = try loadFixture("hdfc_upi_credit_1.eml")
        let sut = HDFCParser()
        // P2P incoming is NOT an expense — parser should return nil
        let result = sut.parse(rawEmail: raw)
        #expect(result == nil)
    }

    // MARK: - Scores

    @Test("parse: fingerprintScore and extractionScore are in [0,1] — ING-07")
    func scoresInRange() throws {
        let raw = try loadFixture("hdfc_upi_debit_1.eml")
        let sut = HDFCParser()
        let result = try #require(sut.parse(rawEmail: raw))
        #expect(result.fingerprintScore >= 0.0 && result.fingerprintScore <= 1.0)
        #expect(result.extractionScore >= 0.0 && result.extractionScore <= 1.0)
    }

    // MARK: - MerchantNormalizer integration

    @Test("parse: normalizedMerchant is populated (may differ from rawMerchant) — ING-15")
    func normalizedMerchantPopulated() throws {
        let raw = try loadFixture("hdfc_upi_debit_1.eml")
        let sut = HDFCParser()
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
