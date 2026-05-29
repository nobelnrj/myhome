import Foundation
import SwiftData

// MARK: - BudgetColor

enum BudgetColor: Equatable {
    case normal
    case warning
    case overBudget
}

// MARK: - BudgetProgressData

/// Pure value type for budget progress computation.
/// No SwiftUI, no @Query — consumed by BudgetProgressView.
struct BudgetProgressData {
    let category: Category
    let spent: Decimal
    let budget: Decimal?

    // Stub — returns wrong values so RED tests fail
    var remaining: Decimal? { nil }
    var fractionUsed: Double? { nil }
    var colorThreshold: BudgetColor { .normal }
}

// MARK: - BudgetCalculator

/// Pure static aggregation over already-fetched expense arrays.
/// Import Foundation only — no SwiftUI, no SwiftData views.
struct BudgetCalculator {

    /// Returns per-category spend totals keyed by PersistentIdentifier.
    /// Expenses with empty categories are excluded (they feed the uncategorized bucket).
    static func monthlySpend(
        for expenses: [Expense],
        categories: [Category]
    ) -> [PersistentIdentifier: Decimal] {
        [:]  // stub
    }

    /// Returns the sum of expenses whose categories array is empty (D2-08).
    static func uncategorizedSpend(for expenses: [Expense]) -> Decimal {
        .zero  // stub
    }

    /// Computes the inclusive [start, end] boundaries for a given year/month in the
    /// user's timezone (P2-05, T-02-06).
    static func monthBoundaries(for month: DateComponents) -> (start: Date, end: Date)? {
        nil  // stub
    }
}
