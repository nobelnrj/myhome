import Testing
import SwiftData
import Foundation
@testable import MyHome

/// V6→V7 migration fixture tests — proves additive migration does not corrupt data (D-03, ASSET-08).
///
/// BLOCKING: All tests in this suite must pass before any Wave 2 plan (Holdings CRUD,
/// AMFI NAV service, Overview net-worth card) is executed.
///
/// Migration is purely additive:
///   - amfiSchemeCode: String? = nil on Asset (D-01); nil after migration for all existing rows.
///   - NetWorthSnapshot: new entity; no backfill; queryable immediately after migration.
///   - No didMigrate closure — SchemaV7 stage uses .custom with nil closures (FB13812722).
@MainActor
struct SchemaV7MigrationTests {

    // MARK: - V6→V7 additive migration test (BLOCKING)

    @Test("V6→V7: existing Asset rows survive migration with amfiSchemeCode == nil")
    func v6StoreAssetAmfiSchemeCodeIsNilAfterMigration() throws {
        let seedURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("v6seed-\(UUID()).store")
        let migrateURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("v6tov7-\(UUID()).store")
        defer {
            try? FileManager.default.removeItem(at: seedURL)
            try? FileManager.default.removeItem(at: migrateURL)
        }

        // 1. Build a genuine V6 store with one Asset row and one Expense row.
        //    Use MigrationTestsPlanV6 (trimmed plan stopping at V6) so SchemaV7 migration is NOT triggered here.
        try {
            let v6Schema = Schema(versionedSchema: SchemaV6.self)
            let config = ModelConfiguration(schema: v6Schema, url: seedURL)
            let container = try ModelContainer(
                for: v6Schema,
                migrationPlan: MigrationTestsPlanV6.self,
                configurations: [config]
            )
            let ctx = container.mainContext

            let asset = SchemaV6.Asset()
            asset.name = "Aditya Birla MF"
            asset.assetClassRaw = "mutual_fund"
            asset.units = Decimal(100)
            asset.costBasisPerUnit = Decimal(string: "105.50")
            asset.currentNAV = Decimal(string: "112.25")
            ctx.insert(asset)

            let expense = SchemaV6.Expense(amount: Decimal(500), note: "Seed expense")
            ctx.insert(expense)

            try ctx.save()
            try ctx.save()  // second save flushes WAL to main store file (mirrors MigrationTests.swift pattern)
        }()

        // 2. Copy the seed store to a fresh URL before opening under V7.
        //    (avoids container lock contention — mirrors SchemaV6MigrationTests.swift pattern)
        try FileManager.default.copyItem(at: seedURL, to: migrateURL)

        // 3. Migrate to V7 using the production AppMigrationPlan (SchemaV6 → SchemaV7).
        let v7Schema = Schema(versionedSchema: SchemaV7.self)
        let migrateConfig = ModelConfiguration(schema: v7Schema, url: migrateURL)
        let container = try ModelContainer(
            for: v7Schema,
            migrationPlan: AppMigrationPlan.self,
            configurations: [migrateConfig]
        )
        let ctx = container.mainContext

        // 4. Assert the existing Asset row survived with amfiSchemeCode == nil (D-01, D-03).
        let assets = try ctx.fetch(FetchDescriptor<Asset>())
        #expect(assets.count == 1, "Exactly 1 asset row must survive V6→V7 migration")

        let migratedAsset = assets.first
        #expect(migratedAsset?.name == "Aditya Birla MF",
                "Asset name must be preserved byte-for-byte through migration")
        #expect(migratedAsset?.units == Decimal(100),
                "Asset units must be preserved through migration")
        #expect(migratedAsset?.amfiSchemeCode == nil,
                "amfiSchemeCode must be nil on existing V6 assets after V7 migration (additive, no backfill)")

        // 5. Assert existing Expense row is intact.
        let expenses = try ctx.fetch(FetchDescriptor<Expense>())
        #expect(expenses.count == 1, "Expense row must survive V6→V7 migration")
        #expect(expenses.first?.amount == Decimal(500),
                "Expense amount must be preserved through migration")
    }

    // MARK: - NetWorthSnapshot queryable after migration (BLOCKING)

    @Test("V6→V7: NetWorthSnapshot entity is queryable (FetchDescriptor returns empty, not a crash)")
    func netWorthSnapshotQueryableAfterMigration() throws {
        let seedURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("v6seed-snap-\(UUID()).store")
        let migrateURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("v6tov7-snap-\(UUID()).store")
        defer {
            try? FileManager.default.removeItem(at: seedURL)
            try? FileManager.default.removeItem(at: migrateURL)
        }

        // 1. Build a V6 store (no NetWorthSnapshot entity exists at V6).
        try {
            let v6Schema = Schema(versionedSchema: SchemaV6.self)
            let config = ModelConfiguration(schema: v6Schema, url: seedURL)
            let container = try ModelContainer(
                for: v6Schema,
                migrationPlan: MigrationTestsPlanV6.self,
                configurations: [config]
            )
            let ctx = container.mainContext
            // Insert a minimal row so the store file is non-trivial
            let expense = SchemaV6.Expense(amount: Decimal(100))
            ctx.insert(expense)
            try ctx.save()
            try ctx.save()  // flush WAL
        }()

        try FileManager.default.copyItem(at: seedURL, to: migrateURL)

        // 2. Migrate to V7 and verify the new NetWorthSnapshot entity is accessible.
        let v7Schema = Schema(versionedSchema: SchemaV7.self)
        let config = ModelConfiguration(schema: v7Schema, url: migrateURL)
        let container = try ModelContainer(
            for: v7Schema,
            migrationPlan: AppMigrationPlan.self,
            configurations: [config]
        )
        let ctx = container.mainContext

        // This FetchDescriptor MUST NOT crash. It must return an empty array — no records exist yet.
        let snapshots = try ctx.fetch(FetchDescriptor<NetWorthSnapshot>())
        #expect(snapshots.isEmpty,
                "NetWorthSnapshot must return empty array (not crash) after V6→V7 migration — new entity with no rows")
    }
}

// ---------------------------------------------------------------------------
// MigrationTestsPlanV6 — trimmed migration plan stopping at SchemaV6.
//
// Mirrors MigrationTestsPlanV5 (SchemaV6MigrationTests.swift) exactly.
// Used to seed genuine V6 stores in tests without triggering the V7 migration.
// ---------------------------------------------------------------------------
enum MigrationTestsPlanV6: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [SchemaV1.self, SchemaV2.self, SchemaV3.self, SchemaV4.self, SchemaV5.self, SchemaV6.self]
    }
    static var stages: [MigrationStage] {
        [v1ToV2, v2ToV3, v3ToV4, v4ToV5, v5ToV6]
    }
    static let v1ToV2 = MigrationStage.custom(
        fromVersion: SchemaV1.self, toVersion: SchemaV2.self, willMigrate: nil, didMigrate: nil)
    static let v2ToV3 = MigrationStage.custom(
        fromVersion: SchemaV2.self, toVersion: SchemaV3.self, willMigrate: nil, didMigrate: nil)
    static let v3ToV4 = MigrationStage.custom(
        fromVersion: SchemaV3.self, toVersion: SchemaV4.self, willMigrate: nil, didMigrate: nil)
    static let v4ToV5 = MigrationStage.custom(
        fromVersion: SchemaV4.self, toVersion: SchemaV5.self, willMigrate: nil, didMigrate: nil)
    static let v5ToV6 = MigrationStage.custom(
        fromVersion: SchemaV5.self,
        toVersion: SchemaV6.self,
        willMigrate: nil,
        didMigrate: { context in
            // Minimal idempotent backfill — mirrors AppMigrationPlan.v5ToV6
            let expenses = try context.fetch(FetchDescriptor<SchemaV6.Expense>())
            let existingAccounts = try context.fetch(FetchDescriptor<SchemaV6.Account>())
            var accountByLabel: [String: SchemaV6.Account] = [:]
            for account in existingAccounts {
                if let label = account.sourceLabel { accountByLabel[label] = account }
            }
            let labels = Set(expenses.compactMap(\.sourceLabel))
            for label in labels {
                if accountByLabel[label] == nil {
                    let typeRaw = inferAccountType(from: label)
                    let account = SchemaV6.Account(name: label, typeRaw: typeRaw, sourceLabel: label)
                    context.insert(account)
                    accountByLabel[label] = account
                }
            }
            for expense in expenses {
                guard expense.accountID == nil, let label = expense.sourceLabel else { continue }
                expense.accountID = accountByLabel[label]?.id
            }
            try context.save()
        }
    )
}
