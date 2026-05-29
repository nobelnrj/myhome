import Testing
import SwiftData
import Foundation
@testable import MyHome

/// Migration-load test: verifies that the bundled v1 SQLite store opens cleanly
/// under AppMigrationPlan and that the seeded expense survives the load.
///
/// This is the FND-05 gate — it exercises the full ModelContainer + AppMigrationPlan
/// init path against a real on-disk v1 store, so Phase 2's first additive migration
/// cannot fail silently (PITFALLS.md Pitfall 7).
@MainActor
struct MigrationTests {

    @Test("v1 store loads successfully under AppMigrationPlan")
    func v1StoreMigratesCleanly() throws {
        // 1. Locate the bundled v1 seed store in the test bundle.
        //    Bundle(for:) works in the Swift Testing + hosted test bundle context (A5).
        //    The store was seeded with one Expense(amount: 100, note: "Seed").
        let testBundle = Bundle(for: MigrationTestsClass.self)
        guard let bundledStoreURL = testBundle.url(forResource: "MyHomeV1Seed", withExtension: "store") else {
            // Seed store missing — this is an explicit FAILURE, not a skip.
            // The FND-05 gate requires the store to be present and loadable.
            Issue.record("Bundled v1 seed store not found — MyHomeV1Seed.store must be in the MyHomeTests target's Copy Bundle Resources build phase")
            return
        }

        // 2. Copy to a unique temp location so the test never modifies the bundle resource.
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("migration-test-\(UUID()).store")
        defer { try? FileManager.default.removeItem(at: tempURL) }

        try FileManager.default.copyItem(at: bundledStoreURL, to: tempURL)

        // 3. Open with the migration plan.
        //    If migration fails, ModelContainer.init throws — the test fails with a clear error.
        //    Schema target is SchemaV2 so AppMigrationPlan drives the V1→V2 migration.
        let schema = Schema(versionedSchema: SchemaV2.self)
        let config = ModelConfiguration(schema: schema, url: tempURL)
        let container = try ModelContainer(
            for: schema,
            migrationPlan: AppMigrationPlan.self,
            configurations: [config]
        )

        // 4. Verify the seeded expense is readable (store was pre-seeded with one row).
        let context = container.mainContext
        let expenses = try context.fetch(FetchDescriptor<Expense>())
        #expect(!expenses.isEmpty, "At least one expense must survive the v1 store load (FND-05)")

        // 5. Verify the seeded data is intact.
        let seedExpense = expenses.first
        #expect(seedExpense?.amount == Decimal(100), "Seed expense amount must be 100")
        #expect(seedExpense?.note == "Seed", "Seed expense note must be 'Seed'")
        #expect(seedExpense?.currencyCode == "INR", "Seed expense currencyCode must be 'INR'")
    }
}

// ---------------------------------------------------------------------------
// Bundle accessor helper
// ---------------------------------------------------------------------------

/// A concrete class used solely to obtain the test bundle via Bundle(for:).
/// Swift Testing runs test structs without a class context; using a dedicated
/// class here is the reliable cross-platform pattern (Assumption A5).
private final class MigrationTestsClass {}
