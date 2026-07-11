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
                // Screen header: 34pt title + raised "Manage" pill (v2 handoff, Screen 3)
                titleHeader

                // Month stepper: ‹ July 2026 › with accent chevrons
                monthStepper

                // Month content — child view re-inits on month change (RESEARCH OQ3)
                if let (start, end) = BudgetCalculator.monthBoundaries(for: viewedMonth) {
                    BudgetsMonthView(start: start, end: end)
                }
            }
            .background(DesignTokens.bgCanvas)
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showManageCategories) {
                ManageCategoriesView()
            }
        }
    }

    // MARK: - Title Header

    @ViewBuilder
    private var titleHeader: some View {
        HStack(alignment: .center) {
            Text("Budgets")
                .font(.system(size: 34, weight: .bold))
                .foregroundStyle(DesignTokens.label)
            Spacer()
            Button("Manage") {
                showManageCategories = true
            }
            .buttonStyle(NeuSecondaryButtonStyle(
                expands: false, fontSize: 14, verticalPadding: 11, horizontalPadding: 22
            ))
            .accessibilityLabel("Manage categories")
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    // MARK: - Month Stepper

    @ViewBuilder
    private var monthStepper: some View {
        HStack(spacing: 18) {
            Button(action: previousMonth) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(DesignTokens.accent)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Previous month")

            if let (start, _) = BudgetCalculator.monthBoundaries(for: viewedMonth) {
                Text(start.formattedAsMonthYear())
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(DesignTokens.label)
                    .frame(minWidth: 110)
            }

            Button(action: nextMonth) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(isAtCurrentMonth ? DesignTokens.label3 : DesignTokens.accent)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .disabled(isAtCurrentMonth)
            .accessibilityLabel("Next month")
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 2)
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

        // Aggregate across budgeted categories for the summary ring.
        let budgeted: [(spent: Decimal, limit: Decimal)] = categories.compactMap { category in
            guard let limit = category.monthlyBudget, limit > 0 else { return nil }
            return (spendByCategory[category.persistentModelID] ?? .zero, limit)
        }

        List {
            // Summary ring (or "set a budget" prompt) at the top of the list.
            Section {
                BudgetSummaryCard(budgeted: budgeted)
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }

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
        .scrollContentBackground(.hidden)
        .background(DesignTokens.bgCanvas)
    }

    @ViewBuilder
    private func uncategorizedRow(total: Decimal) -> some View {
        HStack {
            Image(systemName: "tray")
                .font(.body)
                .foregroundStyle(DesignTokens.label2)
                .frame(width: 28, height: 28)
                .accessibilityHidden(true)
            Text("Uncategorized")
                .font(.body)
                .foregroundStyle(DesignTokens.label)
            Spacer()
            Text(total.formattedINR())
                .font(.subheadline)
                .foregroundStyle(DesignTokens.label2)
        }
        .neuSurface(.raised, radius: 20)
    }
}

// MARK: - BudgetSummaryCard

/// Top-of-Budgets summary: a donut ring of % used + left-to-spend / over-budget figure and an
/// "N over limit" chip. Falls back to a "set a budget" prompt when no category has a limit.
/// Mirrors the design's Budgets header card. Aggregation only — no @Query.
private struct BudgetSummaryCard: View {

    let budgeted: [(spent: Decimal, limit: Decimal)]

    private var totalLimit: Decimal { budgeted.reduce(.zero) { $0 + $1.limit } }
    private var totalSpent: Decimal { budgeted.reduce(.zero) { $0 + $1.spent } }
    private var remaining: Decimal { totalLimit - totalSpent }
    private var overCount: Int { budgeted.filter { $0.spent > $0.limit }.count }

    private var fraction: Double {
        guard totalLimit > 0 else { return 0 }
        return NSDecimalNumber(decimal: totalSpent).doubleValue
            / NSDecimalNumber(decimal: totalLimit).doubleValue
    }

    private var ringColor: Color {
        if remaining < 0 { return DesignTokens.negative }
        if fraction > 0.85 { return DesignTokens.orange }
        return DesignTokens.positive
    }

    var body: some View {
        if budgeted.isEmpty {
            VStack(spacing: 10) {
                Image(systemName: "chart.pie")
                    .font(.system(size: 28))
                    .foregroundStyle(DesignTokens.accent)
                    .frame(width: 52, height: 52)
                    .background(DesignTokens.fillRecessed, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .neonGlow(DesignTokens.accent, radius: 7, intensity: 0.8)
                Text("Set a budget to track spending")
                    .font(.headline)
                    .foregroundStyle(DesignTokens.label)
                    .multilineTextAlignment(.center)
                Text("Tap any category below to set a monthly limit.")
                    .font(.subheadline)
                    .foregroundStyle(DesignTokens.label2)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .neuSurface(.floating, padding: 22)
        } else {
            HStack(spacing: 20) {
                // Circular well + gradient ring + raised % puck (v2 handoff, Screen 3)
                NeuCircularWell(size: 136) {
                    BudgetGradientRing(fraction: fraction, over: remaining < 0)
                    NeuCircularPuck(size: 80) {
                        VStack(spacing: 0) {
                            Text("\(Int(fraction * 100))%")
                                .font(.system(size: 20, weight: .bold))
                                .foregroundStyle(DesignTokens.label)
                                .monospacedDigit()
                                .lineLimit(1)
                                .minimumScaleFactor(0.6)
                                .frame(maxWidth: 62)
                            Text("used")
                                .font(.system(size: 11))
                                .foregroundStyle(DesignTokens.label2)
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(remaining >= 0 ? "LEFT TO SPEND" : "OVER BUDGET").eyebrow()
                    Text(abs(remaining).formattedINRWhole())
                        .font(.system(size: 32, weight: .semibold))
                        .foregroundStyle(remaining >= 0 ? DesignTokens.label : DesignTokens.negative)
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    Text("\(totalSpent.formattedINRWords()) of \(totalLimit.formattedINRWords())")
                        .font(.system(size: 13))
                        .foregroundStyle(DesignTokens.label3)
                    if overCount > 0 {
                        Label("\(overCount) over limit", systemImage: "flag.fill")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(DesignTokens.negative)
                            .padding(.top, 4)
                    }
                }
            }
            .neuSurface(.floating, padding: 20)
        }
    }
}

// MARK: - BudgetGradientRing

/// The summary ring: a faint recessed track circle plus a rounded-cap yellow→green gradient
/// arc with a soft yellow glow (`drop-shadow(0 4px 12px rgba(255,214,10,0.35))`). Turns
/// solid red when over budget. Sweeps in on appear; honors Reduce Motion.
private struct BudgetGradientRing: View {
    /// 0…1+ fraction of budget used (clamped to a full turn).
    let fraction: Double
    let over: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var reveal: Double = 0

    private let size: CGFloat = 108
    private let lineWidth: CGFloat = 13

    var body: some View {
        ZStack {
            // Faint track
            Circle()
                .stroke(Color.black.opacity(0.18), lineWidth: lineWidth)

            // Gradient arc
            Circle()
                .trim(from: 0, to: max(0.0001, min(fraction, 1) * reveal))
                .stroke(
                    over
                        ? AnyShapeStyle(DesignTokens.negative)
                        : AnyShapeStyle(LinearGradient(
                            colors: [DesignTokens.accent, DesignTokens.positive],
                            startPoint: .top, endPoint: .bottom
                          )),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .shadow(color: (over ? DesignTokens.negative : DesignTokens.accent).opacity(0.35),
                        radius: 12, y: 4)
        }
        .frame(width: size, height: size)
        .onAppear {
            if reduceMotion { reveal = 1 }
            else { withAnimation(.easeOut(duration: 0.5)) { reveal = 1 } }
        }
        .accessibilityHidden(true)
    }
}
