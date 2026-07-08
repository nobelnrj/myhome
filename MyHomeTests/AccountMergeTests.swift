import Testing
import SwiftData
import Foundation
@testable import MyHome

/// Tests for `AccountMerger.merge` (D-MERGE-01): folding two ingestion identities that are
/// really one real-world balance (savings + debit card; ••843 + ••6843) into one account.
@MainActor
struct AccountMergeTests {

    @Test("merge re-points the absorbed account's expenses onto the survivor")
    func repointsExpenses() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: Account.self, Expense.self, configurations: config)
        let ctx = container.mainContext

        let survivor = Account(name: "ICICI Savings", typeRaw: "savings", sourceLabel: "ICICI Savings")
        let absorbed = Account(name: "ICICI Debit Card", typeRaw: "savings", sourceLabel: "ICICI Debit Card")
        ctx.insert(survivor); ctx.insert(absorbed)

        let onAbsorbed = Expense(amount: 300, date: Date()); onAbsorbed.accountID = absorbed.id
        let onSurvivor = Expense(amount: 100, date: Date()); onSurvivor.accountID = survivor.id
        let unrelated = Expense(amount: 50, date: Date())  // accountID nil
        [onAbsorbed, onSurvivor, unrelated].forEach { ctx.insert($0) }
        try ctx.save()

        let expenses = [onAbsorbed, onSurvivor, unrelated]
        let result = AccountMerger.merge(absorbed: absorbed, into: survivor, allExpenses: expenses)

        #expect(onAbsorbed.accountID == survivor.id, "Absorbed expense must re-point to survivor")
        #expect(onSurvivor.accountID == survivor.id, "Survivor expense unchanged")
        #expect(unrelated.accountID == nil, "Unrelated expense unchanged")
        #expect(result.repointedExpenseIDs == [onAbsorbed.id])
        #expect(result.survivorID == survivor.id)
        #expect(result.absorbedID == absorbed.id)
    }

    @Test("merge folds both identities into the survivor's sourceLabel alias set")
    func foldsAliases() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: Account.self, Expense.self, configurations: config)
        let ctx = container.mainContext

        let survivor = Account(name: "ICICI Savings", typeRaw: "savings", sourceLabel: "ICICI Savings")
        let absorbed = Account(name: "ICICI Debit Card", typeRaw: "savings", sourceLabel: "ICICI Debit Card")
        ctx.insert(survivor); ctx.insert(absorbed)
        try ctx.save()

        AccountMerger.merge(absorbed: absorbed, into: survivor, allExpenses: [])

        let aliases = AccountAttributionHelper.aliases(of: survivor)
        #expect(aliases == ["ICICI Savings", "ICICI Debit Card"], "Survivor now owns both identities, got \(aliases)")

        // And attribution routes both labels to the survivor after merge.
        let map = AccountAttributionHelper.buildAccountIDsByLabel(from: [survivor])
        #expect(AccountAttributionHelper.accountID(forSourceLabel: "ICICI Debit Card", in: map) == survivor.id)
    }

    @Test("merge keeps the survivor's baseline and adopts last4 only when survivor lacks one")
    func baselineAndLast4() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: Account.self, Expense.self, configurations: config)
        let ctx = container.mainContext

        let survivor = Account(name: "ICICI Savings", typeRaw: "savings", sourceLabel: "ICICI Savings")
        survivor.balanceBaseline = 5000
        // survivor.last4 stays nil → should adopt absorbed's.
        let absorbed = Account(name: "ICICI Debit", typeRaw: "savings", sourceLabel: "ICICI Debit")
        absorbed.balanceBaseline = 999
        absorbed.last4 = "6843"
        ctx.insert(survivor); ctx.insert(absorbed)
        try ctx.save()

        AccountMerger.merge(absorbed: absorbed, into: survivor, allExpenses: [])

        #expect(survivor.balanceBaseline == 5000, "Survivor baseline preserved")
        #expect(survivor.last4 == "6843", "Survivor with no last4 adopts absorbed's")
    }

    @Test("merged balance sums both identities' expenses against the survivor baseline")
    func mergedBalanceIsUnified() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: Account.self, Expense.self, configurations: config)
        let ctx = container.mainContext

        let asOf = Date(timeIntervalSince1970: 0)
        let survivor = Account(name: "ICICI Savings", typeRaw: "savings", sourceLabel: "ICICI Savings")
        survivor.balanceBaseline = 10_000
        survivor.balanceAsOfDate = asOf
        let absorbed = Account(name: "ICICI Debit", typeRaw: "savings", sourceLabel: "ICICI Debit")
        ctx.insert(survivor); ctx.insert(absorbed)

        // A spend on each identity (positive = outflow per app convention).
        let spendA = Expense(amount: 300, date: Date(timeIntervalSince1970: 100)); spendA.accountID = survivor.id
        let spendB = Expense(amount: 200, date: Date(timeIntervalSince1970: 200)); spendB.accountID = absorbed.id
        [spendA, spendB].forEach { ctx.insert($0) }
        try ctx.save()

        // Pass the explicit expense set (not a store-wide fetch): AccountBalance/AccountMerger are
        // pure functions, and SwiftData in-memory stores leak across sibling tests in one process.
        let expenses = [spendA, spendB]
        AccountMerger.merge(absorbed: absorbed, into: survivor, allExpenses: expenses)

        let balance = AccountBalance.compute(
            baseline: survivor.balanceBaseline,
            asOf: survivor.balanceAsOfDate,
            expenses: expenses,
            accountID: survivor.id
        )
        // Use an explicit Decimal: a bare `10_000 - 500` literal infers a non-Decimal type that
        // compares unequal to the Decimal balance (Decimal literal-inference gotcha).
        #expect(balance == Decimal(9500), "Both spends must reduce the single merged balance (got \(balance))")
    }

    @Test("merging an account into itself is a no-op")
    func selfMergeNoOp() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: Account.self, Expense.self, configurations: config)
        let ctx = container.mainContext

        let account = Account(name: "ICICI", typeRaw: "savings", sourceLabel: "ICICI")
        ctx.insert(account)
        try ctx.save()

        let result = AccountMerger.merge(absorbed: account, into: account, allExpenses: [])
        #expect(result.repointedExpenseIDs.isEmpty)
        #expect(AccountAttributionHelper.aliases(of: account) == ["ICICI"], "Self-merge must not duplicate aliases")
    }
}
