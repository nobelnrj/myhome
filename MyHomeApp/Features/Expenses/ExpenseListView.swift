import SwiftUI
import SwiftData

/// Root expense list view.
///
/// Layout (UI-SPEC Screen 1):
/// - NavigationStack, navigationTitle "Expenses" inline
/// - List insetGrouped of @Query(sort by date, order .reverse) expenses
/// - Each row: ExpenseRow with onTapGesture → edit sheet
/// - .onDelete: swipe-to-delete via modelContext.delete
/// - Toolbar: "+" (SF Symbol plus, accent, accessibilityLabel "Add Expense")
/// - Empty state: ContentUnavailableView "No Expenses Yet"
///
/// Reads via @Query (RESEARCH Pattern 4). Writes via modelContext (no repository wrapper).
/// Pitfall 5: @Observable/@State/@Bindable only — no @StateObject/@ObservedObject/@Published.
struct ExpenseListView: View {

    @Query(sort: \Expense.date, order: .reverse) private var expenses: [Expense]
    @Environment(\.modelContext) private var context

    @State private var showingAddSheet: Bool = false
    @State private var editingExpense: Expense? = nil

    var body: some View {
        NavigationStack {
            Group {
                if expenses.isEmpty {
                    ContentUnavailableView(
                        "No Expenses Yet",
                        systemImage: "tray",
                        description: Text("Tap + to record your first expense.")
                    )
                } else {
                    List {
                        ForEach(expenses) { expense in
                            ExpenseRow(expense: expense)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    editingExpense = expense
                                }
                        }
                        .onDelete(perform: deleteExpenses)
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("Expenses")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
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
    }

    // MARK: - Actions

    private func deleteExpenses(at offsets: IndexSet) {
        for index in offsets {
            context.delete(expenses[index])
        }
    }
}
