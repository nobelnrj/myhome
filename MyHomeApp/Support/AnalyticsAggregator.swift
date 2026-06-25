import Foundation
import SwiftUI    // required for Color (CategorySpendItem.color + CategoryStyle.color)
import SwiftData  // required for PersistentIdentifier

// MARK: - SpendSummary

/// Pre-aggregated value type produced by `AnalyticsAggregator.summarize`.
///
/// Pure struct — no SwiftUI/SwiftData @Observable, no Identifiable requirement.
/// Phase 16 (InsightService / AI card) can consume this type without modification.
///
/// **Delta semantics (ANL-05):** positive `delta` = spent MORE vs prior period (shown coral/negative
/// in the UI). Inverted color logic lives in the View layer (`DeltaChip`), not here.
struct SpendSummary {

    // MARK: Range identity

    /// The range this summary was computed for.
    let range: SpendRange

    // MARK: Headline figures (Decimal for display; Double only at Chart boundary)

    /// Total spend in the current period, self-transfer-excluded.
    let totalSpend: Decimal

    /// Total spend in the immediately prior same-length period, self-transfer-excluded.
    let priorTotalSpend: Decimal

    // MARK: Period-over-period delta

    /// Current minus prior spend.
    /// Positive = spent MORE (bad / coral in UI); negative = spent LESS (good / green in UI).
    var delta: Decimal { totalSpend - priorTotalSpend }

    /// Fractional change as Double for "↓ 12%" display; zero-guarded.
    /// Pitfall 7: stays in Decimal until the final NSDecimalNumber conversion.
    var deltaFraction: Double {
        guard priorTotalSpend > 0 else { return 0 }
        return NSDecimalNumber(decimal: delta / priorTotalSpend).doubleValue
    }

    // MARK: Trend chart data

    /// Pre-bucketed spend data for the current period.
    /// Delegates to `SpendOverTimeAggregator.bucket(...)` — no re-implementation (ANL-03).
    /// For `.year` range, filtered to months <= current month (no future zero-bars).
    let trendBuckets: [SpendBucket]

    // MARK: Category breakdown

    /// Per-category spend for the current period, sorted descending by spend.
    /// Reuses `CategorySpendItem` from `SpendByCategoryChart` — zero changes needed in the
    /// category bar view when it consumes this aggregator vs the Overview's manual construction.
    let categoryBreakdown: [CategorySpendItem]

    /// Per-category spend for the prior period, keyed by PersistentIdentifier for O(1) lookup.
    /// Used by `DeltaDrillDownSheet` (ANL-06) to show which categories drove the delta.
    let priorCategorySpend: [PersistentIdentifier: Decimal]
}

// MARK: - AnalyticsAggregator

/// Pure static aggregator that produces a `SpendSummary` for a given time range (ANL-07).
///
/// No SwiftUI Views, no @Query, no SwiftData context — purely operates on already-fetched arrays.
/// Trend bucketing delegates entirely to `SpendOverTimeAggregator` (ANL-03): no `startOfDay` or
/// `startOfMonth` re-implementation lives here (Pitfall 3).
///
/// Inject an `Asia/Kolkata` `Calendar` in tests to verify IST midnight boundary behaviour without
/// depending on the simulator's system timezone (Pitfall 1 / ANL-07).
enum AnalyticsAggregator {

    // MARK: - Public API

    /// Produces a `SpendSummary` for the given range.
    ///
    /// - Parameters:
    ///   - expenses: All expenses spanning BOTH the current and prior period.
    ///               (The caller's `@Query` must be wide enough — e.g. 2 years for `.year` range.)
    ///   - categories: All categories (for name + color resolution).
    ///   - range: `.week` / `.month` / `.year`
    ///   - calendar: Defaults to `.current` (device timezone). Inject an IST-forced calendar for
    ///               tests or explicit timezone-aware aggregation (ANL-07, T-15-02).
    static func summarize(
        expenses: [Expense],
        categories: [Category],
        range: SpendRange,
        calendar: Calendar = .current
    ) -> SpendSummary {

        // (a) Compute period windows.
        let (currentStart, currentEnd) = currentPeriodBounds(range: range, calendar: calendar)
        let (priorStart, priorEnd) = priorPeriodBounds(range: range, calendar: calendar)

        // (b) Filter to each period, excluding confirmed self-transfers.
        let currentExpenses = expenses.filter {
            $0.date >= currentStart && $0.date <= currentEnd && $0.isTransfer != true
        }
        let priorExpenses = expenses.filter {
            $0.date >= priorStart && $0.date <= priorEnd && $0.isTransfer != true
        }

        // (c) Delegate trend bucketing — NO re-implementation of IST logic (ANL-03, Pitfall 3).
        var trendBuckets = SpendOverTimeAggregator.bucket(
            expenses: currentExpenses,
            range: range,
            calendar: calendar
        )

        // (d) For .year only: filter out future months (Pitfall 4 / success criterion 3).
        if range == .year {
            let currentMonth = calendar.component(.month, from: Date())
            trendBuckets = trendBuckets.filter {
                calendar.component(.month, from: $0.date) <= currentMonth
            }
        }

        // (e) Per-category totals for both periods — single source of truth for the
        // headline AND the bars, so the two can never silently disagree.
        let currentCategoryTotals = BudgetCalculator.monthlySpend(
            for: currentExpenses,
            categories: categories
        )
        let priorCategoryTotals = BudgetCalculator.monthlySpend(
            for: priorExpenses,
            categories: categories
        )

        // (f) Headline totals — composed identically to OverviewView (CR-01): categorized
        // spend + uncategorized spend. This matches the app-wide spend convention and keeps
        // the headline reconciled with the category bars (their sum + the uncategorized
        // remainder). The previous raw `reduce` was wrong: it subtracted refund/income
        // (negative-amount) rows and counted orphaned-category spend the bars exclude.
        let totalSpend = currentCategoryTotals.values.reduce(Decimal.zero, +)
            + BudgetCalculator.uncategorizedSpend(for: currentExpenses)
        let priorTotalSpend = priorCategoryTotals.values.reduce(Decimal.zero, +)
            + BudgetCalculator.uncategorizedSpend(for: priorExpenses)

        // (g) Per-category breakdown for current period.
        // Map PersistentIdentifier → CategorySpendItem, resolving name + color from categories.
        let catLookup: [PersistentIdentifier: Category] = Dictionary(
            uniqueKeysWithValues: categories.map { ($0.persistentModelID, $0) }
        )
        let categoryBreakdown: [CategorySpendItem] = currentCategoryTotals
            .compactMap { (id, decimalSpent) -> CategorySpendItem? in
                guard decimalSpent > .zero else { return nil }
                let cat = catLookup[id]
                // Pitfall B: Double only at this boundary via NSDecimalNumber.
                let doubleSpent = NSDecimalNumber(decimal: decimalSpent).doubleValue
                return CategorySpendItem(
                    id: id,
                    name: cat?.name ?? "Unknown",
                    spent: doubleSpent,
                    spentDecimal: decimalSpent,
                    color: CategoryStyle.color(for: cat)
                )
            }
            .sorted { $0.spentDecimal > $1.spentDecimal }

        // (h) Prior-period per-category totals feed the drill-down delta chips (ANL-06).
        // Reuses the totals already computed in (e) — no second monthlySpend pass.
        return SpendSummary(
            range: range,
            totalSpend: totalSpend,
            priorTotalSpend: priorTotalSpend,
            trendBuckets: trendBuckets,
            categoryBreakdown: categoryBreakdown,
            priorCategorySpend: priorCategoryTotals
        )
    }

    // MARK: - Period boundary helpers

    /// Returns (start, end) for the CURRENT period in the injected calendar.
    ///
    /// - `.week`:  rolling 7-day window ending today (today-6 … today)
    /// - `.month`: start of calendar month … end of calendar month
    /// - `.year`:  Jan 1 this year … today
    private static func currentPeriodBounds(
        range: SpendRange,
        calendar: Calendar
    ) -> (Date, Date) {
        let today = calendar.startOfDay(for: Date())
        switch range {
        case .week:
            let start = calendar.date(byAdding: .day, value: -6, to: today) ?? today
            let end = calendar.date(byAdding: .day, value: 1, to: today).flatMap {
                calendar.date(byAdding: .second, value: -1, to: $0)
            } ?? today
            return (start, end)

        case .month:
            var comps = calendar.dateComponents([.year, .month], from: today)
            comps.day = 1
            let start = calendar.date(from: comps) ?? today
            let nextMonthStart = calendar.date(byAdding: .month, value: 1, to: start) ?? today
            let end = calendar.date(byAdding: .second, value: -1, to: nextMonthStart) ?? today
            return (start, end)

        case .year:
            var comps = DateComponents()
            comps.year = calendar.component(.year, from: today)
            comps.month = 1
            comps.day = 1
            let start = calendar.date(from: comps) ?? today
            let end = calendar.date(byAdding: .day, value: 1, to: today).flatMap {
                calendar.date(byAdding: .second, value: -1, to: $0)
            } ?? today
            return (start, end)
        }
    }

    /// Returns (start, end) for the PRIOR period immediately preceding the current one.
    ///
    /// - `.week`:  today-13 … today-7
    /// - `.month`: start of last month … end of last month
    /// - `.year`:  Jan 1 last year … Dec 31 last year
    private static func priorPeriodBounds(
        range: SpendRange,
        calendar: Calendar
    ) -> (Date, Date) {
        let today = calendar.startOfDay(for: Date())
        switch range {
        case .week:
            let start = calendar.date(byAdding: .day, value: -13, to: today) ?? today
            let endDay = calendar.date(byAdding: .day, value: -7, to: today) ?? today
            let end = calendar.date(byAdding: .day, value: 1, to: endDay).flatMap {
                calendar.date(byAdding: .second, value: -1, to: $0)
            } ?? endDay
            return (start, end)

        case .month:
            var comps = calendar.dateComponents([.year, .month], from: today)
            comps.day = 1
            let thisMonthStart = calendar.date(from: comps) ?? today
            let priorMonthStart = calendar.date(byAdding: .month, value: -1, to: thisMonthStart) ?? today
            let end = calendar.date(byAdding: .second, value: -1, to: thisMonthStart) ?? today
            return (priorMonthStart, end)

        case .year:
            let thisYear = calendar.component(.year, from: today)
            var startComps = DateComponents()
            startComps.year = thisYear - 1
            startComps.month = 1
            startComps.day = 1
            let start = calendar.date(from: startComps) ?? today
            var endComps = DateComponents()
            endComps.year = thisYear - 1
            endComps.month = 12
            endComps.day = 31
            let end = calendar.date(from: endComps).flatMap {
                calendar.date(byAdding: .day, value: 1, to: $0).flatMap {
                    calendar.date(byAdding: .second, value: -1, to: $0)
                }
            } ?? today
            return (start, end)
        }
    }
}
