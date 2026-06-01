import SwiftUI

/// Root TabView host (D2-10, D3-17, D4-01).
///
/// Phase 4 tabs (4-tab bar — D4-01):
/// 0. Home — OverviewView (dashboard, default launch tab).      tag: 0
/// 1. Expenses — ExpenseListView (owns its NavigationStack).    tag: 1
/// 2. Budgets — BudgetsView (owns its NavigationStack).         tag: 2
/// 3. Notes — NotesHomeView (segmented List|Calendar host).     tag: 3
///
/// The `selectedTab` binding allows programmatic tab switching, e.g. on a
/// notification deep-link (kOpenNoteNotification → switch to Notes tab, open note).
///
/// No shared NavigationPath — each tab owns its navigation independently.
struct RootView: View {

    @State private var selectedTab: Int = 0
    @State private var deepLinkNoteID: UUID? = nil
    /// CR-03: Thread blockID deep-link through the view hierarchy so EditNoteView can
    /// scroll to and highlight the target block row when a block-level reminder is tapped.
    @State private var deepLinkBlockID: UUID? = nil

    var body: some View {
        TabView(selection: $selectedTab) {
            OverviewView(selectedTab: $selectedTab, deepLinkNoteID: $deepLinkNoteID)
                .tabItem {
                    Label("Home", systemImage: "house")
                }
                .tag(0)

            ExpenseListView()
                .tabItem {
                    Label("Expenses", systemImage: "list.bullet")
                }
                .tag(1)

            BudgetsView()
                .tabItem {
                    Label("Budgets", systemImage: "chart.bar")
                }
                .tag(2)

            NotesHomeView(deepLinkNoteID: $deepLinkNoteID, deepLinkBlockID: $deepLinkBlockID)
                .tabItem {
                    Label("Notes", systemImage: "note.text")
                }
                .tag(3)
        }
        // Deep-link observer: notification banner tap → switch to Notes tab + open note
        .onReceive(NotificationCenter.default.publisher(for: kOpenNoteNotification)) { notification in
            if let noteID = notification.userInfo?["noteID"] as? UUID {
                deepLinkNoteID = noteID
                // CR-03: forward block target when present
                deepLinkBlockID = notification.userInfo?["blockID"] as? UUID
                selectedTab = 3
            }
        }
    }
}
