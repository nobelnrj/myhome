import SwiftUI

/// Presentation-only mapping from a `Category` to a display color.
///
/// Phase 14 (D-03): rewired to the neumorphic category palette from `DesignTokens.cat*`.
/// The data model only stores `symbolName`, so the color is **derived here at render
/// time** — no schema field is added (feature-preservation constraint). Unknown symbols fall
/// back to a stable hashed palette slot so custom categories still get a consistent color.
///
/// All colors are DesignTokens.cat* values — no stock system colors (D-01 no-translucent rule).
enum CategoryStyle {

    /// Ordered palette used for the hashed fallback — all DesignTokens.cat* values (D-03).
    private static let palette: [Color] = [
        DesignTokens.catGroceries,
        DesignTokens.catDining,
        DesignTokens.catFuel,
        DesignTokens.catUtilities,
        DesignTokens.catRent,
        DesignTokens.catAuto,
        DesignTokens.catShopping,
        DesignTokens.catHealth,
        DesignTokens.catSubscriptions,
        DesignTokens.catEntertainment,
        DesignTokens.catOther,
    ]

    /// Direct symbol → color map for seeded categories (DesignTokens.cat* palette, D-03).
    private static let bySymbol: [String: Color] = [
        "cart":                               DesignTokens.catGroceries,
        "fork.knife":                         DesignTokens.catDining,
        "fuelpump":                           DesignTokens.catFuel,
        "bolt":                               DesignTokens.catUtilities,
        "house":                              DesignTokens.catRent,
        "house.fill":                         DesignTokens.catRent,
        "car":                                DesignTokens.catAuto,
        "bag":                                DesignTokens.catShopping,
        "cross.case":                         DesignTokens.catHealth,
        "film":                               DesignTokens.catEntertainment,
        "antenna.radiowaves.left.and.right":  DesignTokens.catSubscriptions,
        "person.2":                           DesignTokens.catOther,
        "arrow.up.right":                     DesignTokens.catOther,
        "banknote":                           DesignTokens.catGroceries,
        "tray":                               DesignTokens.catOther,
    ]

    /// Stable display color for a category (nil → catOther, unknown symbol → hashed palette slot).
    /// All returned colors are DesignTokens.cat* values — never a stock system color (D-03).
    static func color(for category: Category?) -> Color {
        guard let category else { return DesignTokens.catOther }
        if let symbol = category.symbolName, let mapped = bySymbol[symbol] { return mapped }
        // Stable hashed fallback keyed on the category name (deterministic across launches).
        let key = category.name ?? category.symbolName ?? "?"
        let idx = abs(stableHash(key)) % palette.count
        return palette[idx]   // always a DesignTokens.cat* color (D-03)
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
