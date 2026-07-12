import SwiftUI
import SwiftData

/// Sheet for recording a manual self-transfer between two of the user's own accounts.
///
/// Motivating case: a recurring ₹15k top-up from ICICI (salary) into the shared HDFC account
/// never arrives as an ingestible email, so it can't be captured as an expense and the balances
/// drift. A transfer is not a spend — it's money moving between the user's own accounts — so it
/// gets its own entry path (the `+` menu → "New Transfer") rather than the expense sheet.
///
/// Persistence: builds two cross-linked legs via `TransferFactory` (debit on `from`, credit on
/// `to`), inserts both, and saves atomically. Both legs are `isTransfer = true`, so they move
/// balances (`AccountBalance.compute`) but are excluded from hero cash-flow
/// (`BudgetCalculator.isTransferForCashFlow`).
///
/// Security: T-01-03 amount guard — non-zero AND abs(amount) < 1_000_000_000.
/// from ≠ to enforced before Save is enabled (a transfer to the same account is a no-op).
struct AddTransferView: View {

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    // Amount state (magnitude only — sign is applied per leg by TransferFactory)
    @State private var amountString: String = ""
    @State private var amountShakeOffset: CGFloat = 0
    @State private var amountIsError: Bool = false

    @State private var fromAccount: Account? = nil
    @State private var toAccount: Account? = nil
    @State private var date: Date = Date()
    @State private var note: String = ""
    @State private var showDatePicker: Bool = false

    // Active accounts only — archived accounts can't be a transfer endpoint (D-08 / T-09-09).
    @Query(filter: #Predicate<Account> { !$0.isArchived }, sort: \Account.sortOrder)
    private var activeAccounts: [Account]

    // MARK: - Computed

    private var parsedAmount: Decimal? {
        guard !amountString.isEmpty, let value = Decimal(string: amountString) else { return nil }
        return value
    }

    /// Enabled only with a positive amount, both endpoints chosen, and they differ.
    private var isSaveEnabled: Bool {
        guard let amount = parsedAmount, amount != 0, abs(amount) < Decimal(1_000_000_000) else { return false }
        guard let from = fromAccount, let to = toAccount else { return false }
        return from.id != to.id
    }

    private var displayAmount: String {
        guard let value = parsedAmount, value != 0 else { return Decimal(0).formattedINR() }
        return abs(value).formattedINR()
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 8) {
                    amountSection
                        .padding(.top, 16)
                    routeSection
                        .padding(.top, 8)
                    optionalSection
                        .padding(.top, 8)
                }
                .padding(.horizontal, 16)
            }
            .background(DesignTokens.bgCanvas)
            .navigationTitle("New Transfer")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save Transfer") { saveTransfer() }
                        .disabled(!isSaveEnabled)
                        .tint(DesignTokens.accentText)
                }
            }
        }
    }

    // MARK: - Amount Section

    private var amountSection: some View {
        VStack(spacing: 16) {
            Text(displayAmount)
                .font(.largeTitle)
                .fontWeight(.bold)
                .foregroundStyle(amountIsError ? DesignTokens.negative : DesignTokens.label)
                .frame(maxWidth: .infinity, alignment: .center)
                .accessibilityValue(displayAmount)
                .offset(x: amountShakeOffset)
                .animation(.default, value: amountShakeOffset)

            // Always-visible custom decimal keypad (Pitfall 6 — NO system keyboard)
            DecimalKeypadView(displayString: $amountString)
        }
        .padding(16)
        .background(DesignTokens.surfaceRaised)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - From / To Section

    private var routeSection: some View {
        VStack(spacing: 8) {
            accountRow(label: "From", selection: $fromAccount, excluding: toAccount)
            accountRow(label: "To", selection: $toAccount, excluding: fromAccount)
        }
    }

    /// A single From/To picker row. Uses a Menu (not the shared AccountPickerView) so there is
    /// no "Unassigned" option — a transfer endpoint must be a real account. The counterpart is
    /// excluded so from and to can never be set to the same account.
    private func accountRow(label: String, selection: Binding<Account?>, excluding: Account?) -> some View {
        Menu {
            ForEach(activeAccounts.filter { $0.id != excluding?.id }) { account in
                Button {
                    selection.wrappedValue = account
                } label: {
                    if let symbol = account.symbolName {
                        Label(account.name ?? "Account", systemImage: symbol)
                    } else {
                        Text(account.name ?? "Account")
                    }
                }
            }
        } label: {
            HStack {
                Text(label)
                    .foregroundStyle(DesignTokens.label)
                Spacer()
                if let acc = selection.wrappedValue, let name = acc.name {
                    if let symbol = acc.symbolName {
                        Image(systemName: symbol)
                            .font(.subheadline)
                            .foregroundStyle(DesignTokens.label2)
                    }
                    // Plain Text — never AttributedString(markdown:) (T-02-15)
                    Text(name)
                        .foregroundStyle(DesignTokens.label2)
                        .font(.subheadline)
                } else {
                    Text("Choose account")
                        .foregroundStyle(DesignTokens.label2)
                        .font(.subheadline)
                }
                Image(systemName: "chevron.up.chevron.down")
                    .foregroundStyle(DesignTokens.label2)
                    .font(.caption)
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 16)
            .frame(minHeight: 44)
        }
        .background(DesignTokens.surfaceRaised)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Optional Fields Section

    private var optionalSection: some View {
        VStack(spacing: 8) {
            // Date row
            VStack(spacing: 0) {
                Button(action: { showDatePicker.toggle() }) {
                    HStack {
                        Text("Date")
                            .foregroundStyle(DesignTokens.label)
                        Spacer()
                        Text(date.formattedForDatePickerRow())
                            .foregroundStyle(DesignTokens.label2)
                            .font(.subheadline)
                        Image(systemName: showDatePicker ? "chevron.up" : "chevron.down")
                            .foregroundStyle(DesignTokens.label2)
                            .font(.caption)
                    }
                    .padding(.vertical, 12)
                    .padding(.horizontal, 16)
                    .frame(minHeight: 44)
                }
                .buttonStyle(.plain)

                if showDatePicker {
                    Divider()
                        .padding(.horizontal, 16)
                    DatePicker(
                        "Select date",
                        selection: $date,
                        displayedComponents: [.date, .hourAndMinute]
                    )
                    .datePickerStyle(.graphical)
                    .padding(.horizontal, 8)
                    .padding(.bottom, 8)
                    .labelsHidden()
                }
            }
            .background(DesignTokens.surfaceRaised)
            .clipShape(RoundedRectangle(cornerRadius: 12))

            // Note field (T-01-06: plain TextField — never AttributedString(markdown:))
            HStack {
                Text("Note")
                    .foregroundStyle(DesignTokens.label)
                Spacer()
                TextField("Optional memo", text: $note)
                    .multilineTextAlignment(.trailing)
                    .foregroundStyle(DesignTokens.label2)
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 16)
            .frame(minHeight: 44)
            .background(DesignTokens.surfaceRaised)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    // MARK: - Actions

    private func saveTransfer() {
        guard let amount = parsedAmount, amount != 0, abs(amount) < Decimal(1_000_000_000) else {
            shakeAmount()
            return
        }
        guard let from = fromAccount, let to = toAccount, from.id != to.id else {
            shakeAmount()
            return
        }
        let trimmedNote: String? = note.trimmingCharacters(in: .whitespaces).isEmpty
            ? nil
            : note.trimmingCharacters(in: .whitespaces)

        let pair = TransferFactory.makeTransfer(
            amount: amount,
            from: from,
            to: to,
            date: date,
            note: trimmedNote
        )
        // CR-01: insert BOTH legs before the single save so both commit or both roll back atomically.
        context.insert(pair.debit)
        context.insert(pair.credit)
        do {
            try context.save()
        } catch {
            assertionFailure("Failed to save transfer: \(error)")
            print("Failed to save transfer: \(error)")
            shakeAmount()
            return
        }
        Haptics.success()
        dismiss()
    }

    private func shakeAmount() {
        amountIsError = true
        withAnimation(.easeInOut(duration: 0.05).repeatCount(5, autoreverses: true)) {
            amountShakeOffset = 8
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            amountShakeOffset = 0
            amountIsError = false
        }
    }
}
