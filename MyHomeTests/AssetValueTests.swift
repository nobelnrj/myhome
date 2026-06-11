import Testing
import SwiftData
import Foundation
@testable import MyHome

/// Asset current-value derivation tests — ASSET-02: currentValue = units × currentNAV.
///
/// Pure Decimal math; all assertions use exact Decimal equality (never Double).
/// Uses an in-memory ModelContainer mirroring AssetCRUDTests.swift.
///
/// currentValue is a computed property on SchemaV7.Asset derived at the call site.
/// The formula: (units ?? 0) × (currentNAV ?? 0) — nil units or nil NAV yields 0.
@MainActor
struct AssetValueTests {

    private func makeContainer() throws -> ModelContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: Asset.self, configurations: config)
    }

    // Compute current value using the canonical formula (mirrors RESEARCH.md Net-Worth Aggregation section)
    private func currentValue(of asset: Asset) -> Decimal {
        guard let units = asset.units, let nav = asset.currentNAV else { return Decimal(0) }
        return units * nav
    }

    // MARK: - ASSET-02: currentValue = units × currentNAV

    @Test("ASSET-02: currentValue equals units × currentNAV (exact Decimal equality)")
    func currentValueEqualsUnitsByNAV() throws {
        let container = try makeContainer()
        let ctx = container.mainContext

        let asset = Asset()
        asset.name = "Test MF"
        asset.assetClassRaw = "mutual_fund"
        asset.units = Decimal(10)
        asset.currentNAV = Decimal(string: "12.50")
        ctx.insert(asset)
        try ctx.save()

        let fetched = try ctx.fetch(FetchDescriptor<Asset>()).first!
        let value = currentValue(of: fetched)

        // Exact: 10 × 12.50 = 125.00
        #expect(value == Decimal(string: "125.00"),
                "ASSET-02: currentValue must equal units × currentNAV = 10 × 12.50 = 125.00 (exact Decimal)")
    }

    @Test("ASSET-02: larger holding — 1000 units at 234.56 yields 234560.00")
    func currentValueLargeHolding() throws {
        let container = try makeContainer()
        let ctx = container.mainContext

        let asset = Asset()
        asset.name = "HDFC Flexicap Fund"
        asset.assetClassRaw = "mutual_fund"
        asset.units = Decimal(1000)
        asset.currentNAV = Decimal(string: "234.56")
        ctx.insert(asset)
        try ctx.save()

        let fetched = try ctx.fetch(FetchDescriptor<Asset>()).first!
        let value = currentValue(of: fetched)

        #expect(value == Decimal(string: "234560.00"),
                "ASSET-02: 1000 units × 234.56 must equal 234560.00 (exact Decimal)")
    }

    // MARK: - ASSET-02: nil guard — nil units yields 0

    @Test("ASSET-02: nil units yields currentValue of 0 (no crash)")
    func nilUnitsYieldsZeroCurrentValue() throws {
        let container = try makeContainer()
        let ctx = container.mainContext

        let asset = Asset()
        asset.name = "Incomplete Asset"
        asset.assetClassRaw = "mutual_fund"
        asset.units = nil               // units not set
        asset.currentNAV = Decimal(string: "100.00")
        ctx.insert(asset)
        try ctx.save()

        let fetched = try ctx.fetch(FetchDescriptor<Asset>()).first!
        let value = currentValue(of: fetched)

        #expect(value == Decimal(0),
                "ASSET-02: nil units must yield currentValue = 0 (no crash, no NaN)")
    }

    // MARK: - ASSET-02: nil guard — nil currentNAV yields 0

    @Test("ASSET-02: nil currentNAV yields currentValue of 0 (no crash)")
    func nilNAVYieldsZeroCurrentValue() throws {
        let container = try makeContainer()
        let ctx = container.mainContext

        let asset = Asset()
        asset.name = "Asset Without NAV"
        asset.assetClassRaw = "stock"
        asset.units = Decimal(50)
        asset.currentNAV = nil          // NAV not set
        ctx.insert(asset)
        try ctx.save()

        let fetched = try ctx.fetch(FetchDescriptor<Asset>()).first!
        let value = currentValue(of: fetched)

        #expect(value == Decimal(0),
                "ASSET-02: nil currentNAV must yield currentValue = 0 (no crash, no NaN)")
    }

    // MARK: - ASSET-02: nil guard — both nil yields 0

    @Test("ASSET-02: nil units and nil currentNAV yields currentValue of 0 (no crash)")
    func bothNilYieldsZeroCurrentValue() throws {
        let container = try makeContainer()
        let ctx = container.mainContext

        let asset = Asset()
        asset.name = "Empty Asset"
        asset.units = nil
        asset.currentNAV = nil
        ctx.insert(asset)
        try ctx.save()

        let fetched = try ctx.fetch(FetchDescriptor<Asset>()).first!
        let value = currentValue(of: fetched)

        #expect(value == Decimal(0),
                "ASSET-02: nil units + nil NAV must yield 0 (no crash, no NaN)")
    }
}
