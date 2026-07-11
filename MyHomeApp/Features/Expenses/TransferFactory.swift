import Foundation

/// Pure builder for a manual self-transfer between two of the user's own accounts.
///
/// A transfer is modelled as TWO cross-linked `Expense` rows (the same shape the Gmail
/// scanner produces, and the same shape `AccountBalance.compute` / `BudgetCalculator`
/// already understand — see `store-appgroup-only` / `cashflow-transfer-exclusion` notes):
///
///   - **Debit leg** (money leaving `from`): amount stored POSITIVE → lowers the `from`
///     balance via `baseline − net` (AccountBalance sign convention).
///   - **Credit leg** (money arriving in `to`): amount stored NEGATIVE → raises the `to`
///     balance.
///
/// Both legs are created already-confirmed (`isTransfer = true`) with `transferPairID`
/// cross-set to each other's `id` (matches TransferScanService D-07 / TransferPairRow.confirmPair).
/// Because both legs carry `isTransfer = true`, `BudgetCalculator.isTransferForCashFlow`
/// excludes them from hero income/spend — moving your own money never counts as income/spend.
///
/// Pure (no SwiftData insert, no SwiftUI) so it is unit-testable without a ModelContainer.
/// The caller inserts both returned expenses and saves atomically.
enum TransferFactory {

    /// Build the two linked legs of a self-transfer.
    ///
    /// - Parameters:
    ///   - amount: The transfer magnitude. Callers pass a positive value; the sign is applied
    ///     per leg here. `abs()` is taken defensively so a stray negative can't invert the legs.
    ///   - from: Source account (money leaves here). Its `id` attributes the debit leg.
    ///   - to: Destination account (money arrives here). Its `id` attributes the credit leg.
    ///   - date: Transaction date for both legs (UTC instant; formatted at display time).
    ///   - note: Optional user memo. When nil, each leg gets an auto memo naming the counterpart.
    /// - Returns: `(debit, credit)` — the source-side outflow and destination-side inflow.
    static func makeTransfer(
        amount: Decimal,
        from: Account,
        to: Account,
        date: Date,
        note: String?
    ) -> (debit: Expense, credit: Expense) {
        let magnitude = abs(amount)

        let fromName = from.name ?? "account"
        let toName = to.name ?? "account"
        let trimmed = note?.trimmingCharacters(in: .whitespaces)
        let userNote = (trimmed?.isEmpty ?? true) ? nil : trimmed

        // Debit leg: positive amount, attributed to the source account.
        let debit = Expense(
            amount: magnitude,
            date: date,
            note: userNote ?? "Transfer to \(toName)"
        )
        debit.accountID = from.id

        // Credit leg: negative amount, attributed to the destination account.
        let credit = Expense(
            amount: -magnitude,
            date: date,
            note: userNote ?? "Transfer from \(fromName)"
        )
        credit.accountID = to.id

        // Cross-link + confirm both legs (D-16: balance-move relies on the pair link staying intact).
        debit.isTransfer = true
        credit.isTransfer = true
        debit.transferPairID = credit.id
        credit.transferPairID = debit.id

        return (debit, credit)
    }
}
