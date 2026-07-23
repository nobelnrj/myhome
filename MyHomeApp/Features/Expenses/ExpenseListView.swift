import SwiftUI
import SwiftData

/// Root expense list view.
///
/// Layout (neumorphic v2, handoff expenses.jsx):
/// - NavigationStack, navigationTitle "Activity" large
/// - "Needs Review" card at the top for ingested expenses needing triage (D7-04)
/// - Main expenses grouped into one raised card per day (header = "TODAY · WED, 9 JUL"
///   + signed net total), newest day first; rows within a day stay date-descending.
/// - Toolbar filter menu to scope the list by category / account / transfers.
/// - Each row: ExpenseRow button → edit sheet; delete via context menu (and EditExpenseView)
/// - Toolbar: "+" menu (New Expense / New Transfer)
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

    /// Pending transfer debit legs: transferPairID set + amount > 0 + isTransfer still nil (D-07).
    ///
    /// STAB-08-safe: predicate uses UUID? and Decimal comparisons — NOT Bool? (#Predicate on
    /// optional Bool is unreliable in SwiftData; the nil-check is done in-view instead — A2).
    /// The `isTransfer == nil` guard is applied defensively in the ForEach, not in the @Query.
    @Query(
        filter: #Predicate<Expense> { $0.transferPairID != nil && $0.amount > 0 },
        sort: \Expense.date,
        order: .reverse
    ) private var pendingDebitLegs: [Expense]

    @Environment(\.modelContext) private var context

    @State private var showingAddSheet: Bool = false
    @State private var showingAddTransferSheet: Bool = false
    @State private var editingExpense: Expense? = nil

    /// Active category filter for the main list. Defaults to showing everything.
    @State private var activeCategoryFilter: CategoryFilter = .all

    /// Active account filter for the main list. Defaults to showing all accounts (ACCT-06/D-07).
    @State private var accountFilter: AccountFilter = .all

    /// Active transfer filter — .normal hides confirmed transfers; .transfers shows only them (D-12).
    @State private var transferFilter: TransferFilter = .normal

    /// Active accounts for the account filter menu (archived excluded — D-08).
    @Query(filter: #Predicate<Account> { !$0.isArchived }, sort: \Account.sortOrder)
    private var activeAccounts: [Account]

    /// Bound to RootView so it can drive the Expenses tab badge (D7-04).
    @Binding var reviewBadgeCount: Int
    /// OVR-06: Optional deep-link category filter from Overview donut tap.
    /// When non-nil on appear, sets the internal activeCategoryFilter to .category(uuid) and clears the binding.
    /// Renamed to deepLinkCategoryFilter to avoid collision with internal activeCategoryFilter @State.
    @Binding var deepLinkCategoryFilter: UUID?

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

    /// Transfer visibility filter (D-12).
    ///
    /// - `.normal`: default view — excludes confirmed transfers (isTransfer == true) from main list.
    /// - `.transfers`: shows ONLY confirmed transfers.
    private enum TransferFilter: Hashable {
        case normal
        case transfers
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
                if expenses.isEmpty && reviewItems.isEmpty && pendingDebitLegs.isEmpty {
                    ContentUnavailableView(
                        "No Expenses Yet",
                        systemImage: "tray",
                        description: Text("Tap + to record your first expense.")
                    )
                } else {
                    // Neumorphic v2: one raised card per day group (handoff expenses.jsx) —
                    // ScrollView + LazyVStack instead of List so cards carry the dual outer
                    // shadow. Row triage that used to live on swipeActions is now inline
                    // buttons (ReviewInboxRow / TransferPairRow) and a context-menu delete.
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: DesignTokens.spacing22) {
                            // "Needs Review" section — shown above the main expense list (D7-04)
                            if !reviewItems.isEmpty {
                                sectionCard(header: sectionHeader("Needs Review")) {
                                    ForEach(reviewItems) { expense in
                                        ReviewInboxRow(expense: expense)
                                            .padding(.horizontal, 16)
                                            .padding(.vertical, 8)
                                            .contentShape(Rectangle())
                                            .onTapGesture {
                                                editingExpense = expense
                                            }
                                        if expense.id != reviewItems.last?.id {
                                            rowDivider
                                        }
                                    }
                                }
                            }

                            // "Possible Transfers" section — pending scorer-detected pairs (D-11, XFER-02)
                            if !pendingPairs.isEmpty {
                                sectionCard(header: sectionHeader("Possible Transfers")) {
                                    ForEach(pendingPairs, id: \.debit.id) { pair in
                                        TransferPairRow(debit: pair.debit, credit: pair.credit)
                                            .padding(.horizontal, 16)
                                            .padding(.vertical, 8)
                                        if pair.debit.id != pendingPairs.last?.debit.id {
                                            rowDivider
                                        }
                                    }
                                }
                            }

                            // Main list — grouped into day-group cards (filtered by category).
                            if daySections.isEmpty {
                                ContentUnavailableView(
                                    "No Matching Expenses",
                                    systemImage: "line.3.horizontal.decrease.circle",
                                    description: Text("No expenses for \(filterLabel).")
                                )
                                .frame(maxWidth: .infinity)
                                .padding(.top, 40)
                            } else {
                                ForEach(daySections) { section in
                                    sectionCard(header: dayHeader(for: section)) {
                                        ForEach(section.expenses) { expense in
                                            Button {
                                                editingExpense = expense
                                            } label: {
                                                ExpenseRow(expense: expense)
                                                    .padding(.horizontal, 16)
                                                    .padding(.vertical, 3)
                                                    .contentShape(Rectangle())
                                            }
                                            .buttonStyle(.plain)
                                            .contextMenu {
                                                Button(role: .destructive) {
                                                    deleteExpense(expense)
                                                } label: {
                                                    Label("Delete Expense", systemImage: "trash")
                                                }
                                            }
                                            if expense.id != section.expenses.last?.id {
                                                rowDivider
                                            }
                                        }
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 4)
                        .padding(.bottom, 24)
                    }
                    .background(DesignTokens.bgCanvas)
                    .floatingBarClearance()
                }
            }
            .navigationTitle("Activity")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                if !expenses.isEmpty {
                    ToolbarItem(placement: .topBarLeading) {
                        filterMenu
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button {
                            showingAddSheet = true
                        } label: {
                            Label("New Expense", systemImage: "creditcard")
                        }
                        Button {
                            showingAddTransferSheet = true
                        } label: {
                            Label("New Transfer", systemImage: "arrow.left.arrow.right")
                        }
                    } label: {
                        Image(systemName: "plus")
                    }
                    .tint(DesignTokens.accentText)
                    .accessibilityLabel("Add")
                }
            }
            .sheet(isPresented: $showingAddSheet) {
                AddExpenseView()
            }
            .sheet(isPresented: $showingAddTransferSheet) {
                AddTransferView()
            }
            .sheet(item: $editingExpense) { expense in
                EditExpenseView(expense: expense)
            }
        }
        // Keep the badge count in sync with what the UI actually renders as actionable (D7-04, XFER-03).
        // We observe the derived `actionableBadgeCount` directly: confirming a transfer flips
        // `isTransfer` (not the raw @Query counts), so watching counts alone would miss it and leave
        // the badge stuck. `actionableBadgeCount` recomputes on every dependency change.
        .onChange(of: actionableBadgeCount) { _, newCount in
            reviewBadgeCount = newCount
        }
        // OVR-06: respond to category filter taps from Overview donut when already on the Activity tab
        .onChange(of: deepLinkCategoryFilter) { _, uuid in
            guard let uuid else { return }
            deepLinkCategoryFilter = nil   // consume and clear
            activeCategoryFilter = CategoryFilter.category(uuid)
        }
        .onAppear {
            reviewBadgeCount = actionableBadgeCount
            // OVR-06: consume incoming deep-link category filter from Overview donut tap
            if let uuid = deepLinkCategoryFilter {
                deepLinkCategoryFilter = nil   // consume and clear the binding
                activeCategoryFilter = CategoryFilter.category(uuid)
            }
        }
    }

    // MARK: - Section card builders (neumorphic v2)

    /// A day-group / inbox section: header row above one raised card of rows
    /// (handoff expenses.jsx — 13pt uppercase header, radius-26 card, dual shadow).
    private func sectionCard(header: some View, @ViewBuilder rows: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            header
                .padding(.horizontal, 16)
            VStack(spacing: 0) {
                rows()
            }
            .padding(.vertical, 6)
            .neuSurface(.raised, padding: nil)
        }
    }

    /// Uppercase micro-header for the inbox sections ("NEEDS REVIEW", "POSSIBLE TRANSFERS").
    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 13))
            .kerning(0.3)
            .textCase(.uppercase)
            .foregroundStyle(DesignTokens.label2)
    }

    /// v2 day header: uppercase day + signed net total. Spends are stored positive,
    /// so total > 0 = net spend day ("−₹X", dim) and total < 0 = net income day
    /// ("+₹X", green) — see AccountBalance sign convention.
    private func dayHeader(for section: DaySection) -> some View {
        HStack {
            Text(section.title)
                .font(.system(size: 13))
                .kerning(0.3)
                .textCase(.uppercase)
                .foregroundStyle(DesignTokens.label2)
            Spacer()
            Text(signedDayTotal(section.total))
                .font(.system(size: 13, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(section.total < 0 ? DesignTokens.positive : DesignTokens.label3)
        }
    }

    /// Hairline row separator inset past the 36pt icon tile (16 + 36 + 12 spacing = 64).
    private var rowDivider: some View {
        Rectangle()
            .fill(DesignTokens.separatorHairline)
            .frame(height: 0.5)
            .padding(.leading, 64)
    }

    // MARK: - Filter menu

    private var filterMenu: some View {
        Menu {
            // Category filter section
            Picker("Category", selection: $activeCategoryFilter) {
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

            Divider()

            // Transfer filter section (D-12)
            Picker("Transfers", selection: $transferFilter) {
                Label("Normal Expenses", systemImage: "dollarsign.circle")
                    .tag(TransferFilter.normal)
                Label("Transfers", systemImage: "arrow.left.arrow.right")
                    .tag(TransferFilter.transfers)
            }
        } label: {
            // Filled icon signals any active (non-default) filter — category, account, or transfer.
            Image(systemName: (activeCategoryFilter == .all && accountFilter == .all && transferFilter == .normal)
                  ? "line.3.horizontal.decrease.circle"
                  : "line.3.horizontal.decrease.circle.fill")
        }
        .accessibilityLabel("Filter Expenses")
    }

    // MARK: - Derived data

    /// Actionable pending transfer pairs — the source of truth for BOTH the "Possible Transfers"
    /// section AND the tab badge count (XFER-03).
    ///
    /// `pendingDebitLegs` (the @Query) is deliberately broad — it matches `transferPairID != nil
    /// && amount > 0` and does NOT filter on `isTransfer` (#Predicate on optional Bool is unreliable
    /// in SwiftData — see the @Query note above). After a pair is *confirmed*, `confirmPair()` sets
    /// `isTransfer = true` but keeps `transferPairID` intact (D-16 balance-move relies on the link),
    /// so the confirmed leg stays in `pendingDebitLegs`.
    ///
    /// We therefore narrow to genuinely-actionable pairs here: both legs still pending
    /// (`isTransfer == nil`) and the credit leg still present. Basing the badge on this (rather than
    /// the raw `pendingDebitLegs.count`) prevents a stuck badge with no row to act on.
    private var pendingPairs: [(debit: Expense, credit: Expense)] {
        pendingDebitLegs.compactMap { debit in
            guard debit.isTransfer == nil,
                  let pairID = debit.transferPairID,
                  let credit = expenses.first(where: { $0.id == pairID }),
                  credit.isTransfer == nil
            else { return nil }
            return (debit: debit, credit: credit)
        }
    }

    /// The number the Expenses tab badge should show — review inbox items plus actionable
    /// transfer pairs. Mirrors exactly what the UI renders as needing action (XFER-03).
    private var actionableBadgeCount: Int {
        reviewItems.count + pendingPairs.count
    }

    /// Expenses after applying the active category filter, preserving @Query date order.
    private var filteredExpenses: [Expense] {
        // 1. Category filter (existing)
        let categoryFiltered: [Expense]
        switch activeCategoryFilter {
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
        let accountFiltered: [Expense]
        switch accountFilter {
        case .all:
            accountFiltered = categoryFiltered
        case .unassigned:
            accountFiltered = categoryFiltered.filter { $0.accountID == nil }
        case .account(let id):
            accountFiltered = categoryFiltered.filter { $0.accountID == id }
        }
        // 3. Transfer filter chained after account filter (D-12).
        //    .normal: default — excludes confirmed transfers so they don't pollute spend totals.
        //    .transfers: shows ONLY confirmed transfers (both legs).
        switch transferFilter {
        case .normal:
            return accountFiltered.filter { $0.isTransfer != true }
        case .transfers:
            return accountFiltered.filter { $0.isTransfer == true }
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
                title: dayHeaderTitle(for: dayStart),
                total: total,
                expenses: items
            )
        }
    }

    /// v2 day header: "Today · Wed, 9 Jul" / "Yesterday · Tue, 8 Jul" / "Sat, 4 Jul".
    /// (Rendered uppercase by the header's .textCase.)
    private func dayHeaderTitle(for dayStart: Date) -> String {
        let cal = Calendar.current
        let relative = dayStart.formattedAsRelativeDay()
        if cal.isDateInToday(dayStart) || cal.isDateInYesterday(dayStart) {
            let formatter = DateFormatter()
            formatter.locale = .current
            formatter.timeZone = .current
            formatter.setLocalizedDateFormatFromTemplate("EEEdMMM")
            return "\(relative) · \(formatter.string(from: dayStart))"
        }
        return relative
    }

    /// Signed net figure for a day header. Spends are stored positive (see AccountBalance
    /// sign convention), so a positive total is money OUT ("−₹X") and a negative total is
    /// money IN ("+₹X").
    private func signedDayTotal(_ total: Decimal) -> String {
        if total > 0 { return "−\(total.formattedINRWhole())" }
        if total < 0 { return "+\(abs(total).formattedINRWhole())" }
        return total.formattedINRWhole()
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
        switch activeCategoryFilter {
        case .all:
            return "this filter"
        case .uncategorized:
            return "uncategorized"
        case .category(let id):
            return categories.first { $0.id == id }?.name ?? "this category"
        }
    }

    // MARK: - Actions

    /// Delete a single expense (context-menu action; EditExpenseView also offers Delete).
    private func deleteExpense(_ expense: Expense) {
        context.deleteSynced(expense, kind: .expense)
        // CR-01: persist the delete explicitly — do not rely on implicit autosave.
        do {
            try context.save()
        } catch {
            // Surface the failure rather than swallowing it silently.
            assertionFailure("Failed to save after deleting expense: \(error)")
            print("Failed to save after deleting expense: \(error)")
        }
    }
}
