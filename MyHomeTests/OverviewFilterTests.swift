import Testing
import SwiftData
import Foundation
@testable import MyHome

// Requirements: OVF-01 (empty selection = all accounts default; subset filters),
//               OVF-02 (account × custom-date-range totals with self-transfer exclusion preserved)
// Validation: xcodebuild test -scheme MyHome -destination 'platform=iOS Simulator,name=iPhone 17' \
//             -only-testing:MyHomeTests/OverviewFilterTests

// Disambiguation: the Objective-C runtime also defines `Category`.
private typealias Cat = MyHome.Category

/// OverviewFilterTests — pure-logic tests for `OverviewFilterEngine` (Plan 21-01).
///
/// Proves the OVF-01 all-accounts default, account-subset / includeUnassigned filtering,
/// preservation of the self-transfer exclusion when totals route through
/// `BudgetCalculator.grossSpend`/`grossIncome`, account × custom-date-range aggregation,
/// and inclusive day-granular range boundaries on an injected Asia/Kolkata (IST) calendar.
///
/// Decimal footgun (memory: decimal-literal-comparison-footgun): every money assertion
/// compares against `Decimal(N)` constructors, never bare arithmetic literals.
@MainActor
struct OverviewFilterTests {

    // MARK: - Container

    private func makeContainer() throws -> ModelContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: Expense.self, Cat.self, Account.self,
                                  configurations: config)
    }

    // MARK: - Helpers

    /// Asia/Kolkata (IST, UTC+5:30) calendar so date-edge tests never depend on the
    /// simulator timezone (mirrors the AnalyticsAggregator injection pattern).
    private func istCalendar() -> Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Kolkata")!
        return cal
    }

    /// Build a specific instant in IST from Y/M/D + optional time-of-day.
    private func istDate(
        _ cal: Calendar,
        year: Int, month: Int, day: Int,
        hour: Int = 0, minute: Int = 0, second: Int = 0
    ) -> Date {
        var comps = DateComponents()
        comps.year = year; comps.month = month; comps.day = day
        comps.hour = hour; comps.minute = minute; comps.second = second
        return cal.date(from: comps)!
    }

    @discardableResult
    private func makeAccount(_ context: ModelContext, name: String) -> Account {
        let account = Account(name: name)
        context.insert(account)
        return account
    }

    @discardableResult
    private func makeExpense(
        _ context: ModelContext,
        amount: Decimal,
        accountID: UUID?,
        date: Date = Date(),
        isTransfer: Bool? = nil,
        transferPairID: UUID? = nil
    ) -> Expense {
        let expense = Expense(amount: amount, date: date)
        expense.accountID = accountID
        expense.isTransfer = isTransfer
        expense.transferPairID = transferPairID
        context.insert(expense)
        return expense
    }

    // MARK: - OVF-01: default filter passes everything (incl. unassigned)

    @Test("defaultFilterMatchesAll: default OverviewFilter passes assigned AND nil-accountID expenses")
    func defaultFilterMatchesAll() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let accountA = makeAccount(context, name: "HDFC")

        let assigned = makeExpense(context, amount: Decimal(100), accountID: accountA.id)
        let unassigned = makeExpense(context, amount: Decimal(200), accountID: nil)
        try context.save()

        let filter = OverviewFilter()  // all-accounts default
        #expect(filter.isActive == false)
        #expect(filter.accountFilterActive == false)

        let result = OverviewFilterEngine.apply(filter, to: [assigned, unassigned])
        #expect(result.count == 2, "Default filter must pass every expense including nil-accountID rows")
    }

    // MARK: - OVF-01: single-account subset

    @Test("singleAccountSubset: accountIDs = {A} passes only A; B and unassigned excluded")
    func singleAccountSubset() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let accountA = makeAccount(context, name: "HDFC")
        let accountB = makeAccount(context, name: "ICICI")

        let a = makeExpense(context, amount: Decimal(100), accountID: accountA.id)
        let b = makeExpense(context, amount: Decimal(200), accountID: accountB.id)
        let unassigned = makeExpense(context, amount: Decimal(300), accountID: nil)
        try context.save()

        var filter = OverviewFilter()
        filter.accountIDs = [accountA.id]
        #expect(filter.accountFilterActive == true)
        #expect(filter.isActive == true)

        let result = OverviewFilterEngine.apply(filter, to: [a, b, unassigned])
        #expect(result.count == 1)
        #expect(result.first?.accountID == accountA.id)
    }

    // MARK: - OVF-01: multi-account subset

    @Test("multiAccountSubset: accountIDs = {A, B} passes A and B; C and unassigned excluded")
    func multiAccountSubset() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let accountA = makeAccount(context, name: "HDFC")
        let accountB = makeAccount(context, name: "ICICI")
        let accountC = makeAccount(context, name: "SBI")

        let a = makeExpense(context, amount: Decimal(100), accountID: accountA.id)
        let b = makeExpense(context, amount: Decimal(200), accountID: accountB.id)
        let c = makeExpense(context, amount: Decimal(300), accountID: accountC.id)
        let unassigned = makeExpense(context, amount: Decimal(400), accountID: nil)
        try context.save()

        var filter = OverviewFilter()
        filter.accountIDs = [accountA.id, accountB.id]

        let result = OverviewFilterEngine.apply(filter, to: [a, b, c, unassigned])
        let ids = Set(result.compactMap { $0.accountID })
        #expect(result.count == 2)
        #expect(ids == [accountA.id, accountB.id])
    }

    // MARK: - OVF-01: includeUnassigned

    @Test("includeUnassigned: accountIDs = {A} + includeUnassigned passes A's rows AND nil-accountID rows")
    func includeUnassigned() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let accountA = makeAccount(context, name: "HDFC")
        let accountB = makeAccount(context, name: "ICICI")

        let a = makeExpense(context, amount: Decimal(100), accountID: accountA.id)
        let b = makeExpense(context, amount: Decimal(200), accountID: accountB.id)
        let unassigned = makeExpense(context, amount: Decimal(300), accountID: nil)
        try context.save()

        var filter = OverviewFilter()
        filter.accountIDs = [accountA.id]
        filter.includeUnassigned = true

        let result = OverviewFilterEngine.apply(filter, to: [a, b, unassigned])
        #expect(result.count == 2, "A's rows + unassigned rows survive; B excluded")
        #expect(result.contains { $0.accountID == accountA.id })
        #expect(result.contains { $0.accountID == nil })
        #expect(!result.contains { $0.accountID == accountB.id })
    }

    // MARK: - OVF-02 / T-21-02: transfer exclusion survives filtering

    @Test("transferExclusionPreserved: grossSpend/grossIncome over apply() still excludes confirmed + pending pairs")
    func transferExclusionPreserved() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let accountA = makeAccount(context, name: "HDFC")

        // Spend legs (positive amounts), all on account A:
        let confirmedSpend = makeExpense(context, amount: Decimal(1000), accountID: accountA.id,
                                         isTransfer: true)                       // excluded
        let pendingSpend = makeExpense(context, amount: Decimal(2000), accountID: accountA.id,
                                       isTransfer: nil, transferPairID: UUID())  // excluded
        let rejectedSpend = makeExpense(context, amount: Decimal(500), accountID: accountA.id,
                                        isTransfer: false)                        // included (real spend)
        let normalSpend = makeExpense(context, amount: Decimal(300), accountID: accountA.id) // included

        // Income legs (negative amounts), on account A:
        let normalIncome = makeExpense(context, amount: Decimal(-400), accountID: accountA.id) // included
        let confirmedIncome = makeExpense(context, amount: Decimal(-700), accountID: accountA.id,
                                          isTransfer: true)                       // excluded
        try context.save()

        var filter = OverviewFilter()
        filter.accountIDs = [accountA.id]

        let filtered = OverviewFilterEngine.apply(filter, to: [
            confirmedSpend, pendingSpend, rejectedSpend, normalSpend, normalIncome, confirmedIncome,
        ])

        // grossSpend: 500 (rejected) + 300 (normal) — confirmed + pending excluded.
        #expect(BudgetCalculator.grossSpend(for: filtered) == Decimal(800))
        // grossIncome: 400 (normal) — confirmed transfer income excluded.
        #expect(BudgetCalculator.grossIncome(for: filtered) == Decimal(400))
    }

    // MARK: - OVF-02: account × date-range cell total

    @Test("accountTimesDateRange: apply account filter + rangeBoundaries window → grossSpend for exactly that cell")
    func accountTimesDateRange() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let cal = istCalendar()
        let accountA = makeAccount(context, name: "HDFC")
        let accountB = makeAccount(context, name: "ICICI")

        // Account A: two inside the Jul 1–15 window, one outside (Jul 20).
        let aInside1 = makeExpense(context, amount: Decimal(1000), accountID: accountA.id,
                                   date: istDate(cal, year: 2026, month: 7, day: 5))
        let aInside2 = makeExpense(context, amount: Decimal(2000), accountID: accountA.id,
                                   date: istDate(cal, year: 2026, month: 7, day: 10))
        let aOutside = makeExpense(context, amount: Decimal(500), accountID: accountA.id,
                                   date: istDate(cal, year: 2026, month: 7, day: 20))
        // Account B inside the window but excluded by the account filter.
        let bInside = makeExpense(context, amount: Decimal(9999), accountID: accountB.id,
                                  date: istDate(cal, year: 2026, month: 7, day: 8))
        try context.save()

        var filter = OverviewFilter()
        filter.accountIDs = [accountA.id]

        let accountFiltered = OverviewFilterEngine.apply(filter, to: [aInside1, aInside2, aOutside, bInside])

        let (start, end) = OverviewFilterEngine.rangeBoundaries(
            from: istDate(cal, year: 2026, month: 7, day: 1),
            to: istDate(cal, year: 2026, month: 7, day: 15),
            calendar: cal
        )
        let cell = accountFiltered.filter { $0.date >= start && $0.date <= end }

        // Only Jul 5 (1000) + Jul 10 (2000) for account A survive both dimensions.
        #expect(BudgetCalculator.grossSpend(for: cell) == Decimal(3000))
    }

    // MARK: - T-21-01: inclusive boundaries on injected IST calendar

    @Test("rangeBoundariesInclusiveIST: start-day 00:00 and end-day 23:59 are inside; day-after-end is outside")
    func rangeBoundariesInclusiveIST() throws {
        let cal = istCalendar()
        let (start, end) = OverviewFilterEngine.rangeBoundaries(
            from: istDate(cal, year: 2026, month: 7, day: 10),
            to: istDate(cal, year: 2026, month: 7, day: 12),
            calendar: cal
        )

        let startEdge = istDate(cal, year: 2026, month: 7, day: 10, hour: 0, minute: 0, second: 0)
        let endEdge = istDate(cal, year: 2026, month: 7, day: 12, hour: 23, minute: 59, second: 0)
        let dayAfter = istDate(cal, year: 2026, month: 7, day: 13, hour: 0, minute: 0, second: 0)

        #expect(startEdge >= start && startEdge <= end, "00:00 IST on the start day is inside [start, end]")
        #expect(endEdge >= start && endEdge <= end, "23:59 IST on the end day is inside [start, end]")
        #expect(!(dayAfter >= start && dayAfter <= end), "00:00 IST the day after end is outside [start, end]")
    }

    // MARK: - T-21-01: from > to swapped, not crashed/empty

    @Test("rangeBoundariesSwapped: from > to is swapped into a valid ascending window")
    func rangeBoundariesSwapped() throws {
        let cal = istCalendar()
        let (start, end) = OverviewFilterEngine.rangeBoundaries(
            from: istDate(cal, year: 2026, month: 7, day: 12),   // later
            to: istDate(cal, year: 2026, month: 7, day: 10),     // earlier
            calendar: cal
        )

        #expect(start < end, "Swapped range must still yield start < end, not an empty/negative window")
        let expectedStart = cal.startOfDay(for: istDate(cal, year: 2026, month: 7, day: 10))
        #expect(start == expectedStart, "start must clamp to start-of-day of the earlier date (Jul 10)")

        // A Jul 11 instant lands inside the swapped-and-corrected window.
        let midpoint = istDate(cal, year: 2026, month: 7, day: 11, hour: 12)
        #expect(midpoint >= start && midpoint <= end)
    }

    // MARK: - WR-01 / WR-02: shared range label discloses the from-side year across years

    @Test("rangeLabelCrossYearShowsBothYears: a range spanning a year boundary discloses BOTH years")
    func rangeLabelCrossYearShowsBothYears() throws {
        let cal = istCalendar()
        let from = istDate(cal, year: 2025, month: 12, day: 5)
        let to = istDate(cal, year: 2026, month: 1, day: 12)

        let label = OverviewFilterEngine.rangeLabel(from: from, to: to, calendar: cal)

        #expect(label.contains("2025"), "cross-year label must disclose the from-side (2025) year")
        #expect(label.contains("2026"), "cross-year label must disclose the to-side (2026) year")
    }

    @Test("rangeLabelSameYearOmitsFromYear: a same-year range shows the year once (to-side only)")
    func rangeLabelSameYearOmitsFromYear() throws {
        let cal = istCalendar()
        let from = istDate(cal, year: 2026, month: 6, day: 5)
        let to = istDate(cal, year: 2026, month: 7, day: 12)

        let label = OverviewFilterEngine.rangeLabel(from: from, to: to, calendar: cal)

        let yearOccurrences = label.components(separatedBy: "2026").count - 1
        #expect(yearOccurrences == 1, "same-year label must show the year exactly once (redundant from-year dropped)")
    }
}
