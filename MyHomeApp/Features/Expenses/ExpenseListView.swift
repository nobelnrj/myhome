import SwiftUI
import SwiftData

/// Root expense list view.
///
/// Layout (UI-SPEC Screen 1):
/// - NavigationStack, navigationTitle "Expenses" inline
/// - "Needs Review" section at the top for ingested expenses needing triage (D7-04)
/// - Main expenses grouped into month sections (header = "May 2026" + month total),
///   newest month first; rows within a month stay date-descending.
/// - Toolbar filter menu to scope the list by category (All / each category / Uncategorized).
/// - Each row: ExpenseRow with onTapGesture → edit sheet
/// - .onDelete: swipe-to-delete via modelContext.delete
/// - Toolbar: "+" (SF Symbol plus, accent, accessibilityLabel "Add Expense")
/// - Empty state: ContentUnavailableView "No Expenses Yet"
///
/// Reads via @Query (RESEARCH Pattern 4). Writes via modelContext (no repository wrapper).
/// Pitfall 5: @Observable/@State/@Bindable only — no @StateObject/@ObservedObject/@Published.
struct ExpenseListView: View {

    /// All expenses sorted by date descending (includes autoSaved ingested ones).
    @Query(sort: \Expense.date, order: .reverse) private var expenses: [Expense]

    /// Categories for the filter menu, in their predefined display order.
    @Query(sort: \Category.sortOrder) private var categories: [Category]

    /// Review items: ingested expenses that need triage (needsReview or possibleDuplicate).
    /// Sorted by createdAt descending (most recent first) — RESEARCH Code Example 2.
    @Query(
        filter: #Predicate<Expense> { $0.ingestionStateRaw != nil && $0.ingestionStateRaw != "autoSaved" },
        sort: \Expense.createdAt,
        order: .reverse
    ) private var reviewItems: [Expense]

    @Environment(\.modelContext) private var context

    @State private var showingAddSheet: Bool = false
    @State private var editingExpense: Expense? = nil

    /// Active category filter for the main list. Defaults to showing everything.
    @State private var categoryFilter: CategoryFilter = .all

    /// Active account filter for the main list. Defaults to showing all accounts (ACCT-06/D-07).
    @State private var accountFilter: AccountFilter = .all

    /// Active accounts for the account filter menu (archived excluded — D-08).
    @Query(filter: #Predicate<Account> { !$0.isArchived }, sort: \Account.sortOrder)
    private var activeAccounts: [Account]

    /// Bound to RootView so it can drive the Expenses tab badge (D7-04).
    @Binding var reviewBadgeCount: Int

    /// Single-selection filter for the main expense list.
    private enum CategoryFilter: Hashable {
        case all
        case uncategorized
        case category(UUID)
    }

    /// Single-selection account filter for the main expense list (ACCT-06/D-07).
    private enum AccountFilter: Hashable {
        case all
        case unassigned       // accountID == nil
        case account(UUID)    // accountID == specific UUID
    }

    /// One day's worth of expenses, used as a List section (design groups by day).
    private struct DaySection: Identifiable {
        let id: Date            // start-of-day (stable section identity)
        let title: String       // "Today" / "Yesterday" / "Wed, 3 Jun 2026"
        let total: Decimal       // sum of amounts on this day
        let expenses: [Expense]  // date-descending (inherited from the @Query order)
    }

    var body: some View {
        NavigationStack {
            Group {
                if expenses.isEmpty && reviewItems.isEmpty {
                    ContentUnavailableView(
                        "No Expenses Yet",
                        systemImage: "tray",
                        description: Text("Tap + to record your first expense.")
                    )
                } else {
                    List {
                        // "Needs Review" section — shown above the main expense list (D7-04)
                        if !reviewItems.isEmpty {
                            Section("Needs Review") {
                                ForEach(reviewItems) { expense in
                                    ReviewInboxRow(expense: expense)
                                        .contentShape(Rectangle())
                                        .onTapGesture {
                                            editingExpense = expense
                                        }
                                }
                            }
                        }

                        // Main list — grouped into day sections (filtered by category).
                        if daySections.isEmpty {
                            Section {
                                ContentUnavailableView(
                                    "No Matching Expenses",
                                    systemImage: "line.3.horizontal.decrease.circle",
                                    description: Text("No expenses for \(filterLabel).")
                                )
                            }
                        } else {
                            ForEach(daySections) { section in
                                Section {
                                    ForEach(section.expenses) { expense in
                                        ExpenseRow(expense: expense)
                                            .contentShape(Rectangle())
                                            .onTapGesture {
                                                editingExpense = expense
                                            }
                                    }
                                    .onDelete { offsets in
                                        deleteExpenses(in: section.expenses, at: offsets)
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
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("Expenses")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if !expenses.isEmpty {
                    ToolbarItem(placement: .topBarLeading) {
                        filterMenu
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button(action: { showingAddSheet = true }) {
                        Image(systemName: "plus")
                    }
                    .tint(.accentColor)
                    .accessibilityLabel("Add Expense")
                }
            }
            .sheet(isPresented: $showingAddSheet) {
                AddExpenseView()
            }
            .sheet(item: $editingExpense) { expense in
                EditExpenseView(expense: expense)
            }
        }
        // Keep the badge count in sync whenever reviewItems changes (D7-04)
        .onChange(of: reviewItems.count) { _, newCount in
            reviewBadgeCount = newCount
        }
        .onAppear {
            reviewBadgeCount = reviewItems.count
        }
    }

    // MARK: - Filter menu

    private var filterMenu: some View {
        Menu {
            // Category filter section
            Picker("Category", selection: $categoryFilter) {
                Label("All Categories", systemImage: "tray.full").tag(CategoryFilter.all)
                ForEach(categories) { category in
                    Label(category.name ?? "Untitled", systemImage: category.symbolName ?? "tag")
                        .tag(CategoryFilter.category(category.id))
                }
                Label("Uncategorized", systemImage: "questionmark.circle").tag(CategoryFilter.uncategorized)
            }

            Divider()

            // Account filter section (ACCT-06/D-07; archived accounts excluded)
            Picker("Account", selection: $accountFilter) {
                Label("All Accounts", systemImage: "building.columns").tag(AccountFilter.all)
                Label("Unassigned", systemImage: "questionmark.circle").tag(AccountFilter.unassigned)
                ForEach(activeAccounts) { account in
                    Label(account.name ?? "Untitled", systemImage: account.symbolName ?? "creditcard")
                        .tag(AccountFilter.account(account.id))
                }
            }
        } label: {
            // Filled icon signals any active (non-"All") filter — category or account.
            Image(systemName: (categoryFilter == .all && accountFilter == .all)
                  ? "line.3.horizontal.decrease.circle"
                  : "line.3.horizontal.decrease.circle.fill")
        }
        .accessibilityLabel("Filter Expenses")
    }

    // MARK: - Derived data

    /// Expenses after applying the active category filter, preserving @Query date order.
    private var filteredExpenses: [Expense] {
        // 1. Category filter (existing)
        let categoryFiltered: [Expense]
        switch categoryFilter {
        case .all:
            categoryFiltered = expenses
        case .uncategorized:
            categoryFiltered = expenses.filter { $0.categories.isEmpty }
        case .category(let id):
            categoryFiltered = expenses.filter { expense in
                expense.categories.contains { $0.id == id }
            }
        }
        // 2. Account filter chained after category filter (ACCT-06/D-07)
        switch accountFilter {
        case .all:
            return categoryFiltered
        case .unassigned:
            return categoryFiltered.filter { $0.accountID == nil }
        case .account(let id):
            return categoryFiltered.filter { $0.accountID == id }
        }
    }

    /// Filtered expenses grouped into day sections, newest day first.
    private var daySections: [DaySection] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: filteredExpenses) { expense -> Date in
            calendar.startOfDay(for: expense.date)
        }
        return grouped.keys.sorted(by: >).map { dayStart in
            let items = grouped[dayStart] ?? []  // already date-descending from the @Query
            let total = items.reduce(Decimal(0)) { $0 + $1.amount }
            return DaySection(
                id: dayStart,
                title: dayStart.formattedAsRelativeDay(),
                total: total,
                expenses: items
            )
        }
    }

    /// Human-readable label for the active filter (used in the empty state).
    private var filterLabel: String {
        // Account filter takes precedence in the label if both are active
        if accountFilter != .all {
            switch accountFilter {
            case .all:
                break
            case .unassigned:
                return "unassigned expenses"
            case .account(let id):
                let name = activeAccounts.first { $0.id == id }?.name ?? "this account"
                return name
            }
        }
        switch categoryFilter {
        case .all:
            return "this filter"
        case .uncategorized:
            return "uncategorized"
        case .category(let id):
            return categories.first { $0.id == id }?.name ?? "this category"
        }
    }

    // MARK: - Actions

    /// Delete swiped rows from a specific month section.
    ///
    /// Offsets are relative to `sectionExpenses`, so we resolve them against that array
    /// (not the full `expenses` query) before deleting.
    private func deleteExpenses(in sectionExpenses: [Expense], at offsets: IndexSet) {
        for index in offsets {
            context.delete(sectionExpenses[index])
        }
        // CR-01: persist the delete explicitly — do not rely on implicit autosave.
        do {
            try context.save()
        } catch {
            // Surface the failure rather than swallowing it silently.
            assertionFailure("Failed to save after deleting expenses: \(error)")
            print("Failed to save after deleting expenses: \(error)")
        }
    }
}
