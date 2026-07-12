import SwiftUI
import SwiftData

/// CRUD list of bank accounts under Settings (D-06, ACCT-01/02/03/07).
///
/// Active accounts are listed in the main section; archived accounts are in a collapsed
/// DisclosureGroup (D-08). Mirrors ManageCategoriesView structure and patterns.
///
/// Threat mitigations:
/// - T-09-08: Lookup-before-insert (case-insensitive) prevents duplicate account names.
/// - T-09-06: Account name displayed via plain Text() — never AttributedString(markdown:).
/// - T-09-SC: No third-party packages used.
struct AccountsListView: View {

    @Environment(\.modelContext) private var context

    /// All accounts sorted by sortOrder (ascending — new accounts prepend via min-1).
    @Query(sort: \Account.sortOrder) private var allAccounts: [Account]

    /// All expenses — used for live balance in each account row.
    @Query private var allExpenses: [Expense]

    // MARK: - Computed splits

    private var activeAccounts: [Account] { allAccounts.filter { !$0.isArchived } }
    private var archivedAccounts: [Account] { allAccounts.filter { $0.isArchived } }

    /// Auto-created accounts still awaiting review (sourceLabel non-nil). Used to gate the
    /// migration-review banner so it never shows when there is nothing to review (e.g. a
    /// stale `accountReviewPending` flag left over from a reset store).
    private var hasAutoCreatedAccounts: Bool { allAccounts.contains { $0.sourceLabel != nil } }

    // MARK: - State

    @State private var showAddSheet = false
    @State private var accountToDelete: Account? = nil
    @State private var showDeleteConfirmation = false
    @State private var archivedExpanded = false
    @State private var showReviewSheet = false
    @State private var accountReviewPending: Bool =
        UserDefaults.standard.bool(forKey: "accountReviewPending")

    // MARK: - Body

    var body: some View {
        Group {
            if allAccounts.isEmpty {
                ContentUnavailableView(
                    "No Accounts Yet",
                    systemImage: "building.columns",
                    description: Text("Tap + to add your first bank account.")
                )
            } else {
                List {
                    // MARK: Migration Review Banner (D-02)
                    // Gated on hasAutoCreatedAccounts so a stale flag never shows an empty banner.
                    if accountReviewPending && hasAutoCreatedAccounts {
                        Section {
                            HStack(alignment: .top, spacing: 12) {
                                Image(systemName: "exclamationmark.circle.fill")
                                    .foregroundStyle(DesignTokens.orange)
                                    .font(.title3)
                                    .accessibilityHidden(true)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Review Auto-Created Accounts")
                                        .font(.body.weight(.semibold))
                                    Text("These accounts were created from your transaction history. Rename, change type, or delete before they're finalized.")
                                        .font(.subheadline)
                                        .foregroundStyle(DesignTokens.label2)
                                }
                            }
                            Button("Review Now →") {
                                showReviewSheet = true
                            }
                            .font(.body)
                            .tint(DesignTokens.accentText)
                        }
                    }

                    // MARK: Active Accounts

                    Section("Active") {
                        ForEach(activeAccounts) { account in
                            NavigationLink(destination: AccountDetailView(account: account)) {
                                accountRow(account)
                            }
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    accountToDelete = account
                                    showDeleteConfirmation = true
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }

                                Button {
                                    account.isArchived = true
                                    try? context.save()  // CR-01: explicit save
                                } label: {
                                    Label("Archive", systemImage: "archivebox")
                                }
                                .tint(DesignTokens.orange)
                            }
                        }
                    }

                    // MARK: Archived Accounts (collapsed DisclosureGroup, D-08)

                    if !archivedAccounts.isEmpty {
                        Section {
                            DisclosureGroup(
                                "Archived (\(archivedAccounts.count))",
                                isExpanded: $archivedExpanded
                            ) {
                                ForEach(archivedAccounts) { account in
                                    accountRow(account)
                                        .opacity(0.5)
                                        .swipeActions(edge: .trailing) {
                                            Button {
                                                account.isArchived = false
                                                try? context.save()  // CR-01: explicit save
                                            } label: {
                                                Label("Unarchive", systemImage: "arrow.uturn.left")
                                            }
                                            .tint(DesignTokens.catSubscriptions)
                                        }
                                }
                            }
                        }
                    }
                }
                .listStyle(.insetGrouped)
                .scrollContentBackground(.hidden)
                .background(DesignTokens.bgCanvas)
            }
        }
        .navigationTitle("Accounts")
        .onAppear {
            // Self-heal a stale review flag: if it's set but no auto-created accounts exist
            // (e.g. the store was reset while UserDefaults persisted), clear it so the badge
            // and banner stop showing with nothing to review.
            if accountReviewPending && !hasAutoCreatedAccounts {
                UserDefaults.standard.set(false, forKey: "accountReviewPending")
                accountReviewPending = false
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showAddSheet = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Add Account")
            }
        }
        .sheet(isPresented: $showAddSheet) {
            EditAccountView(account: nil)
        }
        .sheet(isPresented: $showReviewSheet, onDismiss: {
            // Refresh the pending flag after review sheet closes
            accountReviewPending = UserDefaults.standard.bool(forKey: "accountReviewPending")
        }) {
            MigrationReviewSheet()
        }
        .confirmationDialog(
            "Delete Account?",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete Account", role: .destructive) {
                if let acc = accountToDelete { deleteAccount(acc) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("All expenses attributed to this account will become unassigned. This cannot be undone.")
        }
    }

    // MARK: - Account Row

    @ViewBuilder
    private func accountRow(_ account: Account) -> some View {
        let balance = AccountBalance.compute(
            baseline: account.balanceBaseline,
            asOf: account.balanceAsOfDate,
            expenses: allExpenses,
            accountID: account.id
        )
        HStack(spacing: 16) {
            IconTile(
                symbol: account.symbolName ?? "creditcard",
                color: Color(hex: account.colorHex ?? "#636366"),
                size: 30
            )
            VStack(alignment: .leading, spacing: 0) {
                Text(account.name ?? "")  // T-09-06: plain Text — never AttributedString(markdown:)
                    .font(.body)
                    .foregroundStyle(DesignTokens.label)
                Text(displayType(account.typeRaw))
                    .font(.subheadline)
                    .foregroundStyle(DesignTokens.label2)
            }
            Spacer(minLength: 8)
            Text(balance.formattedINR())
                .font(.body)
                .foregroundStyle(balanceColor(balance: balance, typeRaw: account.typeRaw))
            Image(systemName: "chevron.right")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(DesignTokens.label3)
        }
        .frame(minHeight: 44)
    }

    // MARK: - Helpers

    private func displayType(_ typeRaw: String?) -> String {
        switch typeRaw {
        case "savings": return "Savings"
        case "current": return "Current"
        case "credit_card": return "Credit Card"
        default: return "Savings"
        }
    }

    private func balanceColor(balance: Decimal, typeRaw: String?) -> Color {
        // D-09: CC balance is always red (negative = amount owed); savings/current green/label2
        if typeRaw == "credit_card" { return DesignTokens.negative }
        if balance > 0 { return DesignTokens.positive }
        if balance < 0 { return DesignTokens.negative }
        return DesignTokens.label2
    }

    // MARK: - CRUD Actions

    private func deleteAccount(_ account: Account) {
        context.delete(account)
        do {
            try context.save()  // CR-01: explicit save
        } catch {
            assertionFailure("Failed to delete account: \(error)")
        }
    }
}
