import Foundation
import SwiftData

/// Spend donut aggregation helper for OVR-05.
///
/// Produces the top-4 categories by spend plus an "Others" roll-up for the Overview donut.
/// Self-transfer exclusion is delegated to `BudgetCalculator.monthlySpend` (which filters
/// `isTransfer != true`) — no `#Predicate`-based exclusion is used here (Pitfall 6).
enum SpendDonutAggregation {

    /// Returns donut segments for the given expense list.
    ///
    /// - Returns: Up to 4 named segments (category non-nil) sorted by descending spend,
    ///   alphabetical tie-break; followed by at most 1 "Others" entry (`category == nil`)
    ///   summing categories ranked 5+. Entries with zero spend are omitted.
    ///   Returns an empty array when no expenses have positive spend (zero-spend empty state).
    static func donutSegments(
        expenses: [Expense],
        categories: [Category]
    ) -> [(category: Category?, spent: Decimal)] {
        // Delegate self-transfer exclusion to BudgetCalculator (which filters isTransfer != true)
        let spendByID: [PersistentIdentifier: Decimal] =
            BudgetCalculator.monthlySpend(for: expenses, categories: categories)

        // Build (category, spent) pairs for categories with positive spend, ranked descending
        let ranked: [(category: Category, spent: Decimal)] = categories
            .compactMap { cat in
                let spent = spendByID[cat.persistentModelID] ?? .zero
                guard spent > .zero else { return nil }
                return (cat, spent)
            }
            .sorted { lhs, rhs in
                if lhs.spent != rhs.spent { return lhs.spent > rhs.spent }
                // Alphabetical tie-break by name (mirrors OverviewAggregation.topCategories)
                return (lhs.category.name ?? "") < (rhs.category.name ?? "")
            }

        guard !ranked.isEmpty else { return [] }

        // Top-4 named segments
        let top4 = Array(ranked.prefix(4))
        var result: [(category: Category?, spent: Decimal)] = top4.map { ($0.category, $0.spent) }

        // Others roll-up: sum categories ranked 5+ only when total > 0
        if ranked.count > 4 {
            let othersTotal = ranked.dropFirst(4).reduce(Decimal.zero) { $0 + $1.spent }
            if othersTotal > .zero {
                result.append((category: nil, spent: othersTotal))
            }
        }

        return result
    }
}
