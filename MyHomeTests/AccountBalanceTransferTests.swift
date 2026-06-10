import Testing
import SwiftData
import Foundation
@testable import MyHome

/// Tests verifying AccountBalance.compute behavior for confirmed transfer pairs (XFER-04/ACCT-05).
///
/// These tests lock the EXISTING AccountBalance.compute formula behavior for transfer legs.
/// AccountBalance.swift is NOT modified — this is a verification-only task.
///
/// Key finding (Research open question A3 / RESEARCH.md Critical Finding 4):
/// The existing formula adds `expense.amount` to `baseline`. For a confirmed linked transfer pair:
/// - Debit leg (amount > 0, attributed to account A): balance of A = baseline + positive_amount
///   → A's balance INCREASES by the transfer amount (formula treats positive = inflow to account).
/// - Credit leg (amount < 0, attributed to account B): balance of B = baseline + negative_amount
///   → B's balance DECREASES by the transfer amount.
///
/// This means: for the current formula, a confirmed debit (`amount > 0`) FROM account A
/// increases A's displayed balance, and a confirmed credit (`amount < 0`) RECEIVED BY account B
/// decreases B's displayed balance. This is the "D-16 implicit balance-move" described in
/// Critical Finding 4 — the pair nets to zero, so total net worth is unchanged.
///
/// Task 4 (human-verify checkpoint) resolves whether this sign convention is correct for
/// savings accounts with real data (Research A3). The verdict from Task 4 will determine
/// whether Plan 03 needs a formula correction before wiring D-16.
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

    @Test("balanceMoveDirection: documents the sign convention — debit leg (amount > 0) increases its account balance; credit leg (amount < 0) decreases its account balance")
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

        // D-16 direction documentation (existing formula behavior):
        // Debit leg (amount > 0) attributed to account A → A's balance INCREASES by transferAmount.
        // Credit leg (amount < 0) attributed to account B → B's balance DECREASES by transferAmount.
        // This is the "implicit balance-move" via sign convention in AccountBalance.compute.
        //
        // NOTE: Task 4 (human-verify) must confirm whether this sign behavior is correct for
        // savings accounts with real data. If debit (+5000) correctly represents money LEAVING
        // account A (reducing its balance), then the formula has an inversion that D-16 wiring
        // in Plan 03 must correct. If debit (+5000) represents an INFLOW (which would increase
        // balance correctly), then the formula is already correct.
        //
        // For now, we lock the ACTUAL formula behavior:
        let expectedComputeA = baselineA + transferAmount    // 10000 + 3000 = 13000
        let expectedComputeB = baselineB + (-transferAmount)  // 20000 - 3000 = 17000

        #expect(computeA == expectedComputeA,
                "Account A (debit leg, amount > 0): balance should be \(expectedComputeA), got \(computeA). Formula: baseline + positive_amount = balance increases.")
        #expect(computeB == expectedComputeB,
                "Account B (credit leg, amount < 0): balance should be \(expectedComputeB), got \(computeB). Formula: baseline + negative_amount = balance decreases.")
    }
}
