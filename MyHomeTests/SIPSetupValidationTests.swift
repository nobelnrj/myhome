import Testing
import Foundation
@testable import MyHome

/// Unit tests for SIPSetupView static pure functions:
/// - `validate(amount:dayOfMonth:isNPS:npsAllocationE:npsAllocationC:npsAllocationG:)` (T-114-01)
/// - `nextInstallmentDate(dayOfMonth:after:calendar:)` (D-07)
///
/// These tests run offline — no SwiftData container needed.
@Suite("SIPSetupValidationTests")
struct SIPSetupValidationTests {

    // MARK: - Helpers

    /// IST Gregorian calendar (matches SIPSetupView internals)
    private var istCal: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Kolkata")!
        return c
    }

    /// Build a Date at midnight IST for the given year, month, day.
    private func istDate(year: Int, month: Int, day: Int) -> Date {
        var comps = DateComponents()
        comps.year = year
        comps.month = month
        comps.day = day
        comps.hour = 0
        comps.minute = 0
        comps.second = 0
        comps.timeZone = TimeZone(identifier: "Asia/Kolkata")!
        return Calendar(identifier: .gregorian).date(from: comps)!
    }

    // MARK: - Validation tests (T-114-01)

    @Test("NPS SIP with E50/C30/G20 is valid")
    func npsAllocationSumsTo100IsValid() {
        let result = SIPSetupView.validate(
            amount: 5000,
            dayOfMonth: 10,
            isNPS: true,
            npsAllocationE: 50,
            npsAllocationC: 30,
            npsAllocationG: 20
        )
        #expect(result == true, "E50+C30+G20=100 should be valid for NPS SIP")
    }

    @Test("NPS SIP with E50/C30/G10 (sum=90) is rejected")
    func npsAllocationNotSumsTo100IsRejected() {
        let result = SIPSetupView.validate(
            amount: 5000,
            dayOfMonth: 10,
            isNPS: true,
            npsAllocationE: 50,
            npsAllocationC: 30,
            npsAllocationG: 10
        )
        #expect(result == false, "E50+C30+G10=90 should be rejected for NPS SIP")
    }

    @Test("Amount = 0 is rejected for any SIP type")
    func amountZeroIsRejected() {
        // MF SIP with amount 0
        let mfResult = SIPSetupView.validate(
            amount: 0,
            dayOfMonth: 5,
            isNPS: false,
            npsAllocationE: 0,
            npsAllocationC: 0,
            npsAllocationG: 0
        )
        #expect(mfResult == false, "Amount 0 should be rejected for MF SIP")

        // NPS SIP with amount 0
        let npsResult = SIPSetupView.validate(
            amount: 0,
            dayOfMonth: 5,
            isNPS: true,
            npsAllocationE: 50,
            npsAllocationC: 30,
            npsAllocationG: 20
        )
        #expect(npsResult == false, "Amount 0 should be rejected for NPS SIP")
    }

    @Test("dayOfMonth = 0 is rejected")
    func dayOfMonthZeroIsRejected() {
        let result = SIPSetupView.validate(
            amount: 5000,
            dayOfMonth: 0,
            isNPS: false,
            npsAllocationE: 0,
            npsAllocationC: 0,
            npsAllocationG: 0
        )
        #expect(result == false, "dayOfMonth 0 is out of range 1...31")
    }

    @Test("dayOfMonth = 32 is rejected")
    func dayOfMonth32IsRejected() {
        let result = SIPSetupView.validate(
            amount: 5000,
            dayOfMonth: 32,
            isNPS: false,
            npsAllocationE: 0,
            npsAllocationC: 0,
            npsAllocationG: 0
        )
        #expect(result == false, "dayOfMonth 32 is out of range 1...31")
    }

    @Test("MF SIP with amount > 0 and valid dayOfMonth is valid regardless of allocation")
    func mfSIPIgnoresNPSAllocation() {
        // MF SIPs do not require nps allocation to sum to 100
        let result = SIPSetupView.validate(
            amount: 3000,
            dayOfMonth: 15,
            isNPS: false,
            npsAllocationE: 0,
            npsAllocationC: 0,
            npsAllocationG: 0
        )
        #expect(result == true, "MF SIP should be valid regardless of allocation %, since isNPS is false")
    }

    @Test("MF SIP with allocation 50/0/0 is still valid (isNPS false)")
    func mfSIPWithPartialAllocationIsValid() {
        let result = SIPSetupView.validate(
            amount: 3000,
            dayOfMonth: 15,
            isNPS: false,
            npsAllocationE: 50,
            npsAllocationC: 0,
            npsAllocationG: 0
        )
        #expect(result == true, "MF SIP (isNPS=false) validates regardless of allocation values")
    }

    @Test("dayOfMonth = 1 and 31 are at the boundary and should be valid")
    func dayOfMonthBoundariesAreValid() {
        let day1 = SIPSetupView.validate(
            amount: 1000,
            dayOfMonth: 1,
            isNPS: false,
            npsAllocationE: 0,
            npsAllocationC: 0,
            npsAllocationG: 0
        )
        let day31 = SIPSetupView.validate(
            amount: 1000,
            dayOfMonth: 31,
            isNPS: false,
            npsAllocationE: 0,
            npsAllocationC: 0,
            npsAllocationG: 0
        )
        #expect(day1 == true, "dayOfMonth 1 is valid")
        #expect(day31 == true, "dayOfMonth 31 is valid")
    }

    // MARK: - nextInstallmentDate tests (D-07)

    @Test("nextInstallmentDate: dayOfMonth 5 after 2026-06-12 returns 2026-07-05")
    func nextInstallmentAfterToday_dayInFuture_pastCurrentMonthDay() {
        let ref = istDate(year: 2026, month: 6, day: 12)
        let next = SIPSetupView.nextInstallmentDate(dayOfMonth: 5, after: ref, calendar: istCal)
        let expected = istDate(year: 2026, month: 7, day: 5)
        #expect(next == expected, "dayOfMonth 5, after 2026-06-12 should yield 2026-07-05 (day 5 already passed in June)")
    }

    @Test("nextInstallmentDate: dayOfMonth 20 after 2026-06-12 returns 2026-06-20")
    func nextInstallmentAfterToday_dayInCurrentMonth() {
        let ref = istDate(year: 2026, month: 6, day: 12)
        let next = SIPSetupView.nextInstallmentDate(dayOfMonth: 20, after: ref, calendar: istCal)
        let expected = istDate(year: 2026, month: 6, day: 20)
        #expect(next == expected, "dayOfMonth 20, after 2026-06-12 should yield 2026-06-20 (still in June)")
    }

    @Test("nextInstallmentDate: dayOfMonth 12 after 2026-06-12 (exact same day, not strictly after) returns 2026-07-12")
    func nextInstallmentAfterToday_exactSameDay_returnsNextMonth() {
        let ref = istDate(year: 2026, month: 6, day: 12)
        let next = SIPSetupView.nextInstallmentDate(dayOfMonth: 12, after: ref, calendar: istCal)
        let expected = istDate(year: 2026, month: 7, day: 12)
        #expect(next == expected, "dayOfMonth 12 on exact same date as reference (not strictly after) should return next month")
    }

    @Test("nextInstallmentDate: dayOfMonth 31 in January reference returns 2026-01-31")
    func nextInstallmentDate_day31_inJanuary() {
        // Reference is 2026-01-15; dayOfMonth 31 — January has 31 days, so 2026-01-31
        let ref = istDate(year: 2026, month: 1, day: 15)
        let next = SIPSetupView.nextInstallmentDate(dayOfMonth: 31, after: ref, calendar: istCal)
        let expected = istDate(year: 2026, month: 1, day: 31)
        #expect(next == expected, "dayOfMonth 31 after 2026-01-15 should return 2026-01-31 (Jan has 31 days)")
    }

    @Test("nextInstallmentDate: dayOfMonth 31 in February reference clamps to Feb 28")
    func nextInstallmentDate_day31_inFebruary_clamps() {
        // Reference is 2026-02-01 (non-leap year — Feb has 28 days)
        let ref = istDate(year: 2026, month: 2, day: 1)
        let next = SIPSetupView.nextInstallmentDate(dayOfMonth: 31, after: ref, calendar: istCal)
        let expected = istDate(year: 2026, month: 2, day: 28)
        #expect(next == expected, "dayOfMonth 31 in Feb 2026 (non-leap) should clamp to Feb 28")
    }

    @Test("nextInstallmentDate: dayOfMonth 31 in leap-year February clamps to Feb 29")
    func nextInstallmentDate_day31_inLeapYearFebruary_clamps() {
        // Reference is 2028-02-01 (2028 is a leap year — Feb has 29 days)
        let ref = istDate(year: 2028, month: 2, day: 1)
        let next = SIPSetupView.nextInstallmentDate(dayOfMonth: 31, after: ref, calendar: istCal)
        let expected = istDate(year: 2028, month: 2, day: 29)
        #expect(next == expected, "dayOfMonth 31 in Feb 2028 (leap year) should clamp to Feb 29")
    }

    @Test("nextInstallmentDate: result is always strictly after reference")
    func nextInstallmentDateIsAlwaysStrictlyAfterReference() {
        let ref = istDate(year: 2026, month: 6, day: 12)
        for day in [1, 5, 10, 12, 15, 20, 28, 29, 30, 31] {
            let next = SIPSetupView.nextInstallmentDate(dayOfMonth: day, after: ref, calendar: istCal)
            #expect(next > ref, "nextInstallmentDate(dayOfMonth: \(day)) must be strictly after reference")
        }
    }
}
