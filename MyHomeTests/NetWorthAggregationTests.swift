import Testing
import SwiftData
import Foundation
@testable import MyHome

/// NetWorthCalculator aggregation tests — ASSET-05, T-11-07.
///
/// Verifies:
///   - Net worth = MF + stock + NPS + cash (plain sum)
///   - cashValue = Σ AccountBalance.compute() over non-archived accounts
///   - CC debt (negative baseline) reduces cashValue and total net worth
///   - Nil units or nil currentNAV on an Asset contributes 0 (ASSET-02 nil-safe)
///   - NetWorthCalculator.breakdown reuses AccountBalance.compute (no re-implementation)
@MainActor
struct NetWorthAggregationTests {

    private func makeContainer() throws -> ModelContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: Asset.self, Account.self, Expense.self, NetWorthSnapshot.self,
                                  configurations: config)
    }

    // MARK: - Basic aggregation

    @Test("ASSET-05 mfValue: mutual_fund assets with units and nav contribute to mfValue")
    func mfValueAggregation() throws {
        // 3 MF assets: 10 × 100 + 20 × 50 + 5 × 200 = 1000 + 1000 + 1000 = 3000
        let bd = NetWorthCalculator.breakdown(
            assets: [
                makeAsset(class: "mutual_fund", units: 10, nav: 100),
                makeAsset(class: "mutual_fund", units: 20, nav: 50),
                makeAsset(class: "mutual_fund", units: 5,  nav: 200),
            ],
            accounts: [],
            expenses: []
        )
        #expect(bd.mfValue == 3000, "mfValue must be sum of units×nav for mutual_fund assets")
        #expect(bd.stockValue == 0, "stockValue must be 0 when no stock assets")
        #expect(bd.npsValue   == 0, "npsValue must be 0 when no NPS assets")
    }

    @Test("ASSET-05 stockValue and npsValue: each class aggregates independently")
    func stockAndNPSAggregation() throws {
        let bd = NetWorthCalculator.breakdown(
            assets: [
                makeAsset(class: "stock",        units: 10, nav: 500),  // 5000
                makeAsset(class: "nps",          units: 100, nav: 30),  // 3000
                makeAsset(class: "mutual_fund",  units: 1,   nav: 200), // 200
            ],
            accounts: [],
            expenses: []
        )
        #expect(bd.stockValue == 5000, "stockValue must sum stock assets only")
        #expect(bd.npsValue   == 3000, "npsValue must sum NPS assets only")
        #expect(bd.mfValue    == 200,  "mfValue must sum MF assets only")
    }

    // MARK: - Nil-safe asset handling

    @Test("ASSET-02 nil units: asset with nil units contributes 0 to its class sub-total")
    func nilUnitsContributesZero() throws {
        var assetNilUnits = makeAsset(class: "mutual_fund", units: nil, nav: 100)
        let bd = NetWorthCalculator.breakdown(
            assets: [assetNilUnits],
            accounts: [],
            expenses: []
        )
        #expect(bd.mfValue == 0, "nil units must contribute 0")
        #expect(bd.totalNetWorth == 0, "totalNetWorth must be 0 when all assets have nil units")
    }

    @Test("ASSET-02 nil currentNAV: asset with nil currentNAV contributes 0 to its class sub-total")
    func nilNAVContributesZero() throws {
        let assetNilNAV = makeAsset(class: "stock", units: 100, nav: nil)
        let bd = NetWorthCalculator.breakdown(
            assets: [assetNilNAV],
            accounts: [],
            expenses: []
        )
        #expect(bd.stockValue == 0, "nil currentNAV must contribute 0")
    }

    @Test("ASSET-02 both nil: asset with nil units AND nil currentNAV contributes 0")
    func bothNilContributesZero() throws {
        let assetBothNil = makeAsset(class: "nps", units: nil, nav: nil)
        let bd = NetWorthCalculator.breakdown(
            assets: [assetBothNil],
            accounts: [],
            expenses: []
        )
        #expect(bd.npsValue == 0, "nil units AND nil NAV must contribute 0")
    }

    // MARK: - Cash aggregation (AccountBalance.compute sign convention)

    @Test("ASSET-05 cashValue: savings account with positive balance adds to cashValue")
    func savingsAccountAddsToCashValue() throws {
        let container = try makeContainer()
        let ctx = container.mainContext

        // Savings: baseline 10000, one spend of 500 after asOf → balance = 9500
        let account = makeAccount(ctx: ctx, baseline: 10000, archived: false)
        let spend = makeExpense(ctx: ctx, amount: 500, accountID: account.id,
                                date: account.balanceAsOfDate!.addingTimeInterval(86400))
        try ctx.save()

        let allExpenses = try ctx.fetch(FetchDescriptor<Expense>())
        let allAccounts = try ctx.fetch(FetchDescriptor<Account>())

        let bd = NetWorthCalculator.breakdown(assets: [], accounts: allAccounts, expenses: allExpenses)
        #expect(bd.cashValue == 9500, "cashValue = baseline(10000) − spend(500) = 9500")
    }

    @Test("ASSET-05 CC debt: CC account (negative baseline) reduces cashValue — sign convention honored")
    func ccDebtReducesCashValue() throws {
        let container = try makeContainer()
        let ctx = container.mainContext

        // Savings: balance = 20000 (no expenses after asOf)
        let savings = makeAccount(ctx: ctx, baseline: 20000, archived: false)

        // CC: baseline = -5000 (amount owed), one spend of 2000 after asOf
        //     balance = (-5000) - 2000 = -7000
        let cc = makeAccount(ctx: ctx, baseline: -5000, archived: false)
        let _ = makeExpense(ctx: ctx, amount: 2000, accountID: cc.id,
                            date: cc.balanceAsOfDate!.addingTimeInterval(86400))
        try ctx.save()

        let allExpenses = try ctx.fetch(FetchDescriptor<Expense>())
        let allAccounts = try ctx.fetch(FetchDescriptor<Account>())

        let bd = NetWorthCalculator.breakdown(assets: [], accounts: allAccounts, expenses: allExpenses)
        // cashValue = savings(20000) + cc(-5000-2000) = 20000 - 7000 = 13000
        #expect(bd.cashValue == 13000, "cashValue must be savings+cc = 20000 + (-7000) = 13000")
    }

    @Test("ASSET-05 CC-heavy: cashValue is negative when CC debt exceeds all savings (D-11)")
    func ccHeavyYieldsNegativeCashValue() throws {
        let container = try makeContainer()
        let ctx = container.mainContext

        // Savings: 1000
        let _ = makeAccount(ctx: ctx, baseline: 1000, archived: false)

        // CC: -15000 baseline, spend 5000 → balance = -20000
        let cc = makeAccount(ctx: ctx, baseline: -15000, archived: false)
        let _ = makeExpense(ctx: ctx, amount: 5000, accountID: cc.id,
                            date: cc.balanceAsOfDate!.addingTimeInterval(86400))
        try ctx.save()

        let allExpenses = try ctx.fetch(FetchDescriptor<Expense>())
        let allAccounts = try ctx.fetch(FetchDescriptor<Account>())

        let bd = NetWorthCalculator.breakdown(assets: [], accounts: allAccounts, expenses: allExpenses)
        // cashValue = 1000 + (-15000 - 5000) = 1000 - 20000 = -19000
        #expect(bd.cashValue < 0,
                "cashValue must be negative when CC debt exceeds savings (D-11)")
        #expect(bd.cashValue == -19000, "cashValue = 1000 + (-20000) = -19000")
    }

    @Test("ASSET-05 archived accounts are excluded from cashValue")
    func archivedAccountExcluded() throws {
        let container = try makeContainer()
        let ctx = container.mainContext

        let active   = makeAccount(ctx: ctx, baseline: 5000, archived: false)
        let archived = makeAccount(ctx: ctx, baseline: 9999, archived: true)
        try ctx.save()

        let allExpenses = try ctx.fetch(FetchDescriptor<Expense>())
        let allAccounts = try ctx.fetch(FetchDescriptor<Account>())

        let bd = NetWorthCalculator.breakdown(assets: [], accounts: allAccounts, expenses: allExpenses)
        #expect(bd.cashValue == 5000, "Archived account must not contribute to cashValue")
    }

    // MARK: - Total net worth

    @Test("ASSET-05 totalNetWorth: holdings + account balances with correct sign convention")
    func totalNetWorthCombinesHoldingsAndCash() throws {
        let container = try makeContainer()
        let ctx = container.mainContext

        // Savings: 10000
        let _ = makeAccount(ctx: ctx, baseline: 10000, archived: false)
        // CC: -2000 (no extra spends)
        let _ = makeAccount(ctx: ctx, baseline: -2000, archived: false)
        try ctx.save()

        let allExpenses = try ctx.fetch(FetchDescriptor<Expense>())
        let allAccounts = try ctx.fetch(FetchDescriptor<Account>())

        // MF: 100 × 200 = 20000; Stock: 10 × 150 = 1500
        let bd = NetWorthCalculator.breakdown(
            assets: [
                makeAsset(class: "mutual_fund", units: 100, nav: 200),
                makeAsset(class: "stock",       units: 10,  nav: 150),
            ],
            accounts: allAccounts,
            expenses: allExpenses
        )
        // total = 20000 + 1500 + (10000 + (-2000)) = 21500 + 8000 = 29500
        #expect(bd.mfValue    == 20000,  "mfValue")
        #expect(bd.stockValue == 1500,   "stockValue")
        #expect(bd.cashValue  == 8000,   "cashValue = savings - cc = 10000 - 2000 = 8000")
        #expect(bd.totalNetWorth == 29500, "totalNetWorth = 20000 + 1500 + 8000 = 29500")
    }

    // MARK: - Helpers

    private func makeAsset(class assetClass: String, units: Decimal?, nav: Decimal?) -> Asset {
        let a = Asset()
        a.assetClassRaw = assetClass
        a.units = units
        a.currentNAV = nav
        return a
    }

    @discardableResult
    private func makeAccount(ctx: ModelContext, baseline: Decimal, archived: Bool) -> Account {
        let a = Account(name: "Test Account")
        a.balanceBaseline = baseline
        a.balanceAsOfDate = Calendar.current.date(from: DateComponents(year: 2025, month: 1, day: 1))!
        a.isArchived = archived
        ctx.insert(a)
        return a
    }

    @discardableResult
    private func makeExpense(ctx: ModelContext, amount: Decimal, accountID: UUID, date: Date) -> Expense {
        let e = Expense(amount: amount)
        e.accountID = accountID
        e.date = date
        ctx.insert(e)
        return e
    }
}
