import Testing
import SwiftData
import Foundation
@testable import MyHome

/// Tests for AccountBalance.compute() — the live balance formula (ACCT-05, D-09, D-10).
///
/// These tests verify the pure formula in isolation; no SwiftUI is involved.
@MainActor
struct AccountBalanceTests {

    private func makeContainer() throws -> ModelContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: Account.self, Expense.self, configurations: config)
    }

    // MARK: - liveBalance = baseline − net of attributed expenses dated on/after asOf
    //
    // App-wide sign convention: a SPEND is stored POSITIVE, a REFUND negative.
    // A spend reduces a positive savings balance, so the formula SUBTRACTS the net.

    @Test("liveBalance equals baseline minus net of attributed post-asOf spends (pre-asOf excluded)")
    func liveBalanceEqualsBaselineMinusNet() throws {
        let container = try makeContainer()
        let ctx = container.mainContext

        let account = Account(name: "Test Savings")
        account.id = UUID()
        ctx.insert(account)

        let asOf = Calendar.current.date(from: DateComponents(year: 2026, month: 1, day: 1))!

        // After asOf: spends of 200 and 50 (positive = spend; both included)
        let e1 = Expense(amount: Decimal(200))
        e1.date = Calendar.current.date(from: DateComponents(year: 2026, month: 2, day: 1))!
        e1.accountID = account.id
        ctx.insert(e1)

        let e2 = Expense(amount: Decimal(50))
        e2.date = Calendar.current.date(from: DateComponents(year: 2026, month: 3, day: 1))!
        e2.accountID = account.id
        ctx.insert(e2)

        // Before asOf: spend of 999 (must be excluded)
        let e3 = Expense(amount: Decimal(999))
        e3.date = Calendar.current.date(from: DateComponents(year: 2025, month: 12, day: 1))!
        e3.accountID = account.id
        ctx.insert(e3)

        try ctx.save()

        let allExpenses = try ctx.fetch(FetchDescriptor<Expense>())

        let balance = AccountBalance.compute(
            baseline: Decimal(1000),
            asOf: asOf,
            expenses: allExpenses,
            accountID: account.id
        )

        // 1000 − (200 + 50) = 750 (the 999 before asOf is excluded). Spends reduce savings.
        #expect(balance == Decimal(750), "Expected 750 but got \(balance)")
    }

    // MARK: - savings: a spend DECREASES the balance, a refund INCREASES it (RESEARCH-A3 regression)

    @Test("savingsSpendDecreasesRefundIncreases: spend(+500) lowers, refund(−200) raises a savings baseline")
    func savingsSpendDecreasesRefundIncreases() throws {
        let container = try makeContainer()
        let ctx = container.mainContext

        let account = Account(name: "ICICI Savings")
        account.id = UUID()
        ctx.insert(account)

        let asOf = Calendar.current.date(from: DateComponents(year: 2026, month: 1, day: 1))!

        let spend = Expense(amount: Decimal(500))   // positive = spend
        spend.date = Calendar.current.date(from: DateComponents(year: 2026, month: 2, day: 1))!
        spend.accountID = account.id
        ctx.insert(spend)

        let refund = Expense(amount: Decimal(-200)) // negative = refund/inflow
        refund.date = Calendar.current.date(from: DateComponents(year: 2026, month: 2, day: 5))!
        refund.accountID = account.id
        ctx.insert(refund)

        try ctx.save()
        let allExpenses = try ctx.fetch(FetchDescriptor<Expense>())

        let balance = AccountBalance.compute(
            baseline: Decimal(10000),
            asOf: asOf,
            expenses: allExpenses,
            accountID: account.id
        )

        // 10000 − (500 + (−200)) = 10000 − 300 = 9700. Spend lowered it; refund partly offset.
        #expect(balance == Decimal(9700), "Expected 9700 but got \(balance)")
    }

    // MARK: - credit card: negative baseline goes more negative as you spend (D-09)

    @Test("creditCardIsNegative: CC baseline -5000 + spend(+1000) yields -6000 owed (D-09)")
    func creditCardIsNegative() throws {
        let container = try makeContainer()
        let ctx = container.mainContext

        let account = Account(name: "HDFC CC", typeRaw: "credit_card")
        account.id = UUID()
        ctx.insert(account)

        let asOf = Calendar.current.date(from: DateComponents(year: 2026, month: 1, day: 1))!

        let expense = Expense(amount: Decimal(1000)) // positive = spend
        expense.date = Calendar.current.date(from: DateComponents(year: 2026, month: 2, day: 1))!
        expense.accountID = account.id
        ctx.insert(expense)

        try ctx.save()

        let allExpenses = try ctx.fetch(FetchDescriptor<Expense>())

        let balance = AccountBalance.compute(
            baseline: Decimal(-5000),
            asOf: asOf,
            expenses: allExpenses,
            accountID: account.id
        )

        // -5000 − (1000) = -6000 (a CC spend increases amount owed)
        #expect(balance == Decimal(-6000), "Expected -6000 but got \(balance)")
    }

    // MARK: - nil baseline yields 0

    @Test("nilBaselineYieldsZero: account with nil balanceBaseline yields 0")
    func nilBaselineYieldsZero() throws {
        let balance = AccountBalance.compute(
            baseline: nil,
            asOf: Date(),
            expenses: [],
            accountID: UUID()
        )

        #expect(balance == Decimal(0), "Expected 0 for nil baseline but got \(balance)")
    }

    // MARK: - nil asOf yields 0

    @Test("nilAsOfYieldsZero: account with nil asOf yields 0")
    func nilAsOfYieldsZero() throws {
        let balance = AccountBalance.compute(
            baseline: Decimal(1000),
            asOf: nil,
            expenses: [],
            accountID: UUID()
        )

        #expect(balance == Decimal(0), "Expected 0 for nil asOf but got \(balance)")
    }
}
