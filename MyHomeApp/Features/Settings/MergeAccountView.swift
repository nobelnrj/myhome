import SwiftUI
import SwiftData

/// Sheet to merge the viewed account (`absorbed`) into another account (D-MERGE-01).
///
/// Motivation: one real-world balance can surface as several accounts — a savings account and
/// its debit card, or the same account masked as `••843` in one email and `••6843` in another.
/// Merging re-points every transaction onto the chosen survivor, folds the absorbed account's
/// ingestion identities into the survivor's alias set (so future emails route to one balance),
/// then deletes the now-empty absorbed account.
///
/// The **survivor is kept** (its name, icon, and balance baseline); the account you opened this
/// sheet from is the one that goes away. Pick the survivor to be the account whose balance
/// settings are correct — typically the savings account, not the debit card.
struct MergeAccountView: View {

    /// The account being merged away (the one the user opened this sheet from).
    let absorbed: Account
    /// Called after a successful merge so the caller can pop the now-deleted account's detail view.
    var onMerged: () -> Void

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @Query(sort: \Account.sortOrder) private var allAccounts: [Account]
    @Query private var allExpenses: [Expense]

    @State private var pendingSurvivor: Account?

    // MARK: - Derived

    /// Candidate survivors: every other non-archived account.
    private var candidates: [Account] {
        allAccounts.filter { !$0.isArchived && $0.id != absorbed.id }
    }

    /// Count of transactions currently attributed to the absorbed account (moved on merge).
    private var movingCount: Int {
        allExpenses.filter { $0.accountID == absorbed.id }.count
    }

    private func liveBalance(of account: Account) -> Decimal {
        AccountBalance.compute(
            baseline: account.balanceBaseline,
            asOf: account.balanceAsOfDate,
            expenses: allExpenses,
            accountID: account.id
        )
    }

    private var absorbedName: String { absorbed.name ?? "This account" }
    private var txnNoun: String { "transaction\(movingCount == 1 ? "" : "s")" }

    private var footerText: String {
        "“\(absorbedName)” and its \(movingCount) \(txnNoun) will move into the account you pick, then be removed. The account you pick keeps its balance settings."
    }

    private func confirmTitle(_ survivor: Account) -> String {
        "Merge into “\(survivor.name ?? "account")”?"
    }

    private func confirmMessage(_ survivor: Account) -> String {
        "\(movingCount) \(txnNoun) will move into “\(survivor.name ?? "account")”. This can’t be undone automatically."
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            Group {
                if candidates.isEmpty {
                    ContentUnavailableView(
                        "No Other Accounts",
                        systemImage: "rectangle.stack.badge.minus",
                        description: Text("Add another account first, then merge this one into it.")
                    )
                } else {
                    List {
                        Section {
                            ForEach(candidates) { survivor in
                                Button { pendingSurvivor = survivor } label: {
                                    survivorRow(survivor)
                                }
                                .buttonStyle(.plain)
                            }
                        } header: {
                            Text("Merge into")
                        } footer: {
                            Text(footerText)
                        }
                    }
                    .listStyle(.insetGrouped)
                    .scrollContentBackground(.hidden)
                    .background(DesignTokens.bgCanvas)
                }
            }
            .navigationTitle("Merge Account")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .confirmationDialog(
                pendingSurvivor.map(confirmTitle) ?? "",
                isPresented: Binding(
                    get: { pendingSurvivor != nil },
                    set: { if !$0 { pendingSurvivor = nil } }
                ),
                titleVisibility: .visible,
                presenting: pendingSurvivor
            ) { survivor in
                Button("Merge and Remove “\(absorbedName)”", role: .destructive) {
                    performMerge(into: survivor)
                }
                Button("Cancel", role: .cancel) { pendingSurvivor = nil }
            } message: { survivor in
                Text(confirmMessage(survivor))
            }
        }
    }

    // MARK: - Rows

    private func survivorRow(_ survivor: Account) -> some View {
        HStack(spacing: 12) {
            IconTile(
                symbol: survivor.symbolName ?? "creditcard",
                color: Color(hex: survivor.colorHex ?? "#636366"),
                size: 36
            )
            VStack(alignment: .leading, spacing: 2) {
                Text(survivor.name ?? "Account")   // T-09-06: plain Text
                    .font(.body)
                    .foregroundStyle(DesignTokens.label)
                Text(liveBalance(of: survivor).formattedINR())
                    .font(.subheadline)
                    .foregroundStyle(DesignTokens.label2)
            }
            Spacer()
            Image(systemName: "arrow.right.circle")
                .foregroundStyle(DesignTokens.label3)
        }
        .frame(minHeight: 44)
        .contentShape(Rectangle())
    }

    // MARK: - Merge

    private func performMerge(into survivor: Account) {
        AccountMerger.merge(absorbed: absorbed, into: survivor, allExpenses: allExpenses)
        context.delete(absorbed)
        do {
            try context.save()   // CR-01: explicit save
        } catch {
            assertionFailure("Failed to merge accounts: \(error)")
            return
        }
        pendingSurvivor = nil
        dismiss()
        onMerged()
    }
}
