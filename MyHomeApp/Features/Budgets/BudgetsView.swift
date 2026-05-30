import SwiftUI
import SwiftData

/// Budgets tab root view — month pager + per-category budget cards + uncategorized row.
///
/// Owns its NavigationStack. Month paging state is held in @State (local UI state).
/// Month-scoped expense query is delegated to BudgetsMonthView child (RESEARCH OQ3):
/// re-initializing the child re-runs the @Query with new date boundaries.
///
/// Satisfies: EXP-08 (budget progress), EXP-09 (month-grouped by category + tap-through),
/// D2-10 (TabView tab 2), D2-11 (Manage Categories inline).
struct BudgetsView: View {

    @Environment(\.modelContext) private var context

    @State private var viewedMonth: DateComponents = {
        Calendar.current.dateComponents([.year, .month], from: Date())
    }()

    @State private var showManageCategories: Bool = false

    private var currentMonth: DateComponents {
        Calendar.current.dateComponents([.year, .month], from: Date())
    }

    private var isAtCurrentMonth: Bool {
        viewedMonth.year == currentMonth.year && viewedMonth.month == currentMonth.month
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Month pager header
                monthPagerHeader

                // Month content — child view re-inits on month change (RESEARCH OQ3)
                if let (start, end) = BudgetCalculator.monthBoundaries(for: viewedMonth) {
                    BudgetsMonthView(start: start, end: end)
                }
            }
            .navigationTitle("Budgets")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Manage Categories") {
                        showManageCategories = true
                    }
                }
            }
            .sheet(isPresented: $showManageCategories) {
                ManageCategoriesView()
            }
        }
    }

    // MARK: - Month Pager Header

    @ViewBuilder
    private var monthPagerHeader: some View {
        HStack {
            // < Previous month button
            Button(action: previousMonth) {
                Image(systemName: "chevron.left")
                    .foregroundStyle(.secondary)
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("Previous month")

            Spacer()

            // Month + year label
            if let (start, _) = BudgetCalculator.monthBoundaries(for: viewedMonth) {
                Text(start.formattedAsMonthYear())
                    .font(.title2)
                    .fontWeight(.semibold)
            }

            Spacer()

            // > Next month button — disabled at current month
            Button(action: nextMonth) {
                Image(systemName: "chevron.right")
                    .foregroundStyle(.secondary)
                    .frame(width: 44, height: 44)
            }
            .disabled(isAtCurrentMonth)
            .opacity(isAtCurrentMonth ? 0.3 : 1.0)
            .accessibilityLabel("Next month")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color(.systemBackground))
        Divider()
    }

    // MARK: - Month Navigation

    private func previousMonth() {
        var cal = Calendar.current
        cal.timeZone = TimeZone.current
        guard let start = cal.date(from: viewedMonth),
              let prev = cal.date(byAdding: .month, value: -1, to: start)
        else { return }
        viewedMonth = cal.dateComponents([.year, .month], from: prev)
    }

    private func nextMonth() {
        guard !isAtCurrentMonth else { return }
        var cal = Calendar.current
        cal.timeZone = TimeZone.current
        guard let start = cal.date(from: viewedMonth),
              let next = cal.date(byAdding: .month, value: 1, to: start)
        else { return }
        viewedMonth = cal.dateComponents([.year, .month], from: next)
    }
}

// MARK: - BudgetsMonthView

/// Child view that owns the month-scoped @Query. Re-initialized when start/end change
/// (RESEARCH OQ3 — child re-init triggers @Query re-execution with new bounds).
private struct BudgetsMonthView: View {

    let start: Date
    let end: Date

    @Query(sort: \Category.sortOrder) private var categories: [Category]
    @Query private var monthExpenses: [Expense]

    init(start: Date, end: Date) {
        self.start = start
        self.end = end
        let lo = start
        let hi = end
        _monthExpenses = Query(
            filter: #Predicate<Expense> { expense in
                expense.date >= lo && expense.date <= hi
            },
            sort: \.date, order: .reverse
        )
    }

    var body: some View {
        let spendByCategory = BudgetCalculator.monthlySpend(for: monthExpenses, categories: categories)
        let uncategorizedTotal = BudgetCalculator.uncategorizedSpend(for: monthExpenses)

        List {
            // Per-category budget cards sorted by sortOrder
            ForEach(categories) { category in
                let spent = spendByCategory[category.persistentModelID] ?? .zero
                let progressData = BudgetProgressData(
                    category: category,
                    spent: spent,
                    budget: category.monthlyBudget
                )
                NavigationLink {
                    FilteredExpenseListView(category: category, start: start, end: end)
                } label: {
                    BudgetCategoryCard(progressData: progressData)
                }
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }

            // Uncategorized row — only shown when total != 0 (D2-08)
            if uncategorizedTotal != 0 {
                NavigationLink {
                    UncategorizedExpenseListView(start: start, end: end)
                } label: {
                    uncategorizedRow(total: uncategorizedTotal)
                }
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }
        }
        .listStyle(.insetGrouped)
    }

    @ViewBuilder
    private func uncategorizedRow(total: Decimal) -> some View {
        HStack {
            Image(systemName: "tray")
                .font(.body)
                .foregroundStyle(.secondary)
                .frame(width: 28, height: 28)
                .accessibilityHidden(true)
            Text("Uncategorized")
                .font(.body)
                .foregroundStyle(.primary)
            Spacer()
            Text(total.formattedINR())
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.04), radius: 2, y: 1)
    }
}
