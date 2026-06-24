import SwiftUI
import SwiftData
import UIKit

/// Overview dashboard — default launch tab (tag 0).
///
/// Restyled to the `MyHome.html` design: a month label, the spend hero + stacked bar, a Gmail
/// review banner, a "Where it's going" donut card, a Budgets glance, and a Recent list. The
/// previous Pinned-Note card and Spend-over-time chart are intentionally not shown here (the
/// user chose to match the design exactly).
///
/// Owns the @Query sources, pre-aggregates with OverviewAggregation + BudgetCalculator, and
/// passes value-type data down to dumb subviews. No raw @Query array enters any Chart DSL.
///
/// Satisfies: OVR-01, OVR-02, OVR-04, EXP-10, EXP-11, D4-01, D4-03, D4-06.
struct OverviewView: View {

    @Binding var selectedTab: Int
    @Binding var deepLinkNoteID: UUID?
    /// OVR-06: Category filter binding — written by SpendDonutCard tap, read by ExpenseListView.
    @Binding var activityCategoryFilter: UUID?

    @State private var showAddExpense = false

    /// The "now" the month boundaries are derived from. Backed by @State so a day/month
    /// rollover while the app is left open refreshes the boundaries (WR-06).
    @State private var referenceDate = Date()

    private var currentMonth: DateComponents {
        Calendar.current.dateComponents([.year, .month], from: referenceDate)
    }

    var body: some View {
        NavigationStack {
            if let (start, end) = BudgetCalculator.monthBoundaries(for: currentMonth) {
                OverviewMonthContent(
                    start: start,
                    end: end,
                    monthLabel: start.formattedAsMonthYear(),
                    selectedTab: $selectedTab,
                    deepLinkNoteID: $deepLinkNoteID,
                    activityCategoryFilter: $activityCategoryFilter,
                    showAddExpense: $showAddExpense
                )
            } else {
                // WR-04: monthBoundaries is Optional; show an observable fallback rather than blank.
                ContentUnavailableView(
                    "Couldn't load this month",
                    systemImage: "calendar.badge.exclamationmark",
                    description: Text("Please reopen the Home tab.")
                )
            }
        }
        .navigationTitle("Home")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showAddExpense = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Add Expense")
            }
        }
        .sheet(isPresented: $showAddExpense) {
            AddExpenseView()
        }
        // WR-06: refresh the reference date on a significant time change (midnight / month rollover).
        .onReceive(NotificationCenter.default.publisher(
            for: UIApplication.significantTimeChangeNotification
        )) { _ in
            referenceDate = Date()
        }
    }
}

// MARK: - OverviewMonthContent

/// Child view that owns the month-scoped @Query sources. Re-initialized when start/end change
/// (RESEARCH OQ3 — child re-init triggers @Query re-execution with new bounds).
private struct OverviewMonthContent: View {

    let start: Date
    let end: Date
    let monthLabel: String
    @Binding var selectedTab: Int
    @Binding var deepLinkNoteID: UUID?
    @Binding var activityCategoryFilter: UUID?
    @Binding var showAddExpense: Bool

    @Query(sort: \Category.sortOrder) private var categories: [Category]
    @Query private var monthExpenses: [Expense]
    /// Review-inbox items needing triage — drives the Gmail review banner (D7-04). Reads existing
    /// data only; the banner just routes to the Expenses tab.
    @Query(
        filter: #Predicate<Expense> { $0.ingestionStateRaw != nil && $0.ingestionStateRaw != "autoSaved" },
        sort: \Expense.createdAt,
        order: .reverse
    ) private var reviewItems: [Expense]

    // Net-worth card data sources (D-04 / ASSET-05/07/08)
    @Query(sort: \Asset.createdAt, order: .reverse) private var allAssets: [Asset]
    @Query(sort: \NetWorthSnapshot.date, order: .reverse) private var netWorthSnapshots: [NetWorthSnapshot]
    @Query private var allAccounts: [Account]
    @Query private var allGlobalExpenses: [Expense]

    @State private var editingExpense: Expense?
    @State private var navigateToAssets = false
    @State private var navigateToAnalytics = false

    init(start: Date, end: Date, monthLabel: String,
         selectedTab: Binding<Int>,
         deepLinkNoteID: Binding<UUID?>,
         activityCategoryFilter: Binding<UUID?>,
         showAddExpense: Binding<Bool>) {
        self.start = start
        self.end = end
        self.monthLabel = monthLabel
        self._selectedTab = selectedTab
        self._deepLinkNoteID = deepLinkNoteID
        self._activityCategoryFilter = activityCategoryFilter
        self._showAddExpense = showAddExpense

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
        // Pre-aggregate outside any Chart DSL (Pitfall A guard)
        let spendByCategory = BudgetCalculator.monthlySpend(for: monthExpenses, categories: categories)
        let totalBudget: Decimal = categories.compactMap(\.monthlyBudget).reduce(.zero, +)
        let totalSpend = spendByCategory.values.reduce(.zero, +)
            + BudgetCalculator.uncategorizedSpend(for: monthExpenses)

        // Income this month (expenses with negative amounts = refunds/income, negated to positive display)
        let totalIncome = monthExpenses
            .filter { $0.amount < 0 && $0.isTransfer != true }
            .reduce(Decimal.zero) { $0 + abs($1.amount) }

        // Category spend, sorted descending — feeds the stacked bar + donut + legend.
        let rankedSpend: [(category: Category, spent: Decimal)] = categories
            .compactMap { category in
                let spent = spendByCategory[category.persistentModelID] ?? .zero
                return spent > .zero ? (category, spent) : nil
            }
            .sorted { $0.spent > $1.spent }

        // Budgeted categories, most-consumed first — feeds the Budgets glance.
        let budgeted: [(category: Category, spent: Decimal, limit: Decimal)] = categories
            .compactMap { category in
                guard let limit = category.monthlyBudget, limit > 0 else { return nil }
                return (category, spendByCategory[category.persistentModelID] ?? .zero, limit)
            }
            .sorted { fraction($0.spent, $0.limit) > fraction($1.spent, $1.limit) }

        let recent = Array(monthExpenses.prefix(5))

        // CategorySpendItem for SpendByCategoryChart (D-05: keep chart on Overview, restyled)
        let categoryItems: [CategorySpendItem] = rankedSpend.map { item in
            CategorySpendItem(
                id: item.category.persistentModelID,
                name: item.category.name ?? "—",
                spent: NSDecimalNumber(decimal: item.spent).doubleValue,
                spentDecimal: item.spent,
                color: CategoryStyle.color(for: item.category)
            )
        }

        // Net-worth suppression test: compute cashValue outside ScrollView (Pitfall A guard)
        let netWorthBreakdown = NetWorthCalculator.breakdown(
            assets: allAssets, accounts: allAccounts, expenses: allGlobalExpenses
        )
        let showNetWorth = !allAssets.isEmpty || netWorthBreakdown.cashValue != 0

        ScrollView(.vertical) {
            LazyVStack(alignment: .leading, spacing: 16) {
                // Month label
                Text(monthLabel)
                    .font(.subheadline)
                    .foregroundStyle(DesignTokens.label2)
                    .padding(.bottom, -8)
                    .entrance(0)

                // Hero
                SpendBudgetCard(
                    income: totalIncome,
                    spent: totalSpend,
                    totalBudget: totalBudget,
                    selectedTab: $selectedTab
                )
                .entrance(1)

                // Gmail review banner — only when there are items to triage
                if !reviewItems.isEmpty {
                    ReviewBanner(count: reviewItems.count) { selectedTab = 1 }
                        .entrance(2)
                }

                // Net Worth card — suppressed when no assets and cash is 0 (D-04 / ASSET-05)
                if showNetWorth {
                    sectionHeader("Net Worth", action: ("See holdings", { navigateToAssets = true }))
                    NetWorthCard(
                        allAssets: allAssets,
                        allAccounts: allAccounts,
                        allExpenses: allGlobalExpenses,
                        snapshots: netWorthSnapshots
                    )
                    .entrance(3)
                }

                // Where it’s going — donut + legend (OVR-05/06)
                if !rankedSpend.isEmpty {
                    sectionHeader("Where it’s going")
                    SpendDonutCard(
                        ranked: Array(rankedSpend.prefix(4)),
                        // Share denominator = total categorised spend (gross), so per-category
                        // %s are stable regardless of income netting `totalSpend` down.
                        total: rankedSpend.reduce(Decimal.zero) { $0 + $1.spent },
                        onCategoryTap: { uuid in
                            activityCategoryFilter = uuid
                            selectedTab = 1
                        }
                    )
                    .entrance(4)
                }

                // Spend by category chart (D-05 — restyled, retained on Overview)
                if !categoryItems.isEmpty {
                    sectionHeader("By Category")
                    SpendByCategoryChart(categoryItems: categoryItems)
                        .entrance(5)
                }

                // Spend over time chart (D-05 — restyled, retained on Overview)
                if !allGlobalExpenses.isEmpty {
                    sectionHeader("Over Time", action: ("See analytics", { navigateToAnalytics = true }))
                    SpendOverTimeChart(expenses: allGlobalExpenses)
                        .entrance(6)
                }

                // Budgets glance
                if !budgeted.isEmpty {
                    sectionHeader("Budgets", action: ("See all", { selectedTab = 2 }))
                    VStack(spacing: 0) {
                        ForEach(Array(budgeted.prefix(3).enumerated()), id: \.element.category.id) { index, item in
                            BudgetGlanceRow(category: item.category, spent: item.spent, limit: item.limit)
                            if index < min(budgeted.count, 3) - 1 {
                                Divider().padding(.leading, 36)
                            }
                        }
                    }
                    .neuSurface(.raised)
                    .entrance(7)
                }

                // Recent
                if !recent.isEmpty {
                    sectionHeader("Recent", action: ("See all", { selectedTab = 1 }))
                    VStack(spacing: 0) {
                        ForEach(Array(recent.enumerated()), id: \.element.id) { index, expense in
                            Button {
                                editingExpense = expense
                            } label: {
                                RecentExpenseRow(expense: expense)
                            }
                            .buttonStyle(.plain)
                            if index < recent.count - 1 {
                                Divider().padding(.leading, 58)
                            }
                        }
                    }
                    .neuSurface(.raised, padding: nil)
                    .entrance(8)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
        }
        .scrollContentBackground(.hidden)
        .background(DesignTokens.bgCanvas)
        .sheet(item: $editingExpense) { expense in
            EditExpenseView(expense: expense)
        }
        .navigationDestination(isPresented: $navigateToAssets) {
            AssetsListView()
        }
        .navigationDestination(isPresented: $navigateToAnalytics) {
            AnalyticsView(expenses: allGlobalExpenses, categories: categories)
        }
    }

    // MARK: - Section header

    @ViewBuilder
    private func sectionHeader(_ title: String, action: (label: String, run: () -> Void)? = nil) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.title2)
                .fontWeight(.bold)
            Spacer()
            if let action {
                Button(action.label, action: action.run)
                    .font(.subheadline)
                    .foregroundStyle(DesignTokens.accent)
                    .tint(DesignTokens.accent)
                    .neonGlow(DesignTokens.accent, radius: 5, intensity: 0.7)
            }
        }
        .padding(.bottom, -8)
    }

    // MARK: - Decimal helpers

    private func double(_ d: Decimal) -> Double { NSDecimalNumber(decimal: d).doubleValue }
    private func fraction(_ spent: Decimal, _ limit: Decimal) -> Double {
        guard limit > 0 else { return 0 }
        return double(spent) / double(limit)
    }
}

// MARK: - Review banner

private struct ReviewBanner: View {
    let count: Int
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                IconTile(symbol: "envelope", color: DesignTokens.accent, size: 38, cornerRadius: 10)
                    .neonGlow(DesignTokens.accent, radius: 6, intensity: 0.8)
                VStack(alignment: .leading, spacing: 1) {
                    Text("\(count) \(count == 1 ? "expense" : "expenses") to review")
                        .font(.headline)
                        .foregroundStyle(DesignTokens.label)
                    Text("Imported from Gmail · tap to confirm")
                        .font(.subheadline)
                        .foregroundStyle(DesignTokens.label2)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(DesignTokens.label3)
            }
            .neuSurface(.raised, radius: 20, padding: 14, isInteractive: true)
        }
        .buttonStyle(.plain)
    }
}
// MARK: - Budgets glance row

private struct BudgetGlanceRow: View {
    let category: Category
    let spent: Decimal
    let limit: Decimal

    private var fraction: Double {
        guard limit > 0 else { return 0 }
        return NSDecimalNumber(decimal: spent).doubleValue / NSDecimalNumber(decimal: limit).doubleValue
    }
    private var isOver: Bool { spent > limit }
    private var barColor: Color {
        if isOver { return DesignTokens.negative }
        if fraction >= 0.85 { return DesignTokens.orange }
        return CategoryStyle.color(for: category)
    }

    var body: some View {
        VStack(spacing: 9) {
            HStack(spacing: 10) {
                IconTile(category: category, size: 26)
                Text(category.name ?? "—")
                    .font(.subheadline)
                    .lineLimit(1)
                Spacer(minLength: 6)
                HStack(spacing: 4) {
                    Text(spent.formattedINRWhole())
                        .foregroundStyle(isOver ? DesignTokens.negative : DesignTokens.label2)
                    Text("/ \(limit.formattedINRWhole())")
                        .foregroundStyle(DesignTokens.label3)
                }
                .font(.subheadline)
                .fontWeight(.medium)
            }
            ProgressBarLine(fraction: fraction, color: barColor)
        }
        .padding(.vertical, 13)
    }
}

/// Thin inline progress bar used by the Overview glance (matches the design's `ProgressBar`).
private struct ProgressBarLine: View {
    let fraction: Double
    let color: Color
    var height: CGFloat = 8

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(DesignTokens.fillRecessed2)
                Capsule().fill(color)
                    .frame(width: max(0, min(CGFloat(fraction), 1)) * geo.size.width)
            }
        }
        .frame(height: height)
        .accessibilityHidden(true)
    }
}

// MARK: - Recent expense row

private struct RecentExpenseRow: View {
    let expense: Expense

    private var category: Category? { expense.categories.first }

    var body: some View {
        HStack(spacing: 12) {
            IconTile(category: category, size: 30)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.body)
                    .foregroundStyle(DesignTokens.label)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(DesignTokens.label2)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            Text(expense.amount.formattedINR())
                .font(.body)
                .foregroundStyle(expense.amount < 0 ? DesignTokens.positive : DesignTokens.label)
                .lineLimit(1)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
        .contentShape(Rectangle())
    }

    private var title: String {
        if let note = expense.note, !note.isEmpty { return note }
        return category?.name ?? "Expense"
    }
    private var subtitle: String {
        let cat = category?.name ?? "Uncategorized"
        return "\(cat) · \(expense.date.formattedForExpenseList())"
    }
}
