import SwiftUI

/// Root TabView host (D2-10).
///
/// Phase 2 tabs:
/// 1. Expenses — existing ExpenseListView (owns its NavigationStack).
/// 2. Budgets — new BudgetsView (owns its NavigationStack).
///
/// Future tabs (Overview Phase 4, Settings Phase 5) slot in here.
/// No shared NavigationPath — each tab owns its navigation independently.
struct RootView: View {
    var body: some View {
        TabView {
            ExpenseListView()
                .tabItem {
                    Label("Expenses", systemImage: "list.bullet")
                }

            BudgetsView()
                .tabItem {
                    Label("Budgets", systemImage: "chart.bar")
                }
        }
    }
}
