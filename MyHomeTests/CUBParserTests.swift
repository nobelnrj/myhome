import Testing
import Foundation
@testable import MyHome

// Requirements: ING-06, ING-07, ING-08, ING-09
// Threat ref: none (parser tests run against fixture strings only)
// Validation command: xcodebuild test ... -only-testing:MyHomeTests/CUBParserTests
// CUBParser calibrated to the 06-05 confirmed corpus (City Union Bank savings debit alert).

/// CUBParserTests — unit tests for CUBParser.
///
/// ING-06: Parser extracts amount, merchant, date from a well-formed bank email.
/// ING-07: Parser returns nil for emails that fail the pre-filter fingerprint.
/// ING-08: canHandle rejects OTP, promo, verification, statement emails and non-CUB senders.
/// ING-09: Reversal / credit emails produce isReversal=true and a negative amount.
@MainActor
struct CUBParserTests {

    // MARK: - ING-08: canHandle — confirmed CUB sender + transaction subjects

    @Test("canHandle: accepts CUB transaction alert subject — ING-08")
    func canHandleAcceptsTransactionAlert() {
        let sut = CUBParser()
        #expect(sut.canHandle(
            sender: "cubalert@cityunionbank.org",
            subject: "CUB Transaction Alert"))
    }

    @Test("canHandle: rejects statement subject — ING-08")
    func canHandleRejectsStatement() {
        let sut = CUBParser()
        #expect(!sut.canHandle(
            sender: "cubalert@cityunionbank.org",
            subject: "Your City Union Bank Account Statement for May 2026"))
    }

    @Test("canHandle: rejects OTP subject — ING-08")
    func canHandleRejectsOTP() {
        let sut = CUBParser()
        #expect(!sut.canHandle(
            sender: "cubalert@cityunionbank.org",
            subject: "Your OTP is 123456"))
    }

    @Test("canHandle: rejects promotional subject — ING-08")
    func canHandleRejectsPromo() {
        let sut = CUBParser()
        #expect(!sut.canHandle(
            sender: "cubalert@cityunionbank.org",
            subject: "Special offer on CUB DHI Credit Card"))
    }

    @Test("canHandle: rejects non-CUB sender — ING-08")
    func canHandleRejectsNonCUBSender() {
        let sut = CUBParser()
        #expect(!sut.canHandle(
            sender: "alerts@hdfcbank.bank.in",
            subject: "CUB Transaction Alert"))
    }

    // MARK: - ING-07: parse returns nil on fingerprint failure

    @Test("parse: returns nil when required fingerprint literals missing — ING-07")
    func parseReturnsNilOnFingerprintFailure() {
        let sut = CUBParser()
        let result = sut.parse(rawEmail: "Hello, this is not a bank email.")
        #expect(result == nil)
    }

    // MARK: - ING-06: Savings debit fixture (INR 10000.00, 03-JUN-2026)

    @Test("parse: CUB savings debit → INR 10000, NACH merchant, not reversal — ING-06")
    func parsesSavingsDebit() throws {
        let raw = try loadFixture("cub_savings_debit_1.eml")
        let sut = CUBParser()
        let result = try #require(sut.parse(rawEmail: raw))
        #expect(result.amount == Decimal(string: "10000.00"))
        #expect(result.rawMerchant == "TO ONL NACH_DR/CIUB7020202261000973/INDIAN CLEARING C::00520")
        #expect(!result.isReversal)
        #expect(result.rawSourceLabel == "CUB ••45")
    }

    @Test("parse: CUB savings debit date → 03-JUN-2026 (IST) — ING-06")
    func parsesSavingsDebitDate() throws {
        let raw = try loadFixture("cub_savings_debit_1.eml")
        let sut = CUBParser()
        let result = try #require(sut.parse(rawEmail: raw))

        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Kolkata")!
        let comps = cal.dateComponents([.year, .month, .day], from: result.date)
        #expect(comps.year == 2026)
        #expect(comps.month == 6)
        #expect(comps.day == 3)
    }

    // MARK: - ING-06: Real-corpus direct emails (downloaded from inbox 06-05)

    @Test("parse: REAL CUB direct debit #1 → INR 5000, NACH merchant, 03-JUN-2026 — ING-06")
    func parsesRealDirectDebit1() throws {
        let raw = try loadFixture("cub_savings_debit_real_1.eml")
        let sut = CUBParser()
        let result = try #require(sut.parse(rawEmail: raw))
        #expect(result.amount == Decimal(string: "5000.00"))
        #expect(result.rawMerchant == "TO ONL NACH_DR/CIUB7020202261000973/INDIAN CLEARING C::00520")
        #expect(!result.isReversal)
        #expect(result.rawSourceLabel == "CUB ••45")

        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Kolkata")!
        let comps = cal.dateComponents([.year, .month, .day], from: result.date)
        #expect(comps.year == 2026)
        #expect(comps.month == 6)
        #expect(comps.day == 3)
    }

    @Test("parse: REAL CUB direct debit #2 → INR 10000, NACH merchant, 03-JUN-2026 — ING-06")
    func parsesRealDirectDebit2() throws {
        let raw = try loadFixture("cub_savings_debit_real_2.eml")
        let sut = CUBParser()
        let result = try #require(sut.parse(rawEmail: raw))
        #expect(result.amount == Decimal(string: "10000.00"))
        #expect(result.rawMerchant == "TO ONL NACH_DR/CIUB7020202261000973/INDIAN CLEARING C::00520")
        #expect(!result.isReversal)
        #expect(result.rawSourceLabel == "CUB ••45")
    }

    @Test("canHandle: REAL CUB direct sender + subject accepted — ING-08")
    func canHandleRealDirect() {
        let sut = CUBParser()
        #expect(sut.canHandle(
            sender: "cubalert@cityunionbank.org",
            subject: "CUB Transaction Alert"))
    }

    // MARK: - Scores

    @Test("parse: fingerprintScore and extractionScore are in [0,1] — ING-07")
    func scoresInRange() throws {
        let raw = try loadFixture("cub_savings_debit_1.eml")
        let sut = CUBParser()
        let result = try #require(sut.parse(rawEmail: raw))
        #expect(result.fingerprintScore >= 0.0 && result.fingerprintScore <= 1.0)
        #expect(result.extractionScore >= 0.0 && result.extractionScore <= 1.0)
    }

    // MARK: - MerchantNormalizer integration

    @Test("parse: normalizedMerchant is populated — ING-15")
    func normalizedMerchantPopulated() throws {
        let raw = try loadFixture("cub_savings_debit_1.eml")
        let sut = CUBParser()
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
