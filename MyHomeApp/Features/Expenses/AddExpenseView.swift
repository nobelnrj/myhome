import SwiftUI
import SwiftData

/// Sheet for adding a new expense in ≤3 taps (open → type amount → Save Expense).
///
/// Layout (UI-SPEC Screen 2):
/// - NavigationStack-in-sheet titled "New Expense" (inline)
/// - Toolbar: leading "Cancel", trailing "Save Expense" (accent, disabled until non-zero)
/// - Section 1: large centered amount display, sign toggle, always-visible DecimalKeypadView
/// - Section 2: optional date picker row + note TextField (collapsed from ≤3-tap path)
///
/// Security: T-01-03 — amount guard: non-zero AND abs(amount) < 1_000_000_000.
/// Note rendering: T-01-06 — plain Text() only; never AttributedString(markdown:).
struct AddExpenseView: View {

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    // Amount state
    @State private var amountString: String = ""
    @State private var isNegative: Bool = false
    @State private var amountShakeOffset: CGFloat = 0
    @State private var amountIsError: Bool = false

    // Optional fields (Section 2 — off the ≤3-tap critical path)
    @State private var date: Date = Date()
    @State private var note: String = ""
    @State private var showDatePicker: Bool = false
    @State private var selectedCategory: Category? = nil
    @State private var showCategoryPicker: Bool = false

    // MARK: - Computed

    private var parsedAmount: Decimal? {
        guard !amountString.isEmpty, let value = Decimal(string: amountString) else { return nil }
        return isNegative ? -value : value
    }

    private var isSaveEnabled: Bool {
        guard let amount = parsedAmount else { return false }
        return amount != 0
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
                }
                .padding(.horizontal, 16)
            }
            .navigationTitle("New Expense")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
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
        }
    }

    // MARK: - Amount Section

    private var amountSection: some View {
        VStack(spacing: 16) {
            // Sign toggle + amount display
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

    // MARK: - Optional Fields Section (Section 2)

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

            // Category row (Section 2, optional — off the ≤3-tap critical path; D2-12)
            Button(action: { showCategoryPicker = true }) {
                HStack {
                    Text("Category")
                        .foregroundStyle(.primary)
                    Spacer()
                    if let cat = selectedCategory, let name = cat.name {
                        if let symbol = cat.symbolName {
                            Image(systemName: symbol)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        // T-02-07: plain Text — never AttributedString(markdown:)
                        Text(name)
                            .foregroundStyle(.secondary)
                            .font(.subheadline)
                    } else {
                        Text("None")
                            .foregroundStyle(.secondary)
                            .font(.subheadline)
                    }
                    Image(systemName: "chevron.right")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                }
                .padding(.vertical, 12)
                .padding(.horizontal, 16)
                .frame(minHeight: 44)
            }
            .buttonStyle(.plain)
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .padding(.top, 8)
            .sheet(isPresented: $showCategoryPicker) {
                CategoryPickerView(selectedCategory: $selectedCategory)
            }

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

    // MARK: - Actions

    private func saveExpense() {
        guard let amount = parsedAmount, amount != 0 else {
            shakeAmount()
            return
        }
        // T-01-03: input validation — abs(amount) < 1_000_000_000
        guard abs(amount) < Decimal(1_000_000_000) else {
            shakeAmount()
            return
        }
        let trimmedNote: String? = note.trimmingCharacters(in: .whitespaces).isEmpty
            ? nil
            : note.trimmingCharacters(in: .whitespaces)
        let expense = Expense(amount: amount, date: date, note: trimmedNote)
        context.insert(expense)
        // Wire optional category (v1 UI: single-select; schema supports multiple — D2-02)
        expense.categories = selectedCategory.map { [$0] } ?? []
        // CR-01: persist explicitly — do not rely on implicit autosave (financial write).
        do {
            try context.save()
        } catch {
            // Surface the failure; do not dismiss as if the save succeeded.
            assertionFailure("Failed to save new expense: \(error)")
            print("Failed to save new expense: \(error)")
            shakeAmount()
            return
        }
        // T-01-07: dismiss cleanly after insert (Pitfall 19 — no same-tick navigation race)
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
