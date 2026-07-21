import SwiftUI

/// Derived stock state of a pantry item (KTCH-02).
///
/// Never stored: `PantryItem` carries only `quantity` and `lowStockThreshold`, and the state is
/// computed at render time. That keeps two phones from disagreeing about a materialised flag and
/// makes the shopping list (20-04) a pure function of pantry rows.
enum StockStatus: Equatable {
    /// Above the low-stock threshold — nothing to do.
    case inStock
    /// At or below the per-item threshold, but still some left.
    case low
    /// Nothing left (`quantity <= 0`).
    case out
}

/// Pure stock math + the sanctioned mutation helpers for pantry rows.
///
/// Single source of truth: the row steppers, the Overview glance, and the 20-04 shopping list all
/// resolve stock state through `stockStatus(quantity:threshold:)` so "low" means exactly one thing.
///
/// Sync hygiene (18-04 contract): every mutation helper calls `touch()` so a user action carries an
/// honest last-writer-wins clock. Helpers only mutate — the CALLER saves.
enum KitchenLogic {

    // MARK: - Stock status (KTCH-02)

    /// Derives the stock state from a quantity and its per-item low-stock threshold.
    ///
    /// Order matters: zero is ALWAYS `.out`, even when the threshold is 0 (a zero threshold means
    /// "only tell me when it's gone", not "never tell me"). At the threshold counts as `.low` —
    /// KTCH-02 says "at or below".
    static func stockStatus(quantity: Double, threshold: Double) -> StockStatus {
        if quantity <= 0 { return .out }
        if quantity <= threshold { return .low }
        return .inStock
    }

    /// Convenience overload for a live pantry row.
    static func stockStatus(for item: PantryItem) -> StockStatus {
        stockStatus(quantity: item.quantity, threshold: item.lowStockThreshold)
    }

    // MARK: - Mutations

    /// One-tap "I used some": decrements by 1, clamped at 0 (stock is never negative).
    /// Stamps the LWW clock. Caller saves.
    @MainActor
    static func markUsed(_ item: PantryItem) {
        item.quantity = max(0, item.quantity - 1)
        item.touch()
    }

    /// One-tap "I restocked": ADDS `restockQuantity` (additive by user decision, 2026-07-21 —
    /// the shopping "↻ + 3 kg" pill states the amount added, not a target level).
    /// Stamps the LWW clock. Caller saves.
    @MainActor
    static func markRestocked(_ item: PantryItem) {
        item.quantity += item.restockQuantity
        item.touch()
    }

    // MARK: - Derived shopping list (KTCH-03)

    /// The auto half of the shopping list: every pantry row that is NOT `.inStock`, out-of-stock
    /// first, then low, alphabetical (case-insensitive) within each group with unnamed rows last.
    ///
    /// PURE — takes rows, returns rows. It never touches a `ModelContext` and, critically, it
    /// **never inserts `ShoppingListItem` rows for auto entries** (20-01 locked sync design):
    /// materialising derived rows would let two phones mint duplicate "auto" entries that the
    /// merge engine could not reconcile, and it would break check-off restock, which is
    /// unambiguous precisely because a derived row IS its `PantryItem`. `ShoppingListItem` exists
    /// only for MANUAL extras. `ShoppingListTests.derivationNeverMaterialisesRows` pins this.
    static func deriveShoppingItems(from pantry: [PantryItem]) -> [PantryItem] {
        pantry
            .filter { stockStatus(for: $0) != .inStock }
            .sorted { a, b in
                let sa = stockStatus(for: a)
                let sb = stockStatus(for: b)
                if sa != sb { return sa == .out }          // out of stock first
                return sortKey(a) < sortKey(b)             // then alphabetical, unnamed last
            }
    }

    /// Alphabetical key: case-insensitive, and nil/blank names sort last (`"\u{10FFFF}"` beats any
    /// real name) so an unnamed row never jumps to the top of the list.
    private static func sortKey(_ item: PantryItem) -> String {
        let name = (item.name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? "\u{10FFFF}" : name.lowercased()
    }

    // MARK: - Manual shopping rows (KTCH-03)

    /// Flips a MANUAL shopping row's checked state and stamps the LWW clock. Caller saves.
    ///
    /// Deliberately does NOT touch the pantry: only DERIVED rows restock (via `markRestocked`).
    /// A manual extra ("Batteries") has no pantry row to restock — that is the whole point of the
    /// two-section split.
    @MainActor
    static func toggleChecked(_ item: ShoppingListItem) {
        item.isChecked.toggle()
        item.checkedAt = item.isChecked ? Date() : nil
        item.touch()
    }

    // MARK: - Derived item iconography (user decision, 2026-07-21 — DERIVED, never stored)

    /// SF Symbol + tile colour for a pantry item, derived from its NAME.
    ///
    /// Deliberately not persisted: `PantryItem` gains no `symbolName`/`colorHex`, so there is no
    /// icon field to sync, diverge, or migrate — and no icon picker in the edit sheet. Keyword
    /// matching is case-insensitive substring on the trimmed name; anything unmatched falls back to
    /// a neutral bag tile.
    ///
    /// Colours are existing semantic/category tokens only (adaptive light/dark pairs) — no new
    /// tokens, no edits to DesignTokens.swift.
    static func icon(forName rawName: String?) -> (symbol: String, color: Color) {
        let name = (rawName ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !name.isEmpty else { return fallbackIcon }

        for rule in iconRules where rule.keywords.contains(where: { name.contains($0) }) {
            return (rule.symbol, rule.color)
        }
        return fallbackIcon
    }

    /// Convenience overload for a live pantry row.
    static func icon(for item: PantryItem) -> (symbol: String, color: Color) {
        icon(forName: item.name)
    }

    private static let fallbackIcon: (symbol: String, color: Color) =
        ("bag.fill", DesignTokens.catOther)

    private struct IconRule {
        let keywords: [String]
        let symbol: String
        let color: Color
    }

    /// First match wins, so put the specific rules above the generic ones.
    private static let iconRules: [IconRule] = [
        IconRule(keywords: ["milk", "curd", "yoghurt", "yogurt", "cream"],
                 symbol: "drop.fill", color: DesignTokens.catGroceries),
        IconRule(keywords: ["egg"],
                 symbol: "oval.fill", color: DesignTokens.catGroceries),
        IconRule(keywords: ["coffee", "tea", "chai"],
                 symbol: "cup.and.saucer.fill", color: DesignTokens.catPantryBrew),
        IconRule(keywords: ["oil", "ghee", "butter"],
                 symbol: "drop.circle.fill", color: DesignTokens.catRent),
        IconRule(keywords: ["soap", "detergent", "dishwash", "cleaner", "phenyl"],
                 symbol: "bubbles.and.sparkles.fill", color: DesignTokens.catUtilities),
        IconRule(keywords: ["onion", "tomato", "potato", "vegetable", "veg", "spinach", "chilli", "chili"],
                 symbol: "leaf.fill", color: DesignTokens.catSubscriptions),
        IconRule(keywords: ["fruit", "apple", "banana", "orange", "mango"],
                 symbol: "basket.fill", color: DesignTokens.catFuel),
        // Dry staples share ONE warm amber jar tile, matching the reference mockup where rice,
        // atta, dal and sugar are visually the same kind of thing on the shelf.
        // NOTE: "takeoutbag.fill.and.rectangle.portrait" is NOT a real SF Symbol — it rendered an
        // empty tile (caught by screenshot, not by tests: SwiftUI silently draws nothing for an
        // unknown symbol name). Both dry-staple rules use shippingbox.fill, which is verified to
        // render. Any new symbol name here must be eyeballed on the simulator before it ships.
        IconRule(keywords: ["salt", "sugar", "jaggery", "masala", "spice", "powder"],
                 symbol: "shippingbox.fill", color: DesignTokens.catPantryGrain),
        IconRule(keywords: ["rice", "atta", "flour", "dal", "wheat", "rava", "poha", "grain", "pulse"],
                 symbol: "shippingbox.fill", color: DesignTokens.catPantryGrain),
        IconRule(keywords: ["bread", "bun", "biscuit", "cookie", "snack"],
                 symbol: "birthday.cake.fill", color: DesignTokens.catEntertainment),
        IconRule(keywords: ["water", "juice", "drink", "soda"],
                 symbol: "waterbottle.fill", color: DesignTokens.catAuto)
    ]
}
