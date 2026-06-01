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
    func formattedINRCompact() -> String {
        let d = NSDecimalNumber(decimal: self).doubleValue
        if d >= 100_000 { return "₹\(Int(d / 100_000))L" }
        if d >= 1_000   { return "₹\(Int(d / 1_000))k" }
        return "₹\(Int(d))"
    }
}
