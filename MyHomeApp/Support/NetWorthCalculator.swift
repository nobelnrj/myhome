import Foundation
import SwiftData

// MARK: - NetWorthBreakdown

/// Pure value type carrying the four per-class sub-totals plus total net worth.
///
/// All amounts are Decimal (Pitfall 17). Negative cashValue is valid (CC debt > savings — D-11).
struct NetWorthBreakdown {
    let mfValue: Decimal
    let stockValue: Decimal
    let npsValue: Decimal
    let cashValue: Decimal
    var totalNetWorth: Decimal { mfValue + stockValue + npsValue + cashValue }
}

// MARK: - NetWorthCalculator

/// Pure static aggregation for net worth — no persistence, no SwiftUI (ASSET-05).
///
/// Reuses `AccountBalance.compute()` for cash aggregation so the POSITIVE-spend / baseline−net
/// sign convention is honored exactly (T-11-07). Never re-implements the balance formula.
///
/// Asset class lookup: by `assetClassRaw` String raw value (rule 8: no stored enums).
/// Nil units or nil currentNAV contribute 0 (ASSET-02 nil-safe).
enum NetWorthCalculator {

    /// Compute the full net-worth breakdown from raw model arrays.
    ///
    /// - Parameters:
    ///   - assets: All Asset rows (archived and non-archived; filtering by class only).
    ///   - accounts: All Account rows; non-archived ones contribute to cashValue.
    ///   - expenses: All Expense rows; used by AccountBalance.compute for each account.
    /// - Returns: A NetWorthBreakdown with per-class sub-totals and total.
    static func breakdown(assets: [Asset], accounts: [Account], expenses: [Expense]) -> NetWorthBreakdown {
        var mf: Decimal = 0
        var stock: Decimal = 0
        var nps: Decimal = 0

        for asset in assets {
            guard let units = asset.units, let nav = asset.currentNAV else { continue }
            let value = units * nav
            switch asset.assetClassRaw {
            case "mutual_fund": mf += value
            case "stock":       stock += value
            case "nps":         nps += value
            default:            break
            }
        }

        // T-11-07: reuse AccountBalance.compute — never re-implement the balance formula
        var cash: Decimal = 0
        for account in accounts where !account.isArchived {
            cash += AccountBalance.compute(
                baseline: account.balanceBaseline,
                asOf: account.balanceAsOfDate,
                expenses: expenses,
                accountID: account.id
            )
        }

        return NetWorthBreakdown(mfValue: mf, stockValue: stock, npsValue: nps, cashValue: cash)
    }
}
