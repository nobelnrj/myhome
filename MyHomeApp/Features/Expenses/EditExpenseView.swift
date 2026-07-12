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
    @State private var selectedCategory: Category? = nil
    @State private var showCategoryPicker: Bool = false
    @State private var selectedAccount: Account? = nil
    @State private var showAccountPicker: Bool = false
    @State private var isMarkedTransfer: Bool = false

    // Active accounts for resolving expense.accountID on appear (D-04)
    @Query(filter: #Predicate<Account> { !$0.isArchived }, sort: \Account.sortOrder)
    private var activeAccounts: [Account]

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
            || selectedCategory?.persistentModelID != expense.categories.first?.persistentModelID
            || selectedAccount?.id != expense.accountID
            || isMarkedTransfer != (expense.isTransfer == true)
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
            .background(DesignTokens.bgCanvas)
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
                    .tint(DesignTokens.accentText)
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
                    .foregroundStyle(amountIsError ? DesignTokens.negative : (isNegative && parsedAmount != nil ? DesignTokens.positive : DesignTokens.label))
                    .frame(maxWidth: .infinity, alignment: .center)
                    .accessibilityValue(displayAmount)
                    .offset(x: amountShakeOffset)
                    .animation(.default, value: amountShakeOffset)
            }

            // Always-visible custom decimal keypad (Pitfall 6 — NO system keyboard)
            DecimalKeypadView(displayString: $amountString)
        }
        .padding(16)
        .background(DesignTokens.surfaceRaised)
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

            // Category row (Section 2, optional — off the ≤3-tap critical path; D2-12)
            Button(action: { showCategoryPicker = true }) {
                HStack {
                    Text("Category")
                        .foregroundStyle(DesignTokens.label)
                    Spacer()
                    if let cat = selectedCategory, let name = cat.name {
                        if let symbol = cat.symbolName {
                            Image(systemName: symbol)
                                .font(.subheadline)
                                .foregroundStyle(DesignTokens.label2)
                        }
                        // T-02-07: plain Text — never AttributedString(markdown:)
                        Text(name)
                            .foregroundStyle(DesignTokens.label2)
                            .font(.subheadline)
                    } else {
                        Text("None")
                            .foregroundStyle(DesignTokens.label2)
                            .font(.subheadline)
                    }
                    Image(systemName: "chevron.right")
                        .foregroundStyle(DesignTokens.label2)
                        .font(.caption)
                }
                .padding(.vertical, 12)
                .padding(.horizontal, 16)
                .frame(minHeight: 44)
            }
            .buttonStyle(.plain)
            .background(DesignTokens.surfaceRaised)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .padding(.top, 8)
            .sheet(isPresented: $showCategoryPicker) {
                CategoryPickerView(selectedCategory: $selectedCategory)
            }

            // Account row (D-04: optional account picker, seeded from expense.accountID)
            Button(action: { showAccountPicker = true }) {
                HStack {
                    Text("Account")
                        .foregroundStyle(DesignTokens.label)
                    Spacer()
                    if let acc = selectedAccount, let name = acc.name {
                        if let symbol = acc.symbolName {
                            Image(systemName: symbol)
                                .font(.subheadline)
                                .foregroundStyle(DesignTokens.label2)
                        }
                        // T-02-15: plain Text — never AttributedString(markdown:)
                        Text(name)
                            .foregroundStyle(DesignTokens.label2)
                            .font(.subheadline)
                    } else {
                        Text("Unassigned")
                            .foregroundStyle(DesignTokens.label2)
                            .font(.subheadline)
                    }
                    Image(systemName: "chevron.right")
                        .foregroundStyle(DesignTokens.label2)
                        .font(.caption)
                }
                .padding(.vertical, 12)
                .padding(.horizontal, 16)
                .frame(minHeight: 44)
            }
            .buttonStyle(.plain)
            .background(DesignTokens.surfaceRaised)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .padding(.top, 8)
            .sheet(isPresented: $showAccountPicker) {
                AccountPickerView(selectedAccount: $selectedAccount)
            }

            // Note field (T-01-06: plain TextField — never AttributedString(markdown:))
            HStack {
                Text("Note")
                    .foregroundStyle(DesignTokens.label)
                Spacer()
                TextField("Merchant or memo", text: $note)
                    .multilineTextAlignment(.trailing)
                    .foregroundStyle(DesignTokens.label2)
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 16)
            .frame(minHeight: 44)
            .background(DesignTokens.surfaceRaised)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .padding(.top, 8)

            // Transfer toggle (XFER-05, D-14): marks a solo transfer or unmarks with cascade-unlink
            Toggle(isOn: $isMarkedTransfer) {
                Text("Mark as Transfer")
                    .foregroundStyle(DesignTokens.label)
            }
            .toggleStyle(.switch)
            .padding(.vertical, 12)
            .padding(.horizontal, 16)
            .frame(minHeight: 44)
            .background(DesignTokens.surfaceRaised)
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
        .tint(DesignTokens.negative)
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
        selectedCategory = expense.categories.first   // v1 UI: single-select (D2-02)
        // D-04: Seed selectedAccount from expense.accountID (active accounts only — T-09-09)
        if let accountID = expense.accountID {
            selectedAccount = activeAccounts.first { $0.id == accountID }
            // If accountID resolves to nil (deleted or archived account), leave nil = Unassigned
        }
        // XFER-05 / D-14: Seed transfer toggle from persisted state
        isMarkedTransfer = expense.isTransfer == true
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
        // Wire optional category (v1 UI: single-select; schema supports multiple — D2-02)
        expense.categories = selectedCategory.map { [$0] } ?? []
        // D-04: Write account attribution; guard against archived (T-09-09 / Pitfall 6)
        // Do NOT touch sourceAccount (Gmail dedup key, ACCT-08) or sourceLabel
        if let acc = selectedAccount, !acc.isArchived {
            expense.accountID = acc.id
        } else {
            expense.accountID = nil   // Unassigned (archived account treated as nil)
        }
        // XFER-05 / D-14: apply transfer mark/unmark (uses static helper for testability)
        EditExpenseView.applyTransferMark(isMarkedTransfer, expense: expense, context: context)
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

    /// Applies the manual transfer mark or unmark to `expense`.
    ///
    /// Exposed as a `static` helper so unit tests can exercise the mutation logic
    /// without instantiating the full SwiftUI view.
    ///
    /// - Parameters:
    ///   - mark: `true` to flag as a solo transfer; `false` to unmark and cascade-unlink.
    ///   - expense: The expense to mutate.
    ///   - context: The model context used to fetch a linked counterpart on unmark.
    ///
    /// D-14 rules:
    ///   - Mark: set `isTransfer = true`; leave `transferPairID` as-is (solo flag allowed,
    ///     per-plan may already carry a pairID from the confirm flow).
    ///   - Unmark: reset `isTransfer = nil` and `transferPairID = nil`; if a counterpart
    ///     exists (fetched by the current `transferPairID`), cascade-reset it too.
    ///     `nil` chosen over `false` so the scorer can re-evaluate the expense (D-14).
    ///     T-10-12: cascade prevents a dangling half-transfer pair.
    static func applyTransferMark(_ mark: Bool, expense: Expense, context: ModelContext) {
        if mark {
            // Solo mark. If the expense is currently in a PENDING pair
            // (isTransfer == nil with a back-pointer), release the counterpart first so
            // it does not become an inbox ghost — a half-pair the user can't dismiss (CR-01).
            // Only a pending (nil) partner is released; a confirmed (true) partner is left
            // untouched. A solo transfer has no partner, so drop our own link too.
            if let pairID = expense.transferPairID {
                let descriptor = FetchDescriptor<Expense>()
                if let all = try? context.fetch(descriptor),
                   let partner = all.first(where: { $0.id == pairID }),
                   partner.isTransfer == nil {
                    partner.transferPairID = nil
                }
            }
            expense.transferPairID = nil
            expense.isTransfer = true
        } else if expense.isTransfer == true {
            // Unmark — cascade-unlink any paired counterpart first (T-10-12)
            if let pairID = expense.transferPairID {
                let descriptor = FetchDescriptor<Expense>()
                if let all = try? context.fetch(descriptor),
                   let partner = all.first(where: { $0.id == pairID }) {
                    partner.isTransfer = nil
                    partner.transferPairID = nil
                }
            }
            expense.isTransfer = nil
            expense.transferPairID = nil
        }
        // If expense.isTransfer was nil and mark is false, nothing to do (already unevaluated)
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
