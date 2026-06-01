import Testing
import Foundation
import SwiftData
@testable import MyHome

// Requirements: EXP-11 (bucketing: week/month/year, zero-spend slots, Decimal→Double boundary)
// Validation command: xcodebuild test -scheme MyHome -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:MyHomeTests/SpendOverTimeAggregatorTests

// Disambiguation: Objective-C runtime also defines `Category`.
private typealias Cat = MyHome.Category

/// SpendOverTimeAggregatorTests — pure-logic tests for spend bucketing.
///
/// EXP-11: spend-over-time chart across configurable date ranges.
/// Exercised API (NOT YET WRITTEN — RED state):
///   - `SpendOverTimeAggregator.bucket(expenses:range:calendar:) -> [SpendBucket]`
///   - `SpendRange` enum: `.week`, `.month`, `.year`
///   - `SpendBucket`: `id: Date`, `date: Date`, `spent: Double`, `dateLabel: String`
///
/// These symbols do NOT exist until Plan 04-02. This file is expected to fail to compile/run
/// (RED) until the production helpers are written.
@MainActor
struct SpendOverTimeAggregatorTests {

    // MARK: - Container

    private func makeContainer() throws -> ModelContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: Expense.self, Cat.self, configurations: config)
    }

    // MARK: - Helper: insert an expense on a given date

    private func insertExpense(
        amount: Decimal,
        on date: Date,
        context: ModelContext
    ) throws -> Expense {
        let expense = Expense(amount: amount)
        expense.date = date
        context.insert(expense)
        return expense
    }

    // MARK: - EXP-11 Week range → exactly 7 daily buckets

    @Test("weekBucketCount: week range returns exactly 7 SpendBucket entries (one per day)")
    func weekBucketCount() throws {
        let container = try makeContainer()
        let context = container.mainContext

        // Insert one expense today so the range is not completely empty.
        var cal = Calendar.current
        cal.timeZone = TimeZone.current
        let today = cal.startOfDay(for: Date())
        let expense = try insertExpense(amount: Decimal(200), on: today, context: context)
        try context.save()

        let buckets = SpendOverTimeAggregator.bucket(
            expenses: [expense],
            range: SpendRange.week,
            calendar: cal
        )

        #expect(buckets.count == 7,
                "Week range must produce exactly 7 daily buckets, got \(buckets.count)")
    }

    // MARK: - EXP-11 Month range → 28–31 daily buckets

    @Test("monthBucketCount: month range returns 28-31 SpendBucket entries (all days in current month)")
    func monthBucketCount() throws {
        let container = try makeContainer()
        let context = container.mainContext

        var cal = Calendar.current
        cal.timeZone = TimeZone.current
        let today = Date()

        // Determine how many days are in the current month for the assertion range.
        let range = cal.range(of: .day, in: .month, for: today)!
        let daysInMonth = range.count  // 28, 29, 30, or 31

        // Insert no expenses — zero-spend month.
        let buckets = SpendOverTimeAggregator.bucket(
            expenses: [],
            range: SpendRange.month,
            calendar: cal
        )

        #expect(buckets.count == daysInMonth,
                "Month range must produce \(daysInMonth) daily buckets for the current month, got \(buckets.count)")
    }

    // MARK: - EXP-11 Year range → exactly 12 monthly buckets

    @Test("yearBucketCount: year range returns exactly 12 SpendBucket entries (one per month)")
    func yearBucketCount() throws {
        var cal = Calendar.current
        cal.timeZone = TimeZone.current

        let buckets = SpendOverTimeAggregator.bucket(
            expenses: [],
            range: SpendRange.year,
            calendar: cal
        )

        #expect(buckets.count == 12,
                "Year range must produce exactly 12 monthly buckets, got \(buckets.count)")
    }

    // MARK: - EXP-11 Zero-spend scenario: all buckets present with spent == 0.0 (Pitfall C)

    @Test("zeroSpendWeek: empty expense array → all 7 buckets present with spent == 0.0 (no omitted slots)")
    func zeroSpendWeek() throws {
        var cal = Calendar.current
        cal.timeZone = TimeZone.current

        let buckets = SpendOverTimeAggregator.bucket(
            expenses: [],
            range: SpendRange.week,
            calendar: cal
        )

        // All slots must be present (count == 7).
        #expect(buckets.count == 7,
                "Zero-spend week must still have 7 buckets — no slots omitted (Pitfall C)")

        // Every bucket must have spent == 0.0.
        let allZero = buckets.allSatisfy { $0.spent == 0.0 }
        #expect(allZero,
                "All buckets in a zero-spend week must have spent == 0.0")
    }

    @Test("zeroSpendYear: empty expense array → all 12 monthly buckets present with spent == 0.0")
    func zeroSpendYear() throws {
        var cal = Calendar.current
        cal.timeZone = TimeZone.current

        let buckets = SpendOverTimeAggregator.bucket(
            expenses: [],
            range: SpendRange.year,
            calendar: cal
        )

        #expect(buckets.count == 12,
                "Zero-spend year must still have 12 buckets — no slots omitted (Pitfall C)")

        let allZero = buckets.allSatisfy { $0.spent == 0.0 }
        #expect(allZero,
                "All buckets in a zero-spend year must have spent == 0.0")
    }

    // MARK: - EXP-11 Decimal→Double boundary (no money rounding error in display)

    @Test("decimalDoubleBoundary: Decimal(1234.56) on one day produces bucket with spent ≈ 1234.56")
    func decimalDoubleBoundary() throws {
        let container = try makeContainer()
        let context = container.mainContext

        var cal = Calendar.current
        cal.timeZone = TimeZone.current
        let today = cal.startOfDay(for: Date())

        let expense = try insertExpense(amount: Decimal(1234.56), on: today, context: context)
        try context.save()

        let buckets = SpendOverTimeAggregator.bucket(
            expenses: [expense],
            range: SpendRange.week,
            calendar: cal
        )

        // Find today's bucket.
        guard let todayBucket = buckets.first(where: { cal.isDate($0.date, inSameDayAs: today) }) else {
            Issue.record("Today's bucket must be present in the week range")
            return
        }

        // Allow a small tolerance window for Decimal→Double conversion.
        let tolerance = 0.01
        #expect(
            abs(todayBucket.spent - 1234.56) < tolerance,
            "Decimal(1234.56) should convert to Double ≈ 1234.56, got \(todayBucket.spent)"
        )
    }

    // MARK: - EXP-11 Refund handling: negative expense reduces the day's bucket

    @Test("refundReducesBucket: negative-amount expense reduces the bucket for that day")
    func refundReducesBucket() throws {
        let container = try makeContainer()
        let context = container.mainContext

        var cal = Calendar.current
        cal.timeZone = TimeZone.current
        let today = cal.startOfDay(for: Date())

        let expense1 = try insertExpense(amount: Decimal(500), on: today, context: context)
        let expense2 = try insertExpense(amount: Decimal(-200), on: today, context: context)  // refund
        try context.save()

        let buckets = SpendOverTimeAggregator.bucket(
            expenses: [expense1, expense2],
            range: SpendRange.week,
            calendar: cal
        )

        guard let todayBucket = buckets.first(where: { cal.isDate($0.date, inSameDayAs: today) }) else {
            Issue.record("Today's bucket must be present after inserting expenses")
            return
        }

        // 500 - 200 = 300 net spend (or 0 if clamped; either is acceptable per contract).
        // The key assertion is that the refund is NOT ignored: spent != 500.
        let tolerance = 0.01
        let netSpend = 300.0
        #expect(
            abs(todayBucket.spent - netSpend) < tolerance || todayBucket.spent == 0.0,
            "Refund should reduce bucket: expected ≈ 300 (or 0 if clamped), got \(todayBucket.spent)"
        )
    }
}
