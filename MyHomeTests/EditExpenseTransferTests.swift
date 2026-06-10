import Testing
import SwiftData
import Foundation
@testable import MyHome

/// Tests for the manual mark/unmark transfer toggle in EditExpenseView (XFER-05, D-14).
///
/// These tests exercise the pure mutation logic extracted into
/// `EditExpenseView.applyTransferMark(_:expense:context:)` — no SwiftUI involved.
@MainActor
struct EditExpenseTransferTests {

    private func makeContainer() throws -> ModelContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: Expense.self, Account.self, configurations: config)
    }

    // MARK: - manualMarkSetsSoloTransfer

    @Test("Marking an unpaired expense sets isTransfer = true, leaves transferPairID nil")
    func manualMarkSetsSoloTransfer() throws {
        let container = try makeContainer()
        let ctx = container.mainContext

        let expense = Expense(amount: Decimal(500))
        ctx.insert(expense)
        try ctx.save()

        // Apply mark
        EditExpenseView.applyTransferMark(true, expense: expense, context: ctx)
        try ctx.save()

        #expect(expense.isTransfer == true)
        #expect(expense.transferPairID == nil)
    }

    // MARK: - manualUnmarkResetsTransfer

    @Test("Unmarking a solo transfer (no pair) resets isTransfer to nil, transferPairID stays nil")
    func manualUnmarkResetsTransfer() throws {
        let container = try makeContainer()
        let ctx = container.mainContext

        let expense = Expense(amount: Decimal(500))
        expense.isTransfer = true
        // transferPairID remains nil (solo)
        ctx.insert(expense)
        try ctx.save()

        // Apply unmark
        EditExpenseView.applyTransferMark(false, expense: expense, context: ctx)
        try ctx.save()

        #expect(expense.isTransfer == nil)
        #expect(expense.transferPairID == nil)
    }

    // MARK: - unmarkCascadeUnlinksCounterpart

    @Test("Unmarking one leg of a confirmed pair resets BOTH legs (cascade unlink)")
    func unmarkCascadeUnlinksCounterpart() throws {
        let container = try makeContainer()
        let ctx = container.mainContext

        // Set up a confirmed transfer pair (debit + credit linked)
        let debit = Expense(amount: Decimal(1000))
        let credit = Expense(amount: Decimal(-1000))

        let pairID = UUID()
        debit.isTransfer = true
        debit.transferPairID = credit.id
        credit.isTransfer = true
        credit.transferPairID = debit.id

        ctx.insert(debit)
        ctx.insert(credit)
        try ctx.save()

        // Unmark the debit leg — should cascade-reset BOTH legs
        EditExpenseView.applyTransferMark(false, expense: debit, context: ctx)
        try ctx.save()

        // Debit leg reset
        #expect(debit.isTransfer == nil)
        #expect(debit.transferPairID == nil)

        // Credit leg also reset (cascade)
        #expect(credit.isTransfer == nil)
        #expect(credit.transferPairID == nil)

        _ = pairID // suppress unused warning
    }

    // MARK: - markDoesNotClearTransferPairID

    @Test("Marking a PENDING-paired expense goes solo (own pairID cleared) and releases the partner (CR-01)")
    func markReleasesPendingPartnerAndGoesSolo() throws {
        let container = try makeContainer()
        let ctx = container.mainContext

        // A pending pair: both legs isTransfer == nil, cross-linked by transferPairID.
        let debit = Expense(amount: Decimal(750))
        let credit = Expense(amount: Decimal(-750))
        debit.transferPairID = credit.id
        credit.transferPairID = debit.id
        ctx.insert(debit)
        ctx.insert(credit)
        try ctx.save()

        // Mark the debit leg as a solo transfer.
        EditExpenseView.applyTransferMark(true, expense: debit, context: ctx)
        try ctx.save()

        // The marked leg becomes a proper solo transfer: isTransfer == true, no dangling pair.
        #expect(debit.isTransfer == true)
        #expect(debit.transferPairID == nil)

        // The partner is released so it cannot become an inbox ghost: link cleared, still
        // unevaluated (nil) so the scorer can re-pair it later.
        #expect(credit.transferPairID == nil)
        #expect(credit.isTransfer == nil)
    }
}
