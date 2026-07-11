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

    // MARK: - 07-07: expanded templates (inline raw fixtures)

    /// Builds a minimal raw email the parser can consume (Date header + single text/html part).
    private func rawEmail(sender: String, date: String, body: String) -> String {
        "From: \(sender)\r\nDate: \(date)\r\nSubject: alert\r\n\r\n<html><body>\(body)</body></html>"
    }

    @Test("parse: ICICI CC spend in USD → amount 23.60, currencyCode USD — 07-07")
    func parsesForeignCurrencyCCSpend() throws {
        let raw = rawEmail(
            sender: "credit_cards@icici.bank.in",
            date: "Wed, 10 Jun 2026 01:31:53 +0530",
            body: "Dear Customer, Your ICICI Bank Credit Card XX8006 has been used for a transaction of USD 23.60 on Jun 10, 2026 at 01:31:53. Info: ANTHROPIC* CLAUDE SUB. The Available Credit Limit on your card is INR 1,46,443.82.")
        let result = try #require(ICICIParser().parse(rawEmail: raw))
        #expect(result.amount == Decimal(string: "23.60"))
        #expect(result.currencyCode == "USD")
        #expect(result.rawMerchant == "ANTHROPIC* CLAUDE SUB")
        #expect(!result.isReversal)
    }

    @Test("parse: ICICI CC spend in INR still defaults currencyCode INR — 07-07 regression")
    func inrCCSpendKeepsINRCurrency() throws {
        let raw = rawEmail(
            sender: "credit_cards@icici.bank.in",
            date: "Thu, 02 Jul 2026 07:56:54 +0530",
            body: "Dear Customer, Your ICICI Bank Credit Card XX5005 has been used for a transaction of INR 704.00 on Jul 02, 2026 at 07:56:54. Info: AMAZON PAY IN E COMMERCE. The Available Credit Limit on your card is INR 2,00,000.00.")
        let result = try #require(ICICIParser().parse(rawEmail: raw))
        #expect(result.amount == Decimal(string: "704.00"))
        #expect(result.currencyCode == "INR")
        #expect(!result.isReversal)
    }

    @Test("parse: ICICI CC reversal → negative amount, isReversal true, full month date — 07-07")
    func parsesCCReversal() throws {
        let raw = rawEmail(
            sender: "credit_cards@icici.bank.in",
            date: "Sat, 20 Jun 2026 10:15:51 +0530",
            body: "Greetings from ICICI Bank. We wish to inform you that the reversal of INR 590 has been done on your ICICI Bank Credit Card  XX8006 on June      20, 2026.")
        let result = try #require(ICICIParser().parse(rawEmail: raw))
        #expect(result.amount == Decimal(string: "-590"))
        #expect(result.isReversal)
        #expect(result.rawSourceLabel == "ICICI CC ••8006")
    }

    @Test("parse: ICICI savings NEFT outflow → amount 50000, payee extracted, not reversal — 07-07")
    func parsesNEFTDebit() throws {
        let raw = rawEmail(
            sender: "customernotification@icici.bank.in",
            date: "Tue, 01 Jul 2026 14:33:47 +0530",
            body: "Dear Customer, You have made an online NEFT payment of Rs. 50,000.00 towards Nobel Reo Jacob K S on Jul 01, 2026 at 08:03 p.m. from your ICICI Bank Savings Account XXXX6843. The Transaction ID is IN12618244306080.")
        let result = try #require(ICICIParser().parse(rawEmail: raw))
        #expect(result.amount == Decimal(string: "50000.00"))
        #expect(result.rawMerchant == "Nobel Reo Jacob K S")
        #expect(!result.isReversal)
        #expect(result.rawSourceLabel == "ICICI Savings ••6843")
    }

    @Test("parse: ICICI account interest credit → negative amount, isReversal true — 07-07")
    func parsesAccountCredit() throws {
        let raw = rawEmail(
            sender: "customernotification@icici.bank.in",
            date: "Tue, 30 Jun 2026 13:47:14 +0530",
            body: "Dear Customer, Greetings from ICICI Bank. Your ICICI Bank Account XX843 has been credited with INR 74 on 30-Jun-26. Info: XX843:Int.Pd:30-03-2026 to 29-06-2026.")
        let result = try #require(ICICIParser().parse(rawEmail: raw))
        #expect(result.amount == Decimal(string: "-74"))
        #expect(result.isReversal)
        #expect(result.rawMerchant == "Interest Credit")
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

// MARK: - CurrencyConverter (07-07)

/// Tests the FX conversion math with injected rates (no network — the live fetch in
/// CurrencyRateProvider is exercised only in production / integration).
@MainActor
struct CurrencyConverterTests {

    private let rates: [String: Decimal] = ["INR": 1, "USD": 86, "EUR": 93]

    @Test("toINR: converts USD to INR using supplied rate — 07-07")
    func convertsUSD() {
        #expect(CurrencyConverter.toINR(Decimal(string: "23.60")!, from: "USD", using: rates) == Decimal(string: "2029.60"))
    }

    @Test("toINR: INR passes through at 1:1 — 07-07")
    func inrIdentity() {
        #expect(CurrencyConverter.toINR(Decimal(500), from: "INR", using: rates) == Decimal(500))
    }

    @Test("toINR: case-insensitive currency code — 07-07")
    func caseInsensitive() {
        #expect(CurrencyConverter.toINR(Decimal(10), from: "usd", using: rates) == Decimal(860))
    }

    @Test("toINR: unknown currency → nil (caller keeps original) — 07-07")
    func unknownCurrencyReturnsNil() {
        #expect(CurrencyConverter.toINR(Decimal(10), from: "XYZ", using: rates) == nil)
    }

    @Test("staticRatesToINR: offline fallback contains INR identity and USD — 07-07")
    func staticFallbackSane() {
        #expect(CurrencyConverter.staticRatesToINR["INR"] == 1)
        #expect(CurrencyConverter.staticRatesToINR["USD"] != nil)
    }
}
