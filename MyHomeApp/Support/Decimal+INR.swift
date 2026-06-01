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
}
