import Testing
import SwiftData
import Foundation
@testable import MyHome

/// Migration-load tests: verify that prior-version stores open cleanly under AppMigrationPlan
/// and that seeded data survives each migration hop.
///
/// FND-05 gate — exercises the full ModelContainer + AppMigrationPlan init path against
/// real on-disk stores so migrations cannot fail silently (PITFALLS.md Pitfall 7).
///
/// Updated in plan 07-02: existing V1/V2 tests now use AppMigrationPlan + SchemaV4 (the live
/// schema after the typealias flip). The temporary MigrationTestsPlanV3 workaround introduced
/// in plan 07-01 is no longer needed and has been removed.
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

        // 3. Open with the full migration plan targeting SchemaV6 (live schema post Phase 9).
        //    V1 → V2 → V3 → V4 → V5 → V6 chain via AppMigrationPlan.
        //    If migration fails, ModelContainer.init throws — the test fails with a clear error.
        let schema = Schema(versionedSchema: SchemaV8.self)
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

    // MARK: - V2 → V3 → V4 migration

    /// Validation command: -only-testing:MyHomeTests/MigrationTests/v2StoreMigratesToV3
    /// Requirement: Migration — V2→V3→V4 store opens under AppMigrationPlan; Expense rows survive.
    @Test("v2 store loads and Expense rows survive under AppMigrationPlan (V2→V3→V4)")
    func v2StoreMigratesToV3() throws {
        // 1. Locate the bundled v2 seed store.
        let testBundle = Bundle(for: MigrationTestsClass.self)
        guard let bundledStoreURL = testBundle.url(forResource: "MyHomeV2Seed", withExtension: "store") else {
            Issue.record("Bundled v2 seed store not found — MyHomeV2Seed.store must be in the MyHomeTests target's Copy Bundle Resources build phase")
            return
        }

        // 2. Copy to a unique temp location so the test never modifies the bundle resource.
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("migration-v2v3-test-\(UUID()).store")
        defer { try? FileManager.default.removeItem(at: tempURL) }

        try FileManager.default.copyItem(at: bundledStoreURL, to: tempURL)

        // 3. Open with the full migration plan targeting SchemaV6 (V2 → V3 → V4 → V5 → V6 via AppMigrationPlan).
        let schema = Schema(versionedSchema: SchemaV8.self)
        let config = ModelConfiguration(schema: schema, url: tempURL)
        let container = try ModelContainer(
            for: schema,
            migrationPlan: AppMigrationPlan.self,
            configurations: [config]
        )

        // 4. Verify the seeded expense is readable (store was pre-seeded with one Expense row).
        let context = container.mainContext
        let expenses = try context.fetch(FetchDescriptor<Expense>())
        #expect(!expenses.isEmpty, "At least one Expense must survive the V2→V3→V4→V5→V6 migration (T-03-02)")

        // 5. Verify the seeded data is intact (generator seeded amount=100, note="Seed").
        let seedExpense = expenses.first
        #expect(seedExpense?.amount == Decimal(100), "Seed expense amount must be 100 after migration")
        #expect(seedExpense?.note == "Seed", "Seed expense note must be 'Seed' after migration")
        #expect(seedExpense?.currencyCode == "INR", "Seed expense currencyCode must be 'INR' after migration")
    }

    // MARK: - V3 → V4 migration

    /// Validates that a V3-schema store migrates to V5 via AppMigrationPlan, with all new
    /// fields defaulting to nil (T-07-04 + D-MA-03 / additive-only migration gate).
    ///
    /// The test constructs a V3 store in-memory, seeds one Expense, writes it to a temp
    /// file, then re-opens it under AppMigrationPlan + SchemaV5 to exercise the v3ToV4→v4ToV5 stages.
    @Test("v3 store migrates to V5; ingestion fields and sourceAccount default to nil (T-07-04, D-MA-03)")
    func v3StoreMigratesToV4() throws {
        let seedURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("migration-v3seed-\(UUID()).store")
        let migrateURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("migration-v3tov5-\(UUID()).store")
        defer {
            try? FileManager.default.removeItem(at: seedURL)
            try? FileManager.default.removeItem(at: migrateURL)
        }

        // 1. Build a V3 store and seed one Expense row.
        //    Scope the container in a do-block so it is fully released (and WAL checkpointed)
        //    before we copy the file.
        try {
            let v3Schema = Schema(versionedSchema: SchemaV3.self)
            let seedConfig = ModelConfiguration(schema: v3Schema, url: seedURL)
            let seedContainer = try ModelContainer(
                for: v3Schema,
                migrationPlan: MigrationTestsPlanV3.self,  // stops at V3
                configurations: [seedConfig]
            )
            let seedContext = seedContainer.mainContext
            let expense = SchemaV3.Expense(amount: Decimal(250), note: "V3SeedRow")
            seedContext.insert(expense)
            try seedContext.save()
            // Explicit flush — ensures WAL is written to the main store file.
            try seedContext.save()
        }()

        // 2. Copy the seed file to a second temp URL (no container lock contention).
        try FileManager.default.copyItem(at: seedURL, to: migrateURL)

        // 3. Re-open under AppMigrationPlan targeting SchemaV6 — triggers v3ToV4 + v4ToV5 + v5ToV6 stages.
        let v6Schema = Schema(versionedSchema: SchemaV8.self)
        let migrateConfig = ModelConfiguration(schema: v6Schema, url: migrateURL)
        let migratedContainer = try ModelContainer(
            for: v6Schema,
            migrationPlan: AppMigrationPlan.self,
            configurations: [migrateConfig]
        )

        // 4. Assert the row survived migration.
        let ctx = migratedContainer.mainContext
        let expenses = try ctx.fetch(FetchDescriptor<Expense>())
        #expect(!expenses.isEmpty, "Expense row must survive V3→V4→V5→V6 migration (T-07-04)")

        // 5. Verify original fields are intact.
        let migratedExpense = expenses.first
        #expect(migratedExpense?.amount == Decimal(250), "amount must be preserved across V3→V5 migration")
        #expect(migratedExpense?.note == "V3SeedRow", "note must be preserved across V3→V5 migration")
        #expect(migratedExpense?.currencyCode == "INR", "currencyCode must be preserved across V3→V5 migration")

        // 6. Assert all new V4 ingestion fields default to nil (additive migration, T-07-04).
        #expect(migratedExpense?.rawEmailBody == nil, "rawEmailBody must be nil after V3→V5 migration")
        #expect(migratedExpense?.parserID == nil, "parserID must be nil after V3→V5 migration")
        #expect(migratedExpense?.parserVersion == nil, "parserVersion must be nil after V3→V5 migration")
        #expect(migratedExpense?.sourceLabel == nil, "sourceLabel must be nil after V3→V5 migration")
        #expect(migratedExpense?.gmailMessageID == nil, "gmailMessageID must be nil after V3→V5 migration")
        #expect(migratedExpense?.ingestionStateRaw == nil, "ingestionStateRaw must be nil after V3→V5 migration")
        #expect(migratedExpense?.parseConfidence == nil, "parseConfidence must be nil after V3→V5 migration")

        // 7. Assert V5 sourceAccount field defaults to nil (additive migration, D-MA-03).
        #expect(migratedExpense?.sourceAccount == nil, "sourceAccount must be nil after V3→V5 migration (D-MA-03)")
    }

    // MARK: - V4 → V5 migration with NOTE data (STAB-08 / real-device upgrade path)

    /// STAB-08 — proves an existing V4 store that already contains notes (the real on-device
    /// situation: a phone running shipped v1.0/V4 with notes) upgrades to V5 WITHOUT data loss
    /// and WITHOUT the notes-save crash. Mirrors the production path exactly:
    /// `Schema(versionedSchema: SchemaV8.self)` + `AppMigrationPlan`.
    ///
    /// Before the typealias fix, the app wrote/read `SchemaV4.Note` under a V5 container and
    /// crashed. This test seeds a genuine V4 store with a note + block, migrates it to V5, and
    /// asserts (a) the old note survives and is readable as the app's `Note`, and (b) a brand-new
    /// note saves cleanly on the migrated store.
    @Test("v4 store WITH notes migrates to V5; old notes survive and new notes save (STAB-08)")
    func v4StoreWithNotesMigratesToV5() throws {
        let seedURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("migration-v4noteseed-\(UUID()).store")
        let migrateURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("migration-v4tov5-note-\(UUID()).store")
        defer {
            try? FileManager.default.removeItem(at: seedURL)
            try? FileManager.default.removeItem(at: migrateURL)
        }

        // 1. Build a genuine V4 store (canonical V4 schema, no plan) and seed one Note + NoteBlock.
        try {
            let v4Schema = Schema(versionedSchema: SchemaV4.self)
            let seedConfig = ModelConfiguration(schema: v4Schema, url: seedURL)
            let seedContainer = try ModelContainer(for: v4Schema, configurations: [seedConfig])
            let ctx = seedContainer.mainContext
            let note = SchemaV4.Note(title: "OldPhoneNote")
            ctx.insert(note)
            let block = SchemaV4.NoteBlock(kindRaw: "checkbox", text: "old task", order: 0)
            ctx.insert(block)
            block.note = note
            try ctx.save()
            try ctx.save()  // flush WAL to the main store file
        }()

        // 2. Copy the V4 seed to a second URL (avoids container lock contention).
        try FileManager.default.copyItem(at: seedURL, to: migrateURL)

        // 3. Re-open EXACTLY like appContainer(): versionedSchema V6 + AppMigrationPlan (runs v4ToV5 + v5ToV6).
        let v6Schema = Schema(versionedSchema: SchemaV8.self)
        let migrateConfig = ModelConfiguration(schema: v6Schema, url: migrateURL)
        let container = try ModelContainer(
            for: v6Schema,
            migrationPlan: AppMigrationPlan.self,
            configurations: [migrateConfig]
        )
        let ctx = container.mainContext

        // 4. The pre-existing note survived migration and reads back as the app's Note (V5).
        let migrated = try ctx.fetch(FetchDescriptor<Note>())
        #expect(migrated.count == 1, "STAB-08: the pre-existing V4 note must survive the V4→V5 upgrade")
        #expect(migrated.first?.title == "OldPhoneNote", "STAB-08: migrated note title must be preserved")

        // 5. A brand-new note saves cleanly on the migrated store (the path that crashed pre-fix).
        let newNote = Note(title: "AddedAfterUpgrade")
        ctx.insert(newNote)
        try ctx.save()
        #expect(try ctx.fetch(FetchDescriptor<Note>()).count == 2,
                "STAB-08: adding a note after upgrade must not crash and must persist")
    }
}

// ---------------------------------------------------------------------------
// Bundle accessor helper
// ---------------------------------------------------------------------------

/// A concrete class used solely to obtain the test bundle via Bundle(for:).
/// Swift Testing runs test structs without a class context; using a dedicated
/// class here is the reliable cross-platform pattern (Assumption A5).
private final class MigrationTestsClass {}

// ---------------------------------------------------------------------------
// MigrationTestsPlanV3 — trimmed migration plan stopping at SchemaV3.
//
// Kept for use in v3StoreMigratesToV4 to seed a valid V3 store before
// exercising the V3→V4 migration stage. Not used for V1/V2 tests (they
// use AppMigrationPlan + SchemaV4 directly, per plan 07-02 flip).
// ---------------------------------------------------------------------------
enum MigrationTestsPlanV3: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [SchemaV1.self, SchemaV2.self, SchemaV3.self]
    }
    static var stages: [MigrationStage] {
        [v1ToV2, v2ToV3]
    }
    static let v1ToV2 = MigrationStage.custom(
        fromVersion: SchemaV1.self, toVersion: SchemaV2.self,
        willMigrate: nil, didMigrate: nil
    )
    static let v2ToV3 = MigrationStage.custom(
        fromVersion: SchemaV2.self, toVersion: SchemaV3.self,
        willMigrate: nil, didMigrate: nil
    )
}
