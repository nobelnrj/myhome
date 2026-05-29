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
}
