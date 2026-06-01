import SwiftUI
import SwiftData

/// Overview dashboard — default launch tab (tag 0).
///
/// Owns the three @Query sources (month expenses, categories, all notes), pre-aggregates with
/// OverviewAggregation + BudgetCalculator helpers, and passes value-type data down to the five
/// dumb card components (Plans 04-03 / 04-04). No raw @Query arrays enter any Chart DSL.
///
/// Architecture: mirrors BudgetsView — a thin parent that computes current-month boundaries
/// and delegates @Query ownership to an inner `OverviewMonthContent` child. Re-initialising
/// the child with new boundaries re-triggers @Query execution (RESEARCH OQ3 pattern).
///
/// Satisfies: OVR-01, OVR-02, OVR-03, OVR-04, EXP-10, EXP-11, D4-01, D4-03, D4-06.
struct OverviewView: View {

    @Binding var selectedTab: Int
    @Binding var deepLinkNoteID: UUID?

    @State private var showAddExpense = false

    private var currentMonth: DateComponents {
        Calendar.current.dateComponents([.year, .month], from: Date())
    }

    var body: some View {
        NavigationStack {
            if let (start, end) = BudgetCalculator.monthBoundaries(for: currentMonth) {
                OverviewMonthContent(
                    start: start,
                    end: end,
                    selectedTab: $selectedTab,
                    deepLinkNoteID: $deepLinkNoteID,
                    showAddExpense: $showAddExpense
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
    }
}

// MARK: - OverviewMonthContent

/// Child view that owns the month-scoped @Query sources. Re-initialized when start/end change
/// (RESEARCH OQ3 — child re-init triggers @Query re-execution with new bounds).
///
/// Pre-aggregates all data in `body` before passing value types to card subviews.
/// No raw @Query array is ever passed into a Chart DSL.
private struct OverviewMonthContent: View {

    let start: Date
    let end: Date
    @Binding var selectedTab: Int
    @Binding var deepLinkNoteID: UUID?
    @Binding var showAddExpense: Bool

    @Query(sort: \Category.sortOrder) private var categories: [Category]
    @Query private var monthExpenses: [Expense]
    /// Year-scoped expenses for SpendOverTimeChart. The aggregator computes its own
    /// date windows (rolling week / current month / current calendar year) so it needs
    /// data spanning the widest range it can display — the calendar year — not just the
    /// current month (CR-01: a month-bounded array makes the Year view show 11 empty
    /// buckets and drops prior-month days from week views straddling a month boundary).
    @Query private var yearExpenses: [Expense]
    @Query private var allNotes: [Note]

    init(start: Date, end: Date,
         selectedTab: Binding<Int>,
         deepLinkNoteID: Binding<UUID?>,
         showAddExpense: Binding<Bool>) {
        self.start = start
        self.end = end
        self._selectedTab = selectedTab
        self._deepLinkNoteID = deepLinkNoteID
        self._showAddExpense = showAddExpense

        let lo = start
        let hi = end
        _monthExpenses = Query(
            filter: #Predicate<Expense> { expense in
                expense.date >= lo && expense.date <= hi
            },
            sort: \.date, order: .reverse
        )

        // Year-scoped query feeding SpendOverTimeChart (CR-01). Bounded to the start of
        // the current calendar year so the Year range's 12 month-buckets and any
        // month-straddling Week window receive the data the aggregator expects.
        let cal = Calendar.current
        let yearStart = cal.date(from: cal.dateComponents([.year], from: Date())) ?? start
        _yearExpenses = Query(
            filter: #Predicate<Expense> { expense in
                expense.date >= yearStart
            },
            sort: \.date, order: .reverse
        )
        _allNotes = Query(sort: \Note.modifiedAt, order: .reverse)
    }

    var body: some View {
        // Pre-aggregate outside any Chart DSL (Pitfall A guard)
        let spendByCategory = BudgetCalculator.monthlySpend(for: monthExpenses, categories: categories)
        let totalBudget: Decimal = categories.compactMap(\.monthlyBudget).reduce(.zero, +)
        let totalSpend = spendByCategory.values.reduce(.zero, +)
            + BudgetCalculator.uncategorizedSpend(for: monthExpenses)
        let top3 = OverviewAggregation.topCategories(
            spendByCategory: spendByCategory,
            categories: categories
        )
        let pinnedNote = OverviewAggregation.pinnedOrChecklistNote(from: allNotes)
        let isFallbackChecklist: Bool = {
            guard let note = pinnedNote else { return false }
            // Determine if this is the fallback checklist note (not a real pinned note)
            let sections = NoteListOrganizer.organize(allNotes)
            return sections.pinned.first == nil
        }()
        // Build CategorySpendItem array (Double, sorted descending) for by-category chart
        let categoryItems: [CategorySpendItem] = spendByCategory
            .compactMap { (id, spend) -> CategorySpendItem? in
                guard spend > .zero,
                      let category = categories.first(where: { $0.persistentModelID == id })
                else { return nil }
                return CategorySpendItem(
                    id: id,
                    name: category.name ?? "Unnamed",
                    spent: NSDecimalNumber(decimal: spend).doubleValue
                )
            }
            .sorted { $0.spent > $1.spent }

        ScrollView(.vertical) {
            LazyVStack(alignment: .leading, spacing: 16) {
                SpendBudgetCard(
                    totalSpend: totalSpend,
                    totalBudget: totalBudget,
                    selectedTab: $selectedTab
                )

                TopCategoriesCard(top3: top3)

                PinnedNoteCard(
                    note: pinnedNote,
                    isFallbackChecklist: isFallbackChecklist,
                    selectedTab: $selectedTab,
                    deepLinkNoteID: $deepLinkNoteID
                )

                SpendByCategoryChart(categoryItems: categoryItems)

                SpendOverTimeChart(expenses: yearExpenses)
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
        }
    }
}
