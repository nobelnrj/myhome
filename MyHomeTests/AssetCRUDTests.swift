import Testing
import SwiftData
import Foundation
@testable import MyHome

/// Asset CRUD model tests — verifies insert/edit/delete against an in-memory SchemaV7 container.
///
/// Covers ASSET-01 (holdings CRUD), ASSET-04 (manual NAV preserved; not auto-overwritten).
/// Uses an in-memory ModelContainer per test (FND-06), mirroring AccountCRUDTests.swift.
@MainActor
struct AssetCRUDTests {

    private func makeContainer() throws -> ModelContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: Asset.self, configurations: config)
    }

    // MARK: - ASSET-01: Insert

    @Test("insert: inserting an Asset and saving produces one persisted row with correct fields")
    func insertAsset() throws {
        let container = try makeContainer()
        let ctx = container.mainContext

        let asset = Asset()
        asset.name = "Aditya Birla Sun Life MF"
        asset.assetClassRaw = "mutual_fund"
        asset.units = Decimal(50)
        asset.costBasisPerUnit = Decimal(string: "105.50")
        ctx.insert(asset)
        try ctx.save()

        let all = try ctx.fetch(FetchDescriptor<Asset>())
        #expect(all.count == 1, "Exactly one Asset must be in the store after insert")

        let fetched = all.first
        #expect(fetched?.name == "Aditya Birla Sun Life MF", "Asset name must be preserved")
        #expect(fetched?.assetClassRaw == "mutual_fund", "Asset class must be preserved")
        #expect(fetched?.units == Decimal(50), "Asset units must be preserved")
        #expect(fetched?.costBasisPerUnit == Decimal(string: "105.50"), "Cost basis per unit must be preserved")
    }

    // MARK: - ASSET-01: Edit

    @Test("edit: updating currentNAV and saving reflects the new value on re-fetch")
    func editAssetNAV() throws {
        let container = try makeContainer()
        let ctx = container.mainContext

        let asset = Asset()
        asset.name = "HDFC Mid-Cap Opportunities"
        asset.assetClassRaw = "mutual_fund"
        asset.units = Decimal(100)
        asset.currentNAV = Decimal(string: "80.00")
        ctx.insert(asset)
        try ctx.save()

        // Update currentNAV
        asset.currentNAV = Decimal(string: "95.75")
        try ctx.save()

        let all = try ctx.fetch(FetchDescriptor<Asset>())
        #expect(all.count == 1, "Still exactly one Asset after edit")
        #expect(all.first?.currentNAV == Decimal(string: "95.75"),
                "Updated currentNAV must be reflected on re-fetch")
    }

    // MARK: - ASSET-01: Delete

    @Test("delete: deleting an Asset and saving returns zero rows on re-fetch")
    func deleteAsset() throws {
        let container = try makeContainer()
        let ctx = container.mainContext

        let asset = Asset()
        asset.name = "SBI Small Cap Fund"
        asset.assetClassRaw = "mutual_fund"
        ctx.insert(asset)
        try ctx.save()

        // Verify it was inserted
        let before = try ctx.fetch(FetchDescriptor<Asset>())
        #expect(before.count == 1, "Asset must exist before delete")

        // Delete and save
        ctx.delete(asset)
        try ctx.save()

        let after = try ctx.fetch(FetchDescriptor<Asset>())
        #expect(after.isEmpty, "Asset store must be empty after delete")
    }

    // MARK: - ASSET-04: Manual NAV preserved (stock/NPS)

    @Test("ASSET-04: manually set currentNAV on a stock/NPS asset persists unchanged across fetch cycles")
    func manualNAVPreservedForStockAsset() throws {
        let container = try makeContainer()
        let ctx = container.mainContext

        // Stock asset with manually-entered NAV — no AMFI auto-fetch touches stock assets
        let stockAsset = Asset()
        stockAsset.name = "Infosys"
        stockAsset.assetClassRaw = "stock"
        stockAsset.units = Decimal(10)
        stockAsset.currentNAV = Decimal(string: "1750.50")  // manually set
        ctx.insert(stockAsset)
        try ctx.save()

        // Simulate a fetch (e.g., on a subsequent app launch) — no code path in Plan 01 touches this value
        let fetched = try ctx.fetch(FetchDescriptor<Asset>())
        let fetchedStock = fetched.first { $0.assetClassRaw == "stock" }

        #expect(fetchedStock?.currentNAV == Decimal(string: "1750.50"),
                "ASSET-04: manually set currentNAV for stock/NPS asset must persist unchanged (no auto-overwrite in this plan)")
    }

    // MARK: - ASSET-07: amfiSchemeCode stored and queryable

    @Test("amfiSchemeCode: setting amfiSchemeCode on an Asset persists and is queryable")
    func amfiSchemeCodePersistedOnAsset() throws {
        let container = try makeContainer()
        let ctx = container.mainContext

        let asset = Asset()
        asset.name = "Axis Bluechip Fund - Growth"
        asset.assetClassRaw = "mutual_fund"
        asset.amfiSchemeCode = "120503"  // D-01: AMFI scheme code
        ctx.insert(asset)
        try ctx.save()

        let all = try ctx.fetch(FetchDescriptor<Asset>())
        #expect(all.first?.amfiSchemeCode == "120503",
                "amfiSchemeCode must persist and be queryable on SchemaV7 Asset (D-01)")
    }
}
