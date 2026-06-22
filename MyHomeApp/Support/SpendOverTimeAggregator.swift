import Foundation

// MARK: - SpendRange

/// The three time ranges for the spend-over-time chart (EXP-11).
enum SpendRange: String, CaseIterable {
    case week
    case month
    case year

    /// Human-readable label for tab/segment control display.
    var label: String {
        switch self {
        case .week:  return "Week"
        case .month: return "Month"
        case .year:  return "Year"
        }
    }
}

// MARK: - SpendBucket

/// A single data point for the spend-over-time chart: a date slot and its total spend.
///
/// `spent` is `Double` (not `Decimal`) because Swift Charts requires `Double` or `Int` for
/// numeric axes. The conversion from `Decimal` happens once, at construction, via
/// `NSDecimalNumber(decimal:).doubleValue` (Pitfall B guard — no float drift in stored money).
struct SpendBucket: Identifiable {
    /// Stable identity for SwiftUI diffing — equals `date` (start-of-day or start-of-month).
    let id: Date
    /// The calendar slot this bucket represents.
    let date: Date
    /// Total spend in this slot, converted from Decimal at the aggregation boundary.
    /// Used ONLY as the Chart plot value (Plottable requires Double).
    let spent: Double
    /// Original Decimal spend, carried alongside `spent` so the point annotation /
    /// accessibility label format from the exact value — never reconstruct
    /// `Decimal(spent)` from the lossy Double (WR-03, Pitfall B: no float drift).
    let spentDecimal: Decimal
    /// Accessibility / chart tooltip label for this date slot.
    var dateLabel: String
}

// MARK: - SpendOverTimeAggregator

/// Pure static helper for spend-over-time bucketing (EXP-11).
///
/// **Pure contract:** operates on already-fetched arrays; no SwiftData access,
/// no @Query, no SwiftUI, no Charts import. Mirrors the CalendarAggregator discipline.
///
/// Bucketing uses the **injected** calendar's timezone (defaults to `Calendar.current`,
/// which inherits `TimeZone.current` — device timezone). Pass a calendar with
/// `timeZone = TimeZone(identifier: "Asia/Kolkata")` to force IST bucketing in tests
/// or for IST-aware aggregation (ANL-03 / T-15-02).
///
/// Money stays `Decimal` throughout the accumulation loop; the `Decimal → Double` conversion
/// happens only at `SpendBucket` construction via `NSDecimalNumber(decimal:).doubleValue`
/// (T-04-02 / Pitfall B guard).
enum SpendOverTimeAggregator {

    // MARK: - Private helpers

    /// Returns the start-of-day `Date` for a given `Date` in the injected calendar's timezone.
    /// The caller owns the timezone — no override to `TimeZone.current`.
    private static func startOfDay(_ date: Date, calendar: Calendar) -> Date {
        return calendar.startOfDay(for: date)
    }

    /// Returns the start-of-month `Date` for a given `Date` in the injected calendar's timezone.
    private static func startOfMonth(_ date: Date, calendar: Calendar) -> Date {
        let components = calendar.dateComponents([.year, .month], from: date)
        return calendar.date(from: components) ?? date
    }

    // MARK: - Per-range helpers

    /// Generates 7 daily `SpendBucket` slots for the rolling week ending today.
    private static func weekBuckets(
        expenses: [Expense],
        calendar: Calendar
    ) -> [SpendBucket] {
        let today = startOfDay(Date(), calendar: calendar)

        // Generate all 7 day slots: today-6 … today
        var slots: [Date] = []
        for offset in -6...0 {
            if let day = calendar.date(byAdding: .day, value: offset, to: today) {
                slots.append(day)
            }
        }

        // Accumulate Decimal totals per slot
        var totals: [Date: Decimal] = [:]
        for expense in expenses {
            let dayKey = startOfDay(expense.date, calendar: calendar)
            totals[dayKey, default: .zero] += expense.amount
        }

        // Map every slot to a SpendBucket (default .zero for empty slots — Pitfall C)
        return slots.map { day in
            let decimalSpent = totals[day] ?? .zero
            let doubleSpent = NSDecimalNumber(decimal: decimalSpent).doubleValue
            let label = day.formatted(.dateTime.weekday(.abbreviated).day())
            return SpendBucket(id: day, date: day, spent: doubleSpent, spentDecimal: decimalSpent, dateLabel: label)
        }
    }

    /// Generates one `SpendBucket` per day in the current calendar month (28–31 slots).
    private static func monthBuckets(
        expenses: [Expense],
        calendar: Calendar
    ) -> [SpendBucket] {
        let today = Date()
        let monthStart = startOfMonth(today, calendar: calendar)

        // Number of days in the current month
        let dayRange = calendar.range(of: .day, in: .month, for: today) ?? 1..<29
        let daysInMonth = dayRange.count

        // Generate all day slots for the month
        var slots: [Date] = []
        for offset in 0..<daysInMonth {
            if let day = calendar.date(byAdding: .day, value: offset, to: monthStart) {
                slots.append(day)
            }
        }

        // Accumulate Decimal totals per slot
        var totals: [Date: Decimal] = [:]
        for expense in expenses {
            let dayKey = startOfDay(expense.date, calendar: calendar)
            totals[dayKey, default: .zero] += expense.amount
        }

        return slots.map { day in
            let decimalSpent = totals[day] ?? .zero
            let doubleSpent = NSDecimalNumber(decimal: decimalSpent).doubleValue
            let label = day.formatted(.dateTime.month(.abbreviated).day())
            return SpendBucket(id: day, date: day, spent: doubleSpent, spentDecimal: decimalSpent, dateLabel: label)
        }
    }

    /// Generates 12 monthly `SpendBucket` slots for the current calendar year.
    private static func yearBuckets(
        expenses: [Expense],
        calendar: Calendar
    ) -> [SpendBucket] {
        let today = Date()
        let year = calendar.component(.year, from: today)

        // Generate all 12 month-start dates for this year
        var slots: [Date] = []
        for month in 1...12 {
            var components = DateComponents()
            components.year = year
            components.month = month
            components.day = 1
            if let monthStart = calendar.date(from: components) {
                slots.append(monthStart)
            }
        }

        // Accumulate Decimal totals keyed by start-of-month
        var totals: [Date: Decimal] = [:]
        for expense in expenses {
            let monthKey = startOfMonth(expense.date, calendar: calendar)
            totals[monthKey, default: .zero] += expense.amount
        }

        return slots.map { monthStart in
            let decimalSpent = totals[monthStart] ?? .zero
            let doubleSpent = NSDecimalNumber(decimal: decimalSpent).doubleValue
            let label = monthStart.formatted(.dateTime.month(.abbreviated))
            return SpendBucket(id: monthStart, date: monthStart, spent: doubleSpent, spentDecimal: decimalSpent, dateLabel: label)
        }
    }

    // MARK: - Public API

    /// Buckets the given expenses into the requested date range.
    ///
    /// - Parameters:
    ///   - expenses: Already-fetched expense array for the relevant period.
    ///   - range: `.week` (7 days), `.month` (all days this month), or `.year` (12 months).
    ///   - calendar: `Calendar` to use for bucketing; defaults to `.current` (device timezone).
    /// - Returns: Array of `SpendBucket` with **all** slots present, including zero-spend ones
    ///   (Pitfall C: never omit empty slots — chart would show gaps).
    static func bucket(
        expenses: [Expense],
        range: SpendRange,
        calendar: Calendar = .current
    ) -> [SpendBucket] {
        let spendable = expenses.filter { $0.isTransfer != true } // D-15: exclude confirmed self-transfers from spend chart
        switch range {
        case .week:  return weekBuckets(expenses: spendable, calendar: calendar)
        case .month: return monthBuckets(expenses: spendable, calendar: calendar)
        case .year:  return yearBuckets(expenses: spendable, calendar: calendar)
        }
    }
}
