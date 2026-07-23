import SwiftUI
import SwiftData

/// Tap-through view showing expenses for a single category in a single month (EXP-09).
///
/// Navigation: pushed onto BudgetsView's NavigationStack when a category card is tapped.
/// The category parameter is required; this view has no add/onDelete, but Phase 23 (EDIT-01)
/// wires each row to the SAME existing edit sheet the Activity list uses — parity across every
/// place an expense row appears (saved edits reflect everywhere via the shared SwiftData model).
///
/// Query strategy (RESEARCH Open Question 1 / A3):
/// The init-time #Predicate uses a date-range filter only. Category membership is verified
/// in-memory via expense.categories.contains(where:) to avoid the known relationship-contains
/// predicate fragility in early SwiftData versions.
struct FilteredExpenseListView: View {

    let category: Category
    let start: Date
    let end: Date

    @Query private var monthExpenses: [Expense]

    /// Phase 23 (EDIT-01): drives the shared EditExpenseView sheet, same pattern as
    /// ExpenseListView.editingExpense.
    @State private var editingExpense: Expense?

    init(category: Category, start: Date, end: Date) {
        self.category = category
        self.start = start
        self.end = end

        let lo = start
        let hi = end
        // Date-only predicate — safe and not fragile (RESEARCH OQ1/A3 in-memory fallback)
        _monthExpenses = Query(
            filter: #Predicate<Expense> { expense in
                expense.date >= lo && expense.date <= hi
            },
            sort: \.date, order: .reverse
        )
    }

    // MARK: - Filtered expenses for this category (in-memory)

    private var expenses: [Expense] {
        let catID = category.persistentModelID
        return monthExpenses.filter {
            $0.categories.contains(where: { $0.persistentModelID == catID })
        }
    }

    private var monthLabel: String {
        start.formattedAsMonthYear()
    }

    var body: some View {
        Group {
            if expenses.isEmpty {
                ContentUnavailableView(
                    "No Expenses",
                    systemImage: "tray",
                    description: Text("No expenses in \(category.name ?? "this category") for \(monthLabel).")
                )
            } else {
                List {
                    ForEach(expenses) { expense in
                        Button {
                            editingExpense = expense
                        } label: {
                            ExpenseRow(expense: expense)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .listRowBackground(DesignTokens.surfaceRaised)
                    }
                }
                .listStyle(.insetGrouped)
                .scrollContentBackground(.hidden)
                .background(DesignTokens.bgCanvas)
            }
        }
        .navigationTitle(category.name ?? "Uncategorized")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $editingExpense) { expense in
            EditExpenseView(expense: expense)
        }
    }
}

/// Tap-through view showing uncategorized expenses for a single month.
///
/// Separate struct used for the "Uncategorized" row tap-through in BudgetsView,
/// since `FilteredExpenseListView` requires a `Category` instance. Phase 23 (EDIT-01):
/// rows open the same shared edit sheet as everywhere else.
struct UncategorizedExpenseListView: View {

    let start: Date
    let end: Date

    @Query private var monthExpenses: [Expense]

    /// Phase 23 (EDIT-01): drives the shared EditExpenseView sheet.
    @State private var editingExpense: Expense?

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

    private var expenses: [Expense] {
        monthExpenses.filter { $0.categories.isEmpty }
    }

    private var monthLabel: String {
        start.formattedAsMonthYear()
    }

    var body: some View {
        Group {
            if expenses.isEmpty {
                ContentUnavailableView(
                    "No Expenses",
                    systemImage: "tray",
                    description: Text("No uncategorized expenses for \(monthLabel).")
                )
            } else {
                List {
                    ForEach(expenses) { expense in
                        Button {
                            editingExpense = expense
                        } label: {
                            ExpenseRow(expense: expense)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .listRowBackground(DesignTokens.surfaceRaised)
                    }
                }
                .listStyle(.insetGrouped)
                .scrollContentBackground(.hidden)
                .background(DesignTokens.bgCanvas)
            }
        }
        .navigationTitle("Uncategorized")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $editingExpense) { expense in
            EditExpenseView(expense: expense)
        }
    }
}
