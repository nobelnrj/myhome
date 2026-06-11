import Testing
import SwiftData
import Foundation
@testable import MyHome

/// V5→V6 migration fixture tests — proves lossless backfill and idempotency (ACCT-08).
///
/// RED gate (plan 09-01 Task 1): this file intentionally does not compile until
/// SchemaV6, Account, and Asset are introduced in Task 2/3. Do NOT make this green
/// by adding V6 stubs — the green gate is Task 3 (flip all typealiases + add v5ToV6 stage).
///
/// BLOCKING: Both tests must pass before any Wave 2 plan (Accounts CRUD, attribution
/// surfaces, routine reset) is executed.
@MainActor
struct SchemaV6MigrationTests {

    // MARK: - Lossless backfill test

    @Test("V5→V6: expenses with sourceLabel backfilled with accountID; sourceAccount unchanged (ACCT-08)")
    func v5StoreBackfillsAccountID() throws {
        let seedURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("v5seed-\(UUID()).store")
        let migrateURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("v5tov6-\(UUID()).store")
        defer {
            try? FileManager.default.removeItem(at: seedURL)
            try? FileManager.default.removeItem(at: migrateURL)
        }

        // 1. Build a V5 store and seed three expenses with distinct behaviour:
        //    e1 — HDFC CC (credit card keyword → typeRaw "credit_card")
        //    e2 — ICICI Savings (no credit keyword → typeRaw "savings")
        //    e3 — nil sourceLabel → must remain Unassigned (accountID == nil) after migration
        try {
            let v5Schema = Schema(versionedSchema: SchemaV5.self)
            let config = ModelConfiguration(schema: v5Schema, url: seedURL)
            let container = try ModelContainer(
                for: v5Schema,
                migrationPlan: MigrationTestsPlanV5.self,   // trimmed plan — stops at V5
                configurations: [config]
            )
            let ctx = container.mainContext

            let e1 = SchemaV5.Expense(amount: Decimal(100))
            e1.sourceLabel = "HDFC CC"
            e1.sourceAccount = "user@gmail.com"
            ctx.insert(e1)

            let e2 = SchemaV5.Expense(amount: Decimal(50))
            e2.sourceLabel = "ICICI Savings"
            e2.sourceAccount = "user@gmail.com"
            ctx.insert(e2)

            let e3 = SchemaV5.Expense(amount: Decimal(25))
            // e3: no sourceLabel — must remain Unassigned after migration
            ctx.insert(e3)

            try ctx.save()
            try ctx.save()  // second save flushes the WAL to the main store file (mirror MigrationTests.swift line 136)
        }()

        // 2. Copy the seed store to a fresh URL before opening under V6
        //    (avoids container lock contention — mirror MigrationTests.swift line 140)
        try FileManager.default.copyItem(at: seedURL, to: migrateURL)

        // 3. Migrate to V6 using the production AppMigrationPlan
        let v6Schema = Schema(versionedSchema: SchemaV7.self)
        let migrateConfig = ModelConfiguration(schema: v6Schema, url: migrateURL)
        let container = try ModelContainer(
            for: v6Schema,
            migrationPlan: AppMigrationPlan.self,
            configurations: [migrateConfig]
        )
        let ctx = container.mainContext

        // 4. Assert exactly 2 Account rows were auto-created (HDFC CC + ICICI Savings)
        let accounts = try ctx.fetch(FetchDescriptor<Account>())
        #expect(accounts.count == 2, "V5→V6 migration must create exactly 2 accounts (HDFC CC, ICICI Savings)")

        // 5. Locate migrated expenses and their expected accounts
        let expenses = try ctx.fetch(FetchDescriptor<Expense>())
        let hdfcAccount = accounts.first { $0.sourceLabel == "HDFC CC" }
        let icicAccount = accounts.first { $0.sourceLabel == "ICICI Savings" }

        let e1Migrated = expenses.first { $0.amount == Decimal(100) }
        let e2Migrated = expenses.first { $0.amount == Decimal(50) }
        let e3Migrated = expenses.first { $0.amount == Decimal(25) }

        // 6. Assert e1 is attributed to HDFC account (D-01)
        #expect(e1Migrated?.accountID == hdfcAccount?.id,
                "HDFC CC expense must be attributed to the HDFC account (D-01)")

        // 7. Assert sourceAccount is RETAINED unchanged (ACCT-08 — Gmail dedup key must not be touched)
        #expect(e1Migrated?.sourceAccount == "user@gmail.com",
                "sourceAccount must be retained byte-for-byte unchanged through migration (ACCT-08)")

        // 8. Assert e2 is attributed to ICICI account
        #expect(e2Migrated?.accountID == icicAccount?.id,
                "ICICI Savings expense must be attributed to the ICICI account (D-01)")

        // 9. Assert e3 (nil sourceLabel) remains Unassigned
        #expect(e3Migrated?.accountID == nil,
                "Nil-sourceLabel expense must remain Unassigned (accountID == nil) after migration (D-01)")

        // 10. Assert account type inference (D-03)
        #expect(hdfcAccount?.typeRaw == "credit_card",
                "D-03: sourceLabel containing 'CC' must infer typeRaw = 'credit_card'")
        #expect(icicAccount?.typeRaw == "savings",
                "D-03: sourceLabel with no credit keyword must infer typeRaw = 'savings'")
    }

    // MARK: - Idempotency test

    @Test("V5→V6 migration is idempotent — re-running does not duplicate Account rows")
    func v5MigrationIsIdempotent() throws {
        let seedURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("v5seed-idem-\(UUID()).store")
        let migrateURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("v5tov6-idem-\(UUID()).store")
        defer {
            try? FileManager.default.removeItem(at: seedURL)
            try? FileManager.default.removeItem(at: migrateURL)
        }

        // 1. Seed the same V5 store as the first test
        try {
            let v5Schema = Schema(versionedSchema: SchemaV5.self)
            let config = ModelConfiguration(schema: v5Schema, url: seedURL)
            let container = try ModelContainer(
                for: v5Schema,
                migrationPlan: MigrationTestsPlanV5.self,
                configurations: [config]
            )
            let ctx = container.mainContext

            let e1 = SchemaV5.Expense(amount: Decimal(100))
            e1.sourceLabel = "HDFC CC"
            e1.sourceAccount = "user@gmail.com"
            ctx.insert(e1)

            let e2 = SchemaV5.Expense(amount: Decimal(50))
            e2.sourceLabel = "ICICI Savings"
            e2.sourceAccount = "user@gmail.com"
            ctx.insert(e2)

            try ctx.save()
            try ctx.save()  // flush WAL
        }()

        try FileManager.default.copyItem(at: seedURL, to: migrateURL)

        // 2. First migration open — runs v5ToV6 didMigrate backfill
        let v6Schema = Schema(versionedSchema: SchemaV7.self)
        let config1 = ModelConfiguration(schema: v6Schema, url: migrateURL)
        let container1 = try ModelContainer(
            for: v6Schema,
            migrationPlan: AppMigrationPlan.self,
            configurations: [config1]
        )
        let ctx1 = container1.mainContext

        // Verify first migration produced the expected 2 accounts
        let accountsAfterFirst = try ctx1.fetch(FetchDescriptor<Account>())
        #expect(accountsAfterFirst.count == 2, "First migration must create exactly 2 accounts")

        // Find the HDFC account ID from the first migration (to check it is the same after second open)
        let hdfcAfterFirst = accountsAfterFirst.first { $0.sourceLabel == "HDFC CC" }
        let hdfcIDAfterFirst = hdfcAfterFirst?.id

        // 3. Close the container by letting it go out of scope (container1 released at end of block)
        // then re-open the same store URL under AppMigrationPlan again
        let config2 = ModelConfiguration(schema: v6Schema, url: migrateURL)
        let container2 = try ModelContainer(
            for: v6Schema,
            migrationPlan: AppMigrationPlan.self,
            configurations: [config2]
        )
        let ctx2 = container2.mainContext

        // 4. After the second open: still exactly 2 Account rows — no duplicates (D-02 idempotency)
        let accountsAfterSecond = try ctx2.fetch(FetchDescriptor<Account>())
        #expect(accountsAfterSecond.count == 2,
                "Re-opening the V6 store must not duplicate Account rows (idempotent backfill — D-02)")

        // 5. e1 still points to a single HDFC account (no duplicated attribution)
        let expensesAfterSecond = try ctx2.fetch(FetchDescriptor<Expense>())
        let e1AfterSecond = expensesAfterSecond.first { $0.amount == Decimal(100) }
        let hdfcAfterSecond = accountsAfterSecond.first { $0.sourceLabel == "HDFC CC" }

        #expect(e1AfterSecond?.accountID == hdfcAfterSecond?.id,
                "HDFC CC expense must still point at a single HDFC account after second open")
        #expect(hdfcAfterSecond?.id == hdfcIDAfterFirst,
                "HDFC account UUID must be stable across re-opens (no duplicate created)")
    }
}

// ---------------------------------------------------------------------------
// MigrationTestsPlanV5 — trimmed migration plan stopping at SchemaV5.
//
// Mirrors MigrationTestsPlanV3 (MigrationTests.swift lines 255–270) exactly.
// Used to seed genuine V5 stores in tests without triggering the V6 migration.
// ---------------------------------------------------------------------------
enum MigrationTestsPlanV5: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [SchemaV1.self, SchemaV2.self, SchemaV3.self, SchemaV4.self, SchemaV5.self]
    }
    static var stages: [MigrationStage] {
        [v1ToV2, v2ToV3, v3ToV4, v4ToV5]
    }
    static let v1ToV2 = MigrationStage.custom(
        fromVersion: SchemaV1.self, toVersion: SchemaV2.self, willMigrate: nil, didMigrate: nil)
    static let v2ToV3 = MigrationStage.custom(
        fromVersion: SchemaV2.self, toVersion: SchemaV3.self, willMigrate: nil, didMigrate: nil)
    static let v3ToV4 = MigrationStage.custom(
        fromVersion: SchemaV3.self, toVersion: SchemaV4.self, willMigrate: nil, didMigrate: nil)
    static let v4ToV5 = MigrationStage.custom(
        fromVersion: SchemaV4.self, toVersion: SchemaV5.self, willMigrate: nil, didMigrate: nil)
}
