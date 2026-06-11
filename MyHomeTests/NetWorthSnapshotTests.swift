import Testing
import SwiftData
import Foundation
@testable import MyHome

/// NetWorthSnapshot model-level persistence tests — partial ASSET-08 coverage.
///
/// Model-layer tests (Plan 01 scope): insert, defaults, negative cashValue, createdAt/id.
/// Service-layer tests (Plan 02): same-day upsert idempotency, new-day produces second row.
///
/// Uses an in-memory ModelContainer mirroring AssetCRUDTests.swift.
@MainActor
struct NetWorthSnapshotTests {

    private func makeContainer() throws -> ModelContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(
            for: NetWorthSnapshot.self, Asset.self, Account.self, Expense.self,
            configurations: config
        )
    }

    // MARK: - Model-level persistence (Plan 01)

    @Test("ASSET-08 model: insert a NetWorthSnapshot with all Decimal sub-totals and fetch returns exact values")
    func insertAndFetchSnapshotPreservesDecimalValues() throws {
        let container = try makeContainer()
        let ctx = container.mainContext

        let snapshot = NetWorthSnapshot()
        snapshot.date = Date()
        snapshot.totalNetWorth = Decimal(string: "1250000.75")!
        snapshot.mfValue = Decimal(string: "800000.00")!
        snapshot.stockValue = Decimal(string: "200000.25")!
        snapshot.npsValue = Decimal(string: "150000.50")!
        snapshot.cashValue = Decimal(string: "100000.00")!
        ctx.insert(snapshot)
        try ctx.save()

        let all = try ctx.fetch(FetchDescriptor<NetWorthSnapshot>())
        #expect(all.count == 1, "Exactly one NetWorthSnapshot must be in the store")

        let fetched = all.first!
        #expect(fetched.totalNetWorth == Decimal(string: "1250000.75"),
                "totalNetWorth must persist exactly (Decimal, not Double)")
        #expect(fetched.mfValue == Decimal(string: "800000.00"),
                "mfValue must persist exactly")
        #expect(fetched.stockValue == Decimal(string: "200000.25"),
                "stockValue must persist exactly")
        #expect(fetched.npsValue == Decimal(string: "150000.50"),
                "npsValue must persist exactly")
        #expect(fetched.cashValue == Decimal(string: "100000.00"),
                "cashValue must persist exactly")
    }

    @Test("ASSET-08 model: snapshot defaults — all Decimal fields default to 0, not nil")
    func snapshotDefaultsAreZero() throws {
        let container = try makeContainer()
        let ctx = container.mainContext

        let snapshot = NetWorthSnapshot()
        ctx.insert(snapshot)
        try ctx.save()

        let fetched = try ctx.fetch(FetchDescriptor<NetWorthSnapshot>()).first!
        #expect(fetched.totalNetWorth == Decimal(0), "totalNetWorth default must be 0")
        #expect(fetched.mfValue == Decimal(0), "mfValue default must be 0")
        #expect(fetched.stockValue == Decimal(0), "stockValue default must be 0")
        #expect(fetched.npsValue == Decimal(0), "npsValue default must be 0")
        #expect(fetched.cashValue == Decimal(0), "cashValue default must be 0")
    }

    @Test("ASSET-08 model: negative cashValue (CC debt > savings) persists without clamping")
    func negativeCashValuePersists() throws {
        let container = try makeContainer()
        let ctx = container.mainContext

        let snapshot = NetWorthSnapshot()
        snapshot.totalNetWorth = Decimal(string: "950000.00")!
        snapshot.mfValue = Decimal(string: "1000000.00")!
        snapshot.cashValue = Decimal(string: "-50000.00")!  // CC debt exceeds savings (D-11)
        ctx.insert(snapshot)
        try ctx.save()

        let fetched = try ctx.fetch(FetchDescriptor<NetWorthSnapshot>()).first!
        #expect(fetched.cashValue == Decimal(string: "-50000.00"),
                "Negative cashValue (CC debt) must persist without clamping at the model layer (D-11)")
        #expect(fetched.totalNetWorth == Decimal(string: "950000.00"),
                "totalNetWorth must reflect the negative cash contribution")
    }

    @Test("ASSET-08 model: createdAt and id are auto-populated on init")
    func snapshotAutoFieldsPopulated() throws {
        let container = try makeContainer()
        let ctx = container.mainContext

        let before = Date()
        let snapshot = NetWorthSnapshot()
        let after = Date()
        ctx.insert(snapshot)
        try ctx.save()

        let fetched = try ctx.fetch(FetchDescriptor<NetWorthSnapshot>()).first!
        #expect(fetched.id != UUID(uuidString: "00000000-0000-0000-0000-000000000000")!,
                "id must be non-zero UUID from init")
        #expect(fetched.createdAt >= before && fetched.createdAt <= after,
                "createdAt must be set to approximately now in init")
    }

    // MARK: - ASSET-08 service upsert tests (Plan 02 — NetWorthSnapshotService)

    @Test("ASSET-08 upsert: calling upsertIfNeeded twice on same IST day produces exactly one snapshot row")
    func upsertSameDayProducesOneRow() async throws {
        let container = try makeContainer()
        let ctx = container.mainContext

        let service = NetWorthSnapshotService()
        service.modelContext = ctx

        // First call
        service.upsertIfNeeded()
        // Give the internal Task a moment to run
        try await Task.sleep(nanoseconds: 100_000_000) // 0.1 s

        // Second call on the same day
        service.upsertIfNeeded()
        try await Task.sleep(nanoseconds: 100_000_000)

        let all = try ctx.fetch(FetchDescriptor<NetWorthSnapshot>())
        #expect(all.count == 1,
                "Two upsertIfNeeded calls on the same IST day must produce exactly 1 snapshot row (no duplicate)")
    }

    @Test("ASSET-08 upsert: second call on same day overwrites totalNetWorth — not duplicate insert")
    func upsertSameDayOverwritesTotalNetWorth() async throws {
        let container = try makeContainer()
        let ctx = container.mainContext

        // Insert a snapshot for today manually with a sentinel value
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Kolkata")!
        let todayIST = cal.startOfDay(for: Date())

        let initial = NetWorthSnapshot()
        initial.date = todayIST
        initial.totalNetWorth = Decimal(string: "999999.00")!
        ctx.insert(initial)
        try ctx.save()

        let service = NetWorthSnapshotService()
        service.modelContext = ctx

        // Insert an asset so upsert produces a non-sentinel total
        let asset = Asset()
        asset.assetClassRaw = "stock"
        asset.units = Decimal(1)
        asset.currentNAV = Decimal(123)
        ctx.insert(asset)
        try ctx.save()

        service.upsertIfNeeded()
        try await Task.sleep(nanoseconds: 150_000_000) // 0.15 s

        let all = try ctx.fetch(
            FetchDescriptor<NetWorthSnapshot>(sortBy: [SortDescriptor(\.date, order: .reverse)])
        )
        #expect(all.count == 1, "upsertIfNeeded must not create a duplicate row")
        // The totalNetWorth should no longer be the sentinel (overwritten by the service)
        #expect(all.first!.totalNetWorth != Decimal(string: "999999.00")!,
                "upsertIfNeeded must overwrite the existing snapshot's totalNetWorth")
    }

    @Test("ASSET-08 snapshot: snapshot carries all 4 sub-totals + total (D-09)")
    func snapshotCarriesFullBreakdown() async throws {
        let container = try makeContainer()
        let ctx = container.mainContext

        // One MF asset: 10 × 100 = 1000
        let mfAsset = Asset()
        mfAsset.assetClassRaw = "mutual_fund"
        mfAsset.units = Decimal(10)
        mfAsset.currentNAV = Decimal(100)
        ctx.insert(mfAsset)

        // One stock asset: 5 × 200 = 1000
        let stockAsset = Asset()
        stockAsset.assetClassRaw = "stock"
        stockAsset.units = Decimal(5)
        stockAsset.currentNAV = Decimal(200)
        ctx.insert(stockAsset)
        try ctx.save()

        let service = NetWorthSnapshotService()
        service.modelContext = ctx
        service.upsertIfNeeded()
        try await Task.sleep(nanoseconds: 150_000_000)

        let all = try ctx.fetch(FetchDescriptor<NetWorthSnapshot>())
        #expect(all.count == 1)
        let snap = all.first!
        #expect(snap.mfValue    == 1000, "mfValue must be 10×100 = 1000")
        #expect(snap.stockValue == 1000, "stockValue must be 5×200 = 1000")
        #expect(snap.npsValue   == 0,    "npsValue must be 0 (no NPS assets)")
        #expect(snap.cashValue  == 0,    "cashValue must be 0 (no accounts)")
        #expect(snap.totalNetWorth == 2000, "totalNetWorth must be MF+stock = 2000")
    }
}
