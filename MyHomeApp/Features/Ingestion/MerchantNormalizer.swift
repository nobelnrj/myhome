import Foundation

// MARK: - MerchantSeedEntry

/// A single entry in the merchant normalization seed table (ING-15, D7-09, D7-12).
///
/// `normalizedName` is the display-ready merchant name (e.g., "Amazon", "Zomato").
/// `categoryHint` is the suggested category name matching the existing 14-category seed list,
/// or nil when no suitable category is known (maps to Uncategorized fallback — D7-09).
public struct MerchantSeedEntry: Sendable {
    public let normalizedName: String
    public let categoryHint: String?   // nil = Uncategorized fallback (D7-09)

    public init(normalizedName: String, categoryHint: String?) {
        self.normalizedName = normalizedName
        self.categoryHint = categoryHint
    }
}

// MARK: - MerchantNormalizer

/// Pure static lookup that maps raw bank-email merchant strings to normalized names and
/// category hints. No I/O, no SwiftData — safe to call from any context (ING-15, D7-12).
///
/// **Seed table:** ~29 Indian merchants curated by Claude (D7-12). Not user-editable in v1.
/// Keys are UPPERCASE substrings that appear in bank email merchant fields.
/// **Longest-key-wins rule:** Resolves ambiguous prefix matches by sorting keys by length
/// descending and returning the first `contains` hit (D7-09).
/// **Unknown fallback:** When no key matches, returns the raw merchant string unchanged
/// with nil categoryHint (Uncategorized — D7-09).
///
/// Category hint strings match the seeded category names in `ModelContainer+App.swift`.
/// "Travel" is not in the v1 seed list — travel merchants map to "Misc" (closest match).
public struct MerchantNormalizer {

    /// Merchant seed table. Keys are UPPERCASE substrings; values are display name + hint.
    /// [ASSUMED] The exact raw merchant strings that appear in HDFC/ICICI emails. Refined
    /// from real corpus (D7-03) after first week in production.
    public static let seed: [String: MerchantSeedEntry] = [
        // --- E-Commerce / Shopping ---
        "AMAZON IN":      .init(normalizedName: "Amazon",      categoryHint: "Shopping"),
        "AMAZON":         .init(normalizedName: "Amazon",      categoryHint: "Shopping"),
        "FLIPKART":       .init(normalizedName: "Flipkart",    categoryHint: "Shopping"),
        "MYNTRA":         .init(normalizedName: "Myntra",      categoryHint: "Shopping"),
        "NYKAA":          .init(normalizedName: "Nykaa",       categoryHint: "Shopping"),
        // --- Food Delivery / Dining ---
        "ZOMATO":         .init(normalizedName: "Zomato",      categoryHint: "Dining"),
        "SWIGGY":         .init(normalizedName: "Swiggy",      categoryHint: "Dining"),
        // --- Grocery / Quick Commerce ---
        "BIGBASKET":      .init(normalizedName: "BigBasket",   categoryHint: "Groceries"),
        "BLINKIT":        .init(normalizedName: "Blinkit",     categoryHint: "Groceries"),
        "ZEPTO":          .init(normalizedName: "Zepto",       categoryHint: "Groceries"),
        "INSTAMART":      .init(normalizedName: "Swiggy Instamart", categoryHint: "Groceries"),
        // --- Auto / Cab ---
        "UBER":           .init(normalizedName: "Uber",        categoryHint: "Auto/Cab"),
        "OLA":            .init(normalizedName: "Ola",         categoryHint: "Auto/Cab"),
        "RAPIDO":         .init(normalizedName: "Rapido",      categoryHint: "Auto/Cab"),
        // --- Fuel ---
        "INDIAN OIL":     .init(normalizedName: "Indian Oil",  categoryHint: "Fuel"),
        "HPCL":           .init(normalizedName: "HPCL",        categoryHint: "Fuel"),
        "BPCL":           .init(normalizedName: "BPCL",        categoryHint: "Fuel"),
        // --- Entertainment / Streaming ---
        "NETFLIX":        .init(normalizedName: "Netflix",     categoryHint: "Entertainment"),
        "SPOTIFY":        .init(normalizedName: "Spotify",     categoryHint: "Entertainment"),
        "HOTSTAR":        .init(normalizedName: "Disney+ Hotstar", categoryHint: "Entertainment"),
        "JIOCINEMA":      .init(normalizedName: "JioCinema",   categoryHint: "Entertainment"),
        // --- Travel (no "Travel" category in v1 seed → map to "Misc") ---
        "MAKEMYTRIP":     .init(normalizedName: "MakeMyTrip",  categoryHint: "Misc"),
        "GOIBIBO":        .init(normalizedName: "Goibibo",     categoryHint: "Misc"),
        "IRCTC":          .init(normalizedName: "IRCTC",       categoryHint: "Misc"),
        // --- Health / Pharmacy ---
        "APOLLO":         .init(normalizedName: "Apollo Pharmacy", categoryHint: "Health/Pharmacy"),
        "MEDPLUS":        .init(normalizedName: "MedPlus",     categoryHint: "Health/Pharmacy"),
        // --- UPI / Digital Payments ---
        "PHONEPE":        .init(normalizedName: "PhonePe",     categoryHint: "UPI to Person"),
        "GPAY":           .init(normalizedName: "Google Pay",  categoryHint: "UPI to Person"),
        "PAYTM":          .init(normalizedName: "Paytm",       categoryHint: "UPI to Person"),
    ]

    /// Returns a `MerchantSeedEntry` for the given raw merchant string.
    ///
    /// Algorithm (D7-09 longest-key-wins):
    /// 1. Uppercase the input.
    /// 2. Sort seed keys by length descending (longest first).
    /// 3. Return the entry for the first key contained in the uppercased input.
    /// 4. If no key matches, return the raw string as-is with nil categoryHint (D7-12).
    public static func normalize(_ rawMerchant: String) -> MerchantSeedEntry {
        let upper = rawMerchant.uppercased()
        // Sort by key length descending — longer (more specific) keys win.
        let hit = seed.keys
            .sorted { $0.count > $1.count }
            .first { upper.contains($0) }
        if let key = hit, let entry = seed[key] {
            return entry
        }
        // Unknown merchant: pass through raw string, no category hint (D7-12, D7-09).
        return MerchantSeedEntry(normalizedName: rawMerchant, categoryHint: nil)
    }
}
