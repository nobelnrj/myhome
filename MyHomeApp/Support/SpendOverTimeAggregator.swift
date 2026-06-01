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
    let spent: Double
    /// Accessibility / chart tooltip label for this date slot.
    var dateLabel: String
}

// MARK: - SpendOverTimeAggregator

/// Pure static helper for spend-over-time bucketing (EXP-11).
///
/// **Pure contract:** operates on already-fetched arrays; no SwiftData access,
/// no @Query, no SwiftUI, no Charts import. Mirrors the CalendarAggregator discipline.
///
/// Bucketing uses `Calendar.current` + `TimeZone.current` (device timezone) so displayed
/// dates match the user's clock (Pitfall 5 / T-04-02).
///
/// Money stays `Decimal` throughout the accumulation loop; the `Decimal → Double` conversion
/// happens only at `SpendBucket` construction via `NSDecimalNumber(decimal:).doubleValue`
/// (T-04-02 / Pitfall B guard).
enum SpendOverTimeAggregator {

    // MARK: - Private helpers

    /// Returns the start-of-day `Date` for a given `Date` in the device timezone.
    /// Copied verbatim from CalendarAggregator (device-timezone bucketing pattern).
    private static func startOfDay(_ date: Date, calendar: Calendar) -> Date {
        var cal = calendar
        cal.timeZone = TimeZone.current
        return cal.startOfDay(for: date)
    }

    /// Returns the start-of-month `Date` for a given `Date` in the device timezone.
    private static func startOfMonth(_ date: Date, calendar: Calendar) -> Date {
        var cal = calendar
        cal.timeZone = TimeZone.current
        let components = cal.dateComponents([.year, .month], from: date)
        return cal.date(from: components) ?? date
    }

    // MARK: - Per-range helpers

    /// Generates 7 daily `SpendBucket` slots for the rolling week ending today.
    private static func weekBuckets(
        expenses: [Expense],
        calendar: Calendar
    ) -> [SpendBucket] {
        var cal = calendar
        cal.timeZone = TimeZone.current

        let today = startOfDay(Date(), calendar: cal)

        // Generate all 7 day slots: today-6 … today
        var slots: [Date] = []
        for offset in -6...0 {
            if let day = cal.date(byAdding: .day, value: offset, to: today) {
                slots.append(day)
            }
        }

        // Accumulate Decimal totals per slot
        var totals: [Date: Decimal] = [:]
        for expense in expenses {
            let dayKey = startOfDay(expense.date, calendar: cal)
            totals[dayKey, default: .zero] += expense.amount
        }

        // Map every slot to a SpendBucket (default .zero for empty slots — Pitfall C)
        return slots.map { day in
            let decimalSpent = totals[day] ?? .zero
            let doubleSpent = NSDecimalNumber(decimal: decimalSpent).doubleValue
            let label = day.formatted(.dateTime.weekday(.abbreviated).day())
            return SpendBucket(id: day, date: day, spent: doubleSpent, dateLabel: label)
        }
    }

    /// Generates one `SpendBucket` per day in the current calendar month (28–31 slots).
    private static func monthBuckets(
        expenses: [Expense],
        calendar: Calendar
    ) -> [SpendBucket] {
        var cal = calendar
        cal.timeZone = TimeZone.current

        let today = Date()
        let monthStart = startOfMonth(today, calendar: cal)

        // Number of days in the current month
        let dayRange = cal.range(of: .day, in: .month, for: today) ?? 1..<29
        let daysInMonth = dayRange.count

        // Generate all day slots for the month
        var slots: [Date] = []
        for offset in 0..<daysInMonth {
            if let day = cal.date(byAdding: .day, value: offset, to: monthStart) {
                slots.append(day)
            }
        }

        // Accumulate Decimal totals per slot
        var totals: [Date: Decimal] = [:]
        for expense in expenses {
            let dayKey = startOfDay(expense.date, calendar: cal)
            totals[dayKey, default: .zero] += expense.amount
        }

        return slots.map { day in
            let decimalSpent = totals[day] ?? .zero
            let doubleSpent = NSDecimalNumber(decimal: decimalSpent).doubleValue
            let label = day.formatted(.dateTime.month(.abbreviated).day())
            return SpendBucket(id: day, date: day, spent: doubleSpent, dateLabel: label)
        }
    }

    /// Generates 12 monthly `SpendBucket` slots for the current calendar year.
    private static func yearBuckets(
        expenses: [Expense],
        calendar: Calendar
    ) -> [SpendBucket] {
        var cal = calendar
        cal.timeZone = TimeZone.current

        let today = Date()
        let year = cal.component(.year, from: today)

        // Generate all 12 month-start dates for this year
        var slots: [Date] = []
        for month in 1...12 {
            var components = DateComponents()
            components.year = year
            components.month = month
            components.day = 1
            if let monthStart = cal.date(from: components) {
                slots.append(monthStart)
            }
        }

        // Accumulate Decimal totals keyed by start-of-month
        var totals: [Date: Decimal] = [:]
        for expense in expenses {
            let monthKey = startOfMonth(expense.date, calendar: cal)
            totals[monthKey, default: .zero] += expense.amount
        }

        return slots.map { monthStart in
            let decimalSpent = totals[monthStart] ?? .zero
            let doubleSpent = NSDecimalNumber(decimal: decimalSpent).doubleValue
            let label = monthStart.formatted(.dateTime.month(.abbreviated))
            return SpendBucket(id: monthStart, date: monthStart, spent: doubleSpent, dateLabel: label)
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
        switch range {
        case .week:  return weekBuckets(expenses: expenses, calendar: calendar)
        case .month: return monthBuckets(expenses: expenses, calendar: calendar)
        case .year:  return yearBuckets(expenses: expenses, calendar: calendar)
        }
    }
}
