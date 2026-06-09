import SwiftUI
import SwiftData

/// Per-account balance card + attributed expense list (ACCT-05/06, D-07/D-09/D-10).
///
/// Balance is computed reactively from @Query — never stored, never manually refreshed (D-10).
/// Sign convention (D-09): CC balance is always red (amount owed is negative); savings/current
/// green when positive, red when negative (overdrawn), primary when zero.
///
/// Threat mitigations:
/// - T-09-06: Account name via plain Text() — never AttributedString(markdown:).
struct AccountDetailView: View {

    var account: Account

    // MARK: - Queries

    /// All expenses (date descending) — filtered in-memory by accountID (mirrors ExpenseListView).
    @Query(sort: \Expense.date, order: .reverse) private var allExpenses: [Expense]

    // MARK: - Computed

    /// Expenses attributed to this account.
    private var attributedExpenses: [Expense] {
        allExpenses.filter { $0.accountID == account.id }
    }

    /// Live balance — computed (never stored). Reactive via @Query (ACCT-05, D-10).
    private var liveBalance: Decimal {
        AccountBalance.compute(
            baseline: account.balanceBaseline,
            asOf: account.balanceAsOfDate,
            expenses: allExpenses,
            accountID: account.id
        )
    }

    /// Day sections for attributed expenses (mirrors ExpenseListView.daySections).
    private var daySections: [(id: Date, title: String, total: Decimal, expenses: [Expense])] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: attributedExpenses) { expense -> Date in
            calendar.startOfDay(for: expense.date)
        }
        return grouped.keys.sorted(by: >).map { dayStart in
            let items = grouped[dayStart] ?? []
            let total = items.reduce(Decimal(0)) { $0 + $1.amount }
            return (id: dayStart, title: dayStart.formattedAsRelativeDay(), total: total, expenses: items)
        }
    }

    private var balanceColor: Color {
        // D-09: CC is always red (amount owed is negative); savings/current green/red/.primary
        if account.typeRaw == "credit_card" { return Color(.systemRed) }
        if liveBalance > 0 { return Color(.systemGreen) }
        if liveBalance < 0 { return Color(.systemRed) }
        return .primary
    }

    private var typeLabel: String {
        switch account.typeRaw {
        case "savings": return "Savings"
        case "current": return "Current"
        case "credit_card": return "Credit Card"
        default: return "Savings"
        }
    }

    // MARK: - State

    @State private var showEditSheet = false

    // MARK: - Body

    var body: some View {
        Group {
            if attributedExpenses.isEmpty {
                VStack(spacing: 16) {
                    // Balance card (shown even with no expenses)
                    balanceCard
                        .padding(.horizontal, 16)
                        .padding(.top, 16)
                    ContentUnavailableView(
                        "No Expenses",
                        systemImage: "tray",
                        description: Text("Expenses attributed to this account will appear here.")
                    )
                    Spacer()
                }
            } else {
                List {
                    // Balance card pinned at top as first section
                    Section {
                        balanceCard
                            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                    }

                    // Expenses grouped per day
                    ForEach(daySections, id: \.id) { section in
                        Section {
                            ForEach(section.expenses) { expense in
                                ExpenseRow(expense: expense)
                            }
                        } header: {
                            HStack {
                                Text(section.title)
                                Spacer()
                                Text(section.total.formattedINR())
                            }
                        }
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
        .navigationTitle(account.name ?? "Account")  // T-09-06: plain Text access
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Edit") { showEditSheet = true }
            }
        }
        .sheet(isPresented: $showEditSheet) {
            EditAccountView(account: account)
        }
        // NOTE: No pull-to-refresh — balance is reactive via @Query (D-10 contract)
    }

    // MARK: - Balance Card

    private var balanceCard: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(typeLabel)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Text(liveBalance.formattedINR())
                .font(.largeTitle.weight(.semibold))
                .foregroundStyle(balanceColor)
                .accessibilityValue(liveBalance.formattedINR())

            HStack(spacing: 4) {
                IconTile(
                    symbol: account.symbolName ?? "creditcard",
                    color: Color(hex: account.colorHex ?? "#636366"),
                    size: 20
                )
                if let asOf = account.balanceAsOfDate {
                    Text("as of \(asOf.formattedForDatePickerRow())")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .cardStyle()
    }
}
