import Foundation

// MARK: - CUBParser
// ING-06, ING-07, ING-08, ING-09
// Threat: T-07-08 (body treated as plain String — no eval, no HTML rendering)
// Threat: T-07-09 (canHandle pre-filter rejects non-bank senders)

/// Two-stage City Union Bank (CUB) email parser.
///
/// Stage 1 (ING-08): sender host + blocked-subject pre-filter via `canHandle`.
/// Stage 2 (ING-07): fingerprint → extraction → normalization → reversal detection.
///
/// CUB transaction alerts arrive as multipart/alternative (text/plain + text/html,
/// quoted-printable encoded). The parser decodes quoted-printable and strips HTML
/// tags to recover visible text, mirroring `HDFCParser`.
///
/// **Confirmed corpus (06-05):**
/// - CUB debit: "<AccountType> No XXXXXXXX<NN> debited with INR <amount> towards <description> on <DD-MON-YYYY>.Avl Bal <balance>"
///
/// A symmetric credit/reversal template ("credited with INR …") is handled defensively
/// (ING-09) — when present it produces isReversal=true and a negative amount.
public struct CUBParser: BankEmailParser {

    public let parserID = "cub-v1"
    public let parserVersion = "1.0"

    public init() {}

    // MARK: - Allowed senders (confirmed, ING-08)

    /// Confirmed CUB sender host (domain portion after @) — cubalert@cityunionbank.org.
    private static let allowedSenderHost = "cityunionbank.org"

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
        // Sender host must match (T-07-09: rejects non-CUB senders)
        let senderLower = sender.lowercased()
        guard senderLower.hasSuffix("@\(CUBParser.allowedSenderHost)") ||
              senderLower.hasSuffix(".\(CUBParser.allowedSenderHost)") else {
            return false
        }
        // Block OTP/promo/statement subjects (ING-08)
        let subjectLower = subject.lowercased()
        for keyword in CUBParser.blockedSubjectKeywords {
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

        // Try debit first, then credit/reversal
        if let expense = parseDebit(body: body, fallbackDate: fallbackDate) {
            return expense
        }
        if let expense = parseCredit(body: body, fallbackDate: fallbackDate) {
            return expense
        }
        return nil
    }

    // MARK: - Template parsers

    /// CUB debit: "<AccountType> No XXXXXXXX<NN> debited with INR <amount> towards <description> on <DD-MON-YYYY>.Avl Bal <balance>"
    private func parseDebit(body: String, fallbackDate: Date) -> ParsedExpense? {
        // FINGERPRINT — required literals (ING-07): if any missing, return nil
        guard body.contains("debited with INR"),
              body.contains("towards"),
              body.contains("Avl Bal") else {
            return nil
        }

        // EXTRACT amount — "debited with INR <amount> towards"
        guard let amount = extractAmount(pattern: #"debited with INR\s+([\d,]+(?:\.\d{1,2})?)\s+towards"#, from: body) else {
            return nil
        }

        // EXTRACT account tail — "No XXXXXXXX<NN>"
        let accountTail = extractCapture(pattern: #"No\s+X+(\d{2,4})"#, from: body) ?? ""
        let sourceLabel = accountTail.isEmpty ? "CUB" : "CUB ••\(accountTail)"

        // EXTRACT merchant — text between "towards " and " on <DD-MON-YYYY>"
        guard let merchant = extractCUBMerchant(from: body) else { return nil }

        // EXTRACT date — "on <DD-MON-YYYY>"
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

    /// CUB credit/reversal: "<AccountType> No XXXXXXXX<NN> credited with INR <amount> towards <description> on <DD-MON-YYYY>.Avl Bal <balance>"
    ///
    /// Symmetric to the debit template. Produces isReversal=true with a negative amount (ING-09).
    private func parseCredit(body: String, fallbackDate: Date) -> ParsedExpense? {
        // FINGERPRINT
        guard body.contains("credited with INR"),
              body.contains("towards"),
              body.contains("Avl Bal") else {
            return nil
        }

        // EXTRACT amount — "credited with INR <amount> towards"
        guard let amount = extractAmount(pattern: #"credited with INR\s+([\d,]+(?:\.\d{1,2})?)\s+towards"#, from: body) else {
            return nil
        }

        // EXTRACT account tail — "No XXXXXXXX<NN>"
        let accountTail = extractCapture(pattern: #"No\s+X+(\d{2,4})"#, from: body) ?? ""
        let sourceLabel = accountTail.isEmpty ? "CUB" : "CUB ••\(accountTail)"

        // EXTRACT merchant — text between "towards " and " on <DD-MON-YYYY>"
        guard let merchant = extractCUBMerchant(from: body) else { return nil }

        // EXTRACT date — "on <DD-MON-YYYY>"
        let date = extractDDMonYYYY(from: body) ?? fallbackDate

        // NORMALISE
        let normalized = MerchantNormalizer.normalize(merchant)

        return ParsedExpense(
            amount: -abs(amount),   // Credit/reversal → negative amount (ING-09)
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

    // MARK: - Extraction helpers

    /// Decodes quoted-printable and strips HTML tags to get visible text.
    ///
    /// CUB emails are multipart/alternative (text/plain + text/html, quoted-printable).
    /// The body lacks a top-level `<html` tag, so the whole raw message is decoded and
    /// stripped — the first regex match is taken from the leading text/plain section.
    private func extractVisibleText(from rawEmail: String) -> String {
        let lower = rawEmail.lowercased()
        var htmlContent = rawEmail

        if let htmlStart = lower.range(of: "<html") {
            htmlContent = String(rawEmail[htmlStart.lowerBound...])
        }

        let qpDecoded = decodeQuotedPrintable(htmlContent)
        return stripHTMLTags(qpDecoded)
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
                    // Soft line break: =\r\n
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
        var text = html
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

    /// Extracts CUB merchant/description: text between "towards " and " on <DD-MON-YYYY>".
    ///
    /// Corpus: "towards TO ONL NACH_DR/CIUB7020202261000973/INDIAN CLEARING C::00520 on 03-JUN-2026"
    private func extractCUBMerchant(from body: String) -> String? {
        let pattern = #"towards\s+(.+?)\s+on\s+\d{1,2}-\w{3}-\d{4}"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
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

    /// Parses CUB date format: "DD-MON-YYYY" (e.g. "03-JUN-2026"). Month token is uppercase
    /// in the corpus; parsing is normalised to title-case for DateFormatter robustness.
    private func extractDDMonYYYY(from body: String) -> Date? {
        let pattern = #"\b(\d{1,2}-\w{3}-\d{4})\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return nil }
        let nsBody = body as NSString
        let range = NSRange(location: 0, length: nsBody.length)
        guard let match = regex.firstMatch(in: body, options: [], range: range) else { return nil }
        let dateStr = nsBody.substring(with: match.range(at: 1))

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "Asia/Kolkata")
        formatter.dateFormat = "dd-MMM-yyyy"
        if let d = formatter.date(from: dateStr) { return d }

        // Fallback: normalise month token to title-case (JUN → Jun)
        let parts = dateStr.split(separator: "-")
        if parts.count == 3 {
            let normalized = "\(parts[0])-\(parts[1].capitalized)-\(parts[2])"
            return formatter.date(from: normalized)
        }
        return nil
    }
}
