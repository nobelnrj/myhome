import SwiftUI

/// Presentation-only mapping from a `Category` to a display color.
///
/// The refreshed design (`MyHome.html`) gives each category a stable color from the iOS system
/// palette. The data model only stores `symbolName`, so the color is **derived here at render
/// time** — no schema field is added (feature-preservation constraint). Unknown symbols fall
/// back to a stable hashed palette slot so custom categories still get a consistent color.
///
/// All colors are iOS system colors, so light/dark adaptation is automatic.
enum CategoryStyle {

    /// Ordered palette used for the hashed fallback.
    private static let palette: [Color] = [
        Color(.systemGreen), Color(.systemOrange), Color(.systemRed),
        Color(.systemYellow), Color(.systemIndigo), Color(.systemTeal),
        Color(.systemPink), Color(.systemPurple), Color(.systemBlue),
        Color(.systemBrown), Color(.systemCyan), Color(.systemMint),
    ]

    /// Direct symbol → color map for the seeded categories (mirrors the design palette).
    private static let bySymbol: [String: Color] = [
        "cart": Color(.systemGreen),                              // Groceries
        "fork.knife": Color(.systemOrange),                       // Dining
        "fuelpump": Color(.systemRed),                            // Fuel
        "bolt": Color(.systemYellow),                             // Utilities
        "house": Color(.systemIndigo),                            // Rent
        "house.fill": Color(.systemIndigo),
        "car": Color(.systemTeal),                                // Auto/Cab
        "bag": Color(.systemPink),                                // Shopping
        "cross.case": Color(.systemPurple),                       // Health/Pharmacy
        "film": Color(.systemMint),                               // Entertainment
        "antenna.radiowaves.left.and.right": Color(.systemCyan),  // Recharge/DTH
        "person.2": Color(.systemBrown),                          // Maid/Help
        "arrow.up.right": Color(.systemBlue),                     // UPI to Person
        "banknote": Color(.systemGreen),                          // ATM
        "tray": Color(.systemGray),                               // Misc
    ]

    /// Stable display color for a category (nil → neutral gray, e.g. Uncategorized).
    static func color(for category: Category?) -> Color {
        guard let category else { return Color(.systemGray) }
        if let symbol = category.symbolName, let mapped = bySymbol[symbol] { return mapped }
        // Stable hashed fallback keyed on the category name (deterministic across launches).
        let key = category.name ?? category.symbolName ?? "?"
        let idx = abs(stableHash(key)) % palette.count
        return palette[idx]
    }

    /// SF Symbol to render for a category (falls back to a neutral tag glyph).
    static func symbol(for category: Category?) -> String {
        category?.symbolName ?? "tag"
    }

    /// FNV-1a — deterministic across processes (Swift's `Hashable` is salted per run, so it
    /// can't be used for a color that must stay stable across launches).
    private static func stableHash(_ s: String) -> Int {
        var h: UInt64 = 1469598103934665603
        for byte in s.utf8 { h = (h ^ UInt64(byte)) &* 1099511628211 }
        return Int(bitPattern: UInt(truncatingIfNeeded: h))
    }
}
