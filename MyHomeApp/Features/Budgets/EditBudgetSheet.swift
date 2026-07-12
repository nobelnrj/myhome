import SwiftUI
import SwiftData

/// Sheet for setting or clearing a category's recurring monthly budget (EXP-07, D2-11).
///
/// Layout (UI-SPEC Screen 7):
/// - NavigationStack titled "Set Budget" (inline)
/// - Category name shown as "for [Category]" below title
/// - amountSection: large centered amount + DecimalKeypadView (no sign toggle — budgets positive only)
/// - removeBudgetSection: "Remove Budget" destructive button, only when monthlyBudget != nil
/// - Toolbar: "Cancel" (cancellationAction, no save) + "Save Budget" (confirmationAction, disabled until > 0)
///
/// Security:
/// - T-02-09: guards amount > 0 and abs(amount) < 1_000_000_000 (same guard as expense amount, V5 input validation)
/// - T-02-10: explicit context.save() (CR-01) on set and remove; remove gated by confirmationDialog
/// - T-02-11: category name displayed via plain Text — never AttributedString(markdown:)
struct EditBudgetSheet: View {

    @Bindable var category: Category
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var amountString: String = ""
    @State private var amountShakeOffset: CGFloat = 0
    @State private var amountIsError: Bool = false
    @State private var showRemoveConfirmation: Bool = false

    // MARK: - Computed

    private var parsedAmount: Decimal? {
        guard !amountString.isEmpty, let value = Decimal(string: amountString) else { return nil }
        return value
    }

    private var isSaveEnabled: Bool {
        guard let amount = parsedAmount else { return false }
        return amount > 0
    }

    private var displayAmount: String {
        guard let value = parsedAmount, value > 0 else {
            return Decimal(0).formattedINR()
        }
        return value.formattedINR()
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    // "for [Category]" subtitle label below the navigation title
                    // T-02-11: plain Text — never AttributedString(markdown:)
                    Text("for \(category.name ?? "")")
                        .font(.subheadline)
                        .foregroundStyle(DesignTokens.label2)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.top, 8)
                        .padding(.bottom, 4)

                    amountSection
                        .padding(.top, 12)

                    if category.monthlyBudget != nil {
                        removeBudgetSection
                            .padding(.top, 24)
                            .padding(.bottom, 32)
                    }
                }
                .padding(.horizontal, 16)
            }
            .background(DesignTokens.bgCanvas)
            .navigationTitle("Set Budget")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save Budget") {
                        saveBudget()
                    }
                    .disabled(!isSaveEnabled)
                    .tint(DesignTokens.accentText)
                }
            }
            .confirmationDialog(
                "Remove Budget?",
                isPresented: $showRemoveConfirmation,
                titleVisibility: .visible
            ) {
                Button("Remove Budget", role: .destructive) {
                    category.monthlyBudget = nil
                    // CR-01: persist explicitly — configuration write (T-02-10)
                    do {
                        try context.save()
                        dismiss()
                    } catch {
                        assertionFailure("Failed to remove budget: \(error)")
                        print("Failed to remove budget: \(error)")
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("The monthly budget for this category will be removed. Spending data is not affected.")
            }
        }
        .onAppear {
            initializeFields()
        }
    }

    // MARK: - Amount Section

    private var amountSection: some View {
        VStack(spacing: 16) {
            // Large centered amount display (no sign toggle — budgets always positive)
            Text(displayAmount)
                .font(.largeTitle)
                .fontWeight(.bold)
                .foregroundStyle(amountIsError ? DesignTokens.negative : DesignTokens.label)
                .frame(maxWidth: .infinity, alignment: .center)
                .offset(x: amountShakeOffset)
                .animation(.default, value: amountShakeOffset)

            // Always-visible custom decimal keypad (Pitfall 6 — no system keyboard)
            DecimalKeypadView(displayString: $amountString)
        }
        .neuSurface(.recessed, radius: DesignTokens.radiusInner)
    }

    // MARK: - Remove Budget Section

    private var removeBudgetSection: some View {
        Button(role: .destructive) {
            showRemoveConfirmation = true
        } label: {
            Text("Remove Budget")
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
        }
        .buttonStyle(.bordered)
        .tint(DesignTokens.negative)
        .frame(minHeight: 44)
    }

    // MARK: - Actions

    private func initializeFields() {
        if let existing = category.monthlyBudget, existing > 0 {
            amountString = String(describing: existing)
            // Clean up trailing zeros (e.g. "500.00" → "500", "500.50" stays)
            if let dotIndex = amountString.firstIndex(of: ".") {
                let decimals = amountString[amountString.index(after: dotIndex)...]
                if decimals.allSatisfy({ $0 == "0" }) {
                    amountString = String(amountString[..<dotIndex])
                }
            }
        }
    }

    private func saveBudget() {
        guard let amount = parsedAmount, amount > 0 else {
            shakeAmount()
            return
        }
        // T-02-09: same guard as Phase 1 expense amount (V5 input validation)
        guard abs(amount) < Decimal(1_000_000_000) else {
            shakeAmount()
            return
        }
        category.monthlyBudget = amount
        // CR-01: persist explicitly — configuration write (T-02-10)
        do {
            try context.save()
        } catch {
            assertionFailure("Failed to save budget: \(error)")
            print("Failed to save budget: \(error)")
            shakeAmount()
            return
        }
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
