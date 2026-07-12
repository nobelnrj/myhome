import SwiftUI
import SwiftData

/// Sheet for creating or editing a bank account (ACCT-01/02/03/04, D-09/D-10).
///
/// Presented as a NavigationStack-in-sheet (mirrors AddExpenseView pattern).
/// nil account = create mode; non-nil = edit mode.
///
/// Threat mitigations:
/// - T-09-05: abs(balanceBaseline) < 1_000_000_000 guard (mirrors T-01-03).
/// - T-09-06: Account name displayed via plain Text() — never AttributedString(markdown:).
/// - T-09-08: Lookup-before-insert (case-insensitive) in saveAccount() prevents duplicates.
struct EditAccountView: View {

    var account: Account?  // nil = create, non-nil = edit

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    // MARK: - Form State

    @State private var name: String = ""
    @State private var typeRaw: String = "savings"
    @State private var symbolName: String = "creditcard"
    @State private var colorHex: String = "#636366"
    @State private var last4: String = ""
    @State private var balanceBaseline: Decimal = 0
    @State private var balanceAsOfDate: Date = Date()
    @State private var nameError: String? = nil

    // Icon + color picker sheet
    @State private var showIconColorPicker = false

    // MARK: - Validation

    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty &&
        abs(balanceBaseline) < 1_000_000_000
    }

    // MARK: - Icon + Color Picker Data

    private static let availableSymbols = [
        "building.columns", "creditcard", "banknote", "wallet.pass",
        "dollarsign.circle", "house", "car", "briefcase",
        "stethoscope", "cart", "fork.knife", "bolt",
        "fuelpump", "bag", "graduationcap", "airplane",
        "gift", "heart", "tag", "star"
    ]

    private static let availableColors: [(name: String, hex: String)] = [
        ("Blue",   "#007AFF"),
        ("Green",  "#34C759"),
        ("Orange", "#FF9500"),
        ("Red",    "#FF3B30"),
        ("Yellow", "#FFCC00"),
        ("Indigo", "#5856D6"),
        ("Teal",   "#5AC8FA"),
        ("Pink",   "#FF2D55"),
        ("Purple", "#AF52DE"),
        ("Brown",  "#A2845E"),
        ("Cyan",   "#32ADE6"),
        ("Mint",   "#00C7BE"),
    ]

    // MARK: - Body

    var body: some View {
        NavigationStack {
            Form {
                // MARK: Section 1 — Identity
                Section {
                    // Icon + color row
                    Button(action: { showIconColorPicker.toggle() }) {
                        HStack(spacing: 12) {
                            IconTile(
                                symbol: symbolName,
                                color: Color(hex: colorHex),
                                size: 44
                            )
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Icon & Color")
                                    .font(.body)
                                    .foregroundStyle(DesignTokens.label)
                                Text("Tap to change")
                                    .font(.subheadline)
                                    .foregroundStyle(DesignTokens.label2)
                            }
                            Spacer()
                        }
                        .frame(minHeight: 44)
                    }
                    .buttonStyle(.plain)

                    // Name
                    VStack(alignment: .leading, spacing: 4) {
                        TextField("Account name", text: $name)
                            .font(.body)
                            .frame(minHeight: 44)
                        if let error = nameError {
                            Text(error)
                                .font(.subheadline)
                                .foregroundStyle(DesignTokens.negative)
                        }
                    }

                    // Last 4 (optional)
                    TextField("Last 4 digits (optional)", text: $last4)
                        .keyboardType(.numberPad)
                        .font(.body)
                        .frame(minHeight: 44)
                }

                // MARK: Section 2 — Type
                Section("Account Type") {
                    Picker("Account Type", selection: $typeRaw) {
                        Text("Savings").tag("savings")
                        Text("Current").tag("current")
                        Text("Credit Card").tag("credit_card")
                    }
                    .pickerStyle(.segmented)
                }

                // MARK: Section 3 — Balance
                Section("Balance") {
                    HStack {
                        Text(typeRaw == "credit_card" ? "Amount Owed" : "Opening Balance")
                            .font(.body)
                        Spacer()
                        TextField("0", value: $balanceBaseline, format: .number)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .font(.body)
                            .foregroundStyle(typeRaw == "credit_card" ? DesignTokens.negative : DesignTokens.label)
                    }
                    .frame(minHeight: 44)

                    DatePicker("As of", selection: $balanceAsOfDate, displayedComponents: [.date])
                        .font(.body)
                }

                // MARK: Section 4 — Danger Zone (edit mode only)
                if account != nil {
                    Section {
                        Button("Archive Account") {
                            account?.isArchived = true
                            try? context.save()  // CR-01
                            dismiss()
                        }
                        .foregroundStyle(DesignTokens.orange)
                        .frame(minHeight: 44)
                    }
                }

                // MARK: Icon + Color Picker (inline expandable)
                if showIconColorPicker {
                    Section("Choose Icon") {
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 5), spacing: 12) {
                            ForEach(Self.availableSymbols, id: \.self) { sym in
                                Button(action: { symbolName = sym }) {
                                    ZStack {
                                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                                            .fill(symbolName == sym ? DesignTokens.accent.opacity(0.15) : DesignTokens.fillRecessed)
                                            .frame(width: 48, height: 48)
                                        Image(systemName: sym)
                                            .font(.title3)
                                            .foregroundStyle(symbolName == sym ? DesignTokens.accentText : DesignTokens.label2)
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.vertical, 4)
                    }

                    Section("Choose Color") {
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: 12) {
                            ForEach(Self.availableColors, id: \.hex) { item in
                                Button(action: { colorHex = item.hex }) {
                                    ZStack {
                                        Circle()
                                            .fill(Color(hex: item.hex))
                                            .frame(width: 40, height: 40)
                                        if colorHex.uppercased() == item.hex.uppercased() {
                                            Image(systemName: "checkmark")
                                                .font(.caption.weight(.bold))
                                                .foregroundStyle(.white)
                                        }
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            .navigationTitle(account == nil ? "New Account" : "Edit Account")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save Account") {
                        saveAccount()
                    }
                    .disabled(!isValid)
                    .tint(DesignTokens.accentText)
                }
            }
            .onAppear {
                if let acc = account {
                    name = acc.name ?? ""
                    typeRaw = acc.typeRaw ?? "savings"
                    symbolName = acc.symbolName ?? "creditcard"
                    colorHex = acc.colorHex ?? "#636366"
                    last4 = acc.last4 ?? ""
                    balanceBaseline = acc.balanceBaseline ?? 0
                    balanceAsOfDate = acc.balanceAsOfDate ?? Date()
                }
            }
        }
    }

    // MARK: - Save

    private func saveAccount() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            nameError = "Account name cannot be empty."
            return
        }
        // T-09-05: reject unreasonably large balanceBaseline (mirrors T-01-03)
        guard abs(balanceBaseline) < 1_000_000_000 else {
            nameError = "Balance must be less than ₹1,00,00,00,000."
            return
        }

        // Lookup-before-insert for uniqueness (T-09-08, mirrors ManageCategoriesView)
        let lower = trimmed.lowercased()
        do {
            let all = try context.fetch(FetchDescriptor<Account>())
            // Allow saving with same name when editing self
            let duplicate = all.first {
                ($0.name ?? "").lowercased() == lower &&
                $0.persistentModelID != (account?.persistentModelID ?? PersistentIdentifier?.none)
            }
            if duplicate != nil {
                nameError = "An account with that name already exists."
                return
            }

            let target: Account
            if let existing = account {
                target = existing
            } else {
                target = Account(name: trimmed, typeRaw: typeRaw)
                // Prepend insertion: min(existing.sortOrder) - 1 (STAB-03 pattern)
                let nextSortOrder = (all.map(\.sortOrder).min() ?? 0) - 1
                target.sortOrder = nextSortOrder
                context.insert(target)
            }

            target.name = trimmed
            target.typeRaw = typeRaw
            target.symbolName = symbolName
            target.colorHex = colorHex
            target.last4 = last4.isEmpty ? nil : last4
            target.balanceBaseline = balanceBaseline
            target.balanceAsOfDate = balanceAsOfDate

            try context.save()  // CR-01: explicit save
            nameError = nil
            dismiss()
        } catch {
            assertionFailure("Failed to save account: \(error)")
        }
    }
}
