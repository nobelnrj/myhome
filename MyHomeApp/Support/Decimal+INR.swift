import Foundation

extension Decimal {
    /// Formats this Decimal as Indian Rupee with lakh grouping.
    ///
    /// Examples:
    ///   Decimal(100000).formattedINR()  // "₹1,00,000.00"  (lakh grouping — FND-07)
    ///   Decimal(-500).formattedINR()    // "-₹500.00"       (sign before symbol)
    ///
    /// Uses FormatStyle (not NumberFormatter) — the modern API (iOS 15+) per RESEARCH Pattern 5.
    /// Never hand-rolled ₹ symbol or custom String(format:) (Pitfall 17).
    func formattedINR() -> String {
        self.formatted(
            .currency(code: "INR")
            .locale(Locale(identifier: "en_IN"))
        )
    }

    /// Whole-rupee INR (no paise) with lakh grouping.
    ///
    /// Used by the refreshed UI's hero figures, donut centers, and budget glances where paise
    /// add visual noise. `formattedINR()` (with paise) remains the default for row-level amounts.
    func formattedINRWhole() -> String {
        self.formatted(
            .currency(code: "INR")
            .locale(Locale(identifier: "en_IN"))
            .precision(.fractionLength(0))
        )
    }

    /// Compact INR formatter for chart axis labels and bar annotations only.
    ///
    /// Thresholds (truncation via Int, no rounding):
    ///   ≥ 1,00,000 → "₹NL"   (lakhs,   e.g. "₹1L", "₹5L")
    ///   ≥ 1,000    → "₹Nk"   (thousands, e.g. "₹1k", "₹50k")
    ///   else       → "₹N"    (units,     e.g. "₹500", "₹999")
    ///
    /// Conversion via NSDecimalNumber(decimal:).doubleValue — never Double(truncating:)
    /// or String(format:) (Pitfall B/17 guard). Do NOT use this for stored money or
    /// displayed totals — use formattedINR() everywhere else.
    ///
    /// Negative amounts (refunds — a first-class concept; a large refund can drive a
    /// daily/monthly bucket negative) compact on magnitude with the sign placed before
    /// the symbol, matching formattedINR()'s "-₹500" convention (WR-01).
    func formattedINRCompact() -> String {
        let d = NSDecimalNumber(decimal: self).doubleValue
        let sign = d < 0 ? "-" : ""
        let a = abs(d)
        if a >= 100_000 { return "\(sign)₹\(Int(a / 100_000))L" }
        if a >= 1_000   { return "\(sign)₹\(Int(a / 1_000))k" }
        return "\(sign)₹\(Int(a))"
    }

    /// Rounded "word" INR for compact card readouts (e.g. donut amounts), per the user's
    /// "3 Lakhs" preference. Indian scale words; one decimal, trailing ".0" trimmed.
    ///
    ///   ≥ 1 crore  → "₹1.2 Cr"
    ///   ≥ 1 lakh   → "₹3 Lakhs" / "₹1.5 Lakhs" (singular "Lakh" at exactly 1)
    ///   ≥ 1,000    → "₹17K"
    ///   else       → "₹500"
    func formattedINRWords() -> String {
        let d = NSDecimalNumber(decimal: self).doubleValue
        let sign = d < 0 ? "-" : ""
        let a = abs(d)

        func trim(_ v: Double) -> String {
            let r = (v * 10).rounded() / 10
            return r == r.rounded() ? String(Int(r)) : String(format: "%.1f", r)
        }

        if a >= 10_000_000 { return "\(sign)₹\(trim(a / 10_000_000)) Cr" }
        if a >= 100_000 {
            let lakhs = trim(a / 100_000)
            return "\(sign)₹\(lakhs) \(lakhs == "1" ? "Lakh" : "Lakhs")"
        }
        if a >= 1_000 { return "\(sign)₹\(Int((a / 1_000).rounded()))K" }
        return "\(sign)₹\(Int(a.rounded()))"
    }
}
