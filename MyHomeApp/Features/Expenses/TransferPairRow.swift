import SwiftUI
import SwiftData

/// Inbox row for a pending transfer pair in the "Possible Transfers" section.
///
/// Design mirrors ReviewInboxRow (same swipeActions pattern, same mutate-then-save contract).
///
/// A pending pair is encoded as: `transferPairID != nil && isTransfer == nil` (D-07).
/// The debit leg always has `amount > 0`; the credit leg has `amount < 0`.
///
/// Swipe actions (D-13, T-10-10):
/// - Confirm (green checkmark): sets `isTransfer = true` on BOTH legs, keeps transferPairID
///   cross-set (the pair remains linked for balance-move — D-16).
/// - Reject (destructive xmark): sets `isTransfer = false` on BOTH legs, clears transferPairID
///   on both (un-links the pair so both legs appear as normal expenses).
///
/// CR-01: BOTH legs are mutated BEFORE a single `try context.save()` — atomic commit or rollback.
struct TransferPairRow: View {

    let debit: Expense
    let credit: Expense

    @Environment(\.modelContext) private var context
    @Query(sort: \Account.sortOrder) private var accounts: [Account]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {

            // Header: amount + "Transfer?" badge
            HStack(alignment: .center, spacing: 8) {
                Text(debit.amount.formattedINR())
                    .font(.headline)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                Spacer(minLength: 8)

                Text("Transfer?")
                    .font(.caption2)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.purple, in: Capsule())
            }

            // Two-leg route: debit account → arrow → credit account
            HStack(spacing: 4) {
                Text(accountName(for: debit.accountID))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Image(systemName: "arrow.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(accountName(for: credit.accountID))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            // Date
            Text(debit.date.formattedForExpenseList())
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {

            // Destructive: Reject — marks both legs as non-transfer and unlinks the pair (D-13)
            Button(role: .destructive) {
                rejectPair()
            } label: {
                Label("Reject", systemImage: "xmark")
            }

            // Non-destructive: Confirm — marks both legs as confirmed transfers (D-13)
            Button {
                confirmPair()
            } label: {
                Label("Confirm", systemImage: "checkmark")
            }
            .tint(.green)
        }
    }

    // MARK: - Helpers

    private func accountName(for accountID: UUID?) -> String {
        guard let id = accountID else { return "Unassigned" }
        return accounts.first { $0.id == id }?.name ?? "Unknown"
    }

    // MARK: - Actions

    /// Confirms the pair — sets isTransfer = true on both legs; keeps transferPairID cross-set (D-16).
    ///
    /// CR-01: mutate BOTH legs before the single save so both commit or both roll back atomically.
    private func confirmPair() {
        debit.isTransfer = true
        credit.isTransfer = true
        debit.updatedAt = Date()
        credit.updatedAt = Date()
        // transferPairID intentionally left intact (D-16 balance-move relies on the link)
        do {
            try context.save()
        } catch {
            print("[TransferPairRow] confirmPair save failed: \(error)")
        }
    }

    /// Rejects the pair — sets isTransfer = false on both legs and clears transferPairID (D-13).
    ///
    /// CR-01: mutate BOTH legs before the single save so both commit or both roll back atomically.
    private func rejectPair() {
        debit.isTransfer = false
        credit.isTransfer = false
        debit.transferPairID = nil
        credit.transferPairID = nil
        debit.updatedAt = Date()
        credit.updatedAt = Date()
        do {
            try context.save()
        } catch {
            print("[TransferPairRow] rejectPair save failed: \(error)")
        }
    }
}
