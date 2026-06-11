import Testing
import Foundation
@testable import MyHome

/// Gain/loss calculation tests — verifies AssetValuation pure-logic helper (ASSET-06, T-11-11).
///
/// Cases covered:
///   positive gain: absoluteGain > 0, percentGain > 0
///   negative gain: absoluteGain < 0, percentGain < 0
///   zero cost basis: percentGain == nil (no divide-by-zero crash), absoluteGain == currentValue
///   nil cost basis: percentGain == nil
struct AssetGainLossTests {

    // MARK: - Positive Gain

    @Test("positive gain: both absolute and percent gain are positive")
    func positiveGain() {
        // units: 100, costBasisPerUnit: 100, currentNAV: 120
        // totalCost = 10_000, currentValue = 12_000, absoluteGain = 2_000, percentGain = 20%
        let abs = AssetValuation.absoluteGain(units: 100, costBasisPerUnit: 100, currentNAV: 120)
        let pct = AssetValuation.percentGain(units: 100, costBasisPerUnit: 100, currentNAV: 120)

        #expect(abs == Decimal(2000), "absoluteGain must be 2000 when value grew from 10000 to 12000")
        #expect(pct != nil, "percentGain must be non-nil when totalCost > 0")
        #expect(pct! > 0, "percentGain must be positive for a gain")
        // 20% exactly
        #expect(pct == Decimal(20), "percentGain must be 20% (2000/10000 * 100)")
    }

    // MARK: - Negative Gain (Loss)

    @Test("negative gain: both absolute and percent gain are negative")
    func negativeGain() {
        // units: 50, costBasisPerUnit: 200, currentNAV: 150
        // totalCost = 10_000, currentValue = 7_500, absoluteGain = -2_500, percentGain = -25%
        let abs = AssetValuation.absoluteGain(units: 50, costBasisPerUnit: 200, currentNAV: 150)
        let pct = AssetValuation.percentGain(units: 50, costBasisPerUnit: 200, currentNAV: 150)

        #expect(abs == Decimal(-2500), "absoluteGain must be -2500 for a loss")
        #expect(pct != nil, "percentGain must be non-nil when totalCost > 0")
        #expect(pct! < 0, "percentGain must be negative for a loss")
        #expect(pct == Decimal(-25), "percentGain must be -25%")
    }

    // MARK: - Zero Cost Basis (T-11-11 — no divide-by-zero)

    @Test("zero cost basis: percentGain is nil, absoluteGain is currentValue")
    func zeroCostBasis() {
        // units: 10, costBasisPerUnit: 0, currentNAV: 50
        // totalCost = 0, absoluteGain = 500, percentGain = nil
        let abs = AssetValuation.absoluteGain(units: 10, costBasisPerUnit: 0, currentNAV: 50)
        let pct = AssetValuation.percentGain(units: 10, costBasisPerUnit: 0, currentNAV: 50)

        #expect(abs == Decimal(500), "absoluteGain must equal currentValue when costBasis is 0")
        #expect(pct == nil, "percentGain must be nil when totalCost == 0 (no divide-by-zero)")
    }

    @Test("nil cost basis: percentGain is nil, absoluteGain is currentValue")
    func nilCostBasis() {
        // Same as zero — nil costBasisPerUnit treated as 0
        let abs = AssetValuation.absoluteGain(units: 10, costBasisPerUnit: nil, currentNAV: 50)
        let pct = AssetValuation.percentGain(units: 10, costBasisPerUnit: nil, currentNAV: 50)

        #expect(abs == Decimal(500), "absoluteGain must equal currentValue when costBasis is nil")
        #expect(pct == nil, "percentGain must be nil when totalCost is nil/0")
    }

    // MARK: - Helper functions (currentValue, totalCost)

    @Test("currentValue: units * currentNAV")
    func currentValueCalculation() {
        let value = AssetValuation.currentValue(units: 100, currentNAV: Decimal(string: "123.45"))
        #expect(value == Decimal(string: "12345.00"), "currentValue = 100 × 123.45 = 12345.00")
    }

    @Test("totalCost: units * costBasisPerUnit")
    func totalCostCalculation() {
        let cost = AssetValuation.totalCost(units: 50, costBasisPerUnit: Decimal(string: "200.00"))
        #expect(cost == Decimal(10000), "totalCost = 50 × 200.00 = 10000")
    }

    @Test("nil units treated as 0 for all calculations")
    func nilUnitsProduceZero() {
        let abs = AssetValuation.absoluteGain(units: nil, costBasisPerUnit: 100, currentNAV: 120)
        let pct = AssetValuation.percentGain(units: nil, costBasisPerUnit: 100, currentNAV: 120)
        #expect(abs == 0, "absoluteGain with nil units must be 0")
        #expect(pct == nil, "percentGain with nil units (totalCost == 0) must be nil")
    }
}
