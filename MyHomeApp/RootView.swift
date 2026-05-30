import SwiftUI

/// Root TabView host (D2-10, D3-17).
///
/// Phase 3 tabs (3-tab bar, lean — D3-17):
/// 1. Expenses — ExpenseListView (owns its NavigationStack).
/// 2. Budgets — BudgetsView (owns its NavigationStack).
/// 3. Notes — NotesHomeView (segmented List|Calendar host; owns its NavigationStack).
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

            NotesHomeView()
                .tabItem {
                    Label("Notes", systemImage: "note.text")
                }
        }
    }
}
