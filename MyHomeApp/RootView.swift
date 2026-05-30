import SwiftUI

/// Root TabView host (D2-10, D3-17).
///
/// Phase 3 tabs (3-tab bar, lean — D3-17):
/// 1. Expenses — ExpenseListView (owns its NavigationStack).  tag: 0
/// 2. Budgets — BudgetsView (owns its NavigationStack).        tag: 1
/// 3. Notes — NotesHomeView (segmented List|Calendar host).    tag: 2
///
/// The `selectedTab` binding allows programmatic tab switching, e.g. on a
/// notification deep-link (kOpenNoteNotification → switch to Notes tab, open note).
///
/// Future tabs (Overview Phase 4, Settings Phase 5) slot in here.
/// No shared NavigationPath — each tab owns its navigation independently.
struct RootView: View {

    @State private var selectedTab: Int = 0
    @State private var deepLinkNoteID: UUID? = nil

    var body: some View {
        TabView(selection: $selectedTab) {
            ExpenseListView()
                .tabItem {
                    Label("Expenses", systemImage: "list.bullet")
                }
                .tag(0)

            BudgetsView()
                .tabItem {
                    Label("Budgets", systemImage: "chart.bar")
                }
                .tag(1)

            NotesHomeView(deepLinkNoteID: $deepLinkNoteID)
                .tabItem {
                    Label("Notes", systemImage: "note.text")
                }
                .tag(2)
        }
        // Deep-link observer: notification banner tap → switch to Notes tab + open note
        .onReceive(NotificationCenter.default.publisher(for: kOpenNoteNotification)) { notification in
            if let noteID = notification.userInfo?["noteID"] as? UUID {
                deepLinkNoteID = noteID
                selectedTab = 2
            }
        }
    }
}
