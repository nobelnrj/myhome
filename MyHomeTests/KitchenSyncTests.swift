import Testing
import SwiftData
import Foundation
@testable import MyHome

// Requirements: KTCH-04 — kitchen data flows through the Phase 18 sync engine.
// Validation: xcodebuild test -scheme MyHome -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:MyHomeTests/KitchenSyncTests

/// KitchenSyncTests — proves PantryItem / ShoppingListItem get the SAME guarantees as every
/// other synced entity: no duplicates on re-import, convergence when both phones create the
/// same staple independently, clean refusal of a snapshot from a phone still on schema v10,
/// no resurrection of deleted rows, and last-writer-wins on concurrent edits.
///
/// Everything runs on fresh in-memory SchemaV11 containers — no device, no App-Group store.
///
/// Double comparisons use plain `==` because every value asserted here (0.0, 1.0, 2.0, 5.0,
/// 7.0) is exactly representable in binary floating point. Kitchen quantities are measurements,
/// never money; no `Decimal` appears anywhere in this file by design.
@MainActor
struct KitchenSyncTests {

    // MARK: - Fixtures

    private static func makeStore() throws -> ModelContainer {
        let schema = Schema(versionedSchema: SchemaV11.self)
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [config])
    }

    /// Seeds the kitchen fixture on `ctx`: 2 pantry items (one in stock, one out) and one
    /// manual shopping-list row.
    private static func seedKitchen(_ ctx: ModelContext) throws {
        let rice = PantryItem(
            name: "Rice", quantity: 2.0, unit: "kg", lowStockThreshold: 1.0, restockQuantity: 5.0
        )
        ctx.insert(rice)
        let milk = PantryItem(name: "Milk", quantity: 0.0, unit: "L", lowStockThreshold: 1.0)
        ctx.insert(milk)
        let sponges = ShoppingListItem(name: "Sponges", quantity: 1.0)
        ctx.insert(sponges)
        try ctx.save()
    }

    private static func pantry(_ ctx: ModelContext) throws -> [PantryItem] {
        try ctx.fetch(FetchDescriptor<PantryItem>())
    }

    private static func shopping(_ ctx: ModelContext) throws -> [ShoppingListItem] {
        try ctx.fetch(FetchDescriptor<ShoppingListItem>())
    }

    // MARK: - Round-trip

    @Test("Kitchen survives export A → merge into empty B with identical values and syncIDs")
    func kitchenRoundTrip() throws {
        let a = try Self.makeStore()
        try Self.seedKitchen(a.mainContext)

        let snap = try SnapshotExporter.makeSnapshot(context: a.mainContext, deviceName: "A")

        let b = try Self.makeStore()
        _ = try SnapshotImporter.merge(snap, into: b.mainContext)

        let bPantry = try Self.pantry(b.mainContext).sorted { ($0.name ?? "") < ($1.name ?? "") }
        #expect(bPantry.count == 2)

        let milk = try #require(bPantry.first { $0.name == "Milk" })
        #expect(milk.quantity == 0.0)
        #expect(milk.lowStockThreshold == 1.0)
        #expect(milk.unit == "L")

        let rice = try #require(bPantry.first { $0.name == "Rice" })
        #expect(rice.quantity == 2.0)
        #expect(rice.lowStockThreshold == 1.0)
        #expect(rice.restockQuantity == 5.0)
        #expect(rice.unit == "kg")

        // Identity is preserved across the wire — same syncIDs on both phones.
        let aSyncIDs = Set(try Self.pantry(a.mainContext).map(\.syncID))
        #expect(Set(bPantry.map(\.syncID)) == aSyncIDs)

        let bShopping = try Self.shopping(b.mainContext)
        #expect(bShopping.count == 1)
        #expect(bShopping.first?.name == "Sponges")
        #expect(bShopping.first?.quantity == 1.0)
        #expect(bShopping.first?.isChecked == false)
        #expect(bShopping.first?.syncID == (try Self.shopping(a.mainContext).first?.syncID))
    }

    @Test("Re-importing the same kitchen snapshot inserts nothing and creates no duplicates")
    func reImportIsIdempotent() throws {
        let a = try Self.makeStore()
        try Self.seedKitchen(a.mainContext)
        let snap = try SnapshotExporter.makeSnapshot(context: a.mainContext, deviceName: "A")

        let b = try Self.makeStore()
        _ = try SnapshotImporter.merge(snap, into: b.mainContext)

        let pantryBefore = try Self.pantry(b.mainContext).count
        let shoppingBefore = try Self.shopping(b.mainContext).count

        let stats = try SnapshotImporter.merge(snap, into: b.mainContext)

        #expect(stats.inserted == 0)
        #expect(stats.adopted == 0)
        #expect(stats.deleted == 0)
        #expect(try Self.pantry(b.mainContext).count == pantryBefore)
        #expect(try Self.shopping(b.mainContext).count == shoppingBefore)
    }

    // MARK: - Identity adoption (both phones added the same staple before their first sync)

    @Test("Two phones independently adding the same pantry item converge to ONE row")
    func pantryAdoptionConverges() throws {
        let a = try Self.makeStore()
        let aRice = PantryItem(name: "rice", quantity: 3.0, unit: "kg")
        a.mainContext.insert(aRice)
        try a.mainContext.save()

        let b = try Self.makeStore()
        let bRice = PantryItem(name: "  Rice ", quantity: 1.0, unit: "kg")
        b.mainContext.insert(bRice)
        try b.mainContext.save()

        let aSync = aRice.syncID
        let bSync = bRice.syncID
        let expected = min(aSync.uuidString, bSync.uuidString)

        let snap = try SnapshotExporter.makeSnapshot(context: a.mainContext, deviceName: "A")
        let stats = try SnapshotImporter.merge(snap, into: b.mainContext)

        let rows = try Self.pantry(b.mainContext)
        #expect(rows.count == 1, "adoption must not leave a duplicate rice row")
        #expect(rows.first?.syncID.uuidString == expected)
        #expect(stats.adopted == 1)
    }

    @Test("Two phones independently adding the same shopping row converge to ONE row")
    func shoppingAdoptionConverges() throws {
        let a = try Self.makeStore()
        let aItem = ShoppingListItem(name: "Paper towels", quantity: 2.0)
        a.mainContext.insert(aItem)
        try a.mainContext.save()

        let b = try Self.makeStore()
        let bItem = ShoppingListItem(name: "paper towels", quantity: 1.0)
        b.mainContext.insert(bItem)
        try b.mainContext.save()

        let expected = min(aItem.syncID.uuidString, bItem.syncID.uuidString)

        let snap = try SnapshotExporter.makeSnapshot(context: a.mainContext, deviceName: "A")
        let stats = try SnapshotImporter.merge(snap, into: b.mainContext)

        let rows = try Self.shopping(b.mainContext)
        #expect(rows.count == 1)
        #expect(rows.first?.syncID.uuidString == expected)
        #expect(stats.adopted == 1)
    }

    // MARK: - Version refusal (the phone still on v10)

    @Test("A schema-v10 payload is refused and leaves the kitchen tables untouched")
    func v10PayloadRefused() throws {
        let a = try Self.makeStore()
        try Self.seedKitchen(a.mainContext)
        let data = try SnapshotExporter.exportData(context: a.mainContext, deviceName: "A")

        // Simulate the other phone still running the pre-Phase-20 build.
        var json = String(decoding: data, as: UTF8.self)
        json = json.replacingOccurrences(of: "\"schemaVersion\":11", with: "\"schemaVersion\":10")
        let stale = Data(json.utf8)

        let b = try Self.makeStore()
        let localRice = PantryItem(name: "Local rice", quantity: 4.0)
        b.mainContext.insert(localRice)
        try b.mainContext.save()

        #expect(throws: SyncError.schemaVersionMismatch(found: 10, expected: 11)) {
            _ = try SnapshotImporter.mergeData(stale, into: b.mainContext)
        }

        let rows = try Self.pantry(b.mainContext)
        #expect(rows.count == 1)
        #expect(rows.first?.name == "Local rice")
        #expect(rows.first?.quantity == 4.0)
        #expect(try Self.shopping(b.mainContext).isEmpty)
    }

    // MARK: - Tombstones

    @Test("A deleted pantry item is never resurrected by an older snapshot that still has it")
    func deletedPantryItemNeverResurrects() throws {
        let a = try Self.makeStore()
        try Self.seedKitchen(a.mainContext)
        let snap = try SnapshotExporter.makeSnapshot(context: a.mainContext, deviceName: "A")

        let b = try Self.makeStore()
        _ = try SnapshotImporter.merge(snap, into: b.mainContext)

        let rice = try #require(try Self.pantry(b.mainContext).first { $0.name == "Rice" })
        let riceSyncID = rice.syncID
        b.mainContext.deleteSynced(rice, kind: .pantryItem)
        try b.mainContext.save()
        #expect(try Self.pantry(b.mainContext).count == 1)

        // A's OLDER snapshot still contains Rice — it must NOT come back.
        let stats = try SnapshotImporter.merge(snap, into: b.mainContext)

        let after = try Self.pantry(b.mainContext)
        #expect(after.count == 1)
        #expect(after.allSatisfy { $0.name != "Rice" })
        #expect(stats.skipped >= 1)

        // The tombstone travels onward with the right kind, so A deletes it too.
        let bSnap = try SnapshotExporter.makeSnapshot(context: b.mainContext, deviceName: "B")
        #expect(bSnap.deletions.contains {
            $0.entitySyncID == riceSyncID
                && $0.entityKindRaw == SyncEntityKind.pantryItem.rawValue
        })
    }

    @Test("A deleted shopping row is never resurrected and tombstones with the right kind")
    func deletedShoppingRowNeverResurrects() throws {
        let a = try Self.makeStore()
        try Self.seedKitchen(a.mainContext)
        let snap = try SnapshotExporter.makeSnapshot(context: a.mainContext, deviceName: "A")

        let b = try Self.makeStore()
        _ = try SnapshotImporter.merge(snap, into: b.mainContext)

        let sponges = try #require(try Self.shopping(b.mainContext).first)
        let syncID = sponges.syncID
        b.mainContext.deleteSynced(sponges, kind: .shoppingListItem)
        try b.mainContext.save()

        _ = try SnapshotImporter.merge(snap, into: b.mainContext)

        #expect(try Self.shopping(b.mainContext).isEmpty)
        let bSnap = try SnapshotExporter.makeSnapshot(context: b.mainContext, deviceName: "B")
        #expect(bSnap.deletions.contains {
            $0.entitySyncID == syncID
                && $0.entityKindRaw == SyncEntityKind.shoppingListItem.rawValue
        })
    }

    // MARK: - Last-writer-wins

    @Test("Newer remote quantity overwrites the local row in place")
    func newerRemoteQuantityWins() throws {
        let (b, local, snapBuilder) = try Self.pairedPantry()
        let snap = snapBuilder(7.0, local.updatedAt.addingTimeInterval(60))

        _ = try SnapshotImporter.merge(snap, into: b.mainContext)

        let rows = try Self.pantry(b.mainContext)
        #expect(rows.count == 1, "LWW must update in place, never insert")
        #expect(rows.first?.quantity == 7.0)
    }

    @Test("Older remote quantity is skipped and the local row is kept")
    func olderRemoteQuantityLoses() throws {
        let (b, local, snapBuilder) = try Self.pairedPantry()
        let snap = snapBuilder(7.0, local.updatedAt.addingTimeInterval(-60))

        _ = try SnapshotImporter.merge(snap, into: b.mainContext)

        let rows = try Self.pantry(b.mainContext)
        #expect(rows.count == 1)
        #expect(rows.first?.quantity == 2.0)
    }

    /// A store B holding one Rice row, plus a builder producing a remote snapshot carrying the
    /// SAME syncID with a chosen quantity and updatedAt — the concurrent-edit setup for LWW.
    private static func pairedPantry() throws -> (
        ModelContainer, PantryItem, (Double, Date) -> SyncSnapshot
    ) {
        let b = try makeStore()
        let local = PantryItem(name: "Rice", quantity: 2.0, unit: "kg", lowStockThreshold: 1.0)
        b.mainContext.insert(local)
        try b.mainContext.save()

        var dto = SnapshotExporter.dto(local)
        let builder: (Double, Date) -> SyncSnapshot = { quantity, updatedAt in
            dto.quantity = quantity
            dto.updatedAt = updatedAt
            return SyncSnapshot(exportedAt: Date(), deviceName: "A", pantryItems: [dto])
        }
        return (b, local, builder)
    }

    // MARK: - Checked state

    @Test("Checked state on a shopping row syncs to the other phone")
    func checkedStateSyncs() throws {
        let a = try Self.makeStore()
        let item = ShoppingListItem(name: "Sponges", quantity: 1.0)
        a.mainContext.insert(item)
        try a.mainContext.save()

        let b = try Self.makeStore()
        _ = try SnapshotImporter.merge(
            try SnapshotExporter.makeSnapshot(context: a.mainContext, deviceName: "A"),
            into: b.mainContext
        )
        #expect(try Self.shopping(b.mainContext).first?.isChecked == false)

        // A checks it off at the shop.
        let checkedAt = Date()
        item.isChecked = true
        item.checkedAt = checkedAt
        item.touch()
        try a.mainContext.save()

        _ = try SnapshotImporter.merge(
            try SnapshotExporter.makeSnapshot(context: a.mainContext, deviceName: "A"),
            into: b.mainContext
        )

        let rows = try Self.shopping(b.mainContext)
        #expect(rows.count == 1, "checking an item must not mint a second row")
        #expect(rows.first?.isChecked == true)
        #expect(rows.first?.checkedAt != nil)
    }
}
