import Testing
import Foundation
import SwiftData
@testable import MyHome

// Requirements: ANL-07 (IST midnight boundary), ANL-03 (bucketing delegation), ANL-05 (delta semantics)
// Validation command: xcodebuild test -scheme MyHome -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:MyHomeTests/AnalyticsAggregatorTests

// Disambiguation: Objective-C runtime also defines `Category`.
private typealias Cat = MyHome.Category

/// AnalyticsAggregatorTests — pure-logic tests for AnalyticsAggregator + SpendSummary.
///
/// ANL-07: IST-midnight boundary, year-range future-bucket filter, self-transfer exclusion, delta.
/// All tests that touch IST bucketing pass an explicit `Asia/Kolkata` calendar — never
/// depend on simulator's system timezone (Pitfall 1 / T-15-02).
@MainActor
struct AnalyticsAggregatorTests {

    // MARK: - Container

    private func makeContainer() throws -> ModelContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: Expense.self, Cat.self, configurations: config)
    }

    // MARK: - ANL-07: IST midnight boundary (required exit criterion)

    @Test("testMidnightISTBucketBoundary: 18:29Z and 18:31Z on the same UTC date land in different IST day buckets")
    func testMidnightISTBucketBoundary() throws {
        // UTC midnight for IST is 18:30 UTC.
        // 18:29Z = 23:59 IST on day D.
        // 18:31Z = 00:01 IST on day D+1 (crosses into next IST day).
        //
        // We use dates from within the last 2 days to fall inside the .week window
        // (today-6..today). We anchor to 2 days ago at 18:29 UTC and 18:31 UTC,
        // which always land within the rolling 7-day window regardless of today's date.
        var istCalendar = Calendar(identifier: .gregorian)
        istCalendar.timeZone = TimeZone(identifier: "Asia/Kolkata")!

        // Anchor: start-of-yesterday in UTC as a reference point.
        var utcCalendar = Calendar(identifier: .gregorian)
        utcCalendar.timeZone = TimeZone(identifier: "UTC")!

        // Use "2 days ago at 18:29 UTC" and "2 days ago at 18:31 UTC".
        // Both are on the same UTC date; IST flips to the next day at 18:30.
        let twoDaysAgoUTCStart = utcCalendar.date(
            byAdding: .day,
            value: -2,
            to: utcCalendar.startOfDay(for: Date())
        )!

        // 2 days ago at 18:29 UTC = 23:59 IST on that day
        let dayD_2359_IST = twoDaysAgoUTCStart.addingTimeInterval(18 * 3600 + 29 * 60)
        // 2 days ago at 18:31 UTC = 00:01 IST on the next IST day
        let dayD1_0001_IST = twoDaysAgoUTCStart.addingTimeInterval(18 * 3600 + 31 * 60)

        let container = try makeContainer()
        let e1 = Expense(amount: Decimal(100))
        e1.date = dayD_2359_IST
        let e2 = Expense(amount: Decimal(200))
        e2.date = dayD1_0001_IST
        container.mainContext.insert(e1)
        container.mainContext.insert(e2)

        // Use .week range so day-level bucketing is active.
        // The IST calendar is injected — bucketing must respect Asia/Kolkata timezone.
        let summary = AnalyticsAggregator.summarize(
            expenses: [e1, e2],
            categories: [],
            range: .week,
            calendar: istCalendar
        )

        // Both expenses must land in separate IST day buckets (non-zero spend on 2 distinct dates).
        let nonZeroBuckets = summary.trendBuckets.filter { $0.spent > 0 }
        #expect(nonZeroBuckets.count == 2, "Expected 2 non-zero buckets (one per IST day)")

        // Verify the bucket dates themselves differ by 1 IST day.
        if nonZeroBuckets.count == 2 {
            let days = nonZeroBuckets.map { istCalendar.dateComponents([.day, .month], from: $0.date) }
            #expect(days[0].day != days[1].day, "The two non-zero buckets must fall on different IST calendar days")
        }
    }

    // MARK: - ANL-07: Year range — no future zero-bars

    @Test("testYearNoFutureBuckets: .year range trendBuckets count <= current month number")
    func testYearNoFutureBuckets() throws {
        // Insert one expense this month so the bucket is non-trivially populated.
        let container = try makeContainer()
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Kolkata")!

        let today = Date()
        let e = Expense(amount: Decimal(500))
        e.date = today
        container.mainContext.insert(e)

        let summary = AnalyticsAggregator.summarize(
            expenses: [e],
            categories: [],
            range: .year,
            calendar: cal
        )

        let currentMonth = cal.component(.month, from: today)
        #expect(
            summary.trendBuckets.count <= currentMonth,
            "Year range must return at most current-month buckets (no future months)"
        )

        // No future month should appear.
        for bucket in summary.trendBuckets {
            let bucketMonth = cal.component(.month, from: bucket.date)
            #expect(bucketMonth <= currentMonth, "Bucket month must not exceed current month")
        }
    }

    // MARK: - ANL-07: Self-transfer exclusion

    @Test("testSelfTransferExclusion: expense with isTransfer == true excluded from totalSpend and all trendBuckets")
    func testSelfTransferExclusion() throws {
        let container = try makeContainer()
        let today = Date()
        let normalExpense = Expense(amount: Decimal(300))
        normalExpense.date = today
        normalExpense.isTransfer = false

        let transferExpense = Expense(amount: Decimal(50_000))
        transferExpense.date = today
        transferExpense.isTransfer = true   // confirmed transfer — must be excluded everywhere

        container.mainContext.insert(normalExpense)
        container.mainContext.insert(transferExpense)

        let summary = AnalyticsAggregator.summarize(
            expenses: [normalExpense, transferExpense],
            categories: [],
            range: .week
        )

        // Self-transfer must NOT appear in totalSpend.
        #expect(summary.totalSpend == Decimal(300), "totalSpend must exclude confirmed transfers")

        // Self-transfer must NOT appear in any trend bucket.
        let maxBucketSpent = summary.trendBuckets.map { $0.spentDecimal }.max() ?? .zero
        #expect(maxBucketSpent < Decimal(1_000), "No trend bucket should contain the 50,000 transfer amount")
    }

    // MARK: - ANL-07: Delta semantics

    @Test("testDelta: current spend > prior spend → positive delta and positive deltaFraction")
    func testDelta() throws {
        // Build two expenses: one in the current 7-day window, one in the prior 7-day window.
        // With .week range: current = today-6..today; prior = today-13..today-7.
        var cal = Calendar.current
        let today = cal.startOfDay(for: Date())

        let currentExpense = Expense(amount: Decimal(1000))
        currentExpense.date = today   // today = in current week window

        let priorDate = cal.date(byAdding: .day, value: -8, to: today)!  // 8 days ago = prior week
        let priorExpense = Expense(amount: Decimal(500))
        priorExpense.date = priorDate

        let container = try makeContainer()
        container.mainContext.insert(currentExpense)
        container.mainContext.insert(priorExpense)

        let summary = AnalyticsAggregator.summarize(
            expenses: [currentExpense, priorExpense],
            categories: [],
            range: .week,
            calendar: cal
        )

        // Current 1000 > prior 500 → delta = 500 (positive = spent MORE).
        #expect(summary.totalSpend == Decimal(1000), "totalSpend should be 1000")
        #expect(summary.priorTotalSpend == Decimal(500), "priorTotalSpend should be 500")
        #expect(summary.delta > 0, "delta should be positive when current > prior")
        #expect(summary.deltaFraction > 0, "deltaFraction should be positive when current > prior")

        // Approximate: delta / prior = 500 / 500 = 1.0 (100% increase)
        #expect(abs(summary.deltaFraction - 1.0) < 0.01, "deltaFraction should be approximately 1.0 (100% increase)")
    }

    @Test("testDeltaZeroGuard: deltaFraction == 0 when priorTotalSpend == 0 (zero-guard, Pitfall 7)")
    func testDeltaZeroGuard() throws {
        let today = Date()

        let e = Expense(amount: Decimal(500))
        e.date = today

        let container = try makeContainer()
        container.mainContext.insert(e)

        // Only current-period expense; prior period is empty → priorTotalSpend = 0.
        let summary = AnalyticsAggregator.summarize(
            expenses: [e],
            categories: [],
            range: .week
        )

        #expect(summary.priorTotalSpend == .zero, "priorTotalSpend should be 0 when no prior expenses")
        #expect(summary.deltaFraction == 0, "deltaFraction must be 0 (zero-guarded) when priorTotalSpend == 0")
    }
}
