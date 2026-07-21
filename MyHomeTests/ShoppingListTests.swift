import Testing
import SwiftData
import Foundation
@testable import MyHome

// Requirements: KTCH-03 (shopping list auto-populates from low stock; check-off restocks pantry).
// Validation: xcodebuild test -scheme MyHome -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:MyHomeTests/ShoppingListTests

/// ShoppingListTests — pins the DERIVED + MANUAL shopping design locked in 20-01.
///
/// The auto half is a pure function of `PantryItem` state (`KitchenLogic.deriveShoppingItems`) and
/// is NEVER written to the `ShoppingListItem` table (T-20-08: materialised auto rows would let two
/// phones mint duplicates the merge engine cannot reconcile). The manual half is real rows, and
/// every delete leaves a `shoppingListItem` tombstone (T-20-09).
///
/// Double comparisons only touch exactly-representable values (0, 1, 2, 3, 5, 12).
@MainActor
struct ShoppingListTests {

    // MARK: - Fixtures

    private static func makeStore() throws -> ModelContainer {
        let schema = Schema(versionedSchema: SchemaV11.self)
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [config])
    }

    /// 5 items: 2 low, 1 out, 2 stocked.
    private static func seedPantry(_ ctx: ModelContext) -> [String: PantryItem] {
        let rows: [(String, Double, Double, Double)] = [
            // (name, quantity, lowStockThreshold, restockQuantity)
            ("Milk",   0, 1, 3),    // OUT
            ("Eggs",   2, 4, 12),   // LOW
            ("Atta",   1, 1, 5),    // LOW (at threshold)
            ("Rice",   5, 1, 5),    // in stock
            ("Sugar",  3, 1, 2)     // in stock
        ]
        var made: [String: PantryItem] = [:]
        for (name, qty, threshold, restock) in rows {
            let item = PantryItem(
                name: name, quantity: qty, unit: "kg",
                lowStockThreshold: threshold, restockQuantity: restock
            )
            ctx.insert(item)
            made[name] = item
        }
        return made
    }

    // MARK: - Auto-population (KTCH-03)

    @Test("Derivation returns only low+out rows, out first, alphabetical within each group")
    func derivationOrdersOutThenLowAlphabetically() throws {
        let store = try Self.makeStore()
        let ctx = store.mainContext
        _ = Self.seedPantry(ctx)
        try ctx.save()

        let pantry = try ctx.fetch(FetchDescriptor<PantryItem>())
        let derived = KitchenLogic.deriveShoppingItems(from: pantry)

        #expect(derived.count == 3)
        #expect(derived.map { $0.name } == ["Milk", "Atta", "Eggs"])
    }

    @Test("Unnamed rows sort last within their group")
    func unnamedRowsSortLast() throws {
        let store = try Self.makeStore()
        let ctx = store.mainContext
        let ghost = PantryItem(name: "", quantity: 0, unit: nil, lowStockThreshold: 1)
        let zebra = PantryItem(name: "Zebra beans", quantity: 0, unit: "kg", lowStockThreshold: 1)
        ctx.insert(ghost)
        ctx.insert(zebra)
        try ctx.save()

        let derived = KitchenLogic.deriveShoppingItems(from: try ctx.fetch(FetchDescriptor<PantryItem>()))
        #expect(derived.map { $0.name } == ["Zebra beans", ""])
    }

    @Test("Auto-population reacts to state: dropping to the threshold adds, restocking removes")
    func derivationTracksLiveState() throws {
        let store = try Self.makeStore()
        let ctx = store.mainContext
        let items = Self.seedPantry(ctx)
        try ctx.save()
        let sugar = try #require(items["Sugar"])

        func derivedNames() throws -> [String?] {
            KitchenLogic.deriveShoppingItems(from: try ctx.fetch(FetchDescriptor<PantryItem>()))
                .map { $0.name }
        }

        #expect(try !derivedNames().contains("Sugar"))

        // 3 → 1 (its threshold) makes it LOW, so it lands on the list.
        sugar.quantity = 1
        #expect(try derivedNames().contains("Sugar"))

        // Restocking above the threshold takes it back off.
        KitchenLogic.markRestocked(sugar)   // +2 → 3
        #expect(sugar.quantity == 3.0)
        #expect(try !derivedNames().contains("Sugar"))
    }

    // MARK: - Check-off restocks the pantry (the pantry↔shopping link)

    @Test("Checking off a derived row restocks the pantry and drops it from the list")
    func checkOffRestocksAndLeavesList() throws {
        let store = try Self.makeStore()
        let ctx = store.mainContext
        let coffee = PantryItem(
            name: "Filter coffee", quantity: 0, unit: "pack",
            lowStockThreshold: 1, restockQuantity: 5
        )
        ctx.insert(coffee)
        try ctx.save()

        #expect(KitchenLogic.deriveShoppingItems(from: [coffee]).count == 1)
        let before = coffee.updatedAt

        KitchenLogic.markRestocked(coffee)
        try ctx.save()

        #expect(coffee.quantity == 5.0)
        #expect(KitchenLogic.stockStatus(for: coffee) == .inStock)
        #expect(KitchenLogic.deriveShoppingItems(from: [coffee]).isEmpty)
        #expect(coffee.updatedAt > before)   // honest LWW clock (18-04)
    }

    @Test("An insufficient restockQuantity legitimately leaves the row on the list")
    func insufficientRestockStaysListed() throws {
        let store = try Self.makeStore()
        let ctx = store.mainContext
        // Intentional, not a bug: one restock = one purchase. If restockQuantity is smaller than
        // the threshold the item is still LOW afterwards and stays on the list — the user taps
        // again or raises "Restock by" in the editor.
        let dal = PantryItem(
            name: "Toor dal", quantity: 0, unit: "kg",
            lowStockThreshold: 3, restockQuantity: 1
        )
        ctx.insert(dal)
        try ctx.save()

        KitchenLogic.markRestocked(dal)
        try ctx.save()

        #expect(dal.quantity == 1.0)
        #expect(KitchenLogic.stockStatus(for: dal) == .low)
        #expect(KitchenLogic.deriveShoppingItems(from: [dal]).map { $0.name } == ["Toor dal"])
    }

    // MARK: - Zero materialisation (T-20-08)

    @Test("Derivation and check-off never write ShoppingListItem rows")
    func derivationNeverMaterialisesRows() throws {
        let store = try Self.makeStore()
        let ctx = store.mainContext
        let items = Self.seedPantry(ctx)
        try ctx.save()

        func shoppingRowCount() throws -> Int {
            try ctx.fetchCount(FetchDescriptor<ShoppingListItem>())
        }

        #expect(try shoppingRowCount() == 0)

        let pantry = try ctx.fetch(FetchDescriptor<PantryItem>())
        let derived = KitchenLogic.deriveShoppingItems(from: pantry)
        #expect(derived.count == 3)
        try ctx.save()
        #expect(try shoppingRowCount() == 0)

        for item in derived { KitchenLogic.markRestocked(item) }
        try ctx.save()

        #expect(try shoppingRowCount() == 0)
        #expect(try #require(items["Milk"]).quantity == 3.0)
    }

    // MARK: - Manual extras lifecycle

    @Test("A manual extra round-trips through the store")
    func manualItemRoundTrips() throws {
        let store = try Self.makeStore()
        let ctx = store.mainContext
        ctx.insert(ShoppingListItem(name: "Batteries", quantity: 2, unit: "pcs"))
        try ctx.save()

        let rows = try ctx.fetch(FetchDescriptor<ShoppingListItem>())
        #expect(rows.count == 1)
        let row = try #require(rows.first)
        #expect(row.name == "Batteries")
        #expect(row.quantity == 2.0)
        #expect(row.unit == "pcs")
        #expect(row.isChecked == false)
        #expect(row.checkedAt == nil)
    }

    @Test("Toggling a manual extra sets isChecked + checkedAt and bumps the LWW clock")
    func toggleCheckedStampsState() throws {
        let store = try Self.makeStore()
        let ctx = store.mainContext
        let row = ShoppingListItem(name: "Sponges")
        ctx.insert(row)
        try ctx.save()

        let before = row.updatedAt
        KitchenLogic.toggleChecked(row)
        try ctx.save()

        #expect(row.isChecked)
        #expect(row.checkedAt != nil)
        #expect(row.updatedAt > before)

        let afterCheck = row.updatedAt
        KitchenLogic.toggleChecked(row)
        #expect(row.isChecked == false)
        #expect(row.checkedAt == nil)
        #expect(row.updatedAt > afterCheck)
    }

    @Test("Checking off a manual extra never touches the pantry")
    func manualCheckOffLeavesPantryAlone() throws {
        let store = try Self.makeStore()
        let ctx = store.mainContext
        let milk = PantryItem(name: "Milk", quantity: 0, unit: "L",
                              lowStockThreshold: 1, restockQuantity: 3)
        ctx.insert(milk)
        let extra = ShoppingListItem(name: "Aluminium foil")
        ctx.insert(extra)
        try ctx.save()

        KitchenLogic.toggleChecked(extra)
        try ctx.save()

        #expect(milk.quantity == 0)
        #expect(KitchenLogic.stockStatus(for: milk) == .out)
    }

    @Test("Clearing checked extras tombstones each deleted row as shoppingListItem")
    func clearCheckedLeavesTombstones() throws {
        let store = try Self.makeStore()
        let ctx = store.mainContext
        let bought = ShoppingListItem(name: "Batteries")
        let alsoBought = ShoppingListItem(name: "Sponges")
        let pending = ShoppingListItem(name: "Paper napkins")
        for row in [bought, alsoBought, pending] { ctx.insert(row) }
        try ctx.save()

        KitchenLogic.toggleChecked(bought)
        KitchenLogic.toggleChecked(alsoBought)
        try ctx.save()
        let boughtSyncIDs = Set([bought.syncID, alsoBought.syncID])

        for row in try ctx.fetch(FetchDescriptor<ShoppingListItem>()) where row.isChecked {
            ctx.deleteSynced(row, kind: .shoppingListItem)
        }
        try ctx.save()

        let remaining = try ctx.fetch(FetchDescriptor<ShoppingListItem>())
        #expect(remaining.map { $0.name } == ["Paper napkins"])

        let logs = try ctx.fetch(FetchDescriptor<DeletionLog>())
        #expect(logs.count == 2)
        #expect(logs.allSatisfy { $0.entityKindRaw == "shoppingListItem" })
        #expect(Set(logs.compactMap { $0.entitySyncID }) == boughtSyncIDs)
    }
}
