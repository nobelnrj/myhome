import SwiftUI
import SwiftData

/// First-launch review sheet for auto-created accounts (D-02).
///
/// Displayed after V5→V6 migration when `accountReviewPending` is true. Allows the user
/// to rename, retype, or delete auto-created accounts before they are treated as permanent.
/// Mirrors ManageCategoriesView inline-rename + confirmationDialog delete pattern.
///
/// Threat mitigations:
/// - T-09-06: Account name via plain Text() / TextField — never AttributedString(markdown:).
struct MigrationReviewSheet: View {

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    /// All accounts — filter in-view to show only auto-created (sourceLabel non-nil).
    @Query private var allAccounts: [Account]

    private var autoCreatedAccounts: [Account] {
        allAccounts.filter { $0.sourceLabel != nil }
    }

    @State private var renamingAccount: Account? = nil
    @State private var renameText: String = ""
    @State private var nameError: String? = nil
    @State private var accountToDelete: Account? = nil
    @State private var showDeleteConfirmation = false

    var body: some View {
        NavigationStack {
            List {
                Section(footer: Text("Changes here are permanent. Tap Done when finished.")
                    .foregroundStyle(DesignTokens.label2)) {
                    ForEach(autoCreatedAccounts) { account in
                        accountReviewRow(account)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(DesignTokens.bgCanvas)
            .navigationTitle("Review Accounts")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        do {
                            try? context.save()  // CR-01: persist any pending edits
                        }
                        UserDefaults.standard.set(false, forKey: "accountReviewPending")
                        dismiss()
                    }
                    .foregroundStyle(DesignTokens.accentText)
                }
            }
            .confirmationDialog(
                "Delete Account?",
                isPresented: $showDeleteConfirmation,
                titleVisibility: .visible
            ) {
                Button("Delete Account", role: .destructive) {
                    if let acc = accountToDelete {
                        context.deleteSynced(acc, kind: .account)
                        try? context.save()  // CR-01
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("All expenses attributed to this account will become unassigned. This cannot be undone.")
            }
        }
    }

    // MARK: - Account Review Row

    @ViewBuilder
    private func accountReviewRow(_ account: Account) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if renamingAccount?.persistentModelID == account.persistentModelID {
                // Rename mode: inline TextField (mirrors ManageCategoriesView pattern)
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        TextField("Account name", text: $renameText)
                            .font(.body)
                            .submitLabel(.done)
                            .onSubmit { saveRename(for: account) }
                        Button("Done") { saveRename(for: account) }
                            .font(.body)
                            .tint(DesignTokens.accentText)
                    }
                    .frame(minHeight: 44)
                    if let error = nameError {
                        Text(error)
                            .font(.subheadline)
                            .foregroundStyle(DesignTokens.negative)
                    }
                }
            } else {
                // Normal row: tap to rename
                Button(action: {
                    renamingAccount = account
                    renameText = account.name ?? ""
                    nameError = nil
                }) {
                    HStack {
                        Text(account.name ?? "")  // T-09-06: plain Text
                            .font(.body)
                            .foregroundStyle(DesignTokens.label2)
                        Spacer()
                    }
                    .frame(minHeight: 44)
                }
                .buttonStyle(.plain)
            }

            // Segmented type picker (always visible)
            Picker("", selection: Binding(
                get: { account.typeRaw ?? "savings" },
                set: { newValue in
                    account.typeRaw = newValue
                    try? context.save()  // CR-01: save type change immediately
                }
            )) {
                Text("Savings").tag("savings")
                Text("Current").tag("current")
                Text("Credit Card").tag("credit_card")
            }
            .pickerStyle(.segmented)
            .tint(DesignTokens.accent)
        }
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                accountToDelete = account
                showDeleteConfirmation = true
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        .listRowBackground(DesignTokens.surfaceRaised)
    }

    // MARK: - Rename

    private func saveRename(for account: Account) {
        let trimmed = renameText.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            nameError = "Account name cannot be empty."
            return
        }
        account.name = trimmed
        do {
            try context.save()  // CR-01
            nameError = nil
            renamingAccount = nil
        } catch {
            assertionFailure("Failed to save rename: \(error)")
        }
    }
}
