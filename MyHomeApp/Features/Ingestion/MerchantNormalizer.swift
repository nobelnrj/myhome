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

        // =====================================================================
        // Real-corpus additions (07-07) — merchants observed in the live
        // HDFC/ICICI email corpus that previously fell through to Uncategorized.
        // Keys are UPPERCASE substrings; longest-key-wins resolves overlaps.
        // =====================================================================

        // --- Grocery / Quick Commerce (legal names + recurring local vendors) ---
        "INNOVATIVE RETAIL CONCEPTS": .init(normalizedName: "BigBasket", categoryHint: "Groceries"), // BigBasket's registered entity
        "BLINK COMMERCE":  .init(normalizedName: "Blinkit",   categoryHint: "Groceries"),            // Blinkit's registered entity
        "LICIOUS":         .init(normalizedName: "Licious",   categoryHint: "Meat"),
        "DELIGHTFUL GOURMET": .init(normalizedName: "Licious", categoryHint: "Meat"),                 // Delightful Gourmet Pvt Ltd = Licious (meat/seafood delivery)
        "SRI SAI VEG":     .init(normalizedName: "Sri Sai Veg Basket", categoryHint: "Groceries"),
        "FRESHALICIOUS":   .init(normalizedName: "Freshalicious", categoryHint: "Groceries"),
        // Amazon Pay "grocery" MCC is more specific than the generic AMAZON→Shopping key.
        "AMAZON PAY IN GROCERY": .init(normalizedName: "Amazon Pay", categoryHint: "Groceries"),
        "AMAZON PAY GROCER":     .init(normalizedName: "Amazon Pay", categoryHint: "Groceries"),   // "Amazon Pay Groceries", "amazonpaygrocery"

        // --- Dining (recurring local eateries) ---
        "CORNER HOUSE":    .init(normalizedName: "Corner House Ice Creams", categoryHint: "Dining"),
        "OHHH MOMO":       .init(normalizedName: "Ohhh Momo Station", categoryHint: "Dining"),
        "AIRMENUS":        .init(normalizedName: "AirMenus",  categoryHint: "Dining"),

        // --- Shopping ---
        "ADITYA BIRLA FASHION": .init(normalizedName: "Aditya Birla Fashion", categoryHint: "Shopping"),
        "ASSPL":           .init(normalizedName: "Amazon",    categoryHint: "Shopping"),             // Amazon Seller Services Pvt Ltd

        // --- Utilities / Bills ---
        "ATRIA CONVERGENCE": .init(normalizedName: "ACT Fibernet", categoryHint: "Utilities"),       // Atria Convergence Technologies = ACT
        "ACT FIBERNET":    .init(normalizedName: "ACT Fibernet", categoryHint: "Utilities"),

        // --- Investments (SIPs / brokerages seen in CUB NACH + UPI corpus, 07-07) ---
        "GROWW":           .init(normalizedName: "Groww",       categoryHint: "Investments"),
        "ZERODHA":         .init(normalizedName: "Zerodha",     categoryHint: "Investments"),
        "BSE LIMITED":     .init(normalizedName: "BSE",         categoryHint: "Investments"),   // BSE StAR MF payments
        "BSE STAR":        .init(normalizedName: "BSE StAR MF",  categoryHint: "Investments"),
        "KUVERA":          .init(normalizedName: "Kuvera",      categoryHint: "Investments"),
        "INDMONEY":        .init(normalizedName: "INDmoney",    categoryHint: "Investments"),
        "SMALLCASE":       .init(normalizedName: "Smallcase",   categoryHint: "Investments"),

        // --- Software / Subscriptions (no dedicated category in v1 → Misc) ---
        "ANTHROPIC":       .init(normalizedName: "Anthropic", categoryHint: "Misc"),
        "CLAUDE":          .init(normalizedName: "Anthropic", categoryHint: "Misc"),
        "VERCEL":          .init(normalizedName: "Vercel",    categoryHint: "Misc"),
        "OPENAI":          .init(normalizedName: "OpenAI",    categoryHint: "Misc"),
        "GITHUB":          .init(normalizedName: "GitHub",    categoryHint: "Misc"),
    ]

    // MARK: - Keyword-based category fallback

    /// Category keyword table (07-07). Applied ONLY when no explicit `seed` key matches.
    /// Each entry maps an UPPERCASE substring to a seeded category name. This captures the
    /// long tail of local merchants (small eateries, kirana stores, clinics) whose exact
    /// names can't be enumerated but whose type is evident from a keyword in the string.
    ///
    /// Longest-keyword-wins (same rule as `seed`) so multi-word keywords like "ICE CREAM"
    /// take precedence over any shorter overlap. Conservative by design: a wrong hint is
    /// always user-correctable, but a false positive on a broad word (e.g. "STORE") would
    /// mis-tag many merchants, so only high-signal keywords are included.
    static let categoryKeywords: [String: String] = [
        // Dining
        "ICE CREAM": "Dining", "RESTAURANT": "Dining", "BIRYANI": "Dining",
        "BIRIYANI": "Dining", "BAKERY": "Dining", "PIZZA": "Dining",
        "MOMO": "Dining", "DHABA": "Dining", "SWEETS": "Dining",
        "CATERERS": "Dining", "FOOD COURT": "Dining",
        // Groceries
        "SUPER BAZAAR": "Groceries", "SUPERMARKET": "Groceries",
        "VEG BASKET": "Groceries", "PROVISION": "Groceries",
        "KIRANA": "Groceries", "GROCER": "Groceries", "DAIRY": "Groceries",
        // Fuel
        "PETROLEUM": "Fuel", "FILLING STATION": "Fuel", "PETROL PUMP": "Fuel",
        // ATM (CUB/HDFC cash withdrawals appear as "ATM WDL" / "ATM WITHDRAWAL")
        "ATM WDL": "ATM", "ATM WITHDRAWAL": "ATM", "ATM-CASH": "ATM",
        // Health / Pharmacy
        "PHARMACY": "Health/Pharmacy", "PHARMA": "Health/Pharmacy",
        "HOSPITAL": "Health/Pharmacy", "DIAGNOSTIC": "Health/Pharmacy",
        "CLINIC": "Health/Pharmacy",
        // Shopping
        "FASHION": "Shopping", "APPAREL": "Shopping", "GARMENTS": "Shopping",
        "LIFESTYLE": "Shopping",
        // Utilities
        "BROADBAND": "Utilities", "FIBERNET": "Utilities",
        // Investments (NACH SIP / MF clearing descriptions without an explicit platform name)
        "INDIAN CLEARING": "Investments", "MUTUAL FUND": "Investments",
        "INVEST TECH": "Investments", "STAR MF": "Investments",
    ]

    /// Returns a `MerchantSeedEntry` for the given raw merchant string.
    ///
    /// Algorithm (D7-09 longest-key-wins):
    /// 1. Uppercase the input.
    /// 2. Sort seed keys by length descending (longest first).
    /// 3. Return the entry for the first key contained in the uppercased input.
    /// 4. Fallback (07-07): no exact seed key → try the keyword table for a category hint,
    ///    keeping the raw merchant name unchanged.
    /// 5. If neither matches, return the raw string as-is with nil categoryHint (D7-12).
    public static func normalize(_ rawMerchant: String) -> MerchantSeedEntry {
        let upper = rawMerchant.uppercased()
        // Sort by key length descending — longer (more specific) keys win.
        let hit = seed.keys
            .sorted { $0.count > $1.count }
            .first { upper.contains($0) }
        if let key = hit, let entry = seed[key] {
            return entry
        }
        // Keyword fallback (07-07): infer a category from a high-signal keyword, but keep
        // the raw merchant string as the display name (we don't have a friendly name for it).
        // Longest-keyword-wins mirrors the seed rule so multi-word keywords take precedence.
        let keywordHit = categoryKeywords.keys
            .sorted { $0.count > $1.count }
            .first { upper.contains($0) }
        if let key = keywordHit, let category = categoryKeywords[key] {
            return MerchantSeedEntry(normalizedName: rawMerchant, categoryHint: category)
        }
        // Unknown merchant: pass through raw string, no category hint (D7-12, D7-09).
        return MerchantSeedEntry(normalizedName: rawMerchant, categoryHint: nil)
    }
}
