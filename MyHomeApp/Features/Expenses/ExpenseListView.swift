import SwiftUI
import SwiftData

/// Root expense list view.
///
/// Layout (UI-SPEC Screen 1):
/// - NavigationStack, navigationTitle "Expenses" inline
/// - "Needs Review" section at the top for ingested expenses needing triage (D7-04)
/// - List insetGrouped of @Query(sort by date, order .reverse) expenses
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

    /// Bound to RootView so it can drive the Expenses tab badge (D7-04).
    @Binding var reviewBadgeCount: Int

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

                        // Main expense list (all expenses including autoSaved)
                        if !expenses.isEmpty {
                            Section {
                                ForEach(expenses) { expense in
                                    ExpenseRow(expense: expense)
                                        .contentShape(Rectangle())
                                        .onTapGesture {
                                            editingExpense = expense
                                        }
                                }
                                .onDelete(perform: deleteExpenses)
                            }
                        }
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
        // Keep the badge count in sync whenever reviewItems changes (D7-04)
        .onChange(of: reviewItems.count) { _, newCount in
            reviewBadgeCount = newCount
        }
        .onAppear {
            reviewBadgeCount = reviewItems.count
        }
    }

    // MARK: - Actions

    private func deleteExpenses(at offsets: IndexSet) {
        for index in offsets {
            context.delete(expenses[index])
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
