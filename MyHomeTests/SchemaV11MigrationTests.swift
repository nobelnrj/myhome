import Testing
import SwiftData
import Foundation
@testable import MyHome

/// `Category` is ambiguous at type-lookup in test scope — disambiguate as the repo does elsewhere.
private typealias Cat11 = MyHome.Category

/// V10→V11 migration fixture tests — proves the kitchen schema bump (Phase 20, plan 20-01) is
/// PURELY ADDITIVE and that the two new kitchen tables are live and syncable from birth.
///
/// BLOCKING (Wave 1): every later Phase 20 plan builds on PantryItem/ShoppingListItem, so this
/// suite gates them all.
///
/// What V11 changes: nothing about the 12 classes copied forward from V10 — not one field,
/// default, or @Relationship. It only adds `PantryItem` (KTCH-01) and `ShoppingListItem`
/// (KTCH-03), both carrying syncID/updatedAt from birth (KTCH-04). That is why `v10ToV11` has
/// `didMigrate: nil`: the constant-default UUID()/Date() trap that forced v9ToV10's backfill
/// only bites fields added to tables that ALREADY hold rows, and these tables start empty.
///
/// The additive claim is tested rather than asserted: the fixture records each seeded row's
/// Decimal amount, syncID and updatedAt BEFORE migrating and requires them byte-identical after.
///
/// STAB-08 guard: this suite inserts and fetches through the bare `PantryItem` and `Expense`
/// typealiases under the production AppMigrationPlan. A partial typealias flip (any file left on
/// SchemaV10 while the container runs V11) crashes there.
@MainActor
struct SchemaV11MigrationTests {

    /// Identity of a seeded row, captured pre-migration so survival is provable, not assumed.
    private struct SeededExpense {
        let note: String
        let amount: Decimal
        let syncID: UUID
        let updatedAt: Date
    }

    private struct Fixture {
        let container: ModelContainer
        let storeURL: URL
        let expenses: [SeededExpense]
        let categorySyncID: UUID
        let accountSyncID: UUID
        let tombstoneSyncID: UUID
        let cleanup: () -> Void
    }

    // MARK: - Fixture

    /// Seeds a genuine V10 store (2 Expenses, 1 Category, 1 Account, 1 DeletionLog), copies it to
    /// a fresh URL, and reopens it under the production plan at V11.
    ///
    /// Seeding uses MigrationTestsPlanV10 (trimmed, stops at V10) so the V11 migration is not
    /// triggered until the reopen. The copy avoids container lock contention on one store file.
    private func migratedV11Fixture(label: String) throws -> Fixture {
        let seedURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("v10seed-\(label)-\(UUID()).store")
        let migrateURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("v10tov11-\(label)-\(UUID()).store")
        let cleanup = {
            try? FileManager.default.removeItem(at: seedURL)
            try? FileManager.default.removeItem(at: migrateURL)
        }

        var seeded: [SeededExpense] = []
        var categorySyncID = UUID()
        var accountSyncID = UUID()
        var tombstoneSyncID = UUID()

        // 1. Build a genuine V10 store. Scoped so ARC releases the container before the copy.
        try {
            let v10Schema = Schema(versionedSchema: SchemaV10.self)
            let config = ModelConfiguration(schema: v10Schema, url: seedURL)
            let container = try ModelContainer(
                for: v10Schema,
                migrationPlan: MigrationTestsPlanV10.self,
                configurations: [config]
            )
            let ctx = container.mainContext

            // Distinct Decimal amounts — Decimal(...) typed, never a bare literal (comparison footgun).
            let lunch = SchemaV10.Expense(amount: Decimal(9500), note: "Lunch")
            let coffee = SchemaV10.Expense(amount: Decimal(2500), note: "Coffee")
            ctx.insert(lunch)
            ctx.insert(coffee)

            let category = SchemaV10.Category(name: "Food", symbolName: "fork.knife")
            ctx.insert(category)
            let account = SchemaV10.Account(name: "HDFC Savings", typeRaw: "savings")
            ctx.insert(account)
            let tombstone = SchemaV10.DeletionLog(entitySyncID: UUID(), entityKindRaw: "expense")
            ctx.insert(tombstone)

            try ctx.save()
            try ctx.save()  // second save flushes WAL to the main store file

            // Capture identity AFTER save, so what we compare is what is actually on disk.
            seeded = [lunch, coffee].map {
                SeededExpense(note: $0.note ?? "", amount: $0.amount,
                              syncID: $0.syncID, updatedAt: $0.updatedAt)
            }
            categorySyncID = category.syncID
            accountSyncID = account.syncID
            tombstoneSyncID = tombstone.entitySyncID
        }()

        // 2. Copy before opening under V11.
        try FileManager.default.copyItem(at: seedURL, to: migrateURL)

        // 3. Reopen under the production AppMigrationPlan — runs V10→V11.
        let v11Schema = Schema(versionedSchema: SchemaV11.self)
        let migrateConfig = ModelConfiguration(schema: v11Schema, url: migrateURL)
        let container = try ModelContainer(
            for: v11Schema,
            migrationPlan: AppMigrationPlan.self,
            configurations: [migrateConfig]
        )
        return Fixture(
            container: container,
            storeURL: migrateURL,
            expenses: seeded,
            categorySyncID: categorySyncID,
            accountSyncID: accountSyncID,
            tombstoneSyncID: tombstoneSyncID,
            cleanup: cleanup
        )
    }

    // MARK: - Additive proof (BLOCKING — this stage runs over real financial data)

    @Test("V10→V11: every pre-existing row survives with its amount, syncID and updatedAt unchanged")
    func existingDataSurvivesUnchanged() throws {
        let fixture = try migratedV11Fixture(label: "survives")
        defer { fixture.cleanup() }
        let ctx = fixture.container.mainContext

        let expenses = try ctx.fetch(FetchDescriptor<Expense>())
        #expect(expenses.count == 2, "Both expense rows must survive V10→V11 migration")

        for seeded in fixture.expenses {
            let migrated = expenses.first { $0.note == seeded.note }
            #expect(migrated != nil, "Expense '\(seeded.note)' must survive the migration")
            #expect(migrated?.amount == seeded.amount,
                    "Expense '\(seeded.note)' amount must be unchanged — V11 alters no copied field")
            #expect(migrated?.syncID == seeded.syncID,
                    "Expense '\(seeded.note)' syncID must be unchanged — a reassigned syncID would make every peer resync it as a new record")
            #expect(migrated?.updatedAt == seeded.updatedAt,
                    "Expense '\(seeded.note)' updatedAt must be unchanged — v10ToV11 has didMigrate: nil and must touch nothing")
        }

        let categories = try ctx.fetch(FetchDescriptor<Cat11>())
        #expect(categories.count == 1, "The category row must survive migration")
        #expect(categories.first?.syncID == fixture.categorySyncID,
                "Category syncID must survive V10→V11 unchanged")

        let accounts = try ctx.fetch(FetchDescriptor<Account>())
        #expect(accounts.count == 1, "The account row must survive migration")
        #expect(accounts.first?.syncID == fixture.accountSyncID,
                "Account syncID must survive V10→V11 unchanged")

        let tombstones = try ctx.fetch(FetchDescriptor<DeletionLog>())
        #expect(tombstones.count == 1, "The DeletionLog tombstone must survive migration")
        #expect(tombstones.first?.entitySyncID == fixture.tombstoneSyncID,
                "DeletionLog.entitySyncID must survive V10→V11 unchanged")
    }

    // MARK: - Kitchen tables live

    @Test("V10→V11: PantryItem and ShoppingListItem are queryable and empty after migration")
    func kitchenTablesExistAndAreEmpty() throws {
        let fixture = try migratedV11Fixture(label: "empty")
        defer { fixture.cleanup() }
        let ctx = fixture.container.mainContext

        // New entities with no rows — the fetch must return empty, not crash.
        #expect(try ctx.fetch(FetchDescriptor<PantryItem>()).isEmpty,
                "PantryItem must return an empty array (not crash) after V10→V11 migration")
        #expect(try ctx.fetch(FetchDescriptor<ShoppingListItem>()).isEmpty,
                "ShoppingListItem must return an empty array (not crash) after V10→V11 migration")
    }

    @Test("V10→V11: PantryItem round-trips with its quantity fields and a syncID")
    func pantryItemRoundTrips() throws {
        let fixture = try migratedV11Fixture(label: "pantry")
        defer { fixture.cleanup() }
        let ctx = fixture.container.mainContext

        // Doubles chosen to be exactly representable — no epsilon comparison needed.
        ctx.insert(PantryItem(name: "Rice", quantity: 2, unit: "kg", lowStockThreshold: 1))
        try ctx.save()

        let items = try ctx.fetch(FetchDescriptor<PantryItem>())
        #expect(items.count == 1, "An inserted PantryItem must round-trip through the V11 store")
        let rice = items.first
        #expect(rice?.name == "Rice", "PantryItem.name must round-trip unchanged")
        #expect(rice?.quantity == 2.0, "PantryItem.quantity must round-trip unchanged")
        #expect(rice?.unit == "kg", "PantryItem.unit must round-trip unchanged")
        #expect(rice?.lowStockThreshold == 1.0, "PantryItem.lowStockThreshold must round-trip unchanged")
        #expect(rice?.restockQuantity == 1.0, "PantryItem.restockQuantity must default to 1")
        #expect(rice?.syncID != nil, "PantryItem must carry a syncID from birth (KTCH-04)")
    }

    @Test("V10→V11: two PantryItems get DISTINCT syncIDs (assigned at init, not a constant default)")
    func pantryItemsGetDistinctSyncIDs() throws {
        let fixture = try migratedV11Fixture(label: "distinct")
        defer { fixture.cleanup() }
        let ctx = fixture.container.mainContext

        ctx.insert(PantryItem(name: "Rice", quantity: 2, unit: "kg"))
        ctx.insert(PantryItem(name: "Dal", quantity: 1.5, unit: "kg"))
        try ctx.save()

        let items = try ctx.fetch(FetchDescriptor<PantryItem>())
        #expect(items.count == 2, "Both pantry rows must persist")
        #expect(Set(items.map(\.syncID)).count == 2,
                "Each PantryItem must have a DISTINCT syncID — rows sharing one syncID would make the merge engine treat different staples as the same record")
    }

    @Test("V10→V11: ShoppingListItem round-trips with isChecked defaulting to false")
    func shoppingListItemRoundTrips() throws {
        let fixture = try migratedV11Fixture(label: "shopping")
        defer { fixture.cleanup() }
        let ctx = fixture.container.mainContext

        ctx.insert(ShoppingListItem(name: "Paper towels", quantity: 2, unit: "pcs"))
        try ctx.save()

        let items = try ctx.fetch(FetchDescriptor<ShoppingListItem>())
        #expect(items.count == 1, "An inserted ShoppingListItem must round-trip through the V11 store")
        let towels = items.first
        #expect(towels?.name == "Paper towels", "ShoppingListItem.name must round-trip unchanged")
        #expect(towels?.quantity == 2.0, "ShoppingListItem.quantity must round-trip unchanged")
        #expect(towels?.unit == "pcs", "ShoppingListItem.unit must round-trip unchanged")
        #expect(towels?.isChecked == false, "A new ShoppingListItem must start unchecked")
        #expect(towels?.checkedAt == nil, "checkedAt must be nil while the row is unchecked")
        #expect(towels?.syncID != nil, "ShoppingListItem must carry a syncID from birth (KTCH-04)")
    }

    // MARK: - SyncStamped conformance (KTCH-04)

    @Test("V10→V11: kitchen models are SyncStamped — touch() bumps updatedAt")
    func kitchenModelsAreSyncStamped() throws {
        let fixture = try migratedV11Fixture(label: "syncstamped")
        defer { fixture.cleanup() }
        let ctx = fixture.container.mainContext

        let rice = PantryItem(name: "Rice", quantity: 2, unit: "kg")
        let towels = ShoppingListItem(name: "Paper towels")
        ctx.insert(rice)
        ctx.insert(towels)
        try ctx.save()

        // Statically proves conformance: a non-SyncStamped model would not compile here.
        let stamped: [any SyncStamped] = [rice, towels]
        #expect(stamped.count == 2, "Both kitchen models must satisfy SyncStamped (KTCH-04)")

        let riceBefore = rice.updatedAt
        let towelsBefore = towels.updatedAt
        rice.touch()
        towels.touch()
        #expect(rice.updatedAt > riceBefore,
                "PantryItem.touch() must advance the LWW clock the merge engine compares")
        #expect(towels.updatedAt > towelsBefore,
                "ShoppingListItem.touch() must advance the LWW clock the merge engine compares")
    }

    // MARK: - STAB-08 guard

    @Test("V10→V11: bare PantryItem and Expense typealiases round-trip under the production plan (STAB-08)")
    func bareTypealiasesRoundTripUnderProductionPlan() throws {
        let fixture = try migratedV11Fixture(label: "stab08")
        defer { fixture.cleanup() }
        let ctx = fixture.container.mainContext

        // A typealias still pointing at SchemaV10 would make these entities absent from the V11
        // store schema — save()/fetch() would trap here. This is the partial-flip tripwire.
        let fresh = Expense(amount: Decimal(1250), note: "Post-migration insert")
        ctx.insert(fresh)
        ctx.insert(PantryItem(name: "Atta", quantity: 5, unit: "kg", lowStockThreshold: 0.5))
        try ctx.save()

        let inserted = try ctx.fetch(FetchDescriptor<Expense>())
            .first { $0.note == "Post-migration insert" }
        #expect(inserted != nil, "A newly inserted Expense must be fetchable via the bare typealias")
        #expect(inserted?.amount == Decimal(1250),
                "Amount must round-trip — compare against Decimal(1250), never a bare literal")

        let atta = try ctx.fetch(FetchDescriptor<PantryItem>()).first { $0.name == "Atta" }
        #expect(atta != nil, "A newly inserted PantryItem must be fetchable via the bare typealias")
        #expect(atta?.lowStockThreshold == 0.5,
                "lowStockThreshold must round-trip unchanged through the bare typealias")
    }
}

// ---------------------------------------------------------------------------
// MigrationTestsPlanV10 — trimmed migration plan stopping at SchemaV10.
//
// Mirrors MigrationTestsPlanV9 (SchemaV10MigrationTests.swift), extended by v9ToV10. Used to
// seed genuine V10 stores in tests without triggering the V11 migration.
//
// The stages are REUSED from AppMigrationPlan rather than re-declared: v9ToV10 carries a
// non-trivial syncID/updatedAt backfill, and a hand-copied divergent duplicate of it would seed
// stores that no real device could ever produce.
// ---------------------------------------------------------------------------
enum MigrationTestsPlanV10: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [SchemaV1.self, SchemaV2.self, SchemaV3.self, SchemaV4.self, SchemaV5.self,
         SchemaV6.self, SchemaV7.self, SchemaV8.self, SchemaV9.self, SchemaV10.self]
    }
    static var stages: [MigrationStage] {
        [AppMigrationPlan.v1ToV2, AppMigrationPlan.v2ToV3, AppMigrationPlan.v3ToV4,
         AppMigrationPlan.v4ToV5, AppMigrationPlan.v5ToV6, AppMigrationPlan.v6ToV7,
         AppMigrationPlan.v7ToV8, AppMigrationPlan.v8ToV9, AppMigrationPlan.v9ToV10]
    }
}
