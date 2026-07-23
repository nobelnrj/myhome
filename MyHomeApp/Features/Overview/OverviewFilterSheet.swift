import SwiftUI
import SwiftData

/// The Overview filter sheet ("Show data from") — OVF-01 account selection + OVF-02 date range,
/// in one sheet so `OverviewFilter()` default stays the single one-tap clear (UI-REFERENCE
/// Decision 2). Edits apply LIVE through the `@Binding` (the figures behind the sheet recompute
/// as the user taps); "Done" only dismisses, "Reset" restores `OverviewFilter()`.
///
/// Styled entirely with the existing neumorphic token system (DesignTokens + NeuSurface); no new
/// colors, no DesignSystem edits (dark bit-identity, Phase 17). Both light and dark come free from
/// the adaptive tokens.
///
/// The sheet doubles as a per-account glance: each row shows that account's period spend/income,
/// computed through the SAME `BudgetCalculator.grossSpend`/`grossIncome` transfer-excluding path
/// the hero uses (`periodExpenses` is the date-windowed, account-UNfiltered array from the parent),
/// so the numbers reconcile with the hero readout.
struct OverviewFilterSheet: View {

    @Binding var filter: OverviewFilter
    /// Date-windowed, account-UNfiltered expenses for the current period (the parent's
    /// `monthExpenses`). Used only to render each row's per-account spend/income glance.
    let periodExpenses: [Expense]

    @Environment(\.dismiss) private var dismiss

    /// OVF-01: active (non-archived) accounts, in the same order as the rest of the app.
    @Query(filter: #Predicate<Account> { !$0.isArchived }, sort: \Account.sortOrder)
    private var accounts: [Account]

    // Local custom-range editing state, seeded from the current filter (or sensible defaults).
    @State private var customFrom: Date
    @State private var customTo: Date

    init(filter: Binding<OverviewFilter>, periodExpenses: [Expense]) {
        self._filter = filter
        self.periodExpenses = periodExpenses

        let range = filter.wrappedValue.dateRange
        let cal = Calendar.current
        let now = Date()
        let monthStart = cal.date(from: cal.dateComponents([.year, .month], from: now)) ?? now
        self._customFrom = State(initialValue: range?.lowerBound ?? monthStart)
        self._customTo = State(initialValue: range?.upperBound ?? now)
    }

    private var isCustomRange: Bool { filter.dateRange != nil }

    var body: some View {
        NavigationStack {
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: DesignTokens.spacing16) {
                    header

                    // MARK: Accounts (OVF-01)
                    VStack(spacing: 10) {
                        allAccountsRow
                        ForEach(accounts) { account in
                            accountRow(account)
                        }
                        unassignedRow
                    }

                    periodSection

                    manageAccountsFooter
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
            .scrollContentBackground(.hidden)
            .background(DesignTokens.bgCanvas)
            .sheetBottomClearance()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Reset") {
                        filter = OverviewFilter()
                    }
                    .tint(DesignTokens.accentText)
                    .disabled(!filter.isActive)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                        .tint(DesignTokens.accentText)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("Show data from")
                .font(.system(size: 26, weight: .bold))
                .foregroundStyle(DesignTokens.label)
            // UI-REFERENCE Decision 1: reach is the Overview only (Budgets are suppressed while
            // a filter is active), so the mocked "Applies across Home, Expenses & Budgets" is wrong.
            Text("Applies to your Overview")
                .font(.subheadline)
                .foregroundStyle(DesignTokens.label2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Account rows

    private var allAccountsRow: some View {
        let selected = !filter.accountFilterActive
        return Button {
            // Tapping "All accounts" empties the subset and clears Unassigned (the account reset).
            filter.accountIDs = []
            filter.includeUnassigned = false
            Haptics.selection()
        } label: {
            HStack(spacing: 14) {
                IconTile(symbol: "square.3.layers.3d", color: DesignTokens.accent, size: 40, cornerRadius: 12)
                VStack(alignment: .leading, spacing: 1) {
                    Text("All accounts")
                        .font(.headline)
                        .foregroundStyle(DesignTokens.label)
                    Text(allAccountsSubtitle)
                        .font(.subheadline)
                        .foregroundStyle(DesignTokens.label2)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                Text(BudgetCalculator.grossSpend(for: periodExpenses).formattedINRWhole())
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(DesignTokens.label)
                    .monospacedDigit()
                selectionCircle(selected)
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: DesignTokens.radiusInner, style: .continuous)
                    .fill(LinearGradient(
                        colors: [DesignTokens.surfaceRaisedTop, DesignTokens.surfaceRaisedBottom],
                        startPoint: .topLeading, endPoint: .bottomTrailing))
            )
            .overlay(
                RoundedRectangle(cornerRadius: DesignTokens.radiusInner, style: .continuous)
                    .strokeBorder(selected ? DesignTokens.accent : DesignTokens.glassBorder,
                                  lineWidth: selected ? 1.5 : 0.5)
            )
        }
        .buttonStyle(.plain)
    }

    private func accountRow(_ account: Account) -> some View {
        let selected = filter.accountIDs.contains(account.id)
        let exps = periodExpenses.filter { $0.accountID == account.id }
        let spend = BudgetCalculator.grossSpend(for: exps)
        let income = BudgetCalculator.grossIncome(for: exps)
        return Button {
            toggle(account.id)
            Haptics.selection()
        } label: {
            HStack(spacing: 14) {
                IconTile(
                    symbol: account.symbolName ?? defaultSymbol(account.typeRaw),
                    color: Color(hex: account.colorHex ?? "#636366"),
                    size: 40, cornerRadius: 12
                )
                VStack(alignment: .leading, spacing: 1) {
                    Text(account.name ?? "Account")
                        .font(.headline)
                        .foregroundStyle(DesignTokens.label)
                        .lineLimit(1)
                    Text(accountSubtitle(account, income: income))
                        .font(.subheadline)
                        .foregroundStyle(DesignTokens.label2)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                Text(spend.formattedINRWhole())
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(DesignTokens.label)
                    .monospacedDigit()
                selectionCircle(selected)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var unassignedRow: some View {
        let selected = filter.includeUnassigned
        let exps = periodExpenses.filter { $0.accountID == nil }
        let spend = BudgetCalculator.grossSpend(for: exps)
        return Button {
            filter.includeUnassigned.toggle()
            Haptics.selection()
        } label: {
            HStack(spacing: 14) {
                IconTile(symbol: "questionmark.circle", color: DesignTokens.catOther, size: 40, cornerRadius: 12)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Unassigned")
                        .font(.headline)
                        .foregroundStyle(DesignTokens.label)
                    Text("Manual · no account")
                        .font(.subheadline)
                        .foregroundStyle(DesignTokens.label2)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                Text(spend.formattedINRWhole())
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(DesignTokens.label)
                    .monospacedDigit()
                selectionCircle(selected)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Period section (OVF-02)

    private var periodSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Period").eyebrow()

            HStack(spacing: 10) {
                periodChip(title: "This Month", active: !isCustomRange) {
                    filter.dateRange = nil
                    Haptics.selection()
                }
                periodChip(title: "Custom range", active: isCustomRange) {
                    applyCustomRange()
                    Haptics.selection()
                }
            }

            if isCustomRange {
                VStack(spacing: 6) {
                    DatePicker("From", selection: $customFrom, displayedComponents: .date)
                        .onChange(of: customFrom) { _, _ in applyCustomRange() }
                    Divider()
                    DatePicker("To", selection: $customTo, displayedComponents: .date)
                        .onChange(of: customTo) { _, _ in applyCustomRange() }
                }
                .font(.subheadline)
                .tint(DesignTokens.accentText)
                .foregroundStyle(DesignTokens.label)
                .padding(14)
                .neuSurface(.recessed, radius: DesignTokens.radiusInner, padding: nil)
            }
        }
    }

    private func periodChip(title: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(active ? DesignTokens.accentOnYellow : DesignTokens.label)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 11)
                .background(
                    Capsule().fill(active
                        ? AnyShapeStyle(DesignTokens.accent)
                        : AnyShapeStyle(LinearGradient(
                            colors: [DesignTokens.surfaceRaisedTop, DesignTokens.surfaceRaisedBottom],
                            startPoint: .topLeading, endPoint: .bottomTrailing)))
                )
                .overlay(
                    Capsule().strokeBorder(active ? Color.clear : DesignTokens.glassBorder, lineWidth: 0.5)
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Footer

    private var manageAccountsFooter: some View {
        HStack {
            Spacer()
            NavigationLink {
                AccountsListView()
            } label: {
                Label("Manage accounts", systemImage: "gearshape")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(DesignTokens.accentText)
            }
            Spacer()
        }
        .padding(.top, 4)
    }

    // MARK: - Selection indicator

    @ViewBuilder
    private func selectionCircle(_ selected: Bool) -> some View {
        if selected {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 22))
                .foregroundStyle(DesignTokens.accentOnYellow, DesignTokens.accent)
                .accessibilityLabel("Selected")
        } else {
            Circle()
                .fill(DesignTokens.fillRecessed)
                .frame(width: 22, height: 22)
                .overlay(Circle().strokeBorder(DesignTokens.separatorHairline, lineWidth: 1))
                .accessibilityLabel("Not selected")
        }
    }

    // MARK: - Logic helpers

    private func toggle(_ id: UUID) {
        if filter.accountIDs.contains(id) {
            filter.accountIDs.remove(id)
        } else {
            filter.accountIDs.insert(id)
        }
    }

    /// Enable/refresh the custom range from the local pickers, clamping `from ≤ to` before
    /// assigning (the engine also swaps defensively — T-21-06).
    private func applyCustomRange() {
        let lo = min(customFrom, customTo)
        let hi = max(customFrom, customTo)
        filter.dateRange = lo...hi
    }

    private func defaultSymbol(_ typeRaw: String?) -> String {
        typeRaw == "credit_card" ? "creditcard" : "building.columns"
    }

    private var allAccountsSubtitle: String {
        let income = BudgetCalculator.grossIncome(for: periodExpenses)
        let n = accounts.count
        let base = "\(n) account\(n == 1 ? "" : "s")"
        guard income > 0 else { return base }
        return "\(base) · +\(income.formattedINRWhole()) in"
    }

    private func accountSubtitle(_ account: Account, income: Decimal) -> String {
        var parts: [String] = [displayType(account.typeRaw)]
        if let last4 = account.last4, !last4.isEmpty { parts.append("··\(last4)") }
        var line = parts.joined(separator: " ")
        if income > 0 { line += " · +\(income.formattedINRWhole()) in" }
        return line
    }

    private func displayType(_ typeRaw: String?) -> String {
        switch typeRaw {
        case "savings": return "Savings"
        case "current": return "Current"
        case "credit_card": return "Credit"
        default: return "Savings"
        }
    }
}
