import Testing
import SwiftData
import Foundation
@testable import MyHome

// Requirements: KTCH-01 (add/edit + used/restocked), KTCH-02 (per-item low/out thresholds).
// Validation: xcodebuild test -scheme MyHome -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:MyHomeTests/KitchenLogicTests

/// KitchenLogicTests — locks the stock-status boundaries (the semantics the whole kitchen surface
/// and the 20-04 shopping list derive from), the used/restocked mutation behaviour including the
/// clamp at zero and the honest LWW clock, the derived icon rules (user decision 2026-07-21:
/// icons are DERIVED from the name, never stored), and the tombstone-on-delete UI contract.
///
/// Double comparisons only ever touch exactly-representable values (0, 0.5, 1, 2, 5, 7), so plain
/// `==` is safe. Kitchen quantities are measurements, never money — no `Decimal` appears here.
@MainActor
struct KitchenLogicTests {

    // MARK: - Fixtures

    private static func makeStore() throws -> ModelContainer {
        let schema = Schema(versionedSchema: SchemaV11.self)
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [config])
    }

    // MARK: - Stock status (KTCH-02)

    @Test("Zero quantity is always out of stock, even with a zero threshold")
    func zeroIsAlwaysOut() {
        #expect(KitchenLogic.stockStatus(quantity: 0, threshold: 1) == .out)
        #expect(KitchenLogic.stockStatus(quantity: 0, threshold: 0) == .out)
    }

    @Test("At the threshold flags LOW — KTCH-02 says at OR below")
    func atThresholdIsLow() {
        #expect(KitchenLogic.stockStatus(quantity: 1, threshold: 1) == .low)
        #expect(KitchenLogic.stockStatus(quantity: 0.5, threshold: 1) == .low)
        #expect(KitchenLogic.stockStatus(quantity: 2, threshold: 5) == .low)
    }

    @Test("Above the threshold is in stock")
    func aboveThresholdIsInStock() {
        #expect(KitchenLogic.stockStatus(quantity: 2, threshold: 1) == .inStock)
        #expect(KitchenLogic.stockStatus(quantity: 0.5, threshold: 0) == .inStock)
    }

    @Test("The item overload reads the row's own threshold")
    func statusFromItem() {
        let milk = PantryItem(name: "Milk", quantity: 1.0, unit: "L", lowStockThreshold: 1.0)
        #expect(KitchenLogic.stockStatus(for: milk) == .low)
        milk.quantity = 5.0
        #expect(KitchenLogic.stockStatus(for: milk) == .inStock)
        milk.quantity = 0
        #expect(KitchenLogic.stockStatus(for: milk) == .out)
    }

    // MARK: - Mutations (KTCH-01)

    @Test("markUsed decrements by one and bumps the LWW clock")
    func markUsedDecrements() throws {
        let store = try Self.makeStore()
        let ctx = store.mainContext
        let rice = PantryItem(name: "Rice", quantity: 5.0, unit: "kg", lowStockThreshold: 1.0)
        ctx.insert(rice)
        try ctx.save()

        let before = rice.updatedAt
        KitchenLogic.markUsed(rice)
        try ctx.save()

        #expect(rice.quantity == 4.0)
        #expect(rice.updatedAt > before)
    }

    @Test("markUsed clamps at zero — stock never goes negative")
    func markUsedClampsAtZero() throws {
        let store = try Self.makeStore()
        let ctx = store.mainContext
        let eggs = PantryItem(name: "Eggs", quantity: 0.5, unit: "pcs", lowStockThreshold: 4.0)
        ctx.insert(eggs)

        KitchenLogic.markUsed(eggs)
        #expect(eggs.quantity == 0)

        KitchenLogic.markUsed(eggs)
        #expect(eggs.quantity == 0)
        #expect(KitchenLogic.stockStatus(for: eggs) == .out)
    }

    @Test("markRestocked adds restockQuantity and bumps the LWW clock")
    func markRestockedAdds() throws {
        let store = try Self.makeStore()
        let ctx = store.mainContext
        let coffee = PantryItem(
            name: "Coffee", quantity: 0, unit: "pack", lowStockThreshold: 1.0, restockQuantity: 5.0
        )
        ctx.insert(coffee)
        try ctx.save()

        let before = coffee.updatedAt
        KitchenLogic.markRestocked(coffee)
        try ctx.save()

        #expect(coffee.quantity == 5.0)
        #expect(coffee.updatedAt > before)
        #expect(KitchenLogic.stockStatus(for: coffee) == .inStock)

        // Additive, not "fill to target" (user decision 2026-07-21).
        KitchenLogic.markRestocked(coffee)
        #expect(coffee.quantity == 10.0)
    }

    // MARK: - Delete path (T-20-07 — the UI delete contract)

    @Test("deleteSynced leaves a pantryItem tombstone and removes the row")
    func deleteLeavesTombstone() throws {
        let store = try Self.makeStore()
        let ctx = store.mainContext
        let item = PantryItem(name: "Sugar", quantity: 2.0, unit: "kg", lowStockThreshold: 1.0)
        ctx.insert(item)
        try ctx.save()
        let syncID = item.syncID

        ctx.deleteSynced(item, kind: .pantryItem)
        try ctx.save()

        let remaining = try ctx.fetch(FetchDescriptor<PantryItem>())
        #expect(remaining.isEmpty)

        let logs = try ctx.fetch(FetchDescriptor<DeletionLog>())
        #expect(logs.count == 1)
        #expect(logs.first?.entityKindRaw == "pantryItem")
        #expect(logs.first?.entitySyncID == syncID)
    }

    // MARK: - Derived icons (user decision 2026-07-21 — derived, never stored)

    @Test("Keyword rules resolve the mockup's items to distinct tiles")
    func iconRulesMatchMockupItems() {
        #expect(KitchenLogic.icon(forName: "Milk").symbol == "drop.fill")
        #expect(KitchenLogic.icon(forName: "Eggs").symbol == "oval.fill")
        #expect(KitchenLogic.icon(forName: "Filter coffee").symbol == "cup.and.saucer.fill")
        #expect(KitchenLogic.icon(forName: "Cooking oil").symbol == "drop.circle.fill")
        #expect(KitchenLogic.icon(forName: "Sona Masoori rice").symbol == "shippingbox.fill")
        #expect(KitchenLogic.icon(forName: "Onions").symbol == "leaf.fill")
    }

    @Test("Icon matching is case-insensitive and trims whitespace")
    func iconMatchingIsCaseInsensitive() {
        #expect(KitchenLogic.icon(forName: "  ATTA  ").symbol == "shippingbox.fill")
        #expect(KitchenLogic.icon(forName: "toor DAL").symbol == "shippingbox.fill")
    }

    @Test("Unmatched and empty names fall back to the neutral tile")
    func iconFallback() {
        #expect(KitchenLogic.icon(forName: "Zqx widget").symbol == "bag.fill")
        #expect(KitchenLogic.icon(forName: "").symbol == "bag.fill")
        #expect(KitchenLogic.icon(forName: nil).symbol == "bag.fill")
        #expect(KitchenLogic.icon(forName: "   ").symbol == "bag.fill")
    }

    // MARK: - Keyword → category seam (22-01, ICON-02)
    //
    // The three tests above are the NON-REGRESSION proof that routing the keyword table through
    // PantryCategory changed no shipped tile — they must keep passing unedited. The tests below
    // pin the new seam that 22-02's cache and 22-03's model resolver build on.

    @Test("Keyword matching yields the category behind each mockup item")
    func keywordCategoryResolvesMockupItems() {
        #expect(KitchenLogic.keywordCategory(forName: "Milk") == .dairy)
        #expect(KitchenLogic.keywordCategory(forName: "Eggs") == .eggs)
        #expect(KitchenLogic.keywordCategory(forName: "Sona Masoori rice") == .grainStaple)
        #expect(KitchenLogic.keywordCategory(forName: "Filter coffee") == .brew)
        #expect(KitchenLogic.keywordCategory(forName: "Cooking oil") == .oilFat)
        #expect(KitchenLogic.keywordCategory(forName: "Onions") == .produce)
        #expect(KitchenLogic.keywordCategory(forName: "Dishwash liquid") == .cleaning)
    }

    @Test("Spices render a different tile from staples (spice separated 2026-07-22)")
    func keywordCategorySeparatesSpiceFromStaple() {
        #expect(KitchenLogic.keywordCategory(forName: "Garam masala") == .spice)
        #expect(KitchenLogic.keywordCategory(forName: "Toor dal") == .grainStaple)
        // spice was given its own glyph at the user's request — the two tiles now differ, which is
        // the whole point of the change (they used to be the identical amber box).
        #expect(KitchenLogic.icon(forName: "Garam masala").symbol == "flame.fill")
        #expect(KitchenLogic.icon(forName: "Toor dal").symbol == "shippingbox.fill")
        #expect(KitchenLogic.icon(forName: "Garam masala").symbol
                != KitchenLogic.icon(forName: "Toor dal").symbol)
    }

    @Test("No keyword match means nil — 'no opinion', distinct from a confident .other")
    func keywordCategoryReturnsNilWhenItHasNoOpinion() {
        #expect(KitchenLogic.keywordCategory(forName: "Zqx widget") == nil)
        #expect(KitchenLogic.keywordCategory(forName: "") == nil)
        #expect(KitchenLogic.keywordCategory(forName: "   ") == nil)
        #expect(KitchenLogic.keywordCategory(forName: nil) == nil)
    }

    @Test("Keyword categorisation is case-insensitive and whitespace-trimmed")
    func keywordCategoryIsCaseInsensitive() {
        #expect(KitchenLogic.keywordCategory(forName: "  ATTA  ") == .grainStaple)
        #expect(KitchenLogic.keywordCategory(forName: "toor DAL") == .grainStaple)
    }

    @Test("normalizedIconKey is the one normalisation rule (22-02 caches on it)")
    func normalizedIconKeyTrimsAndLowercases() {
        #expect(KitchenLogic.normalizedIconKey(forName: "  Sona Masoori RICE ") == "sona masoori rice")
        #expect(KitchenLogic.normalizedIconKey(forName: "Milk") == "milk")
        #expect(KitchenLogic.normalizedIconKey(forName: "") == nil)
        #expect(KitchenLogic.normalizedIconKey(forName: "   ") == nil)
        #expect(KitchenLogic.normalizedIconKey(forName: nil) == nil)
    }
}
