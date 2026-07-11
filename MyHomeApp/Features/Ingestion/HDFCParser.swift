import Foundation

// MARK: - HDFCParser
// ING-06, ING-07, ING-08, ING-09
// Threat: T-07-08 (body treated as plain String — no eval, no HTML rendering)
// Threat: T-07-09 (canHandle pre-filter rejects non-bank senders)

/// Two-stage HDFC bank email parser.
///
/// Stage 1 (ING-08): sender host + blocked-subject pre-filter via `canHandle`.
/// Stage 2 (ING-07): fingerprint → extraction → normalization → reversal detection.
///
/// All HDFC transaction emails in the confirmed corpus are HTML-only
/// (multipart/alternative with a single text/html part, quoted-printable encoded).
/// The parser extracts visible text by decoding quoted-printable and stripping HTML tags.
///
/// **Confirmed corpus (07-04):**
/// - HDFC UPI debit:    "Rs.<amt> is debited … towards VPA <vpa> (<MERCHANT>) on <dd-mm-yy>"
/// - HDFC debit-card:  "Rs.<amt> is debited from your HDFC Bank Debit Card ending <NNNN> at <MERCHANT> on <dd Mon, yyyy>"
/// - HDFC refund:      "Rs. <amt> is successfully credited to your account **<NNNN> by VPA <vpa> <MERCHANT> on <dd-mm-yy>"
/// - HDFC P2P credit:  "Rs.<amt> has been successfully credited to your HDFC Bank account
///                      ending in <NNNN> … Sender:" → CREDIT (money in), sender as merchant
public struct HDFCParser: BankEmailParser {

    public let parserID = "hdfc-v1"
    // 1.1 (07-08): P2P credit recorded with sender as merchant (was skip). Bumping the
    // version triggers the sync layer's wide rescan so pre-upgrade mails are re-fetched.
    public let parserVersion = "1.1"

    public init() {}

    // MARK: - Allowed senders (confirmed, ING-08)

    /// Confirmed HDFC sender host (domain portion after @) from plan 07-04 corpus.
    private static let allowedSenderHost = "hdfcbank.bank.in"

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
        // Sender host must match (T-07-09: rejects non-HDFC senders)
        let senderLower = sender.lowercased()
        guard senderLower.hasSuffix("@\(HDFCParser.allowedSenderHost)") ||
              senderLower.hasSuffix(".\(HDFCParser.allowedSenderHost)") else {
            return false
        }
        // Block OTP/promo/statement subjects (ING-08)
        let subjectLower = subject.lowercased()
        for keyword in HDFCParser.blockedSubjectKeywords {
            if subjectLower.contains(keyword) {
                return false
            }
        }
        return true
    }

    // MARK: - parse

    public func parse(rawEmail: String) -> ParsedExpense? {
        // Extract visible text (quoted-printable decode + HTML strip)
        let body = extractVisibleText(from: rawEmail)

        // Extract message Date header for fallback
        let fallbackDate = extractDate(from: rawEmail) ?? Date()

        // Try each known template in order
        if let expense = parseUPIDebit(body: body, fallbackDate: fallbackDate) {
            return expense
        }
        if let expense = parseUPIInstaAlert(body: body, fallbackDate: fallbackDate) {
            return expense
        }
        if let expense = parseDebitCard(body: body, fallbackDate: fallbackDate) {
            return expense
        }
        if let expense = parseRefund(body: body, fallbackDate: fallbackDate) {
            return expense
        }
        if let expense = parseAccountCredit(body: body, fallbackDate: fallbackDate) {
            return expense
        }
        if let expense = parseNewDepositCredit(body: body, fallbackDate: fallbackDate) {
            return expense
        }
        // P2P credit and unrecognised templates → nil (ING-07)
        return nil
    }

    // MARK: - Template parsers

    /// HDFC UPI debit: "Rs.<amt> is debited from your account ending <NNNN> towards VPA <vpa> (<MERCHANT>) on <dd-mm-yy>"
    private func parseUPIDebit(body: String, fallbackDate: Date) -> ParsedExpense? {
        // FINGERPRINT — required literals (ING-07): if any missing, return nil
        guard body.contains("is debited from your account ending"),
              body.contains("towards VPA"),
              body.contains("UPI transaction reference no") else {
            return nil
        }
        // Skip P2P credit (same "account ending" phrasing but has "has been successfully credited")
        if body.contains("has been successfully credited") { return nil }

        // EXTRACT amount — pattern: "Rs.<amount> is debited"
        guard let amount = extractAmount(pattern: #"Rs\.(\d[\d,]*(?:\.\d{1,2})?)\s+is debited"#, from: body) else {
            return nil
        }

        // EXTRACT merchant — text inside last (...) before " on "
        guard let merchant = extractUPIMerchant(from: body) else { return nil }

        // EXTRACT account tail — "account ending <NNNN>"
        let sourceTail = extractAccountTail(pattern: #"account ending\s+(\d{4})"#, from: body) ?? ""
        let sourceLabel = sourceTail.isEmpty ? "HDFC Debit" : "HDFC ••\(sourceTail)"

        // EXTRACT date — "on <dd-mm-yy>"
        let date = extractDDMMYY(from: body) ?? fallbackDate

        // NORMALISE
        let normalized = MerchantNormalizer.normalize(merchant)

        return ParsedExpense(
            amount: amount,
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

    /// HDFC UPI InstaAlert debit (newer "You have done a UPI txn" format, sender HDFC Bank InstaAlerts):
    /// "Rs.<amt> has been debited from account <NNNN> to VPA <vpa> <MERCHANT> on <dd-mm-yy>.
    ///  Your UPI transaction reference number is <ref>."
    ///
    /// Distinct from `parseUPIDebit` ("is debited from your account ending … towards VPA") and from
    /// `parseRefund` (credit, "by VPA"). Added from real-corpus verification (07-06) — this format
    /// was not present in the original 07-04 sample corpus.
    private func parseUPIInstaAlert(body: String, fallbackDate: Date) -> ParsedExpense? {
        // FINGERPRINT — required literals; if any missing, return nil
        guard body.contains("has been debited from account"),
              body.contains("to VPA"),
              body.contains("UPI transaction reference number") else {
            return nil
        }
        // Credits use "credited" not "debited" — exclude defensively
        if body.contains("has been credited to") { return nil }

        // EXTRACT amount — "Rs.<amount> has been debited"
        guard let amount = extractAmount(pattern: #"Rs\.?\s*(\d[\d,]*(?:\.\d{1,2})?)\s+has been debited"#, from: body) else {
            return nil
        }

        // EXTRACT account tail — "from account <NNNN>"
        let accountTail = extractAccountTail(pattern: #"from account\s+(\d{4})"#, from: body) ?? ""
        let sourceLabel = accountTail.isEmpty ? "HDFC Bank A/c" : "HDFC ••\(accountTail)"

        // EXTRACT merchant — text after the VPA token, up to " on <dd-mm-yy>"
        guard let merchant = extractInstaAlertMerchant(from: body) else { return nil }

        // EXTRACT date — "on <dd-mm-yy>"
        let date = extractDDMMYY(from: body) ?? fallbackDate

        // NORMALISE
        let normalized = MerchantNormalizer.normalize(merchant)

        return ParsedExpense(
            amount: amount,
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

    /// HDFC debit-card: "Rs.<amt> is debited from your HDFC Bank Debit Card ending <NNNN> at <MERCHANT> on <dd Mon, yyyy>"
    private func parseDebitCard(body: String, fallbackDate: Date) -> ParsedExpense? {
        // FINGERPRINT
        guard body.contains("is debited from your HDFC Bank Debit Card ending"),
              body.contains(" at "),
              body.contains(" on ") else {
            return nil
        }

        // EXTRACT amount — "Rs.<amount> is debited from your HDFC Bank Debit Card"
        guard let amount = extractAmount(pattern: #"Rs\.(\d[\d,]*(?:\.\d{1,2})?)\s+is debited from your HDFC Bank Debit Card"#, from: body) else {
            return nil
        }

        // EXTRACT card tail — "Debit Card ending <NNNN>"
        let cardTail = extractAccountTail(pattern: #"Debit Card ending\s+(\d{4})"#, from: body) ?? ""
        let sourceLabel = cardTail.isEmpty ? "HDFC Debit Card" : "HDFC ••\(cardTail)"

        // EXTRACT merchant — text between " at " and " on "
        guard let merchant = extractDebitCardMerchant(from: body) else { return nil }

        // EXTRACT date — "on <dd Mon, yyyy>"
        let date = extractDDMonYYYY(from: body) ?? fallbackDate

        // NORMALISE
        let normalized = MerchantNormalizer.normalize(merchant)

        return ParsedExpense(
            amount: amount,
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

    /// HDFC refund/reversal: "Rs. <amt> is successfully credited to your account **<NNNN> by VPA <vpa> <MERCHANT> on <dd-mm-yy>"
    ///
    /// Disambiguates from P2P credit by requiring "by VPA" (refund) instead of "Sender:" (P2P).
    private func parseRefund(body: String, fallbackDate: Date) -> ParsedExpense? {
        // FINGERPRINT — required literals for refund template
        guard body.contains("is successfully credited to your account"),
              body.contains("by VPA"),
              body.contains("UPI transaction reference number") else {
            return nil
        }
        // P2P credit has "Sender:" line — exclude (ING-09 disambiguation)
        if body.contains("Sender:") { return nil }
        // P2P credit uses "has been successfully credited" — also exclude
        if body.contains("has been successfully credited") { return nil }

        // EXTRACT amount — "Rs. <amount> is successfully credited"
        guard let amount = extractAmount(pattern: #"Rs\.?\s*(\d[\d,]*(?:\.\d{1,2})?)\s+is successfully credited"#, from: body) else {
            return nil
        }

        // EXTRACT account tail — "account **<NNNN>"
        let accountTail = extractAccountTail(pattern: #"account \*{1,2}(\d{4})"#, from: body) ?? ""
        let sourceLabel = accountTail.isEmpty ? "HDFC Debit" : "HDFC ••\(accountTail)"

        // EXTRACT merchant — text after VPA identifier, up to " on "
        guard let merchant = extractRefundMerchant(from: body) else { return nil }

        // EXTRACT date — "on <dd-mm-yy>"
        let date = extractDDMMYY(from: body) ?? fallbackDate

        // NORMALISE
        let normalized = MerchantNormalizer.normalize(merchant)

        return ParsedExpense(
            amount: -abs(amount),   // Reversal → negative amount (ING-09)
            rawMerchant: merchant,
            normalizedMerchant: normalized.normalizedName,
            categoryHint: normalized.categoryHint,
            date: date,
            rawSourceLabel: sourceLabel,
            isReversal: true,
            fingerprintScore: 1.0,
            extractionScore: 1.0
        )
    }

    /// HDFC incoming account credit (07-07): "Rs.<amt> has been successfully credited to your
    /// HDFC Bank account ending in <NNNN>. Transaction Details: a. Date: <dd-mm-yy> …"
    /// (subject "View: Account update for your HDFC Bank A/c"). Captured as a credit
    /// (isReversal=true, negative amount) so incoming money — salary, NEFT-in — is recorded.
    ///
    /// Also covers the incoming **UPI P2P** variant of this format, which carries a
    /// "b. Sender: <NAME> (VPA: <vpa>)" line (07-08 real corpus). When present, the sender
    /// name becomes the merchant. This is distinct from the older P2P skip template
    /// ("credited to your account **<NNNN> … Sender:"), whose different phrasing never matches
    /// this fingerprint and stays skipped via the fall-through path.
    ///
    /// Distinct from `parseRefund` (UPI refund, "by VPA").
    private func parseAccountCredit(body: String, fallbackDate: Date) -> ParsedExpense? {
        // FINGERPRINT
        guard body.contains("has been successfully credited to your HDFC Bank account ending in") else {
            return nil
        }

        // EXTRACT amount — "Rs.<amount> has been successfully credited"
        guard let amount = extractAmount(pattern: #"Rs\.?\s*(\d[\d,]*(?:\.\d{1,2})?)\s+has been successfully credited"#, from: body) else {
            return nil
        }

        // EXTRACT account tail — "account ending in <NNNN>"
        let accountTail = extractAccountTail(pattern: #"account ending in\s+(\d{4})"#, from: body) ?? ""
        let sourceLabel = accountTail.isEmpty ? "HDFC Bank A/c" : "HDFC ••\(accountTail)"

        // EXTRACT date — "Date: <dd-mm-yy>"
        let date = extractDDMMYY(from: body) ?? fallbackDate

        // EXTRACT sender — UPI P2P credits carry "Sender: <NAME> (VPA: …)"; use the
        // sender name as the merchant so the credit is attributable. NEFT/salary credits
        // have no Sender line → generic "Account Credit".
        let merchant = extractCreditSender(from: body) ?? "Account Credit"
        let normalized = MerchantNormalizer.normalize(merchant)

        return ParsedExpense(
            amount: -abs(amount),           // credit → negative (money in), like a reversal (ING-09)
            rawMerchant: merchant,
            normalizedMerchant: normalized.normalizedName,
            categoryHint: nil,
            date: date,
            rawSourceLabel: sourceLabel,
            isReversal: true,
            fingerprintScore: 1.0,
            extractionScore: 1.0
        )
    }

    /// Extracts the sender name from an HDFC UPI P2P credit's "Sender: <NAME> (VPA: …)" line.
    /// Captures the name up to the "(VPA:…)" token, the next lettered detail ("c."), the
    /// "UPI Reference" label, or end of string. Returns nil when there is no Sender line.
    private func extractCreditSender(from body: String) -> String? {
        let pattern = #"Sender:\s*(.+?)\s*(?:\(|\bc\.|UPI Reference|$)"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return nil
        }
        let nsBody = body as NSString
        let range = NSRange(location: 0, length: nsBody.length)
        guard let match = regex.firstMatch(in: body, options: [], range: range),
              match.numberOfRanges > 1, match.range(at: 1).location != NSNotFound else {
            return nil
        }
        let name = nsBody.substring(with: match.range(at: 1)).trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? nil : name
    }

    /// HDFC "New Deposit Alert" incoming credit (07-07, second corpus): "You have received a credit
    /// in your HDFC Bank account. Details of the transaction: Amount received: INR <amt> Account:
    /// XX<NNNN> Date: <dd-MON-yyyy> Reference Details: NEFT Cr-…". A distinct format from
    /// `parseAccountCredit` ("has been successfully credited"). Captured as a credit
    /// (isReversal=true, negative amount).
    private func parseNewDepositCredit(body: String, fallbackDate: Date) -> ParsedExpense? {
        // FINGERPRINT
        guard body.contains("You have received a credit in your HDFC Bank account"),
              body.contains("Amount received: INR") else {
            return nil
        }

        // EXTRACT amount — "Amount received: INR <amount>"
        guard let amount = extractAmount(pattern: #"Amount received:\s*INR\s+(\d[\d,]*(?:\.\d{1,2})?)"#, from: body) else {
            return nil
        }

        // EXTRACT account tail — "Account: XX<NNNN>"
        let accountTail = extractAccountTail(pattern: #"Account:\s*XX(\d{4})"#, from: body) ?? ""
        let sourceLabel = accountTail.isEmpty ? "HDFC Bank A/c" : "HDFC ••\(accountTail)"

        // EXTRACT date — "Date: <dd-MON-yyyy>"
        let date = extractDDMonYYYYDash(from: body) ?? fallbackDate

        return ParsedExpense(
            amount: -abs(amount),           // credit → negative (money in), like a reversal (ING-09)
            rawMerchant: "Deposit",
            normalizedMerchant: "Deposit",
            categoryHint: nil,
            date: date,
            rawSourceLabel: sourceLabel,
            isReversal: true,
            fingerprintScore: 1.0,
            extractionScore: 1.0
        )
    }

    // MARK: - Extraction helpers

    /// Parses HDFC dash date with an uppercase abbreviated month: "dd-MON-yyyy" (e.g. "29-JUN-2026").
    private func extractDDMonYYYYDash(from body: String) -> Date? {
        let pattern = #"\b(\d{1,2}-[A-Za-z]{3}-\d{4})\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return nil }
        let nsBody = body as NSString
        let range = NSRange(location: 0, length: nsBody.length)
        guard let match = regex.firstMatch(in: body, options: [], range: range) else { return nil }
        let dateStr = nsBody.substring(with: match.range(at: 1))
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "Asia/Kolkata")
        formatter.dateFormat = "dd-MMM-yyyy"
        return formatter.date(from: dateStr)
    }

    /// Decodes quoted-printable and strips HTML tags to get visible text.
    ///
    /// All HDFC emails in the confirmed corpus are multipart/alternative with a single
    /// text/html part (quoted-printable encoded). There is no text/plain part.
    /// This method handles both quoted-printable (HDFC) and plain 7bit (ICICI) HTML.
    private func extractVisibleText(from rawEmail: String) -> String {
        // Locate the HTML body section — find first "<html" or "<HTML"
        let lower = rawEmail.lowercased()
        var htmlContent = rawEmail

        if let htmlStart = lower.range(of: "<html") {
            htmlContent = String(rawEmail[htmlStart.lowerBound...])
        }

        // Decode quoted-printable soft line breaks and =XX escapes
        let qpDecoded = decodeQuotedPrintable(htmlContent)

        // Strip HTML tags — replace tags with spaces, then collapse whitespace
        let stripped = stripHTMLTags(qpDecoded)

        return stripped
    }

    /// Decodes quoted-printable encoded text.
    /// Handles soft line breaks (=\r\n and =\n) and hex escapes (=XX).
    ///
    /// Works on Unicode scalars (not Character/grapheme clusters) because Swift treats
    /// \r\n as a SINGLE grapheme cluster, which breaks QP soft-line-break detection.
    private func decodeQuotedPrintable(_ input: String) -> String {
        let scalars = Array(input.unicodeScalars)
        var result = ""
        result.reserveCapacity(scalars.count)
        var i = 0

        while i < scalars.count {
            let sc = scalars[i]
            if sc.value == 0x3D {  // '='
                if i + 1 < scalars.count {
                    let next = scalars[i + 1]
                    // Soft line break: =\n
                    if next.value == 0x0A {
                        i += 2
                        continue
                    }
                    // Soft line break: =\r\n (must check CR then LF separately)
                    if next.value == 0x0D {
                        if i + 2 < scalars.count && scalars[i + 2].value == 0x0A {
                            i += 3
                            continue
                        }
                    }
                    // Hex escape: =XX (two hex digits)
                    if i + 2 < scalars.count {
                        let h1 = scalars[i + 1]
                        let h2 = scalars[i + 2]
                        let hexStr = "\(Character(h1))\(Character(h2))"
                        if let byte = UInt8(hexStr, radix: 16) {
                            let scalar = Unicode.Scalar(byte)
                            result.append(Character(scalar))
                            i += 3
                            continue
                        }
                    }
                }
            }
            result.append(Character(sc))
            i += 1
        }
        return result
    }

    /// Strips HTML tags and normalises whitespace to produce visible text.
    private func stripHTMLTags(_ html: String) -> String {
        // Replace block-level tags with newlines to preserve word boundaries
        var text = html
        // Replace <br>, <br/>, <BR> with space
        text = text.replacingOccurrences(of: "<br", with: " ", options: .caseInsensitive)
        // Remove remaining tags
        // Simple character-level scan — no regex, no HTML parser dependency (T-07-SC)
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
        // Normalise whitespace (collapse runs of spaces/newlines)
        let components = result.components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
        return components.joined(separator: " ")
    }

    /// Extracts the `Date:` header value and parses it as a Date.
    private func extractDate(from rawEmail: String) -> Date? {
        // Look for "Date: " header line
        guard let range = rawEmail.range(of: "Date: ", options: .caseInsensitive) else {
            return nil
        }
        let after = String(rawEmail[range.upperBound...])
        let line = after.components(separatedBy: "\n").first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        // Try RFC 2822 date format
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        let formats = [
            "EEE, dd MMM yyyy HH:mm:ss Z",
            "dd MMM yyyy HH:mm:ss Z",
            "EEE, d MMM yyyy HH:mm:ss Z",
        ]
        for fmt in formats {
            formatter.dateFormat = fmt
            if let date = formatter.date(from: line) { return date }
        }
        return nil
    }

    /// Extracts Decimal amount using an NSRegularExpression pattern.
    /// Group 1 of the pattern must capture the numeric string (may include commas).
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
            .replacingOccurrences(of: ",", with: "")  // strip Indian grouping commas
        return Decimal(string: amtStr)
    }

    /// Extracts account/card last-4-digits.
    private func extractAccountTail(pattern: String, from body: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return nil
        }
        let nsBody = body as NSString
        let range = NSRange(location: 0, length: nsBody.length)
        guard let match = regex.firstMatch(in: body, options: [], range: range),
              match.numberOfRanges > 1 else {
            return nil
        }
        let tailRange = match.range(at: 1)
        guard tailRange.location != NSNotFound else { return nil }
        return nsBody.substring(with: tailRange)
    }

    /// Extracts UPI merchant: text inside last `(...)` that appears before " on <dd-mm-yy>".
    private func extractUPIMerchant(from body: String) -> String? {
        // Pattern: "towards VPA <vpa> (<MERCHANT>) on"
        let pattern = #"towards VPA\s+\S+\s+\(([^)]+)\)\s+on"#
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

    /// Extracts InstaAlert UPI merchant: the display name after the VPA token, before " on <dd-mm-yy>".
    /// Format: "to VPA <vpa> <MERCHANT> on <dd-mm-yy>". Falls back to the VPA token when no display
    /// name is present ("to VPA <vpa> on <dd-mm-yy>").
    private func extractInstaAlertMerchant(from body: String) -> String? {
        let nsBody = body as NSString
        let range = NSRange(location: 0, length: nsBody.length)
        // Preferred: capture the display name that follows the VPA token.
        let withName = #"to VPA\s+\S+\s+(.+?)\s+on\s+\d{2}-\d{2}-\d{2}"#
        if let regex = try? NSRegularExpression(pattern: withName, options: []),
           let m = regex.firstMatch(in: body, options: [], range: range),
           m.numberOfRanges > 1, m.range(at: 1).location != NSNotFound {
            return nsBody.substring(with: m.range(at: 1)).trimmingCharacters(in: .whitespaces)
        }
        // Fallback: no display name — use the VPA token itself.
        let vpaOnly = #"to VPA\s+(\S+)\s+on\s+\d{2}-\d{2}-\d{2}"#
        if let regex = try? NSRegularExpression(pattern: vpaOnly, options: []),
           let m = regex.firstMatch(in: body, options: [], range: range),
           m.numberOfRanges > 1, m.range(at: 1).location != NSNotFound {
            return nsBody.substring(with: m.range(at: 1)).trimmingCharacters(in: .whitespaces)
        }
        return nil
    }

    /// Extracts debit-card merchant: text between " at " and " on " in debit-card template.
    private func extractDebitCardMerchant(from body: String) -> String? {
        // Pattern: "Debit Card ending NNNN at <MERCHANT> on <date>"
        let pattern = #"Debit Card ending\s+\d{4}\s+at\s+(.+?)\s+on\s+\d{2}\s+\w{3}"#
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

    /// Extracts refund merchant: text after "by VPA <vpa-identifier>" up to " on ".
    ///
    /// Corpus example: "by VPA gpayrefund-online@axisbank Google India Digital Services Pvt Ltd on 01-05-26"
    private func extractRefundMerchant(from body: String) -> String? {
        // Pattern: "by VPA <vpa-local-part@domain> <MERCHANT> on <dd-mm-yy>"
        let pattern = #"by VPA\s+\S+\s+(.+?)\s+on\s+\d{2}-\d{2}-\d{2}"#
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

    /// Parses HDFC UPI date format: "dd-mm-yy" (e.g. "02-06-26" = 2 Jun 2026).
    private func extractDDMMYY(from body: String) -> Date? {
        let pattern = #"\b(\d{2}-\d{2}-\d{2})\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return nil }
        let nsBody = body as NSString
        let range = NSRange(location: 0, length: nsBody.length)
        guard let match = regex.firstMatch(in: body, options: [], range: range) else { return nil }
        let dateStr = nsBody.substring(with: match.range(at: 1))
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "Asia/Kolkata")
        formatter.dateFormat = "dd-MM-yy"
        return formatter.date(from: dateStr)
    }

    /// Parses HDFC debit-card date format: "dd Mon, yyyy" (e.g. "01 Jun, 2026").
    private func extractDDMonYYYY(from body: String) -> Date? {
        let pattern = #"\b(\d{1,2}\s+\w{3},\s*\d{4})\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return nil }
        let nsBody = body as NSString
        let range = NSRange(location: 0, length: nsBody.length)
        guard let match = regex.firstMatch(in: body, options: [], range: range) else { return nil }
        let dateStr = nsBody.substring(with: match.range(at: 1))
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "Asia/Kolkata")
        formatter.dateFormat = "d MMM, yyyy"
        return formatter.date(from: dateStr)
    }
}
