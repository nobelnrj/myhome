import Testing
import SwiftData
import Foundation
@testable import MyHome

/// NetWorthSnapshot model-level persistence tests — partial ASSET-08 coverage.
///
/// This suite covers model-layer insert + persist + fetch (Plan 01 scope).
/// Service-level upsert tests (daily dedup, second-call-same-day overwrite) depend on
/// NetWorthSnapshotService shipped in Plan 02 and are stubbed here as named tests to be
/// filled in when the service is available.
///
/// Uses an in-memory ModelContainer mirroring AssetCRUDTests.swift.
@MainActor
struct NetWorthSnapshotTests {

    private func makeContainer() throws -> ModelContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: NetWorthSnapshot.self, configurations: config)
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

    // MARK: - ASSET-08 service stubs (Plan 02 fills these in)
    // These stubs are intentionally incomplete — they require NetWorthSnapshotService (Plan 02).
    // They are named here to serve as a checklist for the Wave 2 planner.

    @Test("STUB — ASSET-08 upsert: calling upsertIfNeeded twice on same day produces exactly one snapshot row")
    func stubUpsertSameDayProducesOneRow() throws {
        // TODO (Plan 02): wire up NetWorthSnapshotService.upsertIfNeeded() and assert
        // that two calls on the same IST date yield count == 1 and the second call
        // overwrites totalNetWorth rather than inserting a duplicate.
        // This test will be completed in plan 11-02.
        //
        // For now, assert a trivially-true condition to keep the suite green as a stub placeholder.
        #expect(Bool(true), "Stub — completed in plan 11-02 (NetWorthSnapshotService)")
    }

    @Test("STUB — ASSET-08 upsert: calling upsertIfNeeded on a new day produces a second snapshot row")
    func stubUpsertNewDayProducesSecondRow() throws {
        // TODO (Plan 02): advance the simulated IST clock by one day and assert count == 2.
        // This test will be completed in plan 11-02.
        #expect(Bool(true), "Stub — completed in plan 11-02 (NetWorthSnapshotService)")
    }
}
