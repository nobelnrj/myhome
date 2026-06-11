import Testing
import Foundation
@testable import MyHome

/// Staleness badge logic tests — verifies IST calendar-day threshold (ASSET-09, D-10).
///
/// All tests use a fixed reference date to be deterministic — no dependency on `Date()` at
/// test-runtime. The IST boundary is computed explicitly in each test.
///
/// Threshold: navAsOfDate is stale when diff (in IST calendar days) > 1.
///   today (diff 0) → not stale
///   yesterday (diff 1) → not stale
///   2 days ago (diff 2) → stale
///   nil → not stale (badge hidden)
struct StalenessBadgeTests {

    // Reference date: 2026-06-11T09:00:00 UTC (which is 2026-06-11T14:30:00 IST — mid-afternoon)
    private static let referenceDate: Date = {
        var components = DateComponents()
        components.year = 2026
        components.month = 6
        components.day = 11
        components.hour = 9
        components.minute = 0
        components.second = 0
        components.timeZone = TimeZone(identifier: "UTC")
        return Calendar(identifier: .gregorian).date(from: components)!
    }()

    // IST calendar for computing day boundaries
    private var istCalendar: Calendar = {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Kolkata")!
        return cal
    }()

    // Helper: a Date representing "N full IST days before referenceDate's IST start-of-day"
    private func dateNDaysBeforeReference(_ n: Int) -> Date {
        let startOfTodayIST = istCalendar.startOfDay(for: Self.referenceDate)
        return startOfTodayIST.addingTimeInterval(TimeInterval(-n * 86400))
    }

    @Test("navAsOfDate == today (diff 0) → not stale")
    func todayDateIsNotStale() {
        // Start-of-today in IST (diff = 0)
        let today = dateNDaysBeforeReference(0)
        let isStale = AssetValuation.isStale(navAsOfDate: today, referenceDate: Self.referenceDate)
        #expect(!isStale, "navAsOfDate equal to today IST start-of-day must NOT be stale (diff = 0)")
    }

    @Test("navAsOfDate == yesterday (diff 1) → not stale")
    func yesterdayDateIsNotStale() {
        let yesterday = dateNDaysBeforeReference(1)
        let isStale = AssetValuation.isStale(navAsOfDate: yesterday, referenceDate: Self.referenceDate)
        #expect(!isStale, "navAsOfDate 1 day before today IST must NOT be stale (diff = 1, threshold > 1)")
    }

    @Test("navAsOfDate == 2 days ago (diff 2) → stale")
    func twoDaysAgoIsStale() {
        let twoDaysAgo = dateNDaysBeforeReference(2)
        let isStale = AssetValuation.isStale(navAsOfDate: twoDaysAgo, referenceDate: Self.referenceDate)
        #expect(isStale, "navAsOfDate 2 days before today IST must be stale (diff = 2 > 1)")
    }

    @Test("navAsOfDate == nil → not stale (badge hidden)")
    func nilDateIsNotStale() {
        let isStale = AssetValuation.isStale(navAsOfDate: nil, referenceDate: Self.referenceDate)
        #expect(!isStale, "nil navAsOfDate must NOT be stale (badge stays hidden — price not yet set)")
    }

    @Test("navAsOfDate == 10 days ago → stale")
    func tenDaysAgoIsStale() {
        let tenDaysAgo = dateNDaysBeforeReference(10)
        let isStale = AssetValuation.isStale(navAsOfDate: tenDaysAgo, referenceDate: Self.referenceDate)
        #expect(isStale, "navAsOfDate 10 days before today must be stale")
    }
}
