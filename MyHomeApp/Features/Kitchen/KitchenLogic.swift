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
    ///
    /// As of 22-01 no symbol string is written here: the keyword table yields a `PantryCategory`
    /// and `PantryCategory.presentation` owns every symbol and colour in the Kitchen feature
    /// (ICON-02). The keyword table is RETAINED and demoted to the offline fallback beneath the
    /// 22-03 on-device model path — it must keep working with Apple Intelligence switched off.
    static func icon(forName rawName: String?) -> (symbol: String, color: Color) {
        keywordCategory(forName: rawName)?.presentation ?? PantryCategory.other.presentation
    }

    /// Convenience overload for a live pantry row.
    static func icon(for item: PantryItem) -> (symbol: String, color: Color) {
        icon(forName: item.name)
    }

    /// The keyword table's opinion about an item name, or `nil` when it has none.
    ///
    /// `nil` means "no opinion" and is deliberately distinct from a confident `.other`: the CALLER
    /// decides the fallback, so 22-03's resolver can tell "the table doesn't know" from "this really
    /// is miscellaneous". `internal` (not private) so that resolver and its tests can call it.
    static func keywordCategory(forName rawName: String?) -> PantryCategory? {
        guard let name = normalizedIconKey(forName: rawName) else { return nil }
        for rule in iconRules where rule.keywords.contains(where: { name.contains($0) }) {
            return rule.category
        }
        return nil
    }

    /// The trimmed, lowercased name — `nil` when blank.
    ///
    /// The ONE normalisation rule in the codebase: keyword matching uses it, and 22-02's device-local
    /// icon cache keys on it, so a cache hit and a keyword match can never disagree about what
    /// "  Sona Masoori RICE " normalises to.
    static func normalizedIconKey(forName rawName: String?) -> String? {
        let key = (rawName ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return key.isEmpty ? nil : key
    }

    private struct IconRule {
        let keywords: [String]
        let category: PantryCategory
    }

    /// First match wins, so put the specific rules above the generic ones. Keyword arrays and their
    /// ORDER are unchanged from 20-03 — 22-01 only swapped each rule's symbol/colour pair for the
    /// category that maps to it, so no shipped tile changed appearance.
    private static let iconRules: [IconRule] = [
        IconRule(keywords: ["milk", "curd", "yoghurt", "yogurt", "cream"], category: .dairy),
        IconRule(keywords: ["egg"], category: .eggs),
        IconRule(keywords: ["coffee", "tea", "chai"], category: .brew),
        IconRule(keywords: ["oil", "ghee", "butter"], category: .oilFat),
        IconRule(keywords: ["soap", "detergent", "dishwash", "cleaner", "phenyl"], category: .cleaning),
        IconRule(keywords: ["onion", "tomato", "potato", "vegetable", "veg", "spinach", "chilli", "chili"],
                 category: .produce),
        IconRule(keywords: ["fruit", "apple", "banana", "orange", "mango"], category: .fruit),
        // Dry staples share ONE warm amber jar tile, matching the reference mockup where rice,
        // atta, dal and sugar are visually the same kind of thing on the shelf. `.spice` and
        // `.grainStaple` therefore render identically today — the split exists so the model path
        // can tell a spice from a staple without changing what the shelf looks like.
        IconRule(keywords: ["salt", "sugar", "jaggery", "masala", "spice", "powder"], category: .spice),
        IconRule(keywords: ["rice", "atta", "flour", "dal", "wheat", "rava", "poha", "grain", "pulse"],
                 category: .grainStaple),
        IconRule(keywords: ["bread", "bun", "biscuit", "cookie", "snack"], category: .snackBakery),
        IconRule(keywords: ["water", "juice", "drink", "soda"], category: .beverage)
    ]
}
