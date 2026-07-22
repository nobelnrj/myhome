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

    /// Phase 21 (OVF-01/02/03): the active Overview scope. `OverviewFilter()` is the neutral
    /// all-accounts / current-month default, so every figure below is byte-for-byte unchanged
    /// until a filter is applied. The visible pill/sheet that mutates this lands in Plan 03.
    @State private var filter = OverviewFilter()

    /// The "now" the month boundaries are derived from. Backed by @State so a day/month
    /// rollover while the app is left open refreshes the boundaries (WR-06).
    @State private var referenceDate = Date()

    private var currentMonth: DateComponents {
        Calendar.current.dateComponents([.year, .month], from: referenceDate)
    }

    /// Effective date window + header label for the current scope (OVF-02).
    ///
    /// When `filter.dateRange` is set, the window becomes the inclusive day boundaries of that
    /// custom range and the label reflects it (never the stale month name — OVF-03). Otherwise
    /// the existing current-month boundaries + "MONTH YEAR" label apply, exactly as before.
    private var effectiveBounds: (start: Date, end: Date, label: String)? {
        if let range = filter.dateRange {
            let bounds = OverviewFilterEngine.rangeBoundaries(from: range.lowerBound, to: range.upperBound)
            return (bounds.start, bounds.end, Self.rangeLabel(from: bounds.start, to: bounds.end))
        }
        guard let (start, end) = BudgetCalculator.monthBoundaries(for: currentMonth) else { return nil }
        return (start, end, start.formattedAsMonthYear())
    }

    /// Compact "5 Jun – 12 Jul 2026" label for a custom range (OVF-02 header, OVF-03 anti-stale).
    /// Locale/timezone-adaptive via `DateFormatter` templates, reusing the Date+Display conventions
    /// (D-02: store UTC, display local). The trailing year is shown once; the from-side year is
    /// dropped when both endpoints fall in the same calendar year to keep the pill compact.
    private static func rangeLabel(from: Date, to: Date) -> String {
        let cal = Calendar.current
        let sameYear = cal.component(.year, from: from) == cal.component(.year, from: to)

        let toFmt = DateFormatter()
        toFmt.locale = .current
        toFmt.timeZone = .current
        toFmt.setLocalizedDateFormatFromTemplate("dMMMyyyy")

        let fromFmt = DateFormatter()
        fromFmt.locale = .current
        fromFmt.timeZone = .current
        fromFmt.setLocalizedDateFormatFromTemplate(sameYear ? "dMMM" : "dMMMyyyy")

        return "\(fromFmt.string(from: from)) – \(toFmt.string(from: to))"
    }

    var body: some View {
        NavigationStack {
            if let bounds = effectiveBounds {
                OverviewMonthContent(
                    start: bounds.start,
                    end: bounds.end,
                    monthLabel: bounds.label,
                    filter: filter,
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
    /// Phase 21: the active account × date scope. The @Query window is already date-scoped by
    /// `start`/`end`; this filter narrows the fetched rows by ACCOUNT before every cash-flow
    /// aggregation (OVF-01). `OverviewFilter()` default = passthrough, so default state is unchanged.
    let filter: OverviewFilter
    @Binding var selectedTab: Int
    @Binding var deepLinkNoteID: UUID?
    @Binding var activityCategoryFilter: UUID?
    @Binding var showAddExpense: Bool

    @Query(sort: \Category.sortOrder) private var categories: [Category]
    @Query private var monthExpenses: [Expense]
    /// Review-inbox items needing triage — drives the Gmail review banner (D7-04). Reads existing
    /// data only; the banner just routes to the Expenses tab.
    /// Phase 21: intentionally UNFILTERED — this is a triage queue, not a financial figure, so the
    /// account/date scope must NOT hide expenses still awaiting confirmation (OVF-03 exempts it).
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
    /// Phase 20 (KTCH-01/02): lightweight pantry query behind the Kitchen entry card's one-line
    /// summary. Stock state is derived at render time via KitchenLogic — never stored.
    @Query(sort: \PantryItem.name) private var pantry: [PantryItem]

    @State private var editingExpense: Expense?
    @State private var navigateToAssets = false
    @State private var navigateToAnalytics = false
    /// Phase 20: Kitchen is a PUSHED surface from Overview (Assets/Analytics precedent) — the
    /// native tab bar stays at 5 tabs and the `-startTab` indices 0–4 are untouched.
    @State private var navigateToKitchen = false

    init(start: Date, end: Date, monthLabel: String,
         filter: OverviewFilter,
         selectedTab: Binding<Int>,
         deepLinkNoteID: Binding<UUID?>,
         activityCategoryFilter: Binding<UUID?>,
         showAddExpense: Binding<Bool>) {
        self.start = start
        self.end = end
        self.monthLabel = monthLabel
        self.filter = filter
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
        // Phase 21 (OVF-01): the single account-filtered source of truth. EVERY cash-flow figure
        // below derives from `visibleExpenses` so no figure can silently read the unfiltered array
        // (threat T-21-03). The date window is already applied by the @Query predicate; this applies
        // the ACCOUNT dimension. With `OverviewFilter()` default this returns `monthExpenses`
        // untouched, keeping default-state figures byte-for-byte identical.
        let visibleExpenses = OverviewFilterEngine.apply(filter, to: monthExpenses)

        // Pre-aggregate outside any Chart DSL (Pitfall A guard)
        let spendByCategory = BudgetCalculator.monthlySpend(for: visibleExpenses, categories: categories)
        let totalBudget: Decimal = categories.compactMap(\.monthlyBudget).reduce(.zero, +)

        // Hero cash-flow totals: gross positive-only spend and gross credit-only income, both with
        // internal transfers excluded. Using positive-only spend (not the category net, which sums
        // in credits) prevents a negative spend total from clamping the orb to 0% (see
        // BudgetCalculator.grossSpend / .isTransferForCashFlow).
        let totalSpend = BudgetCalculator.grossSpend(for: visibleExpenses)
        let totalIncome = BudgetCalculator.grossIncome(for: visibleExpenses)

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

        // Numerator for the hero budget strip: spend in budgeted categories only, so the strip's
        // "% used" reconciles with the per-category Budgets rows (both use net per-category spend
        // against the budgeted-only total). Gross cash-flow spend still drives the orb/tiles/net.
        let budgetedSpent: Decimal = budgeted.reduce(Decimal.zero) { $0 + $1.spent }

        let recent = Array(visibleExpenses.prefix(5))

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

        // OVF-03: Over Time series scoped to the account subset (date range is handled by hiding
        // the section, not by this array). `OverviewFilter()` default = passthrough.
        let overTimeExpenses = OverviewFilterEngine.apply(filter, to: allGlobalExpenses)

        // Net-worth suppression test: compute cashValue outside ScrollView (Pitfall A guard)
        let netWorthBreakdown = NetWorthCalculator.breakdown(
            assets: allAssets, accounts: allAccounts, expenses: allGlobalExpenses
        )
        let showNetWorth = !allAssets.isEmpty || netWorthBreakdown.cashValue != 0

        ScrollViewReader { scrollProxy in
        ScrollView(.vertical) {
            LazyVStack(alignment: .leading, spacing: DesignTokens.spacing22) {
                // Screen header: eyebrow month + 34pt title (v2 handoff)
                VStack(alignment: .leading, spacing: 5) {
                    Text(monthLabel).eyebrow()
                    Text("Overview")
                        .font(.system(size: 34, weight: .bold))
                        .foregroundStyle(DesignTokens.label)
                }
                .padding(.bottom, -6)
                .entrance(0)

                // Hero
                // OVF-03: budgets are whole-month, all-account concepts. While a filter is active
                // the hero budget strip would read a subset spend against a whole-month budget — a
                // stale figure — so we feed 0/0 and let SpendBudgetCard render its no-budget state.
                SpendBudgetCard(
                    income: totalIncome,
                    spent: totalSpend,
                    budgetedSpent: filter.isActive ? 0 : budgetedSpent,
                    totalBudget: filter.isActive ? 0 : totalBudget,
                    selectedTab: $selectedTab,
                    onAddExpense: { showAddExpense = true },
                    onDetails: { navigateToAnalytics = true }
                )
                .entrance(1)

                // Gmail review banner — only when there are items to triage
                if !reviewItems.isEmpty {
                    ReviewBanner(count: reviewItems.count) { selectedTab = 1 }
                        .entrance(2)
                }

                // Net Worth card — suppressed when no assets and cash is 0 (D-04 / ASSET-05).
                // OVF-03: also suppressed while a filter is active — net worth is a balance-sheet
                // total across ALL accounts + assets, so it can't reconcile with subset cash flow.
                if showNetWorth && !filter.isActive {
                    sectionHeader("Net Worth", action: ("See holdings", { navigateToAssets = true }))
                        .id("networth")
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
                        .id("donut")
                    SpendDonutCard(
                        ranked: rankedSpend,
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

                // Spend by category — same vertical pill-well chart as Analytics (user pick)
                if !categoryItems.isEmpty {
                    sectionHeader("By category")
                        .id("bycat")
                    AnalyticsCategoryBars(items: categoryItems)
                        .neuSurface(.raised)
                        .entrance(5)
                }

                // Spend over time chart (D-05 — restyled, retained on Overview).
                // OVF-03: when only the ACCOUNT filter is active the multi-month series recomputes
                // for the subset (overTimeExpenses). When a CUSTOM DATE RANGE is active the chart's
                // multi-month window contradicts the selected range, so the section is hidden.
                if filter.dateRange == nil && !overTimeExpenses.isEmpty {
                    sectionHeader("Over Time", action: ("See analytics", { navigateToAnalytics = true }))
                    SpendOverTimeChart(expenses: overTimeExpenses)
                        .entrance(6)
                }

                // Budgets glance — pill-well gauges, same chart language as "By category"
                // (fill = share of that category's budget, red when over).
                // OVF-03: budgets are whole-month, all-account concepts; hidden while any filter is
                // active so no whole-month budget figure survives beside subset cash flow.
                if !budgeted.isEmpty && !filter.isActive {
                    sectionHeader("Budgets", action: ("See all", { selectedTab = 2 }))
                        .id("budgets")
                    BudgetGlancePills(items: Array(budgeted.prefix(5)))
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

                // Kitchen — entry into the pushed pantry surface (Phase 20, KTCH-01/02)
                sectionHeader("Kitchen", action: ("Open pantry", { navigateToKitchen = true }))
                    .id("kitchen")
                KitchenGlanceCard(pantry: pantry) { navigateToKitchen = true }
                    .entrance(9)
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
        .navigationDestination(isPresented: $navigateToKitchen) {
            KitchenView()
        }
        #if DEBUG
        // Screenshot-verify hooks: `-openAnalytics` pushes the Analytics screen on launch
        // (a navigation push, unreachable via -startTab); `-scrollTo <id>` jumps the
        // Overview scroll to a tagged section ("donut", "budgets").
        .onAppear {
            let args = ProcessInfo.processInfo.arguments
            if args.contains("-openAnalytics") {
                navigateToAnalytics = true
            }
            if args.contains("-openKitchen") {
                navigateToKitchen = true
            }
            if let i = args.firstIndex(of: "-scrollTo"), i + 1 < args.count {
                let target = args[i + 1]
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    scrollProxy.scrollTo(target, anchor: .top)
                }
            }
        }
        #endif
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
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(DesignTokens.accentText)
                    .tint(DesignTokens.accentText)
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
// MARK: - Kitchen glance card

/// Compact Overview entry into the pushed Kitchen surface (Phase 20). One line of pantry state:
/// total tracked items plus how many need restocking, tinted with the SAME semantic twins as the
/// pantry row badges (negative when something is out, orange when only low). Colour is never the
/// sole signal — the text states the count, and an SF Symbol carries the state.
private struct KitchenGlanceCard: View {
    let pantry: [PantryItem]
    let action: () -> Void

    private var outCount: Int {
        pantry.filter { KitchenLogic.stockStatus(for: $0) == .out }.count
    }
    private var lowCount: Int {
        pantry.filter { KitchenLogic.stockStatus(for: $0) == .low }.count
    }
    private var needsRestock: Int { outCount + lowCount }

    private var statusColor: Color {
        if outCount > 0 { return DesignTokens.negative }
        if lowCount > 0 { return DesignTokens.orange }
        return DesignTokens.positive
    }

    private var statusSymbol: String {
        if outCount > 0 { return "minus.circle.fill" }
        if lowCount > 0 { return "exclamationmark.triangle.fill" }
        return "checkmark.circle.fill"
    }

    private var subtitle: String {
        guard !pantry.isEmpty else { return "Set up your pantry" }
        if needsRestock == 0 { return "\(pantry.count) items · all stocked" }
        return "\(pantry.count) items · \(needsRestock) need restocking"
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                IconTile(symbol: "basket.fill", color: DesignTokens.catGroceries, size: 38, cornerRadius: 11)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Pantry")
                        .font(.headline)
                        .foregroundStyle(DesignTokens.label)
                    HStack(spacing: 5) {
                        if !pantry.isEmpty {
                            Image(systemName: statusSymbol)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(statusColor)
                        }
                        Text(subtitle)
                            .font(.subheadline)
                            .foregroundStyle(needsRestock > 0 ? statusColor : DesignTokens.label2)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(DesignTokens.label3)
            }
            .neuSurface(.raised, radius: 20, padding: 14, isInteractive: true)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Pantry. \(subtitle)")
        .accessibilityHint("Opens the kitchen")
    }
}

// MARK: - Budgets glance pills

/// Budgets glance as pill-well gauges — the same chart language as "By category", but the
/// fill is the category's OWN budget consumption (spent/limit), not a share of the largest
/// spend. Colour carries state: category colour normally, orange ≥85%, red when over.
/// Colour is never the sole signal — the amount line carries the numbers (D2-09).
private struct BudgetGlancePills: View {
    let items: [(category: Category, spent: Decimal, limit: Decimal)]

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var reveal: Double = 0

    var body: some View {
        HStack(alignment: .bottom, spacing: 0) {
            ForEach(items, id: \.category.id) { item in
                pillColumn(item)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.vertical, 6)
        .onAppear {
            if reduceMotion { reveal = 1 }
            else { withAnimation(.easeOut(duration: 0.5)) { reveal = 1 } }
        }
    }

    @ViewBuilder
    private func pillColumn(_ item: (category: Category, spent: Decimal, limit: Decimal)) -> some View {
        let fraction = fraction(item.spent, item.limit)
        let isOver = item.spent > item.limit
        let color: Color = isOver
            ? DesignTokens.negative
            : (fraction >= 0.85 ? DesignTokens.orange : CategoryStyle.color(for: item.category))

        VStack(spacing: 10) {
            VerticalPillGauge(fraction: fraction, color: color, reveal: reveal)

            VStack(spacing: 2) {
                Text(item.category.name ?? "—")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(DesignTokens.label2)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text("\(item.spent.formattedINRWords()) / \(item.limit.formattedINRWords())")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(isOver ? DesignTokens.negative : DesignTokens.label)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText(item, isOver: isOver))
    }

    private func fraction(_ spent: Decimal, _ limit: Decimal) -> Double {
        guard limit > 0 else { return 0 }
        return NSDecimalNumber(decimal: spent).doubleValue / NSDecimalNumber(decimal: limit).doubleValue
    }

    private func accessibilityText(_ item: (category: Category, spent: Decimal, limit: Decimal), isOver: Bool) -> String {
        let name = item.category.name ?? "Category"
        let state = isOver ? "over budget" : "\(Int(fraction(item.spent, item.limit) * 100)) percent used"
        return "\(name): \(item.spent.formattedINR()) of \(item.limit.formattedINR()), \(state)"
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
            // v2 row spec: whole rupees; income shows an explicit green "+"
            Text(expense.amount < 0
                 ? "+\(abs(expense.amount).formattedINRWhole())"
                 : expense.amount.formattedINRWhole())
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(expense.amount < 0 ? DesignTokens.positive : DesignTokens.label)
                .monospacedDigit()
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
