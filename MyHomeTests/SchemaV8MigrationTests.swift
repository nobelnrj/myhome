import Testing
import SwiftData
import Foundation
@testable import MyHome

/// V7→V8 migration fixture tests — proves additive migration does not corrupt data (D-08, Phase 11.1).
///
/// BLOCKING: All tests in this suite must pass before any Wave 2 plan (SIP accrual service,
/// NPS NAV auto-refresh, SIP setup UI) is executed.
///
/// Migration is purely additive:
///   - npsSchemeCode: String? = nil on Asset (D-01, D-08); nil after migration for all existing rows.
///   - SIP, SIPAmountChange, Contribution: new entities; no backfill; queryable immediately.
///   - No didMigrate closure — SchemaV8 stage uses .custom with nil closures (FB13812722).
///
/// STAB-08 guard: this suite round-trips Note and Asset inserts under SchemaV8 to verify
/// the atomic typealias flip (Task 3) is consistent. A partial flip would crash here.
@MainActor
struct SchemaV8MigrationTests {

    // MARK: - V7→V8 additive migration test (BLOCKING)

    @Test("V7→V8: existing Asset rows survive migration with npsSchemeCode == nil")
    func v7StoreAssetNpsSchemeCodeIsNilAfterMigration() throws {
        let seedURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("v7seed-\(UUID()).store")
        let migrateURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("v7tov8-\(UUID()).store")
        defer {
            try? FileManager.default.removeItem(at: seedURL)
            try? FileManager.default.removeItem(at: migrateURL)
        }

        // 1. Build a genuine V7 store with one Asset row and one Note row.
        //    Use MigrationTestsPlanV7 (trimmed plan stopping at V7) so SchemaV8 migration is NOT triggered here.
        try {
            let v7Schema = Schema(versionedSchema: SchemaV7.self)
            let config = ModelConfiguration(schema: v7Schema, url: seedURL)
            let container = try ModelContainer(
                for: v7Schema,
                migrationPlan: MigrationTestsPlanV7.self,
                configurations: [config]
            )
            let ctx = container.mainContext

            let asset = SchemaV7.Asset()
            asset.name = "Nippon India NPS"
            asset.assetClassRaw = "nps"
            asset.units = Decimal(string: "150.5")
            asset.costBasisPerUnit = Decimal(string: "48.20")
            asset.currentNAV = Decimal(string: "49.54")
            ctx.insert(asset)

            let note = SchemaV7.Note(title: "NPS tracker")
            ctx.insert(note)

            let block = SchemaV7.NoteBlock(kindRaw: "text", text: "SIP setup on the 5th", order: 0)
            block.note = note
            ctx.insert(block)

            try ctx.save()
            try ctx.save()  // second save flushes WAL to main store file (mirrors SchemaV7MigrationTests pattern)
        }()

        // 2. Copy the seed store to a fresh URL before opening under V8.
        //    (avoids container lock contention — mirrors SchemaV7MigrationTests.swift pattern)
        try FileManager.default.copyItem(at: seedURL, to: migrateURL)

        // 3. Migrate to V8 using the production AppMigrationPlan (SchemaV7 → SchemaV8).
        let v8Schema = Schema(versionedSchema: SchemaV8.self)
        let migrateConfig = ModelConfiguration(schema: v8Schema, url: migrateURL)
        let container = try ModelContainer(
            for: v8Schema,
            migrationPlan: MigrationTestsPlanV8.self,
            configurations: [migrateConfig]
        )
        let ctx = container.mainContext

        // 4. Assert the existing Asset row survived with npsSchemeCode == nil (D-01, D-08).
        let assets = try ctx.fetch(FetchDescriptor<SchemaV8.Asset>())
        #expect(assets.count == 1, "Exactly 1 asset row must survive V7→V8 migration")

        let migratedAsset = assets.first
        #expect(migratedAsset?.name == "Nippon India NPS",
                "Asset name must be preserved byte-for-byte through migration")
        #expect(migratedAsset?.units == Decimal(string: "150.5"),
                "Asset units must be preserved through migration")
        #expect(migratedAsset?.npsSchemeCode == nil,
                "npsSchemeCode must be nil on existing V7 assets after V8 migration (additive, no backfill)")
        #expect(migratedAsset?.amfiSchemeCode == nil,
                "amfiSchemeCode must remain nil on this NPS asset (was not set in V7 seed)")

        // 5. Assert existing Note row is intact. Pinned to SchemaV8.Note explicitly:
        //    the bare `Note` typealias now points at SchemaV9 (Phase 12 flip), so this V8-fixture
        //    test references the V8 model directly to match the V8 container.
        let notes = try ctx.fetch(FetchDescriptor<SchemaV8.Note>())
        #expect(notes.count == 1, "Note row must survive V7→V8 migration")
        #expect(notes.first?.title == "NPS tracker",
                "Note title must be preserved through migration")
    }

    // MARK: - SIP, SIPAmountChange, Contribution queryable after migration (BLOCKING)

    @Test("V7→V8: SIP, SIPAmountChange, Contribution entities are queryable after migration")
    func newEntitiesQueryableAfterMigration() throws {
        let seedURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("v7seed-sip-\(UUID()).store")
        let migrateURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("v7tov8-sip-\(UUID()).store")
        defer {
            try? FileManager.default.removeItem(at: seedURL)
            try? FileManager.default.removeItem(at: migrateURL)
        }

        // 1. Build a V7 store (no SIP/Contribution entities at V7).
        try {
            let v7Schema = Schema(versionedSchema: SchemaV7.self)
            let config = ModelConfiguration(schema: v7Schema, url: seedURL)
            let container = try ModelContainer(
                for: v7Schema,
                migrationPlan: MigrationTestsPlanV7.self,
                configurations: [config]
            )
            let ctx = container.mainContext
            let asset = SchemaV7.Asset()
            asset.name = "Axis Bluechip MF"
            asset.assetClassRaw = "mutual_fund"
            ctx.insert(asset)
            try ctx.save()
            try ctx.save()  // flush WAL
        }()

        try FileManager.default.copyItem(at: seedURL, to: migrateURL)

        // 2. Migrate to V8 and verify new SIP/Contribution entities are accessible.
        let v8Schema = Schema(versionedSchema: SchemaV8.self)
        let config = ModelConfiguration(schema: v8Schema, url: migrateURL)
        let container = try ModelContainer(
            for: v8Schema,
            migrationPlan: MigrationTestsPlanV8.self,
            configurations: [config]
        )
        let ctx = container.mainContext

        // FetchDescriptors MUST NOT crash — must return empty arrays (new entities, no rows).
        let sips = try ctx.fetch(FetchDescriptor<SchemaV8.SIP>())
        #expect(sips.isEmpty, "SIP must return empty array (not crash) after V7→V8 migration")

        let changes = try ctx.fetch(FetchDescriptor<SchemaV8.SIPAmountChange>())
        #expect(changes.isEmpty, "SIPAmountChange must return empty array after V7→V8 migration")

        let contributions = try ctx.fetch(FetchDescriptor<SchemaV8.Contribution>())
        #expect(contributions.isEmpty, "Contribution must return empty array after V7→V8 migration")
    }

    // MARK: - Round-trip insert+query (STAB-08 guard)

    @Test("V7→V8: Note, Asset, SIP, Contribution can be inserted and queried in migrated store")
    func roundTripInsertQueryInMigratedStore() throws {
        let seedURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("v7seed-rt-\(UUID()).store")
        let migrateURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("v7tov8-rt-\(UUID()).store")
        defer {
            try? FileManager.default.removeItem(at: seedURL)
            try? FileManager.default.removeItem(at: migrateURL)
        }

        // 1. Seed a minimal V7 store.
        try {
            let v7Schema = Schema(versionedSchema: SchemaV7.self)
            let config = ModelConfiguration(schema: v7Schema, url: seedURL)
            let container = try ModelContainer(
                for: v7Schema,
                migrationPlan: MigrationTestsPlanV7.self,
                configurations: [config]
            )
            let ctx = container.mainContext
            let expense = SchemaV7.Expense(amount: Decimal(1000), note: "Seed")
            ctx.insert(expense)
            try ctx.save()
            try ctx.save()
        }()

        try FileManager.default.copyItem(at: seedURL, to: migrateURL)

        // 2. Open under V8 and perform round-trip inserts.
        let v8Schema = Schema(versionedSchema: SchemaV8.self)
        let config = ModelConfiguration(schema: v8Schema, url: migrateURL)
        let container = try ModelContainer(
            for: v8Schema,
            migrationPlan: MigrationTestsPlanV8.self,
            configurations: [config]
        )
        let ctx = container.mainContext

        // Note round-trip — pinned to SchemaV8.Note (bare typealias now resolves to SchemaV9 post-Phase-12)
        let note = SchemaV8.Note(title: "Post-migration note")
        ctx.insert(note)
        try ctx.save()
        let fetchedNotes = try ctx.fetch(FetchDescriptor<SchemaV8.Note>())
        #expect(fetchedNotes.contains { $0.title == "Post-migration note" },
                "Note must be saveable and queryable in V8 migrated store (STAB-08)")

        // Asset round-trip with npsSchemeCode (new V8 field)
        let asset = SchemaV8.Asset()
        asset.name = "HDFC NPS Tier 1"
        asset.assetClassRaw = "nps"
        asset.npsSchemeCode = "SM001001"
        ctx.insert(asset)
        try ctx.save()
        let fetchedAssets = try ctx.fetch(FetchDescriptor<SchemaV8.Asset>())
        let npsAsset = fetchedAssets.first { $0.npsSchemeCode == "SM001001" }
        #expect(npsAsset != nil, "Asset with npsSchemeCode must be saveable after V8 migration")
        #expect(npsAsset?.name == "HDFC NPS Tier 1",
                "Asset name must be preserved after V8 insert+query")

        // SIP round-trip
        let sip = SchemaV8.SIP()
        sip.assetID = asset.id
        sip.dayOfMonth = 5
        sip.amount = Decimal(5000)
        sip.isActive = true
        sip.npsAllocationE = 75
        sip.npsAllocationC = 15
        sip.npsAllocationG = 10
        ctx.insert(sip)
        try ctx.save()
        let fetchedSIPs = try ctx.fetch(FetchDescriptor<SchemaV8.SIP>())
        #expect(fetchedSIPs.count == 1, "SIP must be saveable and queryable in V8 migrated store")
        let fetchedSIP = fetchedSIPs.first
        #expect(fetchedSIP?.dayOfMonth == 5, "SIP dayOfMonth must be preserved")
        #expect(fetchedSIP?.amount == Decimal(5000), "SIP amount must be preserved")
        #expect(fetchedSIP?.npsAllocationE == 75, "SIP npsAllocationE must be preserved")

        // Contribution round-trip
        let contribution = SchemaV8.Contribution()
        contribution.assetID = asset.id
        contribution.sipID = sip.id
        contribution.amount = Decimal(5000)
        contribution.navUsed = Decimal(string: "49.5429")!
        contribution.unitsAdded = Decimal(string: "100.9183")!
        contribution.isEstimate = true
        ctx.insert(contribution)
        try ctx.save()
        let fetchedContributions = try ctx.fetch(FetchDescriptor<SchemaV8.Contribution>())
        #expect(fetchedContributions.count == 1, "Contribution must be saveable and queryable in V8 migrated store")
        #expect(fetchedContributions.first?.isEstimate == true, "Contribution.isEstimate must be preserved")
    }
}

// ---------------------------------------------------------------------------
// MigrationTestsPlanV7 — trimmed migration plan stopping at SchemaV7.
//
// Mirrors MigrationTestsPlanV6 (SchemaV7MigrationTests.swift) exactly.
// Used to seed genuine V7 stores in tests without triggering the V8 migration.
// ---------------------------------------------------------------------------
enum MigrationTestsPlanV7: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [SchemaV1.self, SchemaV2.self, SchemaV3.self, SchemaV4.self, SchemaV5.self, SchemaV6.self, SchemaV7.self]
    }
    static var stages: [MigrationStage] {
        [v1ToV2, v2ToV3, v3ToV4, v4ToV5, v5ToV6, v6ToV7]
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
    static let v6ToV7 = MigrationStage.custom(
        fromVersion: SchemaV6.self, toVersion: SchemaV7.self, willMigrate: nil, didMigrate: nil)
}
