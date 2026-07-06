import Foundation

// MARK: - ParsedExpense

/// Value type representing the result of parsing a bank email alert.
///
/// All fields are value types; no @Model references so this type is safe to pass
/// across concurrency boundaries (Sendable). Amount is Decimal — never Double (Pitfall 17).
public struct ParsedExpense: Sendable {
    /// Transaction amount. Negative for reversals/refunds.
    /// Always Decimal — never Double (Pitfall 17; money must not lose precision).
    /// Denominated in `currencyCode` — usually INR, but foreign-currency card spends
    /// (e.g. ICICI USD transactions) carry the original amount with `currencyCode != "INR"`.
    public let amount: Decimal

    /// ISO-4217 currency code for `amount` (07-07). Defaults to "INR".
    /// No FX conversion is performed — the raw foreign amount is preserved as-is, and the
    /// stored `Expense.currencyCode` records the denomination so totals aren't mistaken for INR.
    public let currencyCode: String

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
        currencyCode: String = "INR",
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
        self.currencyCode = currencyCode
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

// MARK: - CurrencyConverter

/// Converts a foreign-currency transaction amount into INR, the app's base currency (07-07).
///
/// Why this exists: parsers preserve the original currency faithfully (e.g. USD card spends),
/// but every downstream aggregator — budgets, analytics, overview, donuts — sums `Expense.amount`
/// as INR. Without conversion a $23.60 charge would count as ₹23.60. Conversion happens once, at
/// ingestion, so those aggregators need no changes and can't accidentally skip a currency.
///
/// Live rates are fetched dynamically by `CurrencyRateProvider` (free, no-key FX API, cached 24h);
/// this `staticRatesToINR` table is only the **offline fallback** used when the network and cache
/// are both unavailable — deliberately kept to honour the "free data only" constraint. An unknown
/// currency returns `nil` (caller keeps the original amount and flags the currency) rather than
/// silently mis-scaling.
public enum CurrencyConverter {

    /// Offline fallback: approximate units of INR per 1 unit of the keyed currency. INR = identity.
    /// Live values from `CurrencyRateProvider` override these whenever available.
    public static let staticRatesToINR: [String: Decimal] = [
        "INR": 1,
        "USD": 86,
        "EUR": 93,
        "GBP": 109,
        "AED": 23,
        "SGD": 64,
        "JPY": Decimal(string: "0.58")!,
    ]

    /// Returns `amount` converted to INR using the supplied `rates` (currency → INR-per-unit),
    /// or `nil` when no rate is known for `currency`. A nil result signals the caller to keep the
    /// original amount and preserve the currency code.
    public static func toINR(_ amount: Decimal, from currency: String, using rates: [String: Decimal]) -> Decimal? {
        let code = currency.uppercased()
        guard let rate = rates[code] else { return nil }
        return amount * rate
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
