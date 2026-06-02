import Foundation

// MARK: - ParsedExpense

/// Value type representing the result of parsing a bank email alert.
///
/// All fields are value types; no @Model references so this type is safe to pass
/// across concurrency boundaries (Sendable). Amount is Decimal — never Double (Pitfall 17).
public struct ParsedExpense: Sendable {
    /// Transaction amount in INR. Negative for reversals/refunds.
    /// Always Decimal — never Double (Pitfall 17; money must not lose precision).
    public let amount: Decimal

    /// Raw merchant string as extracted from the email (before normalization).
    public let rawMerchant: String

    /// Normalized merchant name after lookup in MerchantNormalizer (ING-15, D7-09).
    public let normalizedMerchant: String

    /// Suggested category for the normalized merchant (nil if unknown — ING-15, D7-12).
    public let categoryHint: String?

    /// Transaction date/time extracted from the email (UTC).
    public let date: Date

    /// Human-readable source label, e.g. "HDFC CC ••4321" (D7-15).
    public let rawSourceLabel: String

    /// True if this email describes a reversal, refund, or credit (ING-09).
    /// When true, amount will be negative.
    public let isReversal: Bool

    /// Pre-filter fingerprint score: fraction of required literal strings found in the email (0.0–1.0).
    /// Used as input to ConfidenceScorer. Not money — Double is correct here.
    public let fingerprintScore: Double

    /// Field extraction quality score: fraction of expected fields successfully parsed (0.0–1.0).
    /// Used as input to ConfidenceScorer. Not money — Double is correct here.
    public let extractionScore: Double

    public init(
        amount: Decimal,
        rawMerchant: String,
        normalizedMerchant: String,
        categoryHint: String?,
        date: Date,
        rawSourceLabel: String,
        isReversal: Bool,
        fingerprintScore: Double,
        extractionScore: Double
    ) {
        self.amount = amount
        self.rawMerchant = rawMerchant
        self.normalizedMerchant = normalizedMerchant
        self.categoryHint = categoryHint
        self.date = date
        self.rawSourceLabel = rawSourceLabel
        self.isReversal = isReversal
        self.fingerprintScore = fingerprintScore
        self.extractionScore = extractionScore
    }
}

// MARK: - BankEmailParser

/// Protocol for per-bank email alert parsers.
///
/// Each bank has its own concrete conformer (HDFCParser, ICICIParser, …).
/// Conformers are pure value types (struct, no I/O) — callers supply the raw email string.
///
/// ING-06/07/08: parsers must handle spend, reversal, and fingerprint-failure paths.
/// ING-08: canHandle rejects OTP/promo/verification/statement subjects and non-bank senders.
public protocol BankEmailParser: Sendable {
    /// A stable, unique identifier for this parser (e.g. "hdfc-v1").
    var parserID: String { get }

    /// Semantic version of the parsing rules (e.g. "1.0").
    var parserVersion: String { get }

    /// Returns true when this parser is capable of handling an email with the given
    /// sender address and subject. MUST return false for OTP, promo, verification,
    /// and statement emails, and for senders not belonging to this bank (ING-08).
    func canHandle(sender: String, subject: String) -> Bool

    /// Attempts to parse a raw RFC 2822 email string into a ParsedExpense.
    ///
    /// Returns nil when the email does not match the expected fingerprint (ING-07).
    /// Returns a ParsedExpense with isReversal=true and negative amount for refunds (ING-09).
    func parse(rawEmail: String) -> ParsedExpense?
}
