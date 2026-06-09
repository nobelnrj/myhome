import SwiftUI
import SwiftData

/// Sheet for picking (or clearing) an account on an expense.
///
/// Layout (UI-SPEC Screen 4):
/// - NavigationStack-in-sheet titled "Account" (inline)
/// - Toolbar: leading "Cancel" (dismiss with no change), trailing "Clear" (only when an account is
///   currently selected — sets nil + dismisses, .systemRed tint, .destructiveAction placement)
/// - List (.insetGrouped): "None"/"Unassigned" row at top, then ForEach over active accounts
/// - Selection checkmark in .accentColor on the active row
///
/// Security: T-09-09 — archived accounts excluded via @Query predicate (D-08 / Pitfall 6).
/// Plain Text(account.name ?? "") only; never AttributedString(markdown:) (T-02-15).
struct AccountPickerView: View {

    @Binding var selectedAccount: Account?
    @Environment(\.dismiss) private var dismiss
    // Filter archived accounts from picker (D-08 / Pitfall 6 / T-09-09)
    @Query(filter: #Predicate<Account> { !$0.isArchived }, sort: \Account.sortOrder)
    private var activeAccounts: [Account]

    // MARK: - Body

    var body: some View {
        NavigationStack {
            List {
                // "None" / "Unassigned" row — top of list (represents selectedAccount = nil)
                Button(action: {
                    selectedAccount = nil
                    dismiss()
                }) {
                    HStack {
                        Image(systemName: "circle.slash")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .frame(width: 24, height: 24)
                            .accessibilityHidden(true)
                        Text("Unassigned")
                            .font(.body)
                            .foregroundStyle(.primary)
                        Spacer()
                        if selectedAccount == nil {
                            Image(systemName: "checkmark")
                                .foregroundStyle(Color.accentColor)
                        }
                    }
                    .frame(minHeight: 44)
                }
                .buttonStyle(.plain)

                // Account rows — sorted by sortOrder via @Query; archived excluded
                ForEach(activeAccounts) { account in
                    Button(action: {
                        selectedAccount = account
                        dismiss()
                    }) {
                        HStack {
                            if let symbol = account.symbolName {
                                Image(systemName: symbol)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .frame(width: 24, height: 24)
                                    .accessibilityHidden(true)
                            }
                            // T-02-15: plain Text — never AttributedString(markdown:)
                            Text(account.name ?? "")
                                .font(.body)
                                .foregroundStyle(.primary)
                            Spacer()
                            if selectedAccount?.persistentModelID == account.persistentModelID {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(Color.accentColor)
                            }
                        }
                        .frame(minHeight: 44)
                    }
                    .buttonStyle(.plain)
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Account")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                if selectedAccount != nil {
                    ToolbarItem(placement: .destructiveAction) {
                        Button("Clear") {
                            selectedAccount = nil
                            dismiss()
                        }
                        .tint(Color(.systemRed))
                    }
                }
            }
        }
    }
}
