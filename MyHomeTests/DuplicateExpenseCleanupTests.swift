import Testing
import SwiftData
import Foundation
@testable import MyHome

/// DuplicateExpenseCleanupTests — verifies the one-time duplicate-removal pass.
///
/// Regression guard for the overlapping-sync bug that doubled Overview totals: two sync runs
/// inserted byte-identical expenses (same sourceAccount + gmailMessageID). This pass must
/// collapse each such group to a single row, keeping the earliest-created one, and never touch
/// manual expenses.
@MainActor
struct DuplicateExpenseCleanupTests {

    private func makeExpense(
        msgID: String?,
        account: String?,
        amount: Decimal,
        createdAt: Date,
        note: String = "x"
    ) -> Expense {
        let e = Expense(amount: amount, date: createdAt)
        e.note = note
        e.gmailMessageID = msgID
        e.sourceAccount = account
        e.createdAt = createdAt
        return e
    }

    @Test("Collapses a duplicate pair to one, keeping the earliest createdAt")
    func collapsesPairKeepingEarliest() {
        let t0 = Date(timeIntervalSince1970: 1_000)
        let t1 = Date(timeIntervalSince1970: 1_001)
        let first = makeExpense(msgID: "abc", account: "a@x.com", amount: 500, createdAt: t0)
        let second = makeExpense(msgID: "abc", account: "a@x.com", amount: 500, createdAt: t1)

        let victims = DuplicateExpenseCleanup.duplicatesToDelete(in: [first, second])

        #expect(victims.count == 1)
        #expect(victims.first === second)   // the later insert is deleted, earliest kept
    }

    @Test("Never deletes manual expenses (nil gmailMessageID), even with identical amounts")
    func ignoresManualExpenses() {
        let now = Date()
        let m1 = makeExpense(msgID: nil, account: nil, amount: 300, createdAt: now)
        let m2 = makeExpense(msgID: nil, account: nil, amount: 300, createdAt: now)

        #expect(DuplicateExpenseCleanup.duplicatesToDelete(in: [m1, m2]).isEmpty)
    }

    @Test("Same messageID but different accounts are not merged")
    func differentAccountsNotMerged() {
        let now = Date()
        let a = makeExpense(msgID: "shared", account: "a@x.com", amount: 100, createdAt: now)
        let b = makeExpense(msgID: "shared", account: "b@x.com", amount: 100, createdAt: now)

        #expect(DuplicateExpenseCleanup.duplicatesToDelete(in: [a, b]).isEmpty)
    }

    @Test("Four copies of one message collapse to one deletion of three")
    func quadCollapse() {
        let base = Date(timeIntervalSince1970: 2_000)
        let copies = (0..<4).map {
            makeExpense(msgID: "quad", account: "a@x.com", amount: 1791, createdAt: base.addingTimeInterval(Double($0)))
        }
        let victims = DuplicateExpenseCleanup.duplicatesToDelete(in: copies)
        #expect(victims.count == 3)
        #expect(!victims.contains { $0 === copies[0] })   // earliest survives
    }

    @Test("run(in:) actually deletes duplicate rows and returns the count")
    func runDeletesFromContext() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: Expense.self, MyHome.Category.self,
                                           Note.self, NoteBlock.self, configurations: config)
        let ctx = container.mainContext
        let t0 = Date(timeIntervalSince1970: 5_000)
        ctx.insert(makeExpense(msgID: "m", account: "a@x.com", amount: 999, createdAt: t0))
        ctx.insert(makeExpense(msgID: "m", account: "a@x.com", amount: 999, createdAt: t0.addingTimeInterval(1)))
        ctx.insert(makeExpense(msgID: "n", account: "a@x.com", amount: 111, createdAt: t0))
        try ctx.save()

        let removed = DuplicateExpenseCleanup.run(in: ctx)

        #expect(removed == 1)
        let remaining = try ctx.fetch(FetchDescriptor<Expense>())
        #expect(remaining.count == 2)
    }
}
