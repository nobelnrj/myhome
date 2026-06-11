import XCTest
@testable import MyHomeApp

/// Tests for the allocationSegments builder in NetWorthCard.
///
/// Coverage:
///   - Negative cash clamped to 0-value segment (T-11-12)
///   - Always returns 4 segments regardless of zero sub-totals
///   - True totalNetWorth (including negative) is preserved separately — NOT clamped
final class AllocationSegmentTests: XCTestCase {

    // MARK: - Helpers

    /// Build segments for the given sub-totals and verify count + order.
    private func segments(mf: Decimal = 0, stock: Decimal = 0, nps: Decimal = 0, cash: Decimal = 0) -> [DonutSegment] {
        NetWorthCard.allocationSegments(mf: mf, stock: stock, nps: nps, cash: cash)
    }

    // MARK: - Segment count

    func testAlwaysReturns4Segments() {
        XCTAssertEqual(segments().count, 4)
        XCTAssertEqual(segments(mf: 100_000, stock: 50_000, nps: 20_000, cash: 10_000).count, 4)
        XCTAssertEqual(segments(mf: 0, stock: 0, nps: 0, cash: -500_000).count, 4)
    }

    // MARK: - Negative cash clamp (T-11-12)

    func testNegativeCashSegmentClampsToZero() {
        let segs = segments(mf: 100_000, stock: 50_000, nps: 20_000, cash: -300_000)
        // Find cash segment (id "cash")
        let cashSeg = segs.first { $0.id == "cash" }
        XCTAssertNotNil(cashSeg, "Cash segment should exist even when cash is negative")
        XCTAssertEqual(cashSeg!.value, 0.0, "Negative cash value must be clamped to 0")
    }

    func testLargeNegativeCashClampsToZero() {
        // CC debt larger than all assets combined — total net worth is negative
        let segs = segments(mf: 10_000, stock: 5_000, nps: 0, cash: -1_000_000)
        let cashSeg = segs.first { $0.id == "cash" }
        XCTAssertEqual(cashSeg!.value, 0.0, "Very negative cash must still clamp to 0")
    }

    // MARK: - True total not clamped

    func testTrueTotalPreservedWhenNegative() {
        // The builder does NOT return the total — that's computed by NetWorthBreakdown.
        // Verify the segments do NOT sum to a positive value when net worth is negative:
        // the positive segments (mf/stock/nps) carry their real values, cash = 0.
        let segs = segments(mf: 10_000, stock: 5_000, nps: 0, cash: -1_000_000)
        let mfSeg = segs.first { $0.id == "mf" }
        let stockSeg = segs.first { $0.id == "stock" }
        // Positive sub-totals pass through unchanged
        XCTAssertEqual(mfSeg!.value, 10_000.0, accuracy: 0.001)
        XCTAssertEqual(stockSeg!.value, 5_000.0, accuracy: 0.001)
        // The visual "total" displayed in the donut center is the true breakdown total,
        // which is negative. We verify it via NetWorthBreakdown separately.
        let breakdown = NetWorthBreakdown(
            mfValue: 10_000, stockValue: 5_000, npsValue: 0, cashValue: -1_000_000
        )
        XCTAssertEqual(breakdown.totalNetWorth, -985_000, "True total must be negative — NOT clamped")
    }

    // MARK: - Positive values pass through

    func testPositiveValuesConvertedCorrectly() {
        let segs = segments(mf: 500_000, stock: 250_000, nps: 100_000, cash: 75_000)
        let mfSeg = segs.first { $0.id == "mf" }!
        let stockSeg = segs.first { $0.id == "stock" }!
        let npsSeg = segs.first { $0.id == "nps" }!
        let cashSeg = segs.first { $0.id == "cash" }!
        XCTAssertEqual(mfSeg.value, 500_000.0, accuracy: 0.001)
        XCTAssertEqual(stockSeg.value, 250_000.0, accuracy: 0.001)
        XCTAssertEqual(npsSeg.value, 100_000.0, accuracy: 0.001)
        XCTAssertEqual(cashSeg.value, 75_000.0, accuracy: 0.001)
    }

    func testZeroSubTotalProducesZeroValueSegment() {
        let segs = segments(mf: 100_000, stock: 0, nps: 0, cash: 0)
        let stockSeg = segs.first { $0.id == "stock" }!
        XCTAssertEqual(stockSeg.value, 0.0, "Zero sub-total maps to 0-value segment (thin sliver, no crash)")
    }

    // MARK: - Segment IDs and labels

    func testSegmentIDsAreCorrect() {
        let segs = segments(mf: 1, stock: 2, nps: 3, cash: 4)
        let ids = segs.map { $0.id }
        XCTAssertTrue(ids.contains("mf"))
        XCTAssertTrue(ids.contains("stock"))
        XCTAssertTrue(ids.contains("nps"))
        XCTAssertTrue(ids.contains("cash"))
    }
}
