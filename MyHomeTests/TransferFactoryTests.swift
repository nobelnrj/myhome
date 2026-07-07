import Testing
import SwiftData
import Foundation
@testable import MyHome

/// Tests for TransferFactory — the pure builder behind the manual "New Transfer" sheet.
///
/// A manual self-transfer must produce two legs that (a) move the two account balances in
/// opposite directions, (b) leave net worth unchanged, and (c) are excluded from hero cash-flow.
/// These lock that contract against the same helpers the app uses (AccountBalance.compute,
/// BudgetCalculator.isTransferForCashFlow) so a UI regression can't silently break the model.
@MainActor
struct TransferFactoryTests {

    private func makeContainer() throws -> ModelContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: Account.self, Expense.self, configurations: config)
    }

    private func makeAccount(in ctx: ModelContext, name: String, baseline: Decimal, asOf: Date) -> Account {
        let a = Account(name: name)
        a.id = UUID()
        a.balanceBaseline = baseline
        a.balanceAsOfDate = asOf
        ctx.insert(a)
        return a
    }

    private func asOfDate() -> Date {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Kolkata")!
        return cal.date(from: DateComponents(year: 2026, month: 1, day: 1))!
    }

    private func txDate() -> Date {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Kolkata")!
        return cal.date(from: DateComponents(year: 2026, month: 2, day: 15))!
    }

    // MARK: - Leg shape

    @Test("legsAreCrossLinkedAndConfirmed: debit is positive on `from`, credit is negative on `to`, both isTransfer==true, pairIDs cross-set")
    func legsAreCrossLinkedAndConfirmed() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let asOf = asOfDate()

        let icici = makeAccount(in: ctx, name: "ICICI", baseline: 100000, asOf: asOf)
        let hdfc  = makeAccount(in: ctx, name: "HDFC",  baseline: 50000,  asOf: asOf)

        let (debit, credit) = TransferFactory.makeTransfer(
            amount: 15000, from: icici, to: hdfc, date: txDate(), note: nil
        )

        // Debit = outflow from source (positive), credit = inflow to destination (negative).
        #expect(debit.amount == Decimal(15000))
        #expect(credit.amount == Decimal(-15000))
        #expect(debit.accountID == icici.id)
        #expect(credit.accountID == hdfc.id)

        // Both confirmed and cross-linked to each other's id.
        #expect(debit.isTransfer == true)
        #expect(credit.isTransfer == true)
        #expect(debit.transferPairID == credit.id)
        #expect(credit.transferPairID == debit.id)
    }

    @Test("negativeAmountIsNormalised: a stray negative amount can't invert the legs (abs applied)")
    func negativeAmountIsNormalised() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let asOf = asOfDate()
        let a = makeAccount(in: ctx, name: "A", baseline: 0, asOf: asOf)
        let b = makeAccount(in: ctx, name: "B", baseline: 0, asOf: asOf)

        let (debit, credit) = TransferFactory.makeTransfer(
            amount: -15000, from: a, to: b, date: txDate(), note: nil
        )
        #expect(debit.amount == Decimal(15000))
        #expect(credit.amount == Decimal(-15000))
    }

    @Test("autoNotesNameCounterpart: nil note yields 'Transfer to <to>' / 'Transfer from <from>'; a user note overrides both")
    func autoNotesNameCounterpart() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let asOf = asOfDate()
        let icici = makeAccount(in: ctx, name: "ICICI", baseline: 0, asOf: asOf)
        let hdfc  = makeAccount(in: ctx, name: "HDFC",  baseline: 0, asOf: asOf)

        let (autoDebit, autoCredit) = TransferFactory.makeTransfer(
            amount: 15000, from: icici, to: hdfc, date: txDate(), note: nil
        )
        #expect(autoDebit.note == "Transfer to HDFC")
        #expect(autoCredit.note == "Transfer from ICICI")

        let (uDebit, uCredit) = TransferFactory.makeTransfer(
            amount: 15000, from: icici, to: hdfc, date: txDate(), note: "Monthly shared top-up"
        )
        #expect(uDebit.note == "Monthly shared top-up")
        #expect(uCredit.note == "Monthly shared top-up")
    }

    // MARK: - Balance + cash-flow integration

    @Test("movesBalancesAndPreservesNetWorth: source ↓, destination ↑, sum unchanged")
    func movesBalancesAndPreservesNetWorth() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let asOf = asOfDate()

        let baselineFrom: Decimal = 80000
        let baselineTo: Decimal = 20000
        let icici = makeAccount(in: ctx, name: "ICICI", baseline: baselineFrom, asOf: asOf)
        let hdfc  = makeAccount(in: ctx, name: "HDFC",  baseline: baselineTo,   asOf: asOf)
        try ctx.save()

        let (debit, credit) = TransferFactory.makeTransfer(
            amount: 15000, from: icici, to: hdfc, date: txDate(), note: nil
        )
        ctx.insert(debit)
        ctx.insert(credit)
        try ctx.save()

        let all = try ctx.fetch(FetchDescriptor<Expense>())
        let fromBal = AccountBalance.compute(baseline: baselineFrom, asOf: asOf, expenses: all, accountID: icici.id)
        let toBal   = AccountBalance.compute(baseline: baselineTo,   asOf: asOf, expenses: all, accountID: hdfc.id)

        #expect(fromBal == baselineFrom - 15000, "Source must drop by 15k: got \(fromBal)")
        #expect(toBal   == baselineTo + 15000,   "Destination must rise by 15k: got \(toBal)")
        #expect(fromBal + toBal == baselineFrom + baselineTo, "Net worth unchanged by a self-transfer")
    }

    @Test("excludedFromCashFlow: neither leg counts as hero income or spend")
    func excludedFromCashFlow() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let asOf = asOfDate()
        let icici = makeAccount(in: ctx, name: "ICICI", baseline: 0, asOf: asOf)
        let hdfc  = makeAccount(in: ctx, name: "HDFC",  baseline: 0, asOf: asOf)

        let (debit, credit) = TransferFactory.makeTransfer(
            amount: 15000, from: icici, to: hdfc, date: txDate(), note: nil
        )
        ctx.insert(debit)
        ctx.insert(credit)
        try ctx.save()

        let all = try ctx.fetch(FetchDescriptor<Expense>())
        #expect(BudgetCalculator.isTransferForCashFlow(debit))
        #expect(BudgetCalculator.isTransferForCashFlow(credit))
        #expect(BudgetCalculator.grossSpend(for: all) == 0, "A self-transfer must not add to spend")
        #expect(BudgetCalculator.grossIncome(for: all) == 0, "A self-transfer must not add to income")
    }
}
