import Testing
import SwiftData
import Foundation
@testable import MyHome

/// Tests verifying AccountBalance.compute behavior for confirmed transfer pairs (XFER-04/ACCT-05).
///
/// Resolution of Research open question A3 / RESEARCH.md Critical Finding 4:
/// The Task 4 human-verify gate confirmed the prior `baseline + net` formula was INVERTED —
/// a spend (positive amount) made a savings balance go UP. AccountBalance.compute was corrected
/// to `baseline − net` (spends, stored positive, reduce a savings balance). These tests now lock
/// the corrected, app-consistent behavior for transfer legs:
/// - Debit leg (amount > 0 = outflow) attributed to source account A: A = baseline − positive
///   → A's balance DECREASES by the transfer amount (money LEFT A).
/// - Credit leg (amount < 0 = inflow) attributed to destination account B: B = baseline − negative
///   → B's balance INCREASES by the transfer amount (money ARRIVED in B).
///
/// The pair nets to zero across the two accounts, so total net worth is unchanged (D-16).
@MainActor
struct AccountBalanceTransferTests {

    // MARK: - Helpers

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

    private func transactionDate() -> Date {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Kolkata")!
        return cal.date(from: DateComponents(year: 2026, month: 2, day: 15))!
    }

    // MARK: - Tests

    @Test("confirmedTransferIncludedInBalance: a confirmed transfer leg (isTransfer == true) attributed to an account IS included in compute (not excluded)")
    func confirmedTransferIncludedInBalance() throws {
        let container = try makeContainer()
        let ctx = container.mainContext

        let asOf = asOfDate()
        let txDate = transactionDate()
        let baselineA: Decimal = 10000

        let accountA = makeAccount(in: ctx, name: "Savings A", baseline: baselineA, asOf: asOf)
        try ctx.save()

        // A confirmed transfer debit from account A (amount > 0 = money left A in the transfer context)
        let transferDebit = Expense(amount: Decimal(5000), date: txDate)
        transferDebit.accountID = accountA.id
        transferDebit.isTransfer = true
        transferDebit.transferPairID = UUID()  // linked (simulated partner UUID)
        ctx.insert(transferDebit)
        try ctx.save()

        let allExpenses = try ctx.fetch(FetchDescriptor<Expense>())

        let balance = AccountBalance.compute(
            baseline: baselineA,
            asOf: asOf,
            expenses: allExpenses,
            accountID: accountA.id
        )

        // The transfer leg IS included in the formula (no exclusion for isTransfer == true in AccountBalance).
        // This confirms D-16: transfer legs affect the per-account balance via the formula.
        // balance != baselineA verifies the leg was NOT excluded.
        #expect(balance != baselineA,
                "Confirmed transfer leg must be included in balance computation (not excluded like spend aggregators). Got \(balance), expected != \(baselineA)")
    }

    @Test("netWorthUnchangedByTransfer: a linked confirmed pair with equal-magnitude opposite-sign amounts → total net worth unchanged (sum of both account balances = sum of baselines)")
    func netWorthUnchangedByTransfer() throws {
        let container = try makeContainer()
        let ctx = container.mainContext

        let asOf = asOfDate()
        let txDate = transactionDate()

        let baselineA: Decimal = 10000  // savings account A
        let baselineB: Decimal = 20000  // savings account B

        let accountA = makeAccount(in: ctx, name: "Savings A", baseline: baselineA, asOf: asOf)
        let accountB = makeAccount(in: ctx, name: "Savings B", baseline: baselineB, asOf: asOf)
        try ctx.save()

        // Transfer: 5000 leaves account A (debit, amount > 0) and arrives in account B (credit, amount < 0)
        let transferAmount: Decimal = 5000

        let debitLeg = Expense(amount: transferAmount, date: txDate)
        debitLeg.accountID = accountA.id
        debitLeg.isTransfer = true

        let creditLeg = Expense(amount: -transferAmount, date: txDate)
        creditLeg.accountID = accountB.id
        creditLeg.isTransfer = true

        // Cross-set transferPairID
        debitLeg.transferPairID  = creditLeg.id
        creditLeg.transferPairID = debitLeg.id

        ctx.insert(debitLeg)
        ctx.insert(creditLeg)
        try ctx.save()

        let allExpenses = try ctx.fetch(FetchDescriptor<Expense>())

        let computeA = AccountBalance.compute(
            baseline: baselineA,
            asOf: asOf,
            expenses: allExpenses,
            accountID: accountA.id
        )
        let computeB = AccountBalance.compute(
            baseline: baselineB,
            asOf: asOf,
            expenses: allExpenses,
            accountID: accountB.id
        )

        // NET WORTH INVARIANT: sum of both account balances == sum of both baselines
        // The debit (+5000) and credit (-5000) cancel each other out across the two accounts.
        let totalBalance  = computeA + computeB
        let totalBaseline = baselineA + baselineB

        #expect(totalBalance == totalBaseline,
                "Net worth must be unchanged by a confirmed transfer pair: computeA(\(computeA)) + computeB(\(computeB)) = \(totalBalance), expected \(totalBaseline)")
    }

    @Test("balanceMoveDirection: debit leg (amount > 0) DECREASES its source account; credit leg (amount < 0) INCREASES its destination account")
    func balanceMoveDirection() throws {
        let container = try makeContainer()
        let ctx = container.mainContext

        let asOf = asOfDate()
        let txDate = transactionDate()

        let baselineA: Decimal = 10000
        let baselineB: Decimal = 20000
        let transferAmount: Decimal = 3000

        let accountA = makeAccount(in: ctx, name: "Debit Account", baseline: baselineA, asOf: asOf)
        let accountB = makeAccount(in: ctx, name: "Credit Account", baseline: baselineB, asOf: asOf)
        try ctx.save()

        let debitLeg = Expense(amount: transferAmount, date: txDate)  // amount > 0
        debitLeg.accountID = accountA.id
        debitLeg.isTransfer = true

        let creditLeg = Expense(amount: -transferAmount, date: txDate)  // amount < 0
        creditLeg.accountID = accountB.id
        creditLeg.isTransfer = true

        debitLeg.transferPairID  = creditLeg.id
        creditLeg.transferPairID = debitLeg.id

        ctx.insert(debitLeg)
        ctx.insert(creditLeg)
        try ctx.save()

        let allExpenses = try ctx.fetch(FetchDescriptor<Expense>())

        let computeA = AccountBalance.compute(
            baseline: baselineA,
            asOf: asOf,
            expenses: allExpenses,
            accountID: accountA.id
        )
        let computeB = AccountBalance.compute(
            baseline: baselineB,
            asOf: asOf,
            expenses: allExpenses,
            accountID: accountB.id
        )

        // D-16 direction (corrected `baseline − net` formula):
        // Debit leg (amount > 0 = outflow) attributed to source A → A's balance DECREASES (money left A).
        // Credit leg (amount < 0 = inflow) attributed to destination B → B's balance INCREASES (money arrived).
        let expectedComputeA = baselineA - transferAmount     // 10000 − 3000 = 7000  (money left A)
        let expectedComputeB = baselineB - (-transferAmount)  // 20000 + 3000 = 23000 (money arrived in B)

        #expect(computeA == expectedComputeA,
                "Account A (debit leg, amount > 0 = outflow): balance should be \(expectedComputeA), got \(computeA). Formula: baseline − positive_amount = balance decreases.")
        #expect(computeB == expectedComputeB,
                "Account B (credit leg, amount < 0 = inflow): balance should be \(expectedComputeB), got \(computeB). Formula: baseline − negative_amount = balance increases.")
    }

    // MARK: - 07-07 end-to-end validation (real email formats → detect → balance)

    /// Full-chain validation using the REAL parsers on REAL email shapes: a ₹50,000 transfer that
    /// leaves an ICICI savings account (NEFT-out, now parsed) and arrives in an HDFC account
    /// (credit-in, now parsed). Proves the two legs pair via the scorer and that per-account
    /// balances move correctly (source ↓, destination ↑, net worth unchanged).
    @Test("e2e: real ICICI-NEFT-out + HDFC-credit-in pair and move balances correctly — 07-07")
    func realCrossAccountTransferDetectedAndBalanced() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let asOf = asOfDate()

        // Two own accounts, both attributed.
        let icici = makeAccount(in: ctx, name: "ICICI Savings", baseline: 200000, asOf: asOf)
        let hdfc  = makeAccount(in: ctx, name: "HDFC Savings",  baseline: 100000, asOf: asOf)
        try ctx.save()

        // Parse both legs with the actual production parsers (validates the live formats).
        let neftOutRaw = "From: customernotification@icici.bank.in\r\nDate: Wed, 15 Jul 2026 20:03:00 +0530\r\nSubject: NEFT transaction through ICICI Bank iMobile.\r\n\r\n<html><body>You have made an online NEFT payment of Rs. 50,000.00 towards Bhuvanya Sridhar on Jul 15, 2026 at 08:03 p.m. from your ICICI Bank Savings Account XXXX6843. The Transaction ID is IN123.</body></html>"
        let creditInRaw = "From: alerts@hdfcbank.bank.in\r\nDate: Wed, 15 Jul 2026 20:04:00 +0530\r\nSubject: View: Account update for your HDFC Bank A/c\r\n\r\n<html><body>We're writing to inform you that Rs.50000.00 has been successfully credited to your HDFC Bank account ending in 1011. Transaction Details: a. Date: 15-07-26</body></html>"

        let debitLegParsed  = try #require(ICICIParser().parse(rawEmail: neftOutRaw), "ICICI NEFT-out must parse")
        let creditLegParsed = try #require(HDFCParser().parse(rawEmail: creditInRaw), "HDFC credit-in must parse")

        // Sanity on the parsed legs: opposite signs, equal magnitude.
        #expect(debitLegParsed.amount == Decimal(string: "50000.00"))
        #expect(creditLegParsed.amount == Decimal(string: "-50000.00"))

        // Build Expenses exactly as the controller does (isReversal → negative), attribute to accounts.
        func makeExpense(_ p: ParsedExpense, account: Account) -> Expense {
            let e = Expense(amount: p.isReversal ? -abs(p.amount) : p.amount, date: p.date)
            e.accountID = account.id
            ctx.insert(e)
            return e
        }
        _ = makeExpense(debitLegParsed, account: icici)   // +50000 on ICICI
        _ = makeExpense(creditLegParsed, account: hdfc)   // -50000 on HDFC
        try ctx.save()

        // Run the real scorer (the same call TransferScanService.scan() makes).
        var istCal = Calendar(identifier: .gregorian)
        istCal.timeZone = TimeZone(identifier: "Asia/Kolkata")!
        let all = try ctx.fetch(FetchDescriptor<Expense>())
        let pairs = TransferDetectionScorer.findCandidatePairs(from: all, calendar: istCal)

        // 1) The two legs are detected as a transfer pair.
        #expect(pairs.count == 1, "Expected exactly one detected transfer pair, got \(pairs.count)")

        // 2) Balances move correctly and net worth is unchanged.
        let icBal = AccountBalance.compute(baseline: 200000, asOf: asOf, expenses: all, accountID: icici.id)
        let hdBal = AccountBalance.compute(baseline: 100000, asOf: asOf, expenses: all, accountID: hdfc.id)
        #expect(icBal == Decimal(150000), "ICICI (source) must drop by 50,000 → 150,000, got \(icBal)")
        #expect(hdBal == Decimal(150000), "HDFC (destination) must rise by 50,000 → 150,000, got \(hdBal)")
        #expect(icBal + hdBal == Decimal(300000), "Net worth unchanged across the transfer")
    }
}
