import SwiftUI
import SwiftData

/// Sheet for editing an existing expense.
///
/// Layout (UI-SPEC Screen 3):
/// - Identical form layout to AddExpenseView (DecimalKeypadView always visible)
/// - NavigationStack-in-sheet titled "Edit Expense" (inline)
/// - Toolbar: leading "Cancel" (discards, no confirmation), trailing "Save Expense" (enabled only when isDirty)
/// - Bottom: destructive "Delete Expense" button with confirmation action sheet
///
/// Uses @Bindable for live two-way binding to the @Model (no @StateObject/@ObservedObject/@Published).
/// Security: T-01-07 — dismiss cleanly after save/delete (Pitfall 19).
struct EditExpenseView: View {

    @Bindable var expense: Expense
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    // Local state mirrors expense fields so we can track isDirty and dismiss on Cancel without mutating
    @State private var amountString: String = ""
    @State private var isNegative: Bool = false
    @State private var date: Date = Date()
    @State private var note: String = ""
    @State private var showDatePicker: Bool = false
    @State private var showDeleteConfirmation: Bool = false
    @State private var amountShakeOffset: CGFloat = 0
    @State private var amountIsError: Bool = false

    // MARK: - Computed

    private var parsedAmount: Decimal? {
        guard !amountString.isEmpty, let value = Decimal(string: amountString) else { return nil }
        return isNegative ? -value : value
    }

    private var isDirty: Bool {
        guard let amount = parsedAmount else { return false }
        return amount != expense.amount
            || date != expense.date
            || (note.trimmingCharacters(in: .whitespaces).isEmpty ? nil : note.trimmingCharacters(in: .whitespaces)) != expense.note
    }

    private var isSaveEnabled: Bool {
        guard let amount = parsedAmount else { return false }
        return amount != 0 && isDirty
    }

    private var displayAmount: String {
        guard let value = parsedAmount, value != 0 else {
            return Decimal(0).formattedINR()
        }
        return value.formattedINR()
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    amountSection
                        .padding(.top, 16)

                    optionalSection
                        .padding(.top, 8)

                    deleteSection
                        .padding(.top, 24)
                        .padding(.bottom, 32)
                }
                .padding(.horizontal, 16)
            }
            .navigationTitle("Edit Expense")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        // T-01-07: dismiss cleanly; no same-tick mutation (Pitfall 19)
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save Expense") {
                        saveExpense()
                    }
                    .disabled(!isSaveEnabled)
                    .tint(.accentColor)
                }
            }
            .confirmationDialog(
                "Delete Expense?",
                isPresented: $showDeleteConfirmation,
                titleVisibility: .visible
            ) {
                Button("Delete Expense", role: .destructive) {
                    deleteExpense()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This expense will be permanently removed.")
            }
        }
        .onAppear {
            initializeFields()
        }
    }

    // MARK: - Amount Section

    private var amountSection: some View {
        VStack(spacing: 16) {
            HStack(spacing: 12) {
                Button(action: { isNegative.toggle() }) {
                    Image(systemName: "plus.slash.minus")
                        .font(.title2)
                        .frame(minWidth: 44, minHeight: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Toggle sign")

                Text(displayAmount)
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .foregroundStyle(amountIsError ? Color(.systemRed) : (isNegative && parsedAmount != nil ? Color(.systemGreen) : .primary))
                    .frame(maxWidth: .infinity, alignment: .center)
                    .accessibilityValue(displayAmount)
                    .offset(x: amountShakeOffset)
                    .animation(.default, value: amountShakeOffset)
            }

            // Always-visible custom decimal keypad (Pitfall 6 — NO system keyboard)
            DecimalKeypadView(displayString: $amountString)
        }
        .padding(16)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Optional Fields Section

    private var optionalSection: some View {
        VStack(spacing: 0) {
            // Date row
            VStack(spacing: 0) {
                Button(action: { showDatePicker.toggle() }) {
                    HStack {
                        Text("Date")
                            .foregroundStyle(.primary)
                        Spacer()
                        Text(date.formattedForDatePickerRow())
                            .foregroundStyle(.secondary)
                            .font(.subheadline)
                        Image(systemName: showDatePicker ? "chevron.up" : "chevron.down")
                            .foregroundStyle(.secondary)
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
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))

            // Note field (T-01-06: plain TextField — never AttributedString(markdown:))
            HStack {
                Text("Note")
                    .foregroundStyle(.primary)
                Spacer()
                TextField("Merchant or memo", text: $note)
                    .multilineTextAlignment(.trailing)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 16)
            .frame(minHeight: 44)
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .padding(.top, 8)
        }
    }

    // MARK: - Delete Section

    private var deleteSection: some View {
        Button(role: .destructive) {
            showDeleteConfirmation = true
        } label: {
            Text("Delete Expense")
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
        }
        .buttonStyle(.bordered)
        .tint(Color(.systemRed))
        .frame(minHeight: 44)
    }

    // MARK: - Actions

    private func initializeFields() {
        let amount = expense.amount
        if amount < 0 {
            isNegative = true
            amountString = String(describing: -amount)
        } else {
            isNegative = false
            amountString = String(describing: amount)
        }
        // Clean up trailing zeros for display (e.g. "500.00" → "500", "500.50" stays)
        if let dotIndex = amountString.firstIndex(of: ".") {
            let decimals = amountString[amountString.index(after: dotIndex)...]
            if decimals.allSatisfy({ $0 == "0" }) {
                amountString = String(amountString[..<dotIndex])
            }
        }
        date = expense.date
        note = expense.note ?? ""
    }

    private func saveExpense() {
        guard let amount = parsedAmount, amount != 0 else {
            shakeAmount()
            return
        }
        // T-01-03: input validation
        guard abs(amount) < Decimal(1_000_000_000) else {
            shakeAmount()
            return
        }
        expense.amount = amount
        expense.date = date
        expense.note = note.trimmingCharacters(in: .whitespaces).isEmpty
            ? nil
            : note.trimmingCharacters(in: .whitespaces)
        expense.updatedAt = Date()
        // CR-01: persist explicitly — do not rely on implicit autosave (financial write).
        do {
            try context.save()
        } catch {
            // Surface the failure; do not dismiss as if the save succeeded.
            assertionFailure("Failed to save edited expense: \(error)")
            print("Failed to save edited expense: \(error)")
            shakeAmount()
            return
        }
        // T-01-07: dismiss cleanly after save (Pitfall 19)
        dismiss()
    }

    private func deleteExpense() {
        context.delete(expense)
        // CR-01: persist the delete explicitly — do not rely on implicit autosave.
        do {
            try context.save()
        } catch {
            // Surface the failure; do not dismiss as if the delete succeeded.
            assertionFailure("Failed to delete expense: \(error)")
            print("Failed to delete expense: \(error)")
            return
        }
        // T-01-07: dismiss cleanly after delete (Pitfall 19)
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
