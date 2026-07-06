import Foundation

// MARK: - ICICIParser
// ING-06, ING-07, ING-08, ING-09
// Threat: T-07-08 (body treated as plain String — no eval, no HTML rendering)
// Threat: T-07-09 (canHandle pre-filter rejects non-bank senders)

/// Two-stage ICICI bank email parser.
///
/// Stage 1 (ING-08): sender host + blocked-subject pre-filter via `canHandle`.
/// Stage 2 (ING-07): fingerprint → extraction → normalization → reversal detection.
///
/// All ICICI transaction emails in the confirmed corpus are HTML-only
/// (multipart/mixed with a single text/html part, 7bit/us-ascii encoded).
///
/// **Confirmed corpus (07-04):**
/// - ICICI CC spend: "Your ICICI Bank Credit Card XX<NNNN> has been used for a transaction of INR <amount> on <Mon dd, yyyy>. Info: <MERCHANT>."
/// - ICICI statement: subject contains "Statement" → canHandle = false
///
/// ICICI parser covers CC-spend + statement-reject only (no UPI/debit — see plan 07-04 known gaps).
public struct ICICIParser: BankEmailParser {

    public let parserID = "icici-v1"
    public let parserVersion = "1.0"

    public init() {}

    // MARK: - Allowed senders (confirmed, ING-08)

    /// Confirmed ICICI sender host from plan 07-04 corpus.
    private static let allowedSenderHost = "icici.bank.in"

    // MARK: - Blocked subject keywords (ING-08)

    private static let blockedSubjectKeywords: [String] = [
        "otp",
        "one time password",
        "verification code",
        "verify",
        "promotional",
        "offer",
        "statement",
    ]

    // MARK: - canHandle

    public func canHandle(sender: String, subject: String) -> Bool {
        // Sender host must match (T-07-09: rejects non-ICICI senders)
        let senderLower = sender.lowercased()
        guard senderLower.hasSuffix("@\(ICICIParser.allowedSenderHost)") ||
              senderLower.hasSuffix(".\(ICICIParser.allowedSenderHost)") else {
            return false
        }
        // Block OTP/promo/statement subjects (ING-08)
        let subjectLower = subject.lowercased()
        for keyword in ICICIParser.blockedSubjectKeywords {
            if subjectLower.contains(keyword) {
                return false
            }
        }
        return true
    }

    // MARK: - parse

    public func parse(rawEmail: String) -> ParsedExpense? {
        // Extract visible text (HTML strip — ICICI emails are 7bit, no QP decoding needed)
        let body = extractVisibleText(from: rawEmail)

        // Extract message Date header for fallback
        let fallbackDate = extractDate(from: rawEmail) ?? Date()

        // Try each known template in order (07-07: expanded beyond CC-spend).
        if let expense = parseCCSpend(body: body, fallbackDate: fallbackDate) {
            return expense
        }
        if let expense = parseCCReversal(body: body, fallbackDate: fallbackDate) {
            return expense
        }
        if let expense = parseNEFTDebit(body: body, fallbackDate: fallbackDate) {
            return expense
        }
        if let expense = parseAccountCredit(body: body, fallbackDate: fallbackDate) {
            return expense
        }
        return nil
    }

    // MARK: - Template parsers

    /// ICICI CC spend: "Your ICICI Bank Credit Card XX<NNNN> has been used for a transaction of <CUR> <amount> on <Mon dd, yyyy> at <hh:mm:ss>. Info: <MERCHANT>."
    ///
    /// 07-07: currency generalised from hardcoded INR to any ISO code so foreign-currency
    /// spends (e.g. "USD 23.60" for Anthropic/Vercel) are captured. No FX conversion is done —
    /// the original amount + `currencyCode` are preserved (see ParsedExpense.currencyCode).
    private func parseCCSpend(body: String, fallbackDate: Date) -> ParsedExpense? {
        // FINGERPRINT — required literals (ING-07): if any missing, return nil
        guard body.contains("Your ICICI Bank Credit Card XX"),
              body.contains("has been used for a transaction of"),
              body.contains("Info:") else {
            return nil
        }

        // EXTRACT currency + amount — "transaction of <CUR> <amount> on"
        // Anchored to "transaction of" so the later "Available Credit Limit ... INR" is not matched.
        guard let (currency, amount) = extractCurrencyAmount(
            pattern: #"transaction of\s+([A-Z]{3})\s+([\d,]+(?:\.\d{1,2})?)\s+on"#, from: body) else {
            return nil
        }

        // EXTRACT card tail — "Credit Card XX<NNNN>"
        let cardTail = extractCapture(pattern: #"Credit Card XX(\d{4})"#, from: body) ?? ""
        let sourceLabel = cardTail.isEmpty ? "ICICI CC" : "ICICI CC ••\(cardTail)"

        // EXTRACT merchant — text after "Info:" up to the next period or end of sentence
        guard let merchant = extractICICIMerchant(from: body) else { return nil }

        // EXTRACT date — "on <Mon dd, yyyy>"
        let date = extractMonDDYYYY(from: body) ?? fallbackDate

        // NORMALISE
        let normalized = MerchantNormalizer.normalize(merchant)

        return ParsedExpense(
            amount: amount,
            currencyCode: currency,
            rawMerchant: merchant,
            normalizedMerchant: normalized.normalizedName,
            categoryHint: normalized.categoryHint,
            date: date,
            rawSourceLabel: sourceLabel,
            isReversal: false,
            fingerprintScore: 1.0,
            extractionScore: 1.0
        )
    }

    /// ICICI CC reversal/refund (07-07): "the reversal of INR <amount> has been done on your
    /// ICICI Bank Credit Card XX<NNNN> on <Month dd, yyyy>." Mirrors HDFC refund handling:
    /// isReversal=true, negative amount. No merchant is present in the email.
    private func parseCCReversal(body: String, fallbackDate: Date) -> ParsedExpense? {
        // FINGERPRINT
        guard body.contains("the reversal of INR"),
              body.contains("has been done on your ICICI Bank Credit Card") else {
            return nil
        }

        // EXTRACT amount — "the reversal of INR <amount>"
        guard let amount = extractAmount(pattern: #"the reversal of INR\s+([\d,]+(?:\.\d{1,2})?)"#, from: body) else {
            return nil
        }

        // EXTRACT card tail — "Credit Card XX<NNNN>" (whitespace already collapsed by strip)
        let cardTail = extractCapture(pattern: #"Credit Card\s+XX(\d{4})"#, from: body) ?? ""
        let sourceLabel = cardTail.isEmpty ? "ICICI CC" : "ICICI CC ••\(cardTail)"

        // EXTRACT date — "on <Month dd, yyyy>" (full or abbreviated month)
        let date = extractLongOrShortMonthDate(from: body) ?? fallbackDate

        return ParsedExpense(
            amount: -abs(amount),           // reversal → negative (ING-09)
            rawMerchant: "Reversal",
            normalizedMerchant: "ICICI Reversal",
            categoryHint: nil,
            date: date,
            rawSourceLabel: sourceLabel,
            isReversal: true,
            fingerprintScore: 1.0,
            extractionScore: 1.0
        )
    }

    /// ICICI savings-account NEFT outflow (07-07): "You have made an online NEFT payment of
    /// Rs. <amount> towards <payee> on <Mon dd, yyyy> at <time> from your ICICI Bank Savings
    /// Account XXXX<NNNN>." A genuine debit — downstream transfer detection flags self-transfers.
    private func parseNEFTDebit(body: String, fallbackDate: Date) -> ParsedExpense? {
        // FINGERPRINT
        guard body.contains("You have made an online NEFT payment of"),
              body.contains("from your ICICI Bank Savings Account") else {
            return nil
        }

        // EXTRACT amount — "NEFT payment of Rs. <amount> towards"
        guard let amount = extractAmount(pattern: #"NEFT payment of Rs\.?\s*([\d,]+(?:\.\d{1,2})?)\s+towards"#, from: body) else {
            return nil
        }

        // EXTRACT payee — "towards <payee> on <Mon dd, yyyy>"
        let payee = extractCapture(pattern: #"towards\s+(.+?)\s+on\s+[A-Za-z]{3,9}\s+\d{1,2},"#, from: body) ?? "NEFT Transfer"

        // EXTRACT account tail — "Savings Account XXXX<NNNN>"
        let accountTail = extractCapture(pattern: #"Savings Account\s+X+(\d{4})"#, from: body) ?? ""
        let sourceLabel = accountTail.isEmpty ? "ICICI Savings" : "ICICI Savings ••\(accountTail)"

        // EXTRACT date — "on <Mon dd, yyyy>"
        let date = extractLongOrShortMonthDate(from: body) ?? fallbackDate

        // NORMALISE (payee is usually a person → typically Uncategorized)
        let normalized = MerchantNormalizer.normalize(payee)

        return ParsedExpense(
            amount: amount,
            rawMerchant: payee,
            normalizedMerchant: normalized.normalizedName,
            categoryHint: normalized.categoryHint,
            date: date,
            rawSourceLabel: sourceLabel,
            isReversal: false,
            fingerprintScore: 1.0,
            extractionScore: 1.0
        )
    }

    /// ICICI savings-account incoming credit (07-07): "Your ICICI Bank Account XX<NNNN> has been
    /// credited with INR <amount> on <dd-Mon-yy>. Info: <detail>." Captured as a credit
    /// (isReversal=true, negative amount) so incoming money is recorded, mirroring refund handling.
    private func parseAccountCredit(body: String, fallbackDate: Date) -> ParsedExpense? {
        // FINGERPRINT
        guard body.contains("Your ICICI Bank Account XX"),
              body.contains("has been credited with INR") else {
            return nil
        }

        // EXTRACT amount — "credited with INR <amount>"
        guard let amount = extractAmount(pattern: #"has been credited with INR\s+([\d,]+(?:\.\d{1,2})?)"#, from: body) else {
            return nil
        }

        // EXTRACT account tail — "Account XX<NNNN>"
        let accountTail = extractCapture(pattern: #"ICICI Bank Account XX(\d{3,4})"#, from: body) ?? ""
        let sourceLabel = accountTail.isEmpty ? "ICICI Savings" : "ICICI Savings ••\(accountTail)"

        // Label interest credits distinctly; otherwise generic account credit.
        let merchant = body.contains("Int.Pd") ? "Interest Credit" : "Account Credit"

        // EXTRACT date — "on <dd-Mon-yy>"
        let date = extractDDMonYY(from: body) ?? fallbackDate

        return ParsedExpense(
            amount: -abs(amount),           // credit → negative (money in), like a reversal (ING-09)
            rawMerchant: merchant,
            normalizedMerchant: merchant,
            categoryHint: nil,
            date: date,
            rawSourceLabel: sourceLabel,
            isReversal: true,
            fingerprintScore: 1.0,
            extractionScore: 1.0
        )
    }

    // MARK: - Extraction helpers

    /// Strips HTML tags to get visible text.
    ///
    /// ICICI emails are 7bit-encoded — no quoted-printable decoding needed.
    private func extractVisibleText(from rawEmail: String) -> String {
        let lower = rawEmail.lowercased()
        var htmlContent = rawEmail

        if let htmlStart = lower.range(of: "<html") {
            htmlContent = String(rawEmail[htmlStart.lowerBound...])
        }

        return stripHTMLTags(htmlContent)
    }

    /// Strips HTML tags and normalises whitespace to produce visible text.
    private func stripHTMLTags(_ html: String) -> String {
        var text = html
        // Replace <br> with space for word boundary preservation
        text = text.replacingOccurrences(of: "<br", with: " ", options: .caseInsensitive)
        var result = ""
        result.reserveCapacity(text.count)
        var inTag = false
        for ch in text {
            if ch == "<" {
                inTag = true
            } else if ch == ">" {
                inTag = false
                result.append(" ")
            } else if !inTag {
                result.append(ch)
            }
        }
        let components = result.components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
        return components.joined(separator: " ")
    }

    /// Extracts the `Date:` header value and parses it as a Date.
    private func extractDate(from rawEmail: String) -> Date? {
        guard let range = rawEmail.range(of: "Date: ", options: .caseInsensitive) else {
            return nil
        }
        let after = String(rawEmail[range.upperBound...])
        let line = after.components(separatedBy: "\n").first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        let formats = [
            "EEE, dd MMM yyyy HH:mm:ss Z",
            "EEE, d MMM yyyy HH:mm:ss Z",
            "dd MMM yyyy HH:mm:ss Z",
            "EEE, dd MMM yyyy HH:mm:ss z",
        ]
        for fmt in formats {
            formatter.dateFormat = fmt
            if let date = formatter.date(from: line) { return date }
        }
        return nil
    }

    /// Extracts Decimal amount using an NSRegularExpression pattern.
    /// Group 1 must capture the numeric string (may include Indian grouping commas).
    /// Never uses Double — Pitfall 17.
    private func extractAmount(pattern: String, from body: String) -> Decimal? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return nil
        }
        let nsBody = body as NSString
        let range = NSRange(location: 0, length: nsBody.length)
        guard let match = regex.firstMatch(in: body, options: [], range: range),
              match.numberOfRanges > 1 else {
            return nil
        }
        let amtRange = match.range(at: 1)
        guard amtRange.location != NSNotFound else { return nil }
        let amtStr = nsBody.substring(with: amtRange)
            .replacingOccurrences(of: ",", with: "")
        return Decimal(string: amtStr)
    }

    /// Extracts an ISO currency code (group 1) and Decimal amount (group 2) in one match.
    /// Never uses Double — Pitfall 17.
    private func extractCurrencyAmount(pattern: String, from body: String) -> (String, Decimal)? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return nil
        }
        let nsBody = body as NSString
        let range = NSRange(location: 0, length: nsBody.length)
        guard let match = regex.firstMatch(in: body, options: [], range: range),
              match.numberOfRanges > 2,
              match.range(at: 1).location != NSNotFound,
              match.range(at: 2).location != NSNotFound else {
            return nil
        }
        let currency = nsBody.substring(with: match.range(at: 1)).uppercased()
        let amtStr = nsBody.substring(with: match.range(at: 2))
            .replacingOccurrences(of: ",", with: "")
        guard let amount = Decimal(string: amtStr) else { return nil }
        return (currency, amount)
    }

    /// Generic single-capture-group extraction helper.
    private func extractCapture(pattern: String, from body: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return nil
        }
        let nsBody = body as NSString
        let range = NSRange(location: 0, length: nsBody.length)
        guard let match = regex.firstMatch(in: body, options: [], range: range),
              match.numberOfRanges > 1 else {
            return nil
        }
        let captureRange = match.range(at: 1)
        guard captureRange.location != NSNotFound else { return nil }
        return nsBody.substring(with: captureRange).trimmingCharacters(in: .whitespaces)
    }

    /// Extracts ICICI merchant: text after "Info:" up to the next period (or end of visible text segment).
    ///
    /// Corpus: "Info: AMAZON PAY IN E COMMERCE." and "Info: BOOKMYSHOW COM."
    private func extractICICIMerchant(from body: String) -> String? {
        // Pattern: "Info: <MERCHANT>." (period terminates the merchant)
        let pattern = #"Info:\s+([^.]+?)\s*\."#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return nil
        }
        let nsBody = body as NSString
        let range = NSRange(location: 0, length: nsBody.length)
        guard let match = regex.firstMatch(in: body, options: [], range: range),
              match.numberOfRanges > 1 else {
            return nil
        }
        let mRange = match.range(at: 1)
        guard mRange.location != NSNotFound else { return nil }
        return nsBody.substring(with: mRange).trimmingCharacters(in: .whitespaces)
    }

    /// Parses ICICI CC spend date format: "Mon dd, yyyy" (e.g. "Jun 02, 2026").
    private func extractMonDDYYYY(from body: String) -> Date? {
        let pattern = #"\b(\w{3}\s+\d{1,2},\s*\d{4})\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return nil }
        let nsBody = body as NSString
        let range = NSRange(location: 0, length: nsBody.length)
        guard let match = regex.firstMatch(in: body, options: [], range: range) else { return nil }
        let dateStr = nsBody.substring(with: match.range(at: 1))
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "Asia/Kolkata")
        formatter.dateFormat = "MMM dd, yyyy"
        if let d = formatter.date(from: dateStr) { return d }
        formatter.dateFormat = "MMM d, yyyy"
        return formatter.date(from: dateStr)
    }

    /// Parses an ICICI date that may use a full ("June 20, 2026") or abbreviated ("Jul 01, 2026")
    /// month name — used by the reversal and NEFT templates (07-07). Whitespace is already
    /// collapsed by `stripHTMLTags`, so "June      20" arrives as "June 20".
    private func extractLongOrShortMonthDate(from body: String) -> Date? {
        let pattern = #"\b([A-Za-z]{3,9}\s+\d{1,2},\s*\d{4})\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return nil }
        let nsBody = body as NSString
        let range = NSRange(location: 0, length: nsBody.length)
        guard let match = regex.firstMatch(in: body, options: [], range: range) else { return nil }
        let dateStr = nsBody.substring(with: match.range(at: 1))
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "Asia/Kolkata")
        for fmt in ["MMMM d, yyyy", "MMM d, yyyy", "MMMM dd, yyyy", "MMM dd, yyyy"] {
            formatter.dateFormat = fmt
            if let d = formatter.date(from: dateStr) { return d }
        }
        return nil
    }

    /// Parses ICICI account-alert date format: "dd-Mon-yy" (e.g. "30-Jun-26").
    private func extractDDMonYY(from body: String) -> Date? {
        let pattern = #"\b(\d{1,2}-[A-Za-z]{3}-\d{2})\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return nil }
        let nsBody = body as NSString
        let range = NSRange(location: 0, length: nsBody.length)
        guard let match = regex.firstMatch(in: body, options: [], range: range) else { return nil }
        let dateStr = nsBody.substring(with: match.range(at: 1))
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "Asia/Kolkata")
        formatter.dateFormat = "dd-MMM-yy"
        return formatter.date(from: dateStr)
    }
}
