import Testing
import SwiftData
import Foundation
@testable import MyHome

/// Integration tests for TransferScanService — the @MainActor scan lifecycle coordinator.
///
/// Each test uses a fresh in-memory ModelContainer (mirroring AccountBalanceTests.makeContainer).
/// A fresh UserDefaults suite is injected per test to avoid cross-test pollution.
///
/// Covers: scanWritesPendingPairs, scanLeavesUnmatchedAlone, secondScanIdempotent,
///         confirmedLegSkipped (D-10), rejectedLegSkipped (D-10), firstRunFlagSet.
@MainActor
struct TransferScanServiceTests {

    // MARK: - Helpers

    private func makeContainer() throws -> ModelContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: Account.self, Expense.self, configurations: config)
    }

    /// Creates a fresh UserDefaults suite with a unique name to avoid cross-test pollution.
    private func makeFreshDefaults() -> UserDefaults {
        let name = "test-\(UUID().uuidString)"
        let d = UserDefaults(suiteName: name)!
        d.removePersistentDomain(forName: name)
        return d
    }

    private func makeAccount(in ctx: ModelContext, name: String = "Account") -> Account {
        let a = Account(name: name)
        a.id = UUID()
        ctx.insert(a)
        return a
    }

    private func makeExpense(
        in ctx: ModelContext,
        amount: Decimal,
        accountID: UUID?,
        daysOffset: Int = 0,
        isTransfer: Bool? = nil,
        transferPairID: UUID? = nil
    ) -> Expense {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Kolkata")!
        let base = cal.date(from: DateComponents(year: 2026, month: 1, day: 15))!
        let date = cal.date(byAdding: .day, value: daysOffset, to: base)!

        let e = Expense(amount: amount, date: date)
        e.accountID = accountID
        e.isTransfer = isTransfer
        e.transferPairID = transferPairID
        ctx.insert(e)
        return e
    }

    // MARK: - Tests

    @Test("scanWritesPendingPairs: matching debit+credit on two accounts same day → transferPairID cross-set, isTransfer stays nil")
    func scanWritesPendingPairs() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let defaults = makeFreshDefaults()

        let accountA = makeAccount(in: ctx, name: "Savings")
        let accountB = makeAccount(in: ctx, name: "Current")
        try ctx.save()

        let debit  = makeExpense(in: ctx, amount: Decimal(1000),  accountID: accountA.id)
        let credit = makeExpense(in: ctx, amount: Decimal(-1000), accountID: accountB.id)
        try ctx.save()

        let service = TransferScanService(defaults: defaults)
        service.modelContext = ctx
        service.scan()

        // Both legs must have transferPairID cross-set
        #expect(debit.transferPairID == credit.id,
                "debit.transferPairID should equal credit.id (\(credit.id)), got \(String(describing: debit.transferPairID))")
        #expect(credit.transferPairID == debit.id,
                "credit.transferPairID should equal debit.id (\(debit.id)), got \(String(describing: credit.transferPairID))")

        // isTransfer must remain nil (pending, not auto-confirmed)
        #expect(debit.isTransfer == nil,
                "debit.isTransfer should remain nil (pending state), got \(String(describing: debit.isTransfer))")
        #expect(credit.isTransfer == nil,
                "credit.isTransfer should remain nil (pending state), got \(String(describing: credit.isTransfer))")
    }

    @Test("scanLeavesUnmatchedAlone: lone debit with no matching credit → transferPairID stays nil")
    func scanLeavesUnmatchedAlone() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let defaults = makeFreshDefaults()

        let accountA = makeAccount(in: ctx, name: "Savings")
        try ctx.save()

        let loneDebit = makeExpense(in: ctx, amount: Decimal(500), accountID: accountA.id)
        try ctx.save()

        let service = TransferScanService(defaults: defaults)
        service.modelContext = ctx
        service.scan()

        #expect(loneDebit.transferPairID == nil,
                "Unmatched debit should have transferPairID = nil, got \(String(describing: loneDebit.transferPairID))")
        #expect(loneDebit.isTransfer == nil,
                "Unmatched debit should have isTransfer = nil, got \(String(describing: loneDebit.isTransfer))")
    }

    @Test("secondScanIdempotent: after first scan pairs two legs and both are confirmed (isTransfer = true), second scan produces no new pairs")
    func secondScanIdempotent() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let defaults = makeFreshDefaults()

        let accountA = makeAccount(in: ctx, name: "Savings")
        let accountB = makeAccount(in: ctx, name: "Current")
        try ctx.save()

        let debit  = makeExpense(in: ctx, amount: Decimal(2000),  accountID: accountA.id)
        let credit = makeExpense(in: ctx, amount: Decimal(-2000), accountID: accountB.id)
        try ctx.save()

        // First scan — pairs the two legs
        let service = TransferScanService(defaults: defaults)
        service.modelContext = ctx
        service.scan()

        #expect(debit.transferPairID == credit.id, "First scan should set debit.transferPairID")
        #expect(credit.transferPairID == debit.id, "First scan should set credit.transferPairID")

        // User confirms: set isTransfer = true on both legs
        debit.isTransfer  = true
        credit.isTransfer = true
        try ctx.save()

        // Second scan — confirmed legs are skipped (D-10), no new transferPairIDs
        service.scan()

        // transferPairID must not change
        #expect(debit.transferPairID == credit.id,
                "After second scan, debit.transferPairID must still equal credit.id (not re-written)")
        #expect(credit.transferPairID == debit.id,
                "After second scan, credit.transferPairID must still equal debit.id (not re-written)")
        // isTransfer must remain true (confirmed, not reset)
        #expect(debit.isTransfer == true,
                "debit.isTransfer must remain true after second scan")
        #expect(credit.isTransfer == true,
                "credit.isTransfer must remain true after second scan")
    }

    @Test("confirmedLegSkipped (D-10): expense with isTransfer == true is never selected as a candidate")
    func confirmedLegSkipped() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let defaults = makeFreshDefaults()

        let accountA = makeAccount(in: ctx, name: "Savings")
        let accountB = makeAccount(in: ctx, name: "Current")
        try ctx.save()

        // Pre-confirmed legs (should be skipped by the scanner)
        let confirmedDebit  = makeExpense(in: ctx, amount: Decimal(500),  accountID: accountA.id, isTransfer: true)
        let confirmedCredit = makeExpense(in: ctx, amount: Decimal(-500), accountID: accountB.id, isTransfer: true)
        try ctx.save()

        // Capture original transferPairID values (should remain nil/unchanged)
        let originalDebitPairID  = confirmedDebit.transferPairID
        let originalCreditPairID = confirmedCredit.transferPairID

        let service = TransferScanService(defaults: defaults)
        service.modelContext = ctx
        service.scan()

        #expect(confirmedDebit.transferPairID == originalDebitPairID,
                "Confirmed debit should not be re-paired by scan, got \(String(describing: confirmedDebit.transferPairID))")
        #expect(confirmedCredit.transferPairID == originalCreditPairID,
                "Confirmed credit should not be re-paired by scan, got \(String(describing: confirmedCredit.transferPairID))")
    }

    @Test("rejectedLegSkipped (D-10): expense with isTransfer == false is never selected as a candidate")
    func rejectedLegSkipped() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let defaults = makeFreshDefaults()

        let accountA = makeAccount(in: ctx, name: "Savings")
        let accountB = makeAccount(in: ctx, name: "Current")
        try ctx.save()

        // Pre-rejected legs (should be skipped by the scanner)
        let rejectedDebit  = makeExpense(in: ctx, amount: Decimal(300),  accountID: accountA.id, isTransfer: false)
        let rejectedCredit = makeExpense(in: ctx, amount: Decimal(-300), accountID: accountB.id, isTransfer: false)
        try ctx.save()

        let originalDebitPairID  = rejectedDebit.transferPairID
        let originalCreditPairID = rejectedCredit.transferPairID

        let service = TransferScanService(defaults: defaults)
        service.modelContext = ctx
        service.scan()

        #expect(rejectedDebit.transferPairID == originalDebitPairID,
                "Rejected debit should not be re-paired, got \(String(describing: rejectedDebit.transferPairID))")
        #expect(rejectedCredit.transferPairID == originalCreditPairID,
                "Rejected credit should not be re-paired, got \(String(describing: rejectedCredit.transferPairID))")
    }

    @Test("firstRunFlagSet: after scan(), UserDefaults key 'transferScanFirstRunDone' is true (D-09)")
    func firstRunFlagSet() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let defaults = makeFreshDefaults()

        // Confirm the flag starts unset
        #expect(defaults.bool(forKey: "transferScanFirstRunDone") == false,
                "Flag should start false on fresh defaults")

        let service = TransferScanService(defaults: defaults)
        service.modelContext = ctx
        service.scan()

        #expect(defaults.bool(forKey: "transferScanFirstRunDone") == true,
                "Flag should be true after first scan()")
    }
}
